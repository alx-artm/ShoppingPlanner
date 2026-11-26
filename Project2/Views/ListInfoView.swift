//
//  ListInfoView.swift
//  Project2
//
//  List Info (spec 03, UX_REVIEW §13C): create or edit a list. Name, color,
//  icon (SF Symbols or emoji), budget, currency (LI-20), "Pin to Home", and Delete
//  in edit mode.
//
//  The screen edits a `ListDraft` (a value copy), so ✕ discards everything
//  (LI-02) and a new list is inserted only on ✓ (LI-01).
//

import SwiftUI

struct ListInfoView: View {
    enum Mode {
        case create(ListDraft)
        case edit(ListModel)
    }

    let mode: Mode

    @Environment(PlannerStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var draft: ListDraft
    private let initialDraft: ListDraft
    @State private var iconTab: ListIconKind
    @State private var customEmoji = ""
    @State private var showsDeleteConfirmation = false
    /// The currency picked in the picker while "Prices won't be converted" is asked (LI-21).
    @State private var pendingCurrencyCode: String?
    /// Set when the user confirmed deletion; the list is deleted after the sheet is gone (LI-10).
    @State private var isPendingDeletion = false
    @FocusState private var isNameFocused: Bool

    @ScaledMetric(relativeTo: .title3) private var cellSize: CGFloat = 44
    /// A color of the one-row palette: ~32 pt circles, so all 9 fit an iPhone form row.
    @ScaledMetric(relativeTo: .title3) private var paletteCell: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var previewDiameter: CGFloat = 72

    init(mode: Mode) {
        self.mode = mode
        let draft = switch mode {
        case .create(let draft): draft
        case .edit(let list): ListDraft(list: list)
        }
        initialDraft = draft
        _draft = State(initialValue: draft)
        _iconTab = State(initialValue: draft.iconKind)
        _customEmoji = State(initialValue: draft.iconKind == .emoji
                             && !IconCatalog.emojis.contains(draft.iconName) ? draft.iconName : "")
    }

    private var isNew: Bool {
        if case .create = mode { true } else { false }
    }

    private var isArchived: Bool {
        if case .edit(let list) = mode { list.isArchived } else { false }
    }

    var body: some View {
        NavigationStack {
            Form {
                header
                colorSection
                iconSection
                budgetSection

                // An archived list is not on Home, so it can't be pinned (spec 10).
                if !isArchived {
                    Section {
                        Toggle("Pin to Home", isOn: $draft.isPinned)
                            .accessibilityIdentifier("listEdit.pinToggle")
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete List", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("listEdit.deleteButton")
                    }
                }
            }
            .accessibilityIdentifier("listEdit.form")
            .navigationTitle(isNew ? Text("New List") : Text("List Info"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                    // ✕ stays neutral when the list screen tints the sheet (M7.5).
                    .tint(.primary)
                    .accessibilityIdentifier("listEdit.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        commit()
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("listEdit.doneButton")
                }
            }
            .confirmationDialog(
                Text("Delete “\(draft.name)”?"),
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    isPendingDeletion = true
                    dismiss()
                }
                .accessibilityIdentifier("listEdit.deleteAlert.confirmButton")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All groups and items will be deleted.")
            }
            .alert(
                Text("Prices won't be converted"),
                isPresented: Binding(
                    get: { pendingCurrencyCode != nil },
                    set: { if !$0 { pendingCurrencyCode = nil } }
                ),
                presenting: pendingCurrencyCode
            ) { code in
                Button("Change") {
                    draft.currencyCode = code
                }
                .accessibilityIdentifier("listEdit.currencyAlert.changeButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("listEdit.currencyAlert.cancelButton")
            } message: { code in
                Text("Prices and the budget keep the same numbers. Only the currency changes to \(CurrencyCatalog.displayName(of: code, locale: locale)).")
            }
        }
        // Don't lose edits to an accidental swipe down.
        .interactiveDismissDisabled(draft != initialDraft)
        .onAppear {
            if isNew && draft.name.isEmpty { isNameFocused = true }
        }
        .onDisappear {
            // DM-18: the sheet is gone; if the list is open in the detail, that closes first.
            if isPendingDeletion, case .edit(let list) = mode {
                isPendingDeletion = false
                navigation.requestDeletion(of: list, using: store)
            }
        }
    }

    // MARK: - Sections

    /// Icon preview and the name field.
    private var header: some View {
        Section {
            VStack(spacing: 16) {
                ListIconBadge(iconName: draft.iconName, iconKind: draft.iconKind,
                              color: draft.color, diameter: previewDiameter)
                    .shadow(color: draft.color.color.opacity(0.35), radius: 8, y: 4)

                TextField("List Name", text: $draft.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("listEdit.nameField")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    /// The 9 colors in one row; 5 + 4 centered when one row doesn't fit; the wrapping grid
    /// at large text sizes (LI-04, LI-14, M7.5: no more 7 + 2).
    private var colorSection: some View {
        let colors = FavoriteColor.allCases
        return Section("Color") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Self.paletteSpacing) {
                    ForEach(colors, id: \.self) { colorCell($0, side: paletteCell) }
                }
                VStack(spacing: Self.paletteSpacing) {
                    HStack(spacing: Self.paletteSpacing) {
                        ForEach(colors.prefix(5), id: \.self) { colorCell($0, side: cellSize) }
                    }
                    HStack(spacing: Self.paletteSpacing) {
                        ForEach(colors.dropFirst(5), id: \.self) { colorCell($0, side: cellSize) }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 4)], spacing: 4) {
                    ForEach(colors, id: \.self) { colorCell($0, side: cellSize) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    /// Between the circles of the one-row and 5 + 4 palettes.
    private static let paletteSpacing: CGFloat = 2

    private func colorCell(_ color: FavoriteColor, side: CGFloat) -> some View {
        let isSelected = draft.color == color
        // The ring and the gap scale with the cell, so a small one-row cell keeps its circle.
        let inset = side * (isSelected ? 0.18 : 0.12)
        return Button {
            draft.color = color
        } label: {
            Circle()
                .fill(color.color.gradient)
                .padding(inset)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(color.color, lineWidth: 3)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(color.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("listEdit.color.\(color.rawValue)")
    }

    /// "Symbols | Emoji" (LI-05, LI-06). Emoji come from the grid or from a
    /// normal TextField: the system keyboard's emoji layout is one tap away on
    /// the globe key, so no private keyboard type is needed (LI-07, BUG-10).
    private var iconSection: some View {
        Section {
            Picker("Icon", selection: $iconTab) {
                Text("Symbols").tag(ListIconKind.symbol)
                Text("Emoji").tag(ListIconKind.emoji)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("listEdit.iconTabs")

            switch iconTab {
            case .symbol:
                iconGrid(IconCatalog.symbols, kind: .symbol)
            case .emoji:
                iconGrid(IconCatalog.emojis, kind: .emoji)
                customEmojiField
            }
        } header: {
            Text("Icon")
        }
    }

    private func iconGrid(_ icons: [String], kind: ListIconKind) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 4)], spacing: 4) {
            ForEach(icons, id: \.self) { icon in
                let isSelected = draft.iconKind == kind && draft.iconName == icon
                Button {
                    draft.iconName = icon
                    draft.iconKind = kind
                    if kind == .emoji { customEmoji = "" }
                } label: {
                    Group {
                        switch kind {
                        case .symbol:
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        case .emoji:
                            Text(verbatim: icon)
                                .font(.title2)
                        }
                    }
                    .frame(width: cellSize, height: cellSize)
                    .background {
                        Circle().fill(isSelected
                                      ? AnyShapeStyle(draft.color.color.gradient)
                                      : AnyShapeStyle(Color(.tertiarySystemFill)))
                    }
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("listEdit.\(kind.rawValue).\(icon)")
            }
        }
        .padding(.vertical, 4)
    }

    /// "Other…": accepted only if it is exactly one emoji (LI-06).
    private var customEmojiField: some View {
        let isInvalid = !customEmoji.isEmpty && !IconCatalog.isSingleEmoji(customEmoji)
        return VStack(alignment: .leading, spacing: 4) {
            TextField("Other…", text: $customEmoji)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isInvalid ? AnyShapeStyle(.red) : AnyShapeStyle(.quaternary), lineWidth: 1)
                }
                .onChange(of: customEmoji) { _, text in
                    if IconCatalog.isSingleEmoji(text) {
                        draft.iconName = text
                        draft.iconKind = .emoji
                    }
                }
                .accessibilityIdentifier("listEdit.customEmojiField")
            if isInvalid {
                Text("Enter a single emoji.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Optional budget in the list currency (LI-08), and the currency itself (LI-20).
    private var budgetSection: some View {
        Section {
            LabeledContent("Budget") {
                // Accepts "," and "." as the decimal separator in any locale (BUG-28).
                TextField("None", value: $draft.budget,
                          format: MoneyInputFormat(currencyCode: draft.currencyCode, locale: locale))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("listEdit.budgetField")
            }
            // The same picker as Settings (spec 07); picking relabels the list, no conversion.
            NavigationLink {
                CurrencyPickerView(selection: currencySelection, title: "Currency")
            } label: {
                LabeledContent("Currency") {
                    Text(verbatim: CurrencyCatalog.rowTitle(of: draft.currencyCode, locale: locale))
                }
            }
            .accessibilityIdentifier("listEdit.currency")
        } footer: {
            if draft.hasValidBudget {
                Text("Leave empty for no budget.")
            } else {
                Text("The budget can't be negative.")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Currency (LI-20, LI-21)

    /// The picker's selection: an empty or unpriced list without a budget takes the new code
    /// at once; otherwise the code waits for "Prices won't be converted" → Change.
    private var currencySelection: Binding<String> {
        Binding {
            draft.currencyCode
        } set: { code in
            guard code != draft.currencyCode else { return }
            if ListCurrencyChange.needsConfirmation(hasPricedItems: hasPricedItems, budget: draft.budget) {
                pendingCurrencyCode = code
            } else {
                draft.currencyCode = code
            }
        }
    }

    /// Items with a price in the saved list; a new list has no items yet.
    private var hasPricedItems: Bool {
        if case .edit(let list) = mode { list.hasPricedItems } else { false }
    }

    // MARK: - Commit

    private func commit() {
        switch mode {
        case .create:
            store.createList(from: draft)
        case .edit(let list):
            store.updateList(list, with: draft)
        }
    }
}

#Preview("New") {
    ListInfoView(mode: .create(ListDraft(currencyCode: "EUR")))
        .sampleDataEnvironment()
}

#Preview("Edit") {
    ListInfoView(mode: .edit(SampleData.shared.evaList))
        .sampleDataEnvironment()
}
