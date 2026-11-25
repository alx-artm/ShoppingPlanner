//
//  TipJar.swift
//  Project2
//
//  Spec 12: the Tip Jar's state (products, purchase in flight, pending, thank-you)
//  and the "has tipped" mark. All the rules live here, not in the views, so the
//  unit tests drive them with a fake `TipJarStore`.
//
//  `hasTipped` is a device-local mark in UserDefaults (`tipJar.hasTipped`): never
//  synced, never sent anywhere, reset when the app is deleted (TJ-18). Tips unlock
//  nothing, so only `SettingsView` and `TipJarView` read it (TJ-17).
//

import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class TipJar {
    nonisolated static let hasTippedKey = "tipJar.hasTipped"

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// Shown with "Try Again" (TJ-07, TJ-08).
        case unavailable(Unavailable)
    }

    enum Unavailable: Equatable {
        /// `loadProducts()` threw: offline or a StoreKit error.
        case loadFailed
        /// No products came back (IDs unknown, IAPs not approved yet).
        case noProducts
    }

    enum Alert: Equatable, Identifiable {
        case purchaseFailed
        case unverified

        var id: Self { self }
    }

    private(set) var phase: Phase = .idle
    /// Cheapest first (TJ-05).
    private(set) var products: [TipProduct] = []
    /// The product being bought; while set, every buy button is disabled (TJ-16).
    private(set) var purchasingProductID: String?
    /// "Waiting for approval" (TJ-12).
    private(set) var isPending = false
    /// The thank-you card (TJ-10, TJ-19).
    private(set) var showsThankYou = false
    var alert: Alert?

    private(set) var hasTipped: Bool {
        didSet { defaults.set(hasTipped, forKey: Self.hasTippedKey) }
    }

    /// Set by `TipJarView` while it's on screen: an update from `Transaction.updates`
    /// shows the thank-you only there (TJ-14).
    var isScreenVisible = false

    var isPurchasing: Bool { purchasingProductID != nil }

    @ObservationIgnored private let store: any TipJarStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2",
                                                    category: "TipJar")

    init(store: any TipJarStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        hasTipped = defaults.bool(forKey: Self.hasTippedKey)
    }

    /// The Tip Jar of this launch: `nil` when the flag is off, and then the store is never
    /// even created, so nothing touches StoreKit (TJ-01, TJ-02). Otherwise the
    /// `Transaction.updates` listener starts here, once per launch (TJ-14).
    static func forLaunch(isEnabled: Bool,
                          defaults: UserDefaults = .standard,
                          makeStore: () -> any TipJarStore) -> TipJar? {
        guard isEnabled else { return nil }
        let tipJar = TipJar(store: makeStore(), defaults: defaults)
        tipJar.startListening()
        return tipJar
    }

    /// Emptied every call: UI tests start without the "has tipped" mark.
    static func volatileDefaults() -> UserDefaults {
        let suiteName = "TipJar.volatile"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Starts the app-lifetime listener; a second call does nothing.
    func startListening() {
        guard !isListening else { return }
        isListening = true
        store.startListening { [weak self] outcome in
            self?.apply(outcome, fromUpdates: true)
        }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        store.stopListening()
    }

    /// On the screen's first appearance; after an error "Try Again" calls `loadProducts()`.
    func loadProductsIfNeeded() async {
        guard phase == .idle else { return }
        await loadProducts()
    }

    func loadProducts() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let loaded = try await store.loadProducts()
            let tips = Self.sortedTips(loaded)
            products = tips
            if tips.isEmpty {
                phase = .unavailable(.noProducts)
            } else {
                // TJ-09: a partial answer shows what came back; only the log knows.
                if tips.count < TipKind.allCases.count {
                    #if DEBUG
                    logger.warning("Tip Jar: \(tips.count, privacy: .public) of \(TipKind.allCases.count, privacy: .public) products loaded")
                    #endif
                }
                phase = .loaded
            }
        } catch {
            products = []
            phase = .unavailable(.loadFailed)
        }
    }

    /// Our tips only, cheapest first (TJ-05).
    nonisolated static func sortedTips(_ products: [TipProduct]) -> [TipProduct] {
        products
            .filter { $0.kind != nil }
            .sorted { $0.price < $1.price }
    }

    func purchase(_ product: TipProduct) async {
        // TJ-16: a second tap while a purchase is running does nothing.
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        showsThankYou = false
        isPending = false
        defer { purchasingProductID = nil }
        do {
            apply(try await store.purchase(product), fromUpdates: false)
        } catch {
            // TJ-15: StoreKitError / Product.PurchaseError.
            alert = .purchaseFailed
        }
    }

    /// The thank-you card was read; the next screen visit starts clean.
    func screenDidDisappear() {
        isScreenVisible = false
        showsThankYou = false
    }

    private func apply(_ outcome: TipPurchaseOutcome, fromUpdates: Bool) {
        switch outcome {
        case .success:
            hasTipped = true
            isPending = false
            if !fromUpdates || isScreenVisible {
                showsThankYou = true
                AccessibilityNotification.Announcement(String(localized: "Thank you! Your support means a lot.")).post()
            }
        case .pending:
            isPending = true
        case .cancelled:
            break
        case .failed(.unverified):
            // A late unverified update is finished silently (TJ-14).
            if !fromUpdates { alert = .unverified }
        case .failed(.failed):
            if !fromUpdates { alert = .purchaseFailed }
        }
    }
}
