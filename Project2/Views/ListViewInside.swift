//
//  ListViewInside.swift
//  Project2
//
//  The list screen (spec 04, UX_REVIEW §5): groups as collapsible sections,
//  item rows with swipes and a context menu, "＋ Add Group" at the end, and
//  the summary bar pinned above the bottom edge. Everything that changes data
//  goes through `PlannerStore`.
//

import SwiftUI

struct ListViewInside: View {
    @Environment(PlannerStore.self) private var store
    @Environment(LocalUIState.self) private var uiState
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let list: ListModel

    @State private var sheet: ListSheet?
    @State private var showsDeleteListConfirmation = false
    /// The New Group / Rename alert (owner decision: an alert with a text field).
    @State private var nameAlert: GroupNameAlert?
    @State private var groupName = ""
    @State private var groupToDelete: GroupModel?
    /// "Reorder Items": the list shows drag handles for the not-bought items.
    @State private var editMode: EditMode = .inactive
    private var isReorderingItems: Bool { editMode.isEditing }

    /// The last swipe-deleted item, while its "Undo" toast is on screen (LD-09).
    @State private var deletedItem: DeletedItem?

    private var showsCompleted: Bool {
        uiState.showsCompleted(list.uuid)
    }

    var body: some View {
        let groups = list.sortedGroups

        List {
            ForEach(groups) { group in
                section(for: group)
            }
            if !groups.isEmpty {
                Button {
                    startNewGroup()
                } label: {
                    Label("Add Group", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("listDetail.addGroupRow")
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .overlay {
            if groups.isEmpty { emptyState }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let deletedItem {
                    UndoToast(deleted: deletedItem) { undoDelete(deletedItem) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Always visible, never scrolls away (LD-10).
                ListSummaryBar(list: list)
            }
            .animation(reduceMotion ? nil : .snappy, value: deletedItem)
        }
        .task(id: deletedItem?.id) {
            guard deletedItem != nil else { return }
            try? await Task.sleep(for: DeletedItem.duration)
            if !Task.isCancelled { deletedItem = nil }
        }
        .toolbar {
            if isReorderingItems {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        withAnimation { editMode = .inactive }
                    }
                    .accessibilityIdentifier("listDetail.reorderDoneButton")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) { listMenu }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)

        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newItem(let group): ItemView(mode: .create(group))
            case .editItem(let item): ItemView(mode: .edit(item))
            case .listInfo: ListInfoView(mode: .edit(list))
            case .reorderGroups: ReorderGroupsView(list: list)
            }
        }

        .alert(nameAlert?.title ?? Text(verbatim: ""), isPresented: Binding(
            get: { nameAlert != nil },
            set: { if !$0 { nameAlert = nil } }
        ), presenting: nameAlert) { alert in
            TextField("Group name", text: $groupName)
                .accessibilityIdentifier("groupName.field")
            Button("Cancel", role: .cancel) {}
            Button(alert.isNew ? "Add" : "Save") { commitGroupName(alert) }
                .disabled(PlannerStore.normalizedName(groupName) == nil)
                .accessibilityIdentifier("groupName.saveButton")
        }

        .confirmationDialog(
            Text("Delete group and \(groupToDelete?.items?.count ?? 0) items?"),
            isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: groupToDelete
        ) { group in
            Button("Delete Group", role: .destructive) {
                animated { store.deleteGroup(group) }
            }
            .accessibilityIdentifier("groupDelete.confirmButton")
            Button("Cancel", role: .cancel) {}
        }

        .confirmationDialog(
            Text("Delete “\(list.name)”?"),
            isPresented: $showsDeleteListConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                // Closes this screen first (pop / empty detail), deletes when it is gone (LD-19, DM-18).
                navigation.requestDeletion(of: list, using: store)
            }
            .accessibilityIdentifier("listDetail.deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("listDetail.deleteAlert.cancelButton")
        } message: {
            Text("All groups and items will be deleted.")
        }
    }

    // MARK: - Sections

    private func section(for group: GroupModel) -> some View {
        let isExpanded = uiState.isExpanded(group.uuid)
        return Section(isExpanded: Binding(
            get: { isExpanded },
            set: { uiState.setExpanded($0, for: group.uuid) }
        )) {
            let incomplete = group.incompleteItems
            let visibleItems = showsCompleted ? group.sortedItems : incomplete
            ForEach(visibleItems) { item in
                row(item)
                    // Bought items are ordered by when they were bought (DM-15).
                    .moveDisabled(item.isComplete)
                    .deleteDisabled(true)
            }
            // Drag handles only in "Reorder Items" mode: outside it, a long press is the
            // context menu, and a drag lift competing with it leaves the menu stuck.
            .onMove(perform: isReorderingItems ? { source, destination in
                // Offsets of the visible rows; not-completed items come first, so they match
                // `incompleteItems` as long as the drop stays above the bought ones.
                store.moveItems(in: group, fromOffsets: source,
                                toOffset: min(destination, incomplete.count))
            } : nil)

            if !showsCompleted {
                let boughtCount = (group.items?.count ?? 0) - incomplete.count
                if boughtCount > 0 {
                    // LD-07: hidden bought items stay discoverable.
                    Button {
                        animated { uiState.setShowsCompleted(true, for: list.uuid) }
                    } label: {
                        Text("\(boughtCount) bought")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint(Text("Shows bought items"))
                    .accessibilityIdentifier("group.boughtRow.\(group.name)")
                }
            }

            Button {
                sheet = .newItem(group)
            } label: {
                Label("New Item", systemImage: "plus")
                    .foregroundStyle(.tint)
            }
            .accessibilityIdentifier("group.addItemButton.\(group.name)")
        } header: {
            GroupHeaderView(
                group: group,
                onRename: { startRename(group) },
                onAddItem: {
                    uiState.setExpanded(true, for: group.uuid)
                    sheet = .newItem(group)
                },
                onDelete: { requestDelete(group) }
            )
        }
    }

    private func row(_ item: ItemModel) -> some View {
        ItemRowView(item: item) { sheet = .editItem(item) }
            // LD-09: Done / Undo on the leading edge, Delete (with an undo toast) on the trailing one.
            .swipeActions(edge: .leading) {
                Button {
                    animated { store.toggleComplete(item) }
                } label: {
                    item.isComplete
                        ? Label("Not Bought", systemImage: "arrow.uturn.backward")
                        : Label("Bought", systemImage: "checkmark")
                }
                .tint(item.isComplete ? .gray : .green)
                .accessibilityIdentifier("item.swipe.toggle")
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("item.swipe.delete")
            }
            .contextMenu { itemMenu(item) }
    }

    @ViewBuilder
    private func itemMenu(_ item: ItemModel) -> some View {
        Button("Edit", systemImage: "pencil") { sheet = .editItem(item) }
            .accessibilityIdentifier("item.menu.edit")
        Button("Duplicate", systemImage: "plus.square.on.square") {
            animated { store.duplicateItem(item) }
        }
        .accessibilityIdentifier("item.menu.duplicate")
        let otherGroups = list.sortedGroups.filter { $0 !== item.group }
        if !otherGroups.isEmpty {
            Menu {
                ForEach(otherGroups) { group in
                    Button(group.name) {
                        animated { store.moveItem(item, to: group) }
                    }
                    .accessibilityIdentifier("item.menu.moveTo.\(group.name)")
                }
            } label: {
                Label("Move to Group", systemImage: "folder")
            }
            .accessibilityIdentifier("item.menu.move")
        }
        if let url = ItemLink.url(from: item.urlString) {
            Button("Open Link", systemImage: "safari") { openURL(url) }
                .accessibilityIdentifier("item.menu.openLink")
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
            .accessibilityIdentifier("item.menu.delete")
    }

    // MARK: - Toolbar menu

    private var listMenu: some View {
        Menu {
            Button("List Info", systemImage: "info.circle") { sheet = .listInfo }
                .accessibilityIdentifier("listDetail.menu.edit")
            Button("Add Group", systemImage: "folder.badge.plus") { startNewGroup() }
                .accessibilityIdentifier("listDetail.menu.addGroup")

            Divider()
            Button {
                animated { uiState.setShowsCompleted(!showsCompleted, for: list.uuid) }
            } label: {
                showsCompleted
                    ? Label("Hide Completed", systemImage: "eye.slash")
                    : Label("Show Completed", systemImage: "eye")
            }
            .accessibilityIdentifier("listDetail.menu.toggleCompleted")

            let groups = list.sortedGroups
            if !groups.isEmpty {
                let anyExpanded = groups.contains { uiState.isExpanded($0.uuid) }
                Button {
                    animated {
                        for group in groups { uiState.setExpanded(!anyExpanded, for: group.uuid) }
                    }
                } label: {
                    anyExpanded
                        ? Label("Collapse All", systemImage: "rectangle.compress.vertical")
                        : Label("Expand All", systemImage: "rectangle.expand.vertical")
                }
                .accessibilityIdentifier("listDetail.menu.toggleExpanded")
            }
            if groups.contains(where: { $0.incompleteItems.count > 1 }) {
                Button("Reorder Items", systemImage: "line.3.horizontal") {
                    withAnimation { editMode = .active }
                }
                .accessibilityIdentifier("listDetail.menu.reorderItems")
            }
            if groups.count > 1 {
                Button("Reorder Groups", systemImage: "arrow.up.arrow.down") { sheet = .reorderGroups }
                    .accessibilityIdentifier("listDetail.menu.reorderGroups")
            }

            // Dividers, not Sections: items inside a menu Section lose their identifiers.
            Divider()
            ShareLink(item: ListShareText.make(for: list)) {
                Label("Share as Text", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("listDetail.menu.share")
            Button("Duplicate", systemImage: "plus.square.on.square") {
                navigation.select(store.duplicateList(list))
            }
            .accessibilityIdentifier("listDetail.menu.duplicate")

            Divider()

            Button("Delete List", systemImage: "trash", role: .destructive) {
                showsDeleteListConfirmation = true
            }
            .accessibilityIdentifier("listDetail.menu.delete")
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("listDetail.menuButton")
    }

    /// No groups and no items (LD-18). Centered by `ContentUnavailableView` in an overlay.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items Yet", systemImage: "cart")
        } description: {
            Text("Add the things to buy, or start with groups like rooms or shops.")
        } actions: {
            Button("Add Item") { addFirstItem() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("listDetail.emptyState.addItemButton")
            Button("Add Group") { startNewGroup() }
                .accessibilityIdentifier("listDetail.emptyState.addGroupButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listDetail.emptyState")
    }

    // MARK: - Actions

    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .default, change)
    }

    /// No confirmation; a toast offers Undo for a few seconds (LD-09, owner decision).
    private func delete(_ item: ItemModel) {
        let snapshot = ItemSnapshot(item)
        animated { store.deleteItem(item) }
        deletedItem = DeletedItem(snapshot: snapshot)
    }

    private func undoDelete(_ deleted: DeletedItem) {
        animated { _ = store.restoreItem(deleted.snapshot, in: list) }
        deletedItem = nil
    }

    /// LD-05a: without groups the first item goes into a new group "Items".
    private func addFirstItem() {
        let group = store.createGroup(name: String(localized: "Items", comment: "Name of the group created for the first item of a list without groups."), in: list)
        sheet = .newItem(group)
    }

    /// LD-01: a new group goes last; its name is typed right away.
    private func startNewGroup() {
        groupName = ""
        nameAlert = .new
    }

    private func startRename(_ group: GroupModel) {
        groupName = group.name
        nameAlert = .rename(group)
    }

    private func commitGroupName(_ alert: GroupNameAlert) {
        switch alert {
        case .new:
            animated { _ = store.createGroup(name: groupName, in: list) }
        case .rename(let group):
            store.renameGroup(group, to: groupName)
        }
    }

    /// A group with items asks first; an empty one goes at once (LD-05).
    private func requestDelete(_ group: GroupModel) {
        if (group.items ?? []).isEmpty {
            animated { store.deleteGroup(group) }
        } else {
            groupToDelete = group
        }
    }
}

/// The sheets of the list screen; one `sheet(item:)`.
private enum ListSheet: Identifiable {
    case newItem(GroupModel)
    case editItem(ItemModel)
    case listInfo
    case reorderGroups

    var id: String {
        switch self {
        case .newItem(let group): "newItem-\(group.uuid)"
        case .editItem(let item): "editItem-\(item.uuid)"
        case .listInfo: "listInfo"
        case .reorderGroups: "reorderGroups"
        }
    }
}

/// New Group or Rename: the same alert with a text field.
private enum GroupNameAlert {
    case new
    case rename(GroupModel)

    var isNew: Bool {
        if case .new = self { true } else { false }
    }

    var title: Text {
        switch self {
        case .new: Text("New Group")
        case .rename: Text("Rename Group")
        }
    }
}

#Preview {
    NavigationStack {
        ListViewInside(list: SampleData.shared.alexList)
    }
    .sampleDataEnvironment()
}
