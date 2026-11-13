//
//  ListViewInside.swift
//  Project2
//
//  The list screen (spec 04, UX_REVIEW §5): groups as collapsible sections,
//  item rows, and the summary bar pinned above the bottom edge.
//

import SwiftUI

struct ListViewInside: View {
    @Environment(PlannerStore.self) private var store
    @Environment(LocalUIState.self) private var uiState
    @Environment(AppNavigation.self) private var navigation
    let list: ListModel

    @State private var showDeleteConfirmation: Bool = false
    @State private var newItemRequest: NewItemRequest?
    @State private var itemToEdit: ItemModel?
    /// Not inserted into the context until the user taps Done in `GroupEditView`.
    @State private var draftGroup: GroupModel?
    @State private var showEditList: Bool = false
    @State private var groupToRename: GroupModel?
    @State private var groupName = ""
    @State private var groupToDelete: GroupModel?

    private var showsCompleted: Bool {
        uiState.showsCompleted(list.uuid)
    }

    var body: some View {
        let groups = list.sortedGroups

        List {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Groups", systemImage: "folder.badge.plus")
                } description: {
                    Text("Start by adding your first group.\nTap the folder icon above.")
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(groups) { group in
                    section(for: group)
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            // Always visible, never scrolls away (LD-10).
            ListSummaryBar(list: list)
        }
        .toolbar {
            Button("Add group", systemImage: "folder.badge.plus") {
                draftGroup = GroupModel()
            }
            .accessibilityIdentifier("listDetail.addGroupButton")

            Menu {
                Button {
                    showEditList = true
                } label: {
                    Label("List Info", systemImage: "info.circle")
                }
                .accessibilityIdentifier("listDetail.menu.edit")

                Button {
                    withAnimation {
                        uiState.setShowsCompleted(!showsCompleted, for: list.uuid)
                    }
                } label: {
                    Label("\(showsCompleted ? "Hide" : "Show") completed", systemImage: showsCompleted ? "eye.slash" : "eye")
                }
                .accessibilityIdentifier("listDetail.menu.toggleCompleted")

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete list", systemImage: "trash")
                }
                .accessibilityIdentifier("listDetail.menu.delete")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("listDetail.menuButton")
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)

        .sheet(item: $newItemRequest) { request in
            ItemView(mode: .create(request.group))
        }
        .sheet(item: $itemToEdit) { item in
            ItemView(mode: .edit(item))
        }
        .sheet(item: $draftGroup) { group in
            NavigationStack {
                GroupEditView(group: group, addingTo: list)
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showEditList) {
            ListInfoView(mode: .edit(list))
        }

        .alert("Rename Group", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("Group name", text: $groupName)
                .accessibilityIdentifier("groupName.field")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let group = groupToRename { store.renameGroup(group, to: groupName) }
            }
            .accessibilityIdentifier("groupName.saveButton")
        }

        .confirmationDialog(
            deleteGroupTitle,
            isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: groupToDelete
        ) { group in
            Button("Delete Group", role: .destructive) {
                withAnimation { store.deleteGroup(group) }
            }
            .accessibilityIdentifier("groupDelete.confirmButton")
            Button("Cancel", role: .cancel) {}
        }

        .alert("Delete list?\nAll groups and items in this list will disappear forever.", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                // Closes this screen first (pop / empty detail), deletes when it is gone (DM-18).
                navigation.requestDeletion(of: list, using: store)
            }
            .accessibilityIdentifier("listDetail.deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("listDetail.deleteAlert.cancelButton")
        }
    }

    // MARK: - Sections

    private func section(for group: GroupModel) -> some View {
        let isExpanded = uiState.isExpanded(group.uuid)
        return Section(isExpanded: Binding(
            get: { isExpanded },
            set: { uiState.setExpanded($0, for: group.uuid) }
        )) {
            let visibleItems = showsCompleted ? group.sortedItems : group.incompleteItems
            ForEach(visibleItems) { item in
                ItemRowView(item: item) { itemToEdit = item }
            }
            .onDelete { indexSet in
                // Resolve offsets against the array this ForEach shows (BUG-01).
                let items = indexSet.map { visibleItems[$0] }
                for item in items { store.deleteItem(item) }
            }

            Button {
                newItemRequest = NewItemRequest(group: group)
            } label: {
                Label("New Item", systemImage: "plus")
                    .foregroundStyle(.tint)
            }
            .accessibilityIdentifier("group.addItemButton.\(group.name)")
        } header: {
            GroupHeaderView(
                group: group,
                onRename: {
                    groupName = group.name
                    groupToRename = group
                },
                onAddItem: {
                    uiState.setExpanded(true, for: group.uuid)
                    newItemRequest = NewItemRequest(group: group)
                },
                onDelete: { requestDelete(group) }
            )
        }
    }

    // MARK: - Groups

    /// A group with items asks first; an empty one goes at once (LD-05).
    private func requestDelete(_ group: GroupModel) {
        if (group.items ?? []).isEmpty {
            withAnimation { store.deleteGroup(group) }
        } else {
            groupToDelete = group
        }
    }

    private var deleteGroupTitle: Text {
        let count = groupToDelete?.items?.count ?? 0
        return Text("Delete group and \(count) items?")
    }
}

/// A request to add an item to `group`; nothing is inserted until the user taps Done.
private struct NewItemRequest: Identifiable {
    let id = UUID()
    let group: GroupModel
}

#Preview {
    NavigationStack {
        ListViewInside(list: SampleData.shared.alexList)
    }
    .sampleDataEnvironment()
}
