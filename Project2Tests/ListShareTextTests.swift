//
//  ListShareTextTests.swift
//  Project2Tests
//
//  Spec 02 HM-12 "Share as text": list name, groups and items in display
//  order as "☐/☑ name — qty × price = total", then To buy / Planned (and
//  Budget). All totals in the list currency, with an explicit Locale.
//

import Foundation
import Testing
@testable import Project2

@MainActor
@Suite("ListShareText", .tags(.home, .money))
struct ListShareTextTests {
    let f: StoreFixture
    init() throws { f = try StoreFixture() }

    static let enUS = Locale(identifier: "en_US")

    /// Food: Bread 2 × 1.50, Milk ✓ 2.00, Jacket (no price). Gear: Tent €100 (no rate), Map €10 × 1.1.
    func makeTrip() -> ListModel {
        let list = f.store.createList(name: "Trip", budget: dec("50"))
        let food = f.store.createGroup(name: "Food", in: list)
        f.addItem("Bread", to: food, quantity: 2, price: dec("1.5"))
        let milk = f.addItem("Milk", to: food, price: dec("2"))
        f.addItem("Jacket", to: food)
        f.clock.advance(by: 60)
        f.store.toggleComplete(milk)

        let gear = f.store.createGroup(name: "Gear", in: list)
        let tent = f.addItem("Tent", to: gear, price: dec("100"))
        tent.currencyCode = "EUR"
        let map = f.addItem("Map", to: gear, price: dec("10"))
        map.currencyCode = "EUR"
        map.exchangeRate = dec("1.1")
        return list
    }

    @Test("HM-12 the whole text: groups and items in display order, then the totals", .englishUI)
    func fullText() {
        let text = ListShareText.make(for: makeTrip(), locale: Self.enUS)

        #expect(text == """
        Trip

        Food
        ☐ Bread — 2 × $1.50 = $3.00
        ☐ Jacket — 1
        ☑ Milk — 1 × $2.00 = $2.00

        Gear
        ☐ Tent — 1 × €100.00 = —
        ☐ Map — 1 × €10.00 = $11.00

        To buy: $14.00
        Planned: $16.00
        Budget: $50.00
        """)
    }

    @Test("HM-12 the totals match the list summary (same numbers as Home and the summary bar)")
    func totalsMatchSummary() {
        let list = makeTrip()
        let text = ListShareText.make(for: list, locale: Self.enUS)
        let summary = list.summary
        #expect(summary.toBuy == dec("14"))
        #expect(summary.planned == dec("16"))
        #expect(text.contains(MoneyFormat.string(summary.toBuy, currencyCode: "USD", locale: Self.enUS)))
        #expect(text.contains(MoneyFormat.string(summary.planned, currencyCode: "USD", locale: Self.enUS)))
    }

    @Test("HM-12 item lines use the given locale (language-independent part)")
    func itemLinesInRussianLocale() {
        let text = ListShareText.make(for: makeTrip(), locale: Locale(identifier: "ru_RU")).plainSpaces
        #expect(text.contains("☐ Bread — 2 × 1,50 $ = 3,00 $"))
        #expect(text.contains("☑ Milk — 1 × 2,00 $ = 2,00 $"))
        #expect(text.contains("☐ Map — 1 × 10,00 € = 11,00 $"))
    }

    @Test("HM-12 a list without groups has only the name and zero totals, no budget line", .englishUI)
    func emptyList() {
        let list = f.store.createList(name: "Empty")
        #expect(ListShareText.make(for: list, locale: Self.enUS) == """
        Empty

        To buy: $0.00
        Planned: $0.00
        """)
    }

    @Test("HM-12 groups follow their sortIndex; an empty group shows just its name", .englishUI)
    func groupOrder() {
        let list = f.store.createList(name: "L", currencyCode: "EUR")
        f.store.createGroup(name: "First", in: list)
        let second = f.store.createGroup(name: "Second", in: list)
        f.addItem("Pen", to: second, quantity: 3, price: dec("0.5"))
        f.store.moveGroup(in: list, fromOffsets: [1], toOffset: 0)

        let text = ListShareText.make(for: list, locale: Self.enUS)
        #expect(text == """
        L

        Second
        ☐ Pen — 3 × €0.50 = €1.50

        First

        To buy: €1.50
        Planned: €1.50
        """)
    }
}
