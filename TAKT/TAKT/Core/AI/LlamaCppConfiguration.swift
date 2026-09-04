import Foundation

struct LlamaCppConfiguration: Equatable {
  var modelDirectory: String
  var modelFile: String
  var mmprojFile: String
  var host: String
  var port: Int
  var contextSize: Int
  var parallelSlots: Int
  var batchSize: Int
  var ubatchSize: Int
  var imageMinTokens: Int

  static let defaultModelDirectory =
    "~/Library/Application Support/wertwandler-takt/llama.cpp"
  static let defaultModelFile = "Qwen3VL-4B-Instruct-Q4_K_M.gguf"
  static let defaultMMProjFile = "mmproj-Qwen3VL-4B-Instruct-F16.gguf"
  static let defaultHost = "127.0.0.1"
  static let defaultPort = 8080
  static let defaultContextSize = 8192
  static let defaultParallelSlots = 1
  static let defaultBatchSize = 512
  static let defaultUBatchSize = 256
  static let defaultImageMinTokens = 1024

  static let `default` = LlamaCppConfiguration(
    modelDirectory: defaultModelDirectory,
    modelFile: defaultModelFile,
    mmprojFile: defaultMMProjFile,
    host: defaultHost,
    port: defaultPort,
    contextSize: defaultContextSize,
    parallelSlots: defaultParallelSlots,
    batchSize: defaultBatchSize,
    ubatchSize: defaultUBatchSize,
    imageMinTokens: defaultImageMinTokens
  )

  private enum Key {
    static let modelDirectory = "llamaCppModelDirectory"
    static let modelFile = "llamaCppModelFile"
    static let mmprojFile = "llamaCppMMProjFile"
    static let host = "llamaCppHost"
    static let port = "llamaCppPort"
    static let contextSize = "llamaCppContextSize"
    static let parallelSlots = "llamaCppParallelSlots"
    static let batchSize = "llamaCppBatchSize"
    static let ubatchSize = "llamaCppUBatchSize"
    static let imageMinTokens = "llamaCppImageMinTokens"
  }

  static func load(from defaults: UserDefaults = .standard) -> LlamaCppConfiguration {
    let fallback = LlamaCppConfiguration.default
    return LlamaCppConfiguration(
      modelDirectory: nonEmptyString(defaults.string(forKey: Key.modelDirectory), fallback: fallback.modelDirectory),
      modelFile: nonEmptyString(defaults.string(forKey: Key.modelFile), fallback: fallback.modelFile),
      mmprojFile: nonEmptyString(defaults.string(forKey: Key.mmprojFile), fallback: fallback.mmprojFile),
      host: nonEmptyString(defaults.string(forKey: Key.host), fallback: fallback.host),
      port: positiveInt(defaults.object(forKey: Key.port) as? Int, fallback: fallback.port),
      contextSize: positiveInt(defaults.object(forKey: Key.contextSize) as? Int, fallback: fallback.contextSize),
      parallelSlots: positiveInt(defaults.object(forKey: Key.parallelSlots) as? Int, fallback: fallback.parallelSlots),
      batchSize: positiveInt(defaults.object(forKey: Key.batchSize) as? Int, fallback: fallback.batchSize),
      ubatchSize: positiveInt(defaults.object(forKey: Key.ubatchSize) as? Int, fallback: fallback.ubatchSize),
      imageMinTokens: positiveInt(defaults.object(forKey: Key.imageMinTokens) as? Int, fallback: fallback.imageMinTokens)
    )
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(modelDirectory.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.modelDirectory)
    defaults.set(modelFile.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.modelFile)
    defaults.set(mmprojFile.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.mmprojFile)
    defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.host)
    defaults.set(port, forKey: Key.port)
    defaults.set(contextSize, forKey: Key.contextSize)
    defaults.set(parallelSlots, forKey: Key.parallelSlots)
    defaults.set(batchSize, forKey: Key.batchSize)
    defaults.set(ubatchSize, forKey: Key.ubatchSize)
    defaults.set(imageMinTokens, forKey: Key.imageMinTokens)
  }

  var baseURL: String {
    "http://\(host):\(port)"
  }

  var serverCommand: String {
    let directory = shellPathQuote(modelDirectory)
    let model = shellDoubleQuote(modelFile)
    let projector = shellDoubleQuote(mmprojFile)
    let quotedHost = shellDoubleQuote(host)
    return "cd \(directory) && llama-server -m \(model) --mmproj \(projector) --alias qwen3-vl-4b --ctx-size \(contextSize) --parallel \(parallelSlots) --batch-size \(batchSize) --ubatch-size \(ubatchSize) --image-min-tokens \(imageMinTokens) --host \(quotedHost) --port \(port)"
  }

  private func shellPathQuote(_ value: String) -> String {
    if value.hasPrefix("~/") {
      return "\"$HOME/\(String(value.dropFirst(2)))\""
    }
    return shellDoubleQuote(value)
  }

  private static func nonEmptyString(_ value: String?, fallback: String) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? fallback : trimmed
  }

  private static func positiveInt(_ value: Int?, fallback: Int) -> Int {
    guard let value, value > 0 else { return fallback }
    return value
  }

  private func shellDoubleQuote(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "$", with: "\\$")
      .replacingOccurrences(of: "`", with: "\\`")
    return "\"\(escaped)\""
  }
}
