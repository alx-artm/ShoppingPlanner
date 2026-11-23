//
//  HomeView.swift
//  Project2
//
//  Home, B-hybrid (spec 02, UX_REVIEW §13B): one `List` with a "Pinned"
//  section of tiles and an "All Lists" section of rows. It is the sidebar of
//  the split view (spec 08): tapping a list selects it, which pushes it on a
//  compact iPhone and shows it in the detail column on iPad / iPhone Duo.
//
//  BUG-27: the tile grid is one `List` row, and `List` turns any `.contextMenu`
//  inside a row into the context menu of the whole cell. With several tiles in
//  the row, a long press lifted the whole grid and every tile's menu acted on
//  one list. So a tile is not a `Button` + `.contextMenu` but a `Menu` with a
//  `primaryAction`: tap opens the list, long press opens the menu of that tile.
//  A `Menu` is its own control, so the cell never takes it over. Rows (All
//  Lists, and Pinned in reorder mode or at accessibility sizes) keep the real
//  `.contextMenu`, swipes and reordering: one list per cell, nothing to mix up.
//
//  Reordering is a mode (HM-32…HM-35): ⋯ → "Reorder Lists" shows the system
//  handles, and Done ends it. It is not a nav-bar "Edit" button, because Home
//  has nothing else to edit: a list's details are "List Info" (HM-36).
//
//  Archived lists (spec 10) are not in Pinned / All Lists. The last section is
//  one "Archive N" row that opens the Archive in this column; while searching,
//  matching archived lists show in an "In Archive" section instead (AR-20).
//

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @Query private var lists: [ListModel]

    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @State private var sheet: HomeSheet?
    @State private var listToDelete: ListModel?

    var body: some View {
        @Bindable var navigation = navigation
        let sections = HomeSections(lists: lists, query: query)

        List(selection: $navigation.selectedListID) {
            if !sections.pinned.isEmpty {
                Section {
                    if showsPinnedAsRows {
                        ForEach(sections.pinned) { list in
                            row(list)
                        }
                        .onMove(perform: editMode.isEditing
                                ? { store.moveList(in: sections.pinned, fromOffsets: $0, toOffset: $1) } : nil)
                        .moveDisabled(isSearching)
                    } else {
                        pinnedGrid(sections.pinned)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Pinned")
                } footer: {
                    if sections.exceedsPinnedSoftLimit {
                        // HM-15: a hint, pinning is not blocked.
                        Text("Tip: Home stays tidy with up to 6 pinned lists.")
                            .accessibilityIdentifier("home.pinnedHint")
                    }
                }
            }

            if !sections.others.isEmpty {
                Section("All Lists") {
                    ForEach(sections.others) { list in
                        row(list)
                    }
                    // Reordering only in reorder mode: outside it, a long press is the context menu,
                    // and a drag lift competing with it left the menu stuck (the app never idled).
                    .onMove(perform: editMode.isEditing
                            ? { store.moveList(in: sections.others, fromOffsets: $0, toOffset: $1) } : nil)
                    .moveDisabled(isSearching)
                }
            }

            if sections.showsNoActiveLists {
                // In the list, not an overlay: the Archive row under it must stay tappable (AR-13).
                Section {
                    noActiveListsState
                        .listRowBackground(Color.clear)
                }
            }

            if !sections.archiveMatches.isEmpty {
                Section {
                    ForEach(sections.archiveMatches) { list in
                        ArchivedListRow(list: list) { listToDelete = list }
                    }
                } header: {
                    Text("In Archive")
                        .accessibilityIdentifier("home.searchArchiveSection")
                }
            }

            // AR-09: not a list (no selection, swipe, menu or reordering), hidden in reorder mode.
            if sections.showsArchiveRow && !editMode.isEditing {
                Section {
                    archiveRow(count: sections.archivedCount)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .overlay {
            if lists.isEmpty {
                emptyState
            } else if sections.showsNoSearchResults {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Lists")
        .searchable(text: $query, prompt: Text("Search Lists"))
        .toolbar { toolbar }
        // HM-35: a list deleted elsewhere (the detail column on iPad) can leave nothing to reorder.
        .onChange(of: canReorder) { _, canReorder in
            if !canReorder { editMode = .inactive }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newList(let draft):
                ListInfoView(mode: .create(draft))
            case .editList(let list):
                ListInfoView(mode: .edit(list))
            case .templates:
                TemplatePickerView { template in
                    // Replacing the item closes the picker and opens List Info (LI-12).
                    self.sheet = .newList(ListDraft(template: template, currencyCode: store.defaultCurrencyCode))
                }
            case .settings:
                SettingsView()
            }
        }
        .deleteListConfirmation($listToDelete, identifierPrefix: "home") { list in
            // Closes the detail first if this list is open there (HM-10, DM-18).
            navigation.requestDeletion(of: list, using: store)
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whole sections, not the search results: the search only hides rows (HM-32).
    private var canReorder: Bool {
        HomeSections(lists: lists).canReorder
    }

    // MARK: - Pinned

    /// Rows instead of tiles at accessibility text sizes (HM-02) and in reorder mode,
    /// where rows get the system reorder handles (HM-03, HM-33).
    private var showsPinnedAsRows: Bool {
        dynamicTypeSize.isAccessibilitySize || editMode.isEditing
    }

    /// Exactly 2 columns on every width (HM-02, AD-06). `Grid` gives both tiles of
    /// a row the row's height, so tiles of one row are equal (HM-28).
    private func pinnedGrid(_ pinned: [ListModel]) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(TileRow.rows(of: pinned)) { pair in
                GridRow {
                    tile(pair.first)
                    if let second = pair.second {
                        tile(second)
                    } else {
                        // Keeps a single tile at half the width.
                        Color.clear.gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
    }

    /// Tap opens the list, long press shows the tile's own menu (HM-04, HM-09, BUG-27).
    private func tile(_ list: ListModel) -> some View {
        Menu {
            menu(for: list)
        } label: {
            // On a compact iPhone the selection is cleared when going back, so this
            // ring only shows while the list is open next to the sidebar.
            ListTileView(list: list, isSelected: navigation.isSelected(list))
        } primaryAction: {
            navigation.select(list)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(of: list)))
        .accessibilityAddTraits(navigation.isSelected(list) ? .isSelected : [])
        .accessibilityIdentifier("home.listCard.\(list.name)")
        // HM-16: the menu actions, reachable without a long press.
        .accessibilityAction(named: Text("Unpin")) { togglePin(list) }
        .accessibilityAction(named: Text("List Info")) { sheet = .editList(list) }
        .accessibilityAction(named: Text(ArchiveText.archiveAction)) { archive(list) }
        .accessibilityAction(named: Text("Delete")) { listToDelete = list }
    }

    // MARK: - Rows

    private func row(_ list: ListModel) -> some View {
        NavigationLink(value: list.uuid) {
            ListRowView(list: list)
                // Keeps the texts dark on the outlined selected row; the system would turn
                // them white for its own accent fill.
                .foregroundStyle(Color(.label))
        }
        // M7.5: the open list is outlined in its own color, like its tile (iPad sidebar),
        // instead of the system's accent fill.
        .listRowBackground(navigation.isSelected(list) ? SelectedListRowBackground(list: list) : nil)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(of: list)))
        .accessibilityIdentifier("home.listRow.\(list.name)")
        .swipeActions(edge: .leading) {
            Button {
                togglePin(list)
            } label: {
                pinLabel(for: list)
            }
            .tint(.yellow)
            .accessibilityIdentifier("home.swipe.togglePin")

            // AR-10: after Pin. No confirmation: Restore undoes it.
            Button {
                archive(list)
            } label: {
                Label(ArchiveText.archiveAction, systemImage: "archivebox")
            }
            .tint(.indigo)
            .accessibilityIdentifier("home.swipe.archive")
        }
        .swipeActions(edge: .trailing) {
            // No destructive role: the row must stay until the deletion is confirmed (HM-10).
            Button {
                listToDelete = list
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("home.swipe.delete")

            Button {
                sheet = .editList(list)
            } label: {
                Label("List Info", systemImage: "info.circle")
            }
            .tint(.gray)
            .accessibilityIdentifier("home.swipe.edit")
        }
        .contextMenu { menu(for: list) }
    }

    /// The same sentence for the tile and the row of a list (HM-16).
    private func accessibilityLabel(of list: ListModel) -> String {
        ListStatusText(list.summary, currencyCode: list.currencyCode, locale: locale)
            .accessibilityLabel(name: list.name)
    }

    // MARK: - Menus and actions

    /// Context menu of tiles and rows (HM-09).
    @ViewBuilder
    private func menu(for list: ListModel) -> some View {
        Button {
            togglePin(list)
        } label: {
            pinLabel(for: list)
        }
        .accessibilityIdentifier("home.menu.togglePin")

        // "List Info", not "Edit": the same name as in the list's ⋯ menu (HM-36).
        Button("List Info", systemImage: "info.circle") {
            sheet = .editList(list)
        }
        .accessibilityIdentifier("home.menu.edit")

        // HM-39: the copy opens, as from the Archive and the open list's ⋯.
        Button("Duplicate", systemImage: "plus.square.on.square") {
            animated { navigation.openDuplicate(of: list, using: store) }
        }
        .accessibilityIdentifier("home.menu.duplicate")

        ShareLink(item: ListShareText.make(for: list)) {
            Label("Share as Text", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("home.menu.share")

        Divider()

        // AR-10: before Delete, with the other "put away" action. No confirmation (reversible).
        Button(ArchiveText.archiveAction, systemImage: "archivebox") {
            archive(list)
        }
        .accessibilityIdentifier("home.menu.archive")

        Button("Delete", systemImage: "trash", role: .destructive) {
            listToDelete = list
        }
        .accessibilityIdentifier("home.menu.delete")
    }

    private func pinLabel(for list: ListModel) -> some View {
        list.isPinned
            ? Label("Unpin", systemImage: "pin.slash")
            : Label("Pin", systemImage: "pin")
    }

    private func togglePin(_ list: ListModel) {
        animated { store.togglePin(list) }
    }

    /// AR-11, AR-12: leaves its section at once; an open list closes first.
    private func archive(_ list: ListModel) {
        let name = list.name
        animated { navigation.requestArchive(of: list, using: store) }
        ArchiveAnnouncement.archived(name)
    }

    /// The section change animates, unless Reduce Motion is on (HM-08).
    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .default, change)
    }

    private func newList() {
        sheet = .newList(ListDraft(currencyCode: store.defaultCurrencyCode))
    }

    // MARK: - Toolbar and empty state

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") {
                sheet = .settings
            }
            .accessibilityIdentifier("home.settingsButton")
        }
        if editMode.isEditing {
            // HM-33: only Done while reordering, like `listDetail.reorderDoneButton`.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark", role: .confirm) {
                    withAnimation { editMode = .inactive }
                }
                .accessibilityIdentifier("home.reorderDoneButton")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
            ToolbarItem(placement: .topBarTrailing) {
                // Tap: a new empty list. Long press: the choice with templates (LI-12).
                Menu {
                    Button("New List", systemImage: "plus") { newList() }
                        .accessibilityIdentifier("home.menu.newList")
                    Button("From Template", systemImage: "square.grid.2x2") { sheet = .templates }
                        .accessibilityIdentifier("home.menu.fromTemplate")
                } label: {
                    Label("New List", systemImage: "plus")
                } primaryAction: {
                    newList()
                }
                .accessibilityIdentifier("home.newListButton")
            }
        }
    }

    /// ⋯ of Home (HM-31, HM-32). Always shown, even with no lists: "New from Template"
    /// works then too, and "Reorder Lists" stays visible but disabled.
    private var moreMenu: some View {
        Menu {
            Button("New from Template", systemImage: "square.grid.2x2") { sheet = .templates }
                .accessibilityIdentifier("home.menu.newFromTemplate")
            Button("Reorder Lists", systemImage: "arrow.up.arrow.down") {
                withAnimation { editMode = .active }
            }
            .disabled(!canReorder)
            .accessibilityIdentifier("home.menu.reorderLists")
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("home.menuButton")
    }

    /// "Archive  N  >", the last section (AR-08). One VoiceOver element: "Archive, 3 lists" (AR-23).
    private func archiveRow(count: Int) -> some View {
        Button {
            navigation.showArchive()
        } label: {
            HStack {
                Label("Archive", systemImage: "archivebox")
                Spacer(minLength: 8)
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Archive, \(count) lists"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.archiveRow")
    }

    /// Every list is archived (AR-13): not the onboarding text, the Archive row stays below.
    private var noActiveListsState: some View {
        ContentUnavailableView {
            Label("No Active Lists", systemImage: "cart")
        } description: {
            Text("Create a new list or restore one from the Archive.")
        } actions: {
            Button("New List") { newList() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home.emptyActiveState.newListButton")
            Button("Start from Template") { sheet = .templates }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("home.emptyActiveState.templateButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.emptyActiveState")
    }

    /// No lists at all (HM-14). Centered by `ContentUnavailableView` in an overlay (AD-07).
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "cart")
        } description: {
            Text("Plan purchases for a project, a trip or a celebration, and always see how much is left to buy.")
        } actions: {
            Button("New List") { newList() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home.emptyState.newListButton")
            Button("Start from Template") { sheet = .templates }
                .accessibilityIdentifier("home.emptyState.templateButton")
        }
        // .contain keeps the buttons' own identifiers (otherwise they inherit this one).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.emptyState")
    }
}

/// One row of the 2-column tile grid: `[a, b, c]` → `(a, b), (c, nil)`.
private struct TileRow: Identifiable {
    let first: ListModel
    let second: ListModel?

    var id: UUID { first.uuid }

    static func rows(of lists: [ListModel]) -> [TileRow] {
        stride(from: 0, to: lists.count, by: 2).map { index in
            TileRow(first: lists[index], second: index + 1 < lists.count ? lists[index + 1] : nil)
        }
    }
}

/// The sheets Home can show. One `sheet(item:)`, so switching from the template
/// picker to List Info is a single item change.
private enum HomeSheet: Identifiable {
    case newList(ListDraft)
    case editList(ListModel)
    case templates
    case settings

    var id: String {
        switch self {
        case .newList: "newList"
        case .editList(let list): "editList-\(list.uuid)"
        case .templates: "templates"
        case .settings: "settings"
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .sampleDataEnvironment()
}

/// The row of the list open next to the sidebar: the normal cell, outlined in the list's ink.
private struct SelectedListRowBackground: View {
    let list: ListModel

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(list.color.ink, lineWidth: 2)
                    .padding(2)
            }
    }
}
