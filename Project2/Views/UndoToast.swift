//
//  UndoToast.swift
//  Project2
//
//  "Deleted · Undo" after a swipe-delete (spec 04 LD-09, owner decision
//  2026-11-13): no confirmation per item, but a 4-second way back.
//  The same capsule says "Copy of “Eva” created · Undo" after a list's
//  Duplicate (spec 02 HM-41).
//

import SwiftUI

/// The last deleted item, kept for its toast. A new deletion replaces it.
struct DeletedItem: Identifiable, Equatable {
    let id = UUID()
    let snapshot: ItemSnapshot

    /// How long the toast stays (a UI test can make it longer, see `LaunchConfiguration`).
    static var duration: Duration { UndoToast.duration }
}

struct UndoToast: View {
    let message: Text
    /// "undoToast" (deleted item) or "duplicateToast"; the button is "<identifier>.undoButton".
    var identifier = "undoToast"
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How long a toast stays: 4 s (a UI test can make it longer, see `LaunchConfiguration`).
    /// `nonisolated`: it reads only launch arguments, and `DeletedItem` (not on the main actor) uses it.
    nonisolated static var duration: Duration {
        LaunchConfiguration.undoToastDurationOverride ?? .seconds(4)
    }

    /// "Deleted “Sofa”" (LD-09).
    init(deleted: DeletedItem, onUndo: @escaping () -> Void) {
        self.message = Text("Deleted “\(deleted.snapshot.name)”")
        self.onUndo = onUndo
    }

    /// "Copy of “Eva” created", the original's name (HM-41).
    init(duplicate: RecentDuplicate, onUndo: @escaping () -> Void) {
        self.message = Text(DuplicateText.created(originalName: duplicate.originalName))
        self.identifier = "duplicateToast"
        self.onUndo = onUndo
    }

    var body: some View {
        HStack(spacing: 12) {
            message
                // HM-45: two lines at accessibility sizes, so a name isn't cut beyond recognition.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: onUndo)
                .bold()
                .accessibilityIdentifier("\(identifier).undoButton")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 600)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
