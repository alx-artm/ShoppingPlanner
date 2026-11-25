//
//  TipJarStoreKitTests.swift
//  Project2Tests
//
//  Spec 12 TJ-26, StoreKit part: the real `StoreKitTipJarStore` against
//  `TipJar.storekit` in a local `SKTestSession` (no App Store Connect, no network,
//  no purchase sheet: `disableDialogs`). Covers TJ-05, TJ-10, TJ-12, TJ-14, TJ-15.
//
//  `.serialized`: the StoreKit test environment is one per simulator, so these
//  tests must not overlap. Each test starts from `clearTransactions()`.
//
//  Skipped (not failed) where `SKTestSession` has no effect: with Xcode 27.2 the
//  iOS 26.5 simulator runtime (CI's pinned pair) returns no storefront and no
//  products, while the iOS 27.2 runtime works. The fake-store suite (`TipJarTests`)
//  still covers the same rules everywhere.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Project2

/// Whether this simulator honours `SKTestSession` (see the header).
enum StoreKitTestSupport {
    static let isAvailable: Bool = {
        guard let session = try? SKTestSession(configurationFileNamed: "TipJar") else { return false }
        return !session.storefront.isEmpty
    }()
}

@MainActor
@Suite("Tip Jar (StoreKit test session)", .serialized, .tags(.tipJar),
       .enabled(if: StoreKitTestSupport.isAvailable,
                "SKTestSession has no effect on this simulator runtime (no storefront)"))
final class TipJarStoreKitTests {
    private let suiteName = "TipJarStoreKitTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let session: SKTestSession
    private let store = StoreKitTipJarStore(productIDs: TipKind.allCases.map(\.productID))

    init() async throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        session = try SKTestSession(configurationFileNamed: "TipJar")
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func loadedTipJar() async throws -> TipJar {
        let tipJar = TipJar(store: store, defaults: defaults)
        await tipJar.loadProducts()
        try #require(tipJar.phase == .loaded)
        return tipJar
    }

    private func product(_ kind: TipKind, in tipJar: TipJar) throws -> TipProduct {
        try #require(tipJar.products.first { $0.kind == kind })
    }

    /// Unfinished tip transactions left in the session (consumables disappear once finished).
    private func unfinishedTipCount() async -> Int {
        var count = 0
        for await result in Transaction.unfinished where TipKind(productID: result.unsafePayloadValue.productID) != nil {
            count += 1
        }
        return count
    }

    /// Polls (no sleep-and-hope) until `condition` holds or ~10 s pass.
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test("TJ-05 three products from TipJar.storekit, cheapest first, names and prices from StoreKit")
    func loadFromConfig() async throws {
        let tipJar = try await loadedTipJar()
        #expect(tipJar.products.map(\.kind) == [.coffee, .lunch, .bigThanks])
        #expect(tipJar.products.map(\.displayName) == ["Coffee", "Lunch", "Big Thanks"])
        #expect(tipJar.products.map(\.displayPrice) == ["$0.99", "$2.99", "$5.99"])
    }

    @Test("TJ-10 verified purchase: finished, marked, thank-you")
    func purchaseCoffee() async throws {
        let tipJar = try await loadedTipJar()
        await tipJar.purchase(try product(.coffee, in: tipJar))
        #expect(tipJar.showsThankYou)
        #expect(tipJar.hasTipped)
        #expect(tipJar.alert == nil)
        #expect(await unfinishedTipCount() == 0)
        #expect(session.allTransactions().contains { $0.productIdentifier == TipKind.coffee.productID })
    }

    @Test("TJ-12 / TJ-14 Ask to Buy: pending, then approved via Transaction.updates")
    func askToBuy() async throws {
        session.askToBuyEnabled = true
        let tipJar = try await loadedTipJar()
        tipJar.startListening()
        defer { tipJar.stopListening() }
        tipJar.isScreenVisible = true

        await tipJar.purchase(try product(.lunch, in: tipJar))
        #expect(tipJar.isPending)
        #expect(tipJar.hasTipped == false)
        #expect(tipJar.showsThankYou == false)

        let waiting = try #require(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: waiting.identifier)

        try await eventually { tipJar.hasTipped }
        #expect(tipJar.hasTipped)
        #expect(tipJar.isPending == false)
        #expect(tipJar.showsThankYou)
        #expect(await unfinishedTipCount() == 0)
    }

    @Test("TJ-15 a failing purchase: 'Purchase failed' alert, not marked")
    func failedPurchase() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let tipJar = try await loadedTipJar()
        await tipJar.purchase(try product(.bigThanks, in: tipJar))
        #expect(tipJar.alert == .purchaseFailed)
        #expect(tipJar.hasTipped == false)
        #expect(tipJar.isPurchasing == false)
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }
}
