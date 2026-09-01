//
//  OpenAICompatibleChatProvider.swift
//  Dayflow
//
//  TAKT: OpenAI-kompatibler Chat-Provider (z. B. Nous Portal, OpenRouter).
//  Der Dashboard-Chat laeuft ueber den Standard-LLM-Anbieter aus den
//  Einstellungen — dieselbe Tool-Loop (fetchTimeline/fetchObservations)
//  wie der Gemini-Chat, aber ueber das OpenAI chat/completions-Format.
//

import Foundation

struct OpenAICompatibleChatProvider {
  let endpoint: String
  let modelID: String
  let bearerToken: String?
  let analyticsProvider: String

  static let maxToolRounds = 20

  /// Host fuer die Dashboard-Tool-Ausfuehrung (fetchTimeline/fetchObservations).
  /// Die Tool-Logik haengt historisch als Extension an GeminiDirectProvider,
  /// ist aber vollstaendig unabhaengig von der Gemini-API (nur StorageManager
  /// + Formatierer). Eine Instanz mit Dummy-Key wird nie fuer API-Calls genutzt.
  private let toolExecutor: GeminiDirectProvider

  init(
    endpoint: String,
    modelID: String,
    bearerToken: String?,
    analyticsProvider: String = OpenAICompatiblePreferences.keychainProvider
  ) {
    self.endpoint = endpoint
    self.modelID = modelID
    self.bearerToken = bearerToken
    self.analyticsProvider = analyticsProvider
    self.toolExecutor = GeminiDirectProvider(apiKey: "dashboard-tool-executor")
  }

  /// Baut den Provider aus der gespeicherten OpenAI-kompatiblen Konfiguration
  /// (Base-URL, Modell) plus Keychain-Token. nil, wenn nicht konfiguriert.
  static func makeStandard() -> OpenAICompatibleChatProvider? {
    guard let configuration = OpenAICompatiblePreferences.load(), configuration.isComplete else {
      return nil
    }
    let apiKey = KeychainManager.shared.retrieve(
      for: OpenAICompatiblePreferences.keychainProvider)
    let runtime = OpenAICompatibleRuntimeConfiguration(
      configuration: configuration,
      bearerToken: apiKey)
    return OpenAICompatibleChatProvider(
      endpoint: runtime.endpoint,
      modelID: runtime.modelID,
      bearerToken: runtime.bearerToken,
      analyticsProvider: runtime.analyticsProvider)
  }

  // MARK: - Streaming Chat

  func generateDashboardChatStreaming(
    systemInstruction: String,
    history: [DashboardChatTurn]
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          try await runDashboardChatLoop(
            systemInstruction: systemInstruction,
            history: history,
            continuation: continuation)
          continuation.finish()
        } catch {
          continuation.yield(.error(error.localizedDescription))
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func runDashboardChatLoop(
    systemInstruction: String,
    history: [DashboardChatTurn],
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws {
    guard let url = LocalEndpointUtilities.chatCompletionsURL(baseURL: endpoint) else {
      throw chatError(
        "Ungültige Base-URL des LLM-Anbieters. Bitte unter »LLM-Anbieter« in den Einstellungen prüfen.")
    }

    var messages: [[String: Any]] = []
    let trimmedInstruction = systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedInstruction.isEmpty {
      messages.append(["role": "system", "content": trimmedInstruction])
    }
    for turn in history {
      let role = turn.role == .user ? "user" : "assistant"
      messages.append(["role": role, "content": turn.content])
    }

    var toolRounds = 0
    while toolRounds < Self.maxToolRounds {
      let result = try await streamChatTurn(url: url, messages: messages)

      if result.toolCalls.isEmpty {
        continuation.yield(.complete(text: result.text))
        return
      }

      toolRounds += 1

      var assistantMessage: [String: Any] = [
        "role": "assistant",
        "content": result.text.isEmpty ? NSNull() : result.text,
      ]
      assistantMessage["tool_calls"] = result.toolCalls.map { call in
        [
          "id": call.id,
          "type": "function",
          "function": [
            "name": call.name,
            "arguments": call.arguments,
          ],
        ]
      }
      messages.append(assistantMessage)

      for call in result.toolCalls {
        let dashboardCall = GeminiDirectProvider.DashboardFunctionCall(
          name: call.name,
          args: call.argumentsDict)
        let command = toolExecutor.describeDashboardFunctionCall(dashboardCall)
        continuation.yield(.toolStart(command: command))

        let toolResponse = toolExecutor.executeDashboardFunction(dashboardCall)
        let summary = toolResponse["summary"] as? String ?? "Tool beendet."
        let didFail = toolResponse["error"] != nil
        continuation.yield(.toolEnd(output: summary, exitCode: didFail ? 1 : 0))

        let contentData = (try? JSONSerialization.data(withJSONObject: toolResponse))
          ?? Data("{}".utf8)
        let content = String(data: contentData, encoding: .utf8) ?? "{}"
        messages.append(["role": "tool", "tool_call_id": call.id, "content": content])
      }
    }

    throw chatError(
      "Der Assistent hat zu viele Tool-Runden benötigt. Bitte stelle eine engere Frage.")
  }

  // MARK: - Einzelner Streaming-Turn (SSE)

  private struct ParsedToolCall {
    let id: String
    let name: String
    let arguments: String

    var argumentsDict: [String: Any] {
      guard let data = arguments.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return [:]
      }
      return object
    }
  }

  private struct StreamTurnResult {
    let text: String
    let toolCalls: [ParsedToolCall]
  }

  private func streamChatTurn(
    url: URL,
    messages: [[String: Any]]
  ) async throws -> StreamTurnResult {
    var body: [String: Any] = [
      "model": modelID,
      "messages": messages,
      "stream": true,
      "temperature": 0.2,
      "max_tokens": 4096,
    ]
    body["tools"] = openAIToolDeclarations()
    body["tool_choice"] = "auto"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Nous Portal sitzt hinter Cloudflare-Bot-Schutz: Requests ohne
    // Browser-User-Agent werden mit HTTP 403 (Cloudflare 1010) abgelehnt.
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      forHTTPHeaderField: "User-Agent")
    if let bearerToken, !bearerToken.isEmpty {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    request.timeoutInterval = 180
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw chatError("Keine HTTP-Antwort vom LLM-Anbieter erhalten.")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let errorBody = try await readAllData(from: bytes)
      let message = String(data: errorBody, encoding: .utf8) ?? ""
      let detail = extractOpenAIErrorMessage(from: errorBody) ?? String(message.prefix(200))
      throw chatError(
        "Der LLM-Anbieter antwortete mit HTTP \(httpResponse.statusCode). \(detail)")
    }

    var accumulatedText = ""
    var toolCallsByIndex: [Int: ParsedToolCall] = [:]
    var finishedReason: String?

    for try await line in bytes.lines {
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmedLine.hasPrefix("data:") else { continue }

      let payload = String(trimmedLine.dropFirst(5))
        .trimmingCharacters(in: .whitespaces)
      guard !payload.isEmpty else { continue }
      if payload == "[DONE]" { break }

      guard let data = payload.data(using: .utf8),
        let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = chunk["choices"] as? [[String: Any]],
        let firstChoice = choices.first
      else {
        continue
      }

      if let reason = firstChoice["finish_reason"] as? String {
        finishedReason = reason
      }

      guard let delta = firstChoice["delta"] as? [String: Any] else { continue }

      if let content = delta["content"] as? String, !content.isEmpty {
        accumulatedText += content
      }

      if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
        for toolCall in toolCalls {
          guard let index = toolCall["index"] as? Int else { continue }
          var existing = toolCallsByIndex[index]
            ?? ParsedToolCall(id: "", name: "", arguments: "")

          if let id = toolCall["id"] as? String, !id.isEmpty {
            existing = ParsedToolCall(
              id: id, name: existing.name, arguments: existing.arguments)
          }

          if let function = toolCall["function"] as? [String: Any] {
            if let name = function["name"] as? String, !name.isEmpty {
              existing = ParsedToolCall(
                id: existing.id, name: name, arguments: existing.arguments)
            }
            if let arguments = function["arguments"] as? String, !arguments.isEmpty {
              existing = ParsedToolCall(
                id: existing.id, name: existing.name,
                arguments: existing.arguments + arguments)
            }
          }

          toolCallsByIndex[index] = existing
        }
      }
    }

