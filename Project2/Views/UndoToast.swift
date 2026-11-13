//
//  UndoToast.swift
//  Project2
//
//  "Deleted · Undo" after a swipe-delete (spec 04 LD-09, owner decision
//  2026-11-13): no confirmation per item, but a 4-second way back.
//

import SwiftUI

/// The last deleted item, kept for its toast. A new deletion replaces it.
struct DeletedItem: Identifiable, Equatable {
    let id = UUID()
    let snapshot: ItemSnapshot

    /// How long the toast stays.
    static let duration: Duration = .seconds(4)
}

struct UndoToast: View {
    let deleted: DeletedItem
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Deleted “\(deleted.snapshot.name)”")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: onUndo)
                .bold()
                .accessibilityIdentifier("undoToast.undoButton")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 600)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoToast")
    }
}
