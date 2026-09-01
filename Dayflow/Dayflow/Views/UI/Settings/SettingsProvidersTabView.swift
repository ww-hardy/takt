import AppKit
import SwiftUI

struct SettingsProvidersTabView: View {
  @ObservedObject var viewModel: ProvidersSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
      if viewModel.currentProvider == .local, viewModel.showLocalModelUpgradeBanner {
        LocalModelUpgradeBanner(
          preset: .qwen3VL4B,
          onKeepLegacy: { viewModel.markUpgradeBannerKeepLegacy() },
          onUpgrade: {
            viewModel.markUpgradeBannerUpgrade()
            viewModel.isShowingLocalModelUpgradeSheet = true
          }
        )
        .transition(.opacity)
      }

      if let status = viewModel.upgradeStatusMessage {
        Text(status)
          .font(.custom("Figtree", size: 13))
          .foregroundColor(SettingsStyle.statusGood)
      }

      if let error = viewModel.providerRoutingErrorMessage {
        Text(error)
          .font(.custom("Figtree", size: 13))
          .foregroundColor(.red.opacity(0.8))
      }

      currentConfigurationSection
      connectionHealthSection
      failoverRoutingSection

      if viewModel.currentProvider == .gemini {
        geminiModelSection
      }

      primaryPromptCustomizationSection
      if viewModel.hasCodexOrClaudeProviderInRouting {
        agentPromptCustomizationSection
      }
    }
  }

  // MARK: - Current configuration

  private var currentConfigurationSection: some View {
    SettingsSection(
      title: "Aktuelle Konfiguration",
      subtitle: "Aktiver LLM-Anbieter und Laufzeit-Details."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        summaryRows

        HStack(spacing: 8) {
          SettingsSecondaryButton(
            title: "Konfiguration bearbeiten",
            action: { viewModel.editProviderConfiguration(viewModel.primaryRoutingProviderId) }
          )

          if viewModel.currentProvider == .local {
            SettingsSecondaryButton(
              title: viewModel.usingRecommendedLocalModel
                ? "Lokales Modell verwalten" : "Lokales Modell erweitern",
              action: { viewModel.isShowingLocalModelUpgradeSheet = true }
            )
          }
        }
        .padding(.top, 18)
      }
    }
  }

  @ViewBuilder
  private var summaryRows: some View {
    SettingsRow(label: "Primärer LLM-Anbieter") {
      HStack(spacing: 8) {
        SettingsMetadata(
          text: viewModel.providerDisplayName(viewModel.primaryRoutingProviderId))
        SettingsBadge(text: "PRIMARY", isAccent: true)
      }
    }

    if let backupProvider = viewModel.secondaryRoutingProviderId {
      SettingsRow(label: "Sekundärer LLM-Anbieter") {
        HStack(spacing: 8) {
          SettingsMetadata(text: viewModel.providerDisplayName(backupProvider))
          SettingsBadge(text: "SECONDARY")
        }
      }
    } else {
      SettingsRow(label: "Sekundärer LLM-Anbieter") {
        SettingsMetadata(text: "Nicht konfiguriert")
      }
    }

    switch viewModel.currentProvider {
    case .local:
      SettingsRow(label: "Engine") { SettingsMetadata(text: viewModel.localEngine.displayName) }
      SettingsRow(label: "Modell") {
        SettingsMetadata(
          text: viewModel.localModelId.isEmpty ? "Not configured" : viewModel.localModelId)
      }
      SettingsRow(label: "Endpunkt") { SettingsMetadata(text: viewModel.localBaseURL) }
      let hasKey = !viewModel.localAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      SettingsRow(label: "API-Schlüssel", showsDivider: false) {
        SettingsMetadata(text: hasKey ? "In UserDefaults gespeichert" : "Nicht gesetzt")
      }
    case .gemini:
      SettingsRow(label: "Modellpräferenz") {
        SettingsMetadata(text: viewModel.selectedGeminiModel.displayName)
      }
      SettingsRow(label: "API-Schlüssel", showsDivider: false) {
        SettingsMetadata(
          text: KeychainManager.shared.retrieve(for: "gemini") != nil
            ? "Sicher im Schlüsselbund gespeichert" : "Nicht gesetzt")
      }
    case .chatGPT, .claude:
      SettingsRow(label: "CLI") {
        SettingsMetadata(text: viewModel.cliStatusLabel(for: viewModel.currentProvider))
      }
    case .openAICompatible:
      SettingsRow(label: "Preset") {
        SettingsMetadata(
          text: viewModel.openAICompatiblePreset == .openRouter ? "OpenRouter" : "Custom")
      }
      SettingsRow(label: "Modell") {
        SettingsMetadata(
          text: viewModel.openAICompatibleModelID.isEmpty
            ? "Not configured" : viewModel.openAICompatibleModelID)
      }
      SettingsRow(label: "Endpunkt") {
        SettingsMetadata(text: viewModel.openAICompatibleBaseURL)
      }
      let hasKey = !viewModel.openAICompatibleAPIKey.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      SettingsRow(label: "API-Schlüssel", showsDivider: false) {
        SettingsMetadata(text: hasKey ? "Sicher im Schlüsselbund gespeichert" : "Nicht gesetzt")
      }
    case .dayflow:
      SettingsRow(label: "Status", showsDivider: false) {
        SettingsMetadata(text: viewModel.statusText(for: .dayflow) ?? "Requires TAKT Pro")
      }
    }
  }

  // MARK: - Connection health

  private var connectionHealthSection: some View {
    SettingsSection(
      title: "Verbindungsstatus",
      subtitle: "Schnellen Test für den primären LLM-Anbieter ausführen."
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Text(viewModel.connectionHealthLabel)
          .font(.custom("Figtree", size: 13))
          .fontWeight(.semibold)
          .foregroundColor(SettingsStyle.text)

        switch viewModel.currentProvider {
        case .gemini:
          TestConnectionView(
            model: viewModel.selectedGeminiModel,
            onTestComplete: { _ in }
          )
        case .local:
          LocalLLMTestView(
            baseURL: $viewModel.localTestBaseURL,
            modelId: $viewModel.localTestModelID,
            apiKey: $viewModel.localTestAPIKey,
            engine: viewModel.localEngine,
            showInputs: viewModel.localEngine == .custom,
            onTestComplete: { success in
              viewModel.handleLocalTestCompletion(success: success)
            }
          )
        case .chatGPT:
          ChatCLITestView(
            selectedTool: .codex,
            onTestComplete: { _ in }
          )
        case .claude:
          ChatCLITestView(
            selectedTool: .claude,
            onTestComplete: { _ in }
          )
        case .openAICompatible:
          VStack(alignment: .leading, spacing: 10) {
            Text(
              "Der Test sendet ein kleines Bild, um die Multimodal-Unterstützung zu prüfen, und kann beim LLM-Anbieter Kosten verursachen."
            )
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            SettingsSecondaryButton(title: "Verbindung testen") {
              viewModel.editProviderConfiguration(.openAICompatible)
            }
          }
        case .dayflow:
          Text("Gehostete Karten und Transkription laufen über dein TAKT-Konto.")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(SettingsStyle.secondary)
        }
      }
    }
  }

  // MARK: - Failover routing

  private var failoverRoutingSection: some View {
    SettingsSection(
      title: "Ausweich-Routing",
      subtitle: "Wähle primären und sekundären LLM-Anbieter."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        let providers = viewModel.routingProviders
        ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
          routingRow(
            provider: provider,
            showsDivider: index < providers.count - 1
          )
        }
      }
    }
  }

  private func routingRow(
    provider: CompactProviderInfo,
    showsDivider: Bool
  ) -> some View {
    let isConfigured = viewModel.isProviderConfigured(provider.id)
    let isChecking = viewModel.isProviderReadinessChecking(provider.id)
    let isPrimary = viewModel.primaryRoutingProviderId == provider.id
    let isSecondary = viewModel.isBackupProvider(provider.id)
    let canSetSecondary =
      viewModel.canModifyRouting
      && (viewModel.canAssignSecondary(provider.id) || (!isConfigured && !isPrimary))

    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        Text(provider.providerTableName)
          .font(.custom("Figtree", size: 14))
          .fontWeight(.semibold)
          .foregroundColor(SettingsStyle.text)

        Spacer()

        if isPrimary {
          SettingsBadge(text: "PRIMARY", isAccent: true)
        }
        if isSecondary {
          SettingsBadge(text: "SECONDARY")
        }
        if isChecking && !isPrimary && !isSecondary {
          SettingsBadge(text: "CHECKING")
        } else if !isChecking && !isConfigured && (isPrimary || isSecondary) {
          SettingsBadge(text: "NEEDS ATTENTION")
        } else if !isChecking && !isPrimary && !isSecondary && isConfigured {
          SettingsBadge(
            text: provider.id == .chatGPT || provider.id == .claude
              ? "DETECTED" : "CONFIGURED")
        } else if !isChecking && !isPrimary && !isSecondary {
          SettingsBadge(text: "NOT SET")
        }
      }

      Text(provider.summary)
        .font(.custom("Figtree", size: 12))
        .foregroundColor(SettingsStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        if !isConfigured {
          SettingsSecondaryButton(title: "Setup") {
            viewModel.beginProviderSetup(provider.id, role: .setupOnly)
          }
        }

        SettingsSecondaryButton(title: "Konfiguration bearbeiten") {
          viewModel.editProviderConfiguration(provider.id)
        }

          if !isPrimary {
          SettingsSecondaryButton(
            title: "Als primär setzen",
            isDisabled: !viewModel.canModifyRouting
          ) {
            viewModel.setPrimaryOrSetup(provider.id)
          }
        }

        if !isSecondary {
          SettingsSecondaryButton(title: "Als sekundär setzen", isDisabled: !canSetSecondary) {
            viewModel.setSecondaryOrSetup(provider.id)
          }
        } else {
          SettingsSecondaryButton(title: "Sekundär entfernen") {
            viewModel.clearBackupProvider()
          }
        }
      }
    }
    .padding(.vertical, 14)
    .overlay(alignment: .bottom) {
      if showsDivider {
        Rectangle().fill(SettingsStyle.divider).frame(height: 1)
      }
    }
  }

  // MARK: - Gemini model preference

  private var geminiModelSection: some View {
    SettingsSection(
      title: "Gemini-Modellpräferenz",
      subtitle: "Choose which Gemini model TAKT should prioritize."
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Picker("Gemini model", selection: $viewModel.selectedGeminiModel) {
          ForEach(GeminiModel.allCases, id: \.self) { model in
            Text(model.displayName).tag(model)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .environment(\.colorScheme, .light)
        .onChange(of: viewModel.selectedGeminiModel) { _, newValue in
          viewModel.persistGeminiModelSelection(newValue, source: "settings")
        }

        Text(GeminiModelPreference(primary: viewModel.selectedGeminiModel).fallbackSummary)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)

        Text(
          "TAKT automatically downgrades if your chosen model is rate limited or unavailable."
        )
        .font(.custom("Figtree", size: 11))
        .foregroundColor(SettingsStyle.meta)
      }
    }
  }

  // MARK: - Prompt customization

  @ViewBuilder
  private var primaryPromptCustomizationSection: some View {
    switch viewModel.currentProvider {
    case .gemini:
      promptSection(
        title: "Gemini-Prompt-Anpassung",
        subtitle: "Override TAKT's defaults to tailor card generation.",
        intro:
          "Überschreibungen gelten nur, wenn der Schalter aktiv ist. Nicht aktivierte Abschnitte fallen auf die TAKT-Standards zurück.",
        sections: [
          promptEditorConfig(
            heading: "Card titles",
            description: "Bestimme, wie Kartentitel klingen, und passe die Beispielliste an.",
            isEnabled: $viewModel.useCustomGeminiTitlePrompt,
            text: $viewModel.geminiTitlePromptText,
            defaultText: GeminiPromptDefaults.titleBlock
          ),
          promptEditorConfig(
            heading: "Card summaries",
            description: "Bestimme Ton und Stil des Zusammenfassungsfelds.",
            isEnabled: $viewModel.useCustomGeminiSummaryPrompt,
            text: $viewModel.geminiSummaryPromptText,
            defaultText: GeminiPromptDefaults.summaryBlock
          ),
          promptEditorConfig(
            heading: "Detailed summaries",
            description: "Lege Format und Beispiele für die minutenweise Aufschlüsselung fest.",
            isEnabled: $viewModel.useCustomGeminiDetailedPrompt,
            text: $viewModel.geminiDetailedPromptText,
            defaultText: GeminiPromptDefaults.detailedSummaryBlock
          ),
        ],
        onReset: viewModel.resetGeminiPromptOverrides
      )
    case .local:
      promptSection(
        title: "Lokale Prompt-Anpassung",
        subtitle: "Passe die Prompts für lokale Timeline-Zusammenfassungen an.",
        intro: "Customize the local model prompts for summary and title generation.",
        sections: [
          promptEditorConfig(
            heading: "Timeline summaries",
            description: "Control how the local model writes its 2-3 sentence card summaries.",
            isEnabled: $viewModel.useCustomOllamaSummaryPrompt,
            text: $viewModel.ollamaSummaryPromptText,
            defaultText: OllamaPromptDefaults.summaryBlock
          ),
          promptEditorConfig(
            heading: "Card titles",
            description: "Passe Ton und Beispiele für lokale Titelgenerierung an.",
            isEnabled: $viewModel.useCustomOllamaTitlePrompt,
            text: $viewModel.ollamaTitlePromptText,
            defaultText: OllamaPromptDefaults.titleBlock
          ),
        ],
        onReset: viewModel.resetOllamaPromptOverrides
      )
    case .dayflow, .chatGPT, .claude, .openAICompatible:
      EmptyView()
    }
  }

  private var agentPromptCustomizationSection: some View {
    let defaults: (titleBlock: String, summaryBlock: String, detailedSummaryBlock: String)
    if viewModel.selectedAgentPromptProvider == .claude {
      defaults = (
        ClaudePromptDefaults.titleBlock,
        ClaudePromptDefaults.summaryBlock,
        ClaudePromptDefaults.detailedSummaryBlock
      )
    } else {
      defaults = (
        CodexPromptDefaults.titleBlock,
        CodexPromptDefaults.summaryBlock,
        CodexPromptDefaults.detailedSummaryBlock
      )
    }
    return promptSection(
      title: "ChatGPT and Claude prompt customization",
      subtitle: "Keep independent card-generation prompts for each CLI provider.",
      intro:
        "Überschreibungen gelten nur, wenn der Schalter aktiv ist. Nicht aktivierte Abschnitte fallen auf die TAKT-Standards zurück.",
      sections: [
        promptEditorConfig(
          heading: "Card titles",
          description: "Bestimme, wie Kartentitel klingen, und passe die Beispielliste an.",
          isEnabled: $viewModel.useCustomAgentTitlePrompt,
          text: $viewModel.agentTitlePromptText,
          defaultText: defaults.titleBlock
        ),
        promptEditorConfig(
          heading: "Card summaries",
          description: "Bestimme Ton und Stil des Zusammenfassungsfelds.",
          isEnabled: $viewModel.useCustomAgentSummaryPrompt,
          text: $viewModel.agentSummaryPromptText,
          defaultText: defaults.summaryBlock
        ),
        promptEditorConfig(
          heading: "Detailed summaries",
          description: "Lege Format und Beispiele für die minutenweise Aufschlüsselung fest.",
          isEnabled: $viewModel.useCustomAgentDetailedPrompt,
          text: $viewModel.agentDetailedPromptText,
          defaultText: defaults.detailedSummaryBlock
        ),
      ],
      onReset: viewModel.resetAgentPromptOverrides,
      showsAgentProviderPicker: true
    )
  }

  private struct PromptEditorConfig {
    let heading: String
    let description: String
    let isEnabled: Binding<Bool>
    let text: Binding<String>
    let defaultText: String
  }

  private func promptEditorConfig(
    heading: String,
    description: String,
    isEnabled: Binding<Bool>,
    text: Binding<String>,
    defaultText: String
  ) -> PromptEditorConfig {
    PromptEditorConfig(
      heading: heading, description: description, isEnabled: isEnabled, text: text,
      defaultText: defaultText)
  }

  private func promptSection(
    title: String,
    subtitle: String,
    intro: String,
    sections: [PromptEditorConfig],
    onReset: @escaping () -> Void,
    showsAgentProviderPicker: Bool = false
  ) -> some View {
    SettingsSection(title: title, subtitle: subtitle) {
      VStack(alignment: .leading, spacing: 18) {
        if showsAgentProviderPicker {
          Picker("Provider", selection: $viewModel.selectedAgentPromptProvider) {
            Text("ChatGPT").tag(LLMProviderID.chatGPT)
            Text("Claude").tag(LLMProviderID.claude)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(maxWidth: 320)
        }

        Text(intro)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)

        ForEach(sections.indices, id: \.self) { index in
          promptEditorBlock(config: sections[index])
        }

        HStack {
          Spacer()
          SettingsSecondaryButton(
            title: "Reset to TAKT defaults",
            systemImage: "arrow.counterclockwise",
            action: onReset
          )
        }
      }
    }
  }

  /// A prompt-customization block: toggle + text-editor pair. Keeps its
  /// own subtle container because the text editor needs input-affordance
  /// against the paper background.
  private func promptEditorBlock(config: PromptEditorConfig) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: config.isEnabled) {
        VStack(alignment: .leading, spacing: 3) {
          Text(config.heading)
            .font(.custom("Figtree", size: 14))
            .fontWeight(.semibold)
            .foregroundColor(SettingsStyle.text)
          Text(config.description)
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(SwitchToggleStyle(tint: SettingsStyle.ink))
      .pointingHandCursor()

      ZStack(alignment: .topLeading) {
        if config.text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(config.defaultText)
            .font(.custom("Figtree", size: 12))
            .foregroundColor(SettingsStyle.meta)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
        }

        TextEditor(text: config.text)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.text.opacity(config.isEnabled.wrappedValue ? 1 : 0.4))
          .scrollContentBackground(.hidden)
          .disabled(!config.isEnabled.wrappedValue)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(minHeight: config.isEnabled.wrappedValue ? 140 : 120)
      }
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.white.opacity(0.7))
          .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .stroke(Color.black.opacity(0.12), lineWidth: 1)
          )
      )
      .opacity(config.isEnabled.wrappedValue ? 1 : 0.6)
    }
  }
}

