//
//  MustHaveTests.swift
//  Project2Tests
//
//  Spec 11 "Must-have": the mark on an item (MH-01, MH-05, MH-06, MH-13), the planned
//  total of the marked items (MH-02), the summary bar line (MH-09, MH-10), the row's
//  VoiceOver value (MH-14) and Share as Text (MH-12).
//

import Foundation
import Testing
@testable import Project2

@MainActor
@Suite("Must-have", .tags(.money))
struct MustHaveTests {
    let f: StoreFixture
    init() throws { f = try StoreFixture() }

    static let enUS = Locale(identifier: "en_US")
    static let ruRU = Locale(identifier: "ru_RU")

    // MARK: - Model and store

    @Test("MH-01 a new item, an inline item and an item from a draft without the toggle aren't marked")
    func defaults() throws {
        #expect(ItemModel().isMustHave == false)
        #expect(ItemDraft().isMustHave == false)
        let (_, group) = f.makeGroup()
        #expect(f.addItem("Lamp", to: group).isMustHave == false)
        var draft = ItemDraft(groupID: group.uuid)
        draft.name = "Bed"
        #expect(try #require(f.store.addItem(from: draft, to: group)).isMustHave == false)
        draft.isMustHave = true
        #expect(try #require(f.store.addItem(from: draft, to: group)).isMustHave == true)
    }

    @Test("toggleMustHave marks and unmarks; 'bought' and the order don't change (MH-06)")
    func toggle() {
        let (_, group) = f.makeGroup()
        let a = f.addItem("A", to: group)
        let b = f.addItem("B", to: group)
        f.addItem("C", to: group)
        f.store.toggleComplete(a)
        let indexes = group.sortedItems.map(\.sortIndex)

        f.store.toggleMustHave(b)
        #expect(b.isMustHave)
        #expect(group.sortedItems.map(\.name) == ["B", "C", "A"])
        f.store.toggleMustHave(a)
        #expect(a.isMustHave && a.isComplete, "a bought item stays a must-have")
        f.store.toggleMustHave(b)
        #expect(!b.isMustHave)
        #expect(group.sortedItems.map(\.sortIndex) == indexes)
    }

    @Test("MH-05 the draft takes the mark; ✓ (updateItem) saves it, an untouched draft keeps it")
    func draftAndUpdate() {
        let (_, group) = f.makeGroup()
        let item = f.addItem("Bed", to: group)
        var draft = ItemDraft(item: item)
        #expect(draft == ItemDraft(item: item))
        draft.isMustHave = true
        #expect(draft != ItemDraft(item: item), "the toggle alone is an unsaved change")

        f.store.updateItem(item, with: draft)
        #expect(item.isMustHave)
        #expect(ItemDraft(item: item).isMustHave)
        f.store.updateItem(item, with: ItemDraft(item: item))
        #expect(item.isMustHave)
    }

    @Test("MH-13 duplicate item, Undo of a delete and duplicate list keep the mark; archive / restore too")
    func copiesKeepTheMark() throws {
        let (list, group) = f.makeGroup()
        let bed = f.addItem("Bed", to: group, price: dec("690"))
        f.addItem("Lamp", to: group)
        f.store.toggleMustHave(bed)
        f.store.toggleComplete(bed)

        #expect(try #require(f.store.duplicateItem(bed)).isMustHave)

        let snapshot = ItemSnapshot(bed)
        #expect(snapshot.isMustHave)
        f.store.deleteItem(bed)
        let restored = try #require(f.store.restoreItem(snapshot, in: list))
        #expect(restored.isMustHave)
        #expect(ItemSnapshot(restored) == snapshot)

        let copy = f.store.duplicateList(list)
        let copied = copy.sortedGroups.flatMap(\.sortedItems)
        #expect(copied.filter(\.isMustHave).map(\.name) == ["Bed", "Bed"])
        #expect(copied.allSatisfy { !$0.isComplete }, "only 'bought' is reset")
        #expect(copied.first { $0.name == "Lamp" }?.isMustHave == false)

        f.store.archiveList(list)
        f.store.restoreList(list)
        #expect(list.sortedGroups.flatMap(\.sortedItems).filter(\.isMustHave).count == 2)
    }

    // MARK: - BudgetCalculator (MH-02)

    @Test("MH-02 must-have planned: marked items, bought or not; same price and currency rules as planned")
    func calculator() {
        func line(_ price: String?, mustHave: Bool, complete: Bool = false, quantity: Int = 1,
                  currency: String? = nil, rate: String? = nil) -> BudgetLine {
            BudgetLine(price: price.map(dec), quantity: quantity, isComplete: complete, isMustHave: mustHave,
                       currencyCode: currency, exchangeRate: rate.map(dec))
        }
        let empty = BudgetCalculator.summary(of: [], listCurrencyCode: "USD")
        #expect(empty.mustHavePlanned == 0 && empty.mustHaveCount == 0)

        let lines = [
            line("690", mustHave: true),
            line("200", mustHave: true, complete: true, quantity: 2),
            line("150", mustHave: false),
            line(nil, mustHave: true),
            line("100", mustHave: true, currency: "EUR"),
            line("10", mustHave: true, currency: "EUR", rate: "1.1"),
        ]
        let summary = BudgetCalculator.summary(of: lines, listCurrencyCode: "USD", budget: dec("1000"))
        #expect(summary.mustHavePlanned == dec("1101"))
        #expect(summary.mustHaveCount == 5, "no price: +1 to the count, 0 to the sum")
        #expect(summary.mustHaveExcess == dec("101"))

        let unmarked = lines.map { var l = $0; l.isMustHave = false; return l }
        let plain = BudgetCalculator.summary(of: unmarked, listCurrencyCode: "USD", budget: dec("1000"))
        #expect(plain.planned == summary.planned)
        #expect(plain.bought == summary.bought)
        #expect(plain.toBuy == summary.toBuy)
        #expect(plain.mustHaveExcess == nil)
    }

