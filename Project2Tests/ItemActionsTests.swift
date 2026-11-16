//
//  ItemActionsTests.swift
//  Project2Tests
//
//  Spec 04 LD-09 row actions in the store: duplicate (context menu), and the
//  swipe-delete "Undo" toast, which restores the same item from a snapshot.
//

import Foundation
import Testing
@testable import Project2

@Suite("Item actions", .tags(.deletion))
@MainActor
struct ItemActionsTests {

    @Test("Duplicate goes right after the original, not completed, with the same values")
    func duplicate() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let sofa = fixture.addItem("Sofa", to: group, quantity: 2, price: 450)
        sofa.urlString = "ikea.com"
        fixture.addItem("Lamp", to: group)

        let copy = try #require(fixture.store.duplicateItem(sofa))
        #expect(group.sortedItems.map(\.name) == ["Sofa", "Sofa", "Lamp"])
        #expect(copy.uuid != sofa.uuid)
        #expect(copy.quantity == 2)
        #expect(copy.price == 450)
        #expect(copy.urlString == "ikea.com")
    }

    @Test("Duplicating a bought item gives a not-bought copy")
    func duplicateCompleted() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Soap", to: group)
        fixture.store.toggleComplete(item)

        let copy = try #require(fixture.store.duplicateItem(item))
        #expect(!copy.isComplete)
        #expect(copy.completedAt == nil)
        #expect(group.incompleteItems.map(\.name) == ["Soap"])
    }

    @Test("Undo puts the same item back in its place, with every value")
    func restore() throws {
        let fixture = try StoreFixture()
        let (list, group) = fixture.makeGroup()
        fixture.addItem("A", to: group)
        let item = fixture.addItem("B", to: group, quantity: 3, price: dec("9.99"))
        item.notes = "note"
        fixture.store.toggleComplete(item)
        fixture.addItem("C", to: group)
        let snapshot = ItemSnapshot(item)
        let summary = list.summary

        fixture.store.deleteItem(item)
        #expect(try fixture.count(ItemModel.self) == 2)

        let restored = try #require(fixture.store.restoreItem(snapshot, in: list))
        #expect(ItemSnapshot(restored) == snapshot)
        #expect(group.sortedItems.map(\.name) == ["A", "C", "B"])
        #expect(list.summary == summary)
        #expect(try fixture.count(ItemModel.self) == 3)
    }

    @Test("Undo after the group was deleted does nothing")
    func restoreWithoutGroup() throws {
        let fixture = try StoreFixture()
        let (list, group) = fixture.makeGroup()
        let item = fixture.addItem("A", to: group)
        let snapshot = ItemSnapshot(item)
        fixture.store.deleteGroup(group)

        #expect(fixture.store.restoreItem(snapshot, in: list) == nil)
        #expect(try fixture.count(ItemModel.self) == 0)
    }
}
