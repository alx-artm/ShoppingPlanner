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
    ///
    /// Every change goes through here (Home's selection binding, `select`, back, Undo,
    /// delete / archive, a list that went missing), so this is where the Duplicate toast
    /// ends when the user leaves the copy (HM-41). State, not the copy screen's
    /// `onDisappear`: on a slow device the pushed screen can be torn down and rebuilt
    /// while it is still the selection, and that killed the toast before it was shown.
    var selectedListID: UUID? {
        didSet {
            if let recent = recentDuplicate, selectedListID != recent.copyID {
                recentDuplicate = nil
            }
        }
    }

    /// Screens pushed in Home's column (the sidebar): only the Archive today (spec 10, AR-14).
    var sidebarPath: [SidebarRoute] = []

    /// What happens to a list once its detail screen has closed.
    enum PendingAction: Equatable {
        case delete
        case archive
    }

    /// The copy just made by Duplicate, while its "Copy created · Undo" toast is up (HM-41).
    /// A new Duplicate replaces it (HM-43).
    private(set) var recentDuplicate: RecentDuplicate?

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

    /// Duplicates `list` and opens the copy (spec 02 HM-39, spec 10 AR-04): iPhone pushes it,
    /// iPad shows it in the detail column. The same from every place: Home's tiles, rows and
    /// search, the Archive and the open list's ⋯. A copy is made to be changed, so it opens
    /// for editing at once; the toast's Undo takes it back (HM-41, HM-42).
    @discardableResult
    func openDuplicate(of list: ListModel, using store: any PlannerStoring) -> ListModel {
        let previous = selectedListID
        let copy = store.duplicateList(list)
        recentDuplicate = RecentDuplicate(copyID: copy.uuid, originalName: list.name,
                                          previousSelection: previous)
        select(copy)
        return copy
    }

    /// Undo in the toast (HM-42): deletes the copy and goes back to where the user was, the
    /// list open before (iPad detail, or the original after ⋯ → Duplicate) or nothing (iPhone:
    /// Home or the Archive; iPad: "Select a List"). The copy is on screen, so it is deleted
    /// once its screen has closed (DM-18).
    func undoDuplicate(_ copy: ListModel, using store: any PlannerStoring) {
        guard let recent = recentDuplicate, recent.copyID == copy.uuid else { return }
        recentDuplicate = nil
        if isSelected(copy) {
            pending = (copy, .delete)
            selectedListID = recent.previousSelection
        } else {
            store.deleteList(copy)
        }
    }

    /// The toast's time is up: the copy stays (HM-43). Leaving the copy ends the toast in
    /// `selectedListID`'s `didSet`.
    func dismissDuplicateToast(_ id: RecentDuplicate.ID) {
        if recentDuplicate?.id == id { recentDuplicate = nil }
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

/// A copy made by Duplicate, remembered for its toast's Undo (HM-41, HM-42).
struct RecentDuplicate: Identifiable, Equatable {
    let id = UUID()
    let copyID: UUID
    /// The toast names the original: "Copy of “Eva” created".
    let originalName: String
    /// The list open before Duplicate, shown again after Undo; `nil` = none.
    let previousSelection: UUID?
}

/// A screen pushed in Home's column of the split view.
enum SidebarRoute: Hashable {
    case archive
}
