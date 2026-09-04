//
//  TaktComponents.swift
//  TAKT
//
//  TAKT redesign — the three button variants, the chip and the badge.
//  Replaces TAKTButton / TAKTSurfaceButton / the hand-rolled filter
//  chips. A call site passes a title, a variant and an action — never colors,
//  padding or radius (STYLE_GUIDE.md §4).
//

import SwiftUI

// MARK: - TaktButton

struct TaktButton: View {
  enum Variant {
    case primary   // #FC971C bg, #1A1A1A text, hover/pressed #E07A00
    case secondary // transparent, 1px #D9D9D9, #4A4A4A text
    case ghost     // text only, #595959 -> #1A1A1A
  }

  enum Size {
    case small   // 34pt
    case medium  // 40pt
  }

  let title: String
  var variant: Variant = .primary
  var size: Size = .small
  var icon: String? = nil
  let action: () -> Void

  @State private var isHovered = false

  private var height: CGFloat {
    size == .small ? 34 : 40
  }

  private var foreground: Color {
    switch variant {
    case .primary: return TaktColor.ink
    case .secondary: return isHovered ? TaktColor.ink : TaktColor.textPrimary
    case .ghost: return isHovered ? TaktColor.ink : TaktColor.textSecondary
    }
  }

  private var background: Color {
    switch variant {
    case .primary: return isHovered ? TaktColor.accentPressed : TaktColor.accent
    case .secondary: return .clear
    case .ghost: return .clear
    }
  }

  private var border: Color {
    switch variant {
    case .primary: return .clear
    case .secondary: return isHovered ? TaktColor.ink : TaktColor.borderStrong
    case .ghost: return .clear
    }
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let icon {
          Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
        }
        Text(title)
          .font(TaktFont.ui(14, .semibold))
      }
      .foregroundColor(foreground)
      .frame(height: height)
      .padding(.horizontal, size == .small ? 14 : 18)
      .background(background)
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .stroke(border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(TaktMotion.hover) { isHovered = hovering }
    }
    .animation(TaktMotion.hover, value: isHovered)
    .help(title)
  }
}

// MARK: - TaktChip

/// Filter chip — selected (dark fill) or unselected (1px border, optional color dot).
struct TaktChip: View {
  let title: String
  var isSelected: Bool = false
  var color: Color? = nil
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if let color {
          Circle()
            .fill(color)
            .frame(width: 7, height: 7)
        }
        Text(title)
          .font(TaktFont.ui(13, isSelected ? .semibold : .regular))
          .lineLimit(1)
      }
      .foregroundColor(
        isSelected ? Color.white : (isHovered ? TaktColor.ink : TaktColor.textPrimary))
      .padding(.horizontal, 11)
      .frame(height: TaktMetrics.chipHeight)
      .background(isSelected ? TaktColor.ink : Color.clear)
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radius)
          .stroke(isHovered ? TaktColor.ink : TaktColor.borderStrong, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(TaktMotion.hover) { isHovered = hovering }
    }
    .help(title)
  }
}

// MARK: - TaktBadge

struct TaktBadge: View {
  enum Variant {
    case orange  // #FFF3E0 on #E07A00 — "billable"
    case neutral // #EEEEEE on #1A1A1A — project chips
    case outline // 1px #D9D9D9, #595959 — category value
  }

  let title: String
  var variant: Variant = .neutral

  var body: some View {
    Text(title)
      .font(TaktFont.ui(13, .semibold))
      .lineLimit(1)
      .foregroundColor(foreground)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(background)
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .stroke(border, lineWidth: 1)
      )
  }

  private var foreground: Color {
    switch variant {
    case .orange: return TaktColor.accentPressed
    case .neutral: return TaktColor.ink
    case .outline: return TaktColor.textSecondary
    }
  }

  private var background: Color {
    switch variant {
    case .orange: return TaktColor.accentSoft
    case .neutral: return TaktColor.borderHairline
    case .outline: return .clear
    }
  }

  private var border: Color {
    switch variant {
    case .orange: return .clear
    case .neutral: return .clear
    case .outline: return TaktColor.borderStrong
    }
  }
}
