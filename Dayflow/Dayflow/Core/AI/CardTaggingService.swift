//
//  CardTaggingService.swift
//  Dayflow
//
//  TAKT: Text-only classification pass that suggests client/project tags for
//  timeline cards using the configured OpenAI-compatible endpoint (Nous Portal
//  in the MVP). Uses client/project short descriptions as recognition context
//  and previously corrected cards as few-shot examples.
//

import Foundation

struct CardTaggingService {

  static let shared = CardTaggingService()

  // MARK: - Errors

  enum TaggingError: LocalizedError {
    case notConfigured
    case noClients
    case emptyResponse
    case invalidJSON(String)

    var errorDescription: String? {
      switch self {
      case .notConfigured:
        return
          "Kein KI-Anbieter konfiguriert. Richte unter Einstellungen → Anbieter einen "
          + "OpenAI-kompatiblen Endpoint (z. B. Nous Portal) ein."
      case .noClients:
        return "Lege zuerst mindestens einen Kunden mit Beschreibung an."
      case .emptyResponse:
        return "Der KI-Anbieter hat eine leere Antwort geliefert. Bitte erneut versuchen."
      case .invalidJSON(let detail):
        return "Die KI-Antwort konnte nicht gelesen werden (\(detail))."
      }
    }
  }

  // MARK: - Types

  struct TaggingOutcome {
    let taggedCount: Int
    let skippedCount: Int
  }

  /// Cards that can be offered to the automatic tagging pass.
  ///
  /// System and idle cards are intentionally not customer work. A card that
  /// has already been tagged must not be overwritten, including manual tags.
  /// `skip`/`duplicate` are terminal classifications produced by the tagging
  /// pipeline and therefore must not reappear as open work.
  static func taggingCandidates(from cards: [TimelineCard]) -> [TimelineCard] {
    cards.filter { card in
      guard card.recordId != nil, card.clientId == nil else { return false }

      let category = card.category.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard category != "system", category != "idle" else { return false }

      let source = card.tagSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard source != "manual", source != "corrected",
        source != "skip", source != "duplicate", source != "duplikat"
      else {
        return false
      }
      return true
    }
  }

  private struct TagPayload: Codable {
    let card_id: Int64
    let client_id: Int64?
    let project_id: Int64?
    let task: String?
    let billable: Bool?
    let confidence: Double?
  }

  private struct ChatMessage: Codable {
    let role: String
    let content: String
  }

