//
//  WhatsNewView.swift
//  Dayflow
//
//  Displays release highlights after app updates
//

import AppKit
import SwiftUI

// MARK: - Release Notes Data Structure

struct ReleaseNoteCTA {
  let title: String
  let description: String
  let buttonTitle: String
  let url: String
}

struct ReleaseNoteSocialPreview {
  let authorName: String
  let authorHandle: String
  let dateText: String
  let body: String
  let url: String
}

struct ReleaseNoteBetaSignup {
  let title: String
  let description: String
  let followUp: String
}

struct ReleaseNote: Identifiable {
  let id = UUID()
  let version: String  // e.g. "2.0.1"
  let title: String  // e.g. "Timeline Improvements"
  let highlights: [String]  // Array of bullet points
  let socialPreview: ReleaseNoteSocialPreview?
  let previewIntro: String?
  let previewImageNames: [String]
  let betaSignup: ReleaseNoteBetaSignup?
  let cta: ReleaseNoteCTA?
  let showsWeeklyFeedbackSurvey: Bool

  // Helper to compare semantic versions
  var semanticVersion: [Int] {
    version.split(separator: ".").compactMap { Int($0) }
  }
}

enum AgentsPerDayOption: String, CaseIterable, Identifiable {
  case oneToTwo = "1-2"
  case threeToFive = "3-5"
  case sixToTen = "6-10"
  case elevenToTwenty = "11-20"
  case moreThanTwenty = "20+"

  var id: String { rawValue }

  var title: String {
    rawValue.replacingOccurrences(of: "-", with: "–")
  }
}

enum WhatsNewWeeklyFeedback: String, CaseIterable, Identifiable {
  case valuable = "valuable"
  case usefulNeedsWork = "useful_needs_work"
  case notUsefulYet = "not_useful_yet"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .valuable:
      return "It feels valuable"
    case .usefulNeedsWork:
      return "Useful, but needs work"
    case .notUsefulYet:
      return "Not useful yet"
    }
  }
}

// MARK: - What's New Configuration

private struct GitHubReleasePayload: Codable {
  let tagName: String
  let name: String
  let body: String

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case body
  }
}

enum GitHubReleaseNotesParser {
  static func version(from tag: String) -> String {
    tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
  }

  static func highlights(from body: String) -> [String] {
    body.split(separator: "\n", omittingEmptySubsequences: false)
      .compactMap { rawLine in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return cleanMarkdown(String(line.dropFirst(2)))
      }
      .filter { !$0.isEmpty }
  }

