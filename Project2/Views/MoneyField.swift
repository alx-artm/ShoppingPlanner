//
//  MoneyField.swift
//  Project2
//
//  A price field (BUG-26, spec 05 ID-03/ID-03a, 04 LD-15a): the text the user
//  types stays as typed, the currency symbol sits outside the editable text,
//  and the bound value follows every valid change (live totals). The rules
//  live in `MoneyInput`; this view only wires them to a `TextField`.
//

import SwiftUI

struct MoneyField<Field: Hashable>: View {
    private let title: LocalizedStringKey
    @Binding private var value: Decimal?
    private let currencyCode: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let identifier: String
    private let alignment: TextAlignment

    @Environment(\.locale) private var locale
    @State private var text = ""

    /// - Parameters:
    ///   - title: the VoiceOver label and the placeholder.
    ///   - value: `nil` = no price. Updated on every valid change; invalid text keeps the last value.
    ///   - focus: the screen's focus state; the text is tidied up when this field loses focus.
    ///   - identifier: accessibility identifier of the text field (UI tests).
    init(_ title: LocalizedStringKey, value: Binding<Decimal?>, currencyCode: String,
         focus: FocusState<Field?>.Binding, field: Field, identifier: String,
         alignment: TextAlignment = .leading) {
        self.title = title
        _value = value
        self.currencyCode = currencyCode
        self.focus = focus
        self.field = field
        self.identifier = identifier
        self.alignment = alignment
    }

    var body: some View {
        let affix = CurrencyAffix(currencyCode: currencyCode, locale: locale)
        // Right-aligned (item details): the field hugs its text and is pushed right together
        // with the symbol, so "$" stays next to the digits, not by the label (BUG-30, ID-03a).
        let hugsText = alignment == .trailing
        HStack(spacing: 4) {
            if hugsText { Spacer(minLength: 0) }
            if affix.position == .prefix { symbol(affix) }
            TextField(title, text: $text)
                .keyboardType(affix.fractionDigits == 0 ? .numberPad : .decimalPad)
                .multilineTextAlignment(alignment)
                .monospacedDigit()
                .fixedSize(horizontal: hugsText, vertical: false)
                // An empty field still has a comfortable tap target.
                .frame(minWidth: hugsText ? 44 : nil, alignment: .trailing)
                .focused(focus, equals: field)
                .accessibilityIdentifier(identifier)
            if affix.position == .suffix { symbol(affix) }
        }
        .onAppear { text = editingText }
        .onChange(of: text) { _, newText in
            switch MoneyInput.parse(newText, currencyCode: currencyCode, locale: locale) {
            case .empty: value = nil
            case .amount(let amount): if value != amount { value = amount }
            case .invalid: break
            }
        }
        .onChange(of: focus.wrappedValue) { old, new in
            // Typing is over: show the value the way it was understood ("12,5" → "12,50").
            if old == field, new != field { text = editingText }
        }
        .onChange(of: value) {
            // Changed from outside (another field, a reset): follow it unless the user is typing here.
            if focus.wrappedValue != field { text = editingText }
        }
    }

    private var editingText: String {
        MoneyInput.editingText(for: value, currencyCode: currencyCode, locale: locale)
    }

    private func symbol(_ affix: CurrencyAffix) -> some View {
        Text(verbatim: affix.symbol)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            .accessibilityIdentifier("\(identifier).symbol")
    }
}

#Preview {
    @Previewable @State var price: Decimal? = 12.5
    @Previewable @FocusState var focus: Int?
    Form {
        MoneyField("Price", value: $price, currencyCode: "EUR", focus: $focus, field: 0, identifier: "price")
        MoneyField("Price", value: $price, currencyCode: "EUR", focus: $focus, field: 1, identifier: "price.ru")
            .environment(\.locale, Locale(identifier: "ru_RU"))
        Text(verbatim: "\(price.map { "\($0)" } ?? "nil")")
    }
}
