//
//  CurrencyPickerView.swift
//  Project2
//
//  Currency picker (spec 07 "Currency picker", SC-03, SC-04): the main currency in
//  Settings and a list's currency in List Info (spec 03, LI-20).
//  Which codes go into which section, and the search, live in `CurrencyCatalog`.
//

import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selection: String
    /// "Main Currency" in Settings, "Currency" in List Info.
    var title: LocalizedStringKey = "Main Currency"

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isSearching = false

    var body: some View {
        let sections = CurrencyCatalog.sections(locale: locale, query: query)

        List {
            section("Suggested", codes: sections.suggested)
            section("Popular", codes: sections.popular)
            section("All Currencies", codes: sections.all)
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        // Always visible: search is the main way to reach the ~150 other currencies.
        .searchable(
            text: $query,
            isPresented: $isSearching,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Code, name or symbol")
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("currencyPicker.list")
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, codes: [String]) -> some View {
        if !codes.isEmpty {
            Section(title) {
                ForEach(codes, id: \.self) { code in
                    row(code)
                }
            }
        }
    }

    private func row(_ code: String) -> some View {
        let isSelected = code == selection
        return Button {
            selection = code
            // End the search first: an active search field otherwise stays on screen, with
            // its keyboard, over the view the picker returns to (List Info sheet, LI-20).
            isSearching = false
            dismiss()
        } label: {
            HStack {
                Text(verbatim: CurrencyCatalog.rowTitle(of: code, locale: locale))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("currencyPicker.row.\(code)")
    }
}

#Preview {
    @Previewable @State var code = "EUR"
    NavigationStack {
        CurrencyPickerView(selection: $code)
    }
}
