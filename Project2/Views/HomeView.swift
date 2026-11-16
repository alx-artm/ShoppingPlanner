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
//  Lists, and Pinned in Edit mode or at accessibility sizes) keep the real
//  `.contextMenu`, swipes and reordering: one list per cell, nothing to mix up.
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
                    // Reordering only in Edit mode: outside it, a long press is the context menu,
                    // and a drag lift competing with it left the menu stuck (the app never idled).
                    .onMove(perform: editMode.isEditing
                            ? { store.moveList(in: sections.others, fromOffsets: $0, toOffset: $1) } : nil)
                    .moveDisabled(isSearching)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .overlay {
            if lists.isEmpty {
                emptyState
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Lists")
        .searchable(text: $query, prompt: Text("Search Lists"))
        .toolbar { toolbar }
        .onChange(of: lists.isEmpty) { _, isEmpty in
            if isEmpty { editMode = .inactive }
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
        .confirmationDialog(
            Text("Delete “\(listToDelete?.name ?? "")”?"),
            isPresented: Binding(
                get: { listToDelete != nil },
                set: { if !$0 { listToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: listToDelete
        ) { list in
            Button("Delete List", role: .destructive) {
                // Closes the detail first if this list is open there (HM-10, DM-18).
                navigation.requestDeletion(of: list, using: store)
            }
            .accessibilityIdentifier("home.deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("home.deleteAlert.cancelButton")
        } message: { _ in
            Text("All groups and items will be deleted.")
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Pinned

    /// Rows instead of tiles at accessibility text sizes (HM-02) and in Edit mode,
    /// where rows get the system reorder handles (HM-03).
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
        .accessibilityAction(named: Text("Edit")) { sheet = .editList(list) }
        .accessibilityAction(named: Text("Delete")) { listToDelete = list }
    }

    // MARK: - Rows

    private func row(_ list: ListModel) -> some View {
        NavigationLink(value: list.uuid) {
            ListRowView(list: list)
        }
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
                Label("Edit", systemImage: "info.circle")
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

        Button("Edit", systemImage: "info.circle") {
            sheet = .editList(list)
        }
        .accessibilityIdentifier("home.menu.edit")

        Button("Duplicate", systemImage: "plus.square.on.square") {
            animated { store.duplicateList(list) }
        }
        .accessibilityIdentifier("home.menu.duplicate")

        ShareLink(item: ListShareText.make(for: list)) {
            Label("Share as Text", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("home.menu.share")

        Divider()

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
        ToolbarItem(placement: .topBarTrailing) {
            Button(editMode.isEditing ? "Done" : "Edit") {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            }
            .disabled(lists.isEmpty)
            .accessibilityIdentifier("home.editButton")
        }
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