    @Test("MH-10 the excess only with a budget the must-haves are over")
    func excess() {
        let marked = [BudgetLine(price: dec("500"), isMustHave: true)]
        #expect(BudgetCalculator.summary(of: marked, listCurrencyCode: "USD").mustHaveExcess == nil)
        #expect(BudgetCalculator.summary(of: marked, listCurrencyCode: "USD", budget: dec("500")).mustHaveExcess == nil)
        #expect(BudgetCalculator.summary(of: marked, listCurrencyCode: "USD", budget: dec("450")).mustHaveExcess == dec("50"))
    }

    // MARK: - Summary line (MH-09, MH-10)

    @Test("MH-09 / MH-10 summary line: none without marks; amount; '… over budget' only over the budget")
    func summaryLine() throws {
        let en = try ListStatusTextTests.languageBundle("en")
        let ru = try ListStatusTextTests.languageBundle("ru")
        func text(_ budget: String?, marked: Bool = true, locale: Locale = Self.enUS, bundle: Bundle) -> MustHaveText? {
            let summary = BudgetCalculator.summary(
                of: [BudgetLine(price: dec("1090"), isMustHave: marked), BudgetLine(price: dec("150"))],
                listCurrencyCode: "USD", budget: budget.map(dec))
            return MustHaveText(summary, currencyCode: "USD", locale: locale, bundle: bundle)
        }
        #expect(text("1000", marked: false, bundle: en) == nil)

        let fits = try #require(text("2000", bundle: en))
        #expect(fits.amount == "Must-haves $1,090.00")
        #expect(fits.overBudget == nil && !fits.isOverBudget)
        #expect(try #require(text(nil, bundle: en)).overBudget == nil, "no budget: no tail")

        let over = try #require(text("1000", bundle: en))
        #expect(over.overBudget == "$90.00 over budget")
        #expect(over.isOverBudget)
        #expect(over.accessibilityLabel == "Must-haves $1,090.00, $90.00 over budget")

        let overRU = try #require(text("1000", locale: Self.ruRU, bundle: ru))
        #expect(overRU.amount.plainSpaces == "Обязательные 1 090,00 $")
        #expect(overRU.overBudget?.plainSpaces == "на 90,00 $ больше бюджета")
    }

    @Test("MH-09 the summary bar text has the line only while an item is marked")
    func summaryTextFollowsTheMarks() {
        let (list, group) = f.makeGroup()
        let bed = f.addItem("Bed", to: group, price: dec("690"))
        #expect(ListSummaryText(list.summary, currencyCode: "USD", locale: Self.enUS).mustHaves == nil)
        f.store.toggleMustHave(bed)
        #expect(ListSummaryText(list.summary, currencyCode: "USD", locale: Self.enUS).mustHaves != nil)
        f.store.toggleMustHave(bed)
        #expect(ListSummaryText(list.summary, currencyCode: "USD", locale: Self.enUS).mustHaves == nil)
    }

    // MARK: - Row VoiceOver value (MH-14)

    @Test("MH-14 row value: 'Must-have', 'Must-have, Bought', 'Bought', empty")
    func rowValue() throws {
        let en = try ListStatusTextTests.languageBundle("en")
        let ru = try ListStatusTextTests.languageBundle("ru")
        func value(_ complete: Bool, _ mustHave: Bool, _ bundle: Bundle) -> String {
            ItemRowText.accessibilityValue(isComplete: complete, isMustHave: mustHave, bundle: bundle)
        }
        #expect(value(false, true, en) == "Must-have")
        #expect(value(true, true, en) == "Must-have, Bought")
        #expect(value(true, false, en) == "Bought")
        #expect(value(false, false, en) == "")
        #expect(value(true, true, ru) == "обязательное, Куплено")
    }

    // MARK: - Share as Text (MH-12)

    @Test("MH-12 Share as Text: '★ ' before marked names, 'Must-haves:' after 'Planned:'", .englishUI)
    func shareText() {
        let list = f.store.createList(name: "Flat", budget: dec("1000"))
        let group = f.store.createGroup(name: "Bedroom", in: list)
        let bed = f.addItem("Bed", to: group, price: dec("690"))
        f.addItem("Lamp", to: group, price: dec("150"))
        let plain = ListShareText.make(for: list, locale: Self.enUS)
        #expect(!plain.contains("★"))
        #expect(!plain.contains("Must-haves"))

        f.store.toggleMustHave(bed)
        #expect(ListShareText.make(for: list, locale: Self.enUS) == """
        Flat

        Bedroom
        ☐ ★ Bed — 1 × $690.00 = $690.00
        ☐ Lamp — 1 × $150.00 = $150.00

        To buy: $840.00
        Planned: $840.00
        Must-haves: $690.00
        Budget: $1,000.00
        """)
    }
}
