//
//  CurrencyCatalog.swift
//  Project2
//
//  Which currencies exist, which one is the default, and how the currency
//  picker lists and searches them (spec 07 SC-01, SC-03, SC-04).
//
//  Pure functions of a `Locale`: the app passes `Locale.current`, tests pass a
//  fixed one (e.g. `ru_RU`), so results don't depend on the machine's settings.
//

import Foundation

enum CurrencyCatalog {
    /// Used when the region has no (valid) currency (SC-01).
    static let fallbackCode = ListModel.fallbackCurrencyCode

    /// The "Popular" section, in this order (SC-04).
    static let popularCodes = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CAD", "AUD", "CHF", "SEK", "NOK",
        "DKK", "PLN", "CZK", "TRY", "INR", "BRL", "MXN", "UAH", "KZT", "RUB",
    ]

    /// ISO 4217 codes in current use. `Locale.Currency.isoCurrencies` also
    /// contains historic ones (DEM, FRF, …) that nobody should pick.
    static let activeCodes: Set<String> = Set(Locale.commonISOCurrencyCodes)

    static func isActive(_ code: String) -> Bool {
        activeCodes.contains(code)
    }

    // MARK: Main currency

    /// The currency of the locale's region, or USD when it has none or it isn't
    /// an active ISO 4217 code (SC-01).
    static func defaultCode(for locale: Locale) -> String {
        guard let code = locale.currency?.identifier.uppercased(), isActive(code) else {
            return fallbackCode
        }
        return code
    }

    /// The main currency to use: the stored choice when it is valid, otherwise
    /// the region default (first launch, or a corrupted value).
    static func resolvedMainCurrency(stored: String?, locale: Locale) -> String {
        if let stored = stored?.uppercased(), isActive(stored) {
            return stored
        }
        return defaultCode(for: locale)
    }

    // MARK: Picker

    struct Sections: Equatable, Sendable {
        /// The region's currency (empty when the region has none).
        var suggested: [String]
        var popular: [String]
        var all: [String]

        var isEmpty: Bool { suggested.isEmpty && popular.isEmpty && all.isEmpty }
    }

    /// Picker sections. A code appears in at most one section (SC-04):
    /// the region currency is not repeated in Popular, Popular codes are not
    /// repeated in All. `query` filters every section (SC-03).
    static func sections(locale: Locale, query: String = "") -> Sections {
        let regional = locale.currency.map { $0.identifier.uppercased() }.flatMap { isActive($0) ? $0 : nil }
        let suggested = regional.map { [$0] } ?? []
        let popular = popularCodes.filter { $0 != regional }
        let shown = Set(suggested + popular)
        // Sorted by name in the interface language; the name is computed once per code.
        let all = activeCodes.subtracting(shown)
            .map { (code: $0, name: displayName(of: $0, locale: locale)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.code)

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Sections(suggested: suggested, popular: popular, all: all)
        }
        let matching = { (codes: [String]) in codes.filter { matches($0, query: trimmed, locale: locale) } }
        return Sections(suggested: matching(suggested), popular: matching(popular), all: matching(all))
    }

    /// Search by code ("eur"), name in the interface language ("euro", "евро")
    /// or symbol ("€"); case- and diacritic-insensitive (SC-03).
    static func matches(_ code: String, query: String, locale: Locale) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return [code, displayName(of: code, locale: locale), symbol(of: code, locale: locale)]
            .contains { $0.range(of: query, options: options, locale: locale) != nil }
    }

    /// "Euro" in English, "евро" in Russian; the code itself when unknown.
    static func displayName(of code: String, locale: Locale) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Picker row: "Euro · EUR · €". The symbol is left out when it is just the code
    /// ("Swiss Franc · CHF", not "Swiss Franc · CHF · CHF").
    static func rowTitle(of code: String, locale: Locale) -> String {
        let symbol = symbol(of: code, locale: locale)
        let parts = [displayName(of: code, locale: locale), code] + (symbol == code ? [] : [symbol])
        return parts.joined(separator: " · ")
    }

    /// "€" for EUR; for currencies without a well-known symbol it is the code.
    static func symbol(of code: String, locale: Locale) -> String {
        var components = Locale.Components(locale: locale)
        components.currency = Locale.Currency(code)
        return Locale(components: components).currencySymbol ?? code
    }
}
