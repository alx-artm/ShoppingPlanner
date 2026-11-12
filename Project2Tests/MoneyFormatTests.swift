//
//  MoneyFormatTests.swift
//  Project2Tests
//
//  Spec 07 SC-08 / SC-09: every amount is formatted by `MoneyFormat`, with the
//  separators and symbol position of the locale and the fraction digits of the
//  currency. Locales are always passed explicitly, so the results don't depend
//  on the machine (simulator region, CI runner); amounts are built from strings.
//

import Foundation
import Testing
@testable import Project2

@Suite("MoneyFormat", .tags(.money, .settings))
struct MoneyFormatTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let amount: String
        let currency: String
        let locale: String
        /// Written with plain spaces; see `String.plainSpaces`.
        let expected: String

        var testDescription: String { "\(amount) \(currency) in \(locale) → \(expected)" }
    }

    // MARK: - Locale decides separators and symbol position (SC-08)

    static let localeCases: [Case] = [
        // The two examples written in SC-08.
        Case(amount: "1234.5", currency: "EUR", locale: "en_US", expected: "€1,234.50"),
        Case(amount: "1234.5", currency: "EUR", locale: "ru_RU", expected: "1 234,50 €"),
        Case(amount: "1234.5", currency: "EUR", locale: "de_DE", expected: "1.234,50 €"),
        Case(amount: "1234.5", currency: "USD", locale: "en_US", expected: "$1,234.50"),
        Case(amount: "1234.5", currency: "USD", locale: "ru_RU", expected: "1 234,50 $"),
        Case(amount: "1234.5", currency: "USD", locale: "de_DE", expected: "1.234,50 $"),
        Case(amount: "1234.5", currency: "GBP", locale: "en_GB", expected: "£1,234.50"),
    ]

    @Test("SC-08 separators and symbol position follow the locale", arguments: localeCases)
    func localeFormatting(_ c: Case) {
        let text = MoneyFormat.string(dec(c.amount), currencyCode: c.currency, locale: Locale(identifier: c.locale))
        #expect(text.plainSpaces == c.expected)
    }

    @Test("SC-08 ru_RU uses no-break spaces, so an amount never wraps onto two lines")
    func ruUsesNoBreakSpaces() {
        let text = MoneyFormat.string(dec("1234.5"), currencyCode: "EUR", locale: Locale(identifier: "ru_RU"))
        #expect(!text.contains(" "), "plain U+0020 space found in \(text.debugDescription)")
        #expect(text.plainSpaces == "1 234,50 €")
    }

    // MARK: - Currency decides fraction digits (SC-09)

    static let fractionCases: [Case] = [
        Case(amount: "1234.5", currency: "USD", locale: "en_US", expected: "$1,234.50"),
        Case(amount: "1234.5", currency: "EUR", locale: "en_US", expected: "€1,234.50"),
        Case(amount: "1234", currency: "JPY", locale: "en_US", expected: "¥1,234"),
        Case(amount: "1234", currency: "JPY", locale: "ru_RU", expected: "1 234 ¥"),
        Case(amount: "1234", currency: "JPY", locale: "ja_JP", expected: "¥1,234"),
        // Three fraction digits exist too (Kuwaiti dinar).
        Case(amount: "1234.5", currency: "KWD", locale: "en_US", expected: "KWD 1,234.500"),
    ]

    @Test("SC-09 fraction digits follow the currency (JPY 0, USD/EUR 2, KWD 3)", arguments: fractionCases)
    func fractionDigits(_ c: Case) {
        let text = MoneyFormat.string(dec(c.amount), currencyCode: c.currency, locale: Locale(identifier: c.locale))
        #expect(text.plainSpaces == c.expected)
    }

    /// Display-time rounding is half-up, away from zero: a tie goes to the larger
    /// absolute value ("¥2.5 → ¥3"), like people round by hand (owner decision
    /// after the M2 review; ICU's default half-even would give "¥2").
    @Test("SC-09 rounding at display time is half-up (away from zero)", arguments: [
        ("2.5", "JPY", "¥3"),
        ("3.5", "JPY", "¥4"),
        ("2.4", "JPY", "¥2"),
        ("1234.5", "JPY", "¥1,235"),
        ("0.005", "USD", "$0.01"),
        ("0.015", "USD", "$0.02"),
        ("0.0149", "USD", "$0.01"),
        ("-2.5", "JPY", "-¥3"),
    ])
    func halfUpRounding(amount: String, currency: String, expected: String) {
        let text = MoneyFormat.string(dec(amount), currencyCode: currency, locale: Locale(identifier: "en_US"))
        #expect(text == expected)
    }

    // MARK: - Sign, zero, large values

    static let edgeCases: [Case] = [
        Case(amount: "-12.3", currency: "USD", locale: "en_US", expected: "-$12.30"),
        Case(amount: "-12.3", currency: "EUR", locale: "ru_RU", expected: "-12,30 €"),
        Case(amount: "-12.3", currency: "EUR", locale: "de_DE", expected: "-12,30 €"),
        Case(amount: "0", currency: "USD", locale: "en_US", expected: "$0.00"),
        Case(amount: "0", currency: "JPY", locale: "en_US", expected: "¥0"),
        Case(amount: "0", currency: "EUR", locale: "ru_RU", expected: "0,00 €"),
        Case(amount: "1234567890123.45", currency: "USD", locale: "en_US", expected: "$1,234,567,890,123.45"),
        // 19 significant digits: more than a Double can hold exactly.
        Case(amount: "99999999999999999.99", currency: "EUR", locale: "de_DE",
             expected: "99.999.999.999.999.999,99 €"),
    ]

    @Test("SC-08 negative, zero and large amounts", arguments: edgeCases)
    func edges(_ c: Case) {
        let text = MoneyFormat.string(dec(c.amount), currencyCode: c.currency, locale: Locale(identifier: c.locale))
        #expect(text.plainSpaces == c.expected)
    }

    // MARK: - Decimal exactness

    @Test("Decimal math is exact: 0.1 + 0.2 shows as 0.30, and 0.1 × 3 == 0.3")
    func decimalExactness() {
        let sum = dec("0.1") + dec("0.2")
        #expect(sum == dec("0.3"))
        #expect(dec("0.1") * 3 == dec("0.3"))
        #expect(MoneyFormat.string(sum, currencyCode: "USD", locale: Locale(identifier: "en_US")) == "$0.30")
    }

    @Test("Many small prices add up without drift (1000 × 0.01 = 10.00)")
    func noDrift() {
        let total = (0..<1000).reduce(Decimal.zero) { acc, _ in acc + dec("0.01") }
        #expect(total == dec("10"))
        #expect(MoneyFormat.string(total, currencyCode: "EUR", locale: Locale(identifier: "en_US")) == "€10.00")
    }

    // MARK: - API contract

    @Test("SC-08 string(_:) and style(_:) produce the same text")
    func stringMatchesStyle() {
        let locale = Locale(identifier: "de_DE")
        let amount = dec("98765.4321")
        #expect(MoneyFormat.string(amount, currencyCode: "EUR", locale: locale)
                == amount.formatted(MoneyFormat.style(currencyCode: "EUR", locale: locale)))
    }

    @Test("SC-08 the locale never changes the currency: EUR stays € in en_US, $ stays $ in de_DE")
    func localeDoesNotPickCurrency() {
        #expect(MoneyFormat.string(dec("1"), currencyCode: "EUR", locale: Locale(identifier: "en_US")).contains("€"))
        let usdInGermany = MoneyFormat.string(dec("1"), currencyCode: "USD", locale: Locale(identifier: "de_DE"))
        #expect(usdInGermany.contains("$"))
        #expect(!usdInGermany.contains("€"))
    }
}