  private static func cleanMarkdown(_ text: String) -> String {
    var cleaned = text
      .replacingOccurrences(of: "**", with: "")
      .replacingOccurrences(of: "__", with: "")
      .replacingOccurrences(of: "`", with: "")

    let pattern = #"\[([^\]]+)\]\([^\)]+\)"#
    if let expression = try? NSRegularExpression(pattern: pattern) {
      let range = NSRange(cleaned.startIndex..., in: cleaned)
      cleaned = expression.stringByReplacingMatches(
        in: cleaned,
        range: range,
        withTemplate: "$1"
      )
    }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum WhatsNewConfiguration {
  private static let seenKey = "lastSeenWhatsNewVersion"
  private static let cacheKey = "latestGitHubReleaseNotes"
  private static let repository = "ww-hardy/takt"

  /// Local safety net used only when GitHub cannot be reached.
  static var configuredRelease: ReleaseNote? {
    ReleaseNote(
      version: currentAppVersion,
      title: "TAKT wird kontinuierlich weiterentwickelt",
      highlights: [
        "Verbesserungen an Stabilität, Performance und Bildschirmaufzeichnung.",
        "Aktuelle Release Notes werden direkt aus GitHub geladen.",
      ],
      socialPreview: nil,
      previewIntro: nil,
      previewImageNames: [],
      betaSignup: nil,
      cta: nil,
      showsWeeklyFeedbackSurvey: false
    )
  }

  /// Loads the latest published GitHub release and caches it for offline use.
  static func loadLatestRelease() async -> ReleaseNote? {
    do {
      let payload = try await fetchLatestRelease()
      UserDefaults.standard.set(try? JSONEncoder().encode(payload), forKey: cacheKey)
      return makeRelease(from: payload)
    } catch {
      return cachedRelease() ?? configuredRelease
    }
  }

  /// Returns the latest release when it is newer than the last one seen by the user.
  static func pendingReleaseForCurrentBuild() async -> ReleaseNote? {
    guard let release = await loadLatestRelease() else { return nil }
    guard isVersion(release.version, lessThanOrEqualTo: currentAppVersion) else { return nil }
    let lastSeen = UserDefaults.standard.string(forKey: seenKey)

    if lastSeen == nil || lastSeen?.isEmpty == true {
      UserDefaults.standard.set(release.version, forKey: seenKey)
      return nil
    }

    return lastSeen == release.version ? nil : release
  }

  /// Returns the latest GitHub release for the manual Versionshinweise action.
  static func latestRelease() async -> ReleaseNote? {
    await loadLatestRelease()
  }

  static func markReleaseAsSeen(version: String) {
    UserDefaults.standard.set(version, forKey: seenKey)
  }

  private static func fetchLatestRelease() async throws -> GitHubReleasePayload {
    let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("TAKT/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
  }

  private static func cachedRelease() -> ReleaseNote? {
    guard let data = UserDefaults.standard.data(forKey: cacheKey),
      let payload = try? JSONDecoder().decode(GitHubReleasePayload.self, from: data)
    else { return nil }
    return makeRelease(from: payload)
  }

  private static func makeRelease(from payload: GitHubReleasePayload) -> ReleaseNote {
    let highlights = GitHubReleaseNotesParser.highlights(from: payload.body)
    return ReleaseNote(
      version: GitHubReleaseNotesParser.version(from: payload.tagName),
      title: payload.name.isEmpty ? "Neu in TAKT" : payload.name,
      highlights: highlights.isEmpty ? ["Weitere Verbesserungen und Fehlerbehebungen in TAKT."] : highlights,
      socialPreview: nil,
      previewIntro: nil,
      previewImageNames: [],
      betaSignup: nil,
      cta: nil,
      showsWeeklyFeedbackSurvey: false
    )
  }

  private static var currentAppVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  }

  /// Compare two semantic version strings. Returns true if lhs <= rhs.
  private static func isVersion(_ lhs: String, lessThanOrEqualTo rhs: String) -> Bool {
    let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
    let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }

    for i in 0..<max(lhsParts.count, rhsParts.count) {
      let lhsVal = i < lhsParts.count ? lhsParts[i] : 0
      let rhsVal = i < rhsParts.count ? rhsParts[i] : 0
      if lhsVal < rhsVal { return true }
      if lhsVal > rhsVal { return false }
    }
    return true
  }
}

// MARK: - What's New View

struct WhatsNewView: View {
  let releaseNote: ReleaseNote
  let onDismiss: () -> Void

  @Environment(\.openURL) private var openURL
  @AppStorage("whatsNewWeeklyFeedbackSubmittedVersion") private var submittedWeeklyFeedbackVersion =
    ""
  @State private var selectedWeeklyFeedback: WhatsNewWeeklyFeedback?
  @State private var weeklyImprovementText = ""
  @State private var releaseSurveyResponseID = ""
  @State private var isSubmittingWeeklyFeedback = false
  @State private var surveyErrorText: String?
  @State private var didHydrateSurveyState = false
  @AppStorage("whatsNewAgentsBetaSubmittedVersion") private var submittedAgentsBetaVersion = ""
  @State private var selectedAgentsPerDay: AgentsPerDayOption?
  @State private var agentsBetaEmail = ""
  @State private var agentsBetaCompany = ""
  @State private var agentsBetaResponseID = ""
  @State private var isSubmittingAgentsBeta = false
  @State private var agentsBetaErrorText: String?

