//
//  StorageManager+ClientProjects.swift
//  TAKT
//
//  TAKT: Multi-client recognition — CRUD for clients/projects and
//  tagging of timeline cards (client, project, task, billable).
//

import Foundation
import GRDB

extension StorageManager {

  // MARK: - Clients

  /// All clients, ordered by name.
  func fetchClients() -> [Client] {
    (try? timedRead("fetchClients") { db in
      try Row.fetchAll(db, sql: "SELECT * FROM clients ORDER BY name COLLATE NOCASE")
        .map { row in
          Client(
            id: row["id"],
            name: row["name"],
            detail: row["detail"] ?? "",
            color: row["color"] ?? "",
            defaultBillable: (row["default_billable"] as? Int ?? 0) != 0
          )
        }
    }) ?? []
  }

  /// Client by id, or nil.
  func fetchClient(id: Int64) -> Client? {
    (try? timedRead("fetchClient") { db in
      try Row.fetchOne(db, sql: "SELECT * FROM clients WHERE id = ?", arguments: [id])
        .map { row in
          Client(
            id: row["id"],
            name: row["name"],
            detail: row["detail"] ?? "",
            color: row["color"] ?? "",
            defaultBillable: (row["default_billable"] as? Int ?? 0) != 0
          )
        }
    }) ?? nil
  }

  /// Insert a new client. Returns the new id.
  @discardableResult
  func saveClient(_ client: Client) -> Int64? {
    var newId: Int64?
    try? timedWrite("saveClient") { db in
      try db.execute(
        sql: """
              INSERT INTO clients (name, detail, color, default_billable)
              VALUES (?, ?, ?, ?)
          """,
        arguments: [client.name, client.detail ?? "", client.color ?? "", client.defaultBillable ? 1 : 0])
      newId = db.lastInsertedRowID
    }
    return newId
  }

  func updateClient(_ client: Client) {
    guard let id = client.id else { return }
    try? timedWrite("updateClient") { db in
      try db.execute(
        sql: """
              UPDATE clients
              SET name = ?, detail = ?, color = ?, default_billable = ?
              WHERE id = ?
          """,
        arguments: [client.name, client.detail ?? "", client.color ?? "", client.defaultBillable ? 1 : 0, id])
    }
  }

  /// Delete a client and its projects (cascade).
  func deleteClient(id: Int64) {
    try? timedWrite("deleteClient") { db in
      // Untag cards pointing at this client
      try db.execute(sql: "UPDATE timeline_cards SET client_id = NULL, project_id = NULL WHERE client_id = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM clients WHERE id = ?", arguments: [id])
    }
  }

  // MARK: - Projects

  /// All projects, ordered by name.
  func fetchProjects() -> [Project] {
    (try? timedRead("fetchProjects") { db in
      try Row.fetchAll(db, sql: "SELECT * FROM projects ORDER BY name COLLATE NOCASE")
        .map { row in
          Project(
            id: row["id"],
            clientId: row["client_id"],
            name: row["name"],
            detail: row["detail"] ?? ""
          )
        }
    }) ?? []
  }

  /// Projects belonging to a client.
  func fetchProjects(forClient clientId: Int64) -> [Project] {
    (try? timedRead("fetchProjects(forClient:)") { db in
      try Row.fetchAll(db, sql: "SELECT * FROM projects WHERE client_id = ? ORDER BY name COLLATE NOCASE", arguments: [clientId])
        .map { row in
          Project(
            id: row["id"],
            clientId: row["client_id"],
            name: row["name"],
            detail: row["detail"] ?? ""
          )
        }
    }) ?? []
  }

  @discardableResult
  func saveProject(_ project: Project) -> Int64? {
    var newId: Int64?
    try? timedWrite("saveProject") { db in
      try db.execute(
        sql: "INSERT INTO projects (client_id, name, detail) VALUES (?, ?, ?)",
        arguments: [project.clientId ?? nil, project.name, project.detail ?? ""])
      newId = db.lastInsertedRowID
    }
    return newId
  }

