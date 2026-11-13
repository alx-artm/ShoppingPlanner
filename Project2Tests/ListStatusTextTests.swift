//
//  ListStatusTextTests.swift
//  Project2Tests
//
//  Spec 02 "Status model" (HM-05/06, HM-16, HM-18…HM-30): the parts of a list's
//  status on Home (amount / progress / percent / budget short and full /
//  over budget) and the VoiceOver sentence, for states S1–S6.
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

    /// "price×qty", "price×qty✓" (completed) or "-" / "-✓" (no price).
    static func summary(_ lines: [String], budget: String? = nil, currency: String = "USD") -> BudgetSummary {
        let parsed = lines.map { spec -> BudgetLine in
            let done = spec.hasSuffix("✓")
            let bare = spec.replacingOccurrences(of: "✓", with: "")
            guard bare != "-" else { return BudgetLine(price: nil, isComplete: done) }
            let parts = bare.split(separator: "×")
            return BudgetLine(price: dec(String(parts[0])),
                              quantity: parts.count > 1 ? Int(parts[1])! : 1,
                              isComplete: done)
        }
        return BudgetCalculator.summary(of: parsed, listCurrencyCode: currency, budget: budget.map(dec))
    }

    static func status(_ lines: [String], budget: String? = nil, currency: String = "USD",
                       locale: Locale = enUS) -> ListStatusText {
        ListStatusText(summary(lines, budget: budget, currency: currency), currencyCode: currency, locale: locale)
    }

    /// The seed list "Alex": 60 + 55 + 30✓ + 30 + 55×2 + 85 = 370 planned, 30 bought.
    static let alexLines = ["60", "55", "30✓", "30", "55×2", "85"]
    /// The seed list "Victoria": 315 planned in EUR, nothing bought.
    static let victoriaLines = ["60", "55", "30", "30", "55", "85"]

    // MARK: - HM-06 no prices

    @Test("HM-06 hasPrices is false without any priced item (Home shows '—', not '0')",
          arguments: [
            ([], false), (["-"], false), (["-", "-"], false),
            (["-", "10"], true), (["0"], true), (["10✓"], true),
          ] as [([String], Bool)])
    func hasPrices(lines: [String], expected: Bool) {
        #expect(ListStatusText.hasPrices(Self.summary(lines)) == expected)
        #expect(Self.status(lines).hasPrices == expected)
    }

    @Test("Documented: an item priced in a foreign currency without a rate counts as 'has prices'")
    func foreignWithoutRate() {
        let summary = BudgetCalculator.summary(
            of: [BudgetLine(price: dec("10"), currencyCode: "EUR")], listCurrencyCode: "USD")
        #expect(ListStatusText.hasPrices(summary))
        #expect(summary.toBuy == 0, "excluded from sums (DM-22), so the tile shows $0.00, not '—'")
    }

    // MARK: - HM-18 parts for S1–S6

    struct Case: CustomTestStringConvertible, Sendable {
        let state: String
        let lines: [String]
        var budget: String?
        var currency = "USD"
        let progress: ListStatusText.Progress
        let amount: String
        let progressText: String
        let percent: String?
        let budgetShort: String
        let budgetFull: String
        var isOverBudget = false
        var testDescription: String { "\(state): \(progressText) · \(budgetFull)" }
    }

    static let cases: [Case] = [
        Case(state: "S1", lines: [], progress: .empty, amount: "—", progressText: "Empty", percent: nil,
             budgetShort: "No budget", budgetFull: "No budget"),
        Case(state: "S1 budget", lines: [], budget: "500", currency: "EUR", progress: .empty, amount: "—",
             progressText: "Empty", percent: nil, budgetShort: "Budget €500", budgetFull: "budget €500.00"),
        Case(state: "S2", lines: ["-", "-", "-"], budget: "500", currency: "EUR", progress: .items(3),
             amount: "—", progressText: "3 items", percent: nil,
             budgetShort: "Budget €500", budgetFull: "budget €500.00"),
        Case(state: "S2 one", lines: ["-"], progress: .items(1), amount: "—", progressText: "1 item",
             percent: nil, budgetShort: "No budget", budgetFull: "No budget"),
        Case(state: "S3", lines: alexLines, progress: .bought(percent: 8), amount: "$340.00",
             progressText: "8% bought", percent: "8%", budgetShort: "No budget", budgetFull: "No budget"),
        Case(state: "S4", lines: alexLines, budget: "500", progress: .bought(percent: 8), amount: "$340.00",
             progressText: "8% bought", percent: "8%",
             budgetShort: "$130 to spare", budgetFull: "$130.00 to spare of $500.00"),
        // HM-21 example: planned €340, budget €500.
        Case(state: "S4 spec", lines: ["340"], budget: "500", currency: "EUR", progress: .bought(percent: 0),
             amount: "€340.00", progressText: "0% bought", percent: "0%",
             budgetShort: "€160 to spare", budgetFull: "€160.00 to spare of €500.00"),
        // HM-23: planned == budget is "to spare", not over.
        Case(state: "S4 edge", lines: ["370"], budget: "370", progress: .bought(percent: 0), amount: "$370.00",
             progressText: "0% bought", percent: "0%",
             budgetShort: "$0 to spare", budgetFull: "$0.00 to spare of $370.00"),
        // HM-20/21: planned €315, budget €300, nothing bought.
        Case(state: "S5", lines: victoriaLines, budget: "300", currency: "EUR", progress: .bought(percent: 0),
             amount: "€315.00", progressText: "0% bought", percent: "0%",
             budgetShort: "€15 over", budgetFull: "plan €15.00 over budget", isOverBudget: true),
        // LI-08: budget 0, so any planned amount is over.
        Case(state: "S5 zero", lines: ["0.01"], budget: "0", progress: .bought(percent: 0), amount: "$0.01",
             progressText: "0% bought", percent: "0%",
             budgetShort: "$1 over", budgetFull: "plan $0.01 over budget", isOverBudget: true),
        Case(state: "S5 JPY", lines: ["1234.5"], budget: "0", currency: "JPY", progress: .bought(percent: 0),
             amount: "¥1,235", progressText: "0% bought", percent: "0%",
             budgetShort: "¥1,235 over", budgetFull: "plan ¥1,235 over budget", isOverBudget: true),
        Case(state: "S6", lines: ["10✓", "5✓"], progress: .allBought, amount: "$0.00",
             progressText: "All bought", percent: "100%", budgetShort: "No budget", budgetFull: "No budget"),
        // HM-24 / HM-22: everything bought, the plan still over budget: the over part stays red.
        Case(state: "S6 over", lines: ["315✓"], budget: "300", currency: "EUR", progress: .allBought,
             amount: "€0.00", progressText: "All bought", percent: "100%",
             budgetShort: "€15 over", budgetFull: "plan €15.00 over budget", isOverBudget: true),
    ]

    @Test("HM-18 the status parts for S1–S6 in en_US", .englishUI, arguments: cases)
    func parts(_ c: Case) {
        let s = Self.status(c.lines, budget: c.budget, currency: c.currency)
        #expect(s.progress == c.progress)
        #expect(s.amount == c.amount)
        #expect(s.progressText == c.progressText)
        #expect(s.percentText == c.percent)
        #expect(s.budgetShort == c.budgetShort)
        #expect(s.budgetFull == c.budgetFull)
        #expect(s.isOverBudget == c.isOverBudget)
    }

    // MARK: - Progress and percent

    @Test("HM-19/24 percent by money, rounded down; 100% only when everything is bought",
          arguments: [
            (["999✓", "1"], 99),          // 99.9 % is not 100 %
            (["996✓", "4"], 99),          // 99.6 % → 99 (HM-24)
            (alexLines, 8),               // 30 / 370 = 8.1 %
            (["10✓", "-"], 100),          // all the money is bought, an unpriced item is left
            (["0", "0"], 0),              // planned 0: no division by zero
          ] as [([String], Int)])
    func percent(lines: [String], expected: Int) {
        let s = Self.status(lines)
        #expect(s.progress == .bought(percent: expected))
        #expect(s.barFraction == Double(expected) / 100)
    }

    @Test("HM-24 all bought: 'All bought', 100 %, full bar, the amount is 0")
    func allBought() {
        let s = Self.status(["10✓", "-✓"])
        #expect(s.progress == .allBought)
        #expect(s.isAllBought)
        #expect(s.barFraction == 1)
        #expect(s.percentText == "100%")
    }

    @Test("S2 wins over 'all bought' when no item has a price: there is no money to show")
    func allBoughtWithoutPrices() {
        #expect(Self.status(["-✓", "-✓"]).progress == .items(2))
    }

    @Test("HM-19 the tile percent equals the percent in the row text", .englishUI,
          arguments: [alexLines, ["996✓", "4"], ["10✓"], ["60", "55"]])
    func percentMatchesRow(lines: [String]) throws {
        let s = Self.status(lines)
        let percent = try #require(s.percentText)
        #expect(s.progressText == "\(percent) bought" || s.progressText == "All bought")
    }

    // MARK: - Rounding of the short (tile) form

    @Test("HM-29 tile amounts have no cents: 'to spare' rounds down, 'over' rounds up", .englishUI)
    func shortRounding() {
        #expect(Self.status(["339.01"], budget: "500").budgetShort == "$160 to spare")   // 160.99
        #expect(Self.status(["315.01"], budget: "300").budgetShort == "$16 over")        // 15.01
        #expect(Self.status(["315.01"], budget: "300").budgetFull == "plan $15.01 over budget")
    }

    @Test("HM-29 the short budget form is at most 14 characters for amounts under 1 000",
          arguments: ["en_US", "ru_RU"], [("1", nil), ("1", "999"), ("1", "1"), ("1000", "1"), ("1", "0"), ("-", "999")]
            as [(String, String?)])
    func shortLength(locale: String, amounts: (String, String?)) {
        let s = Self.status([amounts.0], budget: amounts.1, currency: "EUR", locale: Locale(identifier: locale))
        #expect(s.budgetShort.count <= 14, "\(s.budgetShort)")
    }

    // MARK: - HM-29 table of short forms (EN and RU)

    /// The app's strings in one language: `en.lproj` / `ru.lproj` of the app bundle,
    /// so the exact RU text is checked whatever language the test host runs in.
    static func languageBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// 0, 15, 160, 999, 9 999 with the digit grouping of en_US and ru_RU.
    static let shortAmounts: [(amount: String, en: String, ru: String)] = [
        ("0", "0", "0"), ("15", "15", "15"), ("160", "160", "160"),
        ("999", "999", "999"), ("9999", "9,999", "9 999"),
    ]

    struct ShortCase: CustomTestStringConvertible, Sendable {
        let language: String
        let locale: String
        let currency: String
        let budget: ListStatusText.Budget
        let expected: String
        var testDescription: String { "\(locale) \(currency): \(expected)" }
    }

    /// Every form for every amount: en_US + USD/EUR, ru_RU + EUR/RUB.
    static let shortCases: [ShortCase] = {
        var cases: [ShortCase] = []
        for row in shortAmounts {
            let value = dec(row.amount)
            for (currency, symbol) in [("USD", "$"), ("EUR", "€")] {
                cases += [
                    ShortCase(language: "en", locale: "en_US", currency: currency,
                              budget: .toSpare(value, of: 10_000), expected: "\(symbol)\(row.en) to spare"),
                    ShortCase(language: "en", locale: "en_US", currency: currency,
                              budget: .over(value), expected: "\(symbol)\(row.en) over"),
                    ShortCase(language: "en", locale: "en_US", currency: currency,
                              budget: .notPlanned(budget: value), expected: "Budget \(symbol)\(row.en)"),
                ]
            }
            for (currency, symbol) in [("EUR", "€"), ("RUB", "₽")] {
                cases += [
                    ShortCase(language: "ru", locale: "ru_RU", currency: currency,
                              budget: .toSpare(value, of: 10_000), expected: "запас \(row.ru) \(symbol)"),
                    ShortCase(language: "ru", locale: "ru_RU", currency: currency,
                              budget: .over(value), expected: "\(row.ru) \(symbol) сверх"),
                    ShortCase(language: "ru", locale: "ru_RU", currency: currency,
                              budget: .notPlanned(budget: value), expected: "Бюджет \(row.ru) \(symbol)"),
                ]
            }
        }
        return cases
    }()

    @Test("HM-29 exact short forms; at most 14 characters, 15 only for EN 'to spare'", arguments: shortCases)
    func shortTable(_ c: ShortCase) throws {
        let text = ListStatusText.shortBudgetText(c.budget, currencyCode: c.currency,
                                                  locale: Locale(identifier: c.locale),
                                                  bundle: try Self.languageBundle(c.language))
        #expect(text.plainSpaces == c.expected)
        let isEnglishToSpare = if case .toSpare = c.budget { c.language == "en" } else { false }
        #expect(text.count <= (isEnglishToSpare ? 15 : 14), "\(text)")
    }

    @Test("HM-29 RU 'to spare' starts with «запас», not «… в запасе»")
    func russianToSpareWording() throws {
        let text = ListStatusText.shortBudgetText(.toSpare(160, of: 500), currencyCode: "EUR",
                                                  locale: Self.ruRU, bundle: try Self.languageBundle("ru"))
        #expect(text.plainSpaces == "запас 160 €")
        #expect(!text.contains("в запасе"))
    }

    // MARK: - Locale

    @Test("Amounts follow the injected locale, not the device region")
    func locale() {
        let ru = Self.status(Self.alexLines, budget: "500", currency: "EUR", locale: Self.ruRU)
        #expect(ru.amount.plainSpaces == "340,00 €")
        #expect(ru.budgetFull.plainSpaces.contains("130,00 €"))
        #expect(ru.budgetFull.plainSpaces.contains("500,00 €"))
        #expect(ru.budgetShort.plainSpaces.contains("130 €"))
        #expect(ru.percentText?.plainSpaces == "8 %")

        let en = Self.status(Self.alexLines, budget: "500", currency: "EUR", locale: Self.enUS)
        #expect(en.budgetFull.contains("€130.00"))
        #expect(en.budgetShort.contains("€130"))
    }

    @Test("HM-21 the over-budget amount is positive (no minus sign)")
    func overBudgetIsPositive() {
        let s = Self.status(["315"], budget: "300", currency: "EUR")
        for text in [s.budgetShort, s.budgetFull, s.budgetSpoken] {
            #expect(text.contains("15"))
            #expect(!text.contains("-"))
            #expect(!text.contains("−"))
        }
    }

    // MARK: - HM-16 VoiceOver

    struct LabelCase: CustomTestStringConvertible, Sendable {
        let name: String
        let lines: [String]
        var budget: String?
        var currency = "USD"
        let expected: String
        var testDescription: String { expected }
    }

    static let labelCases: [LabelCase] = [
        LabelCase(name: "Kitchen", lines: [], expected: "Kitchen, empty, no budget"),
        LabelCase(name: "Kitchen", lines: ["-", "-", "-"], budget: "500", currency: "EUR",
                  expected: "Kitchen, 3 items, no prices yet, budget €500.00"),
        LabelCase(name: "Eva", lines: ["30", "25", "40", "20×2", "45", "-"],
                  expected: "Eva, to buy $180.00, 0% bought, no budget"),
        LabelCase(name: "Alex", lines: alexLines, budget: "500",
                  expected: "Alex, to buy $340.00, 8% bought, $130.00 to spare of $500.00 budget"),
        LabelCase(name: "Victoria", lines: victoriaLines, budget: "300", currency: "EUR",
                  expected: "Victoria, to buy €315.00, 0% bought, plan €15.00 over budget"),
        LabelCase(name: "Kitchen", lines: ["10✓"], budget: "50",
                  expected: "Kitchen, all bought, $40.00 to spare of $50.00 budget"),
    ]

    @Test("HM-16 one VoiceOver sentence per tile/row; the budget is always read, without ⚠",
          .englishUI, arguments: labelCases)
    func accessibilityLabel(_ c: LabelCase) {
        let label = Self.status(c.lines, budget: c.budget, currency: c.currency).accessibilityLabel(name: c.name)
        #expect(label == c.expected)
        #expect(!label.contains("⚠"))
    }
}
