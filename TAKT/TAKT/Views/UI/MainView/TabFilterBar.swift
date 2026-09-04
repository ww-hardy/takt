import SwiftUI

struct TabFilterBar: View {
  let categories: [TimelineCategory]
  let idleCategory: TimelineCategory?
  let onManageCategories: () -> Void

  @State private var chipRowWidth: CGFloat = 0

  private let editButtonSize: CGFloat = 24
  private let chipButtonSpacing: CGFloat = 8

  var body: some View {
    GeometryReader { geometry in
      let availableWidth = max(0, geometry.size.width)
      let maxChipRowWidth = max(0, availableWidth - editButtonSize - chipButtonSpacing)
      let hasMeasuredChipRow = chipRowWidth > 0
      let isOverflowing = hasMeasuredChipRow && chipRowWidth > maxChipRowWidth
      let chipRowFrameWidth =
        hasMeasuredChipRow
        ? min(chipRowWidth, maxChipRowWidth)
        : maxChipRowWidth

      ZStack(alignment: .topLeading) {
        HStack(spacing: chipButtonSpacing) {
          visibleChipRow(width: chipRowFrameWidth)
          editButton
        }
        .frame(width: availableWidth, height: editButtonSize, alignment: .leading)
        .overlay(alignment: .trailing) {
          if isOverflowing {
            overflowGradient
              .padding(.trailing, editButtonSize + chipButtonSpacing)
          }
        }

        measuredChipRow
          .opacity(0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .frame(width: availableWidth, height: editButtonSize, alignment: .leading)
    }
    .frame(height: editButtonSize)
    .onPreferenceChange(ChipRowWidthPreferenceKey.self) { chipRowWidth = $0 }
  }

  struct CategoryChip: View {
    let category: TimelineCategory
    let isIdle: Bool

    var body: some View {
      HStack(spacing: 8) {
        Circle()
          .fill(Color(hex: category.colorHex))
          .frame(width: 8, height: 8)

        Text(category.name)
          .font(TaktFont.ui(12, .medium))
          .foregroundColor(TaktColor.textPrimary)
          .lineLimit(1)
          .fixedSize()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .frame(height: TaktMetrics.chipHeight)
      .background(TaktColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .stroke(TaktColor.borderStrong, lineWidth: TaktMetrics.hairline)
      )
    }
  }

  private func visibleChipRow(width: CGFloat) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      chipRowContent
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 26)
    }
    .frame(width: max(0, width), height: 26, alignment: .leading)
    .clipped()
  }

  private var measuredChipRow: some View {
    chipRowContent
      .fixedSize(horizontal: true, vertical: false)
      .background(
        GeometryReader { proxy in
          Color.clear.preference(key: ChipRowWidthPreferenceKey.self, value: proxy.size.width)
        }
      )
  }

  private var chipRowContent: some View {
    HStack(spacing: 5) {
      ForEach(categories) { category in
        CategoryChip(category: category, isIdle: false)
      }

      if let idleCategory {
        CategoryChip(category: idleCategory, isIdle: true)
      }
    }
    .padding(.leading, 2)
  }

  private var editButton: some View {
    CategoryEditCircleButton(
      action: onManageCategories,
      diameter: editButtonSize
    )
  }

  private var overflowGradient: some View {
    // TAKT redesign: fade uses the app surface token, not the old warm tint.
    LinearGradient(
      gradient: Gradient(colors: [Color.clear, TaktColor.surface]),
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(width: 40)
    .allowsHitTesting(false)
  }

  private struct ChipRowWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = nextValue()
    }
  }
}
