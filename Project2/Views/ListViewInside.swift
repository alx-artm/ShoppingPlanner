//
//  ListViewInside.swift
//  Project2
//
//  The list screen (spec 04, UX_REVIEW §5): groups as collapsible sections,
//  item rows with swipes and a context menu, inline adding of items with a
//  keyboard accessory bar, "＋ Add Group" at the end, and the summary bar
//  pinned above the bottom edge. Everything that changes data goes through
//  `PlannerStore`.
//
//  Inline add (LD-12...LD-17): "＋ New Item" becomes a text field. Return
//  saves the item and keeps the keyboard for the next one; Done, ⓘ or leaving
//  the field saves a non-empty draft and drops an empty one. The draft lives
//  here, so nothing is inserted before a commit.
//

import SwiftData
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
    /// The group being added to inline, `nil` when inline add is closed.
    @State private var inline: InlineAdd?
    @State private var inlineDraft = ItemDraft()
    @FocusState private var inlineFocus: InlineField?
    /// The inline name field has the keyboard (a UIKit field, outside `inlineFocus`).
    @State private var isEditingInlineName = false

    /// Any inline field has the keyboard.
    private var isTypingInline: Bool { isEditingInlineName || inlineFocus != nil }

    /// A group just added with "Add Group", to scroll to once its section is in the list.
    @State private var addedGroupID: PersistentIdentifier?

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

        ScrollViewReader { proxy in
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
        .onChange(of: inline) { old, new in
            // The new empty line after Return, and fields opened from the accessory bar,
            // stay above the keyboard and the summary bar.
            guard let new, old?.groupID == new.groupID else { return }
            withAnimation { proxy.scrollTo(InlineAdd.rowID, anchor: .bottom) }
        }
        .onChange(of: addedGroupID) { _, id in
            // A new group goes last; show its header (owner decision 2026-11-13). The same
            // ScrollViewReader + scrollTo as the owner's Quick List, which wrapped the call in
            // DispatchQueue.main.async: scrolling in the same update that adds the row does
            // nothing, the List doesn't have it yet. Here the target is state, so this runs in
            // the update after the insert; one `Task.yield()` lets the List take the new
            // section first. ScrollPosition / .scrollPosition(id:) is the iOS 17+ API for
            // ScrollView + LazyVStack; with List and sections, scrollTo is the reliable one.
            guard let id else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : .default) {
                    proxy.scrollTo(id, anchor: .top)
                }
                addedGroupID = nil
            }
        }
        }
        .overlay {
            if groups.isEmpty { emptyState }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let deletedItem {
                    UndoToast(deleted: deletedItem) { undoDelete(deletedItem) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Always visible, never scrolls away (LD-10); one line while typing (owner decision).
                ListSummaryBar(list: list, isCompact: isTypingInline)
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
            ToolbarItemGroup(placement: .keyboard) {
                if inline != nil { accessoryBar }
            }
        }
        .onChange(of: isTypingInline) { _, isTyping in
            guard !isTyping, inline != nil else { return }
            // Focus passes through "none" between two fields; only a focus that stays
            // away means the user left the row (tap elsewhere, back).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !isTypingInline, inline != nil { finishInline() }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)

        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editItem(let item, let focusFirstEmpty):
                ItemView(item: item, focusFirstEmpty: focusFirstEmpty)
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

            if inline?.groupID == group.uuid {
                InlineItemRow(draft: $inlineDraft, isEditingName: $isEditingInlineName,
                              extras: inline?.extras ?? InlineExtras(),
                              currencyCode: list.currencyCode, focus: $inlineFocus,
                              onReturn: submitInline,
                              accessory: nameFieldAccessoryBar)
                    .id(InlineAdd.rowID)
            } else {
                Button {
                    startInline(in: group)
                } label: {
                    Label("New Item", systemImage: "plus")
                        .foregroundStyle(.tint)
                }
                .accessibilityIdentifier("group.addItemButton.\(group.name)")
            }
        } header: {
            GroupHeaderView(
                group: group,
                onRename: { startRename(group) },
                onAddItem: { startInline(in: group) },
                onDelete: { requestDelete(group) }
            )
        }
    }

    private func row(_ item: ItemModel) -> some View {
        ItemRowView(item: item) { sheet = .editItem(item, focusFirstEmpty: false) }
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
        Button("Edit", systemImage: "pencil") { sheet = .editItem(item, focusFirstEmpty: false) }
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

    // MARK: - Inline add

    /// Above the keyboard: [Price] [Qty] [Link] … [ⓘ] [Done] (spec 04 Inline add, LD-15).
    @ViewBuilder
    private var accessoryBar: some View {
        Button("Price", systemImage: "tag") {
            inline?.extras.showsPrice = true
            inlineFocus = .price
        }
        .accessibilityIdentifier("inline.accessory.price")
        Button("Quantity", systemImage: "number") {
            inline?.extras.showsQuantity.toggle()
        }
        .accessibilityIdentifier("inline.accessory.quantity")
        Button("Link", systemImage: "link") {
            inline?.extras.showsLink = true
            inlineFocus = .link
        }
        .accessibilityIdentifier("inline.accessory.link")
        Spacer()
        Button("Details", systemImage: "info.circle") { openInlineDetails() }
            .disabled(!inlineDraft.hasValidName)
            .accessibilityIdentifier("inline.accessory.details")
        Button("Done", systemImage: "checkmark") { finishInline() }
            .accessibilityIdentifier("inline.accessory.done")
    }

    /// The same bar for the name field, which is a UIKit field: SwiftUI's keyboard toolbar
    /// doesn't reach it, so it is hosted as the field's input accessory view.
    private var nameFieldAccessoryBar: some View {
        HStack(spacing: 12) { accessoryBar }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .tint(.primary)
    }

    /// "＋ New Item" → a text field with the keyboard. Another open draft is saved first.
    private func startInline(in group: GroupModel, createdGroup: Bool = false) {
        if inline != nil { commitInline() }
        uiState.setExpanded(true, for: group.uuid)
        inlineDraft = ItemDraft(groupID: group.uuid)
        inline = InlineAdd(groupID: group.uuid, createdGroup: createdGroup)
        isEditingInlineName = true
    }

    /// Saves a draft with a name (LD-12); returns the new item.
    @discardableResult
    private func commitInline(_ draft: ItemDraft? = nil) -> ItemModel? {
        let draft = draft ?? inlineDraft
        guard let inline, draft.hasValidName,
              let group = list.groups?.first(where: { $0.uuid == inline.groupID }) else { return nil }
        var item: ItemModel?
        animated { item = store.addItem(from: draft, to: group) }
        return item
    }

    /// Return: save and start the next empty line in the same group, keeping the keyboard (LD-13).
    /// The name field has already emptied itself. Return on an empty line closes inline add.
    private func submitInline(_ line: String) {
        guard let groupID = inline?.groupID else { return }
        var draft = inlineDraft
        draft.name = line
        guard draft.hasValidName else {
            finishInline()
            return
        }
        commitInline(draft)
        inlineDraft = ItemDraft(groupID: groupID)
        inline?.extras = InlineExtras()
        inline?.createdGroup = false
        inline?.submitCount += 1
    }

    /// Done / focus left: save a non-empty draft, drop an empty one, close.
    private func finishInline() {
        guard let current = inline else { return }
        let saved = commitInline()
        inline = nil
        inlineFocus = nil
        isEditingInlineName = false
        // LD-05a: the "Items" group made for the first item goes away if nothing was added.
        if saved == nil, current.createdGroup,
           let group = list.groups?.first(where: { $0.uuid == current.groupID }),
           (group.items ?? []).isEmpty {
            store.deleteGroup(group)
        }
    }

    /// ⓘ: save, then open item details on the first empty field (spec 05 ID-09).
    private func openInlineDetails() {
        let item = commitInline()
        inline = nil
        inlineFocus = nil
        isEditingInlineName = false
        if let item { sheet = .editItem(item, focusFirstEmpty: true) }
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

    /// LD-05a: without groups the first item goes into a new group "Items" (removed again
    /// if the user adds nothing).
    private func addFirstItem() {
        let group = store.createGroup(name: String(localized: "Items", comment: "Name of the group created for the first item of a list without groups."), in: list)
        startInline(in: group, createdGroup: true)
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
            var group: GroupModel?
            animated { group = store.createGroup(name: groupName, in: list) }
            addedGroupID = group?.persistentModelID
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
    case editItem(ItemModel, focusFirstEmpty: Bool)
    case listInfo
    case reorderGroups

    var id: String {
        switch self {
        case .editItem(let item, _): "editItem-\(item.uuid)"
        case .listInfo: "listInfo"
        case .reorderGroups: "reorderGroups"
        }
    }
}

/// Inline add in one group (spec 04 Inline add).
private struct InlineAdd: Equatable {
    static let rowID = "inlineItemRow"

    var groupID: UUID
    var extras = InlineExtras()
    /// The group was made for this first item (LD-05a).
    var createdGroup = false
    /// Counts Returns, to scroll the new empty line into view.
    var submitCount = 0
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
