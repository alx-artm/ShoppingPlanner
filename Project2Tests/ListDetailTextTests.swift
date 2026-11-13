//
//  ListDetailTextTests.swift
//  Project2Tests
//
//  Spec 04 texts of the list screen: the item row's second line and amount
//  (LD-06...LD-08), the group header amount (LD-04) and the summary bar
//  (LD-10, LD-11, LD-11a, compact form while typing).
//

import Foundation
import Testing
@testable import Project2

@Suite("List detail texts", .tags(.money))
struct ListDetailTextTests {

    static let enUS = Locale(identifier: "en_US")
    static let ruRU = Locale(identifier: "ru_RU")

    // MARK: - Item row

    @Test("Row detail: 'qty × unit price' only when qty > 1 and priced; then the first note line",
          arguments: [
            (1, "55", "", nil),
            (2, "55", "", "2 × $55.00"),
            (2, nil, "", nil),
            (1, "55", "grey, 2 m", "grey, 2 m"),
            (3, "10", "\n  first  \nsecond", "3 × $10.00 · first"),
            (1, nil, "   \n ", nil),
          ] as [(Int, String?, String, String?)])
    func rowDetail(quantity: Int, price: String?, notes: String, expected: String?) {
        let text = ItemRowText.detail(quantity: quantity, price: price.map(dec), currencyCode: "USD",
                                      notes: notes, locale: Self.enUS)
        #expect(text == expected)
    }

    @Test("Row detail follows the locale")
    func rowDetailRussian() {
        let text = ItemRowText.detail(quantity: 2, price: dec("1234.5"), currencyCode: "EUR", notes: "",
                                      locale: Self.ruRU)
        #expect(text?.plainSpaces == "2 × 1 234,50 €")
    }

    @Test("LD-08 the row amount is '—' without a price, never 0")
    func rowTotal() {
        #expect(ItemRowText.total(nil, currencyCode: "USD", locale: Self.enUS) == "—")
        #expect(ItemRowText.total(0, currencyCode: "USD", locale: Self.enUS) == "$0.00")
        #expect(ItemRowText.total(dec("110"), currencyCode: "USD", locale: Self.enUS) == "$110.00")
    }

    // MARK: - Group header

    @Test("LD-04 the header shows the group's planned total, bought items included; '—' without prices")
    func groupAmount() {
        let summary = ListStatusTextTests.summary(["60", "55", "30✓"])
        #expect(GroupHeaderText.amount(summary, currencyCode: "USD", locale: Self.enUS) == "$145.00")
        #expect(GroupHeaderText.amount(ListStatusTextTests.summary(["-"]), currencyCode: "USD",
                                       locale: Self.enUS) == "—")
        #expect(GroupHeaderText.amount(ListStatusTextTests.summary([]), currencyCode: "USD",
                                       locale: Self.enUS) == "—")
    }

    // MARK: - Summary bar

    static func bar(_ lines: [String], budget: String? = nil, currency: String = "USD",
                    locale: Locale = enUS) -> ListSummaryText {
        ListSummaryText(ListStatusTextTests.summary(lines, budget: budget, currency: currency),
                        currencyCode: currency, locale: locale)
    }

    @Test("LD-10 the seed list Alex: to buy $340.00 of $370.00, 8% bought", .englishUI)
    func alex() {
        let bar = Self.bar(ListStatusTextTests.alexLines, budget: "500")
        #expect(bar.isVisible)
        #expect(bar.toBuy == "$340.00")
        #expect(bar.ofPlanned == "of $370.00")
        #expect(bar.progress == "8% bought")
        #expect(bar.unpriced == nil)
        #expect(bar.compact == "To buy $340.00 · 8%")
        #expect(bar.status.budgetFull == "$130.00 to spare of $500.00")
    }

    @Test("LD-11 hidden without items")
    func hiddenWhenEmpty() {
        #expect(!Self.bar([]).isVisible)
    }

    @Test("LD-11 '+N without price' with plural forms", .englishUI,
          arguments: [(["10", "-"], "+1 without price"), (["10", "-", "-", "-"], "+3 without price")]
          as [([String], String)])
    func unpriced(lines: [String], expected: String) {
        #expect(Self.bar(lines).unpriced == expected)
    }

    @Test("LD-11a the budget line uses Home's full texts; red only over budget", .englishUI)
    func budgetLine() {
        #expect(Self.bar(["10"]).status.budgetFull == "No budget")
        let over = Self.bar(ListStatusTextTests.victoriaLines, budget: "300", currency: "EUR")
        #expect(over.status.budgetFull == "plan €15.00 over budget")
        #expect(over.status.isOverBudget)
    }

    @Test("Without prices: '—', no 'of planned', no percent in the compact form", .englishUI)
    func noPrices() {
        let bar = Self.bar(["-", "-"])
        #expect(bar.toBuy == "—")
        #expect(bar.ofPlanned == nil)
        #expect(bar.progress == "2 items")
        #expect(bar.compact == "To buy —")
    }

    @Test("The compact form keeps the amount and percent of the full form")
    func compactMatchesFull() throws {
        let bar = Self.bar(["60", "40✓"], locale: Self.ruRU)
        let percent = try #require(bar.status.percentText)
        #expect(bar.compact.contains(bar.toBuy))
        #expect(bar.compact.hasSuffix(percent))
    }

    // MARK: - Bought row style (LD-07a, LD-07b)

    @Test("LD-07b not bought: nothing struck, not dimmed")
    func rowStyleNotBought() {
        let style = ItemRowStyle(isComplete: false)
        #expect(!style.nameStrikethrough)
        #expect(!style.amountStrikethrough)
        #expect(!style.isDimmed)
    }

    @Test("LD-07b bought: the name is struck, the amounts are not, the row is dimmed")
    func rowStyleBought() {
        let style = ItemRowStyle(isComplete: true)
        #expect(style.nameStrikethrough)
        #expect(!style.amountStrikethrough)
        #expect(style.isDimmed)
    }
}
