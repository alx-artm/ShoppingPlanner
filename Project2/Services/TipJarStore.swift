//
//  TipJarStore.swift
//  Project2
//
//  Spec 12 "Сервис TipJarStore": the only place that talks to StoreKit. Views and
//  `TipJar` see `TipProduct` and `TipPurchaseOutcome`, never `Product` or
//  `Transaction`, so unit tests swap in a fake and UI tests a scripted store.
//

import Foundation
import StoreKit

/// A tip as the UI shows it: name and price come from the App Store (TJ-05, TJ-22).
struct TipProduct: Identifiable, Equatable, Sendable {
    /// The product ID.
    let id: String
    let displayName: String
    /// Localized by the App Store (`product.displayPrice`), never hard-coded.
    let displayPrice: String
    /// Sort key: rows go cheapest first (TJ-05).
    let price: Decimal

    var kind: TipKind? { TipKind(productID: id) }
}

enum TipPurchaseFailure: Equatable, Sendable {
    /// The App Store's signature didn't verify (TJ-11). The transaction is finished anyway.
    case unverified
    /// The purchase didn't go through (TJ-15).
    case failed
}

enum TipPurchaseOutcome: Equatable, Sendable {
    /// Verified, and `finish()` was already called (TJ-10).
    case success
    /// Ask to Buy / Strong Customer Authentication: comes later via `Transaction.updates` (TJ-12).
    case pending
    /// The user closed the purchase sheet (TJ-13).
    case cancelled
    case failed(TipPurchaseFailure)
}

@MainActor
protocol TipJarStore: AnyObject {
    /// All tip products in one request (TJ-05). Order is not guaranteed.
    func loadProducts() async throws -> [TipProduct]
    /// Buys a product returned by `loadProducts()`. Store errors are thrown (TJ-15).
    func purchase(_ product: TipProduct) async throws -> TipPurchaseOutcome
    /// Starts the app-lifetime listener of `Transaction.updates` (TJ-14). Each tip
    /// transaction is finished before `onUpdate` gets its outcome.
    func startListening(_ onUpdate: @escaping @MainActor (TipPurchaseOutcome) -> Void)
    func stopListening()
}

/// `VerificationResult → TipPurchaseOutcome` (TJ-10, TJ-11). Generic with an injected
/// `finish`, so a unit test checks both branches without a signed transaction.
@MainActor
enum TipTransactionVerifier {
    static func outcome<Signed: Sendable>(for result: VerificationResult<Signed>,
                                finish: (Signed) async -> Void) async -> TipPurchaseOutcome {
        switch result {
        case .verified(let transaction):
            await finish(transaction)
            return .success
        case .unverified(let transaction, _):
            // Finished too: otherwise it stays unfinished and comes back on every launch.
            await finish(transaction)
            return .failed(.unverified)
        }
    }
}

/// StoreKit 2 implementation (spec 12).
@MainActor
final class StoreKitTipJarStore: TipJarStore {
    private let productIDs: [String]
    /// Products of the last `loadProducts()`, by ID: `purchase` needs the StoreKit value.
    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    init(productIDs: [String]) {
        self.productIDs = productIDs
    }

    func loadProducts() async throws -> [TipProduct] {
        let loaded = try await Product.products(for: productIDs)
        products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return loaded.map {
            TipProduct(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice, price: $0.price)
        }
    }

    func purchase(_ tip: TipProduct) async throws -> TipPurchaseOutcome {
        guard let product = products[tip.id] else { return .failed(.failed) }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch StoreKitError.userCancelled {
            return .cancelled
        }
        switch result {
        case .success(let verification):
            return await TipTransactionVerifier.outcome(for: verification) { await $0.finish() }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .failed(.failed)
        }
    }

    func startListening(_ onUpdate: @escaping @MainActor (TipPurchaseOutcome) -> Void) {
        guard updatesTask == nil else { return }
        let tipIDs = Set(productIDs)
        updatesTask = Task {
            for await update in Transaction.updates {
                // Only our tips; any other product (none today) is left to its own code.
                guard tipIDs.contains(update.unsafePayloadValue.productID) else { continue }
                let outcome = await TipTransactionVerifier.outcome(for: update) { await $0.finish() }
                onUpdate(outcome)
            }
        }
    }

    func stopListening() {
        updatesTask?.cancel()
        updatesTask = nil
    }
}

#if DEBUG
/// UI tests only (`-UITests -UITestsTipJar -UITestsTipJarScenario <scenario>`): fixed
/// products and a scripted purchase result, no StoreKit and no system purchase sheet.
@MainActor
final class ScriptedTipJarStore: TipJarStore {
    enum Scenario: String {
        case success, cancel, pending, failed, unverified
        /// The first `loadProducts()` throws, the retry succeeds (TJ-07).
        case loadError
        /// No products come back (TJ-08).
        case empty
        /// `loadProducts()` never finishes, the loading state stays (TJ-06).
        case slowLoad
    }

    private struct LoadFailed: Error {}

    private let scenario: Scenario
    private var loadCount = 0

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func loadProducts() async throws -> [TipProduct] {
        loadCount += 1
        switch scenario {
        case .loadError where loadCount == 1:
            throw LoadFailed()
        case .empty:
            return []
        case .slowLoad:
            try await Task.sleep(for: .seconds(3600))
        default:
            break
        }
        // Reverse order on purpose: the screen must sort them by price.
        return [
            TipProduct(id: TipKind.bigThanks.productID, displayName: "Big Thanks", displayPrice: "$5.99", price: 5.99),
            TipProduct(id: TipKind.lunch.productID, displayName: "Lunch", displayPrice: "$2.99", price: 2.99),
            TipProduct(id: TipKind.coffee.productID, displayName: "Coffee", displayPrice: "$0.99", price: 0.99),
        ]
    }

    func purchase(_ product: TipProduct) async throws -> TipPurchaseOutcome {
        switch scenario {
        case .cancel: return .cancelled
        case .pending: return .pending
        case .failed: throw StoreKitError.networkError(URLError(.notConnectedToInternet))
        case .unverified: return .failed(.unverified)
        case .success, .loadError, .empty, .slowLoad: return .success
        }
    }

    func startListening(_ onUpdate: @escaping @MainActor (TipPurchaseOutcome) -> Void) {}
    func stopListening() {}
}
#endif
