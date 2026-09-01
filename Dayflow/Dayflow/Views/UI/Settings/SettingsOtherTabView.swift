import SwiftUI

struct SettingsOtherTabView: View {
  @ObservedObject var viewModel: OtherSettingsViewModel
  @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
  @FocusState private var isOutputLanguageFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
      appPreferencesSection
      outputLanguageSection
    }
  }

  // MARK: - App preferences

  private var appPreferencesSection: some View {
    SettingsSection(
      title: "App-Einstellungen",
      subtitle: "Allgemeine Einstellungen und Telemetrie."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: "TAKT beim Anmelden starten",
          subtitle:
            "Hält die Menüleisten-Steuerung nach dem Anmelden am Laufen, damit die Aufnahme sofort weiterlaufen kann."
        ) {
          SettingsToggle(
            isOn: Binding(
              get: { launchAtLoginManager.isEnabled },
              set: { launchAtLoginManager.setEnabled($0) }
            )
          )
        }

        SettingsRow(label: "Absturzberichte und anonyme Nutzungsdaten teilen") {
          SettingsToggle(isOn: $viewModel.analyticsEnabled)
        }

        SettingsRow(
          label: "Dock-Symbol anzeigen",
          subtitle: "Wenn deaktiviert, läuft TAKT nur als Menüleisten-App."
        ) {
          SettingsToggle(isOn: $viewModel.showDockIcon)
        }

        SettingsRow(
          label: "App-/Website-Symbole in der Timeline anzeigen",
          subtitle: "Bei ausgeschaltetem Schalter zeigen Timeline-Karten keine App- oder Website-Symbole."
        ) {
          SettingsToggle(isOn: $viewModel.showTimelineAppIcons)
        }

        SettingsRow(
          label: "Tagesziel-Popups anzeigen",
          subtitle:
            "Wenn deaktiviert, öffnet TAKT nach 4 Uhr morgens nicht automatisch die Ziel-Einrichtung oder die gestrige Übersicht."
        ) {
          SettingsToggle(isOn: $viewModel.showDailyGoalPopups)
        }

        SettingsRow(
          label: "Alle Zeitraffer auf Festplatte sichern",
          subtitle:
            "Neue und neu verarbeitete Timeline-Karten erzeugen Zeitraffer-Videos vor und speichern sie auf der Festplatte statt sie bei Bedarf zu erstellen. Benötigt mehr Speicher und Hintergrundverarbeitung.",
          showsDivider: false
        ) {
          SettingsToggle(isOn: $viewModel.saveAllTimelapsesToDisk)
        }
      }
    }
  }

  // MARK: - Output language override

  private var outputLanguageSection: some View {
    SettingsSection(
      title: "Ausgabesprache überschreiben",
      subtitle:
        "Die Standardsprache ist Deutsch. Du kannst hier jede Sprache angeben (z. B. Deutsch, English, 简体中文, Español, 日本語, 한국어, Français)."
    ) {
      HStack(spacing: 10) {
        TextField("English", text: $viewModel.outputLanguageOverride)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)
          .frame(maxWidth: 220)
          .focused($isOutputLanguageFocused)
          .onChange(of: viewModel.outputLanguageOverride) {
            viewModel.markOutputLanguageOverrideEdited()
          }

        SettingsSecondaryButton(
          title: viewModel.isOutputLanguageOverrideSaved ? "Saved" : "Save",
          systemImage: viewModel.isOutputLanguageOverrideSaved
            ? "checkmark" : nil,
          isDisabled: viewModel.isOutputLanguageOverrideSaved,
          action: {
            viewModel.saveOutputLanguageOverride()
            isOutputLanguageFocused = false
          }
        )

        SettingsSecondaryButton(
          title: "Reset",
          action: {
            viewModel.resetOutputLanguageOverride()
            isOutputLanguageFocused = false
          }
        )

        Spacer()
      }
    }
  }
}
