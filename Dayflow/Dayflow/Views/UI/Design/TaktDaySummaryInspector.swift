//
//  TaktDaySummaryInspector.swift
//  Dayflow
//
//  TAKT redesign — flat day-summary inspector (1a). Uses the existing
//  DaySummaryStats computation functions; renders in the new visual language
//  (no gradients, square, one accent, hairlines).
//

import SwiftUI

struct TaktDaySummaryInspector: View {
  let selectedDate: Date
  let categories: [TimelineCategory]
  let storageManager: StorageManaging
  let cardsToReviewCount: Int
  let onReviewTap: () -> Void
  let onCopyTimeline: () -> Void

  @State private var timelineCards: [TimelineCard] = []
  @State private var hasLoaded = false

  private var timelineDayInfo: (dayString: String, startOfDay: Date, endOfDay: Date) {
    let timelineDate = timelineDisplayDate(from: selectedDate)
    let info = timelineDate.getDayInfoFor4AMBoundary()
    return (info.dayString, info.startOfDay, info.endOfDay)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      headerBlock
      statGrid
      whereTimeWent
      Spacer(minLength: 0)
      footerBlock
    }
    .padding(.horizontal, 26)
    .padding(.top, 26)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(TaktColor.surfaceSunken)
    .onAppear { loadData() }
    .onChange(of: selectedDate) { _ in loadData() }
    .onReceive(NotificationCenter.default.publisher(for: .timelineDataUpdated)) { _ in
      loadData()
    }
  }

  // MARK: - Data

  private func loadData() {
    timelineCards = storageManager.fetchTimelineCards(forDay: timelineDayInfo.dayString)
    hasLoaded = true
  }

  private var cardDurations: [DaySummaryStats.CardWithDuration] {
    DaySummaryStats.precomputeCardDurations(timelineCards)
  }

  private var emptySnapshots: [DayGoalCategorySnapshot] {
    []
  }

  private var dayStart: Date {
    timelineDayInfo.startOfDay
  }

  private var categoryDurations: [CategoryTimeData] {
    DaySummaryStats.computeCategoryDurations(from: cardDurations, categories: categories)
  }

  private var totalCaptured: TimeInterval {
    DaySummaryStats.computeTotalCapturedTime(from: cardDurations, categories: categories)
  }

  private var totalFocus: TimeInterval {
    DaySummaryStats.computeTotalFocusTime(
      from: cardDurations, snapshots: emptySnapshots, categories: categories)
  }

  private var totalDistracted: TimeInterval {
    DaySummaryStats.computeTotalDistractedTime(
      from: cardDurations, snapshots: emptySnapshots, categories: categories)
  }

  private var focusBlocks: [FocusBlock] {
    DaySummaryStats.computeFocusBlocks(
      from: cardDurations, snapshots: emptySnapshots, baseDate: dayStart,
      categories: categories)
  }

  private var contextSwitchCount: Int {
    max(0, focusBlocks.count - 1)
  }

  private var billableFraction: Double {
    let billableSeconds = timelineCards
      .filter { $0.billable == true }
      .reduce(TimeInterval(0)) { acc, card in
        acc + cardInterval(card)
      }
    guard totalCaptured > 0 else { return 0 }
    return min(1, billableSeconds / totalCaptured)
  }

  private func cardInterval(_ card: TimelineCard) -> TimeInterval {
    guard let start = parseTime(card.startTimestamp), let end = parseTime(card.endTimestamp) else {
      return 0
    }
    // Same-day only; the 4am boundary means start > end implies overnight wrap
    if end >= start {
      return TimeInterval(end - start) * 60
    }
    return 0
  }

  /// Parses "h:mm a" style time strings into minutes-of-day.
  private func parseTime(_ time: String) -> Int? {
    let cleaned = time.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = cleaned.lowercased()
    let isPM = lower.contains("pm")
    let digits = lower.replacingOccurrences(of: "pm", with: "")
      .replacingOccurrences(of: "am", with: "")
    let parts = digits.split(separator: ":")
    guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1].prefix(2)) else {
      return nil
    }
    var hour = h
    if isPM, hour < 12 { hour += 12 }
    if !isPM, hour == 12 { hour = 0 }
    return hour * 60 + m
  }

  // MARK: - Blocks

  private var headerBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("TAGESÜBERSICHT")
        .taktLabel()
      Text(daySummarySentence)
        .font(TaktFont.display(19).weight(.semibold))
        .foregroundColor(TaktColor.textPrimary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var daySummarySentence: String {
    let total = totalCaptured
    let hours = Int(total / 3600)
    let minutes = Int((total.truncatingRemainder(dividingBy: 3600)) / 60)
    let timeText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    let blockCount = max(1, focusBlocks.count)
    let blockText = blockCount == 1 ? "1 Fokusblock" : "\(blockCount) Fokusblocks"
    return "\(timeText) erfasst in \(blockText)."
  }

  private var statGrid: some View {
    let stats: [(label: String, value: String)] = [
      ("Längster Fokus", formatDuration(longestFocus)),
      ("Kontextwechsel", "\(contextSwitchCount)"),
      ("Abrechnbar", "\(Int(billableFraction * 100))%"),
      ("Ablenkung", formatDuration(totalDistracted)),
    ]
    return LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
      ],
      spacing: 1
    ) {
      ForEach(stats, id: \.label) { stat in
        VStack(alignment: .leading, spacing: 4) {
          Text(stat.label)
            .font(TaktFont.ui(12))
            .foregroundColor(TaktColor.textTertiary)
          Text(stat.value)
            .font(TaktFont.display(24).weight(.bold))
            .foregroundColor(TaktColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaktColor.surface)
      }
    }
    .background(TaktColor.borderGrid)
  }

  private var longestFocus: TimeInterval {
    focusBlocks.map { $0.endTime.timeIntervalSince($0.startTime) }.max() ?? 0
  }

  private var whereTimeWent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ZEITVERTEILUNG")
        .taktLabel()

      GeometryReader { proxy in
        HStack(spacing: 0) {
          ForEach(nonZeroCategories, id: \.id) { data in
            Rectangle()
              .fill(color(for: data))
              .frame(width: proxy.size.width * dataFraction(data))
          }
        }
      }
      .frame(height: 10)

      VStack(alignment: .leading, spacing: 9) {
        ForEach(nonZeroCategories, id: \.id) { data in
          HStack(spacing: 8) {
            Circle()
              .fill(color(for: data))
              .frame(width: 8, height: 8)
            Text(data.name)
              .font(TaktFont.ui(14))
              .foregroundColor(TaktColor.textPrimary)
            Spacer()
            Text(formatDuration(data.duration))
              .font(TaktFont.ui(14))
              .foregroundColor(TaktColor.textSecondary)
          }
        }
      }
    }
  }

  private var nonZeroCategories: [CategoryTimeData] {
    categoryDurations.filter { $0.duration > 0 }
      .sorted { $0.duration > $1.duration }
  }

  private var totalCategoryDuration: TimeInterval {
    nonZeroCategories.reduce(0) { $0 + $1.duration }
  }

  private func dataFraction(_ data: CategoryTimeData) -> CGFloat {
    guard totalCategoryDuration > 0 else { return 0 }
    return CGFloat(data.duration / totalCategoryDuration)
  }

  private func color(for data: CategoryTimeData) -> Color {
    Color(hex: data.colorHex)
  }

  private var footerBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      Rectangle()
        .fill(TaktColor.borderGrid)
        .frame(height: 1)
        .padding(.top, 6)

      Text(footerSentence)
        .font(TaktFont.ui(14))
        .foregroundColor(TaktColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        TaktButton(
          title: cardsToReviewCount > 0 ? "\(cardsToReviewCount) Karten prüfen" : "Karten prüfen",
          variant: .primary,
          action: onReviewTap
        )
        .disabled(cardsToReviewCount == 0)
        TaktButton(title: "Timeline kopieren", variant: .secondary, action: onCopyTimeline)
      }
    }
  }

  private var footerSentence: String {
    let billableText: String
    let billable = Int(billableFraction * 100)
    billableText = billable > 0 ? "\(billable)% abrechenbar" : "nicht abrechenbar"
    return "\(formatDuration(totalCaptured)) erfasst · \(billableText) · Tagesgrenze 4 Uhr."
  }

  private func formatDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
  }
}
