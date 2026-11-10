//
//  HomeView.swift
//  Project2
//
//  Home, B-hybrid (spec 02, UX_REVIEW §13B): one `List` with a "Pinned"
//  section of tiles and an "All Lists" section of rows. It is the sidebar of
//  the split view (spec 08): tapping a list selects it, which pushes it on a
//  compact iPhone and shows it in the detail column on iPad / iPhone Duo.
//

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    pinnedContent(sections.pinned)
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
                    .onMove { store.moveList(in: sections.others, fromOffsets: $0, toOffset: $1) }
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

    /// Tiles in an adaptive grid; plain rows at accessibility text sizes (HM-02)
    /// and in Edit mode, where rows get the system reorder handles (HM-03).
    @ViewBuilder
    private func pinnedContent(_ pinned: [ListModel]) -> some View {
        if dynamicTypeSize.isAccessibilitySize || editMode.isEditing {
            ForEach(pinned) { list in
                row(list)
            }
            .onMove { store.moveList(in: pinned, fromOffsets: $0, toOffset: $1) }
            .moveDisabled(isSearching)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 12)], spacing: 12) {
                ForEach(pinned) { list in
                    tile(list)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// 150 pt gives 2 columns on every iPhone (375–440 pt). In a regular-width
    /// sidebar a smaller minimum lets a wide sidebar fit 3 or more (AD-06).
    private var minimumTileWidth: CGFloat {
        horizontalSizeClass == .regular ? 120 : 150
    }

    private func tile(_ list: ListModel) -> some View {
        Button {
            navigation.select(list)
        } label: {
            // On a compact iPhone the selection is cleared when going back, so this
            // ring only shows while the list is open next to the sidebar.
            ListTileView(list: list, isSelected: navigation.isSelected(list))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(of: list)))
        .accessibilityAddTraits(navigation.isSelected(list) ? .isSelected : [])
        .accessibilityIdentifier("home.listCard.\(list.name)")
        // HM-16: the context menu actions, reachable without a long press.
        .accessibilityAction(named: Text("Unpin")) { togglePin(list) }
        .accessibilityAction(named: Text("Edit")) { sheet = .editList(list) }
        .accessibilityAction(named: Text("Delete")) { listToDelete = list }
        .contextMenu { menu(for: list) }
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
