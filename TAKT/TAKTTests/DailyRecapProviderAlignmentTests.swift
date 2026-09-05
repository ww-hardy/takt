import XCTest

@testable import Dayflow

/// Regression tests for the TAKT Daily-provider alignment.
///
/// The Daily view must use the same LLM provider as the rest of the application
/// (timeline/chat): the canonical `LLMProviderRoutingStore.primary`. These tests
/// pin that contract so the duplicated `dailyRecapProvider_v1` selection cannot
/// come back.
final class DailyRecapProviderAlignmentTests: XCTestCase {
  private var suiteNames: [String] = []

  override func tearDown() {
    for suiteName in suiteNames {
      UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
    suiteNames = []
    super.tearDown()
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "DailyRecapProviderAlignmentTests.\\(UUID().uuidString)"
    suiteNames.append(suiteName)
    return try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  private func saveRouting(
    _ routing: LLMProviderRouting, to defaults: UserDefaults
  ) throws {
    try LLMProviderRoutingStore.save(routing, to: defaults)
  }

  // MARK: - Daily derives from the canonical routing store

  func testDailyProviderFollowsCanonicalPrimary() throws {
    let defaults = try makeDefaults()

    try saveRouting(LLMProviderRouting(primary: .openAICompatible), to: defaults)
    XCTAssertEqual(
      DailyRecapProvider.load(from: defaults), .openAICompatible,
      "Daily must use the same openAI-compatible provider as timeline/chat")

    try saveRouting(LLMProviderRouting(primary: .gemini), to: defaults)
    XCTAssertEqual(DailyRecapProvider.load(from: defaults), .gemini)

    try saveRouting(LLMProviderRouting(primary: .local), to: defaults)
    XCTAssertEqual(DailyRecapProvider.load(from: defaults), .local)

    try saveRouting(LLMProviderRouting(primary: .chatGPT), to: defaults)
    XCTAssertEqual(DailyRecapProvider.load(from: defaults), .chatgpt)

    try saveRouting(LLMProviderRouting(primary: .claude), to: defaults)
    XCTAssertEqual(DailyRecapProvider.load(from: defaults), .claude)
  }

  func testDailyProviderLegacyDayflowRoutingFallsBackToOpenAICompatible() throws {
    let defaults = try makeDefaults()
    try saveRouting(LLMProviderRouting(primary: .dayflow), to: defaults)

    XCTAssertEqual(
      DailyRecapProvider.load(from: defaults), .openAICompatible,
      "TAKT backend was removed; a legacy routing must fall back to openAI-compatible")
  }

  func testDailyProviderFollowsCanonicalDefaultWhenNoRoutingStored() throws {
    let defaults = try makeDefaults()
    // No routing value and no legacy provider values: migration must use the
    // neutral OpenAI-compatible path rather than silently selecting Gemini.
    XCTAssertEqual(DailyRecapProvider.load(from: defaults), .openAICompatible)
    XCTAssertEqual(
      try LLMProviderRoutingStore.load(from: defaults).primary,
      .openAICompatible
    )
  }

  func testDailyProviderDoesNotReadOrWriteLegacyStorageKey() throws {
    let defaults = try makeDefaults()
    try saveRouting(LLMProviderRouting(primary: .openAICompatible), to: defaults)
    // Simulate a stale legacy selection that contradicted the canonical provider.
    defaults.set("gemini", forKey: "dailyRecapProvider_v1")

    XCTAssertEqual(
      DailyRecapProvider.load(from: defaults), .openAICompatible,
      "A stale dailyRecapProvider_v1 value must never override the canonical routing")
    // The legacy key must not be rewritten by load().
    XCTAssertEqual(defaults.string(forKey: "dailyRecapProvider_v1"), "gemini")
  }

  // MARK: - Daily selection must not overwrite global routing

  func testDailySelectionDoesNotOverwriteCanonicalRouting() throws {
    let defaults = try makeDefaults()
    try saveRouting(LLMProviderRouting(primary: .openAICompatible), to: defaults)

    // The Daily picker is local UI state. The Settings provider is the canonical
    // app-wide decision and must survive a later app restart.
    XCTAssertEqual(
      try LLMProviderRoutingStore.load(from: defaults).primary,
      .openAICompatible
    )
    XCTAssertEqual(
      DailyRecapProvider.load(from: defaults),
      .openAICompatible
    )
  }

  // MARK: - Mapping

  func testCanonicalProviderIDMapping() {
    XCTAssertEqual(DailyRecapProvider.openAICompatible.canonicalProviderID, .openAICompatible)
    XCTAssertEqual(DailyRecapProvider.gemini.canonicalProviderID, .gemini)
    XCTAssertEqual(DailyRecapProvider.chatgpt.canonicalProviderID, .chatGPT)
    XCTAssertEqual(DailyRecapProvider.claude.canonicalProviderID, .claude)
    XCTAssertEqual(DailyRecapProvider.local.canonicalProviderID, .local)
    XCTAssertNil(DailyRecapProvider.none.canonicalProviderID)
  }

  func testSelectableProvidersDoNotIncludeNone() {
    XCTAssertFalse(
      DailyRecapProvider.allCases.contains(.none),
      "Daily no longer has an independent off-state; it follows the canonical provider")
    XCTAssertTrue(DailyRecapProvider.allCases.contains(.openAICompatible))
  }

}
