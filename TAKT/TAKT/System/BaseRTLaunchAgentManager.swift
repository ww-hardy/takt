import Foundation

/// Installs and manages a per-user LaunchAgent that keeps the BaseRT
/// OpenAI-compatible server (`basert serve`) running in the background.
///
/// TAKT is not sandboxed, so it can write directly to
/// `~/Library/LaunchAgents` and drive `launchctl` itself.
///
/// Design:
/// - A small shell wrapper (regenerated on install) is stored in the app's
///   Application Support folder. It reads the current engine/model from
///   UserDefaults at *launch time*, so switching engines or models in the UI
///   never requires reinstalling the agent — a `kickstart` is enough.
/// - The wrapper exits 0 when TAKT is not on the BaseRT engine anymore (or
///   when `basert` is missing), so launchd does not restart it in a loop.
/// - `KeepAlive` only restarts on abnormal exit (crashes), not on clean exit.
enum BaseRTLaunchAgentManager {
  static let agentSuffix = ".basert"

  // MARK: - Paths

  static var bundleID: String {
    Bundle.main.bundleIdentifier ?? "ch.wertwandler.takt"
  }

  static var label: String {
    bundleID + agentSuffix
  }

  static var plistFileName: String {
    label + ".plist"
  }

  static var launchAgentsDirectory: URL {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LaunchAgents", isDirectory: true)
  }

  static var plistURL: URL {
    launchAgentsDirectory.appendingPathComponent(plistFileName)
  }

  static var wrapperURL: URL {
    StoragePaths.appSupportBase.appendingPathComponent("basert-serve.sh")
  }

  static var logURL: URL {
    StoragePaths.appSupportBase.appendingPathComponent("basert-serve.log")
  }

  private static var uid: String {
    String(getuid())
  }

  private static var target: String {
    "gui/\(uid)/\(label)"
  }

  // MARK: - Status

  static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path)
  }

  /// UserDefaults key controlling whether BaseRT should run in the background.
  static let autoStartKey = "llmBaseRTAutoStart"

  /// True when launchd currently has the agent loaded (running or idle).
  static func isLoaded() -> Bool {
    runLaunchCtl(["print", target]).exitCode == 0
  }

  /// True when the agent is loaded AND the underlying process is running.
  static func isRunning() -> Bool {
    guard isLoaded() else { return false }
    // `launchctl print` includes a "state = running" line for active agents.
    let output = runLaunchCtl(["print", target]).stdout
    return output.contains("state = running")
  }

  // MARK: - Install / Uninstall

  /// Writes the wrapper + plist and boots the agent. Safe to call when the
  /// agent is already installed (it reloads with the current configuration).
  static func install() throws {
    try writeWrapper()
    try writePlist()

    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: launchAgentsDirectory.path) {
      try fileManager.createDirectory(
        at: launchAgentsDirectory, withIntermediateDirectories: true)
    }

    // Unload any previous instance before bootstrapping the fresh plist.
    if isLoaded() {
      _ = runLaunchCtl(["bootout", target])
    }
    let result = runLaunchCtl(["bootstrap", "gui/\(uid)", plistURL.path])
    guard result.exitCode == 0 else {
      throw BaseRTLaunchAgentError.installFailed(result.stderr)
    }
    // Start immediately instead of waiting for the next login.
    _ = runLaunchCtl(["kickstart", target])
  }

  /// Unloads the agent and removes both generated files.
  static func uninstall() {
    if isLoaded() {
      _ = runLaunchCtl(["bootout", target])
    }
    try? FileManager.default.removeItem(at: plistURL)
    try? FileManager.default.removeItem(at: wrapperURL)
  }

  /// Restarts the agent so a model/engine change takes effect now.
  static func restartIfInstalled() {
    guard isInstalled else { return }
    if isLoaded() {
      _ = runLaunchCtl(["kickstart", "-k", target])
    } else {
      try? install()
    }
  }

  /// Keeps the agent in sync with the persisted local-engine configuration:
  /// installed exactly when the user runs BaseRT with auto-start enabled,
  /// removed otherwise. Call after any write to `llmLocalEngine`,
  /// `llmLocalModelId`, or the auto-start flag.
  static func syncWithPersistedLocalConfiguration(defaults: UserDefaults = .standard) {
    let engineRaw = defaults.string(forKey: "llmLocalEngine")
    let wantsAutoStart = defaults.bool(forKey: autoStartKey)
    switch syncAction(
      engineRaw: engineRaw, autoStart: wantsAutoStart, currentlyInstalled: isInstalled
    ) {
    case .install:
      try? install()
    case .uninstall:
      uninstall()
    case .none:
      break
    }
  }

  // MARK: - File generation

  static func writeWrapper() throws {
    let script = wrapperScript()
    try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
  }

  static func writePlist() throws {
    let plist = plistXML()
    try plist.write(to: plistURL, atomically: true, encoding: .utf8)
  }

  /// The user's auto-start flag (persisted in UserDefaults).
  static func autoStartEnabled(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: autoStartKey)
  }

  /// Decision helper (pure, unit-testable): should the agent be installed
  /// given a persisted engine and the auto-start flag?
  static func shouldBeInstalled(engineRaw: String?, autoStart: Bool) -> Bool {
    engineRaw == LocalEngine.baseRT.rawValue && autoStart
  }

  /// Pure sync decision given persisted state; returns the action to take.
  enum SyncAction {
    case install
    case uninstall
    case none
  }

  static func syncAction(
    engineRaw: String?, autoStart: Bool, currentlyInstalled: Bool
  ) -> SyncAction {
    if shouldBeInstalled(engineRaw: engineRaw, autoStart: autoStart) {
      return .install
    }
    return currentlyInstalled ? .uninstall : .none
  }

  static func wrapperScript() -> String {
    """
    #!/bin/bash
    # Generated by TAKT — BaseRT background server.
    # Reads the current engine/model from UserDefaults at launch time.

    ENGINE="$(/usr/bin/defaults read \(bundleID) llmLocalEngine 2>/dev/null)"
    if [ "$ENGINE" != "base_rt" ]; then
      # TAKT is not on the BaseRT engine — exit cleanly, do not restart.
      exit 0
    fi

    MODEL="$(/usr/bin/defaults read \(bundleID) llmLocalModelId 2>/dev/null)"
    if [ -z "$MODEL" ]; then
      MODEL="basecompute/gemma-4-E2B-it"
    fi

    BASERT="$HOME/.basert/basert"
    if [ ! -x "$BASERT" ]; then
      echo "basert not found at $BASERT — run the BaseRT installer." >&2
      exit 0
    fi

    exec "$BASERT" serve --model "$MODEL" --port 8080
    """
  }

  static func plistXML() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(label)</string>
      <key>ProgramArguments</key>
      <array>
        <string>/bin/bash</string>
        <string>\(wrapperURL.path)</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <dict>
        <key>SuccessfulExit</key>
        <false/>
      </dict>
      <key>ProcessType</key>
      <string>Background</string>
      <key>StandardOutPath</key>
      <string>\(logURL.path)</string>
      <key>StandardErrorPath</key>
      <string>\(logURL.path)</string>
    </dict>
    </plist>
    """
  }

  // MARK: - launchctl

  @discardableResult
  static func runLaunchCtl(_ arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return (1, "", "launchctl failed to start: \(error.localizedDescription)")
    }
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
  }
}

enum BaseRTLaunchAgentError: LocalizedError {
  case installFailed(String)

  var errorDescription: String? {
    switch self {
    case .installFailed(let detail):
      return "BaseRT background agent could not be installed: \(detail)"
    }
  }
}
