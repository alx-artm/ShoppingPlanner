//
//  TipJarTests.swift
//  Project2Tests
//
//  Spec 12 with a fake `TipJarStore` (TJ-26, fake part): the flag keeps StoreKit
//  untouched (TJ-02), loading / error / empty states (TJ-05, TJ-07...TJ-09),
//  purchase outcomes (TJ-11, TJ-13, TJ-15), no double purchase (TJ-16), the
//  "has tipped" mark (TJ-18, TJ-19) and the updates listener (TJ-14).
//
//  Every test gets its own UserDefaults suite, never `.standard`.
//

import Foundation
import StoreKit
import Testing
@testable import Project2

extension Tag {
    /// Tip Jar: StoreKit service, states, flag (spec 12, TJ-xx).
    @Tag static var tipJar: Self
}

/// Counts calls and answers what the test scripted.
@MainActor
final class FakeTipJarStore: TipJarStore {
    struct Failure: Error {}

    var loadResults: [Result<[TipProduct], any Error>] = []
    var purchaseResult: Result<TipPurchaseOutcome, any Error> = .success(.success)
    /// When `true`, `purchase` waits until `resumePurchase()`.
    var holdsPurchase = false

    private(set) var loadCount = 0
    private(set) var purchaseCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var onUpdate: (@MainActor (TipPurchaseOutcome) -> Void)?
    private var heldPurchase: CheckedContinuation<Void, Never>?

    func loadProducts() async throws -> [TipProduct] {
        loadCount += 1
        let result = loadResults.isEmpty ? .success(FakeTipJarStore.allProducts) : loadResults.removeFirst()
        return try result.get()
    }

    func purchase(_ product: TipProduct) async throws -> TipPurchaseOutcome {
        purchaseCount += 1
        if holdsPurchase {
            await withCheckedContinuation { heldPurchase = $0 }
        }
        return try purchaseResult.get()
    }

    func resumePurchase() {
        heldPurchase?.resume()
        heldPurchase = nil
    }

    func startListening(_ onUpdate: @escaping @MainActor (TipPurchaseOutcome) -> Void) {
        startCount += 1
        self.onUpdate = onUpdate
    }

    func stopListening() {
        stopCount += 1
        onUpdate = nil
    }

    static func product(_ kind: TipKind, _ price: Decimal) -> TipProduct {
        TipProduct(id: kind.productID, displayName: kind.rawValue, displayPrice: "$\(price)", price: price)
    }

    /// Most expensive first, so sorting is visible.
    static let allProducts = [product(.bigThanks, 5.99), product(.coffee, 0.99), product(.lunch, 2.99)]
}

