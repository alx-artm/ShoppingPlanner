//
//  AppNavigation.swift
//  Project2
//
//  Navigation state of one window (spec 08): which list is selected in the
//  split view, and deleting or archiving a list that is on screen safely
//  (DM-18, AD-05, spec 10 AR-12).
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

    /// Screens pushed in Home's column (the sidebar): only the Archive today (spec 10, AR-14).
    var sidebarPath: [SidebarRoute] = []

    /// What happens to a list once its detail screen has closed.
    enum PendingAction: Equatable {
        case delete
        case archive
    }

    /// A list waiting for its detail screen to close before it is deleted or archived.
    @ObservationIgnored private var pending: (list: ListModel, action: PendingAction)?

    /// The action waiting for the detail to close, if any (for tests).
    var pendingAction: PendingAction? { pending?.action }

    init(selectedListID: UUID? = nil) {
        self.selectedListID = selectedListID
    }

    /// Opens the Archive in Home's column (AR-14).
    func showArchive() {
        sidebarPath = [.archive]
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
        request(.delete, of: list, using: store)
    }

    /// Archives `list` (AR-12). If it is open, its screen closes first (pop on iPhone,
    /// "Select a List" on iPad) and the list is archived once it is gone: the user asked
    /// to put it away, so it doesn't stay open with the Archived banner.
    func requestArchive(of list: ListModel, using store: any PlannerStoring) {
        request(.archive, of: list, using: store)
    }

    /// Called by the detail column when the list screen disappeared.
    func detailDidClose(using store: any PlannerStoring) {
        guard let (list, action) = pending else { return }
        pending = nil
        perform(action, on: list, using: store)
    }

    private func request(_ action: PendingAction, of list: ListModel, using store: any PlannerStoring) {
        if isSelected(list) {
            pending = (list, action)
            selectedListID = nil
        } else {
            perform(action, on: list, using: store)
        }
    }

    private func perform(_ action: PendingAction, on list: ListModel, using store: any PlannerStoring) {
        switch action {
        case .delete: store.deleteList(list)
        case .archive: store.archiveList(list)
        }
    }

    /// Drops a selection that points to a list that no longer exists: restored
    /// from a previous launch, or deleted (later: on another device).
    func dropSelectionIfMissing(existing ids: Set<UUID>) {
        if let id = selectedListID, !ids.contains(id) {
            selectedListID = nil
        }
    }
}

/// A screen pushed in Home's column of the split view.
enum SidebarRoute: Hashable {
    case archive
}
