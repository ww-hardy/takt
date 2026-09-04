import AppKit
import Charts
import SwiftUI

struct WelcomePrompt {
  let icon: String
  let text: String
}

struct WelcomeSuggestionRow: View {
  let prompt: WelcomePrompt
  let action: () -> Void

  @State var isHovered = false
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: prompt.icon)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(TaktColor.accent)
          .frame(width: 24, height: 24)
          .background(
            RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
              .fill(TaktColor.accentSoft)
          )

        Text(prompt.text)
          .font(.custom("Figtree", size: 13).weight(.semibold))
          .foregroundColor(TaktColor.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .multilineTextAlignment(.leading)
          .lineLimit(2)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundColor(TaktColor.accent)
          .padding(.trailing, 2)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .fill(isHovered ? TaktColor.surfaceSunken : TaktColor.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .stroke(TaktColor.borderGrid, lineWidth: 1)
      )
      .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.01 : 1))
      .offset(y: reduceMotion ? 0 : (isHovered ? -1 : 0))
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .onHover { hovering in
      guard !reduceMotion else {
        isHovered = false
        return
      }
      withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
        isHovered = hovering
      }
    }
  }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
  let text: String
  let action: () -> Void

  @State var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.custom("Figtree", size: 12).weight(.medium))
        .foregroundColor(TaktColor.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
            .fill(isHovered ? TaktColor.accentSoft : TaktColor.surface)
        )
        .overlay(
          RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
            .stroke(TaktColor.accent.opacity(0.35), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .onHover { hovering in
      withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
        isHovered = hovering
      }
    }
  }
}
