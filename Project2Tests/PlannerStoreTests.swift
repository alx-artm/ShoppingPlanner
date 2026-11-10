//
//  PlannerStoreTests.swift
//  Project2Tests
//
//  Service layer rules (spec 01, DM-06...DM-19, DM-24) on an in-memory
//  ModelContainer created per test, with an injected clock.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("PlannerStore")
struct PlannerStoreTests {

    // MARK: - Lists

    @Suite("Lists")
    @MainActor
    struct Lists {
        let f: StoreFixture
        init() throws { f = try StoreFixture() }

        @Test("DM-12 createList trims the name and stamps createdAt from the clock", .tags(.validation))
        func createListTrims() throws {
            let list = f.store.createList(name: "  Weekend  trip \n")

            #expect(list.name == "Weekend  trip")
            #expect(list.createdAt == f.clock.now)
            #expect(list.currencyCode == "USD")
            #expect(try f.count(ListModel.self) == 1)
            #expect(f.store.lastErrorMessage == nil)
        }

        @Test("DM-12 a blank list name falls back to a placeholder", .tags(.validation))
        func createListBlankName() {
            let list = f.store.createList(name: "   ")
            #expect(list.name.isEmpty == false)
            #expect(list.name.trimmingCharacters(in: .whitespaces) == list.name)
        }

        @Test("DM-12 renameList trims; blank keeps a non-empty placeholder", .tags(.validation))
        func renameList() {
            let list = f.store.createList(name: "Old")
            f.store.renameList(list, to: "  New name ")
            #expect(list.name == "New name")

            f.store.renameList(list, to: " \t ")
            #expect(!list.name.isEmpty)
            #expect(list.name != " \t ")
        }

        @Test("DM-14 a negative budget is rejected, nil removes the budget", .tags(.validation))
        func budgetValidation() {
            let list = f.store.createList(name: "B", budget: dec("-1"))
            #expect(list.budget == nil, "createList must drop a negative budget")

            #expect(f.store.setBudget(dec("250.50"), for: list))
            #expect(list.budget == dec("250.50"))

            #expect(f.store.setBudget(dec("-10"), for: list) == false)
            #expect(list.budget == dec("250.50"), "the old value stays")

            #expect(f.store.setBudget(nil, for: list))
            #expect(list.budget == nil)
        }

        @Test("New lists use the store's default currency unless one is given")
        func currency() throws {
            let euro = try StoreFixture(currency: "EUR")
            #expect(euro.store.createList(name: "A").currencyCode == "EUR")
            #expect(euro.store.createList(name: "B", currencyCode: "JPY").currencyCode == "JPY")
        }

        @Test("DM-06 new lists are appended to the end of their Home section", .tags(.ordering))
        func appendToSection() {
            let a = f.store.createList(name: "A")
            let b = f.store.createList(name: "B")
            let pinned = f.store.createList(name: "P", isPinned: true)

            #expect(f.store.lists(pinned: false).map(\.name) == ["A", "B"])
            #expect(f.store.lists(pinned: true).map(\.name) == ["P"])
            #expect(b.sortIndex > a.sortIndex)
            #expect(pinned.sortIndex == 0)
        }

        @Test("togglePin moves the list to the end of the other section", .tags(.ordering))
        func togglePin() {
            _ = f.store.createList(name: "P1", isPinned: true)
            let a = f.store.createList(name: "A")
            _ = f.store.createList(name: "B")

            f.store.togglePin(a)

            #expect(a.isPinned)
            #expect(f.store.lists(pinned: true).map(\.name) == ["P1", "A"])
            #expect(f.store.lists(pinned: false).map(\.name) == ["B"])

            f.store.togglePin(a)
            #expect(f.store.lists(pinned: false).map(\.name) == ["B", "A"])
        }

        @Test("DM-07 moveList reorders a section", .tags(.ordering))
        func moveList() {
            for name in ["A", "B", "C"] { f.store.createList(name: name) }

            f.store.moveList(in: f.store.lists(pinned: false), fromOffsets: [2], toOffset: 0)

            #expect(f.store.lists(pinned: false).map(\.name) == ["C", "A", "B"])
        }

