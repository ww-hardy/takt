import AppKit
import Foundation
import SwiftUI
import UserNotifications

extension DailyView {
  var canFinishDailyProviderOnboarding: Bool {
    guard !(isRefreshingProviderAvailability && providerAvailability.isEmpty) else {
      return false
    }

    return selectedProviderAvailability.isAvailable
  }
  var selectedProviderAvailability: DailyRecapProviderAvailability {
    providerAvailability[dailyRecapProvider]
      ?? DailyRecapProviderAvailability(
        isAvailable: true,
        detail: dailyRecapProvider.pickerSubtitle
      )
  }
  var canRegenerateStandup: Bool {
    dailyRecapProvider.canGenerate
      && selectedProviderAvailability.isAvailable
      && standupRegenerateState != .regenerating
  }
  var regenerateButtonHelpText: String {
    if !dailyRecapProvider.canGenerate {
      return DailyStandupPlaceholder.noProviderSelectedMessage
    }

    if !selectedProviderAvailability.isAvailable {
      return selectedProviderAvailability.detail
    }

    return "Regenerate standup highlights"
  }
  func dailyProviderButton(scale: CGFloat) -> some View {
    Button {
      if !isShowingProviderPicker {
        refreshProviderAvailability()
      }
      isShowingProviderPicker.toggle()
    } label: {
      ZStack {
        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .fill(TaktColor.surface)

        RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
          .stroke(TaktColor.borderStrong, lineWidth: TaktMetrics.hairline)

        Image(systemName: "gearshape.fill")
          .font(.system(size: 13 * scale, weight: .semibold))
          .foregroundStyle(TaktColor.standupAccent)
      }
      .frame(width: 38 * scale, height: 38 * scale)
      .contentShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
    }
    .buttonStyle(DailyCopyPressButtonStyle())
    .disabled(standupRegenerateState == .regenerating)
    .pointingHandCursorOnHover(
      enabled: standupRegenerateState != .regenerating,
      reassertOnPressEnd: true
    )
    .accessibilityLabel(Text("Tagesbericht-Provider wählen"))
    .help("Tagesbericht-Provider: \\(dailyRecapProvider.selectionLabel)")
    .popover(isPresented: $isShowingProviderPicker, arrowEdge: .bottom) {
      dailyProviderPicker(scale: scale)
        .padding(16)
        .frame(width: 312)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }
  }
  func dailyProviderPicker(scale: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 12 * scale) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2 * scale) {
          Text("Tagesbericht-Provider")
            .font(.custom("InstrumentSerif-Regular", size: 22 * scale))
            .foregroundStyle(TaktColor.textPrimary)

          Text("Wähle, wie der Tagesbericht erstellt wird, oder deaktiviere die Generierung.")
            .font(.custom("Figtree-Regular", size: 12 * scale))
            .foregroundStyle(TaktColor.textSecondary)
        }

        Spacer(minLength: 0)

        if isRefreshingProviderAvailability {
          ProgressView()
            .controlSize(.small)
            .tint(TaktColor.standupAccent)
        }
      }

      VStack(spacing: 8 * scale) {
        ForEach(DailyRecapProvider.allCases, id: \.self) { provider in
          let availability =
            providerAvailability[provider]
            ?? DailyRecapProviderAvailability(isAvailable: true, detail: provider.pickerSubtitle)
          let isSelected = dailyRecapProvider == provider

          Button {
            selectDailyRecapProvider(provider)
          } label: {
            HStack(alignment: .top, spacing: 10 * scale) {
              VStack(alignment: .leading, spacing: 2 * scale) {
                Text(provider.displayName)
                  .font(.custom("Figtree-SemiBold", size: 13 * scale))
                  .foregroundStyle(TaktColor.textPrimary)

                Text(availability.detail)
                  .font(.custom("Figtree-Regular", size: 12 * scale))
                  .foregroundStyle(
                    availability.isAvailable ? TaktColor.textSecondary : TaktColor.textMuted
                  )
                  .multilineTextAlignment(.leading)
              }

              Spacer(minLength: 0)

              Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(
                  isSelected ? TaktColor.accent : TaktColor.textTertiary
                )
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 10 * scale)
            .background(
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .fill(
                  isSelected
                    ? TaktColor.accentSoft
                    : TaktColor.surface
                )
            )
            .overlay(
              RoundedRectangle(cornerRadius: TaktMetrics.radiusControl)
                .stroke(
                  isSelected ? TaktColor.accent : TaktColor.borderGrid,
                  lineWidth: TaktMetrics.hairline
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: TaktMetrics.radiusControl))
          }
          .buttonStyle(.plain)
          .disabled(!availability.isAvailable)
          .pointingHandCursorOnHover(enabled: availability.isAvailable, reassertOnPressEnd: true)
        }
      }
    }
  }
  func selectDailyRecapProvider(_ provider: DailyRecapProvider) {
    let previousProvider = dailyRecapProvider
    guard previousProvider != provider else {
      isShowingProviderPicker = false
      return
    }

    dailyRecapProvider = provider
    DailyRecapGenerator.shared.persistSelectedProvider(provider)
    isShowingProviderPicker = false
    standupRegenerateResetTask?.cancel()
    standupRegenerateResetTask = nil
    standupRegenerateState = .idle
    loadedStandupDraftDay = nil
    loadedStandupFallbackSourceDay = nil

    AnalyticsService.shared.capture(
      "daily_provider_selected",
      [
        "previous_daily_provider": previousProvider.analyticsName,
        "previous_daily_provider_label": previousProvider.displayName,
        "daily_provider": provider.analyticsName,
        "daily_provider_label": provider.displayName,
        "daily_runtime": provider.runtimeLabel,
        "daily_model_or_tool": provider.modelOrTool as Any,
      ]
    )

    refreshWorkflowData()
  }
  func refreshProviderAvailability() {
    providerAvailabilityTask?.cancel()
    isRefreshingProviderAvailability = true

    providerAvailabilityTask = Task.detached(priority: .utility) {
      let snapshot = DailyRecapGenerator.shared.availabilitySnapshot()
      guard !Task.isCancelled else { return }

      await MainActor.run {
        providerAvailability = snapshot
        isRefreshingProviderAvailability = false
        providerAvailabilityTask = nil
      }
    }
  }
}
