import Foundation

enum DailyRecapProvider: String, Codable, CaseIterable, Sendable {
  case local
  case gemini
  case chatgpt
  case claude
  case openAICompatible
  case none

  static let allCases: [DailyRecapProvider] = [
    .openAICompatible,
    .gemini,
    .chatgpt,
    .claude,
    .local,
  ]

  /// The Daily view uses the same LLM provider as the rest of the application
  /// (timeline/chat): the canonical `LLMProviderRoutingStore.primary`. There is no
  /// separate persisted Daily provider selection anymore — that duplication was the
  /// mismatch between Daily and the rest of the app (legacy `dailyRecapProvider_v1`).
  static func load(from defaults: UserDefaults = .standard) -> DailyRecapProvider {
    let providerID = (try? LLMProviderRoutingStore.load(from: defaults))?.primary
    return DailyRecapProvider(canonical: providerID)
  }

  /// Maps the canonical routing provider to the Daily recap provider. `dayflow` was
  /// removed in TAKT; legacy routings fall back to the OpenAI-compatible path.
  init(canonical providerID: LLMProviderID?) {
    switch providerID {
    case .gemini:
      self = .gemini
    case .chatGPT:
      self = .chatgpt
    case .claude:
      self = .claude
    case .local:
      self = .local
    case .openAICompatible:
      self = .openAICompatible
    case .dayflow:
      // TAKT: TAKT-Backend entfernt — auf OpenAI-kompatibel umleiten.
      self = .openAICompatible
    case nil:
      self = .none
    }
  }

  /// The canonical routing provider ID for this Daily provider. `nil` for `.none`
  /// because the routing store always has a primary provider.
  var canonicalProviderID: LLMProviderID? {
    switch self {
    case .openAICompatible:
      return .openAICompatible
    case .gemini:
      return .gemini
    case .chatgpt:
      return .chatGPT
    case .claude:
      return .claude
    case .local:
      return .local
    case .none:
      return nil
    }
  }

  var analyticsName: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .local:
      return "Lokal"
    case .gemini:
      return "Gemini"
    case .chatgpt:
      return "ChatGPT"
    case .claude:
      return "Claude"
    case .openAICompatible:
      return "OpenAI-kompatibel"
    case .none:
      return "Kein Anbieter"
    }
  }

  var selectionLabel: String {
    switch self {
    case .local:
      return "Lokal"
    case .gemini:
      return "Gemini 3.5 Flash"
    case .chatgpt:
      return "GPT-5.4"
    case .claude:
      return "Claude Opus"
    case .openAICompatible:
      return "OpenAI-kompatibel (z. B. Nous Portal)"
    case .none:
      return "Kein Anbieter (Daily aus)"
    }
  }

  var pickerSubtitle: String {
    switch self {
    case .local:
      return "Nutzt Ollama, LM Studio oder einen anderen lokalen Server auf diesem Mac."
    case .gemini:
      return "Gemini 3.5 Flash"
    case .chatgpt:
      return "GPT-5.4"
    case .claude:
      return "Claude Opus"
    case .openAICompatible:
      return "Nutzt den OpenAI-kompatiblen Anbieter aus den Einstellungen (z. B. Nous Portal)."
    case .none:
      return "Schaltet die Daily-Zusammenfassung aus, bis du einen Anbieter wählst."
    }
  }

  var runtimeLabel: String {
    switch self {
    case .local:
      return "local_llm"
    case .gemini:
      return "gemini_direct"
    case .chatgpt, .claude:
      return "chat_cli"
    case .openAICompatible:
      return "openai_compatible"
    case .none:
      return "disabled"
    }
  }

  var modelOrTool: String? {
    switch self {
    case .local:
      return Self.currentLocalModelID()
    case .gemini:
      return GeminiModel.flash36.rawValue
    case .chatgpt:
      return "gpt-5.4"
    case .claude:
      return "opus"
    case .openAICompatible:
      return OpenAICompatiblePreferences.load()?.modelID
    case .none:
      return nil
    }
  }

  var canGenerate: Bool {
    self != .none
  }

  private static func currentLocalModelID(from defaults: UserDefaults = .standard) -> String? {
    let trimmed = defaults.string(forKey: "llmLocalModelId")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return trimmed
    }

    let rawEngine = defaults.string(forKey: "llmLocalEngine") ?? LocalEngine.ollama.rawValue
    let engine = LocalEngine(rawValue: rawEngine) ?? .ollama
    return LocalModelPreferences.defaultModelId(for: engine)
  }
}

enum DailyStandupPlaceholder {
  static let notGeneratedMessage =
    "Daily data has not been generated yet. If this is unexpected, please report a bug."
  static let todayNotGeneratedMessage = "Today's daily recap will be generated tomorrow morning."
  static let insufficientHistoryMessage =
    "Not enough captured activity in the previous 3 days to generate a standup."
  static let noProviderSelectedMessage =
    "No Daily provider is selected. Click the gear button above, then choose a provider to turn recap generation back on."
}

struct DailyStandupGenerationMetadata: Codable, Equatable, Sendable {
  var provider: DailyRecapProvider
  var runtime: String
  var modelOrTool: String?
  var sourceDay: String?
  var generatedAt: Date?

