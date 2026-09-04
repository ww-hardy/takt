import Foundation

struct LocalModelInstructionSet {
  let title: String
  let subtitle: String
  let bullets: [String]
  let commandTitle: String?
  let commandSubtitle: String?
  let command: String?
  let buttonTitle: String?
  let buttonURL: URL?
  let note: String?
}

enum LocalModelPreset: String, CaseIterable, Codable {
  case qwen3VL4B = "qwen3_vl_4b"
  case qwen25VL3B = "qwen25_vl_3b"

  static let recommended: LocalModelPreset = .qwen3VL4B

  var displayName: String {
    switch self {
    case .qwen3VL4B: return "Qwen3-VL 4B"
    case .qwen25VL3B: return "Qwen2.5-VL 3B"
    }
  }

  var highlightBullets: [String] {
    switch self {
    case .qwen3VL4B:
      return [
        "New, most powerful local VLM",
        "Longer reasoning chains for complex sessions",
        "Fits on most Apple Silicon machines (≈5GB VRAM)",
      ]
    case .qwen25VL3B:
      return [
        "Legacy default for TAKT local mode",
        "Lower VRAM footprint but weaker perception",
      ]
    }
  }

  func modelId(for engine: LocalEngine) -> String {
    switch (self, engine) {
    case (.qwen3VL4B, .lmstudio):
      return "Qwen3-VL-4B-Instruct"
    case (.qwen25VL3B, .lmstudio):
      return "qwen2.5-vl-3b-instruct"
    case (.qwen3VL4B, .llamaCpp):
      return "qwen3-vl-4b"
    case (.qwen25VL3B, .llamaCpp):
      return "qwen2.5-vl-3b"
    case (.qwen3VL4B, _):
      return "qwen3-vl:4b"
    case (.qwen25VL3B, _):
      return "qwen2.5vl:3b"
    }
  }

  func instructions(for engine: LocalEngine) -> LocalModelInstructionSet {
    switch engine {
    case .llamaCpp:
      return LocalModelInstructionSet(
        title: "Install with llama.cpp",
        subtitle:
          "Use llama-server with the Qwen3-VL GGUF and its mmproj vision projector. The server exposes an OpenAI-compatible API.",
        bullets: [
          "Install llama.cpp with Homebrew",
          "Download the Q4_K_M model and matching mmproj file",
          "Start llama-server on port 8080, then test the endpoint",
        ],
        commandTitle: "Example server command:",
        commandSubtitle: "The model and mmproj files must be in the same local models directory",
        command:
          "llama-server -m Qwen3VL-4B-Instruct-Q4_K_M.gguf --mmproj mmproj-Qwen3VL-4B-Instruct-F16.gguf --alias qwen3-vl-4b --ctx-size 8192 --parallel 1 --batch-size 512 --ubatch-size 256 --image-min-tokens 1024 --host 127.0.0.1 --port 8080",
        buttonTitle: nil,
        buttonURL: nil,
        note:
          "llama.cpp runs locally. TAKT sends screenshots to the local server at \(LocalEngine.llamaCpp.defaultBaseURL); no native llama.cpp library is embedded in the app."
      )
    case .ollama, .custom:
      return LocalModelInstructionSet(
        title: "Install via Ollama",
        subtitle: "Make sure you're on Ollama 0.12.10 or newer before pulling the model.",
        bullets: [
          "Open Terminal",
          "Run the pull command below (≈5GB download)",
          "Keep Ollama running in the background",
        ],
        commandTitle: "Run this command:",
        commandSubtitle: "Downloads \(displayName) for Ollama",
        command: ollamaPullCommand,
        buttonTitle: nil,
        buttonURL: nil,
        note: "Need to stay on Qwen2.5? Keep your current model selected and skip this upgrade."
      )
    case .lmstudio:
      return LocalModelInstructionSet(
        title: "Install inside LM Studio",
        subtitle:
          "Make sure you're on 0.3.31. Use LM Studio's model browser to download the GGUF build.",
        bullets: [
          "Open LM Studio and click the Models tab",
          "Search for \"\(modelId(for: .lmstudio))\"",
          "Download the Instruct variant, then start Local Server",
        ],
        commandTitle: nil,
        commandSubtitle: nil,
        command: nil,
        buttonTitle: "Open download in LM Studio",
        buttonURL: lmStudioDownloadURL,
        note:
          "Tip: enable \"Launch local server\" so TAKT can talk to LM Studio at \(LocalEngine.lmstudio.defaultBaseURL)."
      )
    }
  }

  var ollamaPullCommand: String {
    switch self {
    case .qwen3VL4B: return "ollama pull qwen3-vl:4b"
    case .qwen25VL3B: return "ollama pull qwen2.5vl:3b"
    }
  }

  var lmStudioDownloadURL: URL? {
    switch self {
    case .qwen3VL4B:
      return URL(
        string: "https://model.lmstudio.ai/download/lmstudio-community/Qwen3-VL-4B-Instruct-GGUF")
    case .qwen25VL3B:
      return URL(
        string: "https://model.lmstudio.ai/download/lmstudio-community/Qwen2.5-VL-3B-Instruct-GGUF")
    }
  }
}

enum LocalModelPreferences {
  private static let presetKey = "llmLocalModelPreset"
  private static let upgradeDismissedKey = "llmLocalModelUpgradeDismissed"
  private static let defaults = UserDefaults.standard

  static func currentPreset() -> LocalModelPreset? {
    guard let raw = defaults.string(forKey: presetKey) else { return nil }
    return LocalModelPreset(rawValue: raw)
  }

  static func savePreset(_ preset: LocalModelPreset) {
    defaults.set(preset.rawValue, forKey: presetKey)
  }

  static func clearPreset() {
    defaults.removeObject(forKey: presetKey)
  }

  static func syncPreset(for engine: LocalEngine, modelId: String) {
    let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      clearPreset()
      return
    }
    if let preset = LocalModelPreset.allCases.first(where: { $0.modelId(for: engine) == normalized }
    ) {
      savePreset(preset)
    } else {
      clearPreset()
    }
  }

  static func defaultModelId(for engine: LocalEngine) -> String {
    LocalModelPreset.recommended.modelId(for: engine)
  }

  static func shouldShowUpgradeBanner(engine: LocalEngine, modelId: String) -> Bool {
    if defaults.bool(forKey: upgradeDismissedKey) { return false }
    if currentPreset() == .qwen3VL4B { return false }
    let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized == LocalModelPreset.qwen25VL3B.modelId(for: engine)
  }

  static func markUpgradeDismissed(_ dismissed: Bool) {
    defaults.set(dismissed, forKey: upgradeDismissedKey)
  }
}
