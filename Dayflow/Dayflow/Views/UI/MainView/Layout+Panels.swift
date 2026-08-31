//
//  Layout+Panels.swift
//  Dayflow
//

import SwiftUI

struct TimelineCalendarButtonFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

enum TimelineAlignment {
  static let topInset: CGFloat = 24
  static let pickerRowOffset: CGFloat = -10
  static let categoryRowInset: CGFloat = 55
  static let headerContentGap: CGFloat = 18
}

enum TimelineNavigationLayout {
  static let arrowSize: CGFloat = 24
  static let hoverCircleSize: CGFloat = 30
  static let calendarGap: CGFloat = 4
}

enum LogoPosition {
  static let logoSize: CGFloat = 48
  static let logoVerticalOffset: CGFloat = 8
}

extension MainView {
  var contentStack: some View {
    // Two-column layout: left logo + sidebar; right white panel with header, filters, timeline
    HStack(alignment: .top, spacing: 0) {
      leftColumn
      rightPanel
    }
    .padding(0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var leftColumn: some View {
    // TAKT redesign: full-height dark rail (208px), wordmark inside the rail.
    // Logo badge above the gutter is gone — the rail carries the brand.
    SidebarView(
      selectedIcon: $selectedIcon,
      weeklyTrackedMinutes: Int(weeklyTrackedMinutes.rounded()),
      weeklyTargetMinutes: Self.weeklyTargetMinutes,
      clientCount: clientCount
    )
    .frame(width: TaktMetrics.railWidth)
    .fixedSize(horizontal: true, vertical: false)
    .frame(maxHeight: .infinity)
    .layoutPriority(1)
  }

  /// Weekly target for the rail's progress bar (40h default, matches the handoff).
  static let weeklyTargetMinutes: Int = 40 * 60

  /// Number of clients, shown in the rail next to Clients.
  private var clientCount: Int {
    StorageManager.shared.fetchClients().count
  }

  @ViewBuilder
  private var rightPanel: some View {
    // Right column: Main white panel including header + content
    ZStack {
      switch selectedIcon {
      case .settings:
        SettingsView()
          .padding(15)
      case .chat:
        ChatPanelView()
      case .flow:
        FlowView()
      case .agents:
        AgentsView()
      case .clients:
        ClientsView()
          .padding(15)
      case .daily:
        DailyView(selectedDate: $selectedDate)
      case .weekly:
        TaktWeeklyView()
      case .journal:
        JournalView()
          .padding(15)
      case .bug:
        BugReportView()
          .padding(15)
      case .timeline:
        GeometryReader { geo in
          timelinePanel(geo: geo)
        }
      }
    }
    .padding(0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // TAKT redesign: no rounded white panel, no shadow — the app fills its
    // window edge to edge; the rail + hairlines provide structure.
    .clipShape(Rectangle())
    .background(TaktColor.surface)
  }

  private var mainPanelBackground: some View {
    // Kept for API compatibility, no longer used by the timeline shell.
    Color.clear
  }

  private func timelinePanel(geo: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      HStack(alignment: .top, spacing: 0) {
        timelineLeftColumn
          .zIndex(1)
        Rectangle()
          .fill(Color(hex: "ECECEC"))
          .frame(width: timelineInspectorDividerWidth)
          .opacity(timelineInspectorDividerWidth == 0 ? 0 : 1)
          .frame(maxHeight: .infinity)
        timelineRightColumn(geo: geo)
      }
    }
    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
    .coordinateSpace(name: "TimelinePanel")
    .overlay(alignment: .topLeading) {
      if goalFlowPresentation == nil {
        timelineCalendarPopoverOverlay(panelWidth: geo.size.width)
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.9), value: goalFlowPresentation?.id)
    .onPreferenceChange(TimelineCalendarButtonFramePreferenceKey.self) { frame in
      timelineCalendarButtonFrame = frame
    }
  }

  private var timelineLeftColumn: some View {
    VStack(alignment: .leading, spacing: TimelineAlignment.headerContentGap) {
      timelineHeader
      timelineContent
    }
    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(.top, TimelineAlignment.topInset)
    .padding(.bottom, 15)
    .padding(.leading, 15)
    .padding(.trailing, 5)
    .overlay(alignment: .bottom) {
      timelineFooter
    }
    .coordinateSpace(name: "TimelinePane")
    .onPreferenceChange(TimelineTimeLabelFramesPreferenceKey.self) { frames in
      timelineTimeLabelFrames = frames
    }
    .onPreferenceChange(WeeklyHoursFramePreferenceKey.self) { frame in
      weeklyHoursFrame = frame
    }
  }

  private var timelineContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      ClientFilterBar(selectedClientIds: $clientFilter)
        .padding(.leading, 10 + TimelineAlignment.categoryRowInset)
        .opacity(contentOpacity)

      TabFilterBar(
        categories: categoryStore.editableCategories,
        idleCategory: categoryStore.idleCategory,
        onManageCategories: { showCategoryEditor = true }
      )
      .padding(.leading, 10 + TimelineAlignment.categoryRowInset)
      .opacity(contentOpacity)

      ZStack(alignment: .topLeading) {
        switch timelineMode {
        case .day:
          CanvasTimelineDataView(
            selectedDate: $selectedDate,
            selectedActivity: $selectedActivity,
            scrollToNowTick: $scrollToNowTick,
            hasAnyActivities: $hasAnyActivities,
            refreshTrigger: $refreshActivitiesTrigger,
            clientFilter: $clientFilter,
            weeklyHoursFrame: weeklyHoursFrame,
            weeklyHoursIntersectsCard: $weeklyHoursIntersectsCard,
            contentLeadingInset: 0,
            hourHeight: TimelineScale.hourHeight,
            cardTextFontSize: TimelineTypography.cardTextFontSize,
            cardTextFontWeight: TimelineTypography.cardTextFontWeight,
            timeLabelFontSize: TimelineTypography.timeLabelFontSize,
            cardIconLeadingInset: TimelineCardLayout.iconLeadingInset,
            cardIconTextSpacing: TimelineCardLayout.iconTextSpacing,
            cardFaviconSize: TimelineCardLayout.faviconSize,
            cardFaviconVerticalOffset: TimelineCardLayout.faviconVerticalOffset,
            cardCompactDurationThreshold: TimelineCardLayout.compactDurationThreshold,
            cardCompactVerticalPadding: TimelineCardLayout.compactVerticalPadding,
            cardNormalVerticalPadding: TimelineCardLayout.normalVerticalPadding,
            cardHoverScale: TimelineCardLayout.hoverScale,
            cardPressedScale: TimelineCardLayout.pressedScale
          )
          // Day is the zoomed-IN view (1/7 of a week). Entering Day feels
          // like diving into a single column: grow from 0.95 → 1 + fade in.
          // Exiting Day (to Week) shrinks 1 → 0.95 + fade out, matching the
          // "pull back to see more" feel when Week slides in behind it.
          .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
          .zIndex(timelineMode == .day ? 1 : 0)

        case .week:
          WeekTimelineGridView(
            selectedDate: $selectedDate,
            selectedActivity: $selectedActivity,
            hasAnyActivities: $hasAnyActivities,
            refreshTrigger: $refreshActivitiesTrigger,
            weekRange: timelineWeekRange,
            onSelectActivity: selectTimelineActivity,
            onClearSelection: { clearTimelineSelection() },
            weeklyHoursFrame: weeklyHoursFrame,
            weeklyHoursIntersectsCard: $weeklyHoursIntersectsCard,
            hideCardsForModeSwitch: hideWeekCardsDuringModeSwitch
          )
          // Week is the zoomed-OUT view (7 days). Entering Week from Day
          // feels like pulling back: start at 1.05 (slightly too large) and
          // settle to 1 + fade in. Exiting Week grows to 1.05 + fade out,
          // matching the "dive in" feel when Day settles to 1 behind it.
          .transition(.opacity.combined(with: .scale(scale: 1.05, anchor: .center)))
          .zIndex(timelineMode == .week ? 1 : 0)
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environmentObject(categoryStore)
      .opacity(contentOpacity)
      .animation(timelineModeContentAnimation, value: timelineMode)
    }
    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var cardsToReviewPromptCount: Int {
    guard cardsToReviewCount > 0 else { return 0 }
    if hasRecentTimelineReviewRating || hasAnyTimelineReviewRating == false {
      return cardsToReviewCount
    }
    return 0
  }

  private var timelineFooter: some View {
    return ZStack(alignment: .bottom) {
      HStack(alignment: .bottom) {
        Spacer()

        copyTimelineButton
          .opacity(contentOpacity)
      }
      .padding(.horizontal, 24)
    }
    .padding(.bottom, 17)
    .allowsHitTesting(true)
  }

  private func timelineRightColumn(geo: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      switch timelineMode {
      case .day:
        dayTimelineInspectorContent(geo: geo)
      case .week:
        weekTimelineInspectorContent(geo: geo)
      }
    }
    .frame(width: timelineInspectorWidth)
    .frame(maxHeight: .infinity)
    .opacity(contentOpacity)
    .clipped()
    .clipShape(Rectangle())
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func dayTimelineInspectorContent(geo: GeometryProxy) -> some View {
    let reviewPromptCount = cardsToReviewPromptCount

    if let activity = selectedActivity {
      timelineActivityInspector(activity: activity, geo: geo)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else {
      TaktDaySummaryInspector(
        selectedDate: selectedDate,
        categories: categoryStore.categories,
        storageManager: StorageManager.shared,
        cardsToReviewCount: reviewPromptCount,
        onReviewTap: {
          guard reviewPromptCount > 0 else { return }
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showTimelineReview = true
          }
        },
        onCopyTimeline: {
          copyTimelineToClipboard()
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
  }

  @ViewBuilder
  private func weekTimelineInspectorContent(geo: GeometryProxy) -> some View {
    if let activity = selectedActivity, isWeekTimelineInspectorVisible {
      timelineActivityInspector(activity: activity, geo: geo)
        .id(activity.id)
        .opacity(weekInspectorContentVisible ? 1 : 0)
        .offset(x: weekInspectorContentVisible ? 0 : 10)
        .animation(inspectorContentAnimation, value: weekInspectorContentVisible)
        .transition(.opacity.combined(with: .offset(x: 10)))
    }
  }

  private func timelineActivityInspector(activity: TimelineActivity, geo: GeometryProxy)
    -> some View
  {
    ZStack(alignment: .bottom) {
      ActivityCard(
        activity: activity,
        maxHeight: geo.size.height,
        scrollSummary: true,
        hasAnyActivities: hasAnyActivities,
        onCategoryChange: { category, activity in
          handleCategoryChange(to: category, for: activity)
        },
        onTitleChange: { newTitle, activity in
          handleTitleChange(to: newTitle, for: activity)
        },
        onTagChange: { selection, activity in
          handleTagChange(
            clientId: selection.clientId,
            projectId: selection.projectId,
            task: selection.task,
            billable: selection.billable,
            for: activity
          )
        },
        onNavigateToCategoryEditor: {
          showCategoryEditor = true
        },
        onRetryBatchCompleted: { batchId in
          refreshActivitiesTrigger &+= 1
          if selectedActivity?.batchId == batchId {
            clearTimelineSelection()
          }
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(!feedbackModalVisible)
      .padding(.bottom, rateSummaryFooterHeight)

      if !feedbackModalVisible {
        TimelineRateSummaryView(
          activityID: activity.id,
          onRate: handleTimelineRating,
          onDelete: handleTimelineDelete
        )
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!feedbackModalVisible)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottomLeading) {
      if let direction = feedbackDirection, feedbackModalVisible {
        TimelineFeedbackModal(
          message: $feedbackMessage,
          shareLogs: $feedbackShareLogs,
          direction: direction,
          mode: feedbackMode,
          content: .timeline,
          onSubmit: handleFeedbackSubmit,
          onClose: { dismissFeedbackModal() }
        )
        .padding(.leading, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  private var weeklyHoursFadeOpacity: Double {
    guard weeklyHoursFrame != .zero, !timelineTimeLabelFrames.isEmpty else { return 1 }
    var maxOverlap: CGFloat = 0
    for frame in timelineTimeLabelFrames {
      let intersection = weeklyHoursFrame.intersection(frame)
      if !intersection.isNull {
        maxOverlap = max(maxOverlap, intersection.height)
      }
    }
    guard maxOverlap > 0 else { return 1 }
    let clamped = min(maxOverlap, weeklyHoursFadeDistance)
    return Double(1 - (clamped / weeklyHoursFadeDistance))
  }

  private var weeklyHoursText: some View {
    let textColor = Color(red: 0.84, green: 0.65, blue: 0.52)
    let parts = timelineTrackedMinutesParts

    return
      (Text(parts.bold)
      .font(Font.custom("Figtree", size: 10).weight(.bold))
      .foregroundColor(textColor)
      + Text(parts.rest)
      .font(Font.custom("Figtree", size: 10).weight(.regular))
      .foregroundColor(textColor))
      .background(
        GeometryReader { proxy in
          Color.clear.preference(
            key: WeeklyHoursFramePreferenceKey.self,
            value: proxy.frame(in: .named("TimelinePane"))
          )
        }
      )
  }

  private var copyTimelineButton: some View {
    // TAKT redesign: flat secondary button (square, token colors).
    let enterTransition = AnyTransition.opacity
      .combined(with: .move(edge: .bottom))
    let exitTransition = AnyTransition.opacity
      .combined(with: .move(edge: .top))

    return Button(action: copyTimelineToClipboard) {
      ZStack {
        if copyTimelineState == .copying {
          ProgressView()
            .scaleEffect(0.6)
            .progressViewStyle(CircularProgressViewStyle(tint: TaktColor.textSecondary))
            .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        } else if copyTimelineState == .copied {
          HStack(spacing: 4) {
            Image(systemName: "checkmark")
              .font(.system(size: 11.5, weight: .medium))
            Text("Kopiert")
              .font(TaktFont.ui(11.5, .medium))
          }
          .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        } else {
          HStack(spacing: 4) {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 11.5, weight: .medium))
            Text("Timeline kopieren")
              .font(TaktFont.ui(11.5, .medium))
          }
          .transition(.asymmetric(insertion: enterTransition, removal: exitTransition))
        }
      }
      .animation(.spring(response: 0.3, dampingFraction: 0.85), value: copyTimelineState)
      .frame(height: 23)
      .padding(.horizontal, 12)
      .foregroundColor(TaktColor.textSecondary)
      .background(TaktColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: TaktMetrics.radius))
      .overlay(
        RoundedRectangle(cornerRadius: TaktMetrics.radius)
          .inset(by: 0.5)
          .stroke(TaktColor.borderStrong, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(ShrinkButtonStyle())
    .disabled(copyTimelineState == .copying)
    .hoverScaleEffect(
      enabled: copyTimelineState != .copying,
      scale: 1.02
    )
    .pointingHandCursorOnHover(
      enabled: copyTimelineState != .copying,
      reassertOnPressEnd: true
    )
    .accessibilityLabel(Text("Timeline in die Zwischenablage kopieren"))
  }
}

private struct ShrinkButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .dayflowPressScale(
        configuration.isPressed,
        pressedScale: 0.97,
        animation: .spring(response: 0.25, dampingFraction: 0.7)
      )
  }
}