        @Test("setIcon: empty icon resets to the default symbol; setColor stores the color")
        func iconAndColor() {
            let list = f.store.createList(name: "A")
            f.store.setIcon("🧸", kind: .emoji, for: list)
            #expect(list.iconName == "🧸")
            #expect(list.iconKind == .emoji)

            f.store.setIcon("", kind: .emoji, for: list)
            #expect(list.iconName == "cart")
            #expect(list.iconKind == .symbol)

            f.store.setColor(.green, for: list)
            #expect(list.color == .green)
        }

        @Test("DM-19 duplicateList copies groups and items, resets completion, keeps currency and budget")
        func duplicateList() throws {
            let (list, group) = f.makeGroup(listName: "Trip", groupName: "Food")
            f.store.setBudget(dec("100"), for: list)
            let item = f.addItem("Bread", to: group, quantity: 2, price: dec("1.5"))
            f.store.toggleComplete(item)
            f.clock.advance(by: 60)

            let copy = f.store.duplicateList(list)

            #expect(copy !== list)
            #expect(copy.uuid != list.uuid)
            #expect(copy.name.contains("Trip"))
            #expect(copy.name != "Trip")
            #expect(copy.budget == dec("100"))
            #expect(copy.currencyCode == list.currencyCode)
            #expect(copy.createdAt == f.clock.now)

            let copiedGroup = try #require(copy.sortedGroups.first)
            #expect(copiedGroup.name == "Food")
            #expect(copiedGroup.uuid != group.uuid)
            let copiedItem = try #require(copiedGroup.items?.first)
            #expect(copiedItem.name == "Bread")
            #expect(copiedItem.uuid != item.uuid)
            #expect(copiedItem.quantity == 2)
            #expect(copiedItem.price == dec("1.5"))
            #expect(copiedItem.isComplete == false)
            #expect(copiedItem.completedAt == nil)

            // The original is untouched.
            #expect(item.isComplete)
            #expect(try f.count(ListModel.self) == 2)
            #expect(try f.count(ItemModel.self) == 2)
        }

        @Test("DM-08 deleteList cascades to its groups and items, other lists stay", .tags(.deletion))
        func deleteListCascades() throws {
            let (list, group) = f.makeGroup()
            f.addItem("A", to: group)
            f.addItem("B", to: f.store.createGroup(name: "G2", in: list))
            let (_, otherGroup) = f.makeGroup(listName: "Other")
            f.addItem("Keep", to: otherGroup)
            #expect(try f.count(ItemModel.self) == 3)

            f.store.deleteList(list)

            #expect(try f.count(ListModel.self) == 1)
            #expect(try f.count(GroupModel.self) == 1)
            #expect(try f.count(ItemModel.self) == 1)
            let survivor = try #require(try f.context.fetch(FetchDescriptor<ItemModel>()).first)
            #expect(survivor.name == "Keep")
        }
    }

    // MARK: - Groups

    @Suite("Groups")
    @MainActor
    struct Groups {
        let f: StoreFixture
        init() throws { f = try StoreFixture() }

        @Test("DM-12 createGroup / renameGroup trim the name", .tags(.validation))
        func trimming() {
            let list = f.store.createList(name: "L")
            let group = f.store.createGroup(name: "  Snacks ", in: list)
            #expect(group.name == "Snacks")
            #expect(group.list === list)
            #expect(group.createdAt == f.clock.now)

            f.store.renameGroup(group, to: " Drinks  ")
            #expect(group.name == "Drinks")

            f.store.renameGroup(group, to: "   ")
            #expect(!group.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        @Test("DM-06 group order comes from sortIndex, not from createdAt or array order",
              .tags(.ordering, .regression), .bug(id: "BUG-02"))
        func groupOrderIsStable() {
            let list = f.store.createList(name: "L")
            // The clock goes backwards: createdAt alone would give the reverse order.
            f.clock.advance(by: 300)
            f.store.createGroup(name: "First", in: list)
            f.clock.advance(by: -100)
            f.store.createGroup(name: "Second", in: list)
            f.clock.advance(by: -100)
            f.store.createGroup(name: "Third", in: list)

            #expect(list.sortedGroups.map(\.name) == ["First", "Second", "Third"])
            #expect(list.sortedGroups.map(\.sortIndex) == [0, 1, 2])
        }