@MainActor
@Suite("Tip Jar (fake store)", .tags(.tipJar))
final class TipJarTests {
    private let suiteName = "TipJarTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let store = FakeTipJarStore()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeTipJar() -> TipJar {
        TipJar(store: store, defaults: defaults)
    }

    /// Lets queued main-actor work (a started purchase Task) run up to its first suspension.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - Flag

    @Test("TJ-02 flag off: no store is created, no listener, no product request")
    func flagOffTouchesNothing() {
        var storesMade = 0
        let tipJar = TipJar.forLaunch(isEnabled: false, defaults: defaults) {
            storesMade += 1
            return store
        }
        #expect(tipJar == nil)
        #expect(storesMade == 0)
        #expect(store.startCount == 0)
        #expect(store.loadCount == 0)
    }

    @Test("TJ-14 flag on: the listener starts once at launch, products load only on the screen")
    func flagOnStartsListenerOnce() throws {
        let tipJar = try #require(TipJar.forLaunch(isEnabled: true, defaults: defaults) { store })
        tipJar.startListening()
        #expect(store.startCount == 1)
        #expect(store.loadCount == 0)
        tipJar.stopListening()
        #expect(store.stopCount == 1)
    }

    @Test("TJ-01 / TJ-03 the flag is off in this build; -UITestsTipJar needs -UITests")
    func flagArguments() {
        #expect(TipJarConfig.isTipJarEnabled == false)
        #expect(TipJarConfig.isEnabled(arguments: []) == false)
        #expect(TipJarConfig.isEnabled(arguments: ["-UITestsTipJar"]) == false)
        #expect(TipJarConfig.isEnabled(arguments: ["-UITests"]) == false)
        #expect(TipJarConfig.isEnabled(arguments: ["-UITests", "-UITestsTipJar"]) == true)
    }

    @Test("Product IDs: <bundleID>.tip.<name>, round-trip to TipKind")
    func productIDs() {
        #expect(TipKind.coffee.productID.hasSuffix(".tip.coffee"))
        #expect(TipKind.lunch.productID.hasSuffix(".tip.lunch"))
        #expect(TipKind.bigThanks.productID.hasSuffix(".tip.bigthanks"))
        for kind in TipKind.allCases {
            #expect(TipKind(productID: kind.productID) == kind)
        }
        #expect(TipKind(productID: "com.other.tip.coffee") == nil)
    }

    // MARK: - Loading

    @Test("TJ-05 three products, one request, cheapest first")
    func loadSortsByPrice() async {
        let tipJar = makeTipJar()
        await tipJar.loadProductsIfNeeded()
        #expect(store.loadCount == 1)
        #expect(tipJar.phase == .loaded)
        #expect(tipJar.products.map(\.kind) == [.coffee, .lunch, .bigThanks])

        // A second appearance doesn't reload.
        await tipJar.loadProductsIfNeeded()
        #expect(store.loadCount == 1)
    }

    @Test("TJ-07 error → Try Again → loaded")
    func retryAfterError() async {
        store.loadResults = [.failure(FakeTipJarStore.Failure()), .success(FakeTipJarStore.allProducts)]
        let tipJar = makeTipJar()
        await tipJar.loadProductsIfNeeded()
        #expect(tipJar.phase == .unavailable(.loadFailed))
        #expect(tipJar.products.isEmpty)

        await tipJar.loadProducts()
        #expect(store.loadCount == 2)
        #expect(tipJar.phase == .loaded)
        #expect(tipJar.products.count == 3)
    }

    @Test("TJ-08 no products → the error state, not an empty list")
    func emptyIsUnavailable() async {
        store.loadResults = [.success([])]
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        #expect(tipJar.phase == .unavailable(.noProducts))
    }

    @Test("TJ-09 a partial answer shows what came back")
    func partialProducts() async {
        store.loadResults = [.success([FakeTipJarStore.product(.lunch, 2.99)])]
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        #expect(tipJar.phase == .loaded)
        #expect(tipJar.products.map(\.kind) == [.lunch])
    }

    @Test("Unknown product IDs are ignored")
    func foreignProductsFiltered() {
        let foreign = TipProduct(id: "com.other.thing", displayName: "X", displayPrice: "$0.01", price: 0.01)
        let sorted = TipJar.sortedTips([foreign] + FakeTipJarStore.allProducts)
        #expect(sorted.map(\.kind) == [.coffee, .lunch, .bigThanks])
    }

    // MARK: - Purchase

    @Test("TJ-10 / TJ-18 success: thank-you, and the mark survives a relaunch")
    func successMarksTipped() async {
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        #expect(tipJar.hasTipped == false)

        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.showsThankYou)
        #expect(tipJar.hasTipped)
        #expect(tipJar.alert == nil)
        #expect(tipJar.isPurchasing == false)
        #expect(defaults.bool(forKey: "tipJar.hasTipped"))

        // "Relaunch": a new TipJar on the same defaults.
        #expect(makeTipJar().hasTipped)
    }

    @Test("TJ-19 tipping again is allowed and thanks again")
    func tipAgain() async {
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        tipJar.screenDidDisappear()
        #expect(tipJar.showsThankYou == false)

        await tipJar.purchase(tipJar.products[2])
        #expect(store.purchaseCount == 2)
        #expect(tipJar.showsThankYou)
    }

    @Test("TJ-11 unverified: no thank-you, no mark, the 'couldn't be verified' alert")
    func unverified() async {
        store.purchaseResult = .success(.failed(.unverified))
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.showsThankYou == false)
        #expect(tipJar.hasTipped == false)
        #expect(tipJar.alert == .unverified)
    }

    @Test("TJ-12 pending: 'Waiting for approval', no error, no thank-you")
    func pending() async {
        store.purchaseResult = .success(.pending)
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.isPending)
        #expect(tipJar.alert == nil)
        #expect(tipJar.showsThankYou == false)
        #expect(tipJar.hasTipped == false)
    }

    @Test("TJ-13 cancelled: nothing happens, buttons active again")
    func cancelled() async {
        store.purchaseResult = .success(.cancelled)
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.alert == nil)
        #expect(tipJar.showsThankYou == false)
        #expect(tipJar.isPending == false)
        #expect(tipJar.isPurchasing == false)
        #expect(tipJar.phase == .loaded)
    }

    @Test("TJ-15 a thrown purchase error shows 'Purchase failed', buttons active again")
    func thrownError() async {
        store.purchaseResult = .failure(StoreKitError.networkError(URLError(.notConnectedToInternet)))
        let tipJar = makeTipJar()
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.alert == .purchaseFailed)
        #expect(tipJar.hasTipped == false)
        #expect(tipJar.isPurchasing == false)
    }

    @Test("TJ-16 a second tap while buying starts no second purchase")
    func noDoublePurchase() async {
        store.holdsPurchase = true
        let tipJar = makeTipJar()
        await tipJar.loadProducts()

        let first = Task { await tipJar.purchase(tipJar.products[0]) }
        await waitUntil { store.purchaseCount == 1 }
        #expect(tipJar.purchasingProductID == TipKind.coffee.productID)
        #expect(tipJar.isPurchasing)

        await tipJar.purchase(tipJar.products[1])   // returns at once
        #expect(store.purchaseCount == 1)

        store.resumePurchase()
        await first.value
        #expect(tipJar.isPurchasing == false)
        #expect(tipJar.showsThankYou)
    }

    // MARK: - Transaction.updates

    @Test("TJ-14 a verified update marks tipped; thank-you only while the screen is open")
    func updates() async throws {
        let tipJar = try #require(TipJar.forLaunch(isEnabled: true, defaults: defaults) { store })
        let onUpdate = try #require(store.onUpdate)

        onUpdate(.success)
        #expect(tipJar.hasTipped)
        #expect(tipJar.showsThankYou == false, "screen closed: no thank-you")

        tipJar.isScreenVisible = true
        onUpdate(.success)
        #expect(tipJar.showsThankYou)
    }

    @Test("TJ-12 → TJ-14 pending, then approved via updates: pending clears, thank-you shows")
    func pendingThenApproved() async throws {
        store.purchaseResult = .success(.pending)
        let tipJar = try #require(TipJar.forLaunch(isEnabled: true, defaults: defaults) { store })
        tipJar.isScreenVisible = true
        await tipJar.loadProducts()
        await tipJar.purchase(tipJar.products[0])
        #expect(tipJar.isPending)

        let onUpdate = try #require(store.onUpdate)
        onUpdate(.success)
        #expect(tipJar.isPending == false)
        #expect(tipJar.showsThankYou)
        #expect(tipJar.hasTipped)
    }

    @Test("TJ-14 an unverified update is silent")
    func unverifiedUpdate() async throws {
        let tipJar = try #require(TipJar.forLaunch(isEnabled: true, defaults: defaults) { store })
        tipJar.isScreenVisible = true
        let onUpdate = try #require(store.onUpdate)
        onUpdate(.failed(.unverified))
        #expect(tipJar.alert == nil)
        #expect(tipJar.hasTipped == false)
        #expect(tipJar.showsThankYou == false)
    }

    // MARK: - Verification mapping

    @Test("TJ-10 verified → finish → .success")
    func verifiedMapping() async {
        var finished: [String] = []
        let outcome = await TipTransactionVerifier.outcome(for: VerificationResult.verified("t1")) {
            finished.append($0)
        }
        #expect(outcome == .success)
        #expect(finished == ["t1"])
    }

    @Test("TJ-11 unverified → finish is still called → .failed(.unverified)")
    func unverifiedMapping() async {
        var finished: [String] = []
        let result = VerificationResult<String>.unverified("t2", .invalidSignature)
        let outcome = await TipTransactionVerifier.outcome(for: result) { finished.append($0) }
        #expect(outcome == .failed(.unverified))
        #expect(finished == ["t2"])
    }
}
