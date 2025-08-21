//
//  NewGroupEditView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

struct GroupEditView: View {
    @Bindable var group: GroupModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteConfirmation = false
    
    let isNew: Bool
    
    @FocusState private var isFocused: Bool
    
    init(group: GroupModel, isNew: Bool = false) {
        self.group = group
        self.isNew = isNew
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
                }
                
                .alert("Delete group? \nAll items in this group will disappear forever.", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        context.delete(group)
                        dismiss()
                        try? context.save()
                    }
                    Button("Cancel", role: .cancel) {}
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
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction){
                    Button {
                        if group.name.isEmpty {
                            group.name = "Untitled group"
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button(isNew ? "Cancel" : "Close") {
                        if isNew {
                            context.delete(group)
                            do {
                                try context.save()
                            } catch {
                                print("Cannot save context: \(error)")
                            }
                            dismiss()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(isNew ? .red : .accentColor)
                }
            }
        }
    }
}

#Preview {
    GroupEditView(group: GroupModel(name: "Test"))
}
