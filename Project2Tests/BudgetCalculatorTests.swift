//
//  BudgetCalculatorTests.swift
//  Project2Tests
//
//  Spec 01, DM-20...DM-25: money math on value snapshots (no SwiftData).
//

import Foundation
import Testing
@testable import Project2

@Suite("BudgetCalculator", .tags(.money))
struct BudgetCalculatorTests {

    // MARK: - lineTotal (DM-20, DM-21, DM-22)

    struct LineCase: CustomTestStringConvertible, Sendable {
        let name: String
        let line: BudgetLine
        let listCurrency: String
        let expected: Decimal?

        var testDescription: String { name }
    }

    static let lineCases: [LineCase] = [
        LineCase(name: "DM-20 same currency: price × quantity",
                 line: BudgetLine(price: dec("12.50"), quantity: 3),
                 listCurrency: "USD", expected: dec("37.50")),
        LineCase(name: "DM-21 unpriced item has no line total",
                 line: BudgetLine(price: nil, quantity: 5),
                 listCurrency: "USD", expected: nil),
        LineCase(name: "DM-20 foreign currency with rate: price × quantity × rate",
                 line: BudgetLine(price: dec("10"), quantity: 2, currencyCode: "EUR", exchangeRate: dec("1.1")),
                 listCurrency: "USD", expected: dec("22")),
        LineCase(name: "DM-22 foreign currency without rate has no line total",
                 line: BudgetLine(price: dec("10"), quantity: 2, currencyCode: "EUR", exchangeRate: nil),
                 listCurrency: "USD", expected: nil),
        LineCase(name: "DM-20 rate is ignored for the list currency",
                 line: BudgetLine(price: dec("10"), quantity: 2, currencyCode: "USD", exchangeRate: dec("3")),
                 listCurrency: "USD", expected: dec("20")),
        LineCase(name: "DM-20 currency codes compare case-insensitively",
                 line: BudgetLine(price: dec("10"), quantity: 1, currencyCode: "eur", exchangeRate: dec("5")),
                 listCurrency: "EUR", expected: dec("10")),
        LineCase(name: "DM-20 nil currency code means list currency",
                 line: BudgetLine(price: dec("4"), quantity: 1, currencyCode: nil, exchangeRate: dec("9")),
                 listCurrency: "EUR", expected: dec("4")),
        LineCase(name: "DM-21 price 0 is a real price, not 'unpriced'",
                 line: BudgetLine(price: 0, quantity: 3),
                 listCurrency: "USD", expected: 0),
    ]

    @Test("lineTotal", arguments: lineCases)
    func lineTotal(_ testCase: LineCase) {
        let total = BudgetCalculator.lineTotal(of: testCase.line, listCurrencyCode: testCase.listCurrency)
        #expect(total == testCase.expected)
    }

    // MARK: - summary (DM-21...DM-23)

    @Test("DM-21 unpriced items add 0 and are counted")
    func unpricedItemsAreCounted() {
        let summary = BudgetCalculator.summary(of: [
            BudgetLine(price: dec("5")),
            BudgetLine(price: nil),
            BudgetLine(price: nil, isComplete: true),
        ], listCurrencyCode: "USD")

        #expect(summary.planned == dec("5"))
        #expect(summary.bought == 0)
        #expect(summary.unpricedCount == 2)
        #expect(summary.missingRateCount == 0)
        #expect(summary.itemCount == 3)
        #expect(summary.completedCount == 1)
    }

    @Test("DM-22 foreign item without rate is excluded and counted")
    func missingRateIsExcluded() {
        let summary = BudgetCalculator.summary(of: [
            BudgetLine(price: dec("10")),
            BudgetLine(price: dec("100"), currencyCode: "GBP", exchangeRate: nil),
            BudgetLine(price: dec("100"), currencyCode: "GBP", exchangeRate: dec("1.25")),
        ], listCurrencyCode: "USD")

        #expect(summary.planned == dec("135"))
        #expect(summary.missingRateCount == 1)
        #expect(summary.unpricedCount == 0)
    }

    @Test("DM-23 planned, bought, toBuy and fraction")
    func plannedBoughtToBuy() {
        let summary = BudgetCalculator.summary(of: [
            BudgetLine(price: dec("60")),
            BudgetLine(price: dec("30"), isComplete: true),
            BudgetLine(price: dec("55"), quantity: 2, isComplete: true),
        ], listCurrencyCode: "USD")

        #expect(summary.planned == dec("200"))
        #expect(summary.bought == dec("140"))
        #expect(summary.toBuy == dec("60"))
        #expect(summary.boughtFraction == dec("0.7"))
    }

