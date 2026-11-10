//
//  ListStatusTextTests.swift
//  Project2Tests
//
//  Spec 02: the status line of a Home row (HM-05...HM-07), the "—" rule for
//  lists without prices (HM-06) and the VoiceOver sentence (HM-16).
//  Amounts are built from strings and formatted with an explicit Locale, so
//  results don't depend on the simulator's region.
//

import Foundation
import Testing
@testable import Project2

@Suite("ListStatusText", .tags(.home, .money))
struct ListStatusTextTests {

    static let enUS = Locale(identifier: "en_US")
    static let ruRU = Locale(identifier: "ru_RU")

    /// "price×qty", "price×qty✓" (completed) or "-" (no price).
    static func summary(_ lines: [String], budget: String? = nil, currency: String = "USD") -> BudgetSummary {
        let parsed = lines.map { spec -> BudgetLine in
            guard spec != "-" else { return BudgetLine(price: nil) }
            let done = spec.hasSuffix("✓")
            let parts = spec.replacingOccurrences(of: "✓", with: "").split(separator: "×")
            return BudgetLine(price: dec(String(parts[0])),
                              quantity: parts.count > 1 ? Int(parts[1])! : 1,
                              isComplete: done)
        }
        return BudgetCalculator.summary(of: parsed, listCurrencyCode: currency, budget: budget.map(dec))
    }

    /// The seed list "Alex": 60 + 55 + 30✓ + 30 + 55×2 + 85 = 370 planned, 30 bought.
    static let alexLines = ["60", "55", "30✓", "30", "55×2", "85"]

    // MARK: - HM-06 no prices

    @Test("HM-06 hasPrices is false without any priced item (Home shows '—', not '0')",
          arguments: [
            ([], false), (["-"], false), (["-", "-"], false),
            (["-", "10"], true), (["0"], true), (["10✓"], true),
          ] as [([String], Bool)])
    func hasPrices(lines: [String], expected: Bool) {
        #expect(ListStatusText.hasPrices(Self.summary(lines)) == expected)
    }

    @Test("Documented: an item priced in a foreign currency without a rate counts as 'has prices'")
    func foreignWithoutRate() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("10"), currencyCode: "EUR")], listCurrencyCode: "USD")
        #expect(ListStatusText.hasPrices(summary))
        #expect(summary.toBuy == 0, "excluded from sums (DM-22), so the tile shows $0.00, not '—'")
    }

    // MARK: - Row subtitle

    struct Case: CustomTestStringConvertible, Sendable {
        let lines: [String]
        var budget: String?
        var currency = "USD"
        let expected: String
        var testDescription: String { expected }
    }

    static let englishCases: [Case] = [
        // HM-06: no items / no prices.
        Case(lines: [], expected: "Empty"),
        Case(lines: ["-"], expected: "1 item"),
        Case(lines: ["-", "-", "-"], expected: "3 items"),
        Case(lines: ["-", "-"], budget: "500", expected: "2 items"),
        // No budget: the bought share, rounded down.
        Case(lines: ["60", "55"], expected: "0% bought"),
        Case(lines: alexLines, expected: "8% bought"),        // 30 / 370 = 8.1 %
        Case(lines: ["999✓", "1"], expected: "99% bought"),     // 99.9 % is not "100 %"
        Case(lines: ["10✓", "5✓"], expected: "100% bought"),
        Case(lines: ["0", "0"], expected: "0% bought"),         // planned 0: no division by zero
        // Budget: "X left of Y".
        Case(lines: alexLines, budget: "500", expected: "$130.00 left of $500.00"),
        Case(lines: ["370"], budget: "370", expected: "$0.00 left of $370.00"), // exactly on budget
        // HM-07 over budget, in the list currency.
        Case(lines: ["60", "55", "30", "30", "55", "85"], budget: "300", currency: "EUR",
             expected: "Over budget by €15.00"),
        // LI-08: budget 0 means any planned amount is over budget.
        Case(lines: ["0.01"], budget: "0", expected: "Over budget by $0.01"),
        Case(lines: ["1234.5"], budget: "0", currency: "JPY", expected: "Over budget by ¥1,235"),
    ]

    @Test("HM-05/06/07 row subtitle in en_US", .englishUI, arguments: englishCases)
    func subtitle(_ c: Case) {
        let text = ListStatusText.subtitle(Self.summary(c.lines, budget: c.budget, currency: c.currency),
                                           currencyCode: c.currency, locale: Self.enUS)
        #expect(text == c.expected)
    }

    @Test("Amounts in the subtitle follow the injected locale, not the device region")
    func subtitleLocale() {
        let summary = Self.summary(Self.alexLines, budget: "500", currency: "EUR")
        let ru = ListStatusText.subtitle(summary, currencyCode: "EUR", locale: Self.ruRU).plainSpaces
        #expect(ru.contains("130,00 €"))
        #expect(ru.contains("500,00 €"))

        let en = ListStatusText.subtitle(summary, currencyCode: "EUR", locale: Self.enUS)
        #expect(en.contains("€130.00"))
        #expect(en.contains("€500.00"))
    }

    @Test("HM-07 the over-budget amount is positive (no minus sign)")
    func overBudgetIsPositive() {
        let summary = Self.summary(["315"], budget: "300", currency: "EUR")
        let text = ListStatusText.subtitle(summary, currencyCode: "EUR", locale: Self.enUS)
        #expect(text.contains("€15.00"))
        #expect(!text.contains("-"))
        #expect(!text.contains("−"))
    }

    @Test("boughtPercent uses the locale's percent format", .englishUI,
          arguments: [("en_US", "8% bought"), ("ru_RU", "8 % bought"), ("de_DE", "8 % bought")])
    func percentLocale(locale: String, expected: String) {
        let text = ListStatusText.boughtPercent(Self.summary(Self.alexLines), locale: Locale(identifier: locale))
        #expect(text.plainSpaces == expected)
    }

    // MARK: - HM-16 VoiceOver

    static let labelCases: [(String, Case)] = [
        ("Alex", Case(lines: alexLines, budget: "500",
                      expected: "Alex, to buy $340.00, 8% bought, $130.00 left of $500.00")),
        ("Eva", Case(lines: ["30", "25", "40", "20×2", "45", "-"],
                     expected: "Eva, to buy $180.00, 0% bought")),
        ("Victoria", Case(lines: ["315"], budget: "300", currency: "EUR",
                          expected: "Victoria, to buy €315.00, 0% bought, Over budget by €15.00")),
        ("New", Case(lines: [], expected: "New, Empty")),
        ("Ideas", Case(lines: ["-", "-"], budget: "100", expected: "Ideas, 2 items")),
    ]

    @Test("HM-16 one VoiceOver sentence per tile/row", .englishUI, arguments: labelCases)
    func accessibilityLabel(name: String, c: Case) {
        let label = ListStatusText.accessibilityLabel(
            name: name, summary: Self.summary(c.lines, budget: c.budget, currency: c.currency),
            currencyCode: c.currency, locale: Self.enUS)
        #expect(label == c.expected)
    }

    @Test("HM-07 the VoiceOver label says 'over budget' in words, in any UI language")
    func overBudgetInLabel() {
        let summary = Self.summary(["315"], budget: "300", currency: "EUR")
        let label = ListStatusText.accessibilityLabel(name: "V", summary: summary, currencyCode: "EUR",
                                                      locale: Self.enUS)
        #expect(label.contains(ListStatusText.subtitle(summary, currencyCode: "EUR", locale: Self.enUS)))
        #expect(label.contains("€15.00"))
    }
}
