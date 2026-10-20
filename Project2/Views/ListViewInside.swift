//
//  NewListView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

struct ListViewInside: View {
    @Environment(PlannerStore.self) private var store
    @Environment(LocalUIState.self) private var uiState
    @Environment(\.dismiss) private var dismiss
    let list: ListModel

    @State private var showDeleteConfirmation: Bool = false
    /// Set when the user confirmed deletion; the list is deleted after this screen is gone (DM-18).
    @State private var isPendingDeletion = false
    @State private var newItemRequest: NewItemRequest?
    /// Not inserted into the context until the user taps Done in `GroupEditView`.
    @State private var draftGroup: GroupModel?
    @State private var showEditList: Bool = false

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
                .containerRelativeFrame(.vertical) { length, _ in length * 0.6 } // центрирование
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            else {

                ForEach(groups) { group in
                    let isExpanded = uiState.isExpanded(group.uuid)

                    Section(isExpanded: Binding(
                        get: { isExpanded },
                        set: { uiState.setExpanded($0, for: group.uuid) }
                    )) {
                            if isExpanded {
                                let visibleItems = showsCompleted ? group.sortedItems : group.incompleteItems
                                ForEach(visibleItems) { item in
                                    ItemRowView(item: item)
                                }
                                .onDelete { indexSet in
                                    // Resolve offsets against the array this ForEach shows (BUG-01).
                                    let items = indexSet.map { visibleItems[$0] }
                                    for item in items { store.deleteItem(item) }
                                }

                                //MARK: КНОПКА ДОБАВЛЕНИЯ АЙТЕМОВ ДЛЯ ВСЕХ ГРУПП
                                Button {
                                    newItemRequest = NewItemRequest(group: group)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .frame(width: 28)
                                        Text("Add new item...")
                                    }
                                    .opacity(0.4)
                                }
                                .accessibilityIdentifier("group.addItemButton.\(group.name)")
                            }
                        } header: {
                            GroupHeaderView(group: group)
                        }

                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 32 }
            }

            let summary = list.summary
            Group {
                if summary.planned != 0 {
                    Section {} header: {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(summary.toBuy, format: .number)
                                .accessibilityIdentifier("listDetail.total")
                        }
                        .font(.title2)
                        .bold()
                        .headerProminence(.standard)
                    }
                }
            }
        }

        .headerProminence(.increased)

        .toolbar {
            Button("Add group", systemImage: "folder.badge.plus") {
                draftGroup = GroupModel()
            }
            .accessibilityIdentifier("listDetail.addGroupButton")

            Menu {
                Button {
                    showEditList = true
                } label: {
                    Label("Edit list", systemImage: "pencil")
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

                // по нажатию на эту кнопку будет появляться .alert, см. код ниже
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
        .listStyle(.plain)
        // МОЖНО СДЕЛАТЬ ТАК - будет вшитая фикша листа со скрывабщейся секцией, но фон листа будет серым
        // .listStyle(.sidebar)
        .navigationBarTitleDisplayMode(.inline)

        .sheet(item: $newItemRequest) { request in
            NavigationStack {
                ItemView(item: request.draft, addingTo: request.group)
            }
            .interactiveDismissDisabled()
        }

        .sheet(item: $draftGroup) { group in
            NavigationStack {
                GroupEditView(group: group, addingTo: list)
            }
            .interactiveDismissDisabled()
        }

        .sheet(isPresented: $showEditList) {
            NavigationStack {
                ListEditView(list: list)
            }
        }

        // если алерт = true, то появляется сообщение с кнопками
        .alert("Delete list?\nAll groups and items in this list will disappear forever.", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                // Close the screen first, delete when it is gone (BUG-04 / DM-18).
                isPendingDeletion = true
                dismiss()
            }
            .accessibilityIdentifier("listDetail.deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("listDetail.deleteAlert.cancelButton")
        }
        .onDisappear {
            if isPendingDeletion {
                isPendingDeletion = false
                store.deleteList(list)
            }
        }
    }
}

/// A request to add an item to `group`; `draft` is not inserted until the user taps Done.
private struct NewItemRequest: Identifiable {
    let id = UUID()
    let group: GroupModel
    let draft = ItemModel()
}

#Preview {
    NavigationStack {
        ListViewInside(list: SampleData.shared.alexList)
    }
    .sampleDataEnvironment()
}
