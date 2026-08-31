//
//  ClientsView.swift
//  Dayflow
//
//  TAKT: Multi-client recognition — manage clients and projects.
//  The short description (detail) is the manual first step that later
//  feeds the AI recognition pass.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClientsView: View {
  @State private var clients: [Client] = []
  @State private var projects: [Project] = []
  @State private var summaryRows: [StorageManager.ClientSummaryRow] = []
  @State private var selectedClientId: Int64?
  @State private var isTagging = false
  @State private var taggingStatus: String?
  @State private var taggingError: String?

  @State private var showAddClient = false
  @State private var showEditClient = false
  @State private var editingClient: Client?
  @State private var showAddProject = false
  @State private var exportStatus: String?

  fileprivate static let palette: [(String, String)] = [
    ("Blau", "#2E6F9E"),
    ("Grün", "#3D8B6E"),
    ("Orange", "#D97B3A"),
    ("Violett", "#7A5FA0"),
    ("Rot", "#B5513D"),
    ("Grau", "#6B7280"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if clients.isEmpty {
        emptyState
      } else {
        HStack(alignment: .top, spacing: 0) {
          clientList
            .frame(width: TaktMetrics.clientListWidth)
            .overlay(
              Rectangle()
                .fill(TaktColor.borderHairline)
                .frame(width: 1),
              alignment: .trailing
            )
          summarySection
            .frame(maxWidth: .infinity)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear(perform: reload)
    .onReceive(NotificationCenter.default.publisher(for: .timelineDataUpdated)) { _ in
      reloadSummary()
    }
    .sheet(isPresented: $showAddClient) {
      ClientEditorSheet { reload() }
    }
    .sheet(isPresented: $showEditClient) {
      if let editingClient {
        ClientEditorSheet(client: editingClient) { reload() }
      }
    }
    .sheet(isPresented: $showAddProject) {
      if let selectedClientId {
        AddProjectSheet(clientId: selectedClientId) { reload() }
      }
    }
    .alert("KI-Erkennung fehlgeschlagen", isPresented: Binding(
      get: { taggingError != nil },
      set: { if !$0 { taggingError = nil } }
    )) {
      Button("OK", role: .cancel) { taggingError = nil }
    } message: {
      Text(taggingError ?? "")
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Kunden & Projekte")
          .font(TaktFont.display(34).weight(.bold))
          .foregroundColor(TaktColor.textPrimary)
        Text("Beschreibe deine Kunden kurz — das erleichtert die automatische Erkennung.")
          .font(TaktFont.ui(15))
          .foregroundColor(TaktColor.textSecondary)
      }
      Spacer()
      TaktButton(title: "Neuer Kunde", variant: .primary, icon: "plus") {
        showAddClient = true
      }
    }
    .padding(.horizontal, 34)
    .padding(.top, 30)
    .padding(.bottom, 22)
    .overlay(
      Rectangle()
        .fill(TaktColor.borderHairline)
        .frame(height: 1),
      alignment: .bottom
    )
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "briefcase")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("Noch keine Kunden angelegt")
        .font(.headline)
      Text("Lege zuerst deine Kunden an (z. B. „ICF Switzerland“ oder „Wertwandler“). Danach kannst du auf der Timeline jede Aktivität einem Kunden und Projekt zuordnen.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      Button("Ersten Kunden anlegen") {
        showAddClient = true
      }
      .buttonStyle(.borderedProminent)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
  }

  private var clientList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        Text("\(clients.count) KUNDE\(clients.count == 1 ? "" : "N")")
          .taktLabel()
          .padding(.horizontal, 26)
          .padding(.top, 24)
        ForEach(clients) { client in
          ClientRow(
            client: client,
            projects: projects.filter { $0.clientId == client.id },
            isSelected: selectedClientId == client.id
          ) {
            selectedClientId = client.id
            showAddProject = true
          } onEdit: {
            editingClient = client
            showEditClient = true
          } onDelete: {
            if let id = client.id {
              StorageManager.shared.deleteClient(id: id)
              if selectedClientId == id { selectedClientId = nil }
              reload()
            }
          }
          .padding(.horizontal, 26)
        }
      }
      .padding(.bottom, 24)
    }
  }

  // MARK: - Summary & export (TAKT)

  private var summarySection: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 4) {
          Text("ZEITÜBERSICHT · DIESE WOCHE")
            .taktLabel()
          let total = summaryRows.reduce(0) { $0 + $1.totalHours }
          let billable = summaryRows.reduce(0) { $0 + $1.billableHours }
          Text(String(format: "%.2f h · %.2f h abrechenbar", total, billable))
            .font(TaktFont.display(28).weight(.bold))
            .foregroundColor(TaktColor.textPrimary)
        }
        Spacer()
        if let taggingStatus {
          Text(taggingStatus)
            .font(TaktFont.caption)
            .foregroundColor(TaktColor.textTertiary)
        }
        if let exportStatus {
          Text(exportStatus)
            .font(TaktFont.caption)
            .foregroundColor(TaktColor.textTertiary)
        }
        TaktButton(title: "CSV", variant: .secondary, icon: "doc.text") {
          exportCSV()
        }
        .disabled(summaryRows.isEmpty)
        TaktButton(title: "Markdown", variant: .secondary, icon: "doc.richtext") {
          exportMarkdown()
        }
        .disabled(summaryRows.isEmpty)
      }

      // Table on a 1px grid
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Text("KUNDE").frame(maxWidth: .infinity, alignment: .leading)
          Text("PROJEKT").frame(maxWidth: .infinity, alignment: .leading)
          Text("STUNDEN").frame(width: 74, alignment: .trailing)
          Text("ABRECHNBAR").frame(width: 96, alignment: .trailing)
        }
        .font(TaktFont.label)
        .foregroundColor(TaktColor.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TaktColor.surfaceSunken)

        if summaryRows.isEmpty {
          Text("Diese Woche noch keine getaggten Aktivitäten. Weise Karten in der Timeline Kunde und Projekt zu.")
            .font(TaktFont.body)
            .foregroundColor(TaktColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        } else {
          ForEach(summaryRows) { row in
            HStack(spacing: 0) {
              Text(row.clientName).frame(maxWidth: .infinity, alignment: .leading)
              Text(row.projectName ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(TaktColor.textSecondary)
              Text(String(format: "%.2f", row.totalHours))
                .frame(width: 74, alignment: .trailing)
                .font(.system(.body, design: .monospaced))
              Text(String(format: "%.2f", row.billableHours))
                .frame(width: 96, alignment: .trailing)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(row.billableHours > 0 ? TaktColor.accentPressed : TaktColor.textTertiary)
            }
            .font(TaktFont.ui(14))
            .foregroundColor(TaktColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(TaktColor.surface)
            .overlay(
              Rectangle()
                .fill(TaktColor.borderGrid)
                .frame(height: 1),
              alignment: .top
            )
          }
        }
      }
      .background(TaktColor.borderGrid)
      .overlay(
        Rectangle()
          .stroke(TaktColor.borderGrid, lineWidth: 1)
      )

      // AI detection banner
      aiDetectionBanner

      Text("Die KI-Erkennung schlägt Kunde und Projekt anhand deiner Kundenbeschreibungen vor — prüfen und in der Timeline korrigieren.")
        .font(TaktFont.ui(14))
        .foregroundColor(TaktColor.textTertiary)
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 24)
  }

  private var aiDetectionBanner: some View {
    let candidateCount = taggingCandidateCountThisWeek()
    return VStack(alignment: .leading, spacing: 8) {
      Text(
        candidateCount == 0
          ? "Diese Woche ist alles erkannt — kein Handlungsbedarf."
          : "\(candidateCount) erkennbare Aktivitäten diese Woche"
      )
        .font(TaktFont.ui(15, .semibold))
        .foregroundColor(TaktColor.textPrimary)
      if candidateCount > 0 {
        Text("Die KI-Erkennung nutzt deine Kundenbeschreibungen, um für jede Karte Kunde und Projekt vorzuschlagen.")
          .font(TaktFont.ui(14))
          .foregroundColor(Color(hex: "7A5A32"))
        TaktButton(
          title: isTagging ? "Erkenne…" : "KI-Erkennung",
          variant: .primary,
          icon: isTagging ? nil : "sparkles"
        ) {
          runAITagging()
        }
        .disabled(isTagging || clients.isEmpty)
        .overlay {
          if isTagging {
            ProgressView()
              .controlSize(.small)
          }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(TaktColor.accentSoft)
    .overlay(
      Rectangle()
        .stroke(Color(hex: "FFE0B2"), lineWidth: 1)
    )
  }

  private func taggingCandidatesThisWeek() -> [TimelineCard] {
    let range = currentWeekRange()
    let cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
      from: range.start, to: range.end)
    return CardTaggingService.taggingCandidates(from: cards)
  }

  private func taggingCandidateCountThisWeek() -> Int {
    taggingCandidatesThisWeek().count
  }

  private func runAITagging() {
    guard !isTagging else { return }
    isTagging = true
    taggingStatus = nil
    taggingError = nil

    let range = currentWeekRange()
    let cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
      from: range.start, to: range.end)
    let untagged = CardTaggingService.taggingCandidates(from: cards)

    guard !untagged.isEmpty else {
      isTagging = false
      taggingStatus = "Keine erkennbaren Aktivitäten"
      clearStatusSoon()
      return
    }

    Task { @MainActor in
      do {
        let outcome = try await CardTaggingService.shared.tagCards(untagged)
        reload()
        taggingStatus =
          "\(outcome.taggedCount) Karte(n) erkannt"
          + (outcome.skippedCount > 0 ? " · \(outcome.skippedCount) übersprungen" : "")
      } catch {
        taggingError = error.localizedDescription
      }
      isTagging = false
      clearStatusSoon()
    }
  }

  private func clearStatusSoon() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      taggingStatus = nil
    }
  }

  private func currentWeekRange() -> (start: Date, end: Date) {
    let calendar = Calendar.current
    let now = Date()
    let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday
    let daysSinceMonday = (weekday + 5) % 7  // Monday = 0
    guard
      let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: calendar.startOfDay(for: now)),
      let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)
    else {
      return (now, now)
    }
    return (monday, nextMonday)
  }

  private func reloadSummary() {
    let range = currentWeekRange()
    summaryRows = StorageManager.shared.clientSummary(from: range.start, to: range.end)
  }

  private func exportCSV() {
    let range = currentWeekRange()
    let content = StorageManager.shared.clientSummaryCSV(summaryRows, from: range.start, to: range.end)
    saveFile(content: content, defaultName: "takt-kunden-uebersicht.csv", fileType: "csv")
  }

  private func exportMarkdown() {
    let range = currentWeekRange()
    let content = StorageManager.shared.clientSummaryMarkdown(summaryRows, from: range.start, to: range.end)
    saveFile(content: content, defaultName: "takt-kunden-uebersicht.md", fileType: "md")
  }

  private func saveFile(content: String, defaultName: String, fileType: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = defaultName
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try content.write(to: url, atomically: true, encoding: .utf8)
        exportStatus = "Gespeichert ✓"
      } catch {
        exportStatus = "Fehler beim Speichern"
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        exportStatus = nil
      }
    }
  }

  private func reload() {
    clients = StorageManager.shared.fetchClients()
    projects = StorageManager.shared.fetchProjects()
    reloadSummary()
  }
}