        @Test("DM-07 moveGroup changes only the moved group's sortIndex", .tags(.ordering))
        func moveGroup() {
            let list = f.store.createList(name: "L")
            for name in ["A", "B", "C", "D"] { f.store.createGroup(name: name, in: list) }
            let before = Dictionary(uniqueKeysWithValues: list.sortedGroups.map { ($0.name, $0.sortIndex) })

            f.store.moveGroup(in: list, fromOffsets: [3], toOffset: 1)

            #expect(list.sortedGroups.map(\.name) == ["A", "D", "B", "C"])
            let after = Dictionary(uniqueKeysWithValues: list.sortedGroups.map { ($0.name, $0.sortIndex) })
            #expect(after["A"] == before["A"])
            #expect(after["B"] == before["B"])
            #expect(after["C"] == before["C"])
            #expect(after["D"] != before["D"])
        }

        @Test("DM-08 deleteGroup cascades to its items, the list and other groups stay", .tags(.deletion))
        func deleteGroupCascades() throws {
            let (list, group) = f.makeGroup()
            f.addItem("A", to: group)
            f.addItem("B", to: group)
            let other = f.store.createGroup(name: "Other", in: list)
            f.addItem("Keep", to: other)

            f.store.deleteGroup(group)

            #expect(try f.count(ListModel.self) == 1)
            #expect(try f.count(GroupModel.self) == 1)
            #expect(try f.count(ItemModel.self) == 1)
            #expect(list.sortedGroups.map(\.name) == ["Other"])
            #expect(list.summary.itemCount == 1)
        }
    }

    // MARK: - Items

    @Suite("Items")
    @MainActor
    struct Items {
        let f: StoreFixture
        init() throws { f = try StoreFixture() }

        @Test("DM-12 addItem rejects a blank name", .tags(.validation),
              arguments: ["", " ", "\n\t  "])
        func blankNameRejected(name: String) throws {
            let (_, group) = f.makeGroup()
            #expect(f.store.addItem(name: name, to: group) == nil)
            #expect(try f.count(ItemModel.self) == 0)
        }

        @Test("DM-12 addItem trims the edges and keeps inner spaces", .tags(.validation))
        func nameTrimmed() throws {
            let (_, group) = f.makeGroup()
            let item = try #require(f.store.addItem(name: "  Ice  cream \n", to: group))
            #expect(item.name == "Ice  cream")
            #expect(item.group === group)
            #expect(item.createdAt == f.clock.now)
        }

        @Test("DM-12 renameItem trims; blank keeps a placeholder", .tags(.validation))
        func renameItem() {
            let (_, group) = f.makeGroup()
            let item = f.addItem("Milk", to: group)
            f.store.renameItem(item, to: " Oat milk ")
            #expect(item.name == "Oat milk")
            f.store.renameItem(item, to: "  ")
            #expect(!item.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        @Test("DM-13 quantity is clamped to 1...999", .tags(.validation), arguments: [
            (Int.min, 1), (-5, 1), (0, 1), (1, 1), (42, 42), (999, 999), (1000, 999), (Int.max, 999),
        ] as [(Int, Int)])
        func quantityClamped(input: Int, expected: Int) {
            let (_, group) = f.makeGroup()
            let added = f.addItem("A", to: group, quantity: input)
            #expect(added.quantity == expected, "addItem")

            let edited = f.addItem("B", to: group)
            f.store.setQuantity(input, for: edited)
            #expect(edited.quantity == expected, "setQuantity")
        }

        @Test("DM-14 a negative price is rejected and the old value stays", .tags(.validation, .money))
        func negativePriceRejected() {
            let (_, group) = f.makeGroup()
            let item = f.addItem("A", to: group, price: dec("9.99"))

            #expect(f.store.setPrice(dec("-0.01"), for: item) == false)
            #expect(item.price == dec("9.99"))

            #expect(f.store.setPrice(dec("0"), for: item))
            #expect(item.price == 0)
        }

        @Test("DM-14 nil price stays nil, not 0", .tags(.validation, .money), .bug(id: "BUG-07"))
        func nilPriceStaysNil() throws {
            let (list, group) = f.makeGroup()
            let item = f.addItem("A", to: group, price: nil)
            #expect(item.price == nil)
            #expect(item.lineTotal == nil)

            f.store.setPrice(dec("5"), for: item)
            #expect(f.store.setPrice(nil, for: item))
            #expect(item.price == nil)
            #expect(list.summary.unpricedCount == 1)
            #expect(list.summary.planned == 0)

            let negative = try #require(f.store.addItem(name: "B", to: group, price: dec("-3")))
            #expect(negative.price == nil, "addItem turns a negative price into 'no price'")
        }