  private let bottomAnchorID = "whats_new_bottom_anchor"
  private let releaseSurveyKey = "weekly_feedback"
  private let agentsBetaSurveyKey = "agents_beta"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text("What's New in \(releaseNote.version) 🎉")
              .font(.custom("InstrumentSerif-Regular", size: 32))
              .foregroundColor(.black.opacity(0.9))

            Text(releaseNote.title)
              .font(.custom("Figtree", size: 17))
              .fontWeight(.semibold)
              .foregroundColor(.black.opacity(0.78))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()

          Button(action: dismiss) {
            Image(systemName: "xmark")
              .font(.system(size: 13, weight: .semibold))
              .padding(8)
              .background(Color.black.opacity(0.05))
              .clipShape(Circle())
          }
          .buttonStyle(PlainButtonStyle())
          .pointingHandCursor()
          .accessibilityLabel("Close")
          .keyboardShortcut(.cancelAction)
        }

        if !releaseNote.highlights.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(releaseNote.highlights.enumerated()), id: \.offset) { _, highlight in
              HStack(alignment: .top, spacing: 12) {
                Circle()
                  .fill(Color(red: 0.25, green: 0.17, blue: 0).opacity(0.6))
                  .frame(width: 6, height: 6)
                  .padding(.top, 7)

                Text(highlight)
                  .font(.custom("Figtree", size: 15))
                  .foregroundColor(.black.opacity(0.75))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }

        if let betaSignup = releaseNote.betaSignup {
          Label(betaSignup.followUp, systemImage: "chart.bar.xaxis")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(.black.opacity(0.58))
        }

        if releaseNote.showsWeeklyFeedbackSurvey {
          surveySection
        }

        if let socialPreview = releaseNote.socialPreview {
          socialPreviewSection(socialPreview)
        }

        if let previewIntro = releaseNote.previewIntro,
          previewIntro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
          Text(previewIntro)
            .font(.custom("Figtree", size: 14))
            .foregroundColor(.black.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }

        if !releaseNote.previewImageNames.isEmpty {
          VStack(spacing: 16) {
            ForEach(releaseNote.previewImageNames, id: \.self) { imageName in
              Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.985, green: 0.985, blue: 0.985))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
          }
          // Let previews use more horizontal space than text for better readability.
          .padding(.top, 6)
          .padding(.horizontal, -36)
        }

        if let betaSignup = releaseNote.betaSignup {
          agentsBetaSignupSection(betaSignup)
        }

        if let cta = releaseNote.cta {
          ctaSection(cta)
        }

        Color.clear
          .frame(height: 1)
          .id(bottomAnchorID)
      }
      .padding(.horizontal, 44)
      .padding(.vertical, 36)
    }
    .frame(maxHeight: 760)
    .frame(width: 780)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white)
        .shadow(color: Color.black.opacity(0.25), radius: 40, x: 0, y: 20)
    )
    .onAppear {
      AnalyticsService.shared.screen("whats_new")
      if releaseNote.showsWeeklyFeedbackSurvey && didHydrateSurveyState == false {
        hydrateSurveyStateIfNeeded()
        didHydrateSurveyState = true
      }
      if releaseNote.betaSignup != nil && agentsBetaResponseID.isEmpty {
        agentsBetaResponseID = loadResponseID(for: agentsBetaSurveyKey)
      }
    }
    .environment(\.colorScheme, .light)
    .preferredColorScheme(.light)
  }

  private func dismiss() {
    AnalyticsService.shared.capture(
      "whats_new_dismissed",
      [
        "version": releaseNote.version,
        "provider_label": currentProviderLabel,
      ])

    onDismiss()
  }

  private var surveySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("How do you feel about Weekly so far?")
        .font(.custom("Figtree", size: 15))
        .fontWeight(.semibold)
        .foregroundColor(.black.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)

      Text(
        "A quick answer helps shape where Weekly goes next."
      )
      .font(.custom("Figtree", size: 13))
      .foregroundColor(.black.opacity(0.62))
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        ForEach(WhatsNewWeeklyFeedback.allCases) { option in
          weeklyFeedbackButton(option)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("How can we improve Weekly?")
          .font(.custom("Figtree", size: 15))
          .fontWeight(.semibold)
          .foregroundColor(.black.opacity(0.85))

        WhatsNewSurveyTextEditor(
          text: $weeklyImprovementText,
          placeholder: "New visualizations, data, comparisons, breakdowns, anything missing..."
        )
        .frame(minHeight: 78)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
      }
      .padding(.top, 4)

      if let surveyErrorText {
        Text(surveyErrorText)
          .font(.custom("Figtree", size: 13))
          .foregroundColor(Color.red.opacity(0.75))
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 12) {
        DayflowSurfaceButton(
          action: submitWeeklyFeedbackFromButton,
          content: {
            HStack(spacing: 8) {
              Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
              Text(isSubmittingWeeklyFeedback ? "Saving..." : "Send feedback")
                .font(.custom("Figtree", size: 14))
                .fontWeight(.semibold)
            }
          },
          background: Color(red: 0.25, green: 0.17, blue: 0),
          foreground: .white,
          borderColor: .clear,
          cornerRadius: 8,
          horizontalPadding: 14,
          verticalPadding: 9,
          showOverlayStroke: true
        )
        .disabled(isSubmittingWeeklyFeedback)
        .opacity(isSubmittingWeeklyFeedback ? 0.72 : 1)
        .pointingHandCursor()

        if hasSubmittedWeeklyFeedback {
          Label("Saved.", systemImage: "checkmark.circle.fill")
            .font(.custom("Figtree", size: 14))
            .foregroundColor(Color(red: 0.25, green: 0.17, blue: 0))
        }
      }
    }
    .padding(.top, 10)
    .environment(\.colorScheme, .light)
    .preferredColorScheme(.light)
  }

  private func weeklyFeedbackButton(_ option: WhatsNewWeeklyFeedback) -> some View {
    let isSelected = selectedWeeklyFeedback == option

    return Button(action: {
      selectWeeklyFeedback(option)
    }) {
      HStack(spacing: 8) {
        Text(option.title)
          .font(.custom("Figtree", size: 14))
          .fontWeight(isSelected ? .semibold : .regular)
          .foregroundColor(.black.opacity(0.82))
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            isSelected
              ? Color(red: 0.25, green: 0.17, blue: 0).opacity(0.06)
              : Color.white
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            isSelected
              ? Color(red: 0.25, green: 0.17, blue: 0).opacity(0.28)
              : Color.black.opacity(0.1),
            lineWidth: 1
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(isSubmittingWeeklyFeedback)
    .pointingHandCursor()
  }

  private func agentsBetaSignupSection(_ signup: ReleaseNoteBetaSignup) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(signup.title)
          .font(.custom("Figtree", size: 17))
          .fontWeight(.bold)
          .foregroundColor(.black.opacity(0.86))

        Text(signup.description)
          .font(.custom("Figtree", size: 14))
          .foregroundColor(.black.opacity(0.68))
      }

      if hasSubmittedAgentsBeta {
        Label("You're on the beta list.", systemImage: "checkmark.circle.fill")
          .font(.custom("Figtree", size: 14))
          .fontWeight(.semibold)
          .foregroundColor(Color(red: 0.25, green: 0.17, blue: 0))
          .padding(.vertical, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("How many agents do you launch per day?")
            .font(.custom("Figtree", size: 14))
            .fontWeight(.semibold)
            .foregroundColor(.black.opacity(0.82))

          HStack(spacing: 8) {
            ForEach(AgentsPerDayOption.allCases) { option in
              agentsPerDayButton(option)
            }
          }
        }

        HStack(alignment: .top, spacing: 10) {
          agentsBetaTextField(
            title: "Email",
            placeholder: "you@company.com",
            text: $agentsBetaEmail,
            isRequired: true
          )

          agentsBetaTextField(
            title: "Company",
            placeholder: "Optional",
            text: $agentsBetaCompany,
            isRequired: false
          )
        }

        if let agentsBetaErrorText {
          Text(agentsBetaErrorText)
            .font(.custom("Figtree", size: 13))
            .foregroundColor(Color.red.opacity(0.75))
        }

        DayflowSurfaceButton(
          action: submitAgentsBeta,
          content: {
            HStack(spacing: 8) {
              if isSubmittingAgentsBeta {
                ProgressView()
                  .controlSize(.small)
                  .tint(.white)
              }

              Text(isSubmittingAgentsBeta ? "Joining..." : "Join the beta")
                .font(.custom("Figtree", size: 14))
                .fontWeight(.semibold)
            }
          },
          background: Color(red: 0.25, green: 0.17, blue: 0),
          foreground: .white,
          borderColor: .clear,
          cornerRadius: 8,
          horizontalPadding: 16,
          verticalPadding: 10,
          showOverlayStroke: true
        )
        .disabled(isSubmittingAgentsBeta)
        .opacity(isSubmittingAgentsBeta ? 0.72 : 1)
        .pointingHandCursor()
      }
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(red: 0.985, green: 0.975, blue: 0.955))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color(red: 0.25, green: 0.17, blue: 0).opacity(0.1), lineWidth: 1)
    )
    .padding(.top, 4)
  }

  private func agentsPerDayButton(_ option: AgentsPerDayOption) -> some View {
    let isSelected = selectedAgentsPerDay == option

    return Button {
      selectedAgentsPerDay = option
      agentsBetaErrorText = nil
    } label: {
      Text(option.title)
        .font(.custom("Figtree", size: 13))
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundColor(.black.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.white : Color.white.opacity(0.55))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              isSelected
                ? Color(red: 0.25, green: 0.17, blue: 0).opacity(0.35)
                : Color.black.opacity(0.09),
              lineWidth: 1
            )
        )
    }
    .buttonStyle(.plain)
    .disabled(isSubmittingAgentsBeta)
    .pointingHandCursor()
  }

  private func agentsBetaTextField(
    title: String,
    placeholder: String,
    text: Binding<String>,
    isRequired: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 3) {
        Text(title)
          .font(.custom("Figtree", size: 13))
          .fontWeight(.semibold)
          .foregroundColor(.black.opacity(0.78))

        if isRequired {
          Text("*")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(.black.opacity(0.42))
        }
      }

      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.custom("Figtree", size: 14))
        .foregroundColor(.black.opacity(0.84))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .disabled(isSubmittingAgentsBeta)
    }
    .frame(maxWidth: .infinity)
  }

  private func ctaSection(_ cta: ReleaseNoteCTA) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(cta.title)
        .font(.custom("Figtree", size: 16))
        .fontWeight(.bold)
        .foregroundColor(.black.opacity(0.86))

      Text(cta.description)
        .font(.custom("Figtree", size: 14))
        .foregroundColor(.black.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)

      DayflowSurfaceButton(
        action: { openCTA(cta) },
        content: {
          HStack(spacing: 8) {
            Image(systemName: "calendar")
              .font(.system(size: 12, weight: .semibold))
            Text(cta.buttonTitle)
              .font(.custom("Figtree", size: 14))
              .fontWeight(.semibold)
          }
        },
        background: Color(red: 0.25, green: 0.17, blue: 0),
        foreground: .white,
        borderColor: .clear,
        cornerRadius: 8,
        horizontalPadding: 16,
        verticalPadding: 10,
        showOverlayStroke: true
      )
      .pointingHandCursor()
    }
    .padding(.top, 6)
  }

  /// TAKT: Statische Karte — kein X/Twitter-Webview-Embed, kein externes
    /// Twitter-Widget-Script. Der Link öffnet den Tweet bei Klick im Browser.
    @ViewBuilder
    private func socialPreviewSection(_ preview: ReleaseNoteSocialPreview) -> some View {
      socialPreviewCard(preview)
    }

  private func socialPreviewCard(_ preview: ReleaseNoteSocialPreview) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 10) {
        Text("J")
          .font(.custom("Figtree", size: 16))
          .fontWeight(.bold)
          .foregroundColor(.white)
          .frame(width: 36, height: 36)
          .background(
            Circle()
              .fill(Color(red: 0.25, green: 0.17, blue: 0))
          )

        VStack(alignment: .leading, spacing: 2) {
          Text(preview.authorName)
            .font(.custom("Figtree", size: 14))
            .fontWeight(.semibold)
            .foregroundColor(.black.opacity(0.86))

          Text("\(preview.authorHandle) - \(preview.dateText)")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(.black.opacity(0.48))
        }

        Spacer()
      }

      Text(preview.body)
        .font(.custom("Figtree", size: 15))
        .foregroundColor(.black.opacity(0.78))
        .fixedSize(horizontal: false, vertical: true)

      Button(action: { openSocialPreview(preview) }) {
        HStack(spacing: 6) {
          Text("View on X")
            .font(.custom("Figtree", size: 14))
            .fontWeight(.semibold)
          Image(systemName: "arrow.up.right")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(Color(red: 0.25, green: 0.17, blue: 0))
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(red: 0.985, green: 0.982, blue: 0.972))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.black.opacity(0.08), lineWidth: 1)
    )
    .padding(.top, 2)
  }

  private func openSocialPreview(_ preview: ReleaseNoteSocialPreview) {
    guard let url = URL(string: preview.url) else { return }
    AnalyticsService.shared.capture(
      "whats_new_social_preview_opened",
      [
        "version": releaseNote.version,
        "preview_url": preview.url,
        "provider_label": currentProviderLabel,
      ])
    openURL(url)
  }

  private func openCTA(_ cta: ReleaseNoteCTA) {
    guard let url = URL(string: cta.url) else { return }
    AnalyticsService.shared.capture(
      "whats_new_cta_opened",
      [
        "version": releaseNote.version,
        "cta_title": cta.title,
        "cta_url": cta.url,
        "provider_label": currentProviderLabel,
      ])
    openURL(url)
  }

  private var hasSubmittedWeeklyFeedback: Bool {
    submittedWeeklyFeedbackVersion == releaseNote.version
  }

  private var hasSubmittedAgentsBeta: Bool {
    submittedAgentsBetaVersion == releaseNote.version
  }

  private func selectWeeklyFeedback(_ option: WhatsNewWeeklyFeedback) {
    let previousSelection = selectedWeeklyFeedback
    selectedWeeklyFeedback = option
    persistWeeklyFeedbackState()
    surveyErrorText = nil

    Task {
      if await submitReleaseSurvey() {
        submittedWeeklyFeedbackVersion = releaseNote.version
      } else {
        selectedWeeklyFeedback = previousSelection
        persistWeeklyFeedbackState()
      }
    }
  }

  private func submitWeeklyFeedbackFromButton() {
    persistWeeklyFeedbackState()
    surveyErrorText = nil

    Task {
      if await submitReleaseSurvey() {
        submittedWeeklyFeedbackVersion = releaseNote.version
      }
    }
  }

  private func persistWeeklyFeedbackState() {
    if let selectedWeeklyFeedback {
      UserDefaults.standard.set(
        selectedWeeklyFeedback.rawValue, forKey: selectedFeedbackStorageKey)
    } else {
      UserDefaults.standard.removeObject(forKey: selectedFeedbackStorageKey)
    }

    UserDefaults.standard.set(weeklyImprovementText, forKey: improvementStorageKey)
  }

  private func hydrateSurveyStateIfNeeded() {
    if let storedFeedback = UserDefaults.standard.string(forKey: selectedFeedbackStorageKey) {
      selectedWeeklyFeedback = WhatsNewWeeklyFeedback(rawValue: storedFeedback)
    }
    weeklyImprovementText = UserDefaults.standard.string(forKey: improvementStorageKey) ?? ""
    releaseSurveyResponseID = loadResponseID(for: releaseSurveyKey)
  }

  private var selectedFeedbackStorageKey: String {
    "whatsNewWeeklyFeedback_\(releaseSurveyKey)_\(releaseNote.version)"
  }

  private var improvementStorageKey: String {
    "whatsNewWeeklyImprovement_\(releaseSurveyKey)_\(releaseNote.version)"
  }

  private func responseIDStorageKey(for surveyKey: String) -> String {
    "whatsNewReleaseSurveyResponseID_\(surveyKey)_\(releaseNote.version)"
  }

  private func loadResponseID(for surveyKey: String) -> String {
    let defaults = UserDefaults.standard
    let storageKey = responseIDStorageKey(for: surveyKey)
    if let existing = defaults.string(forKey: storageKey),
      !existing.isEmpty
    {
      return existing
    }

    let generated = UUID().uuidString.lowercased()
    defaults.set(generated, forKey: storageKey)
    return generated
  }

  private func submitReleaseSurvey() async -> Bool {
    isSubmittingWeeklyFeedback = true

    defer {
      isSubmittingWeeklyFeedback = false
    }

    do {
      let responseID =
        releaseSurveyResponseID.isEmpty
        ? loadResponseID(for: releaseSurveyKey) : releaseSurveyResponseID
      releaseSurveyResponseID = responseID
      let trimmedImprovement = weeklyImprovementText.trimmingCharacters(
        in: .whitespacesAndNewlines)
      try await ReleaseSurveyClient.submit(
        ReleaseSurveyPayload(
          responseID: responseID,
          surveyKey: releaseSurveyKey,
          version: releaseNote.version,
          selectedOption: selectedWeeklyFeedback?.rawValue,
          improvementText: trimmedImprovement.isEmpty ? nil : trimmedImprovement,
          appVersion: appVersion,
          analyticsOptIn: AnalyticsService.shared.isOptedIn,
          providerLabel: currentProviderLabel
        )
      )
      surveyErrorText = nil
      return true
    } catch {
      surveyErrorText = "Could not submit. Please try again."
      return false
    }
  }

  private func submitAgentsBeta() {
    agentsBetaErrorText = nil

    guard let selectedAgentsPerDay else {
      agentsBetaErrorText = "Choose how many agents you launch per day."
      return
    }

    let email = agentsBetaEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isLikelyValidEmail(email) else {
      agentsBetaErrorText = "Enter a valid email address."
      return
    }

    let company = agentsBetaCompany.trimmingCharacters(in: .whitespacesAndNewlines)
    let contact = company.isEmpty ? email : "\(email) | \(company)"
    guard contact.count <= 200 else {
      agentsBetaErrorText = "Email and company must be under 200 characters combined."
      return
    }

    isSubmittingAgentsBeta = true

    Task {
      defer { isSubmittingAgentsBeta = false }

      do {
        let responseID =
          agentsBetaResponseID.isEmpty
          ? loadResponseID(for: agentsBetaSurveyKey) : agentsBetaResponseID
        agentsBetaResponseID = responseID

        try await ReleaseSurveyClient.submit(
          ReleaseSurveyPayload(
            responseID: responseID,
            surveyKey: agentsBetaSurveyKey,
            version: releaseNote.version,
            selectedOption: selectedAgentsPerDay.rawValue,
            improvementText: contact,
            appVersion: appVersion,
            analyticsOptIn: AnalyticsService.shared.isOptedIn,
            providerLabel: currentProviderLabel
          )
        )

        submittedAgentsBetaVersion = releaseNote.version
        agentsBetaEmail = ""
        agentsBetaCompany = ""
        agentsBetaErrorText = nil
      } catch {
        agentsBetaErrorText = "Could not join the beta. Please try again."
      }
    }
  }

  private func isLikelyValidEmail(_ email: String) -> Bool {
    guard email.count <= 254, !email.contains(where: \.isWhitespace) else {
      return false
    }

    let parts = email.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return false }
    return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
  }

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? releaseNote.version
  }

  private var currentProviderLabel: String {
    (try? LLMProviderRoutingStore.load())?.primary.providerLabel ?? "unknown"
  }
}