private struct ClientRow: View {
  let client: Client
  let projects: [Project]
  let isSelected: Bool
  let onAddProject: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Circle()
          .fill(color(from: client.color))
          .frame(width: 8, height: 8)
        Text(client.name)
          .font(TaktFont.title)
          .foregroundColor(TaktColor.textPrimary)
        if client.defaultBillable {
          TaktBadge(title: "billable", variant: .orange)
        }
        Spacer()
        Button("+ Projekt", action: onAddProject)
          .buttonStyle(.plain)
          .font(TaktFont.ui(13))
          .foregroundColor(TaktColor.textTertiary)
          .onHover { hovering in
            // handled by style; kept simple
          }
          .pointingHandCursor()
        Button(action: onEdit) {
          Image(systemName: "pencil")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(TaktColor.textTertiary)
        .help("Kunde bearbeiten")
        .pointingHandCursor()
        Button(role: .destructive) {
          onDelete()
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(TaktColor.textTertiary)
        .pointingHandCursor()
      }
      if let detail = client.detail, !detail.isEmpty {
        Text(detail)
          .font(TaktFont.ui(14))
          .foregroundColor(TaktColor.textSecondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !projects.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(projects) { project in
            TaktBadge(title: project.name, variant: .neutral)
          }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(TaktColor.surface)
    .overlay(
      Rectangle()
        .stroke(isSelected ? TaktColor.ink : TaktColor.borderHairline, lineWidth: 1)
    )
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(color(from: client.color))
        .frame(width: 4)
    }
    .contentShape(Rectangle())
  }

  private func color(from hex: String?) -> Color {
    guard let hex, hex.count == 7 else { return .secondary }
    let r = hex.prefix(3).suffix(2)
    let g = hex.prefix(5).suffix(2)
    let b = hex.suffix(2)
    func value(_ s: Substring) -> Double {
      Double(Int(s, radix: 16) ?? 0) / 255.0
    }
    return Color(red: value(r), green: value(g), blue: value(b))
  }
}

private struct ClientEditorSheet: View {
  let client: Client?
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var detail = ""
  @State private var color = ClientsView.palette[0].1
  @State private var defaultBillable = false

