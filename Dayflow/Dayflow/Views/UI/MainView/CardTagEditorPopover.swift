//
//  CardTagEditorPopover.swift
//  Dayflow
//
//  TAKT: Editor to assign client/project/task/billable to a timeline card.
//

import SwiftUI

struct CardTagEditorPopover: View {
  let activity: TimelineActivity
  let onSave: (CardTagSelection) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var clients: [Client] = []
  @State private var projects: [Project] = []
  @State private var selectedClientId: Int64?
  @State private var selectedProjectId: Int64?
  @State private var task: String
  @State private var billable: Bool

  init(activity: TimelineActivity, onSave: @escaping (CardTagSelection) -> Void) {
    self.activity = activity
    self.onSave = onSave
    _selectedClientId = State(initialValue: activity.clientId)
    _selectedProjectId = State(initialValue: activity.projectId)
    _task = State(initialValue: activity.task ?? "")
    _billable = State(initialValue: activity.billable ?? false)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Kunde & Projekt zuordnen")
        .font(.headline)

      Picker("Kunde", selection: $selectedClientId) {
        Text("—").tag(Int64?.none)
        ForEach(clients) { client in
          Text(client.name).tag(client.id)
        }
      }
      .onChange(of: selectedClientId) { _, newClientId in
        // Reset project when the client changes
        if let newClientId, !projects.contains(where: { $0.id == selectedProjectId && $0.clientId == newClientId }) {
          selectedProjectId = nil
        }
        if newClientId == nil {
          selectedProjectId = nil
        }
      }

      Picker("Projekt", selection: $selectedProjectId) {
        Text("—").tag(Int64?.none)
        ForEach(projects.filter { $0.clientId == selectedClientId }) { project in
          Text(project.name).tag(project.id)
        }
      }
      .disabled(selectedClientId == nil || projects.filter { $0.clientId == selectedClientId }.isEmpty)

      TextField("Aufgabe (optional)", text: $task)
        .textFieldStyle(.roundedBorder)

      Toggle("Abrechenbar", isOn: $billable)

      HStack {
        Spacer()
        Button("Abbrechen") {
          dismiss()
        }
        Button("Speichern") {
          onSave(
            CardTagSelection(
              clientId: selectedClientId,
              projectId: selectedProjectId,
              task: task,
              billable: billable
            )
          )
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(14)
    .frame(width: 300)
    .onAppear {
      clients = StorageManager.shared.fetchClients()
      projects = StorageManager.shared.fetchProjects()
    }
  }
}
