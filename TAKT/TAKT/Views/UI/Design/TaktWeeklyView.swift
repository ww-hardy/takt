//
//  TaktWeeklyView.swift
//  TAKT
//
//  TAKT redesign — weekly review (2b) in the new visual language.
//  Two columns: left = focus heatmap + applications bars; right (400pt) =
//  categories donut + against last week + worth noticing.
//  Reuses the existing snapshot sections; renders flat/square/token-driven.
//

import SwiftUI

struct TaktWeeklyView: View {
  @EnvironmentObject private var categoryStore: CategoryStore
  @Environment(\.scenePhase) private var scenePhase

  @State private var weekRange: WeeklyDateRange
  @State private var dashboardSnapshot: WeeklyDashboardSnapshot
  @State private var isLoading = true
  @State private var weeklyLoadGeneration = 0
  // TAKT Option 4: adaptive Heatmap — gemessene Spaltenbreite steuert
  // die Bucket-Aufloesung (5/15/30 min), entprellt bei Resize.
  @State private var heatmapColumnWidth: CGFloat = 0
  @State private var heatmapBucketMinutes: Double = 5.0
  @State private var heatmapResizeTask: Task<Void, Never>?

  init() {
    let initialWeekRange = WeeklyDateRange.containing(Date())
    _weekRange = State(initialValue: initialWeekRange)
    _dashboardSnapshot = State(
      initialValue: WeeklyDashboardBuilder.build(
        cards: [],
        previousWeekCards: [],
        categories: [],
        weekRange: initialWeekRange
      )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      HStack(alignment: .top, spacing: 0) {
        leftColumn
          .frame(maxWidth: .infinity)
        rightColumn
          .frame(width: 400)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(TaktColor.surface)
    .task(id: weekRange) {
      await loadWeeklyData(for: weekRange, categories: categoryStore.categories)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task {
          await loadWeeklyData(for: weekRange, categories: categoryStore.categories)
        }
      }
    }
  }

  @MainActor
  private func loadWeeklyData(
    for range: WeeklyDateRange,
    categories: [TimelineCategory]
  ) async {
    weeklyLoadGeneration += 1
    let loadGeneration = weeklyLoadGeneration

    isLoading = true

    let loadResult = await Task.detached(priority: .userInitiated) {
      let previousRange = range.shifted(byWeeks: -1)
      let cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
        from: range.weekStart,
        to: range.weekEnd
      )
      let previousCards = StorageManager.shared.fetchTimelineCardsByTimeRange(
        from: previousRange.weekStart,
        to: previousRange.weekEnd
      )
      let snapshot = WeeklyDashboardBuilder.build(
        cards: cards,
        previousWeekCards: previousCards,
        categories: categories,
        weekRange: range
      )
      return snapshot
    }.value

    guard !Task.isCancelled, range == weekRange, loadGeneration == weeklyLoadGeneration else {
      return
    }
    dashboardSnapshot = loadResult
    isLoading = false
  }

  private func showPreviousWeek() {
    weekRange = weekRange.shifted(byWeeks: -1)
  }

