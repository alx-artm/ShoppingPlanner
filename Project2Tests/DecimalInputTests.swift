//
//  DecimalInputTests.swift
//  Project2Tests
//
//  BUG-28 (and BUG-26 in M4): typed amounts accept both "," and "." as the
//  decimal separator, grouping follows the locale, and ambiguous text is
//  rejected instead of silently losing digits.
//

import Foundation
import Testing
@testable import Project2

@Suite("DecimalInput", .tags(.money))
struct DecimalInputTests {

    static func parse(_ text: String, _ locale: String) -> Decimal? {
        try? DecimalInput.parse(text, locale: Locale(identifier: locale))
    }

    @Test("Both separators work as decimal in any locale",
          arguments: [
            ("250,5", "ru_RU", "250.5"), ("250.5", "ru_RU", "250.5"),
            ("1 500,25", "ru_RU", "1500.25"), ("1,500.25", "en_US", "1500.25"),
            ("250,5", "en_US", "250.5"), ("12.", "en_US", "12"), (",5", "ru_RU", "0.5"),
            ("−7,5", "ru_RU", "-7.5"), ("1'234.5", "de_CH", "1234.5"), ("1’234.5", "de_CH", "1234.5"),
          ] as [(String, String, String)])
    func accepted(text: String, locale: String, expected: String) {
        #expect(Self.parse(text, locale) == dec(expected))
    }

    @Test("The locale's grouping separator with 3 digits after it groups",
          arguments: [("1,500", "en_US", "1500"), ("1.500", "de_DE", "1500"), ("1.500", "ru_RU", "1.5")]
          as [(String, String, String)])
    func grouping(text: String, locale: String, expected: String) {
        #expect(Self.parse(text, locale) == dec(expected))
    }

    @Test("Text that isn't one amount is rejected",
          arguments: ["", " ", ",", "abc", "1,2,3", "1.5.0", "12-5", "--5", "5€", "1,50.000"])
    func rejected(text: String) {
        #expect(Self.parse(text, "en_US") == nil)
    }

    @Test("Only the given symbols are ignored")
    func symbols() throws {
        let locale = Locale(identifier: "ru_RU")
        #expect(try DecimalInput.parse("1 234,50 €", locale: locale, ignoring: ["€"]) == dec("1234.5"))
        #expect(throws: DecimalInput.InvalidInput.self) {
            try DecimalInput.parse("$12", locale: locale, ignoring: ["€"])
        }
    }
}
