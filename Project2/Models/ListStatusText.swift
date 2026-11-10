//
//  ListStatusText.swift
//  Project2
//
//  The texts Home shows for a list (spec 02): the status line under the name,
//  the "—" rule for lists without prices (HM-06), the over-budget text (HM-07)
//  and the VoiceOver label of a tile or row (HM-16). Pure functions of a
//  `BudgetSummary`, so they are unit-testable without views.
//

import Foundation

enum ListStatusText {
    /// At least one item has a price. Without one, Home shows "—" instead of "0" (HM-06).
    static func hasPrices(_ summary: BudgetSummary) -> Bool {
        summary.itemCount - summary.unpricedCount > 0
    }

    /// Second line of a row: "Empty", "3 items", "$160.00 left of $500.00",
    /// "Over budget by €15.00" or "8% bought".
    static func subtitle(_ summary: BudgetSummary, currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard summary.itemCount > 0 else { return String(localized: "Empty") }
        guard hasPrices(summary) else { return itemCount(summary.itemCount) }

        if let budget = summary.budget, let left = summary.budgetLeft {
            if summary.isOverBudget {
                let over = MoneyFormat.string(-left, currencyCode: currencyCode, locale: locale)
                return String(localized: "Over budget by \(over)")
            }
            let leftText = MoneyFormat.string(left, currencyCode: currencyCode, locale: locale)
            let budgetText = MoneyFormat.string(budget, currencyCode: currencyCode, locale: locale)
            return String(localized: "\(leftText) left of \(budgetText)")
        }
        return boughtPercent(summary, locale: locale)
    }

    /// "8% bought".
    static func boughtPercent(_ summary: BudgetSummary, locale: Locale = .autoupdatingCurrent) -> String {
        let percent = summary.boughtFraction.formatted(
            .percent.precision(.fractionLength(0)).rounded(rule: .down).locale(locale)
        )
        return String(localized: "\(percent) bought")
    }

    /// "1 item", "3 items" (plural rules come from the String Catalog).
    static func itemCount(_ count: Int) -> String {
        String(localized: "\(count) items")
    }

    /// One VoiceOver sentence for a tile or row (HM-16):
    /// "Alex, to buy $340.00, 8% bought, $130.00 left of $500.00".
    static func accessibilityLabel(name: String, summary: BudgetSummary, currencyCode: String,
                                   locale: Locale = .autoupdatingCurrent) -> String {
        var parts = [name]
        if hasPrices(summary) {
            let toBuy = MoneyFormat.string(summary.toBuy, currencyCode: currencyCode, locale: locale)
            parts.append(String(localized: "to buy \(toBuy)"))
            parts.append(boughtPercent(summary, locale: locale))
            if summary.budget != nil {
                parts.append(subtitle(summary, currencyCode: currencyCode, locale: locale))
            }
        } else {
            parts.append(subtitle(summary, currencyCode: currencyCode, locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}
