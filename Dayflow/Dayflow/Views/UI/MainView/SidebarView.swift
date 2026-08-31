import SwiftUI

private enum SidebarMetrics {
  static let railWidth: CGFloat = 208
  static let itemPaddingV: CGFloat = 11
  static let itemPaddingH: CGFloat = 22
  static let wordmarkPaddingBottom: CGFloat = 34
  static let wordmarkDot: CGFloat = 11
  static let wordmarkFontSize: CGFloat = 21
  static let itemFontSize: CGFloat = 15
  static let countFontSize: CGFloat = 13
  static let weekLabelFontSize: CGFloat = 12
  static let weekTotalFontSize: CGFloat = 30
  static let progressHeight: CGFloat = 3
  static let progressCaptionFontSize: CGFloat = 13
  static let badgeDot: CGFloat = 7
}

enum SidebarIcon: CaseIterable {
  case timeline
  case daily
  case weekly
  case chat
  case agents
  case clients
  case journal
  case bug
  case settings

  var displayName: String {
    switch self {
    case .timeline: return "Timeline"
    case .daily: return "Tag"
    case .weekly: return "Woche"
    case .chat: return "Chat"
    case .agents: return "Agents"
    case .clients: return "Kunden"
    case .journal: return "Journal"
    case .bug: return "Bericht"
    case .settings: return "Einstellungen"
    }
  }

  var analyticsTabName: String {
    switch self {
    case .timeline: return "timeline"
    case .daily: return "daily"
    case .weekly: return "weekly"
    case .chat: return "dashboard"
    case .agents: return "agents"
    case .clients: return "clients"
    case .journal: return "journal"
    case .bug: return "bug_report"
    case .settings: return "settings"
    }
  }
}

struct SidebarView: View {
  @Binding var selectedIcon: SidebarIcon
  @ObservedObject private var badgeManager = NotificationBadgeManager.shared

  /// Weekly tracked minutes + target, filled by MainView via environment/binding.
  var weeklyTrackedMinutes: Int = 0
  var weeklyTargetMinutes: Int = 40 * 60

  /// Number of clients, shown in the rail next to Clients.
  var clientCount: Int = 0

  private var visibleIcons: [SidebarIcon] {
    SidebarIcon.allCases.filter { icon in
      if icon == .journal || icon == .agents { return false }
      return true
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      rail
      Spacer(minLength: 0)
    }
    .frame(width: SidebarMetrics.railWidth)
    .background(TaktColor.ink)
  }

  // MARK: - Rail

  private var rail: some View {
    VStack(alignment: .leading, spacing: 0) {
      wordmark
      navItems
      Spacer(minLength: 0)
      weekBlock
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(.vertical, 26)
  }

  private var wordmark: some View {
    HStack(spacing: 11) {
      Circle()
        .fill(TaktColor.accent)
        .frame(width: SidebarMetrics.wordmarkDot, height: SidebarMetrics.wordmarkDot)
      Text("TAKT")
        .font(TaktFont.display(SidebarMetrics.wordmarkFontSize).weight(.bold))
        .kerning(0.4)
        .foregroundColor(.white)
    }
    .padding(.horizontal, SidebarMetrics.itemPaddingH)
    .padding(.bottom, SidebarMetrics.wordmarkPaddingBottom)
  }

  private var navItems: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(visibleIcons, id: \.self) { icon in
        navItem(icon)
      }
    }
  }

  private func navItem(_ icon: SidebarIcon) -> some View {
    let isSelected = selectedIcon == icon
    return Button {
      selectedIcon = icon
    } label: {
      HStack {
        Text(icon.displayName)
          .font(TaktFont.ui(SidebarMetrics.itemFontSize, isSelected ? .semibold : .regular))
          .lineLimit(1)
        Spacer(minLength: 0)
        trailingSlot(for: icon)
      }
      .foregroundColor(isSelected ? .white : TaktColor.textMuted)
      .padding(.vertical, SidebarMetrics.itemPaddingV)
      .padding(.horizontal, SidebarMetrics.itemPaddingH)
      .background(isSelected ? TaktColor.inkRaised : Color.clear)
      .overlay(
        HStack {
          Rectangle()
            .fill(isSelected ? TaktColor.accent : Color.clear)
            .frame(width: 3)
          Spacer(minLength: 0)
        }
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      // hover handled via foreground change below; kept simple
    }
  }

  @ViewBuilder
  private func trailingSlot(for icon: SidebarIcon) -> some View {
    switch icon {
    case .clients:
      if clientCount > 0 {
        Text("\(clientCount)")
          .font(TaktFont.ui(SidebarMetrics.countFontSize))
          .foregroundColor(TaktColor.textTertiary)
      }
    case .daily:
      if badgeManager.hasPendingDailyRecap {
        Circle()
          .fill(TaktColor.accent)
          .frame(width: SidebarMetrics.badgeDot, height: SidebarMetrics.badgeDot)
      }
    default:
      EmptyView()
    }
  }

  // MARK: - This week block

  private var weekBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("DIESE WOCHE")
        .taktLabel()
        .foregroundColor(TaktColor.textSecondary)
      Text(formattedWeeklyTotal)
        .font(TaktFont.display(SidebarMetrics.weekTotalFontSize).weight(.bold))
        .foregroundColor(.white)
        .lineLimit(1)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(TaktColor.inkDivider)
          Rectangle()
            .fill(TaktColor.accent)
            .frame(width: proxy.size.width * weeklyProgress)
        }
      }
      .frame(height: SidebarMetrics.progressHeight)
      Text("\(Int(weeklyProgress * 100))% von \(formattedWeeklyTarget)")
        .font(TaktFont.ui(SidebarMetrics.progressCaptionFontSize))
        .foregroundColor(TaktColor.textTertiary)
    }
    .padding(.horizontal, SidebarMetrics.itemPaddingH)
  }

  private var weeklyProgress: CGFloat {
    guard weeklyTargetMinutes > 0 else { return 0 }
    return min(1, CGFloat(weeklyTrackedMinutes) / CGFloat(weeklyTargetMinutes))
  }

  private var formattedWeeklyTotal: String {
    let h = weeklyTrackedMinutes / 60
    let m = weeklyTrackedMinutes % 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
  }

  private var formattedWeeklyTarget: String {
    "\(weeklyTargetMinutes / 60)h"
  }
}
