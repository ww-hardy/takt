//
//  TaktHeaderComponents.swift
//  TAKT
//
//  TAKT redesign — square date stepper and Day/Week segmented switch.
//  Replace the circular date-stepper pills with square TAKT controls.
//  These are visual shells: they call the existing navigation actions.
//

import SwiftUI

// MARK: - TaktDateStepper

struct TaktDateStepper: View {
  let title: String
  var canGoPrevious = true
  var canGoNext = true
  let onPrevious: () -> Void
  let onNext: () -> Void

  @State private var hoverPrev = false
  @State private var hoverNext = false

  var body: some View {
    HStack(spacing: 0) {
      chevron("chevron.left", enabled: canGoPrevious, isHovered: hoverPrev) {
        onPrevious()
      }
      .onHover { hoverPrev = $0 }

      Text(title)
        .font(TaktFont.ui(14, .semibold))
        .foregroundColor(TaktColor.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minWidth: 100)
        .overlay(
          Rectangle()
            .fill(TaktColor.borderStrong)
            .frame(width: 1)
            .padding(.vertical, 0),
          alignment: .leading
        )
        .overlay(
          Rectangle()
            .fill(TaktColor.borderStrong)
            .frame(width: 1)
            .padding(.vertical, 0),
          alignment: .trailing
        )

      chevron("chevron.right", enabled: canGoNext, isHovered: hoverNext) {
        onNext()
      }
      .onHover { hoverNext = $0 }
    }
    .frame(height: TaktMetrics.controlHeight)
    .background(TaktColor.surface)
    .overlay(
      RoundedRectangle(cornerRadius: TaktMetrics.radius)
        .stroke(TaktColor.borderStrong, lineWidth: 1)
    )
  }

  private func chevron(
    _ systemName: String, enabled: Bool, isHovered: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(enabled ? (isHovered ? TaktColor.ink : TaktColor.textSecondary) : TaktColor.textMuted)
        .frame(width: 32, height: TaktMetrics.controlHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .pointingHandCursor()
    .accessibilityLabel(enabled ? (systemName.contains("left") ? "Vorheriger Tag" : "Nächster Tag") : "")
  }
}

// MARK: - TaktSegmentedSwitch

struct TaktSegmentedSwitch: View {
  let options: [String]
  @Binding var selection: Int
  var onSelect: ((Int) -> Void)? = nil

  @State private var hoverIndex: Int? = nil

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options.indices, id: \.self) { index in
        Button {
          selection = index
          onSelect?(index)
        } label: {
          Text(options[index])
            .font(TaktFont.ui(14, selection == index ? .semibold : .regular))
            .foregroundColor(selection == index ? .white : (hoverIndex == index ? TaktColor.ink : TaktColor.textSecondary))
            .padding(.horizontal, 16)
            .frame(height: TaktMetrics.controlHeight)
            .background(selection == index ? TaktColor.ink : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          hoverIndex = hovering ? index : nil
        }
        .pointingHandCursor()
        .accessibilityLabel(options[index])
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: TaktMetrics.radius)
        .stroke(TaktColor.borderStrong, lineWidth: 1)
    )
  }
}
