//
//  StoreFixture.swift
//  Project2Tests
//
//  A fresh in-memory SwiftData stack per test: never the on-disk store and
//  never the shared `SampleData` singleton, so tests can't see each other's data.
//

import Foundation
import SwiftData
@testable import Project2

@MainActor
struct StoreFixture {
    /// Kept alive for the whole test: a `ModelContext` stops working without its container.
    let container: ModelContainer
    let clock: TestClock
    let store: PlannerStore

    var context: ModelContext { container.mainContext }

    init(currency: String = "USD") throws {
        container = try Persistence.makeContainer(inMemory: true)
        let clock = TestClock()
        self.clock = clock
        store = PlannerStore(context: container.mainContext, defaultCurrencyCode: currency, now: { clock.now })
    }

    /// Number of saved objects of a type (used for cascade checks, DM-08).
    func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }

    /// A list with one group, ready for item tests.
    func makeGroup(listName: String = "List", groupName: String = "Group") -> (ListModel, GroupModel) {
        let list = store.createList(name: listName)
        let group = store.createGroup(name: groupName, in: list)
        return (list, group)
    }

    /// Adds an item and fails loudly if the store rejected it.
    @discardableResult
    func addItem(_ name: String, to group: GroupModel, quantity: Int = 1, price: Decimal? = nil) -> ItemModel {
        guard let item = store.addItem(name: name, to: group, quantity: quantity, price: price) else {
            preconditionFailure("addItem rejected \(name)")
        }
        return item
    }
}
