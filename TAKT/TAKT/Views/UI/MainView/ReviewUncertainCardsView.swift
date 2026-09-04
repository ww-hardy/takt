//
//  ReviewUncertainCardsView.swift
//  TAKT
//
//  TAKT: Review dialog for cards the AI could not confidently assign.
//  Presents each uncertain card with AI context and lets the user pick
//  a client/project, mark as internal, or skip.
//

import SwiftUI

struct ReviewUncertainCardsView: View {
  let uncertainCards: [CardTaggingService.UncertainCard]
  let clients: [Client]
  let projects: [Project]
  let onComplete: () -> Void

  @State private var currentIndex = 0
  @State private var selectedClientId: Int64?
  @State private var selectedProjectId: Int64?
  @State private var rememberRule = true
  @Environment(\.dismiss) private var dismiss

  private var currentCard: CardTaggingService.UncertainCard? {
    guard currentIndex < uncertainCards.count else { return nil }
    return uncertainCards[currentIndex]
  }

  private var projectsForSelectedClient: [Project] {
    guard let cid = selectedClientId else { return [] }
    return projects.filter { $0.clientId == cid }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text("Aktivitäten zuordnen")
              .font(TaktFont.display(16).weight(.bold))
              .foregroundColor(TaktColor.textPrimary)
            Text("\(uncertainCards.count) unklar")
              .font(TaktFont.ui(11, .semibold))
              .foregroundColor(TaktColor.accent)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(TaktColor.accentSoft)
              .overlay(
                Rectangle().stroke(TaktColor.accent.opacity(0.3), lineWidth: 1)
              )
          }
          Text("TAKT konnte diese Aktivitäten keinem Kunden eindeutig zuweisen.")
            .font(TaktFont.ui(12))
            .foregroundColor(TaktColor.textSecondary)
        }
        Spacer()
        Text("\(currentIndex + 1) von \(uncertainCards.count)")
          .font(TaktFont.ui(12, .semibold))
          .foregroundColor(TaktColor.textTertiary)
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 16)
      .overlay(
        Rectangle()
          .fill(TaktColor.borderHairline)
          .frame(height: 1),
        alignment: .bottom
      )

      // Card content
      if let card = currentCard {
        VStack(alignment: .leading, spacing: 12) {
          // Meta
          HStack {
            Text(formatTime(card.startTimestamp, card.endTimestamp))
              .font(TaktFont.caption)
              .foregroundColor(TaktColor.textTertiary)
            Spacer()
            Text(card.category)
              .font(TaktFont.caption)
              .foregroundColor(TaktColor.textTertiary)
          }

          // Title
          Text(card.title)
            .font(TaktFont.ui(14, .semibold))
            .foregroundColor(TaktColor.textPrimary)

          // Snippet
          Text(card.summary.prefix(300))
            .font(TaktFont.ui(12))
            .foregroundColor(TaktColor.textSecondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)

          // AI hint
          if let suggestion = card.aiSuggestion {
            HStack(spacing: 6) {
              Text("💡")
                .font(.system(size: 12))
              Text("KI-Einschätzung (\(Int(card.aiConfidence * 100))%): \(suggestion)")
                .font(TaktFont.ui(12))
                .foregroundColor(Color(hex: "9A3412"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "FFF7ED"))
            .overlay(
              Rectangle()
                .stroke(Color(hex: "FDBA74"), lineWidth: 1)
            )
          }

          // Options
          Text("WÄHLE ZUORDNUNG")
            .font(TaktFont.ui(10, .bold))
            .foregroundColor(TaktColor.textTertiary)
            .padding(.top, 4)

          // Client picker
          VStack(alignment: .leading, spacing: 4) {
            Text("Kunde")
              .font(TaktFont.ui(11, .semibold))
              .foregroundColor(TaktColor.textSecondary)
            Picker("Kunde", selection: $selectedClientId) {
              Text("— Keine Auswahl —").tag(Int64?.none)
              ForEach(clients) { c in
                Text(c.name).tag(c.id)
              }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedClientId) { _, _ in
              selectedProjectId = nil
            }
          }

          // Project picker (conditional)
          if let cid = selectedClientId, !projectsForSelectedClient.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Projekt")
                .font(TaktFont.ui(11, .semibold))
                .foregroundColor(TaktColor.textSecondary)
              Picker("Projekt", selection: $selectedProjectId) {
                Text("— Kein Projekt —").tag(Int64?.none)
                ForEach(projectsForSelectedClient) { p in
                  Text(p.name).tag(p.id)
                }
              }
              .pickerStyle(.menu)
            }
          }

          // Quick actions
          HStack(spacing: 8) {
            TaktButton(
              title: "Intern / Firma",
              variant: .secondary,
              icon: "building.2"
            ) {
              assignInternal()
            }
            TaktButton(
              title: "Privat / Pause",
              variant: .secondary,
              icon: "hand.raised"
            ) {
              assignSkip()
            }
          }
          .padding(.top, 4)
        }
        .padding(20)
        .background(TaktColor.surfaceSunken)
        .overlay(
          Rectangle().stroke(TaktColor.borderGrid, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
      }

      Spacer()

      // Footer
      VStack(spacing: 12) {
        Toggle(isOn: $rememberRule) {
          Text("Für zukünftige ähnliche Aktivitäten merken")
            .font(TaktFont.ui(12))
            .foregroundColor(TaktColor.textSecondary)
        }
        .toggleStyle(.checkbox)

        HStack {
          Button("Überspringen") {
            advance()
          }
          .buttonStyle(.plain)
          .font(TaktFont.ui(12, .medium))
          .foregroundColor(TaktColor.textSecondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .overlay(
            Rectangle().stroke(TaktColor.borderGrid, lineWidth: 1)
          )

          Spacer()

          TaktButton(
            title: "Zuweisen & Weiter",
            variant: .primary,
            icon: "arrow.right"
          ) {
            confirmAssignment()
          }
          .disabled(selectedClientId == nil)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .overlay(
        Rectangle()
          .fill(TaktColor.borderHairline)
          .frame(height: 1),
        alignment: .top
      )
    }
    .frame(width: 520, height: 580)
    .background(TaktColor.surface)
    .onAppear {
      if let card = currentCard {
        // Pre-select if AI suggested a client that was invalid
        _ = card
      }
    }
  }

  // MARK: - Actions

  private func confirmAssignment() {
    guard let card = currentCard,
      let clientId = selectedClientId
    else { return }

    let source = rememberRule ? "corrected" : "manual"
    StorageManager.shared.updateTimelineCardTagging(
      cardId: card.id,
      clientId: clientId,
      projectId: selectedProjectId,
      task: nil,
      billable: nil,
      tagSource: source,
      tagConfidence: 1.0
    )
    advance()
  }

  private func assignInternal() {
    guard let card = currentCard else { return }
    StorageManager.shared.updateTimelineCardTagging(
      cardId: card.id,
      clientId: nil,
      projectId: nil,
      task: nil,
      billable: false,
      tagSource: rememberRule ? "skip" : "manual",
      tagConfidence: 1.0
    )
    advance()
  }

  private func assignSkip() {
    guard let card = currentCard else { return }
    StorageManager.shared.updateTimelineCardTagging(
      cardId: card.id,
      clientId: nil,
      projectId: nil,
      task: nil,
      billable: nil,
      tagSource: rememberRule ? "skip" : "manual",
      tagConfidence: 1.0
    )
    advance()
  }

  private func advance() {
    selectedClientId = nil
    selectedProjectId = nil
    if currentIndex + 1 < uncertainCards.count {
      currentIndex += 1
    } else {
      onComplete()
      dismiss()
    }
  }

  private func formatTime(_ start: String, _ end: String) -> String {
    // Timestamps are ISO-ish; show a short label
    let s = start.prefix(16)
    let e = end.prefix(16)
    return "\(s) – \(e)"
  }
}
