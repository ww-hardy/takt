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
    VStack(alignment: .leading, spacing: 14) {
      header
      if clients.isEmpty {
        emptyState
      } else {
        clientList
        summarySection
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear(perform: reload)
    .onReceive(NotificationCenter.default.publisher(for: .timelineDataUpdated)) { _ in
      reloadSummary()
    }
    .sheet(isPresented: $showAddClient) {
      AddClientSheet { reload() }
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
      VStack(alignment: .leading, spacing: 2) {
        Text("Kunden & Projekte")
          .font(.title2)
          .fontWeight(.semibold)
        Text("Beschreibe deine Kunden kurz — das macht die Erkennung deiner Arbeitszeit einfacher.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        showAddClient = true
      } label: {
        Label("Neuer Kunde", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
    }
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
      LazyVStack(spacing: 10) {
        ForEach(clients) { client in
          ClientRow(
            client: client,
            projects: projects.filter { $0.clientId == client.id },
            isSelected: selectedClientId == client.id
          ) {
            selectedClientId = client.id
            showAddProject = true
          } onDelete: {
            if let id = client.id {
              StorageManager.shared.deleteClient(id: id)
              if selectedClientId == id { selectedClientId = nil }
              reload()
            }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Summary & export (TAKT)

  private var summarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Zeitübersicht (diese Woche)")
            .font(.headline)
          if !summaryRows.isEmpty {
            let total = summaryRows.reduce(0) { $0 + $1.totalHours }
            let billable = summaryRows.reduce(0) { $0 + $1.billableHours }
            Text(String(format: "Total %.2f h · davon abrechenbar %.2f h", total, billable))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if let taggingStatus {
          Text(taggingStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          runAITagging()
        } label: {
          if isTagging {
            ProgressView()
              .controlSize(.small)
              .frame(width: 16)
          } else {
            Label("KI-Erkennung", systemImage: "sparkles")
          }
        }
        .buttonStyle(.bordered)
        .disabled(isTagging || clients.isEmpty)
        .help(
          "Erkennt automatisch Kunde und Projekt für alle ungetaggten Karten dieser Woche "
            + "anhand deiner Kundenbeschreibungen.")
        if let exportStatus {
          Text(exportStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          exportCSV()
        } label: {
          Label("CSV", systemImage: "doc.text")
        }
        .buttonStyle(.bordered)
        .disabled(summaryRows.isEmpty)
        Button {
          exportMarkdown()
        } label: {
          Label("Markdown", systemImage: "doc.richtext")
        }
        .buttonStyle(.bordered)
        .disabled(summaryRows.isEmpty)
      }

      if summaryRows.isEmpty {
        Text("Noch keine getaggten Aktivitäten diese Woche. Ordne Karten auf der Timeline einem Kunden zu, dann erscheinen sie hier.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.vertical, 6)
      } else {
        VStack(spacing: 0) {
          HStack {
            Text("Kunde").frame(maxWidth: .infinity, alignment: .leading)
            Text("Projekt").frame(maxWidth: .infinity, alignment: .leading)
            Text("Stunden").frame(width: 70, alignment: .trailing)
            Text("Abrechenbar").frame(width: 90, alignment: .trailing)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)

          Divider()

          ForEach(summaryRows) { row in
            HStack {
              Text(row.clientName).frame(maxWidth: .infinity, alignment: .leading)
              Text(row.projectName ?? "—").frame(maxWidth: .infinity, alignment: .leading)
              Text(String(format: "%.2f", row.totalHours)).frame(width: 70, alignment: .trailing)
              Text(String(format: "%.2f", row.billableHours))
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(row.billableHours > 0 ? Color.orange : Color.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
      }
    }
    .padding(.top, 6)
  }

  private func runAITagging() {
    guard !isTagging else { return }
    isTagging = true
    taggingStatus = nil
    taggingError = nil

    let range = currentWeekRange()
    let cards = StorageManager.shared.fetchTimelineCardsByTimeRange(
      from: range.start, to: range.end)
    let untagged = cards.filter { $0.clientId == nil }

    guard !untagged.isEmpty else {
      isTagging = false
      taggingStatus = "Keine ungetaggten Karten"
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
    let content = StorageManager.shared.clientSummaryCSV(summaryRows)
    saveFile(content: content, defaultName: "takt-kunden-uebersicht.csv", fileType: "csv")
  }

  private func exportMarkdown() {
    let content = StorageManager.shared.clientSummaryMarkdown(summaryRows)
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
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Circle()
          .fill(color(from: client.color))
          .frame(width: 10, height: 10)
        Text(client.name)
          .font(.headline)
        if client.defaultBillable {
          Text("abrechenbar")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(4)
        }
        Spacer()
        Button("+ Projekt", action: onAddProject)
          .buttonStyle(.borderless)
        Button(role: .destructive) {
          onDelete()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
      }
      if let detail = client.detail, !detail.isEmpty {
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if !projects.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(projects) { project in
            Text(project.name)
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.secondary.opacity(0.12))
              .cornerRadius(6)
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.white)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    )
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

private struct AddClientSheet: View {
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var detail = ""
  @State private var color = ClientsView.palette[0].1
  @State private var defaultBillable = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Neuer Kunde")
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
          StorageManager.shared.saveClient(
            Client(name: trimmed, detail: detail, color: color, defaultBillable: defaultBillable))
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
