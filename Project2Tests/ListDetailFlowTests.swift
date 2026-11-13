//
//  ListDetailFlowTests.swift
//  Project2Tests
//
//  M4a QA: the list screen's numbers computed from real models through
//  `PlannerStore` (not hand-made summaries), and the store side of its flows:
//  group header = planned (LD-04), summary bar to buy / of / % / "+N without
//  price" / budget (LD-10, LD-11, LD-11a), moving an item between groups
//  (LD-09, ID-08), undo of a delete (LD-09), ✕ of item details (ID-01),
//  group order after a reorder (LD-03), inline add with a typed price
//  (LD-15, BUG-26) and currencies without fraction digits (ID-03a, SC-09).
//
//  Every amount is formatted with an explicit Locale; whole English sentences
//  only run when the test host is in English (`.englishUI`).
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@Suite("List detail flows (M4a)", .tags(.money))
@MainActor
struct ListDetailFlowTests {

    static let enUS = Locale(identifier: "en_US")
    static let ruRU = Locale(identifier: "ru_RU")
    static let jaJP = Locale(identifier: "ja_JP")

    /// What the summary bar shows for `list`.
    static func bar(_ list: ListModel, locale: Locale = enUS) -> ListSummaryText {
        ListSummaryText(list.summary, currencyCode: list.currencyCode, locale: locale)
    }

    /// What the header of `group` shows.
    static func header(_ group: GroupModel, locale: Locale = enUS) -> String {
        GroupHeaderText.amount(group.summary, currencyCode: group.listCurrencyCode, locale: locale)
    }

    /// Kitchen: Sofa 450, Lamp 60 × 2 (bought), Rug (no price). Bath: Towel 15.
    @MainActor
    struct Kitchen {
        let list: ListModel
        let kitchen: GroupModel
        let bath: GroupModel
        let sofa: ItemModel
        let lamp: ItemModel
        let rug: ItemModel
        let towel: ItemModel

        init(_ f: StoreFixture, budget: Decimal? = nil) {
            list = f.store.createList(name: "Flat", budget: budget)
            kitchen = f.store.createGroup(name: "Kitchen", in: list)
            bath = f.store.createGroup(name: "Bath", in: list)
            sofa = f.addItem("Sofa", to: kitchen, price: dec("450"))
            lamp = f.addItem("Lamp", to: kitchen, quantity: 2, price: dec("60"))
            rug = f.addItem("Rug", to: kitchen)
            towel = f.addItem("Towel", to: bath, price: dec("15"))
            f.store.toggleComplete(lamp)
        }
    }

    // MARK: - Group header (LD-04)