  init(client: Client? = nil, onSaved: @escaping () -> Void) {
    self.client = client
    self.onSaved = onSaved
    _name = State(initialValue: client?.name ?? "")
    _detail = State(initialValue: client?.detail ?? "")
    _color = State(initialValue: client?.color ?? ClientsView.palette[0].1)
    _defaultBillable = State(initialValue: client?.defaultBillable ?? false)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(client == nil ? "Neuer Kunde" : "Kunde bearbeiten")
        .font(.title3)
        .fontWeight(.semibold)
      TextField("Name (z. B. ICF Switzerland)", text: $name)
        .textFieldStyle(.roundedBorder)
      TextField("Kurzbeschreibung (was machst du für diesen Kunden?)", text: $detail, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...4)
      HStack {
        Text("Farbe")
        ForEach(ClientsView.palette, id: \.1) { entry in
          Circle()
            .fill(Color(hex: entry.1))
            .frame(width: 20, height: 20)
            .overlay(
              Circle().stroke(color == entry.1 ? Color.primary : Color.clear, lineWidth: 2)
            )
            .onTapGesture { color = entry.1 }
        }
      }
      Toggle("Standardmäßig abrechenbar", isOn: $defaultBillable)
      HStack {
        Spacer()
        Button("Abbrechen") { dismiss() }
        Button("Speichern") {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          if let client {
            StorageManager.shared.updateClient(
              Client(
                id: client.id,
                name: trimmed,
                detail: detail,
                color: color,
                defaultBillable: defaultBillable))
          } else {
            StorageManager.shared.saveClient(
              Client(name: trimmed, detail: detail, color: color, defaultBillable: defaultBillable))
          }
          onSaved()
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Spacer()
    }
    .padding(20)
    .frame(width: 420, height: 260)
  }
}

private struct AddProjectSheet: View {
  let clientId: Int64
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var detail = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Neues Projekt")
        .font(.title3)
        .fontWeight(.semibold)
      TextField("Name (z. B. Strategiewerkstatt)", text: $name)
        .textFieldStyle(.roundedBorder)
      TextField("Kurzbeschreibung (optional)", text: $detail, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...4)
      HStack {
        Spacer()
        Button("Abbrechen") { dismiss() }
        Button("Speichern") {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          StorageManager.shared.saveProject(
            Project(clientId: clientId, name: trimmed, detail: detail))
          onSaved()
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Spacer()
    }
    .padding(20)
    .frame(width: 420, height: 200)
  }
}

private struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: maxWidth, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
