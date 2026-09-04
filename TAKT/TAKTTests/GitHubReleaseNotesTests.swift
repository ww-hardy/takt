import XCTest

@testable import Dayflow

final class GitHubReleaseNotesTests: XCTestCase {
  func testMarkdownBulletsBecomeReleaseHighlights() {
    let body = """
    ## TAKT 2.1.1

    ### Neu in dieser Version

    - **Sparkle aktiviert** — Updates kommen jetzt über GitHub.
    - CPU-Optimierung im Idle.
    * Lokale LLM-Installation im Onboarding.
    """

    XCTAssertEqual(
      GitHubReleaseNotesParser.highlights(from: body),
      [
        "Sparkle aktiviert — Updates kommen jetzt über GitHub.",
        "CPU-Optimierung im Idle.",
        "Lokale LLM-Installation im Onboarding.",
      ])
  }

  func testVersionRemovesReleaseTagPrefix() {
    XCTAssertEqual(GitHubReleaseNotesParser.version(from: "v2.1.1"), "2.1.1")
    XCTAssertEqual(GitHubReleaseNotesParser.version(from: "2.1.1"), "2.1.1")
  }
}
