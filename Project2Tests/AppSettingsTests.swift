//
//  AppSettingsTests.swift
//  Project2Tests
//
//  Spec 07 SC-01 / SC-02: the main currency is decided once (first launch,
//  from the injected locale), stored in UserDefaults under "mainCurrencyCode"
//  and kept when the region changes later.
//
//  Every test gets its own UserDefaults suite with a random name, removed when
//  the test ends, so tests never touch `.standard` and never see each other.
//

import Foundation
import Testing
@testable import Project2

@MainActor
@Suite("AppSettings", .tags(.settings))
final class AppSettingsTests {
    private let suiteName = "AppSettingsTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private var stored: String? { defaults.string(forKey: AppSettings.mainCurrencyKey) }

    private func settings(_ locale: String) -> AppSettings {
        AppSettings(defaults: defaults, locale: Locale(identifier: locale))
    }

    @Test("SC-02 the setting is stored under the key \"mainCurrencyCode\"")
    func key() {
        #expect(AppSettings.mainCurrencyKey == "mainCurrencyCode")
    }

    @Test("SC-01 first launch uses the locale currency and saves it", arguments: [
        ("en_US", "USD"), ("ru_RU", "RUB"), ("de_DE", "EUR"), ("ja_JP", "JPY"), ("en", "USD"),
    ])
    func firstLaunch(locale: String, expected: String) {
        #expect(stored == nil, "fresh suite must be empty")

        #expect(settings(locale).mainCurrencyCode == expected)
        #expect(stored == expected, "the first-launch default is written, not only computed")
    }

    @Test("SC-01 a later region change does not override the saved currency")
    func regionChangeKeepsChoice() {
        _ = settings("ru_RU")                 // first launch in Russia → RUB saved
        let afterMove = settings("de_DE")     // the user moves to Germany

        #expect(afterMove.mainCurrencyCode == "RUB")
        #expect(stored == "RUB")
    }

    @Test("SC-02 a picked currency is saved immediately and read back on the next launch")
    func choicePersists() {
        let first = settings("en_US")
        first.mainCurrencyCode = "EUR"
        #expect(stored == "EUR")

        let nextLaunch = settings("en_US")
        #expect(nextLaunch.mainCurrencyCode == "EUR")
    }

    @Test("SC-01 a corrupted stored value is replaced by the locale default", arguments: ["DEM", "", "euro"])
    func corruptedValue(value: String) {
        defaults.set(value, forKey: AppSettings.mainCurrencyKey)

        #expect(settings("de_DE").mainCurrencyCode == "EUR")
        #expect(stored == "EUR")
    }

    @Test("SC-01 a lowercase stored code is accepted and normalised")
    func lowercaseStored() {
        defaults.set("gbp", forKey: AppSettings.mainCurrencyKey)

        #expect(settings("en_US").mainCurrencyCode == "GBP")
        #expect(stored == "GBP")
    }

    @Test("inMemory() starts from the locale default every time (UI tests, previews)")
    func inMemoryIsVolatile() {
        let first = AppSettings.inMemory(locale: Locale(identifier: "ja_JP"))
        first.mainCurrencyCode = "EUR"

        let second = AppSettings.inMemory(locale: Locale(identifier: "ja_JP"))
        #expect(second.mainCurrencyCode == "JPY")
    }
}

@Suite("AppVersion", .tags(.settings))
struct AppVersionTests {
    @Test("About shows \"version (build)\" from Info.plist", arguments: [
        (["CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"], "1.0 (7)"),
        (["CFBundleShortVersionString": "2.3.1"], "2.3.1"),
        (["CFBundleShortVersionString": "1.0", "CFBundleVersion": ""], "1.0"),
        ([:], "?"),
    ] as [([String: String], String)])
    func versionText(info: [String: String], expected: String) {
        #expect(AppVersion.text(from: info) == expected)
    }
}
