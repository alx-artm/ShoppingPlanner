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
    @Environment(LinkPreviewService.self) private var linkPreviews
    @Environment(LocalUIState.self) private var uiState
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL
    @Environment(\.linkOpener) private var linkOpener
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The icon column of the rows (LD-35), scaled like the item checkbox.
    @ScaledMetric(relativeTo: .title2) private var iconColumn = ListRowGrid.iconColumnWidth
    let list: ListModel

    @State private var sheet: ListSheet?
    /// ⌘⌫ presses while item details are open (AD-12); the sheet asks before deleting.
    @State private var itemDeleteRequests = 0
    /// ⇧⌘M presses while item details are open (MH-15); the sheet toggles its draft.
    @State private var itemMustHaveRequests = 0
    @State private var showsDeleteListConfirmation = false
    /// The New Group / Rename alert (owner decision: an alert with a text field).
    @State private var nameAlert: GroupNameAlert?
    @State private var groupName = ""
    @State private var groupToDelete: GroupModel?
    /// The group being added to inline, `nil` when inline add is closed.
    @State private var inline: InlineAdd?
    @State private var inlineDraft = ItemDraft()
    /// Who has the keyboard in the inline row: the one source of truth (see `InlineFocus`).
    @State private var inlineFocus = InlineFocus()
    /// Carries `inlineFocus` out for the SwiftUI price and link fields. Set only from
    /// `moveInlineFocus`; the user's changes come back through `.onChange` into `inlineFocus`.
    @FocusState private var inlineFieldFocus: InlineField?

    /// Any inline field has the keyboard.
    private var isTypingInline: Bool { inlineFocus.isTyping }

    /// A group just added with "Add Group", to scroll to once its section is in the list.
    @State private var addedGroupID: PersistentIdentifier?

    /// "Reorder Items": the list shows drag handles for the not-bought items.
    @State private var editMode: EditMode = .inactive
    private var isReorderingItems: Bool { editMode.isEditing }

    /// The last swipe-deleted item, while its "Undo" toast is on screen (LD-09).
    @State private var deletedItem: DeletedItem?

    /// An item picked in the purchase bar, to scroll to once its row is in the list (LD-27).
    @State private var itemToReveal: PersistentIdentifier?
    /// The row highlighted for a moment after a purchase bar tap (LD-27).
    @State private var highlight: RowHighlight?

    /// Accessibility text sizes: the summary bar is one line until tapped (LD-33).
    @State private var showsFullSummary = false
    private var isSummaryCompact: Bool {
        isTypingInline || (dynamicTypeSize.isAccessibilitySize && !showsFullSummary)
    }

    private var showsCompleted: Bool {
        uiState.showsCompleted(list.uuid)
    }

    var body: some View {
        let groups = list.sortedGroups

        ScrollViewReader { proxy in
        List {
            ForEach(groups) { group in
                section(for: group, followsExpandedGroup: GroupRhythm.followsExpandedGroup(
                    group, in: groups, isExpanded: { uiState.isExpanded($0.uuid) }))
            }
            if !groups.isEmpty {
                Button {
                    startNewGroup()
                } label: {
                    gridRow(systemImage: "folder.badge.plus", identifier: "listDetail.addGroupRow") { Text("Add Group") }
                        // Icon and title in the list's ink, the same as "＋ New Item" (M7.5).
                        .foregroundStyle(.tint)
                }
                // Only the title: the icon (kept visible to UI tests for LD-35) isn't read.
                .accessibilityLabel(Text("Add Group"))
                .accessibilityIdentifier("listDetail.addGroupRow")
            }
        }
        .listStyle(.plain)
        // LD-30: the plain style's 22 pt gap above every section header becomes a flat 8 pt;
        // the header's own insets and `GroupRhythm` make up the rest.
        .listSectionSpacing(GroupRhythm.sectionSpacing)
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
        .onChange(of: itemToReveal) { _, id in
            // Same pattern as a new group: the row may have just appeared (expanded group,
            // shown bought items), so scroll in a later update.
            guard let id else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : .default) {
                    proxy.scrollTo(id, anchor: .center)
                }
                itemToReveal = nil
            }
        }
        }
        .overlay {
            if groups.isEmpty { emptyState }
        }
        // AR-16, AR-22: an archived list stays editable; the banner says so and offers Restore.
        .archivedBanner(for: list, onRestore: restoreList)
        // LD-34: a bar, not an inset: the list gets the system scroll edge effect under it,
        // so rows passing behind the summary bar fade out instead of showing through.
        .safeAreaBar(edge: .bottom) { bottomBar }
        .task(id: duplicateShownHere?.id) {
            guard let duplicate = duplicateShownHere else { return }
            // HM-44: said once the copy's screen is up; a moment later, so the push's own
            // screen change doesn't cut the announcement off.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(
                DuplicateText.created(originalName: duplicate.originalName)).post()
            try? await Task.sleep(for: UndoToast.duration)
            if !Task.isCancelled { navigation.dismissDuplicateToast(duplicate.id) }
        }
        // HM-41: leaving the copy ends the toast in `AppNavigation` (selection changes),
        // not on `onDisappear`: a slow push can rebuild this screen and fire it early.
        .task(id: deletedItem?.id) {
            guard deletedItem != nil else { return }
            try? await Task.sleep(for: DeletedItem.duration)
            if !Task.isCancelled { deletedItem = nil }
        }
        .task(id: highlight) {
            guard highlight != nil else { return }
            try? await Task.sleep(for: RowHighlight.duration)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { highlight = nil }
            }
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
        .onChange(of: inlineFieldFocus) { old, new in
            // The user moved the keyboard to or away from the price / link field.
            if let new {
                reportInlineFocus { $0.began(new) }
            } else if let old {
                reportInlineFocus { $0.ended(old) }
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
        // A tap on a row's link tile opens Safari inside the app, over this screen (LP-16).
        .inAppBrowser()
        // `debug.lastOpenedLink` for UI tests (`-UITestsRecordOpenedLinks`); nothing otherwise.
        .openedLinkProbe()
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        // M7.5: the screen speaks in the list's color: the bought checkbox, "＋ New Item",
        // "＋ Add Group", Restore / Undo and the toolbar. A readable shade (`ink`), not the
        // raw color; status colors (red, orange ★, green) are set explicitly and stay.
        .tint(list.color.ink)
        // ⌘N / ⇧⌘N on iPad (AD-12); off while a sheet, an alert or Reorder Items is up.
        .focusedSceneValue(\.listShortcutActions, acceptsShortcuts
                           ? ListShortcutActions(newItem: newItemFromShortcut, newGroup: startNewGroup)
                           : nil)
        // ⌘⌫ only while item details are open. Published here, not by the sheet: a value
        // published inside the sheet doesn't reach the scene's commands.
        .focusedSceneValue(\.itemShortcutActions, isEditingItem
                           ? ItemShortcutActions(requestDelete: { itemDeleteRequests += 1 },
                                                 toggleMustHave: { itemMustHaveRequests += 1 })
                           : nil)

        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editItem(let item, let focusFirstEmpty):
                ItemView(item: item, focusFirstEmpty: focusFirstEmpty,
                         presentingSizeClass: horizontalSizeClass,
                         deleteRequests: itemDeleteRequests,
                         mustHaveRequests: itemMustHaveRequests)
                    .tint(list.color.ink)
            case .listInfo: ListInfoView(mode: .edit(list)).tint(list.color.ink)
            case .reorderGroups: ReorderGroupsView(list: list).tint(list.color.ink)
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

    /// The summary bar, with the "Undo" toast above it while it is shown.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let duplicate = duplicateShownHere {
                // HM-41: this list is a copy just made by Duplicate; Undo takes it back.
                UndoToast(duplicate: duplicate) { navigation.undoDuplicate(list, using: store) }
                    .transition(toastTransition)
            }
            if let deletedItem {
                UndoToast(deleted: deletedItem) { undoDelete(deletedItem) }
                    .transition(toastTransition)
            }
            // Always visible, never scrolls away (LD-10); one line while typing (owner
            // decision) and, until tapped, at accessibility text sizes (LD-33).
            ListSummaryBar(list: list, isCompact: isSummaryCompact, onShowItem: reveal,
                           onToggleForm: summaryToggle)
        }
        .animation(reduceMotion ? nil : .snappy, value: deletedItem)
        .animation(reduceMotion ? nil : .snappy, value: duplicateShownHere)
    }

    /// Slides up; with Reduce Motion it only fades in (HM-45).
    private var toastTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    /// The Duplicate that made this list, while its toast is up (HM-41).
    private var duplicateShownHere: RecentDuplicate? {
        guard let duplicate = navigation.recentDuplicate, duplicate.copyID == list.uuid else { return nil }
        return duplicate
    }

    /// Accessibility sizes, not typing: a tap switches the summary bar's form (LD-33).
    private var summaryToggle: (() -> Void)? {
        guard dynamicTypeSize.isAccessibilitySize, !isTypingInline else { return nil }
        return { withAnimation(reduceMotion ? nil : .snappy) { showsFullSummary.toggle() } }
    }

    // MARK: - Sections

    private func section(for group: GroupModel, followsExpandedGroup: Bool) -> some View {
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
                            // A button whose label is one text exposes no children to UI tests;
                            // this empty marker over the text lets them measure LD-35.
                            .overlay {
                                Color.clear
                                    .accessibilityElement()
                                    .accessibilityIdentifier("group.boughtRow.\(group.name).title")
                            }
                            // LD-35: on the text column, under the item names.
                            .padding(.leading, iconColumn + ListRowGrid.spacing)
                    }
                    .accessibilityLabel(Text("\(boughtCount) bought"))
                    .accessibilityHint(Text("Shows bought items"))
                    .accessibilityIdentifier("group.boughtRow.\(group.name)")
                }
            }

            if inline?.groupID == group.uuid {
                InlineItemRow(draft: $inlineDraft, focus: inlineFocus,
                              fieldFocus: $inlineFieldFocus,
                              extras: inline?.extras ?? InlineExtras(),
                              currencyCode: list.currencyCode,
                              onNameFocusChange: { hasFocus in
                                  reportInlineFocus { hasFocus ? $0.began(.name) : $0.ended(.name) }
                              },
                              onReturn: submitInline,
                              onFieldAppear: inlineFieldAppeared,
                              accessory: nameFieldAccessoryBar)
                    .id(InlineAdd.rowID)
            } else {
                Button {
                    startInline(in: group)
                } label: {
                    gridRow(systemImage: "plus", identifier: "group.addItemButton.\(group.name)") { Text("New Item") }
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel(Text("New Item"))
                .accessibilityIdentifier("group.addItemButton.\(group.name)")
            }
        } header: {
            GroupHeaderView(
                group: group,
                onRename: { startRename(group) },
                onAddItem: { startInline(in: group) },
                onDelete: { requestDelete(group) }
            )
            .listRowInsets(.top, GroupRhythm.headerTopInset(followsExpandedGroup: followsExpandedGroup))
            .listRowInsets(.bottom, GroupRhythm.headerBottomInset)
        }
    }

    /// A row on the leading grid (LD-35): the icon centered in the checkbox column, the text
    /// where item names start. "＋ New Item" and "＋ Add Group".
    /// `identifier` + ".icon" / ".title" lets UI tests measure the grid.
    private func gridRow(systemImage: String, identifier: String,
                         @ViewBuilder title: () -> Text) -> some View {
        HStack(spacing: ListRowGrid.spacing) {
            Image(systemName: systemImage)
                .imageScale(.large)
                // Tinted like a Label's icon in a list button; the title keeps its own color.
                .foregroundStyle(.tint)
                // Centered by its layout frame: "folder.badge.plus" has its badge on the right,
                // so the folder itself sits on the axis of the chevron and the checkbox.
                .frame(width: iconColumn)
                .accessibilityIdentifier("\(identifier).icon")
            title()
                .accessibilityIdentifier("\(identifier).title")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private func row(_ item: ItemModel) -> some View {
        ItemRowView(item: item) { sheet = .editItem(item, focusFirstEmpty: false) }
            // A shown row with a link but no preview fetches it (LP-01b). Rows of a collapsed
            // group are never built, so they don't fetch.
            .onAppear { linkPreviews.fetchIfNeeded(for: item) }
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
                // Spec 11: second, so a full swipe still toggles Bought. No reordering (MH-06).
                Button {
                    animated { store.toggleMustHave(item) }
                } label: {
                    item.isMustHave
                        ? Label("Unmark", systemImage: "star.slash")
                        : Label("Must-Have", systemImage: "star.fill")
                }
                .tint(item.isMustHave ? .gray : .orange)
                .accessibilityIdentifier("item.swipe.mustHave")
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
            // LD-27: picked in the purchase bar.
            .listRowBackground(highlight?.itemID == item.persistentModelID
                               ? list.color.color.opacity(0.2) : nil)
    }

    @ViewBuilder
    private func itemMenu(_ item: ItemModel) -> some View {
        Button("Edit", systemImage: "pencil") { sheet = .editItem(item, focusFirstEmpty: false) }
            .accessibilityIdentifier("item.menu.edit")
        // The menu shows a checkmark while the item is marked (MH-04).
        Toggle("Must-Have", systemImage: "star", isOn: Binding(
            get: { item.isMustHave },
            set: { _ in animated { store.toggleMustHave(item) } }
        ))
        .accessibilityIdentifier("item.menu.mustHave")
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
            // D4: the menu opens the shop's app or Safari; the tile opens the page in the app.
            Button("Open Link", systemImage: "safari") { linkOpener.open(url, .external, using: openURL) }
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
        Button("Price", systemImage: "tag") { showInlineField(.price) }
        .accessibilityIdentifier("inline.accessory.price")
        Button("Quantity", systemImage: "number") {
            inline?.extras.showsQuantity.toggle()
        }
        .accessibilityIdentifier("inline.accessory.quantity")
        Button("Link", systemImage: "link") { showInlineField(.link) }
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

    /// A command of the screen moves the inline focus: the owner changes, then the SwiftUI
    /// fields follow in the same update. The name field follows the owner by itself
    /// (`InlineNameField`); price and link through `inlineFieldFocus`. A price or link field
    /// is focused only when the owner changed (a field scrolled back into view mustn't take
    /// the keyboard); "nobody" always clears it, as closing did before.
    private func moveInlineFocus(_ command: (inout InlineFocus) -> Void) {
        var focus = inlineFocus
        command(&focus)
        let changed = focus != inlineFocus
        if changed { inlineFocus = focus }
        switch focus.field {
        case .price, .link: if changed { inlineFieldFocus = focus.field }
        case nil: inlineFieldFocus = nil
        // The name field takes the keyboard itself; a price or link field that has it gives it
        // up then, which comes back through `.onChange(of: inlineFieldFocus)` and is ignored.
        case .name: break
        }
    }

    /// A field reports that the user moved the keyboard: only the owner changes. The fields
    /// already are where the user put them, so nothing is sent back to them (a late "ended" of
    /// one field mustn't take the keyboard from the next one).
    private func reportInlineFocus(_ report: (inout InlineFocus) -> Void) {
        var focus = inlineFocus
        report(&focus)
        if focus != inlineFocus { inlineFocus = focus }
    }

    /// [Price] / [Link]: shows the field in the row and gives it the keyboard (LD-15).
    /// A field already in the row is focused at once. A new one is inserted by the next
    /// render, so the focus waits for it (`InlineFocus.pending`) and moves in its `onAppear`:
    /// no race between the insertion and the focus change, however slow the device.
    private func showInlineField(_ field: InlineField) {
        guard let current = inline else { return }
        let isShown = current.extras.isShown(field)
        moveInlineFocus { $0.request(field, isShown: isShown) }
        if isShown { return }
        if let delay = LaunchConfiguration.inlineFieldDelayOverride {
            // UI tests: the field arrives late, as on a slow device; the focus must still follow.
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                if inline?.groupID == current.groupID { inline?.extras.show(field) }
            }
        } else {
            inline?.extras.show(field)
        }
    }

    /// A price or link field is in the row: it takes the keyboard if [Price] / [Link] asked for it.
    private func inlineFieldAppeared(_ field: InlineField) {
        moveInlineFocus { $0.fieldAppeared(field) }
    }

    /// "＋ New Item" → a text field with the keyboard. Another open draft is saved first.
    private func startInline(in group: GroupModel, createdGroup: Bool = false) {
        if inline != nil { commitInline() }
        uiState.setExpanded(true, for: group.uuid)
        inlineDraft = ItemDraft(groupID: group.uuid)
        inline = InlineAdd(groupID: group.uuid, createdGroup: createdGroup)
        moveInlineFocus { $0.focusName() }
    }

    /// Saves a draft with a name (LD-12); returns the new item.
    @discardableResult
    private func commitInline(_ draft: ItemDraft? = nil) -> ItemModel? {
        let draft = draft ?? inlineDraft
        guard let inline, draft.hasValidName,
              let group = list.groups?.first(where: { $0.uuid == inline.groupID }) else { return nil }
        var item: ItemModel?
        animated { item = store.addItem(from: draft, to: group) }
        if let item { linkPreviews.fetchIfNeeded(for: item) } // LP-01
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
        moveInlineFocus { $0.nextItem() }
        inline?.createdGroup = false
        inline?.submitCount += 1
    }

    /// Done / focus left: save a non-empty draft, drop an empty one, close.
    private func finishInline() {
        guard let current = inline else { return }
        let saved = commitInline()
        inline = nil
        moveInlineFocus { $0.close() }
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
        moveInlineFocus { $0.close() }
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
                // HM-39: the same operation as on Home and in the Archive (toast with Undo).
                navigation.openDuplicate(of: list, using: store)
            }
            .accessibilityIdentifier("listDetail.menu.duplicate")

            Divider()

            // AR-10: Archive before Delete List; an archived list offers Restore there (AR-06).
            if list.isArchived {
                Button("Restore", systemImage: "arrow.uturn.backward", action: restoreList)
                    .accessibilityIdentifier("listDetail.menu.restore")
            } else {
                Button(ArchiveText.archiveAction, systemImage: "archivebox") {
                    let name = list.name
                    // Closes this screen first, archives when it is gone (AR-12).
                    navigation.requestArchive(of: list, using: store)
                    ArchiveAnnouncement.archived(name)
                }
                .accessibilityIdentifier("listDetail.menu.archive")
            }

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

    /// The list stays open, the banner goes (AR-17).
    private func restoreList() {
        store.restoreList(list)
        ArchiveAnnouncement.restored(list.name)
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

    /// LD-27: a purchase bar segment was tapped. Its row is made visible (its group expanded,
    /// bought items shown if they were hidden), scrolled to, and highlighted for a moment.
    private func reveal(_ id: PersistentIdentifier) {
        guard let item = list.allItems.first(where: { $0.persistentModelID == id }) else { return }
        if let group = item.group, !uiState.isExpanded(group.uuid) {
            uiState.setExpanded(true, for: group.uuid)
        }
        if item.isComplete, !showsCompleted {
            uiState.setShowsCompleted(true, for: list.uuid)
        }
        itemToReveal = id
        highlight = RowHighlight(itemID: id)
    }

    /// LD-05a: without groups the first item goes into a new group "Items" (removed again
    /// if the user adds nothing).
    private func addFirstItem() {
        let group = store.createGroup(name: String(localized: "Items", comment: "Name of the group created for the first item of a list without groups."), in: list)
        startInline(in: group, createdGroup: true)
    }

    private var isEditingItem: Bool {
        if case .editItem = sheet { true } else { false }
    }

    /// Nothing covers the list, so ⌘N / ⇧⌘N may act on it.
    private var acceptsShortcuts: Bool {
        sheet == nil && nameAlert == nil && groupToDelete == nil
            && !showsDeleteListConfirmation && !isReorderingItems
    }

    /// ⌘N: inline add in the group an item was added to last, else the first expanded one;
    /// without groups, the first item makes the "Items" group (LD-05a). See `NewItemTarget`.
    private func newItemFromShortcut() {
        let groups = list.sortedGroups
        let candidates = groups.map {
            NewItemTarget.Candidate($0, isExpanded: uiState.isExpanded($0.uuid))
        }
        if let id = NewItemTarget.groupID(in: candidates),
           let group = groups.first(where: { $0.uuid == id }) {
            startInline(in: group)
        } else {
            addFirstItem()
        }
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

/// A row highlighted after a purchase bar tap (LD-27). A new tap, even on the same item,
/// is a new value, so the timer starts again.
private struct RowHighlight: Equatable {
    let itemID: PersistentIdentifier
    let token = UUID()

    /// About a second (a UI test can make it longer, see `LaunchConfiguration`).
    static var duration: Duration {
        LaunchConfiguration.rowHighlightDurationOverride ?? .seconds(1)
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
