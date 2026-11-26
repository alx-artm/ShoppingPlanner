//
//  ListCurrencyChangeTests.swift
//  Project2Tests
//
//  Spec 03 LI-20...LI-22: List Info changes a list's currency as a relabel. Only
//  `currencyCode` changes; prices, the budget and the totals keep their numbers, and
//  every formatted amount uses the new code. A list with a priced item or a budget
//  asks "Prices won't be converted" first (LI-21).
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("List currency change (LI-20...LI-22)", .tags(.listInfo, .money))
struct ListCurrencyChangeTests {

    // MARK: - LI-21: when to ask

    struct ConfirmationCase: CustomTestStringConvertible, Sendable {
        let name: String
        let hasPricedItems: Bool
        let budget: Decimal?
        let expected: Bool

        var testDescription: String { "\(name) → \(expected ? "confirm" : "change at once")" }
    }

    nonisolated static let confirmationCases: [ConfirmationCase] = [
        ConfirmationCase(name: "empty list", hasPricedItems: false, budget: nil, expected: false),
        ConfirmationCase(name: "unpriced items only", hasPricedItems: false, budget: nil, expected: false),
        ConfirmationCase(name: "priced items", hasPricedItems: true, budget: nil, expected: true),
        ConfirmationCase(name: "budget only", hasPricedItems: false, budget: dec("300"), expected: true),
        ConfirmationCase(name: "budget 0 is a budget (LI-08)", hasPricedItems: false, budget: 0, expected: true),
        ConfirmationCase(name: "priced items and budget", hasPricedItems: true, budget: dec("300"), expected: true),
    ]

    @Test("LI-21 needsConfirmation", arguments: confirmationCases)
    func needsConfirmation(_ c: ConfirmationCase) {
        #expect(ListCurrencyChange.needsConfirmation(hasPricedItems: c.hasPricedItems, budget: c.budget) == c.expected)
    }

    /// The flag the screen passes in, from real lists: empty, unpriced, priced, budget only.
    @Test("LI-21 hasPricedItems + budget of real lists")
    func needsConfirmationForLists() throws {
        let f = try StoreFixture()

        let empty = f.store.createList(name: "Empty")
        _ = f.store.createGroup(name: "G", in: empty)

        let (unpriced, unpricedGroup) = f.makeGroup(listName: "Unpriced")
        f.addItem("Jacket", to: unpricedGroup)

        let (priced, pricedGroup) = f.makeGroup(listName: "Priced")
        f.addItem("Jacket", to: pricedGroup)
        f.addItem("Free sample", to: pricedGroup, price: 0)

        let budgetOnly = f.store.createList(name: "Budget", budget: dec("100"))

        let asks = { (list: ListModel) in
            ListCurrencyChange.needsConfirmation(hasPricedItems: list.hasPricedItems, budget: list.budget)
        }
        #expect(!asks(empty))
        #expect(!asks(unpriced))
        #expect(asks(priced), "a price of 0 is still a number the user typed")
        #expect(asks(budgetOnly))
    }

    // MARK: - LI-20: the store mutation

    @Test("LI-20 setCurrency relabels: prices, budget and totals keep their numbers")
    func setCurrencyKeepsNumbers() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        #expect(f.store.setBudget(dec("500"), for: list))
        let shoes = f.addItem("Shoes", to: group, quantity: 2, price: dec("45.50"))
        f.addItem("Hat", to: group, price: dec("20"))
        f.store.toggleComplete(shoes)
        let before = list.summary

        #expect(f.store.setCurrency("EUR", for: list))

        #expect(list.currencyCode == "EUR")
        #expect(list.budget == dec("500"))
        #expect(shoes.price == dec("45.50"))
        let after = list.summary
        #expect(after.planned == before.planned)
        #expect(after.planned == dec("111"))
        #expect(after.bought == before.bought)
        #expect(after.budgetLeft == before.budgetLeft)
        #expect(after.isOverBudget == before.isOverBudget)
        #expect(f.context.hasChanges == false, "saved like any other list edit (LI-22)")
        #expect(f.store.lastErrorMessage == nil)
    }

    @Test("LI-20 setCurrency rejects an unknown code and normalises case",
          arguments: [("eur", "EUR", true), (" gbp ", "GBP", true), ("XYZ", "USD", false), ("", "USD", false)])
    func setCurrencyValidation(input: String, expected: String, accepted: Bool) throws {
        let f = try StoreFixture()
        let list = f.store.createList(name: "L")
        #expect(f.store.setCurrency(input, for: list) == accepted)
        #expect(list.currencyCode == expected)
    }

    @Test("LI-20 List Info ✓ applies the draft's currency; same code changes nothing")
    func updateListAppliesCurrency() throws {
        let f = try StoreFixture()
        let list = f.store.createList(name: "L", budget: dec("300"))

        var draft = ListDraft(list: list)
        f.store.updateList(list, with: draft)
        #expect(list.currencyCode == "USD")

        draft.currencyCode = "JPY"
        f.store.updateList(list, with: draft)
        #expect(list.currencyCode == "JPY")
        #expect(list.budget == dec("300"), "no conversion")

        draft.currencyCode = "nope"
        f.store.updateList(list, with: draft)
        #expect(list.currencyCode == "JPY", "a bad code never replaces the currency")
    }

    // MARK: - Formatting follows the new code at once

    @Test("LI-20 groups, items and formatted amounts use the new code")
    func formattingUsesNewCode() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        let item = f.addItem("Lamp", to: group, quantity: 2, price: dec("1234.5"))
        let enUS = Locale(identifier: "en_US")

        #expect(MoneyFormat.string(list.summary.planned, currencyCode: list.currencyCode, locale: enUS) == "$2,469.00")

        f.store.setCurrency("EUR", for: list)

        // Rows, group headers and item details read the list's code through these.
        #expect(item.listCurrencyCode == "EUR")
        #expect(group.listCurrencyCode == "EUR")
        #expect(MoneyFormat.string(list.summary.planned, currencyCode: list.currencyCode, locale: enUS) == "€2,469.00")
        #expect(ItemRowText.total(item.lineTotal, currencyCode: item.listCurrencyCode, locale: enUS) == "€2,469.00")

        // SC-09: the fraction digits follow the new currency too.
        f.store.setCurrency("JPY", for: list)
        #expect(MoneyFormat.string(list.summary.planned, currencyCode: list.currencyCode, locale: enUS) == "¥2,469")
    }
}
