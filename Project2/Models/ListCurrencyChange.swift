//
//  ListCurrencyChange.swift
//  Project2
//
//  Changing a list's currency in List Info (spec 03, LI-20...LI-22). It is a relabel,
//  not a conversion: prices, the budget and the totals keep their numbers and only
//  `ListModel.currencyCode` changes. A list with numbers in it asks first (LI-21).
//

import Foundation

enum ListCurrencyChange {
    /// LI-21: "Prices won't be converted" is asked when there is a number that would be
    /// relabeled: at least one priced item, or a budget (0 is a real budget, LI-08).
    /// An empty or unpriced list without a budget changes at once.
    static func needsConfirmation(hasPricedItems: Bool, budget: Decimal?) -> Bool {
        hasPricedItems || budget != nil
    }

    /// The code to store: an active ISO 4217 code, upper-cased; `nil` for anything else,
    /// so a bad value never replaces the list's currency.
    static func validCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return CurrencyCatalog.isActive(code) ? code : nil
    }
}

extension ListModel {
    /// At least one item has a price (0 counts: it is a number the user typed).
    var hasPricedItems: Bool {
        allItems.contains { $0.price != nil }
    }
}