        @Test("DM-16 toggleComplete sets completedAt from the clock and clears it", .bug(id: "BUG-03"))
        func completedAt() {
            let (_, group) = f.makeGroup()
            let item = f.addItem("A", to: group)
            #expect(item.completedAt == nil)

            f.clock.advance(by: 3600)
            f.store.toggleComplete(item)
            #expect(item.isComplete)
            #expect(item.completedAt == SeedData.baseDate.addingTimeInterval(3600))

            f.store.toggleComplete(item)
            #expect(item.isComplete == false)
            #expect(item.completedAt == nil)

            f.clock.advance(by: 60)
            f.store.toggleComplete(item)
            #expect(item.completedAt == SeedData.baseDate.addingTimeInterval(3660))
        }

        @Test("DM-15 completed items go after open ones, in completion order", .tags(.ordering))
        func completionOrder() {
            let (_, group) = f.makeGroup()
            let a = f.addItem("A", to: group)
            let b = f.addItem("B", to: group)
            _ = f.addItem("C", to: group)
            f.addItem("D", to: group)

            f.clock.advance(by: 10)
            f.store.toggleComplete(b)
            f.clock.advance(by: 10)
            f.store.toggleComplete(a)

            #expect(group.sortedItems.map(\.name) == ["C", "D", "B", "A"])
            #expect(group.incompleteItems.map(\.name) == ["C", "D"])

            f.store.toggleComplete(a) // back to its manual place
            #expect(group.sortedItems.map(\.name) == ["A", "C", "D", "B"])
        }

        @Test("DM-06 item order comes from sortIndex (appended at the end)", .tags(.ordering))
        func itemOrderStable() {
            let (_, group) = f.makeGroup()
            f.clock.advance(by: 1000)
            f.addItem("First", to: group)
            f.clock.advance(by: -500)
            f.addItem("Second", to: group)
            f.clock.advance(by: -500)
            f.addItem("Third", to: group)

            #expect(group.sortedItems.map(\.name) == ["First", "Second", "Third"])
            #expect(group.sortedItems.map(\.sortIndex) == [0, 1, 2])
        }

        @Test("DM-07 moveItems reorders the open items only", .tags(.ordering))
        func moveItems() {
            let (_, group) = f.makeGroup()
            for name in ["A", "B", "C"] { f.addItem(name, to: group) }
            let done = f.addItem("Done", to: group)
            f.store.toggleComplete(done)

            f.store.moveItems(in: group, fromOffsets: [0], toOffset: 3)

            #expect(group.sortedItems.map(\.name) == ["B", "C", "A", "Done"])
        }

        @Test("moveItem puts the item at the end of the target group")
        func moveItemToGroup() {
            let (list, source) = f.makeGroup()
            let target = f.store.createGroup(name: "Target", in: list)
            f.addItem("T1", to: target)
            f.addItem("T2", to: target)
            let item = f.addItem("Moved", to: source)

            f.store.moveItem(item, to: target)

            #expect(item.group === target)
            #expect(target.sortedItems.map(\.name) == ["T1", "T2", "Moved"])
            #expect(source.items?.isEmpty == true)
        }

        @Test("deleteItem removes exactly that item and updates the sums", .tags(.deletion))
        func deleteItem() throws {
            let (list, group) = f.makeGroup()
            f.addItem("A", to: group, price: dec("10"))
            let b = f.addItem("B", to: group, price: dec("20"))

            f.store.deleteItem(b)

            #expect(try f.count(ItemModel.self) == 1)
            #expect(group.sortedItems.map(\.name) == ["A"])
            #expect(list.summary.planned == dec("10"))
        }

