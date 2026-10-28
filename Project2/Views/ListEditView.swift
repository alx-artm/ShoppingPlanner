//
//  NewListEditView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

/// Creates a list (`isNew`: `list` is an uninserted draft) or edits an existing one.
struct ListEditView: View {
    @Bindable var list: ListModel
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

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
                        .accessibilityIdentifier("listEdit.nameField")
                }

                Section("Select one emoji"){
                    TextField("Select emoji", text: Binding(
                        get: { list.iconKind == .emoji ? list.iconName : "" },
                        set: { newValue in
                            let emoji = String(newValue.filter { $0.isEmoji }.prefix(1))
                            store.setIcon(emoji, kind: .emoji, for: list)
                        })
                    )
                    .keyboardType(.emoji ?? .default)
                    .accessibilityIdentifier("listEdit.emojiField")
                }

                Section {
                    LabeledContent("Color") {
                        Menu {
                            Picker("Color", selection: Binding(
                                get: { list.color },
                                set: { store.setColor($0, for: list) }
                            )) {
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
                        .accessibilityIdentifier("listEdit.colorMenu")
                    }
                }

                Section {

                    HStack {
                        Text("Favourite")
                        Spacer()
                        Button {
                            if isNew {
                                // Draft: the section order is assigned by `createList`.
                                list.isPinned.toggle()
                            } else {
                                store.togglePin(list)
                            }
                        } label: {
                            Image(systemName: list.isPinned ? "star.fill" : "star")
                                .foregroundStyle(list.isPinned ? .yellow : .gray)
                                .font(.title2)
                        }
                        .accessibilityIdentifier("listEdit.pinButton")
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
                    commit()
                    dismiss()
                } label: { Image(systemName: "checkmark.circle.fill") }
                .accessibilityIdentifier("listEdit.doneButton")
            }

            ToolbarItem(placement: .cancellationAction) {
                Button (isNew ? "Cancel" : "Close") {
                    if !isNew {
                        // Edits of an existing list are live; just normalise the name.
                        store.renameList(list, to: list.name)
                    }
                    dismiss()
                }
                .foregroundColor(isNew ? .red : .accentColor)
                .accessibilityIdentifier("listEdit.cancelButton")
            }
        }
    }

    private func commit() {
        if isNew {
            store.createList(
                name: list.name,
                iconName: list.iconName,
                iconKind: list.iconKind,
                color: list.color,
                isPinned: list.isPinned,
                budget: list.budget,
                currencyCode: list.currencyCode
            )
        } else {
            store.renameList(list, to: list.name)
        }
    }
}

extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmoji && ($0.value > 0x238C || $0.properties.isEmojiPresentation) }
    }
}

#Preview {
    NavigationStack {
        ListEditView(list: SampleData.shared.evaList)
    }
    .sampleDataEnvironment()
}
