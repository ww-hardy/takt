import Foundation

enum LocalEngine: String, CaseIterable, Identifiable, Codable {
  case ollama
  case lmstudio
  case llamaCpp = "llama_cpp"
  case baseRT = "base_rt"
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ollama: return "Ollama"
    case .lmstudio: return "LM Studio"
    case .llamaCpp: return "llama.cpp"
    case .baseRT: return "BaseRT"
    case .custom: return "Custom"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .ollama: return "http://localhost:11434"
    case .lmstudio: return "http://localhost:1234"
    case .llamaCpp: return "http://localhost:8080"
    case .baseRT: return "http://localhost:8080"
    case .custom: return "http://localhost:11434"
    }
  }

  var installURL: URL? {
    switch self {
    case .ollama:
      return URL(string: "https://ollama.com/download/mac")
    case .lmstudio:
      return URL(string: "https://lmstudio.ai/")
    case .llamaCpp:
      return URL(string: "https://formulae.brew.sh/formula/llama.cpp")
    case .baseRT:
      return URL(string: "https://docs.basecompute.co/installation")
    case .custom:
      return nil
    }
  }

  var installCommand: String? {
    switch self {
    case .ollama, .lmstudio:
      return nil
    case .llamaCpp:
      return "brew install llama.cpp"
    case .baseRT:
      return "curl -LsSf https://basecompute.co/install.sh | sh"
    case .custom:
      return nil
    }
  }
}
