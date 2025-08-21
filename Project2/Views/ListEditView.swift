//
//  NewListEditView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

struct ListEditView: View {
    @Bindable var list: ListModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var showDeleteConfirmation = false
    
    let isNew: Bool
    
    init(list: ListModel, isNew: Bool = false) {
        self.list = list
        self.isNew = isNew
    }
    
    var body: some View {
        NavigationStack {
            Form {
                
                Section("Title"){
                    TextField("Title", text: $list.name)
                        .focused($isFocused)
                        .onAppear() {
                            if isNew {
                                isFocused = true
                            }
                        }
                }
                
                Section("Select one emoji"){
                    TextField("Select emoji", text: Binding(
                        get: { list.iconName },
                        set: { newValue in
                            let filtered = newValue.filter { $0.isEmoji }
                            list.iconName = String(filtered.prefix(1))
                        })
                    )
                    .keyboardType(.emoji ?? .default)
                }
                
                Section {
                    LabeledContent("Color") {
                        Menu {
                            Picker("Color", selection: $list.color) {
                                ForEach(FavoriteColor.allCases, id: \.self) { tag in
                                    Image(systemName: "circle.fill")
                                        .tint(tag.color)
                                        .tag(tag)
                                }
                            }
                            .pickerStyle(.palette)
                            
                        } label: {
                            Image(systemName: "circle.fill")
                                .tint(list.color.color)
                                .font(.title2)
                        }
                    }
                }
                
                Section {
                    
                    HStack {
                        Text("Favourite")
                        Spacer()
                        Button {
                            list.isFavorited.toggle()
                        } label: {
                            Image(systemName: list.isFavorited ? "star.fill" : "star")
                                .foregroundStyle(list.isFavorited ? .yellow : .gray)
                                .font(.title2)
                        }
                    }
                }
            }
            .headerProminence(.standard)
        }
        .navigationTitle(isNew ? "New list" : "Edit list")
        .toolbarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        
        .toolbar {
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if list.name.isEmpty {
                        list.name = "Untitled list"
                    }
                    dismiss()
                } label: { Image(systemName: "checkmark.circle.fill") }
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button (isNew ? "Cancel" : "Close") {
                    if isNew {
                        context.delete(list)
                        try? context.save()
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

extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmoji && ($0.value > 0x238C || $0.properties.isEmojiPresentation) }
    }
}
