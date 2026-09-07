import XCTest
@testable import Dayflow

final class BaseRTLaunchAgentManagerTests: XCTestCase {
  func testSyncDecisionInstallsOnlyForBaseRTWithAutoStart() {
    XCTAssertEqual(
      BaseRTLaunchAgentManager.syncAction(
        engineRaw: "base_rt", autoStart: true, currentlyInstalled: false),
      .install)
    XCTAssertEqual(
      BaseRTLaunchAgentManager.syncAction(
        engineRaw: "ollama", autoStart: true, currentlyInstalled: true),
      .uninstall)
    XCTAssertEqual(
      BaseRTLaunchAgentManager.syncAction(
        engineRaw: "base_rt", autoStart: false, currentlyInstalled: true),
      .uninstall)
    XCTAssertEqual(
      BaseRTLaunchAgentManager.syncAction(
        engineRaw: nil, autoStart: true, currentlyInstalled: false),
      .none)
    XCTAssertEqual(
      BaseRTLaunchAgentManager.syncAction(
        engineRaw: "ollama", autoStart: false, currentlyInstalled: false),
      .none)
  }

  func testWrapperScriptReadsModelAtLaunchAndFallsBack() {
    let script = BaseRTLaunchAgentManager.wrapperScript()

    XCTAssertTrue(script.contains("#!/bin/bash"))
    XCTAssertTrue(script.contains("llmLocalEngine"))
    XCTAssertTrue(script.contains("llmLocalModelId"))
    XCTAssertTrue(script.contains("basecompute/gemma-4-E2B-it"))
    XCTAssertTrue(script.contains("serve --model \"$MODEL\" --port 8080"))
    // Clean exit when TAKT is not on BaseRT → launchd must not restart it.
    XCTAssertTrue(script.contains("exit 0"))
  }

  func testPlistReferencesWrapperAndKeepsAliveOnCrashOnly() {
    let plist = BaseRTLaunchAgentManager.plistXML()

    XCTAssertTrue(plist.contains("<key>Label</key>"))
    XCTAssertTrue(plist.contains(BaseRTLaunchAgentManager.label))
    XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
    XCTAssertTrue(plist.contains("<true/>"))
    XCTAssertTrue(plist.contains("/bin/bash"))
    XCTAssertTrue(plist.contains(BaseRTLaunchAgentManager.wrapperURL.path))
    XCTAssertTrue(plist.contains(BaseRTLaunchAgentManager.logURL.path))
    XCTAssertTrue(plist.contains("<key>SuccessfulExit</key>"))
    XCTAssertTrue(plist.contains("<false/>"))
  }

  func testAutoStartFlagRoundTripsThroughDefaults() {
    let suiteName = "BaseRTLaunchAgentTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.removeObject(forKey: BaseRTLaunchAgentManager.autoStartKey)
    XCTAssertFalse(BaseRTLaunchAgentManager.autoStartEnabled(defaults: defaults))

    defaults.set(true, forKey: BaseRTLaunchAgentManager.autoStartKey)
    XCTAssertTrue(BaseRTLaunchAgentManager.autoStartEnabled(defaults: defaults))
  }
}
