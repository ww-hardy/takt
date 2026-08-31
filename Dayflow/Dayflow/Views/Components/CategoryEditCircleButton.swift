import SwiftUI

/// Category edit affordance.
///
/// TAKT redesign: square, hairline border, SF glyph, no hover/press scale.
/// The name keeps "Circle" for call-site compatibility — the shape is square.
struct CategoryEditCircleButton: View {
  let action: () -> Void
  var diameter: CGFloat = 30
  var iconSize: CGFloat? = nil
  var accessibilityLabel: String = "Edit categories"

  @State private var isHovering = false

  var body: some View {
    let resolvedIconSize = iconSize ?? diameter * 0.46

    Button(action: action) {
      Image(systemName: "pencil")
        .font(.system(size: resolvedIconSize, weight: .medium))
        .foregroundColor(isHovering ? TaktColor.ink : TaktColor.textSecondary)
        .frame(width: diameter, height: diameter)
        .background(isHovering ? TaktColor.accentSoft : TaktColor.surface)
        .overlay(
          Rectangle()
            .stroke(isHovering ? TaktColor.ink : TaktColor.borderStrong, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
    .accessibilityLabel(accessibilityLabel)
  }
}
