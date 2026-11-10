//
//  AppSettings.swift
//  Project2
//
//  Device settings that the data layer needs: the main currency (spec 07).
//
//  Stored in UserDefaults under `mainCurrencyKey` (SC-02): a setting of this
//  device, never synced. Each list keeps its own currency, so changing the main
//  currency only affects lists created afterwards (SC-05, SC-06).
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    nonisolated static let mainCurrencyKey = "mainCurrencyCode"

    @ObservationIgnored private let defaults: UserDefaults

    /// ISO 4217 code copied into every new list.
    var mainCurrencyCode: String {
        didSet { defaults.set(mainCurrencyCode, forKey: Self.mainCurrencyKey) }
    }

    /// - Parameter locale: decides the first-launch default (SC-01); injectable for tests.
    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.mainCurrencyKey)
        let resolved = CurrencyCatalog.resolvedMainCurrency(stored: stored, locale: locale)
        mainCurrencyCode = resolved
        // Fix the first-launch default, so a later region change doesn't silently switch it.
        if stored != resolved {
            defaults.set(resolved, forKey: Self.mainCurrencyKey)
        }
    }

    /// Volatile settings for previews and UI tests: starts from the locale default every time.
    static func inMemory(locale: Locale = .current) -> AppSettings {
        let suiteName = "AppSettings.inMemory"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults, locale: locale)
    }
}