  init(
    provider: DailyRecapProvider,
    runtime: String? = nil,
    modelOrTool: String? = nil,
    sourceDay: String? = nil,
    generatedAt: Date? = Date()
  ) {
    self.provider = provider
    self.runtime = runtime ?? provider.runtimeLabel
    self.modelOrTool = modelOrTool ?? provider.modelOrTool
    self.sourceDay = sourceDay
    self.generatedAt = generatedAt
  }

  var displayLabel: String {
    switch provider {
    case .local:
      return modelOrTool ?? "Lokal"
    case .gemini:
      return "Gemini 3.5 Flash"
    case .chatgpt:
      return "GPT-5.4"
    case .claude:
      return "Claude Opus"
    case .openAICompatible:
      return modelOrTool ?? "OpenAI-kompatibel"
    case .none:
      return "Kein Anbieter"
    }
  }
}

struct DailyBulletItem: Identifiable, Codable, Equatable, Sendable {
  var id: UUID = UUID()
  var text: String
}

struct DailyStandupDraft: Codable, Equatable, Sendable {
  var highlightsTitle: String
  var highlights: [DailyBulletItem]
  var tasksTitle: String
  var tasks: [DailyBulletItem]
  var blockersTitle: String
  var blockersBody: String
  var generation: DailyStandupGenerationMetadata?

  static let `default` = DailyStandupDraft(
    highlightsTitle: "Yesterday's highlights",
    highlights: [DailyBulletItem(text: DailyStandupPlaceholder.notGeneratedMessage)],
    tasksTitle: "Today's tasks",
    tasks: [DailyBulletItem(text: DailyStandupPlaceholder.notGeneratedMessage)],
    blockersTitle: "Blockers",
    blockersBody: DailyStandupPlaceholder.notGeneratedMessage,
    generation: nil
  )

  static let todayPlaceholder = DailyStandupDraft(
    highlightsTitle: "Yesterday's highlights",
    highlights: [DailyBulletItem(text: DailyStandupPlaceholder.todayNotGeneratedMessage)],
    tasksTitle: "Today's tasks",
    tasks: [DailyBulletItem(text: DailyStandupPlaceholder.todayNotGeneratedMessage)],
    blockersTitle: "Blockers",
    blockersBody: DailyStandupPlaceholder.todayNotGeneratedMessage,
    generation: nil
  )

  static let insufficientHistory = DailyStandupDraft(
    highlightsTitle: "Recent highlights",
    highlights: [DailyBulletItem(text: DailyStandupPlaceholder.insufficientHistoryMessage)],
    tasksTitle: "Tasks",
    tasks: [DailyBulletItem(text: DailyStandupPlaceholder.insufficientHistoryMessage)],
    blockersTitle: "Blockers",
    blockersBody: DailyStandupPlaceholder.insufficientHistoryMessage,
    generation: nil
  )

  static let noProviderSelected = DailyStandupDraft(
    highlightsTitle: "Yesterday's highlights",
    highlights: [DailyBulletItem(text: DailyStandupPlaceholder.noProviderSelectedMessage)],
    tasksTitle: "Today's tasks",
    tasks: [DailyBulletItem(text: DailyStandupPlaceholder.noProviderSelectedMessage)],
    blockersTitle: "Blockers",
    blockersBody: DailyStandupPlaceholder.noProviderSelectedMessage,
    generation: nil
  )

  func encodedJSONString() -> String? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  var hasGeneratedContent: Bool {
    !highlights.isEmpty || !tasks.isEmpty
      || !blockersBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct DailyRecapSourceDayCandidate: Equatable, Sendable {
  let dayString: String
  let startOfDay: Date
  let endOfDay: Date
}

enum DailyRecapSourceDayResolver {
  static func consumedSourceDays(from entries: [DailyStandupEntry]) -> Set<String> {
    entries.reduce(into: Set<String>()) { result, entry in
      guard
        let data = entry.payloadJSON.data(using: .utf8),
        let draft = try? JSONDecoder().decode(DailyStandupDraft.self, from: data),
        let sourceDay = draft.generation?.sourceDay?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !sourceDay.isEmpty
      else {
        return
      }

      result.insert(sourceDay)
    }
  }

  static func sourceDay(
    before targetStart: Date,
    lookbackWindowDays: Int,
    consumedSourceDays: Set<String>,
    hasMinimumActivity: (String) -> Bool
  ) -> DailyRecapSourceDayCandidate? {
    guard lookbackWindowDays > 0 else { return nil }

    let calendar = Calendar.current
    for offset in 1...lookbackWindowDays {
      guard
        let sourceStart = calendar.date(byAdding: .day, value: -offset, to: targetStart)
      else {
        continue
      }

      let dayString = DateFormatter.yyyyMMdd.string(from: sourceStart)
      guard !consumedSourceDays.contains(dayString),
        hasMinimumActivity(dayString),
        let sourceEnd = calendar.date(byAdding: .day, value: 1, to: sourceStart)
      else {
        continue
      }

      return DailyRecapSourceDayCandidate(
        dayString: dayString,
        startOfDay: sourceStart,
        endOfDay: sourceEnd
      )
    }

    return nil
  }
}
