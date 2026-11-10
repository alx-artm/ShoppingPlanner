//
//  NewItemView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//


import SwiftUI

/// Creates an item (`addingTo` is set: `item` is an uninserted draft) or edits an existing one.
struct ItemView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Bindable var item: ItemModel

    /// The group a new item is added to; `nil` when editing an existing item.
    private let newItemGroup: GroupModel?
    private var isNew: Bool { newItemGroup != nil }

    /// Set when the user tapped Delete; the item is deleted after the sheet is gone (DM-18).
    @State private var isPendingDeletion = false
    @FocusState private var isFocused: Bool

    init(item: ItemModel, addingTo group: GroupModel? = nil) {
        self.item = item
        self.newItemGroup = group
    }

    var body: some View {
        NavigationStack {
            Form {

                Section("Title & Price") {

                    TextField("Title", text: $item.name)
                        .focused($isFocused)
                        .onAppear {
                            if isNew {
                                isFocused = true
                            }
                        }
                        .accessibilityIdentifier("itemEdit.nameField")

                    HStack{
                        // An empty field stays "no price" instead of becoming 0 (BUG-07);
                        // a negative value is rejected by the store (DM-14).
                        TextField("Price", value: Binding(
                            get: { item.price },
                            set: { store.setPrice($0, for: item) }
                        ), format: .number)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("itemEdit.priceField")

                        Text("Total:")
                            .bold()

                        Group {
                            if let total = item.lineTotal {
                                Text(total, format: .number)
                            } else {
                                Text(verbatim: "—")
                            }
                        }
                        .bold()
                        .frame(width: 60)
                        .lineLimit(1)
                        .accessibilityIdentifier("itemEdit.total")
                    }
                }

                Section("Quantity") {
                    HStack {
                        let quantity = Binding(
                            get: { item.quantity },
                            set: { store.setQuantity($0, for: item) }
                        )
                        TextField("Quantity", value: quantity, format: .number)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("itemEdit.quantityField")
                        Spacer()
                        Stepper("", value: quantity, in: PlannerStore.quantityRange)
                            .labelsHidden()
                            .sensoryFeedback(.impact(weight: .light), trigger: item.quantity)
                            .accessibilityIdentifier("itemEdit.quantityStepper")
                    }
                }

                Section("Link") {
                    TextField("", text: $item.urlString)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("itemEdit.urlField")
                }

                Section("Note") {
                    TextEditor(text: $item.notes)
                        .accessibilityIdentifier("itemEdit.notesEditor")
                }
            }
            .toolbar {

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commit()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    // A new item needs a name (DM-12).
                    .disabled(isNew && PlannerStore.normalizedName(item.name) == nil)
                    .accessibilityIdentifier("itemEdit.doneButton")
                }

                ToolbarItem(placement: .cancellationAction, content: {
                    Button(isNew ? "Cancel" : "Close") {
                        if !isNew {
                            store.renameItem(item, to: item.name)
                        }
                        dismiss()
                    }
                    .foregroundColor(isNew ? .red : .accentColor)
                    .accessibilityIdentifier("itemEdit.cancelButton")
                })

                // кнопка удаления айтема внизу
                if !isNew {
                    ToolbarItem(placement: .bottomBar) {
                        Button{
                            // Close the sheet first, delete when it is gone (BUG-04 / DM-18).
                            isPendingDeletion = true
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                            Text("Delete item")
                        }
                        .foregroundColor(.red)
                        .accessibilityIdentifier("itemEdit.deleteButton")
                    }
                }
            }
            .navigationTitle(isNew ? "New item" : item.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if isPendingDeletion {
                isPendingDeletion = false
                store.deleteItem(item)
            }
        }
    }

    private func commit() {
        if let group = newItemGroup {
            store.addItem(
                name: item.name,
                to: group,
                quantity: item.quantity,
                price: item.price,
                urlString: item.urlString,
                notes: item.notes
            )
        } else {
            store.renameItem(item, to: item.name)
        }
    }
}


#Preview {
    ItemView(item: SampleData.shared.evaList.allItems.first ?? ItemModel(name: "Puss in boots"))
        .sampleDataEnvironment()
}
