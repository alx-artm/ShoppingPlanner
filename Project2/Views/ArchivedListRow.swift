//
//  ArchivedListRow.swift
//  Project2
//
//  A row of an archived list (spec 10, AR-15, AR-18): the same `ListRowView`
//  as on Home, with the Archive's own actions. Used on the Archive screen and
//  in the "In Archive" section of Home's search results (AR-20).
//
//  The row opens its list with `AppNavigation.select`, like a Home tile, not with
//  a `NavigationLink` in a `List(selection:)`: the Archive is pushed in the same
//  column as Home, and two lists bound to the split view's selection in one
//  column made SwiftUI update forever (the app never idled).
//
//  Swipe leading: Restore. Swipe trailing: Delete (the host asks first, HM-10).
//  Context menu: Restore, Duplicate, Share as Text, Delete. No Pin and no
//  List Info here. VoiceOver gets the swipes as actions by itself; Duplicate,
//  which is only in the context menu, is added as a custom action (AR-23).
//

import SwiftUI

struct ArchivedListRow: View {
    let list: ListModel
    /// Asks for the deletion; the host shows the confirmation (HM-10).
    let onDelete: () -> Void

    @Environment(PlannerStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            navigation.select(list)
        } label: {
            HStack(spacing: 8) {
                ListRowView(list: list)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        // The open list stays highlighted next to the sidebar (iPad), like Home's rows.
        .listRowBackground(navigation.isSelected(list) ? Color(.systemFill) : nil)
        .accessibilityAddTraits(navigation.isSelected(list) ? .isSelected : [])
        .accessibilityLabel(Text(verbatim: ListStatusText(list.summary, currencyCode: list.currencyCode,
                                                          locale: locale).accessibilityLabel(name: list.name)))
        .accessibilityIdentifier("archive.row.\(list.uuid.uuidString)")
        .swipeActions(edge: .leading) {
            Button(action: restore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.indigo)
            .accessibilityIdentifier("archive.swipe.restore")
        }
        .swipeActions(edge: .trailing) {
            // No destructive role: the row must stay until the deletion is confirmed (HM-10).
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("archive.swipe.delete")
        }
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                .accessibilityIdentifier("archive.menu.restore")
            Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                .accessibilityIdentifier("archive.menu.duplicate")
            ShareLink(item: ListShareText.make(for: list)) {
                Label("Share as Text", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("archive.menu.share")
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .accessibilityIdentifier("archive.menu.delete")
        }
        .accessibilityAction(named: Text("Duplicate"), duplicate)
    }

    /// Back to Home, first in All Lists (AR-17).
    private func restore() {
        let name = list.name
        withAnimation(reduceMotion ? nil : .default) { store.restoreList(list) }
        ArchiveAnnouncement.restored(name)
    }

    /// An active copy, first in All Lists; this list stays in the Archive (AR-04).
    private func duplicate() {
        withAnimation(reduceMotion ? nil : .default) { _ = store.duplicateList(list) }
    }
}

/// The action "Archive" has its own key: in Russian the verb ("В архив") differs from
/// the name of the screen and of Home's row ("Архив"), which use the key "Archive".
enum ArchiveText {
    static var archiveAction: String {
        String(localized: "action.archive", defaultValue: "Archive",
               comment: "Action that moves a list to the Archive (menu, swipe, VoiceOver).")
    }
}

/// VoiceOver announcements after Archive / Restore (AR-11, AR-17): the row leaves the
/// screen, so without them a VoiceOver user doesn't hear that anything happened.
enum ArchiveAnnouncement {
    @MainActor
    static func archived(_ name: String) {
        AccessibilityNotification.Announcement(String(localized: "“\(name)” archived")).post()
    }

    @MainActor
    static func restored(_ name: String) {
        AccessibilityNotification.Announcement(String(localized: "“\(name)” restored")).post()
    }
}

extension View {
    /// "Delete “Name”?" with Delete List / Cancel (HM-10), shown while `list` is set.
    /// `identifierPrefix` names the buttons: "<prefix>.deleteAlert.confirmButton" / ".cancelButton".
    func deleteListConfirmation(
        _ list: Binding<ListModel?>,
        identifierPrefix: String,
        onConfirm: @escaping (ListModel) -> Void
    ) -> some View {
        confirmationDialog(
            Text("Delete “\(list.wrappedValue?.name ?? "")”?"),
            isPresented: Binding(
                get: { list.wrappedValue != nil },
                set: { if !$0 { list.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: list.wrappedValue
        ) { list in
            Button("Delete List", role: .destructive) { onConfirm(list) }
                .accessibilityIdentifier("\(identifierPrefix).deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("\(identifierPrefix).deleteAlert.cancelButton")
        } message: { _ in
            Text("All groups and items will be deleted.")
        }
    }
}
