//
//  DayFocusSummarySection.swift
//  TAKT
//
//  Focus section for the Day Summary right rail.
//

import SwiftUI

struct DayFocusSummarySection: View {
  let totalFocusText: String
  let focusBlocks: [FocusBlock]
  let isSelectionEmpty: Bool
  let categories: [TimelineCategory]
  let selectedCategoryIDs: Set<UUID>
  let isEditingCategories: Bool
  var onEditCategories: () -> Void
  var onToggleCategory: (TimelineCategory) -> Void
  var onDoneEditing: () -> Void

  private enum Design {
    static let sectionSpacing: CGFloat = 12
    static let cardsSpacing: CGFloat = 8
    static let editButtonSize: CGFloat = 20
    static let editorWidth: CGFloat = 358
    static let editorOffsetX: CGFloat = -18
    static let editorOffsetY: CGFloat = 28
    static let titleColor = Color(hex: "333333")
    static let subtitleColor = Color(hex: "707070")
    static let iconColor = Color(hex: "CFC7BE")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
      header

      if isSelectionEmpty {
        Text("Edit categories to calculate focus.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Design.subtitleColor)
      }

      VStack(spacing: Design.cardsSpacing) {
        TotalFocusCard(value: totalFocusText)

        LongestFocusCard(focusBlocks: focusBlocks)
      }
      .opacity(isSelectionEmpty ? 0.45 : 1)
    }
    .overlay(alignment: .topLeading) {
      if isEditingCategories {
        DayCategorySelectionEditor(
          categories: categories,
          selectedCategoryIDs: selectedCategoryIDs,
          helperText: "Pick the categories that count towards Focus",
          onToggle: onToggleCategory,
          onDone: onDoneEditing
        )
        .frame(width: Design.editorWidth, alignment: .leading)
        .offset(x: Design.editorOffsetX, y: Design.editorOffsetY)
        .onTapGesture {}
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 6) {
      Text("Your focus")
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(Design.titleColor)

      Image(systemName: "info.circle")
        .font(.system(size: 12))
        .foregroundColor(Design.iconColor)

      Spacer()

      CategoryEditCircleButton(
        action: onEditCategories,
        diameter: Design.editButtonSize
      )
    }
  }
}

private struct TotalFocusCard: View {
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text("Total focus time")
          .font(.custom("InstrumentSerif-Regular", size: 16))
          .foregroundColor(Color(hex: "333333"))

        Image(systemName: "info.circle")
          .font(.system(size: 12))
          .foregroundColor(Color(hex: "CFC7BE"))

        Spacer()
      }

      Text(value)
        .font(.custom("InstrumentSerif-Regular", size: 34))
        .foregroundColor(Color(hex: "F3854B"))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: "F7F7F7"))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
