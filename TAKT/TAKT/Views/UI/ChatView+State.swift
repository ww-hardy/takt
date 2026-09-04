import AppKit
import Charts
import SwiftUI

extension ChatView {
  /// TAKT: Der Chat nutzt ausschliesslich den Standard-LLM-Anbieter aus den
  /// Einstellungen — es gibt keine Chat-Provider-Auswahl mehr.
  var selectedProvider: DashboardChatProvider {
    DashboardChatProvider.fromRoutingStore()
  }

  var isUnlocked: Bool {
    hasBetaAccepted && hasChatMinimumAccess
  }

  var anyRuntimeAvailable: Bool {
    geminiConfigured || codexDetected || claudeDetected || openAICompatibleConfigured
  }

  var hasChatMinimumAccess: Bool {
    FeatureAccessRequirements.hasRequiredBatches(
      completedAccessBatchCount,
      requiredBatchCount: FeatureAccessRequirements.chatRequiredBatchCount
    )
  }

  var chatAccessProgressText: String {
    FeatureAccessRequirements.progressText(
      completedBatchCount: completedAccessBatchCount,
      requiredHours: FeatureAccessRequirements.chatRequiredHours
    )
  }

  var selectedProviderAvailable: Bool {
    isProviderAvailable(selectedProvider)
  }

  var welcomePrompts: [WelcomePrompt] {
    [
      WelcomePrompt(icon: "doc.text", text: "Tagesbericht für gestern erstellen"),
      WelcomePrompt(icon: "checkmark.seal", text: "Was habe ich letzte Woche erledigt?"),
      WelcomePrompt(
        icon: "exclamationmark.bubble", text: "Wann war ich diese Woche am fokussiertesten"),
      WelcomePrompt(
        icon: "sparkles", text: "Vergleiche diese Woche mit der letzten"),
    ]
  }

  var welcomeHeroAnimation: Animation {
    if reduceMotion {
      return .easeOut(duration: 0.01)
    }
    return .timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
  }

  var feedbackStateAnimation: Animation {
    if reduceMotion {
      return .easeOut(duration: 0.01)
    }
    return .easeOut(duration: 0.18)
  }

  var feedbackModalAnimation: Animation {
    if reduceMotion {
      return .easeOut(duration: 0.01)
    }
    return .spring(response: 0.28, dampingFraction: 0.88)
  }

  func welcomeSuggestionAnimation(at index: Int) -> Animation {
    if reduceMotion {
      return .easeOut(duration: 0.01)
    }
    return .timingCurve(0.16, 1, 0.3, 1, duration: 0.34)
      .delay(Double(index) * 0.045)
  }

  var trimmedInputText: String {
    inputText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var canSubmitCurrentInput: Bool {
    !chatService.isProcessing && !trimmedInputText.isEmpty && selectedProviderAvailable
  }

  var composerBorderColor: Color {
    if isInputFocused {
      return Color(hex: "F4A867")
    }
    return Color(hex: "E5D8CA")
  }

  var memoryCharacterCount: Int {
    memoryDraft.count
  }

  var isMemoryDirty: Bool {
    memoryDraft != storedMemoryBlob
  }

  var memoryUpdatedLabel: String {
    guard let memoryUpdatedAt else { return "Not saved yet" }
    return chatViewMemoryUpdatedFormatter.string(from: memoryUpdatedAt)
  }
}
