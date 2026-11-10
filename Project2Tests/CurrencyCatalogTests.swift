//
//  CurrencyCatalogTests.swift
//  Project2Tests
//
//  Spec 07 SC-01, SC-03, SC-04: main currency default, picker sections and
//  search. `CurrencyCatalog` is a set of pure functions of a `Locale`, so each
//  test passes a fixed locale and never depends on the machine's region.
//

import Foundation
import Testing
@testable import Project2

@Suite("CurrencyCatalog", .tags(.settings))
struct CurrencyCatalogTests {

    static let specPopular = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CAD", "AUD", "CHF", "SEK", "NOK",
        "DKK", "PLN", "CZK", "TRY", "INR", "BRL", "MXN", "UAH", "KZT", "RUB",
    ]

    // MARK: - SC-01 region default

    @Test("SC-01 the region's currency is the default", arguments: [
        ("en_US", "USD"), ("ru_RU", "RUB"), ("de_DE", "EUR"), ("fr_FR", "EUR"),
        ("ja_JP", "JPY"), ("en_GB", "GBP"), ("de_CH", "CHF"), ("uk_UA", "UAH"),
        ("kk_KZ", "KZT"), ("pt_BR", "BRL"), ("th_TH", "THB"),
    ])
    func regionDefault(locale: String, expected: String) {
        #expect(CurrencyCatalog.defaultCode(for: Locale(identifier: locale)) == expected)
    }

    /// No region ("en"), a multi-country region ("en_001" world, "es_419" Latin America),
    /// or a region whose currency is the ISO "no currency" code XXX (Antarctica).
    @Test("SC-01 a region without a valid currency falls back to USD",
          arguments: ["en", "ru", "en_001", "es_419", "en_AQ"])
    func fallback(locale: String) {
        #expect(CurrencyCatalog.defaultCode(for: Locale(identifier: locale)) == "USD")
        #expect(CurrencyCatalog.fallbackCode == "USD")
    }

    @Test("SC-01 a valid stored choice wins over the locale, case-insensitively", arguments: [
        ("EUR", "ru_RU", "EUR"),
        ("eur", "ru_RU", "EUR"),
        ("JPY", "en_US", "JPY"),
    ])
    func storedChoiceWins(stored: String, locale: String, expected: String) {
        #expect(CurrencyCatalog.resolvedMainCurrency(stored: stored, locale: Locale(identifier: locale)) == expected)
    }

    /// nil = first launch; the others are corrupted / historic / non-currency values.
    @Test("SC-01 a missing or invalid stored value resolves to the region default",
          arguments: [nil, "", "  ", "DEM", "XXX", "EURO", "€"] as [String?])
    func invalidStoredValue(stored: String?) {
        #expect(CurrencyCatalog.resolvedMainCurrency(stored: stored, locale: Locale(identifier: "de_DE")) == "EUR")
        #expect(CurrencyCatalog.resolvedMainCurrency(stored: stored, locale: Locale(identifier: "en")) == "USD")
    }

    @Test("Active codes contain current currencies but not historic ones")
    func activeCodes() {
        for code in Self.specPopular {
            #expect(CurrencyCatalog.isActive(code), "\(code)")
        }
        for historic in ["DEM", "FRF", "ITL", "XXX"] {
            #expect(!CurrencyCatalog.isActive(historic), "\(historic)")
        }
        #expect(CurrencyCatalog.activeCodes.allSatisfy { $0.count == 3 && $0 == $0.uppercased() })
    }

    // MARK: - SC-04 popular list and sections

    @Test("SC-04 Popular is exactly the 20 spec currencies, in spec order, without duplicates")
    func popularCatalogue() {
        #expect(CurrencyCatalog.popularCodes == Self.specPopular)
        #expect(Set(CurrencyCatalog.popularCodes).count == 20)
    }

    /// Open spec question: SC-04 says both "exactly 20 in Popular" and "the region
    /// currency is not repeated in Popular". When the region currency is one of the
    /// 20, both can't hold. Current behaviour: no duplicate wins, Popular shows 19.
    @Test("SC-04 a popular region currency moves to Suggested; Popular shows the other 19",
          arguments: ["en_US", "ru_RU", "de_DE", "ja_JP"])
    func popularRegionCurrency(locale identifier: String) {
        let locale = Locale(identifier: identifier)
        let regional = CurrencyCatalog.defaultCode(for: locale)
        let sections = CurrencyCatalog.sections(locale: locale)

        #expect(sections.suggested == [regional])
        #expect(sections.popular == Self.specPopular.filter { $0 != regional })
        #expect(sections.popular.count == 19)
    }

    @Test("SC-04 a non-popular region currency is Suggested and Popular keeps all 20",
          arguments: ["th_TH", "ko_KR"])
    func nonPopularRegionCurrency(locale identifier: String) {
        let locale = Locale(identifier: identifier)
        let sections = CurrencyCatalog.sections(locale: locale)

        #expect(sections.suggested == [CurrencyCatalog.defaultCode(for: locale)])
        #expect(sections.popular == Self.specPopular)
    }

    @Test("SC-04 a region without currency has no Suggested section", arguments: ["en", "en_001", "en_AQ"])
    func noSuggested(locale identifier: String) {
        let sections = CurrencyCatalog.sections(locale: Locale(identifier: identifier))
        #expect(sections.suggested.isEmpty)
        #expect(sections.popular == Self.specPopular)
    }

    @Test("SC-03/SC-04 every active code appears in exactly one section",
          arguments: ["en_US", "ru_RU", "th_TH", "en_001"])
    func sectionsPartitionActiveCodes(locale identifier: String) {
        let sections = CurrencyCatalog.sections(locale: Locale(identifier: identifier))
        let everything = sections.suggested + sections.popular + sections.all

        #expect(everything.count == Set(everything).count, "a code is shown twice")
        #expect(Set(everything) == CurrencyCatalog.activeCodes)
        #expect(sections.all.count > 100)
    }

    @Test("SC-03 All Currencies is sorted by the name in the interface language",
          arguments: ["en_US", "ru_RU"])
    func allSortedByName(locale identifier: String) {
        let locale = Locale(identifier: identifier)
        let names = CurrencyCatalog.sections(locale: locale).all.map { CurrencyCatalog.displayName(of: $0, locale: locale) }
        let isSorted = zip(names, names.dropFirst()).allSatisfy { $0.localizedStandardCompare($1) != .orderedDescending }
        #expect(isSorted)
    }

    // MARK: - SC-03 search

    struct SearchCase: CustomTestStringConvertible, Sendable {
        let code: String
        let query: String
        let locale: String
        let matches: Bool

        var testDescription: String { "\"\(query)\" \(matches ? "finds" : "doesn't find") \(code) in \(locale)" }
    }

    static let searchCases: [SearchCase] = [
        // The three queries written in SC-03.
        SearchCase(code: "EUR", query: "eur", locale: "en_US", matches: true),
        SearchCase(code: "EUR", query: "евро", locale: "ru_RU", matches: true),
        SearchCase(code: "EUR", query: "€", locale: "en_US", matches: true),
        // Case-insensitive on code and name.
        SearchCase(code: "EUR", query: "EUR", locale: "en_US", matches: true),
        SearchCase(code: "EUR", query: "EURO", locale: "en_US", matches: true),
        SearchCase(code: "EUR", query: "ЕВРО", locale: "ru_RU", matches: true),
        SearchCase(code: "GBP", query: "pound", locale: "en_US", matches: true),
        SearchCase(code: "JPY", query: "yen", locale: "en_US", matches: true),
        SearchCase(code: "JPY", query: "¥", locale: "en_US", matches: true),
        SearchCase(code: "USD", query: "$", locale: "en_US", matches: true),
        SearchCase(code: "CHF", query: "franc", locale: "en_US", matches: true),
        // The name is matched in the interface language only.
        SearchCase(code: "EUR", query: "евро", locale: "en_US", matches: false),
        SearchCase(code: "USD", query: "eur", locale: "en_US", matches: false),
        SearchCase(code: "EUR", query: "zzz", locale: "en_US", matches: false),
    ]

    @Test("SC-03 matches by code, localized name or symbol", arguments: searchCases)
    func search(_ c: SearchCase) {
        #expect(CurrencyCatalog.matches(c.code, query: c.query, locale: Locale(identifier: c.locale)) == c.matches)
    }

    @Test("SC-03 searching \"eur\", \"евро\", \"€\" puts EUR in the filtered sections", arguments: [
        ("eur", "en_US"), ("  eur \n", "en_US"), ("евро", "ru_RU"), ("€", "en_US"), ("€", "ru_RU"),
    ])
    func filteredSectionsContainEuro(query: String, locale identifier: String) {
        let sections = CurrencyCatalog.sections(locale: Locale(identifier: identifier), query: query)
        let shown = sections.suggested + sections.popular + sections.all
        #expect(shown.contains("EUR"))
        #expect(shown.count == Set(shown).count)
    }

    @Test("SC-03 the region currency stays in Suggested while it matches the query")
    func filteredSuggested() {
        let sections = CurrencyCatalog.sections(locale: Locale(identifier: "de_DE"), query: "eur")
        #expect(sections.suggested == ["EUR"])
        #expect(!sections.popular.contains("EUR"))
    }

    @Test("SC-03 a query that matches nothing gives empty sections; blank query shows everything")
    func emptyAndBlankQuery() {
        let locale = Locale(identifier: "en_US")
        #expect(CurrencyCatalog.sections(locale: locale, query: "qwertyuiop").isEmpty)
        #expect(CurrencyCatalog.sections(locale: locale, query: "   ") == CurrencyCatalog.sections(locale: locale))
    }

    // MARK: - Row title

    @Test("Picker row is \"Name · CODE · symbol\"; the symbol is dropped when it equals the code", arguments: [
        ("EUR", "en_US", "Euro · EUR · €"),
        ("USD", "en_US", "US Dollar · USD · $"),
        ("JPY", "en_US", "Japanese Yen · JPY · ¥"),
        ("CHF", "en_US", "Swiss Franc · CHF"),
        ("EUR", "ru_RU", "евро · EUR · €"),
    ])
    func rowTitle(code: String, locale: String, expected: String) {
        #expect(CurrencyCatalog.rowTitle(of: code, locale: Locale(identifier: locale)) == expected)
    }
}
