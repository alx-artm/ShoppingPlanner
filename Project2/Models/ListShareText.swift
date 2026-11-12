//
//  ListShareText.swift
//  Project2
//
//  "Share as text" (spec 02 HM-12): the list as plain text for the share
//  sheet. Groups and items in display order, "☐/☑ name — qty × price = total",
//  then the totals. All sums are in the list currency.
//
//      Alex
//
//      Vacation
//      ☐ Sunglasses — 1 × $60.00 = $60.00
//      ☑ Flip-flops — 1 × $30.00 = $30.00
//
//      To buy: $340.00
//      Planned: $370.00
//

import Foundation

enum ListShareText {
    static func make(for list: ListModel, locale: Locale = .autoupdatingCurrent) -> String {
        let currency = list.currencyCode
        func money(_ amount: Decimal, _ code: String = currency) -> String {
            MoneyFormat.string(amount, currencyCode: code, locale: locale)
        }

        var lines = [list.name]
        for group in list.sortedGroups {
            lines.append("")
            lines.append(group.name)
            for item in group.sortedItems {
                lines.append(itemLine(item, money: money))
            }
        }

        let summary = list.summary
        lines.append("")
        lines.append(String(localized: "To buy: \(money(summary.toBuy))"))
        lines.append(String(localized: "Planned: \(money(summary.planned))"))
        if let budget = summary.budget {
            lines.append(String(localized: "Budget: \(money(budget))"))
        }
        return lines.joined(separator: "\n")
    }

    /// "☐ BBQ food — 2 × $55.00 = $110.00"; without a price: "☐ Jacket — 1".
    private static func itemLine(_ item: ItemModel, money: (Decimal, String) -> String) -> String {
        let box = item.isComplete ? "☑" : "☐"
        var line = "\(box) \(item.name) — \(item.quantity)"
        if let price = item.price {
            let priceCode = item.currencyCode ?? item.listCurrencyCode
            line += " × \(money(price, priceCode))"
            // A foreign price without a rate has no total in the list currency.
            line += " = " + (item.lineTotal.map { money($0, item.listCurrencyCode) } ?? "—")
        }
        return line
    }
}
