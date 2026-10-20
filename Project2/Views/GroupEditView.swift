//
//  NewGroupEditView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

/// Creates a group (`addingTo` is set: `group` is an uninserted draft) or edits an existing one.
struct GroupEditView: View {
    @Bindable var group: GroupModel
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    /// Set when the user confirmed deletion; the group is deleted after the sheet is gone (DM-18).
    @State private var isPendingDeletion = false

    /// The list a new group is added to; `nil` when editing an existing group.
    private let newGroupList: ListModel?
    private var isNew: Bool { newGroupList != nil }

    @FocusState private var isFocused: Bool

    init(group: GroupModel, addingTo list: ListModel? = nil) {
        self.group = group
        self.newGroupList = list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title"){
                    TextField("Title", text: $group.name)
                        .focused($isFocused)
                        .onAppear {
                            if isNew {
                                isFocused = true
                            }
                        }
                        .accessibilityIdentifier("groupEdit.nameField")
                }

                .alert("Delete group? \nAll items in this group will disappear forever.", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        // Close the sheet first, delete when it is gone (BUG-04 / DM-18).
                        isPendingDeletion = true
                        dismiss()
                    }
                    .accessibilityIdentifier("groupEdit.deleteAlert.confirmButton")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("groupEdit.deleteAlert.cancelButton")
                }
            }

            .headerProminence(.standard)
            .navigationTitle(isNew ? "New group" : "Edit group")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {

                // кнопка удаления внизу
                ToolbarItem(placement: .bottomBar){
                    if !isNew {
                        HStack {
                            Button(role: .destructive, action: {
                                showDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                Text("Delete Group")
                            }
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("groupEdit.deleteButton")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction){
                    Button {
                        if let list = newGroupList {
                            store.createGroup(name: group.name, in: list)
                        } else {
                            store.renameGroup(group, to: group.name)
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .accessibilityIdentifier("groupEdit.doneButton")
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(isNew ? "Cancel" : "Close") {
                        if !isNew {
                            store.renameGroup(group, to: group.name)
                        }
                        dismiss()
                    }
                    .foregroundColor(isNew ? .red : .accentColor)
                    .accessibilityIdentifier("groupEdit.cancelButton")
                }
            }
        }
        .onDisappear {
            if isPendingDeletion {
                isPendingDeletion = false
                store.deleteGroup(group)
            }
        }
    }
}

#Preview {
    GroupEditView(group: GroupModel(name: "Test"), addingTo: SampleData.shared.evaList)
        .sampleDataEnvironment()
}
