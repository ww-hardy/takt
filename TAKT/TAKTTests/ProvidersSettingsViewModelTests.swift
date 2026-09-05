import XCTest

@testable import Dayflow

@MainActor
final class ProvidersSettingsViewModelTests: XCTestCase {
  private let defaultKeys = [
    "llmLocalEngine",
    "llmLocalBaseURL",
    "llmLocalModelId",
    "llmLocalAPIKey",
    "llamaCppModelDirectory",
    "llamaCppModelFile",
    "llamaCppMMProjFile",
    "llamaCppHost",
    "llamaCppPort",
    "llamaCppContextSize",
    "llamaCppParallelSlots",
    "llamaCppBatchSize",
    "llamaCppUBatchSize",
    "llamaCppImageMinTokens",
    "localSetupComplete",
    "chatGPTPromptOverrides",
    "claudePromptOverrides",
    "dayflowProviderEndpointV2",
    "chatgptSetupComplete",
    "claudeSetupComplete",
    "geminiSelectedModel_v3",
    "geminiSelectedModel_v4",
    LLMProviderRoutingStore.storageKey,
  ]

  private var savedDefaults: [String: Any?] = [:]

  override func setUp() {
    super.setUp()
    savedDefaults = Dictionary(
      uniqueKeysWithValues: defaultKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    )
    defaultKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
  }

  override func tearDown() {
    defaultKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    for (key, value) in savedDefaults {
      if let value {
        UserDefaults.standard.set(value, forKey: key)
      }
    }
    savedDefaults = [:]
    super.tearDown()
  }

  func testLlamaCppEngineUsesOpenAICompatibleServerDefaults() {
    XCTAssertEqual(LocalEngine.llamaCpp.rawValue, "llama_cpp")
    XCTAssertEqual(LocalEngine.llamaCpp.defaultBaseURL, "http://localhost:8080")
    XCTAssertEqual(LocalEngine.llamaCpp.displayName, "llama.cpp")
    XCTAssertEqual(LocalEngine(rawValue: "llama_cpp"), .llamaCpp)
    XCTAssertEqual(
      LocalModelPreferences.defaultModelId(for: .llamaCpp),
      "qwen3-vl-4b"
    )
    XCTAssertTrue(
      LocalModelPreset.recommended.instructions(for: .llamaCpp).command?.contains("--alias qwen3-vl-4b") == true
    )
  }

  func testLlamaCppConfigurationPersistsAndBuildsAUsableServerCommand() {
    let configuration = LlamaCppConfiguration(
      modelDirectory: "~/Models/llama.cpp",
      modelFile: "vision.gguf",
      mmprojFile: "projector.gguf",
      host: "127.0.0.1",
      port: 9090,
      contextSize: 4096,
      parallelSlots: 1,
      batchSize: 256,
      ubatchSize: 128,
      imageMinTokens: 1024
    )

    configuration.save()
    let loaded = LlamaCppConfiguration.load()

    XCTAssertEqual(loaded, configuration)
    XCTAssertEqual(loaded.baseURL, "http://127.0.0.1:9090")
    XCTAssertTrue(loaded.serverCommand.contains("cd \"$HOME/Models/llama.cpp\""))
    XCTAssertTrue(loaded.serverCommand.contains("--ctx-size 4096"))
    XCTAssertTrue(loaded.serverCommand.contains("--parallel 1"))
    XCTAssertTrue(loaded.serverCommand.contains("--image-min-tokens 1024"))
  }

  func testLlamaCppConfigurationFallsBackFromInvalidPersistedValues() {
    UserDefaults.standard.set("", forKey: "llamaCppModelDirectory")
    UserDefaults.standard.set(0, forKey: "llamaCppPort")
    UserDefaults.standard.set(-1, forKey: "llamaCppContextSize")

    let configuration = LlamaCppConfiguration.load()

    XCTAssertEqual(configuration.modelDirectory, LlamaCppConfiguration.default.modelDirectory)
    XCTAssertEqual(configuration.port, LlamaCppConfiguration.defaultPort)
    XCTAssertEqual(configuration.contextSize, LlamaCppConfiguration.defaultContextSize)
  }

  func testInitialRoutingUsesPersistedProviderBeforeSettingsAppears() throws {
    try LLMProviderRoutingStore.save(
      LLMProviderRouting(primary: .openAICompatible),
      to: UserDefaults.standard
    )

    let viewModel = ProvidersSettingsViewModel()

    XCTAssertTrue(viewModel.hasLoadedRouting)
    XCTAssertEqual(viewModel.primaryRoutingProviderId, .openAICompatible)
  }

  func testProviderSetupCompletionRefreshesLocalModelSettingsFromDefaults() {
    UserDefaults.standard.set(LocalEngine.ollama.rawValue, forKey: "llmLocalEngine")
    UserDefaults.standard.set("http://localhost:11434", forKey: "llmLocalBaseURL")
    UserDefaults.standard.set("qwen2.5vl:7b", forKey: "llmLocalModelId")

    let viewModel = ProvidersSettingsViewModel()
    XCTAssertEqual(viewModel.localEngine, .ollama)
    XCTAssertEqual(viewModel.localModelId, "qwen2.5vl:7b")

    UserDefaults.standard.set(LocalEngine.lmstudio.rawValue, forKey: "llmLocalEngine")
    UserDefaults.standard.set("http://localhost:1234", forKey: "llmLocalBaseURL")
    UserDefaults.standard.set("gemma-4-local", forKey: "llmLocalModelId")
    UserDefaults.standard.set("local-test-key", forKey: "llmLocalAPIKey")

    viewModel.handleProviderSetupCompletion(.local)

    XCTAssertEqual(viewModel.localEngine, .lmstudio)
    XCTAssertEqual(viewModel.localBaseURL, "http://localhost:1234")
    XCTAssertEqual(viewModel.localModelId, "gemma-4-local")
    XCTAssertEqual(viewModel.localAPIKey, "local-test-key")
  }