  private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
  }

  private struct ChatResponse: Codable {
    struct Choice: Codable {
      struct Message: Codable {
        let content: String?
      }
      let message: Message
    }
    let choices: [Choice]
  }

  // MARK: - Configuration

  /// True when an OpenAI-compatible provider is configured (base URL + model + key).
  var isConfigured: Bool {
    guard let config = OpenAICompatiblePreferences.load(), config.isComplete else {
      return false
    }
    let key = KeychainManager.shared.retrieve(for: OpenAICompatiblePreferences.keychainProvider)
    return !(key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  // MARK: - Main entry point

  /// Classifies the given cards in a single text pass and persists AI tags.
  func tagCards(_ cards: [TimelineCard]) async throws -> TaggingOutcome {
    let candidates = Self.taggingCandidates(from: cards)
    guard !candidates.isEmpty else {
      return TaggingOutcome(taggedCount: 0, skippedCount: 0)
    }
    guard let config = OpenAICompatiblePreferences.load(), config.isComplete, isConfigured else {
      throw TaggingError.notConfigured
    }

    let clients = StorageManager.shared.fetchClients()
    let projects = StorageManager.shared.fetchProjects()
    guard !clients.isEmpty else {
      throw TaggingError.noClients
    }

    let prompt = buildPrompt(cards: candidates, clients: clients, projects: projects)
    let text = try await sendChatCompletion(config: config, prompt: prompt)
    let payloads = try parsePayloads(text)

    let clientIds = Set(clients.compactMap(\.id))
    var projectsByClient: [Int64: Set<Int64>] = [:]
    for project in projects {
      guard let pid = project.id, let cid = project.clientId else { continue }
      projectsByClient[cid, default: []].insert(pid)
    }

    var tagged = 0
    for payload in payloads {
      guard let card = candidates.first(where: { $0.recordId == payload.card_id }),
        let cardId = card.recordId
      else { continue }

      // Validate against the controlled vocabulary; drop invalid references.
      var clientId = payload.client_id
      if let cid = clientId, !clientIds.contains(cid) {
        clientId = nil
      }
      var projectId = payload.project_id
      if let pid = projectId,
        let cid = clientId,
        !(projectsByClient[cid]?.contains(pid) ?? false)
      {
        projectId = nil
      }
      if let pid = projectId, clientId == nil {
        projectId = nil
      }

      let rawTask = payload.task?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let confidence = min(max(payload.confidence ?? 0.5, 0), 1)

      StorageManager.shared.updateTimelineCardTagging(
        cardId: cardId,
        clientId: clientId,
        projectId: projectId,
        task: rawTask.isEmpty ? nil : rawTask,
        billable: payload.billable,
        tagSource: "ai",
        tagConfidence: confidence
      )
      tagged += 1
    }

    return TaggingOutcome(taggedCount: tagged, skippedCount: candidates.count - tagged)
  }

  // MARK: - Prompt building

  private func buildPrompt(
    cards: [TimelineCard], clients: [Client], projects: [Project]
  ) -> String {
    var system = """
      Du bist ein Assistent für automatische Zeiterfassung. Ordne jede Aktivität einem
      Kunden und Projekt aus der folgenden Liste zu. Antworte AUSSCHLIESSLICH mit einem
      JSON-Array, kein Markdown, keine Erklärungen.

      Format je Eintrag:
      {"card_id": <id>, "client_id": <id|null>, "project_id": <id|null>, "task": "<kurze Aufgabe|null>", "billable": true|false, "confidence": 0.0-1.0}

      Regeln:
      - Nutze NUR Kunden- und Projekt-IDs aus der Liste. Unbekannte Zuordnung: client_id=null.
      - project_id muss zum gewählten client_id gehören, sonst null.
      - Lege als billable genau dann true fest, wenn die Aktivität offensichtlich abrechenbare
        Arbeit für den Kunden ist (Coaching, Beratung, Projekterstellung). Verwaltung, Planung
        der eigenen Firma oder Privates sind false.
      - confidence: wie sicher du bist (0.0 unsicher – 1.0 sehr sicher).

      """

    // Clients + projects as controlled vocabulary
    system += "\nKunden:\n"
    for client in clients {
      let detail = (client.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let name = client.name
      system += detail.isEmpty
        ? "- [ID=\(client.id ?? -1)] \(name)\n"
        : "- [ID=\(client.id ?? -1)] \(name) — \(detail)\n"
    }
    system += "\nProjekte:\n"
    for project in projects {
      let detail = (project.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      system +=
        "- [ID=\(project.id ?? -1), Kunde=\(project.clientId ?? -1)] \(project.name)"
        + (detail.isEmpty ? "" : " — \(detail)") + "\n"
    }

    // Few-shot examples from user-corrected cards (max 3, most recent first)
    let examples = StorageManager.shared.fetchTaggedExamples(limit: 3)
    if !examples.isEmpty {
      system += "\nBeispiele aus deinen Korrekturen:\n"
      for ex in examples {
        system +=
          "- Titel: \"\(ex.title)\" → Kunde=\(ex.clientId ?? -1), "
          + "Projekt=\(ex.projectId ?? -1)\(ex.task.map { ", Aufgabe=\($0)" } ?? "")\n"
      }
    }

    // Cards to classify
    var user = "Klassifiziere diese Aktivitäten:\n[\n"
    for card in cards {
      guard let cardId = card.recordId else { continue }
      let summary = (card.summary.isEmpty ? card.detailedSummary : card.summary)
        .replacingOccurrences(of: "\"", with: "'")
        .replacingOccurrences(of: "\n", with: " ")
      user +=
        "  {\"card_id\": \(cardId), \"zeit\": \"\(card.startTimestamp)–\(card.endTimestamp)\", "
        + "\"titel\": \"\(card.title.replacingOccurrences(of: "\"", with: "'"))\", "
        + "\"zusammenfassung\": \"\(summary.prefix(300))\", "
        + "\"kategorie\": \"\(card.category)\"},\n"
    }
    user += "]\n"
    return system + "\n\n" + user
  }

  // MARK: - Networking

  private func sendChatCompletion(
    config: OpenAICompatibleConfiguration, prompt: String
  ) async throws -> String {
    guard let url = config.chatCompletionsURL else {
      throw TaggingError.notConfigured
    }

    let key = KeychainManager.shared.retrieve(for: OpenAICompatiblePreferences.keychainProvider)
    let requestBody = ChatRequest(
      model: config.modelID,
      messages: [
        ChatMessage(role: "system", content: prompt),
      ],
      temperature: 0.0,
      max_tokens: 4096
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Nous Portal sits behind Cloudflare bot protection: requests without a
    // browser-like User-Agent are rejected with HTTP 403 (Cloudflare 1010).
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      forHTTPHeaderField: "User-Agent")
    if let key, !key.isEmpty {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONEncoder().encode(requestBody)
    request.timeoutInterval = 120

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "CardTaggingService", code: http.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "KI-Anbieter antwortete mit HTTP \(http.statusCode). \(body.prefix(200))"
        ])
    }

    let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
    guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
      throw TaggingError.emptyResponse
    }
    return content
  }

  // MARK: - Parsing

  /// Extracts the JSON array from the model output, tolerating ``` fences.
  private func parsePayloads(_ text: String) throws -> [TagPayload] {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("```") {
      let lines = trimmed.components(separatedBy: "\n")
      let body = lines.dropFirst().dropLast().joined(separator: "\n")
      trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let data = trimmed.data(using: .utf8) else {
      throw TaggingError.invalidJSON("encoding")
    }
    do {
      return try JSONDecoder().decode([TagPayload].self, from: data)
    } catch {
      // Some models wrap the array in an object: {"cards": [...]}
      if let wrapped = try? JSONDecoder().decode([String: [TagPayload]].self, from: data),
        let cards = wrapped["cards"]
      {
        return cards
      }
      throw TaggingError.invalidJSON(error.localizedDescription)
    }
  }
}
