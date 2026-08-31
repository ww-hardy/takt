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
          HStack(spacing: 6) {
            chip(
              label: "Alle",
              color: nil,
              isSelected: selectedClientIds.isEmpty
            ) {
              selectedClientIds = []
            }
            ForEach(clients) { client in
              chip(
                label: client.name,
                color: color(from: client.color),
                isSelected: client.id.map { selectedClientIds.contains($0) } ?? false
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

  private func chip(
    label: String,
    color: Color?,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        if let color {
          Circle()
            .fill(color)
            .frame(width: 8, height: 8)
        }
        Text(label)
          .font(Font.custom("Figtree", size: 12))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
      )
      .cornerRadius(6)
    }
    .buttonStyle(PlainButtonStyle())
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
