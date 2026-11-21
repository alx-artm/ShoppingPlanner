//
//  ItemView.swift
//  Project2
//
//  Item details (spec 05, UX_REVIEW §6): name, price per unit, quantity,
//  total, link, note, group, delete. The sheet edits an `ItemDraft`, so ✕
//  discards everything and ✓ saves everything in one go (ID-01).
//  New items are added inline on the list screen (spec 04), not here.
//

import SwiftUI

struct ItemView: View {
    /// Fields that can take the keyboard focus.
    enum Field: Hashable {
        case name, price, quantity, link, note
    }

    let item: ItemModel
    /// The width class of the screen that presents the sheet. The sheet's own content is
    /// always compact (a form sheet is narrow), so it can't tell an iPad from an iPhone.
    let presentingSizeClass: UserInterfaceSizeClass?
    /// Goes up by one for each ⌘⌫ (iPad): asks "Delete …?" like the Delete Item button
    /// (AD-12, ID-11). The command reaches the presenter, not this sheet, so it is passed in.
    let deleteRequests: Int

    @Environment(PlannerStore.self) private var store
    @Environment(LinkPreviewService.self) private var linkPreviews
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
    /// - Parameter presentingSizeClass: the presenter's `horizontalSizeClass` (detents, ID-10).
    init(item: ItemModel, focusFirstEmpty: Bool = false, presentingSizeClass: UserInterfaceSizeClass? = nil,
         deleteRequests: Int = 0) {
        self.item = item
        self.presentingSizeClass = presentingSizeClass
        self.deleteRequests = deleteRequests
        let draft = ItemDraft(item: item)
        initialDraft = draft
        _draft = State(initialValue: draft)
        _quantityText = State(initialValue: "\(draft.quantity)")

        if focusFirstEmpty {
            initialFocus = if draft.price == nil { .price }
                else if draft.urlString.isEmpty { .link }
                else if draft.notes.isEmpty { .note }
                else { nil }
        } else {
            initialFocus = nil
        }
    }

    private var list: ListModel? {
        item.parentList
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

                Section {
                    Button("Delete Item", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("itemEdit.deleteButton")
                }
            }
            .accessibilityIdentifier("itemEdit.form")
            .navigationTitle(Text("Item"))
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
        .presentationDetents(Self.detents(for: presentingSizeClass))
        // A form sheet on iPad and the unfolded iPhone Duo, not a full-width cover (ID-10).
        .presentationSizing(.form)
        // Don't lose edits to an accidental swipe down; ✕ discards on purpose (ID-01).
        .interactiveDismissDisabled(hasChanges)
        .task {
            // After the sheet is on screen; focusing during the presentation is ignored.
            if let initialFocus { focus = initialFocus }
        }
        // A saved link without a preview yet: fetch it now (LP-01a, LP-01b).
        .onAppear { linkPreviews.fetchIfNeeded(for: item) }
        .onChange(of: deleteRequests) {
            showsDeleteConfirmation = true
        }
        .onChange(of: focus) { old, _ in
            if old == .quantity { quantityText = "\(draft.quantity)" }
        }
        .onDisappear {
            if isPendingDeletion {
                isPendingDeletion = false
                store.deleteItem(item)
            }
        }
    }

    /// Half height then full on iPhone (spec 05 Layout). On regular width (iPad, unfolded Duo)
    /// the form sheet is always full height: a half-height form sheet hides the Group picker
    /// and Delete below its edge, and neither dragging the grabber nor scrolling the form
    /// expands it. It also jumped to full height on its own when the docked keyboard came
    /// back after the iPad number pad popover, moving the controls away mid-tap (ID-10).
    static func detents(for sizeClass: UserInterfaceSizeClass?) -> Set<PresentationDetent> {
        sizeClass == .regular ? [.large] : [.medium, .large]
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
        store.updateItem(item, with: draft)
        // A new link has no preview: the store dropped the old one (LP-01, LP-10).
        linkPreviews.fetchIfNeeded(for: item)
    }
}

#Preview {
    ItemView(item: SampleData.shared.evaList.sortedGroups[0].sortedItems[0])
        .sampleDataEnvironment()
}