// MARK: - Upgrade banner (kept as an exception — it's a promotional unit)
//
// This is the one dark surface on the settings page. Semantically it's
// advertising, not configuration, so it gets to play by different rules.

private struct LocalModelUpgradeBanner: View {
  let preset: LocalModelPreset
  let onKeepLegacy: () -> Void
  let onUpgrade: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .foregroundStyle(Color.white)
          .padding(8)
          .background(Color(red: 0.12, green: 0.09, blue: 0.02))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 4) {
          Text("Upgrade auf \(preset.displayName)")
            .font(.custom("Figtree", size: 16))
            .fontWeight(.semibold)
            .foregroundColor(.white)
          Text("Upgrade auf Qwen3VL für eine deutliche Qualitätsverbesserung.")
            .font(.custom("Figtree", size: 13))
            .foregroundColor(.white.opacity(0.8))
        }
        Spacer()
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(preset.highlightBullets, id: \.self) { bullet in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 12))
              .foregroundColor(Color(red: 0.76, green: 1, blue: 0.74))
              .padding(.top, 2)
            Text(bullet)
              .font(.custom("Figtree", size: 13))
              .foregroundColor(.white.opacity(0.85))
          }
        }
      }

      HStack(spacing: 12) {
        Button(action: onKeepLegacy) {
          Text("Keep Qwen2.5")
            .font(.custom("Figtree", size: 13))
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()

        Button(action: onUpgrade) {
          HStack(spacing: 6) {
            Text("Jetzt upgraden")
              .font(.custom("Figtree", size: 13))
              .fontWeight(.semibold)
            Image(systemName: "arrow.right")
              .font(.system(size: 12, weight: .semibold))
          }
          .foregroundColor(.black)
          .padding(.horizontal, 18)
          .padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(Color.white)
          )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(red: 0.16, green: 0.11, blue: 0))
    )
  }
}

