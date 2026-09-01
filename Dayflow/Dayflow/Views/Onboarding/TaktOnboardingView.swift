//
//  TaktOnboardingView.swift
//  Dayflow
//
//  TAKT: minimal 5-step onboarding (de-CH) — welcome (Wertwandler) → LLM
//  provider (Nous / OpenAI-compatible) → first client → screen permission →
//  done. Square, token-based, no marketing videos, no analytics gates.
//  Replaces the Dayflow wizard.
//

import SwiftUI

// MARK: - Flow state

enum TaktOnboardingStep: Int, CaseIterable {
  case welcome
  case provider
  case firstClient
  case screenPermission
  case completion
}

// MARK: - Root view

struct TaktOnboardingView: View {
  @AppStorage("didOnboard") private var didOnboard = false
  @State private var step: TaktOnboardingStep = .screenPermission

  var body: some View {
    ZStack {
      TaktColor.surface.ignoresSafeArea()

      VStack(spacing: 0) {
        header
        Spacer(minLength: 0)
        stepContent
          .frame(maxWidth: 560)
          .transition(.opacity)
        Spacer(minLength: 0)
        footer
      }
      .padding(.horizontal, 48)
      .padding(.vertical, 32)
    }
    .frame(minWidth: 900, minHeight: 600)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      HStack(spacing: 10) {
        // TAKT wordmark (metronome mark asset)
        Image("DayflowLogoMainApp")
          .resizable()
          .scaledToFit()
          .frame(height: 28)
        Text("TAKT")
          .font(TaktFont.title)
          .foregroundColor(TaktColor.ink)
      }

      Spacer()

      // Step indicator: square segments, filled = done
      HStack(spacing: 6) {
        ForEach(TaktOnboardingStep.allCases, id: \.self) { s in
          Rectangle()
            .fill(s.rawValue <= step.rawValue ? TaktColor.accent : TaktColor.borderGrid)
            .frame(width: 28, height: 4)
        }
      }
    }
  }

  // MARK: - Step content

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .welcome:
      welcomeStep
    case .provider:
      providerStep
    case .firstClient:
      firstClientStep
    case .screenPermission:
      screenPermissionStep
    case .completion:
      completionStep
    }
  }

  // MARK: - Footer

  @ViewBuilder
  private var footer: some View {
    if step != .welcome && step != .completion {
      HStack {
        if step == .provider || step == .firstClient || step == .screenPermission {
          Button(action: { goBack() }) {
            Text("Zurück")
              .font(TaktFont.ui(14))
              .foregroundColor(TaktColor.textSecondary)
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
        }
        Spacer()
      }
    }
  }

  // MARK: - Step 1: Welcome

  private var welcomeStep: some View {
    VStack(spacing: 28) {
      Image("WertwandlerMark")
        .resizable()
        .scaledToFit()
        .frame(width: 84, height: 84)

      VStack(spacing: 10) {
        Text("Willkommen bei TAKT")
          .font(TaktFont.display(32).weight(.semibold))
          .foregroundColor(TaktColor.ink)
        Text(
          "TAKT erfasst automatisch, was du am Mac arbeitest — ohne dass du "
            + "etwas notierst. Am Ende des Tages zeigt dir die Timeline, wo deine "
            + "Zeit wirklich geblieben ist."
        )
        .font(TaktFont.body)
        .foregroundColor(TaktColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 470)
      }

      VStack(alignment: .leading, spacing: 12) {
        featureRow(
          "Aufzeichnung",
          "Deine Bildschirm-Aktivität wird lokal erfasst und zu Karten zusammengefasst."
        )
        featureRow(
          "Erkennung",
          "TAKT erkennt selbst, für welchen Kunden du arbeitest — Kategorien und Projekte folgen daraus."
        )
        featureRow(
          "KI-Chat",
          "Frag deinen Tag ab: »Was habe ich heute für die Klinik Zürich gemacht?«"
        )
      }
      .frame(maxWidth: 470, alignment: .leading)

      TaktButton(title: "Los geht's", variant: .primary, action: advance)
        .padding(.top, 8)
    }
  }

  private func featureRow(_ title: String, _ subtitle: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Rectangle()
        .fill(TaktColor.accent)
        .frame(width: 6, height: 6)
        .padding(.top, 7)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(TaktFont.ui(14, .semibold))
          .foregroundColor(TaktColor.ink)
        Text(subtitle)
          .font(TaktFont.caption)
          .foregroundColor(TaktColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Step 4: Screen recording permission

  /// Overridable for UI tests / previews: gate the real TCC check.
  /// Set via `defaults write ch.wertwandler.takt TAKTForceScreenAccess -bool true`
  /// (only honoured in DEBUG builds).
  static var screenCaptureAccessOverride: Bool? {
    #if DEBUG
    if UserDefaults.standard.object(forKey: "TAKTForceScreenAccess") != nil {
      return UserDefaults.standard.bool(forKey: "TAKTForceScreenAccess")
    }
    #endif
    return nil
  }

  private var hasScreenCaptureAccess: Bool {
    if let override = Self.screenCaptureAccessOverride {
      return override
    }
    return CGPreflightScreenCaptureAccess()
  }

  private var screenPermissionStep: some View {
    VStack(spacing: 24) {
      titleBlock(
        "Bildschirm-Erlaubnis",
        "Ein letzter Schritt: TAKT erfasst, was du am Mac machst, und fasst es "
          + "zu Aktivitätskarten zusammen. Dafür braucht die App Zugriff auf deinen Bildschirm."
      )

      if hasScreenCaptureAccess {
        permissionGranted
        TaktButton(title: "Weiter", variant: .primary, action: advance)
          .padding(.top, 8)
      } else {
        Button(action: requestScreenPermission) {
          permissionButtonLabel("Erlaubnis erteilen")
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
    }
    .onAppear {
      // Auto-advance when permission already granted (e.g. re-onboarding).
      if hasScreenCaptureAccess {
        advance()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      // After the user returns from System Settings, re-check and move on.
      if hasScreenCaptureAccess {
        advance()
      }
    }
  }

  private var permissionGranted: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 34))
        .foregroundColor(TaktColor.positive)
      Text("Bereits erteilt — weiter geht’s.")
        .font(TaktFont.body)
        .foregroundColor(TaktColor.textSecondary)
    }
  }

  private func permissionButtonLabel(_ text: String) -> some View {
    Text(text)
      .font(TaktFont.ui(15, .semibold))
      .foregroundColor(.white)
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      .background(TaktColor.accent)
      .overlay(Rectangle().stroke(TaktColor.accentPressed, lineWidth: 1))
  }

  private func requestScreenPermission() {
    // Correct API for Screen Recording (TCC): CGRequestScreenCaptureAccess
    // shows the system prompt and registers this app in System Settings →
    // Privacy → Screen & System Audio Recording. (AXIsProcessTrustedWithOptions
    // would request Assistive Access instead — wrong category.)
    _ = CGRequestScreenCaptureAccess()
    // Re-check immediately; if granted, advance. Otherwise the
    // didBecomeActive handler picks it up when the user returns.
    if CGPreflightScreenCaptureAccess() {
      advance()
    }
  }

  // MARK: - Step 2: LLM provider (Nous / OpenAI-compatible)

  @State private var baseURL = "https://inference-api.nousresearch.com/v1"
  @State private var modelID = "deepseek/deepseek-v4-flash"
  @State private var apiKey = ""
  @State private var testState: TestState = .idle

  private enum TestState {
    case idle, testing, ok, failed(String)
  }

  private var providerStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      titleBlock(
        "LLM-Anbieter",
        "Die KI erkennt später automatisch, für welchen Kunden du arbeitest. "
          + "Standard ist Nous Portal (OpenAI-kompatibel) — passe Base-URL, Modell "
          + "und API-Schlüssel an, falls du etwas anderes nutzt."
      )

      VStack(alignment: .leading, spacing: 6) {
        label("Base-URL")
        TextField("https://…/v1", text: $baseURL)
          .textFieldStyle(.plain)
          .font(TaktFont.ui(14))
          .padding(10)
          .background(TaktColor.surface)
          .overlay(Rectangle().stroke(TaktColor.borderStrong, lineWidth: 1))
      }

      VStack(alignment: .leading, spacing: 6) {
        label("Modell")
        TextField("z. B. deepseek/deepseek-v4-flash", text: $modelID)
          .textFieldStyle(.plain)
          .font(TaktFont.ui(14))
          .padding(10)
          .background(TaktColor.surface)
          .overlay(Rectangle().stroke(TaktColor.borderStrong, lineWidth: 1))
      }

      VStack(alignment: .leading, spacing: 6) {
        label("API-Schlüssel")
        SecureField("sk-…", text: $apiKey)
          .textFieldStyle(.plain)
          .font(TaktFont.ui(14))
          .padding(10)
          .background(TaktColor.surface)
          .overlay(Rectangle().stroke(TaktColor.borderStrong, lineWidth: 1))
      }

      HStack(spacing: 12) {
        TaktButton(
          title: "Verbindung testen",
          variant: .secondary,
          action: testConnection
        )

        if case .testing = testState {
          ProgressView().controlSize(.small)
        }
        if case .ok = testState {
          Text("Verbindung OK")
            .font(TaktFont.caption)
            .foregroundColor(TaktColor.positive)
        }
        if case .failed(let msg) = testState {
          Text(msg)
            .font(TaktFont.caption)
            .foregroundColor(TaktColor.negative)
            .lineLimit(2)
        }
      }

      HStack {
        Spacer()
        TaktButton(
          title: "Weiter",
          variant: .primary,
          action: {
            saveProvider()
            advance()
          }
        )
        .disabled(baseURL.trimmingCharacters(in: .whitespaces).isEmpty
          || modelID.trimmingCharacters(in: .whitespaces).isEmpty
          || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text.uppercased())
      .font(TaktFont.label)
      .kerning(1.2)
      .foregroundColor(TaktColor.textLabel)
  }

  private func testConnection() {
    testState = .testing
    let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedBase.isEmpty, !trimmedModel.isEmpty else {
      testState = .failed("Base-URL und Modell angeben.")
      return
    }

    let config = OpenAICompatibleConfiguration(
      preset: .custom, baseURL: trimmedBase, modelID: trimmedModel)

    Task { @MainActor in
      do {
        let ok = try await verifyOpenAICompatible(
          config: config, apiKey: trimmedKey)
        testState = ok ? .ok : .failed("Antwort des Anbieters nicht lesbar.")
      } catch {
        testState = .failed("Fehler: \(error.localizedDescription)")
      }
    }
  }

  private func saveProvider() {
    let config = OpenAICompatibleConfiguration(
      preset: .custom,
      baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    _ = OpenAICompatiblePreferences.save(config)

    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedKey.isEmpty {
      _ = KeychainManager.shared.store(trimmedKey, for: OpenAICompatiblePreferences.keychainProvider)
    }

    // TAKT: Chat, Timeline und Daily-Recap folgen dem app-weiten Routing
    // (LLMProviderRoutingStore.primary). Ohne diesen Eintrag bliebe der
    // Provider aus dem Legacy-Default aktiv und der Chat wäre tot — der
    // eingerichtete OpenAI-kompatible Anbieter wird daher hier primär.
    try? LLMProviderRoutingStore.save(
      LLMProviderRouting(primary: .openAICompatible))
  }

  // MARK: - Step 3: First client

  @State private var clientName = ""
  @State private var clientDetail = ""

  private var firstClientStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      titleBlock(
        "Erster Kunde",
        "Lege deinen ersten Kunden mit einer kurzen Beschreibung an — so kann die KI "
          + "deine Aktivitäten später automatisch zuordnen."
      )

      VStack(alignment: .leading, spacing: 6) {
        label("Kundenname")
        TextField("z. B. Healthcare-Klinik Zürich", text: $clientName)
          .textFieldStyle(.plain)
          .font(TaktFont.ui(14))
          .padding(10)
          .background(TaktColor.surface)
          .overlay(Rectangle().stroke(TaktColor.borderStrong, lineWidth: 1))
      }

      VStack(alignment: .leading, spacing: 6) {
        label("Beschreibung (optional, hilft der Erkennung)")
        TextField("z. B. Team-Coaching, Vertraulichkeit", text: $clientDetail)
          .textFieldStyle(.plain)
          .font(TaktFont.ui(14))
          .padding(10)
          .background(TaktColor.surface)
          .overlay(Rectangle().stroke(TaktColor.borderStrong, lineWidth: 1))
      }

      HStack {
        Spacer()
        TaktButton(
          title: "Weiter",
          variant: .primary,
          action: {
            saveFirstClient()
            advance()
          }
        )
        .disabled(clientName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }

  private func saveFirstClient() {
    let trimmedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let trimmedDetail = clientDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = StorageManager.shared.saveClient(
      Client(
        id: nil,
        name: trimmedName,
        detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
        color: nil,
        defaultBillable: false
      )
    )
  }

  // MARK: - Step 5: Completion

  private var completionStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 44))
        .foregroundColor(TaktColor.positive)

      Text("Bereit!")
        .font(TaktFont.display(32).weight(.semibold))
        .foregroundColor(TaktColor.ink)

      Text(
        "TAKT läuft jetzt im Hintergrund und erfasst deine Aktivitäten. "
          + "In den Einstellungen kannst du jederzeit Anbieter, Kunden und Projekte anpassen."
      )
      .font(TaktFont.body)
      .foregroundColor(TaktColor.textSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      TaktButton(
        title: "TAKT starten",
        variant: .primary,
        action: finish
      )
    }
  }

  // MARK: - Navigation

  private func advance() {
    withAnimation(.easeInOut(duration: 0.18)) {
      switch step {
      case .welcome:
        step = .provider
      case .provider:
        step = .firstClient
      case .firstClient:
        step = .screenPermission
      case .screenPermission:
        step = .completion
      case .completion:
        break
      }
    }
  }

  private func goBack() {
    withAnimation(.easeInOut(duration: 0.18)) {
      switch step {
      case .provider:
        step = .welcome
      case .firstClient:
        step = .provider
      case .screenPermission:
        step = .firstClient
      default:
        break
      }
    }
  }

  private func finish() {
    // TAKT: Persistenz aktivieren und — sofern die Bildschirm-Erlaubnis
    // erteilt ist — das Recording in dieser Session starten. Beim nächsten
    // App-Start übernimmt AppDelegate (Auto-Start mit gespeicherter Präferenz).
    AppState.shared.enablePersistence()
    if CGPreflightScreenCaptureAccess() {
      RecordingControl.start(reason: "onboarding_complete")
    }
    didOnboard = true
  }

  // MARK: - Shared

  private func titleBlock(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(TaktFont.display(28).weight(.semibold))
        .foregroundColor(TaktColor.ink)
      Text(subtitle)
        .font(TaktFont.body)
        .foregroundColor(TaktColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Verification helper (isolated, testable)

func verifyOpenAICompatible(config: OpenAICompatibleConfiguration, apiKey: String) async throws -> Bool {
  struct PingRequest: Encodable {
    let model: String
    let messages: [[String: String]]
    let max_tokens: Int
  }
  struct PingResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
      }
      let message: Message
    }
    let choices: [Choice]
  }

  guard let url = config.chatCompletionsURL else { return false }

  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  // Nous Portal is behind Cloudflare bot protection; browser UA required.
  request.setValue(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    forHTTPHeaderField: "User-Agent")
  let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  if !trimmedKey.isEmpty {
    request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
  }
  request.httpBody = try JSONEncoder().encode(
    PingRequest(
      model: config.modelID,
      messages: [["role": "user", "content": "ping"]],
      max_tokens: 1
    ))
  request.timeoutInterval = 20

  let (data, response) = try await URLSession.shared.data(for: request)
  guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
    return false
  }
  let decoded = try? JSONDecoder().decode(PingResponse.self, from: data)
  return decoded?.choices.first?.message.content != nil
}

// MARK: - Previews

#Preview {
  TaktOnboardingView()
}
