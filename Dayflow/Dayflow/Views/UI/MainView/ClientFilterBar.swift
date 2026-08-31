//
//  ClientFilterBar.swift
//  Dayflow
//
//  TAKT: Filter the timeline by client. Colored chips; empty selection = all.
//

import SwiftUI

struct ClientFilterBar: View {
  @Binding var selectedClientIds: Set<Int64>

  @State private var clients: [Client] = []

  var body: some View {
    Group {
      if !clients.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            TaktChip(
              title: "All clients",
              isSelected: selectedClientIds.isEmpty,
              action: { selectedClientIds = [] }
            )
            ForEach(clients) { client in
              TaktChip(
                title: client.name,
                isSelected: client.id.map { selectedClientIds.contains($0) } ?? false,
                color: color(from: client.color)
              ) {
                toggle(client)
              }
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .onAppear(perform: reload)
    .onReceive(NotificationCenter.default.publisher(for: .timelineDataUpdated)) { _ in
      reload()
    }
  }

  private func toggle(_ client: Client) {
    guard let id = client.id else { return }
    if selectedClientIds.contains(id) {
      selectedClientIds.remove(id)
    } else {
      selectedClientIds.insert(id)
    }
  }

  private func color(from hex: String?) -> Color {
    guard let hex, hex.count == 7 else { return .secondary }
    return Color(hex: hex)
  }

  private func reload() {
    clients = StorageManager.shared.fetchClients()
  }
}