  func updateProject(_ project: Project) {
    guard let id = project.id else { return }
    try? timedWrite("updateProject") { db in
      try db.execute(
        sql: "UPDATE projects SET name = ?, detail = ? WHERE id = ?",
        arguments: [project.name, project.detail ?? "", id])
    }
  }

  func deleteProject(id: Int64) {
    try? timedWrite("deleteProject") { db in
      try db.execute(sql: "UPDATE timeline_cards SET project_id = NULL WHERE project_id = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [id])
    }
  }

  // MARK: - Card tagging

  /// A light card snapshot used as a few-shot example for AI tagging.
  struct TaggedExample {
    let title: String
    let clientId: Int64?
    let projectId: Int64?
    let task: String?
  }

  /// Returns up to `limit` cards that carry a manual/corrected client tag,
  /// most recent first — used as few-shot examples in the AI tagging prompt.
  func fetchTaggedExamples(limit: Int) -> [TaggedExample] {
    (try? timedRead("fetchTaggedExamples") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT title, client_id, project_id, task
              FROM timeline_cards
              WHERE is_deleted = 0
                AND client_id IS NOT NULL
                AND tag_source IN ('manual', 'corrected')
              ORDER BY start_ts DESC
              LIMIT ?
          """,
        arguments: [limit]
      )
      .map { row in
        TaggedExample(
          title: row["title"],
          clientId: row["client_id"],
          projectId: row["project_id"],
          task: row["task"]
        )
      }
    }) ?? []
  }

  /// Set client/project/task/billable on a timeline card.
  /// tagSource: 'manual' when the user edits directly, 'corrected' when an AI
  /// suggestion is overridden, 'ai'/'pending' for future automatic passes.
  func updateTimelineCardTagging(
    cardId: Int64,
    clientId: Int64?,
    projectId: Int64?,
    task: String?,
    billable: Bool?,
    tagSource: String? = "manual",
    tagConfidence: Double? = nil
  ) {
    try? timedWrite("updateTimelineCardTagging") { db in
      try db.execute(
        sql: """
              UPDATE timeline_cards
              SET client_id = ?, project_id = ?, task = ?, billable = ?, tag_source = ?,
                  tag_confidence = ?
              WHERE id = ?
          """,
        arguments: [
          clientId ?? nil, projectId ?? nil, task ?? nil,
          billable.map { $0 ? 1 : 0 } ?? nil, tagSource ?? nil, tagConfidence ?? nil, cardId,
        ])
    }
    NotificationCenter.default.post(name: .timelineDataUpdated, object: nil)
  }

  // MARK: - Client summary (TAKT)

  /// Aggregated duration per client/project in [from, to).
  struct ClientSummaryRow: Identifiable, Sendable {
    let id: String  // "clientId-projectId"
    let clientId: Int64
    let clientName: String
    let projectId: Int64?
    let projectName: String?
    let totalSeconds: Int
    let billableSeconds: Int

    var totalHours: Double { Double(totalSeconds) / 3600.0 }
    var billableHours: Double { Double(billableSeconds) / 3600.0 }
  }

  func clientSummary(from: Date, to: Date) -> [ClientSummaryRow] {
    let startTs = Int(from.timeIntervalSince1970)
    let endTs = Int(to.timeIntervalSince1970)
    let rows = (try? timedRead("clientSummary") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT tc.client_id,
                     c.name AS client_name,
                     tc.project_id,
                     p.name AS project_name,
                     SUM(tc.end_ts - tc.start_ts) AS total_s,
                     SUM(CASE WHEN tc.billable = 1 THEN tc.end_ts - tc.start_ts ELSE 0 END) AS billable_s
              FROM timeline_cards tc
              LEFT JOIN clients c ON c.id = tc.client_id
              LEFT JOIN projects p ON p.id = tc.project_id
              WHERE tc.start_ts >= ? AND tc.start_ts < ?
                AND tc.is_deleted = 0
                AND tc.client_id IS NOT NULL
              GROUP BY tc.client_id, tc.project_id
              ORDER BY client_name COLLATE NOCASE, project_name COLLATE NOCASE
          """,
        arguments: [startTs, endTs]
      ).map { row in
        ClientSummaryRow(
          id: "\(row["client_id"] ?? 0)-\(row["project_id"] ?? 0)",
          clientId: row["client_id"],
          clientName: row["client_name"] ?? "?",
          projectId: row["project_id"],
          projectName: row["project_name"],
          totalSeconds: row["total_s"] ?? 0,
          billableSeconds: row["billable_s"] ?? 0
        )
      }
    }) ?? []
    return rows
  }

  /// CSV export of the client summary, including the selected period.
  func clientSummaryCSV(_ rows: [ClientSummaryRow], from: Date, to: Date) -> String {
    let fromText = clientSummaryDateFormatter.string(from: from)
    let toText = clientSummaryDateFormatter.string(from: to)
    var csv = "Kunde;Projekt;Zeitraum von;Zeitraum bis;Stunden;Abrechenbar;Nicht abrechenbar\n"
    for row in rows {
      let total = roundedClientSummaryHours(row.totalHours)
      let billable = roundedClientSummaryHours(row.billableHours)
      let nonBillable = roundedClientSummaryHours(max(0, row.totalHours - row.billableHours))
      let values = [row.clientName, row.projectName ?? "", fromText, toText,
                    clientSummaryNumber(total), clientSummaryNumber(billable), clientSummaryNumber(nonBillable)]
      csv += values.map(clientSummaryCSVField).joined(separator: ";") + "\n"
    }
    return csv
  }

  /// Markdown export of the client summary, including period and totals.
  func clientSummaryMarkdown(_ rows: [ClientSummaryRow], from: Date, to: Date) -> String {
    let fromText = clientSummaryDateFormatter.string(from: from)
    let toText = clientSummaryDateFormatter.string(from: to)
    var md = "# Kunden-Zeitübersicht\n\nZeitraum: **\(fromText) bis \(toText)**\n\n"
    md += "| Kunde | Projekt | Stunden | Abrechenbar | Nicht abrechenbar |\n|---|---|---:|---:|---:|\n"
    for row in rows {
      let total = roundedClientSummaryHours(row.totalHours)
      let billable = roundedClientSummaryHours(row.billableHours)
      let nonBillable = roundedClientSummaryHours(max(0, row.totalHours - row.billableHours))
      md += "| \(clientSummaryMarkdownField(row.clientName)) | \(clientSummaryMarkdownField(row.projectName ?? "—")) | \(clientSummaryNumber(total)) | \(clientSummaryNumber(billable)) | \(clientSummaryNumber(nonBillable)) |\n"
    }
    let total = rows.reduce(0) { $0 + $1.totalHours }
    let billable = rows.reduce(0) { $0 + $1.billableHours }
    md += "\n**Gesamt:** \(clientSummaryNumber(roundedClientSummaryHours(total))) h, **abrechenbar:** \(clientSummaryNumber(roundedClientSummaryHours(billable))) h\n"
    md += "\n*Exportiert von TAKT*\n"
    return md
  }

  private static let clientSummaryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private var clientSummaryDateFormatter: DateFormatter { Self.clientSummaryDateFormatter }

  private func roundedClientSummaryHours(_ value: Double) -> Double {
    (value * 100).rounded() / 100
  }

  private func clientSummaryNumber(_ value: Double) -> String {
    String(format: "%.2f", locale: Locale(identifier: "de_CH"), value)
      .replacingOccurrences(of: ".", with: ",")
  }

  private func clientSummaryCSVField(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return (escaped.contains(";") || escaped.contains("\"") || escaped.contains("\n")) ? "\"\(escaped)\"" : escaped
  }

  private func clientSummaryMarkdownField(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
  }
}
