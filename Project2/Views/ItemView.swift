//
//  ItemView.swift
//  Project2
//
//  Item details (spec 05, UX_REVIEW §6): name, price per unit, quantity,
//  total, link, note, group, delete. The sheet edits an `ItemDraft`, so ✕
//  discards everything and ✓ saves everything in one go (ID-01).
//

import SwiftUI

struct ItemView: View {
    enum Mode {
        case create(GroupModel)
        case edit(ItemModel)
    }

    /// Fields that can take the keyboard focus.
    enum Field: Hashable {
        case name, price, quantity, link, note
    }

    let mode: Mode

    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft: ItemDraft
    private let initialDraft: ItemDraft
    /// Where the keyboard goes when the sheet opens.
    private let initialFocus: Field?
    @FocusState private var focus: Field?
    @State private var quantityText: String
    @State private var showsDeleteConfirmation = false
    /// Set when the user confirmed deletion; the item is deleted after the sheet is gone (ID-11, DM-18).
    @State private var isPendingDeletion = false

    /// - Parameter focusFirstEmpty: opened from inline add (ⓘ): focus the first empty
    ///   field of Price, Link, Note (ID-09).
    init(mode: Mode, focusFirstEmpty: Bool = false) {
        self.mode = mode
        let draft = switch mode {
        case .create(let group): ItemDraft(groupID: group.uuid)
        case .edit(let item): ItemDraft(item: item)
        }
        initialDraft = draft
        _draft = State(initialValue: draft)
        _quantityText = State(initialValue: "\(draft.quantity)")

        if case .create = mode {
            initialFocus = .name
        } else if focusFirstEmpty {
            initialFocus = if draft.price == nil { .price }
                else if draft.urlString.isEmpty { .link }
                else if draft.notes.isEmpty { .note }
                else { nil }
        } else {
            initialFocus = nil
        }
    }

    private var isNew: Bool {
        if case .create = mode { true } else { false }
    }

    private var list: ListModel? {
        switch mode {
        case .create(let group): group.list
        case .edit(let item): item.parentList
        }
    }

    private var currencyCode: String {
        list?.currencyCode ?? ListModel.fallbackCurrencyCode
    }

    private var hasChanges: Bool {
        draft != initialDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Item name", text: $draft.name, axis: .vertical)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("itemEdit.nameField")
                }

                Section {
                    adaptiveRow("Price per unit") {
                        MoneyField("Price", value: $draft.price, currencyCode: currencyCode,
                                   focus: $focus, field: .price, identifier: "itemEdit.priceField",
                                   alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    }
                    quantityRow
                    adaptiveRow("Total") {
                        Group {
                            if let total = draft.lineTotal(listCurrencyCode: currencyCode) {
                                MoneyText(total, currencyCode: currencyCode)
                            } else {
                                Text(verbatim: "—")
                                    .accessibilityLabel(Text("No price"))
                            }
                        }
                        .bold()
                        .accessibilityIdentifier("itemEdit.total")
                    }
                }

                linkSection

                Section("Note") {
                    TextField("Note", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focus, equals: .note)
                        .accessibilityIdentifier("itemEdit.notesField")
                }

                if let list, list.sortedGroups.count > 1 {
                    Section {
                        Picker("Group", selection: $draft.groupID) {
                            ForEach(list.sortedGroups) { group in
                                Text(group.name).tag(Optional(group.uuid))
                            }
                        }
                        .accessibilityIdentifier("itemEdit.groupPicker")
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Item", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("itemEdit.deleteButton")
                    }
                }
            }
            .accessibilityIdentifier("itemEdit.form")
            .navigationTitle(isNew ? Text("New Item") : Text("Item"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Neutral, never red: only Delete is red (ID-12).
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier("itemEdit.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        commit()
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("itemEdit.doneButton")
                }
            }
            .confirmationDialog(
                Text("Delete “\(draft.name)”?"),
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Item", role: .destructive) {
                    // Close the sheet first, delete when it is gone (ID-11, DM-18).
                    isPendingDeletion = true
                    dismiss()
                }
                .accessibilityIdentifier("itemEdit.deleteAlert.confirmButton")
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        // A form sheet on iPad and the unfolded iPhone Duo, not a full-width cover (ID-10).
        .presentationSizing(.form)
        // Don't lose edits to an accidental swipe down; ✕ discards on purpose (ID-01).
        .interactiveDismissDisabled(hasChanges)
        .task {
            // After the sheet is on screen; focusing during the presentation is ignored.
            if let initialFocus { focus = initialFocus }
        }
        .onChange(of: focus) { old, _ in
            if old == .quantity { quantityText = "\(draft.quantity)" }
        }
        .onDisappear {
            if isPendingDeletion, case .edit(let item) = mode {
                isPendingDeletion = false
                store.deleteItem(item)
            }
        }
    }

    // MARK: - Rows

    /// Label and value side by side; stacked at accessibility sizes, so amounts are never cut (ID-07).
    @ViewBuilder
    private func adaptiveRow(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                value()
            }
        } else {
            LabeledContent(label) { value() }
        }
    }

    /// A number field (number pad) and a Stepper, both 1...999 (ID-05, ID-06).
    private var quantityRow: some View {
        adaptiveRow("Quantity") {
            HStack {
                TextField("Quantity", text: $quantityText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .monospacedDigit()
                    .focused($focus, equals: .quantity)
                    .onChange(of: quantityText) { _, text in
                        if let quantity = ItemDraft.quantity(from: text) {
                            draft.quantity = quantity
                        }
                    }
                    .accessibilityIdentifier("itemEdit.quantityField")
                Stepper("Quantity", value: $draft.quantity, in: PlannerStore.quantityRange)
                    .labelsHidden()
                    .fixedSize()
                    .sensoryFeedback(.selection, trigger: draft.quantity)
                    .onChange(of: draft.quantity) { _, quantity in
                        if focus != .quantity { quantityText = "\(quantity)" }
                    }
                    .accessibilityIdentifier("itemEdit.quantityStepper")
            }
        }
    }

    /// The address with Open / Remove. The preview card comes in M5 (spec 06).
    private var linkSection: some View {
        Section("Link") {
            TextField("https://…", text: $draft.urlString)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .link)
                .accessibilityLabel(Text("Link"))
                .accessibilityIdentifier("itemEdit.urlField")

            if !draft.urlString.isEmpty {
                HStack {
                    if let url = draft.linkURL {
                        Button("Open", systemImage: "safari") {
                            openURL(url)
                        }
                        .accessibilityIdentifier("itemEdit.openLinkButton")
                    }
                    Spacer()
                    Button("Remove", systemImage: "xmark.circle") {
                        draft.urlString = ""
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("itemEdit.removeLinkButton")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Commit

    private func commit() {
        switch mode {
        case .create(let group):
            let target = list?.groups?.first { $0.uuid == draft.groupID } ?? group
            store.addItem(from: draft, to: target)
        case .edit(let item):
            store.updateItem(item, with: draft)
        }
    }
}

#Preview("Edit") {
    ItemView(mode: .edit(SampleData.shared.evaList.sortedGroups[0].sortedItems[0]))
        .sampleDataEnvironment()
}

#Preview("New") {
    ItemView(mode: .create(SampleData.shared.evaList.sortedGroups[0]))
        .sampleDataEnvironment()
}