  private func showNextWeek() {
    guard weekRange.canNavigateForward else { return }
    weekRange = weekRange.shifted(byWeeks: 1)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center) {
      HStack(spacing: 0) {
        squareChevron("chevron.left") { showPreviousWeek() }
        Text(weekRange.title)
          .font(TaktFont.display(24).weight(.bold))
          .foregroundColor(TaktColor.textPrimary)
          .padding(.horizontal, 12)
        squareChevron("chevron.right", enabled: weekRange.canNavigateForward) { showNextWeek() }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(formatMinutes(dashboardSnapshot.donut.totalMinutes))
          .font(TaktFont.display(32).weight(.bold))
          .foregroundColor(TaktColor.textPrimary)
        Text("erfasst, ohne Leerlauf")
          .font(TaktFont.ui(15))
          .foregroundColor(TaktColor.textSecondary)
      }
    }
    .padding(.horizontal, 34)
    .padding(.top, 26)
    .padding(.bottom, 20)
    .overlay(
      Rectangle()
        .fill(TaktColor.borderHairline)
        .frame(height: 1),
      alignment: .bottom
    )
  }

  private func squareChevron(_ systemName: String, enabled: Bool = true, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(enabled ? TaktColor.textSecondary : TaktColor.textMuted)
        .frame(width: 30, height: 30)
        .background(TaktColor.surface)
        .overlay(
          Rectangle()
            .stroke(TaktColor.borderStrong, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .pointingHandCursor()
  }

  // MARK: - Left column

  private var leftColumn: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 26) {
        focusHeatmapBlock
        applicationsBlock
      }
      .padding(.horizontal, 30)
      .padding(.top, 24)
      .padding(.bottom, 24)
    }
    .background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: HeatmapColumnWidthPreferenceKey.self,
          value: proxy.size.width
        )
      }
    )
    .onPreferenceChange(HeatmapColumnWidthPreferenceKey.self) { width in
      handleHeatmapWidthChange(width)
    }
  }

  private func handleHeatmapWidthChange(_ width: CGFloat) {
    heatmapColumnWidth = width
    let targetBucket: Double
    switch width {
    case ..<520: targetBucket = 30
    case ..<900: targetBucket = 15
    default: targetBucket = 5
    }
    guard targetBucket != heatmapBucketMinutes else { return }

    heatmapResizeTask?.cancel()
    heatmapResizeTask = Task {
      // Entprellt: 250 ms warten, dann Snapshot mit neuer Aufloesung bauen.
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        heatmapBucketMinutes = targetBucket
        rebuildHeatmapOnly(bucketMinutes: targetBucket)
      }
    }
  }

  /// Baut nur die Heatmap mit neuer Bucket-Aufloesung neu — Donut, Overview,
  /// Treemap etc. bleiben unveraendert.
  private func rebuildHeatmapOnly(bucketMinutes: Double) {
    let range = weekRange
    let categories = categoryStore.categories
    weeklyLoadGeneration += 1
    let generation = weeklyLoadGeneration
    isLoading = true
    Task.detached(priority: .userInitiated) {
      let cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
        from: range.weekStart,
        to: range.weekEnd
      )
      let heatmap = WeeklyDashboardBuilder.buildHeatmap(
        fromCards: cards,
        categories: categories,
        weekRange: range,
        bucketMinutes: bucketMinutes
      )
      await MainActor.run {
        guard generation == weeklyLoadGeneration else { return }
        dashboardSnapshot.heatmap = heatmap
        isLoading = false
      }
    }
  }

  private var focusHeatmapBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("FOKUS-HEATMAP")
        .taktLabel()
      // TAKT Option 4: width == nil -> adaptive Karte, Zellen skalieren
      // mit der Spaltenbreite; Bucket-Aufloesung folgt der Breite.
      WeeklyFocusHeatmapSection(
        snapshot: dashboardSnapshot.heatmap,
        width: nil,
        cellGap: 1,
        usesScrollContainers: false
      )
    }
  }

  private var applicationsBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ANWENDUNGEN")
        .taktLabel()

      let apps = topApps
      if apps.isEmpty {
        Text("Diese Woche keine Anwendungen erfasst.")
          .font(TaktFont.body)
          .foregroundColor(TaktColor.textSecondary)
      } else {
        let maxMinutes = apps.map(\.minutes).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
          ForEach(apps, id: \.id) { app in
            HStack(spacing: 12) {
              Text(app.name)
                .font(TaktFont.ui(14))
                .foregroundColor(TaktColor.textPrimary)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)

              GeometryReader { proxy in
                ZStack(alignment: .leading) {
                  Rectangle()
                    .fill(TaktColor.heatmap0)
                  Rectangle()
                    .fill(TaktColor.accent)
                    .frame(width: proxy.size.width * CGFloat(app.minutes) / CGFloat(maxMinutes))
                }
              }
              .frame(height: 14)

              Text(formatMinutes(app.minutes))
                .font(TaktFont.ui(13))
                .foregroundColor(TaktColor.textSecondary)
                .frame(width: 62, alignment: .trailing)
            }
          }
        }
      }
    }
  }

  private var topApps: [WeeklySankeySnapshotApp] {
    let all = dashboardSnapshot.sankey.apps.sorted { $0.minutes > $1.minutes }
    let top = Array(all.prefix(7))
    // Coalesce the overflow into an "Sonstige" bucket (matches the existing rule)
    let overflowMinutes = all.dropFirst(7).reduce(0) { $0 + $1.minutes }
    if overflowMinutes > 0 {
      var result = top
      result.append(
        WeeklySankeySnapshotApp(
          id: "other", name: "Sonstige", minutes: overflowMinutes,
          colorHex: "BBBBBB", faviconPrimaryRaw: nil, faviconSecondaryRaw: nil))
      return result
    }
    return top
  }

  // MARK: - Right column

  private var rightColumn: some View {
    VStack(alignment: .leading, spacing: 24) {
      donutBlock
      againstLastWeekBlock
      Spacer(minLength: 0)
      worthNoticingBlock
    }
    .padding(.horizontal, 26)
    .padding(.top, 24)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(TaktColor.surfaceSunken)
    .overlay(
      Rectangle()
        .fill(TaktColor.borderHairline)
        .frame(width: 1),
      alignment: .leading
    )
  }

  private var donutBlock: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("KATEGORIEN")
        .taktLabel()

      HStack(alignment: .center, spacing: 20) {
        // Donut with hard stops (discrete arcs)
        ZStack {
          Circle()
            .fill(TaktColor.surfaceSunken)
            .frame(width: 118, height: 118)
          ForEach(donutArcs, id: \.id) { arc in
            Circle()
              .trim(from: arc.start, to: arc.end)
              .stroke(Color(hex: arc.colorHex), style: StrokeStyle(lineWidth: 22))
              .frame(width: 92, height: 92)
              .rotationEffect(.degrees(-90))
          }
          VStack(spacing: 0) {
            Text(formatMinutes(dashboardSnapshot.donut.totalMinutes))
              .font(TaktFont.display(19).weight(.bold))
              .foregroundColor(TaktColor.textPrimary)
            Text("gesamt")
              .font(TaktFont.ui(11))
              .foregroundColor(TaktColor.textTertiary)
          }
        }

        VStack(alignment: .leading, spacing: 9) {
          ForEach(dashboardSnapshot.donut.items) { item in
            HStack(spacing: 8) {
              Circle()
                .fill(Color(hex: item.colorHex))
                .frame(width: 8, height: 8)
              Text(item.name)
                .font(TaktFont.ui(14))
                .foregroundColor(TaktColor.textPrimary)
              Spacer()
              Text(formatMinutes(item.minutes))
                .font(TaktFont.ui(14))
                .foregroundColor(TaktColor.textSecondary)
            }
          }
        }
        .frame(maxWidth: .infinity)
      }

      Text("Leerlauf zählt nicht in die Summe.")
        .font(TaktFont.ui(13))
        .foregroundColor(TaktColor.textTertiary)
    }
  }

  private var donutArcs: [(id: String, start: Double, end: Double, colorHex: String)] {
    let items = dashboardSnapshot.donut.items
    let total = max(1, items.reduce(0) { $0 + $1.minutes })
    var start: Double = 0
    var arcs: [(String, Double, Double, String)] = []
    for item in items {
      let fraction = Double(item.minutes) / Double(total)
      let end = start + fraction
      arcs.append((item.id, start, min(end, 1.0), item.colorHex))
      start = end
    }
    return arcs
  }

  private var againstLastWeekBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("GEGENÜBER LETZTER WOCHE")
        .taktLabel()

      VStack(spacing: 0) {
        comparisonRow("Erfasst", value: formatMinutes(dashboardSnapshot.donut.totalMinutes), delta: nil)
        comparisonRow("Kontextwechsel", value: "0", delta: nil)
        comparisonRow("Längster Fokus", value: "—", delta: nil)
        comparisonRow("Ablenkung", value: "—", delta: nil)
      }
      .background(TaktColor.borderGrid)
      .overlay(
        Rectangle()
          .stroke(TaktColor.borderGrid, lineWidth: 1)
      )
    }
  }

  private func comparisonRow(_ label: String, value: String, delta: String?) -> some View {
    HStack {
      Text(label)
        .font(TaktFont.ui(14))
        .foregroundColor(TaktColor.textSecondary)
      Spacer()
      Text(value)
        .font(TaktFont.ui(14, .semibold))
        .foregroundColor(TaktColor.textPrimary)
      if let delta {
        Text(delta)
          .font(TaktFont.ui(14, .semibold))
          .foregroundColor(delta.hasPrefix("+") ? TaktColor.positive : TaktColor.negative)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(TaktColor.surface)
    .overlay(
      Rectangle()
        .fill(TaktColor.borderGrid)
        .frame(height: 1),
      alignment: .top
    )
  }

  private var worthNoticingBlock: some View {
    VStack(alignment: .leading, spacing: 10) {
      Rectangle()
        .fill(TaktColor.borderGrid)
        .frame(height: 1)
        .padding(.top, 6)

      Text("BEMERKENSWERT")
        .taktLabel()

      Text(worthNoticingText)
        .font(TaktFont.ui(15))
        .foregroundColor(TaktColor.textPrimary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var worthNoticingText: String {
    let items = dashboardSnapshot.donut.items
    if let top = items.max(by: { $0.minutes < $1.minutes }) {
      return "\(top.name) led the week at \(formatMinutes(top.minutes)). Keep an eye on whether that focus is moving you toward your goals."
    }
    return "Diese Woche keine Daten erfasst."
  }

  private func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h > 0 {
      return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
    return "\(m)m"
  }
}

struct HeatmapColumnWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