  func testProviderSetupCompletionRefreshesGeminiModelPreference() {
    GeminiModelPreference(primary: .flash36).save()
    let viewModel = ProvidersSettingsViewModel()
    XCTAssertEqual(viewModel.selectedGeminiModel, .flash36)

    GeminiModelPreference(primary: .flashLite35).save()

    XCTAssertTrue(viewModel.handleProviderSetupCompletion(.gemini))
    XCTAssertEqual(viewModel.selectedGeminiModel, .flashLite35)
  }

  func testGeminiModelPreferenceUsesTheNewFallbackChain() {
    XCTAssertEqual(GeminiModel.flash36.rawValue, "gemini-3.6-flash")
    XCTAssertEqual(GeminiModel.flash35.rawValue, "gemini-3.5-flash")
    XCTAssertEqual(GeminiModel.flashLite35.rawValue, "gemini-3.5-flash-lite")
    XCTAssertEqual(
      GeminiModelPreference.default.orderedModels,
      [.flash36, .flash35, .flashLite35]
    )
    XCTAssertEqual(
      GeminiModelPreference(primary: .flash35).orderedModels,
      [.flash35, .flashLite35]
    )
  }

  func testProviderSetupStateHydratesTheSavedLocalConfiguration() {
    UserDefaults.standard.set(LocalEngine.custom.rawValue, forKey: "llmLocalEngine")
    UserDefaults.standard.set("https://local.example.test/v1", forKey: "llmLocalBaseURL")
    UserDefaults.standard.set("saved-vision-model", forKey: "llmLocalModelId")
    UserDefaults.standard.set("saved-local-key", forKey: "llmLocalAPIKey")

    let state = ProviderSetupState()

    XCTAssertEqual(state.localEngine, .custom)
    XCTAssertEqual(state.localBaseURL, "https://local.example.test/v1")
    XCTAssertEqual(state.localModelId, "saved-vision-model")
    XCTAssertEqual(state.localAPIKey, "saved-local-key")
  }

  func testFailedSetupAssignmentRetainsRoutingIntentForRetry() throws {
    UserDefaults.standard.set(
      Data("corrupt-routing".utf8),
      forKey: LLMProviderRoutingStore.storageKey
    )
    let viewModel = ProvidersSettingsViewModel()
    viewModel.loadRouting()
    viewModel.beginProviderSetup(.claude, role: .primary)

    XCTAssertFalse(viewModel.handleProviderSetupCompletion(.claude))
    XCTAssertEqual(viewModel.setupModalProvider, .claude)

    UserDefaults.standard.removeObject(forKey: LLMProviderRoutingStore.storageKey)
    viewModel.loadRouting()

    XCTAssertTrue(viewModel.handleProviderSetupCompletion(.claude))
    XCTAssertEqual(viewModel.primaryRoutingProviderId, .claude)
  }

  func testSwitchingPromptProviderLoadsThatProvidersOverrides() {
    CodexPromptPreferences.save(ActivityCardPromptOverrides(titleBlock: "Codex title"))
    ClaudePromptPreferences.save(ActivityCardPromptOverrides(titleBlock: "Claude title"))

    let viewModel = ProvidersSettingsViewModel()
    viewModel.loadAgentPromptOverridesIfNeeded(force: true)
    XCTAssertEqual(viewModel.agentTitlePromptText, "Codex title")

    viewModel.selectedAgentPromptProvider = .claude
    XCTAssertEqual(viewModel.agentTitlePromptText, "Claude title")
  }

  func testEditingClaudePromptDoesNotMutateCodexPrompt() {
    let viewModel = ProvidersSettingsViewModel()
    viewModel.loadAgentPromptOverridesIfNeeded(force: true)
    viewModel.selectedAgentPromptProvider = .claude
    viewModel.useCustomAgentTitlePrompt = true
    viewModel.agentTitlePromptText = "Claude-only edited title"

    viewModel.selectedAgentPromptProvider = .chatGPT
    XCTAssertFalse(viewModel.useCustomAgentTitlePrompt)
    XCTAssertEqual(viewModel.agentTitlePromptText, CodexPromptDefaults.titleBlock)
    XCTAssertTrue(CodexPromptPreferences.load().isEmpty)

    viewModel.selectedAgentPromptProvider = .claude
    XCTAssertTrue(viewModel.useCustomAgentTitlePrompt)
    XCTAssertEqual(viewModel.agentTitlePromptText, "Claude-only edited title")
  }

  func testResetRestoresOnlyTheSelectedProvidersDefaults() {
    let codexOverrides = ActivityCardPromptOverrides(titleBlock: "Codex title")
    let claudeOverrides = ActivityCardPromptOverrides(titleBlock: "Claude title")
    CodexPromptPreferences.save(codexOverrides)
    ClaudePromptPreferences.save(claudeOverrides)

    let viewModel = ProvidersSettingsViewModel()
    viewModel.selectedAgentPromptProvider = .claude
    viewModel.resetAgentPromptOverrides()

    XCTAssertEqual(viewModel.agentTitlePromptText, ClaudePromptDefaults.titleBlock)
    XCTAssertTrue(ClaudePromptPreferences.load().isEmpty)
    XCTAssertEqual(CodexPromptPreferences.load(), codexOverrides)
  }
}