private struct ReleaseSurveyPayload: Encodable {
  let responseID: String
  let surveyKey: String
  let version: String
  let selectedOption: String?
  let improvementText: String?
  let appVersion: String
  let analyticsOptIn: Bool
  let providerLabel: String

  enum CodingKeys: String, CodingKey {
    case responseID = "response_id"
    case surveyKey = "survey_key"
    case version
    case selectedOption = "pro_interest"
    case improvementText = "pro_price"
    case appVersion = "app_version"
    case analyticsOptIn = "analytics_opt_in"
    case providerLabel = "provider_label"
  }
}

private enum ReleaseSurveyClient {
  /// TAKT ist privacy-first: Survey-Antworten bleiben lokal auf diesem Mac
  /// (UserDefaults) und werden nicht an ein Dayflow-Backend gesendet.
  static func submit(_ payload: ReleaseSurveyPayload) async throws {
    let defaults = UserDefaults.standard
    let storageKey = "takt.survey.\(payload.surveyKey)"
    if let data = try? JSONEncoder().encode(payload) {
      defaults.set(data, forKey: storageKey)
    }
    if let responseID = payload.responseID.isEmpty ? nil : payload.responseID {
      defaults.set(responseID, forKey: "takt.survey.responseID.\(payload.surveyKey)")
    }
  }
}