// MARK: - Upgrade sheet (unchanged — it's a modal, not a settings surface)

struct LocalModelUpgradeSheet: View {
  let preset: LocalModelPreset
  let initialEngine: LocalEngine
  let initialBaseURL: String
  let initialModelId: String
  let initialAPIKey: String
  let onCancel: () -> Void
  let onUpgradeSuccess: (LocalEngine, String, String, String) -> Void

  @State private var selectedEngine: LocalEngine
  @State private var candidateBaseURL: String
  @State private var candidateModelId: String
  @State private var candidateAPIKey: String
  @State private var didApplyUpgrade = false

  init(
    preset: LocalModelPreset,
    initialEngine: LocalEngine,
    initialBaseURL: String,
    initialModelId: String,
    initialAPIKey: String,
    onCancel: @escaping () -> Void,
    onUpgradeSuccess: @escaping (LocalEngine, String, String, String) -> Void
  ) {
    self.preset = preset
    self.initialEngine = initialEngine
    self.initialBaseURL = initialBaseURL
    self.initialModelId = initialModelId
    self.initialAPIKey = initialAPIKey
    self.onCancel = onCancel
    self.onUpgradeSuccess = onUpgradeSuccess

    let startingEngine = initialEngine
    _selectedEngine = State(initialValue: startingEngine)
    _candidateBaseURL = State(
      initialValue: initialBaseURL.isEmpty ? startingEngine.defaultBaseURL : initialBaseURL)
    let recommendedModel = preset.modelId(for: startingEngine == .custom ? .ollama : startingEngine)
    _candidateModelId = State(initialValue: recommendedModel)
    _candidateAPIKey = State(initialValue: initialAPIKey)
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Upgrade auf \(preset.displayName)")
              .font(.custom("Figtree", size: 22))
              .fontWeight(.semibold)
            Text(
              "Folge den Schritten unten, führe einen kurzen Test aus, und TAKT wechselt automatisch."
            )
            .font(.custom("Figtree", size: 13))
            .foregroundColor(SettingsStyle.secondary)
          }
          Spacer()
          Button(action: onCancel) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 20))
              .foregroundColor(SettingsStyle.meta)
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
        }

        VStack(alignment: .leading, spacing: 6) {
          ForEach(preset.highlightBullets, id: \.self) { bullet in
            HStack(spacing: 8) {
              Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundColor(SettingsStyle.ink)
              Text(bullet)
                .font(.custom("Figtree", size: 13))
                .foregroundColor(SettingsStyle.text)
            }
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("Welche lokale Engine nutzt du?")
            .font(.custom("Figtree", size: 14))
            .foregroundColor(SettingsStyle.secondary)
          Picker("Engine", selection: $selectedEngine) {
            Text("Ollama").tag(LocalEngine.ollama)
            Text("LM Studio").tag(LocalEngine.lmstudio)
            Text("Custom").tag(LocalEngine.custom)
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 420)
        }

        instructionView(for: selectedEngine)

        LocalLLMTestView(
          baseURL: $candidateBaseURL,
          modelId: $candidateModelId,
          apiKey: $candidateAPIKey,
          engine: selectedEngine,
          showInputs: true,
          buttonLabel: "Test upgrade",
          basePlaceholder: selectedEngine.defaultBaseURL,
          modelPlaceholder: preset.modelId(
            for: selectedEngine == .custom ? .ollama : selectedEngine),
          onTestComplete: { success in
            if success && !didApplyUpgrade {
              didApplyUpgrade = true
              onUpgradeSuccess(selectedEngine, candidateBaseURL, candidateModelId, candidateAPIKey)
            }
          }
        )

        Text(
          "Sobald der Test erfolgreich ist, aktualisiert TAKT deine Einstellungen automatisch auf \(preset.displayName)."
        )
        .font(.custom("Figtree", size: 12))
        .foregroundColor(SettingsStyle.secondary)

        HStack {
          Spacer()
          SettingsSecondaryButton(title: "Close", action: onCancel)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onChange(of: selectedEngine) { _, newEngine in
      candidateModelId = preset.modelId(for: newEngine == .custom ? .ollama : newEngine)
      if newEngine != .custom {
        candidateBaseURL = newEngine.defaultBaseURL
        candidateAPIKey = ""
      }
    }
  }

  @ViewBuilder
  private func instructionView(for engine: LocalEngine) -> some View {
    let instruction = preset.instructions(for: engine == .custom ? .ollama : engine)
    VStack(alignment: .leading, spacing: 12) {
      Text(instruction.title)
        .font(.custom("Figtree", size: 16))
        .fontWeight(.semibold)
      Text(instruction.subtitle)
        .font(.custom("Figtree", size: 13))
        .foregroundColor(SettingsStyle.secondary)
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(instruction.bullets.enumerated()), id: \.offset) { index, bullet in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index + 1).")
              .font(.custom("Figtree", size: 13))
              .foregroundColor(SettingsStyle.secondary)
              .frame(width: 18, alignment: .leading)
            Text(bullet)
              .font(.custom("Figtree", size: 13))
              .foregroundColor(SettingsStyle.text)
          }
        }
      }

      if let command = instruction.command,
        let commandTitle = instruction.commandTitle,
        let commandSubtitle = instruction.commandSubtitle
      {
        TerminalCommandView(
          title: commandTitle,
          subtitle: commandSubtitle,
          command: command
        )
      }

      if let buttonTitle = instruction.buttonTitle,
        let url = instruction.buttonURL
      {
        SettingsPrimaryButton(
          title: buttonTitle,
          systemImage: "arrow.down.circle.fill",
          action: { NSWorkspace.shared.open(url) }
        )
      }

      if let note = instruction.note {
        Text(note)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)
      }
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    )
  }
}
