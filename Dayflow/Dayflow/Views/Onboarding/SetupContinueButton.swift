//
//  SetupContinueButton.swift
//  Dayflow
//
//  Continue button for the category-editor flow.
//  TAKT redesign: standard Wertwandler style — accent fill (#FC971C), ink
//  text, radius 2, 1px hairline, no shadows. Matches TaktButton .primary
//  but keeps its own pressed/hover scale for the editor sheet.
//

import SwiftUI

struct SetupContinueButton: View {
  let title: String
  let isEnabled: Bool
  let action: () -> Void

  @State private var isPressed = false
  @State private var isHovered = false

  init(title: String = "Weiter", isEnabled: Bool = true, action: @escaping () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.action = action
  }

  var body: some View {
    Button(action: isEnabled ? action : {}) {
      Text(title)
        .font(TaktFont.ui(14, .semibold))
        .foregroundColor(isEnabled ? TaktColor.ink : TaktColor.textMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 18)
        .frame(height: TaktMetrics.controlHeight + 6)
        .background(isEnabled ? TaktColor.accent : TaktColor.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
        .overlay(
          RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
            .stroke(
              isEnabled ? Color.clear : TaktColor.borderStrong,
              lineWidth: TaktMetrics.hairline
            )
        )
    }
    .buttonStyle(.plain)
    .scaleEffect(isPressed ? 0.97 : 1.0)
    .animation(TaktMotion.hover, value: isPressed)
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          if isEnabled {
            isPressed = true
          }
        }
        .onEnded { _ in
          isPressed = false
        }
    )
    .disabled(!isEnabled)
    .pointingHandCursor(enabled: isEnabled)
    .help(title)
  }
}