    @Test("DM-23 budget left (under budget)")
    func budgetLeftUnderBudget() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("120"))], listCurrencyCode: "USD", budget: dec("500"))

        #expect(summary.budget == dec("500"))
        #expect(summary.budgetLeft == dec("380"))
        #expect(summary.isOverBudget == false)
    }

    @Test("DM-23 over budget: budgetLeft is negative")
    func overBudget() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("315"))], listCurrencyCode: "EUR", budget: dec("300"))

        #expect(summary.budgetLeft == dec("-15"))
        #expect(summary.isOverBudget)
    }

    @Test("DM-23 planned exactly equal to budget is not over budget")
    func exactlyOnBudget() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("300"))], listCurrencyCode: "EUR", budget: dec("300"))

        #expect(summary.budgetLeft == 0)
        #expect(summary.isOverBudget == false)
    }

    @Test("DM-23 no budget: budgetLeft is nil and never over budget")
    func noBudget() {
        let summary = BudgetCalculator.summary(of: [BudgetLine(price: dec("1000"))], listCurrencyCode: "USD")

        #expect(summary.budget == nil)
        #expect(summary.budgetLeft == nil)
        #expect(summary.isOverBudget == false)
    }

    @Test("DM-23 boughtFraction", arguments: [
        ([BudgetLine](), Decimal(0)),
        ([BudgetLine(price: nil, isComplete: true)], Decimal(0)),
        ([BudgetLine(price: dec("10"), isComplete: false)], Decimal(0)),
        ([BudgetLine(price: dec("10"), isComplete: true), BudgetLine(price: dec("30"))], dec("0.25")),
        ([BudgetLine(price: dec("10"), isComplete: true)], Decimal(1)),
    ])
    func boughtFraction(lines: [BudgetLine], expected: Decimal) {
        let summary = BudgetCalculator.summary(of: lines, listCurrencyCode: "USD")
        #expect(summary.boughtFraction == expected)
        #expect((0...1).contains(summary.boughtFraction))
    }

    @Test("DM-23 empty list: everything is zero")
    func emptySummary() {
        let summary = BudgetCalculator.summary(of: [], listCurrencyCode: "USD")

        #expect(summary.planned == 0)
        #expect(summary.bought == 0)
        #expect(summary.toBuy == 0)
        #expect(summary.boughtFraction == 0)
        #expect(summary.itemCount == 0)
        #expect(summary.completedCount == 0)
        #expect(summary == BudgetSummary.empty)
    }

    // MARK: - Precision (DM-25)

    @Test("DM-25 3 × 0.10 is exactly 0.30 (no rounding, no binary floating point)")
    func decimalExactness() throws {
        let lines = Array(repeating: BudgetLine(price: dec("0.1")), count: 3)
        let summary = BudgetCalculator.summary(of: lines, listCurrencyCode: "USD")
        #expect(summary.planned == dec("0.3"))

        let quantityThree = try #require(
            BudgetCalculator.lineTotal(of: BudgetLine(price: dec("0.10"), quantity: 3), listCurrencyCode: "USD"))
        #expect(quantityThree == dec("0.30"))

        // The same sum in Double is NOT exact: this is why money is Decimal.
        #expect(0.1 + 0.1 + 0.1 != 0.3)
    }

    @Test("DM-25 amounts are not rounded internally")
    func noInternalRounding() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("0.333"), quantity: 3)], listCurrencyCode: "USD")
        #expect(summary.planned == dec("0.999"))
    }

    // MARK: - Group sums equal list sum (DM-24)

    @Test("DM-24 sum of group summaries equals the list summary (seeded random data)",
          arguments: [1, 7, 42, 2026, 31337] as [UInt64])
    func groupSumsEqualListSum(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let currencies = ["USD", "usd", "EUR", nil] as [String?]

        let groups: [[BudgetLine]] = (0..<Int.random(in: 1...6, using: &rng)).map { _ in
            (0..<Int.random(in: 0...12, using: &rng)).map { _ in
                let cents = Int.random(in: 0...100_000, using: &rng)
                return BudgetLine(
                    price: Bool.random(using: &rng) || cents % 5 != 0 ? Decimal(cents) / 100 : nil,
                    quantity: Int.random(in: 1...999, using: &rng),
                    isComplete: Bool.random(using: &rng),
                    currencyCode: currencies.randomElement(using: &rng) ?? nil,
                    exchangeRate: Bool.random(using: &rng) ? Decimal(Int.random(in: 1...300, using: &rng)) / 100 : nil
                )
            }
        }

        let list = BudgetCalculator.summary(of: groups.flatMap { $0 }, listCurrencyCode: "USD")
        let parts = groups.map { BudgetCalculator.summary(of: $0, listCurrencyCode: "USD") }

        #expect(parts.reduce(0) { $0 + $1.planned } == list.planned)
        #expect(parts.reduce(0) { $0 + $1.bought } == list.bought)
        #expect(parts.reduce(0) { $0 + $1.toBuy } == list.toBuy)
        #expect(parts.reduce(0) { $0 + $1.unpricedCount } == list.unpricedCount)
        #expect(parts.reduce(0) { $0 + $1.missingRateCount } == list.missingRateCount)
        #expect(parts.reduce(0) { $0 + $1.itemCount } == list.itemCount)
    }

    @Test("Decimal.doubleValue converts for display APIs")
    func doubleValue() {
        #expect(dec("0.25").doubleValue == 0.25)
    }
}