private struct WhatsNewSurveyTextEditor: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String
  var isEditable: Bool = true

  private let fontSize: CGFloat = 14
  private let textInsets = NSSize(width: 14, height: 12)

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.focusRingType = .none
    scrollView.appearance = NSAppearance(named: .aqua)

    let textView = PlaceholderTextView()
    textView.delegate = context.coordinator
    textView.placeholder = placeholder
    textView.font = NSFont(name: "Figtree", size: fontSize) ?? .systemFont(ofSize: fontSize)
    textView.textColor = NSColor.black.withAlphaComponent(0.82)
    textView.insertionPointColor = .systemBlue
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.focusRingType = .none
    textView.appearance = NSAppearance(named: .aqua)
    textView.isRichText = false
    textView.importsGraphics = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.autoresizingMask = [.width]
    textView.textContainerInset = textInsets
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.string = text

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    nsView.appearance = NSAppearance(named: .aqua)

    guard let textView = nsView.documentView as? PlaceholderTextView else { return }

    if textView.string != text {
      textView.string = text
    }

    textView.placeholder = placeholder
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.appearance = NSAppearance(named: .aqua)
    textView.needsDisplay = true
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding private var text: String

    init(text: Binding<String>) {
      _text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text = textView.string
      textView.needsDisplay = true
    }
  }
}

private final class PlaceholderTextView: NSTextView {
  var placeholder = "" {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard string.isEmpty, let font else { return }

    let placeholderRect = NSRect(
      x: textContainerInset.width,
      y: textContainerInset.height,
      width: bounds.width - (textContainerInset.width * 2),
      height: (font.ascender - font.descender + font.leading) * 2
    )

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.black.withAlphaComponent(0.35),
    ]

    (placeholder as NSString).draw(
      with: placeholderRect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attributes
    )
  }

  override func didChangeText() {
    super.didChangeText()
    needsDisplay = true
  }
}

// MARK: - Preview

struct WhatsNewView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      if let note = WhatsNewConfiguration.configuredRelease {
        WhatsNewView(
          releaseNote: note,
          onDismiss: { print("Dismissed") }
        )
        .frame(width: 1200, height: 800)
      } else {
        Text("Configure WhatsNewConfiguration.configuredRelease to preview.")
          .frame(width: 780, height: 400)
      }
    }
  }
}
