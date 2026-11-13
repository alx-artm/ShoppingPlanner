//
//  MoneyInputTests.swift
//  Project2Tests
//
//  BUG-26 and spec 05 ID-03/ID-03a, 04 LD-15a, 07 SC-09: a typed price.
//  The symbol is outside the text and placed by the locale; an empty field is
//  "no price"; negative or unreadable text is rejected; the currency decides
//  the number of fraction digits.
//

import Foundation
import Testing
@testable import Project2

@Suite("MoneyInput", .tags(.money, .regression))
struct MoneyInputTests {

    // MARK: - CurrencyAffix

    @Test("ID-03a the symbol and its side follow the locale; JPY has no fraction digits",
          arguments: [
            ("USD", "en_US", "$", CurrencyAffix.Position.prefix, 2),
            ("EUR", "en_US", "€", .prefix, 2),
            ("EUR", "ru_RU", "€", .suffix, 2),
            ("RUB", "ru_RU", "₽", .suffix, 2),
            ("EUR", "de_DE", "€", .suffix, 2),
            ("USD", "ru_RU", "$", .suffix, 2),
            ("JPY", "ja_JP", "¥", .prefix, 0),
            ("JPY", "en_US", "¥", .prefix, 0),
          ] as [(String, String, String, CurrencyAffix.Position, Int)])
    func affix(currency: String, locale: String, symbol: String,
               position: CurrencyAffix.Position, digits: Int) {
        let affix = CurrencyAffix(currencyCode: currency, locale: Locale(identifier: locale))
        #expect(affix.symbol == symbol)
        #expect(affix.position == position)
        #expect(affix.fractionDigits == digits)
    }

    // MARK: - Parsing

    static func parse(_ text: String, _ currency: String = "USD", _ locale: String = "en_US") -> MoneyInput.Parsed {
        MoneyInput.parse(text, currencyCode: currency, locale: Locale(identifier: locale))
    }

    @Test("BUG-26 '12.5' and '12,5' are 12.5 in en_US and ru_RU",
          arguments: ["en_US", "ru_RU"], ["12.5", "12,5"])
    func decimalSeparators(locale: String, text: String) {
        #expect(Self.parse(text, "EUR", locale) == .amount(dec("12.5")))
    }

    @Test("BUG-26 every prefix typed on the way to '12.5' keeps the digits",
          arguments: [("1", "1"), ("12", "12"), ("12.", "12"), ("12.5", "12.5"), ("12.50", "12.5")]
          as [(String, String)])
    func typingStepByStep(text: String, expected: String) {
        #expect(Self.parse(text) == .amount(dec(expected)))
    }

    @Test("ID-03 an empty field is 'no price', not 0", arguments: ["", " ", "\u{00A0}"])
    func empty(text: String) {
        #expect(Self.parse(text) == .empty)
    }

    @Test("ID-03 negative and unreadable text is rejected", arguments: ["-5", "−7,5", "abc", "1,2,3", "5 £"])
    func invalid(text: String) {
        #expect(Self.parse(text) == .invalid)
    }

    @Test("The list currency's own symbol and ISO code may be typed or pasted")
    func symbolInText() {
        #expect(Self.parse("$12.50") == .amount(dec("12.5")))
        #expect(Self.parse("12,50 €", "EUR", "ru_RU") == .amount(dec("12.5")))
        #expect(Self.parse("EUR 3", "EUR", "en_US") == .amount(3))
    }

    @Test("SC-09 the value is rounded to the currency's digits: JPY 12.5 → 13, EUR 1.005 → 1.01")
    func rounding() {
        #expect(Self.parse("12.5", "JPY") == .amount(13))
        #expect(Self.parse("12.4", "JPY") == .amount(12))
        #expect(Self.parse("1.005", "EUR") == .amount(dec("1.01")))
        #expect(Self.parse("0", "EUR") == .amount(0))
    }

    // MARK: - Text shown when not typing

    @Test("The text shown for a value parses back to the same value",
          arguments: [("12.5", "EUR", "en_US", "12.50"), ("12.5", "EUR", "ru_RU", "12,50"),
                      ("1234.5", "USD", "en_US", "1234.50"), ("1235", "JPY", "ja_JP", "1235"),
                      ("0", "USD", "en_US", "0.00")]
          as [(String, String, String, String)])
    func editingText(value: String, currency: String, locale: String, expected: String) {
        let text = MoneyInput.editingText(for: dec(value), currencyCode: currency, locale: Locale(identifier: locale))
        #expect(text == expected)
        #expect(Self.parse(text, currency, locale) == .amount(dec(value)))
    }

    @Test("No price shows an empty field")
    func editingTextNil() {
        #expect(MoneyInput.editingText(for: nil, currencyCode: "USD", locale: Locale(identifier: "en_US")) == "")
    }
}