        /// With "Hide completed" the row offsets refer to `incompleteItems`, not
        /// `sortedItems`. Deleting must resolve offsets against the array that is
        /// shown, and delete by object identity (BUG-01, spec 04 LD-14).
        @Test("BUG-01 swipe-delete with hidden completed items deletes the visible item",
              .tags(.deletion, .regression), .bug(id: "BUG-01"))
        func deleteVisibleItemWithHiddenCompleted() throws {
            let (_, group) = f.makeGroup()
            let done = f.addItem("Done", to: group)
            f.addItem("Apple", to: group)
            f.addItem("Banana", to: group)
            f.addItem("Cherry", to: group)
            f.store.toggleComplete(done)

            // What ListViewInside shows when completed items are hidden.
            let visible = group.incompleteItems
            #expect(visible.map(\.name) == ["Apple", "Banana", "Cherry"])

            // The user swipes the second visible row ("Banana").
            let offsets = IndexSet(integer: 1)
            for item in offsets.map({ visible[$0] }) { f.store.deleteItem(item) }

            #expect(group.sortedItems.map(\.name) == ["Apple", "Cherry", "Done"])
            #expect(try f.count(ItemModel.self) == 3)
        }
    }

    // MARK: - Sums (DM-24)

    @Suite("Sums", .tags(.money))
    @MainActor
    struct Sums {
        @Test("DM-24 group sums equal the list sum (seeded random data through the store)",
              arguments: [3, 11, 2026] as [UInt64])
        func groupSumsEqualListSum(seed: UInt64) throws {
            let f = try StoreFixture()
            var rng = SeededGenerator(seed: seed)
            let list = f.store.createList(name: "Random", budget: dec("1000"))

            for g in 0..<Int.random(in: 1...5, using: &rng) {
                let group = f.store.createGroup(name: "G\(g)", in: list)
                for i in 0..<Int.random(in: 0...8, using: &rng) {
                    let price: Decimal? = Bool.random(using: &rng)
                        ? Decimal(Int.random(in: 0...50_000, using: &rng)) / 100 : nil
                    let item = f.addItem("I\(i)", to: group, quantity: Int.random(in: 1...20, using: &rng), price: price)
                    if Bool.random(using: &rng) { f.store.toggleComplete(item) }
                }
            }

            let parts = list.sortedGroups.map(\.summary)
            let total = list.summary
            #expect(parts.reduce(0) { $0 + $1.planned } == total.planned)
            #expect(parts.reduce(0) { $0 + $1.bought } == total.bought)
            #expect(parts.reduce(0) { $0 + $1.toBuy } == total.toBuy)
            #expect(parts.reduce(0) { $0 + $1.itemCount } == total.itemCount)
            #expect(parts.reduce(0) { $0 + $1.unpricedCount } == total.unpricedCount)
        }

        @Test("Item in a foreign currency uses the list currency of its parent")
        func itemUsesParentCurrency() throws {
            let f = try StoreFixture()
            let list = f.store.createList(name: "EU", currencyCode: "EUR")
            let group = f.store.createGroup(name: "G", in: list)
            let item = f.addItem("A", to: group, quantity: 2, price: dec("10"))
            item.currencyCode = "USD"
            #expect(item.lineTotal == nil, "DM-22: no rate → excluded")
            item.exchangeRate = dec("0.9")
            #expect(item.lineTotal == dec("18"))
            item.currencyCode = "eur"
            #expect(item.lineTotal == dec("20"), "same currency → rate ignored")
        }

        /// The UI tests depend on these numbers (SampleData.swift header table).
        @Test("Seed data totals match the documented table")
        func seedTotals() throws {
            let container = try Persistence.makeContainer(inMemory: true)
            let lists = try SeedData.populate(container.mainContext)

            let alex = lists.alex.summary
            #expect(alex.planned == 370)
            #expect(alex.bought == 30)
            #expect(alex.toBuy == 340)
            #expect(alex.budgetLeft == 130)
            #expect(lists.alex.sortedGroups.map(\.name) == ["Vacation", "Birthday"])
            #expect(lists.alex.sortedGroups.map(\.summary.toBuy) == [115, 225])

            let eva = lists.eva.summary
            #expect(eva.planned == 180)
            #expect(eva.unpricedCount == 1)
            #expect(eva.budget == nil)

            let victoria = lists.victoria.summary
            #expect(victoria.planned == 315)
            #expect(victoria.isOverBudget)
            #expect(lists.victoria.currencyCode == "EUR")

            #expect(try container.mainContext.fetchCount(FetchDescriptor<ItemModel>()) == 18)
        }
    }
}
