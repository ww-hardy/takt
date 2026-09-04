//
//  TaktTheme.swift
//  TAKT
//
//  TAKT redesign — one source of truth for every color, size, duration and
//  font used by the redesigned UI. Nothing else in the app may write a
//  literal color (see STYLE_GUIDE.md section 1).
//
//  Values come from the Wertwandler design handoff (design_handoff_takt_redesign).
//

import SwiftUI

// MARK: - Colors (role-named, not value-named)

enum TaktColor {
  // Accent — the only chromatic UI color
  static let accent = Color(hex: "FC971C")
  static let accentPressed = Color(hex: "E07A00")
  static let accentSoft = Color(hex: "FFF3E0")
  static let accentLight = Color(hex: "FDB950")

  // Neutrals, dark to light
  static let ink = Color(hex: "1A1A1A")
  static let inkRaised = Color(hex: "2A2A2A")    // selected rail item
  static let inkDivider = Color(hex: "3A3A3A")   // dividers on dark
  static let textPrimary = Color(hex: "1A1A1A")
  static let textSecondary = Color(hex: "595959")
  static let textTertiary = Color(hex: "777777")
  static let textLabel = Color(hex: "999999")    // uppercase labels
  static let textMuted = Color(hex: "BBBBBB")    // rail default, disabled chevrons
  static let borderStrong = Color(hex: "D9D9D9")
  static let borderGrid = Color(hex: "E5E5E5")
  static let borderHairline = Color(hex: "EEEEEE")
  static let surface = Color.white
  static let surfaceSunken = Color(hex: "F7F7F7")

  // Semantic
  static let positive = Color(hex: "2E7D32")
  static let negative = Color(hex: "C62828")
  static let negativeSoft = Color(hex: "FBEBE9")

  // Category colors (data-driven accents; fixed set trimmed)
  static let meetings = Color(hex: "37474F")

  // Standup accent (the one warm accent kept)
  static let standupAccent = Color(hex: "B46531")
  static let blockersLabel = Color(hex: "BD9479")
  static let blockersSurface = Color(hex: "F7F6F5")
  static let blockersBorder = Color(hex: "EBE6E3")

  // Client palette — the six values already in ClientsView.palette, unchanged
  static let clientBlue = Color(hex: "2E6F9E")
  static let clientGreen = Color(hex: "3D8B6E")
  static let clientOrange = Color(hex: "D97B3A")
  static let clientViolet = Color(hex: "7A5FA0")
  static let clientRed = Color(hex: "B5513D")
  static let clientGray = Color(hex: "6B7280")

  // Heatmap ramp
  static let heatmap0 = Color(hex: "F2F2F2")
  static let heatmap1 = Color(hex: "FFE7C2")
  static let heatmap2 = Color(hex: "FDB950")
  static let heatmap3 = Color(hex: "FC971C")
  static let heatmap4 = Color(hex: "E07A00")
}

// MARK: - Metrics

enum TaktMetrics {
  static let railWidth: CGFloat = 208
  static let inspectorWidth: CGFloat = 372
  static let inspectorDetailWidth: CGFloat = 468
  static let clientListWidth: CGFloat = 500
  static let controlHeight: CGFloat = 34
  static let chipHeight: CGFloat = 26
  static let radius: CGFloat = 0
  static let radiusControl: CGFloat = 2
  static let hairline: CGFloat = 1

  // Spacing scale (4px base)
  static let space3: CGFloat = 3
  static let space6: CGFloat = 6
  static let space8: CGFloat = 8
  static let space10: CGFloat = 10
  static let space12: CGFloat = 12
  static let space14: CGFloat = 14
  static let space18: CGFloat = 18
  static let space20: CGFloat = 20
  static let space22: CGFloat = 22
  static let space24: CGFloat = 24
  static let space26: CGFloat = 26
  static let space30: CGFloat = 30
  static let space34: CGFloat = 34
}

// MARK: - Fonts

enum TaktFont {
  static func display(_ size: CGFloat) -> Font {
    .custom("InstrumentSerif-Regular", size: size)
  }

  static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Figtree", size: size).weight(weight)
  }

  static let label = ui(12, .regular)       // pair with .kerning(1.2) + .textCase(.uppercase)
  static let body = ui(15)
  static let caption = ui(13)
  static let title = ui(16, .semibold)
  static let value = ui(14, .semibold)
}

// MARK: - Motion

enum TaktMotion {
  static let hover = Animation.easeOut(duration: 0.12)
  static let stateChange = Animation.easeInOut(duration: 0.18)
}

// MARK: - Modifiers

/// The uppercase section label that appears on every screen.
struct TaktLabel: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(TaktFont.label)
      .kerning(1.2)
      .textCase(.uppercase)
      .foregroundColor(TaktColor.textLabel)
  }
}

extension View {
  func taktLabel() -> some View {
    modifier(TaktLabel())
  }
}
