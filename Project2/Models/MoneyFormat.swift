//
//  MoneyFormat.swift
//  Project2
//
//  The single way to turn an amount into text (spec 07 SC-08/SC-09, 09 L10N-05).
//
//  Every amount on screen goes through here, so all of them look the same:
//  currency symbol, grouping and decimal separators of the locale, and the
//  number of fraction digits of the currency (JPY 0, EUR 2). Rounding happens
//  only here, at display time; `BudgetCalculator` never rounds (DM-25).
//
//  Ties round half-up, away from zero ("¥2.5 → ¥3"), like people round by hand.
//  ICU's default would be half-even ("banker's rounding", ¥2.5 → ¥2), which
//  looks like a bug in a shopping app (owner decision after the M2 review).
//

import Foundation

enum MoneyFormat {
    /// Format style for amounts in `currencyCode`.
    ///
    /// - Parameter locale: decides separators and symbol placement, not the currency.
    ///   Views pass `@Environment(\.locale)`; tests pass a fixed locale.
    static func style(currencyCode: String, locale: Locale = .autoupdatingCurrent) -> Decimal.FormatStyle.Currency {
        Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
            .rounded(rule: .toNearestOrAwayFromZero)
    }

    /// `1234.5` + `"EUR"` → `"€1,234.50"` in en_US, `"1 234,50 €"` in ru_RU.
    static func string(_ amount: Decimal, currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(style(currencyCode: currencyCode, locale: locale))
    }
}
