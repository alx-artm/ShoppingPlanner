//
//  MainCurrencyStoreTests.swift
//  Project2Tests
//
//  Spec 07 SC-05 / SC-06: a new list copies the main currency at the moment it
//  is created; changing the main currency later never touches existing lists.
//
//  Wired like the app (Project2App.make): the store reads the currency through
//  a closure over `AppSettings`. In-memory ModelContainer and a private
//  UserDefaults suite per test.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("Main currency in PlannerStore", .tags(.settings, .money))
final class MainCurrencyStoreTests {
    private let suiteName = "MainCurrencyStoreTests.\(UUID().uuidString)"
    let container: ModelContainer
    let settings: AppSettings
    let store: PlannerStore

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        // First launch in Germany → main currency EUR.
        let settings = AppSettings(defaults: defaults, locale: Locale(identifier: "de_DE"))
        self.settings = settings
        store = PlannerStore(
            context: container.mainContext,
            mainCurrencyCode: { settings.mainCurrencyCode },
            now: { SeedData.baseDate }
        )
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// A list with one priced item: 12.50 × 2 = 25.00.
    private func makePricedList(_ name: String) -> ListModel {
        let list = store.createList(name: name)
        let group = store.createGroup(name: "Food", in: list)
        store.addItem(name: "Cake", to: group, quantity: 2, price: dec("12.50"), urlString: "", notes: "")
        return list
    }

    private func fetchList(named name: String) throws -> ListModel {
        let descriptor = FetchDescriptor<ListModel>(predicate: #Predicate { $0.name == name })
        return try #require(try container.mainContext.fetch(descriptor).first)
    }

    @Test("SC-05 a new list gets the current main currency")
    func newListCopiesMainCurrency() {
        #expect(settings.mainCurrencyCode == "EUR")
        #expect(store.defaultCurrencyCode == "EUR")
        #expect(store.createList(name: "Berlin").currencyCode == "EUR")
    }

    @Test("SC-05 the main currency is read at creation time, without rebuilding the store")
    func changedSettingIsUsedForNextList() {
        let before = store.createList(name: "Before")
        settings.mainCurrencyCode = "JPY"
        let after = store.createList(name: "After")

        #expect(before.currencyCode == "EUR")
        #expect(after.currencyCode == "JPY")
    }

    @Test("SC-06 changing the main currency keeps the currency and totals of existing lists")
    func existingListsKeepCurrency() throws {
        let trip = makePricedList("Trip")
        let summaryBefore = trip.summary

        settings.mainCurrencyCode = "USD"
        let home = makePricedList("Home")

        let reloaded = try fetchList(named: "Trip")
        #expect(reloaded.currencyCode == "EUR")
        #expect(reloaded.summary == summaryBefore)
        #expect(reloaded.summary.planned == dec("25.00"))
        #expect(MoneyFormat.string(reloaded.summary.planned, currencyCode: reloaded.currencyCode,
                                   locale: Locale(identifier: "en_US")) == "€25.00")
        #expect(home.currencyCode == "USD")
        #expect(MoneyFormat.string(home.summary.planned, currencyCode: home.currencyCode,
                                   locale: Locale(identifier: "en_US")) == "$25.00")
    }

    @Test("SC-05 an explicit currency (template / Share Extension) wins over the main currency")
    func explicitCurrencyWins() {
        #expect(store.createList(name: "Tokyo", currencyCode: "JPY").currencyCode == "JPY")
    }

    @Test("SC-06 duplicating a list keeps the source currency, not the main one")
    func duplicateKeepsSourceCurrency() {
        let trip = makePricedList("Trip")
        settings.mainCurrencyCode = "GBP"

        let copy = store.duplicateList(trip)
        #expect(copy.currencyCode == "EUR")
        #expect(copy.summary.planned == trip.summary.planned)
    }
}