    let toolCalls = toolCallsByIndex
      .sorted { $0.key < $1.key }
      .map { $0.value }
      .filter { !$0.name.isEmpty }

    // Falls das Modell gestreamten Text vor einem Tool-Call geliefert hat,
    // wird der verworfen — nur der finale Text (ohne Tool-Runde) zaehlt.
    if !toolCalls.isEmpty {
      accumulatedText = ""
    }

    return StreamTurnResult(text: accumulatedText, toolCalls: toolCalls)
  }

  // MARK: - OpenAI Tool-Deklarationen

  private func openAIToolDeclarations() -> [[String: Any]] {
    [
      [
        "type": "function",
        "function": [
          "name": "fetchTimeline",
          "description":
            "Fetch timeline cards for a single day or date range. Returns structured JSON cards including day, time range, title, summary, category, and optional detailed summaries.",
          "parameters": [
            "type": "object",
            "properties": [
              "date": ["type": "string", "description": "Single day in YYYY-MM-DD format."],
              "startDate": ["type": "string", "description": "Range start date in YYYY-MM-DD."],
              "endDate": ["type": "string", "description": "Range end date in YYYY-MM-DD."],
              "includeDetailedSummary": [
                "type": "boolean",
                "description":
                  "When true (default), include detailedSummary. Set false for very large windows.",
              ],
              "limit": [
                "type": "number",
                "description": "Optional row cap. If omitted, returns all matching rows.",
              ],
            ],
          ],
        ],
      ],
      [
        "type": "function",
        "function": [
          "name": "fetchObservations",
          "description":
            "Fetch raw observations for a single day or date range. Returns structured JSON grouped by day, with each day's observations ordered chronologically.",
          "parameters": [
            "type": "object",
            "properties": [
              "date": ["type": "string", "description": "Single day in YYYY-MM-DD format."],
              "startDate": ["type": "string", "description": "Range start date in YYYY-MM-DD."],
              "endDate": ["type": "string", "description": "Range end date in YYYY-MM-DD."],
              "limit": [
                "type": "number",
                "description": "Optional row cap. If omitted, returns all matching rows.",
              ],
            ],
          ],
        ],
      ],
    ]
  }

  // MARK: - Hilfsfunktionen

  private func extractOpenAIErrorMessage(from data: Data) -> String? {
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let errorObj = json["error"] as? [String: Any]
    else {
      return nil
    }
    if let message = errorObj["message"] as? String, !message.isEmpty {
      return String(message.prefix(300))
    }
    return nil
  }

  private func readAllData(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
    }
    return data
  }

  private func chatError(_ message: String) -> NSError {
    NSError(
      domain: "OpenAICompatibleChat",
      code: 1102,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
