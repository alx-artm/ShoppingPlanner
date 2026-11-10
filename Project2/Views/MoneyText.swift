//
//  MoneyText.swift
//  Project2
//
//  SwiftUI wrapper around `MoneyFormat`: use it for every amount on screen.
//

import SwiftUI

/// An amount formatted with `MoneyFormat`, with monospaced digits so columns
/// of prices line up and totals don't jump while they change (SC-08).
struct MoneyText: View {
    let amount: Decimal
    let currencyCode: String

    /// The view's locale (not `Locale.current`), so previews and tests can override it.
    @Environment(\.locale) private var locale

    init(_ amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    var body: some View {
        Text(amount, format: MoneyFormat.style(currencyCode: currencyCode, locale: locale))
            .monospacedDigit()
    }
}

#Preview {
    VStack(alignment: .trailing) {
        MoneyText(1234.5, currencyCode: "EUR")
        MoneyText(1234.5, currencyCode: "JPY")
        MoneyText(1234.5, currencyCode: "EUR")
            .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}