    @Test("LD-04 the header keeps the planned total when an item is bought; only the list's 'to buy' drops")
    func headerIsPlannedNotToBuy() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)
        #expect(Self.header(k.kitchen) == "$570.00")
        #expect(Self.bar(k.list).toBuy == "$465.00")

        f.store.toggleComplete(k.sofa)
        #expect(Self.header(k.kitchen) == "$570.00", "planned includes bought items")
        #expect(Self.bar(k.list).toBuy == "$15.00")

        f.store.toggleComplete(k.sofa)
        #expect(Self.bar(k.list).toBuy == "$465.00", "unchecking gives the amount back")
    }

    @Test("LD-04 a price or quantity change shows in the header and the summary right away")
    func headerFollowsEdits() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)

        var draft = ItemDraft(item: k.sofa)
        draft.price = dec("400.5")
        draft.quantity = 2
        f.store.updateItem(k.sofa, with: draft)

        #expect(Self.header(k.kitchen) == "$921.00")      // 801 + 120
        #expect(Self.bar(k.list).toBuy == "$816.00")      // 801 + 15
        #expect(Self.bar(k.list).ofPlanned == "of $936.00")
    }

    @Test("LD-04 the header shows '—' for a group with only unpriced items, and for an empty group")
    func headerWithoutPrices() throws {
        let f = try StoreFixture()
        let (_, group) = f.makeGroup()
        #expect(Self.header(group) == "—")
        f.addItem("Rug", to: group)
        #expect(Self.header(group) == "—")
        f.addItem("Free sample", to: group, price: 0)
        #expect(Self.header(group) == "$0.00", "a price of 0 is a price")
    }

    // MARK: - Summary bar (LD-10, LD-11, LD-11a)

    @Test("LD-10 / LD-11 summary bar of a real list: to buy, of planned, percent, +N without price",
          .englishUI)
    func summaryFromModels() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)
        let bar = Self.bar(k.list)

        #expect(bar.isVisible)
        #expect(bar.toBuy == "$465.00")
        #expect(bar.ofPlanned == "of $585.00")
        #expect(bar.progress == "20% bought")       // 120 / 585 = 20.5 % → rounded down
        #expect(bar.unpriced == "+1 without price")
        #expect(bar.compact == "To buy $465.00 · 20%")
        #expect(abs(bar.barFraction - 0.2) < 0.0001, "bar and percent agree")
    }

    @Test("LD-11 the bar disappears when the last item is deleted and comes back with Undo")
    func summaryHiddenAfterLastDelete() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        let item = f.addItem("Only", to: group, price: 5)
        let snapshot = ItemSnapshot(item)
        #expect(Self.bar(list).isVisible)

        f.store.deleteItem(item)
        #expect(!Self.bar(list).isVisible)

        f.store.restoreItem(snapshot, in: list)
        #expect(Self.bar(list).isVisible)
    }

    @Test("LD-11 '+N without price' counts unpriced items whether bought or not", .englishUI)
    func unpricedCountsBoughtToo() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)
        f.addItem("Vase", to: k.bath)
        #expect(Self.bar(k.list).unpriced == "+2 without price")

        f.store.toggleComplete(k.rug)
        #expect(Self.bar(k.list).unpriced == "+2 without price")

        var draft = ItemDraft(item: k.rug)
        draft.price = 99
        f.store.updateItem(k.rug, with: draft)
        #expect(Self.bar(k.list).unpriced == "+1 without price", "pricing an item removes it from the count")
    }

    @Test("LD-11a budget line: to spare, exactly on budget (not red), one cent over (red)", .englishUI,
          arguments: [
            ("600", "$15.00 to spare of $600.00", false),
            ("585", "$0.00 to spare of $585.00", false),
            ("584.99", "plan $0.01 over budget", true),
          ] as [(String, String, Bool)])
    func budgetLine(budget: String, expected: String, over: Bool) throws {
        let f = try StoreFixture()
        let k = Kitchen(f, budget: dec(budget))
        let status = Self.bar(k.list).status
        #expect(status.budgetFull == expected)
        #expect(status.isOverBudget == over)
    }

    @Test("LD-11a buying items doesn't change the budget line: it compares the plan with the budget",
          .englishUI)
    func budgetIgnoresBought() throws {
        let f = try StoreFixture()
        let k = Kitchen(f, budget: dec("500"))
        #expect(Self.bar(k.list).status.budgetFull == "plan $85.00 over budget")
        f.store.toggleComplete(k.sofa)
        f.store.toggleComplete(k.towel)
        #expect(Self.bar(k.list).status.budgetFull == "plan $85.00 over budget")
        #expect(Self.bar(k.list).progress == "100% bought", "all the money is bought, unpriced Rug is left")
        f.store.toggleComplete(k.rug)
        #expect(Self.bar(k.list).progress == "All bought")
        #expect(Self.bar(k.list).status.budgetFull == "plan $85.00 over budget")
    }

    @Test("LD-11a deleting an item can bring the list back under budget", .englishUI)
    func budgetAfterDelete() throws {
        let f = try StoreFixture()
        let k = Kitchen(f, budget: dec("500"))
        #expect(Self.bar(k.list).status.isOverBudget)

        f.store.deleteItem(k.lamp)
        #expect(!Self.bar(k.list).status.isOverBudget)
        #expect(Self.bar(k.list).status.budgetFull == "$35.00 to spare of $500.00")
    }

    @Test("Summary bar amounts in ru_RU + EUR use a decimal comma and the € suffix")
    func summaryRussian() throws {
        let f = try StoreFixture(currency: "EUR")
        let (list, group) = f.makeGroup()
        f.addItem("Диван", to: group, price: dec("1234.5"))
        let bought = f.addItem("Лампа", to: group, price: dec("100"))
        f.store.toggleComplete(bought)

        let bar = Self.bar(list, locale: Self.ruRU)
        #expect(bar.toBuy.plainSpaces == "1 234,50 €")
        #expect(bar.ofPlanned?.plainSpaces.hasSuffix("1 334,50 €") == true)
        #expect(Self.header(group, locale: Self.ruRU).plainSpaces == "1 334,50 €")
    }

    // MARK: - JPY: no fraction digits (ID-03a, SC-09)

    @Test("JPY: row, header and summary show whole yen; .5 rounds half up")
    func yen() throws {
        let f = try StoreFixture(currency: "JPY")
        let (list, group) = f.makeGroup()
        let typed = MoneyInput.parse("1234.5", currencyCode: "JPY", locale: Self.enUS)
        #expect(typed == .amount(1235), "a typed fraction is rounded away on input")
        let tea = f.addItem("Tea", to: group, quantity: 2, price: 500)
        f.addItem("Cup", to: group, price: 1235)

        #expect(ItemRowText.total(tea.lineTotal, currencyCode: "JPY", locale: Self.enUS) == "¥1,000")
        #expect(ItemRowText.detail(quantity: 2, price: 500, currencyCode: "JPY", notes: "",
                                   locale: Self.enUS) == "2 × ¥500")
        #expect(Self.header(group) == "¥2,235")
        #expect(Self.bar(list).toBuy == "¥2,235")
        #expect(Self.bar(list).ofPlanned?.hasSuffix("¥2,235") == true)
        #expect(MoneyInput.editingText(for: 1235, currencyCode: "JPY", locale: Self.jaJP) == "1235")
    }

    @Test("JPY: a price stored with a fraction (e.g. from sync) is shown rounded half up, never with decimals")
    func yenStoredFraction() throws {
        let f = try StoreFixture(currency: "JPY")
        let (_, group) = f.makeGroup()
        let item = f.addItem("Odd", to: group, price: dec("2.5"))
        #expect(ItemRowText.total(item.lineTotal, currencyCode: "JPY", locale: Self.enUS) == "¥3")
    }

    // MARK: - Move to another group (LD-09 context menu, ID-08 picker)

    @Test("LD-09 Move to Group updates both group headers; the list totals stay the same")
    func moveUpdatesBothHeaders() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)
        let before = k.list.summary

        f.store.moveItem(k.sofa, to: k.bath)

        #expect(Self.header(k.kitchen) == "$120.00")
        #expect(Self.header(k.bath) == "$465.00")
        #expect(k.list.summary == before)
        #expect(k.bath.sortedItems.map(\.name) == ["Towel", "Sofa"])
    }

    @Test("ID-08 moving a bought item keeps it bought and counts it as bought in the new group")
    func moveBoughtItem() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)

        var draft = ItemDraft(item: k.lamp)
        draft.groupID = k.bath.uuid
        f.store.updateItem(k.lamp, with: draft)

        #expect(k.lamp.isComplete)
        #expect(k.bath.summary.bought == 120)
        #expect(k.kitchen.summary.bought == 0)
        #expect(k.bath.sortedItems.map(\.name) == ["Towel", "Lamp"], "bought items stay after open ones")
    }

    // MARK: - Undo of a delete (LD-09)

    @Test("LD-09 Undo of a not-bought item in the middle puts it back between its neighbours")
    func undoKeepsPosition() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        f.addItem("A", to: group, price: 1)
        let b = f.addItem("B", to: group, quantity: 3, price: dec("9.99"))
        b.urlString = "shop.example.org/b"
        b.notes = "blue\nlarge"
        f.addItem("C", to: group, price: 2)
        let snapshot = ItemSnapshot(b)
        let header = Self.header(group)
        let summary = list.summary

        f.store.deleteItem(b)
        #expect(group.sortedItems.map(\.name) == ["A", "C"])
        #expect(Self.header(group) == "$3.00")

        let restored = try #require(f.store.restoreItem(snapshot, in: list))
        #expect(group.sortedItems.map(\.name) == ["A", "B", "C"])
        #expect(ItemSnapshot(restored) == snapshot, "same uuid, values, sortIndex and dates")
        #expect(Self.header(group) == header)
        #expect(list.summary == summary)
        #expect(!f.context.hasChanges, "saved")
    }

    @Test("LD-09 Undo still puts the item back in its place after another item was added")
    func undoAfterAnotherAdd() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        let a = f.addItem("A", to: group)
        f.addItem("B", to: group)
        let snapshot = ItemSnapshot(a)

        f.store.deleteItem(a)
        f.addItem("New", to: group)
        f.store.restoreItem(snapshot, in: list)

        #expect(group.sortedItems.map(\.name) == ["A", "B", "New"])
    }

    @Test("LD-09 Undo into a list that doesn't own the item's group restores nothing")
    func undoIntoListWithoutTheGroup() throws {
        let f = try StoreFixture()
        let (_, group) = f.makeGroup()
        let (otherList, _) = f.makeGroup(listName: "Other")
        let item = f.addItem("A", to: group)
        let snapshot = ItemSnapshot(item)
        f.store.deleteItem(item)

        #expect(f.store.restoreItem(snapshot, in: otherList) == nil)
        #expect(try f.count(ItemModel.self) == 0)
    }

    // MARK: - Item details ✕ (ID-01)

    @Test("ID-01 ✕: a changed draft that isn't applied leaves the item and the store untouched")
    func cancelDiscardsDraft() throws {
        let f = try StoreFixture()
        let k = Kitchen(f)
        let before = ItemSnapshot(k.sofa)
        let summary = k.list.summary

        var draft = ItemDraft(item: k.sofa)
        draft.name = "Bike"
        draft.price = 99
        draft.quantity = 7
        draft.notes = "changed"
        draft.urlString = "bike.example.org"
        draft.groupID = k.bath.uuid
        #expect(draft != ItemDraft(item: k.sofa), "the sheet would see changes")
        // ✕ = the sheet just goes away; nothing calls the store.

        #expect(ItemSnapshot(k.sofa) == before)
        #expect(k.list.summary == summary)
        #expect(!f.context.hasChanges)
        #expect(ItemDraft(item: k.sofa) != draft, "a new sheet starts from the saved values")
    }

    // MARK: - Reorder groups (LD-03)

    @Test("LD-03 a reordered group order is saved and read back by a fresh context (reopening the list)")
    func reorderGroupsIsSaved() throws {
        let f = try StoreFixture()
        let list = f.store.createList(name: "Flat")
        for name in ["Kitchen", "Bath", "Hall"] { f.store.createGroup(name: name, in: list) }

        f.store.moveGroup(in: list, fromOffsets: [2], toOffset: 0)
        #expect(list.sortedGroups.map(\.name) == ["Hall", "Kitchen", "Bath"])
        #expect(!f.context.hasChanges, "saved")

        let fresh = ModelContext(f.container)
        let lists = try fresh.fetch(FetchDescriptor<ListModel>())
        let reread = try #require(lists.first)
        #expect(reread.sortedGroups.map(\.name) == ["Hall", "Kitchen", "Bath"])
    }

    // MARK: - Inline add with price / quantity (LD-15, BUG-26)

    @Test("LD-15 inline add: a price typed with a decimal comma or dot and Qty 2 make a 25.00 line",
          arguments: [("12,5", "ru_RU", "EUR"), ("12.5", "ru_RU", "EUR"), ("12.5", "en_US", "USD"),
                      ("12,5", "en_US", "USD")] as [(String, String, String)])
    func inlineAddTypedPrice(text: String, locale: String, currency: String) throws {
        let f = try StoreFixture(currency: currency)
        let (list, group) = f.makeGroup()

        var draft = ItemDraft(groupID: group.uuid)
        draft.name = "Kite"
        guard case .amount(let price) = MoneyInput.parse(text, currencyCode: currency,
                                                         locale: Locale(identifier: locale)) else {
            Issue.record("\(text) did not parse")
            return
        }
        draft.price = price
        draft.quantity = 2
        let item = try #require(f.store.addItem(from: draft, to: group))

        #expect(item.price == dec("12.5"))
        #expect(item.lineTotal == 25)
        #expect(list.summary.toBuy == 25)
    }

    @Test("LD-15 an empty inline price field is 'no price': the item counts as unpriced")
    func inlineAddEmptyPrice() throws {
        let f = try StoreFixture()
        let (list, group) = f.makeGroup()
        var draft = ItemDraft(groupID: group.uuid)
        draft.name = "Kite"
        draft.price = MoneyInput.parse("", currencyCode: "USD", locale: Self.enUS) == .empty ? nil : 0
        let item = try #require(f.store.addItem(from: draft, to: group))

        #expect(item.price == nil)
        #expect(list.summary.unpricedCount == 1)
        #expect(ItemRowText.total(item.lineTotal, currencyCode: "USD", locale: Self.enUS) == "—")
    }
}
