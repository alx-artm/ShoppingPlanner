//
//  AppNavigation.swift
//  Project2
//
//  Navigation state of one window (spec 08): which list is selected in the
//  split view, and deleting a list that is on screen safely (DM-18, AD-05).
//
//  It lives at the root of the scene, not inside a pushed view, so the
//  selection survives a size-class change (fold/unfold of iPhone Duo, iPad
//  rotation, Stage Manager resize; AD-04). `ContentView` mirrors it into
//  `@SceneStorage` so it is also restored after the system relaunches the app.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    /// The list shown in the detail column. On a compact iPhone a non-`nil`
    /// value means the list is pushed; going back sets it to `nil`.
    var selectedListID: UUID?

    /// A list waiting for its detail screen to close before it is deleted.
    @ObservationIgnored private var pendingDeletion: ListModel?

    init(selectedListID: UUID? = nil) {
        self.selectedListID = selectedListID
    }

    func select(_ list: ListModel) {
        selectedListID = list.uuid
    }

    func isSelected(_ list: ListModel) -> Bool {
        selectedListID == list.uuid
    }

    /// Deletes `list`. If it is shown in the detail column, the detail is
    /// closed first and the list is deleted once it is gone (DM-18): a view
    /// must never read a deleted model.
    func requestDeletion(of list: ListModel, using store: any PlannerStoring) {
        if isSelected(list) {
            pendingDeletion = list
            selectedListID = nil
        } else {
            store.deleteList(list)
        }
    }

    /// Called by the detail column when the list screen disappeared.
    func detailDidClose(using store: any PlannerStoring) {
        guard let list = pendingDeletion else { return }
        pendingDeletion = nil
        store.deleteList(list)
    }

    /// Drops a selection that points to a list that no longer exists: restored
    /// from a previous launch, or deleted (later: on another device).
    func dropSelectionIfMissing(existing ids: Set<UUID>) {
        if let id = selectedListID, !ids.contains(id) {
            selectedListID = nil
        }
    }
}
