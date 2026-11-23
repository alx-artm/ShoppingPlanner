//
//  TipJarUITests.swift
//  Project2UITests
//
//  Spec 12 end to end with `-UITests -UITestsTipJar`: the Settings section (TJ-04),
//  the three tips (TJ-05, TJ-27) and every purchase result. Purchases go through
//  `ScriptedTipJarStore` (`-UITestsTipJarScenario`), so there's no system purchase
//  sheet to drive and the tests are stable on CI. The real StoreKit flow is covered
//  by `TipJarStoreKitTests` (unit, SKTestSession) and `TipJarStoreKitUITests`.
//  TJ-01 / TJ-28 (no row without the flag) is checked in `SettingsUITests`.
//

import XCTest

final class TipJarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openTipJar(scenario: String, language: String = "en", region: String = "en_US") -> TipJarScreen {
        let app = Launch.app(language: language, region: region, tipJar: true, tipJarScenario: scenario)
        return HomeScreen(app: app).waitUntilShown().openSettings().openTipJar()
    }

    /// TJ-04: between iCloud and About, with the "doesn't unlock anything" footer.
    @MainActor
    func testSectionSitsBetweenICloudAndAbout() {
        let app = Launch.app(tipJar: true, tipJarScenario: "success")
        let settings = HomeScreen(app: app).waitUntilShown().openSettings()
        let list = app.collectionViews.firstMatch

        // About is below the section: once it's reachable, the footer above it is loaded too.
        settings.version.scrollIntoViewLazily(within: list)
        let row = settings.tipJarRow.waitToAppear()
        XCTAssertTrue(row.label.contains("Leave a Tip"), "row: \(row.label)")
        app.staticTexts["Tips don't unlock anything — the app stays free."].waitToAppear()
        XCTAssertLessThan(settings.icloudStatus.frame.minY, row.frame.minY)
        XCTAssertLessThan(row.frame.maxY, settings.version.frame.minY)
    }

    /// TJ-05 / TJ-20 / TJ-24 / TJ-27: three tips, cheapest first, read as "name, price".
    @MainActor
    func testThreeTipsCheapestFirst() {
        let tipJar = openTipJar(scenario: "success")
        let coffee = tipJar.product("coffee").waitToAppear()
        let lunch = tipJar.product("lunch").waitToAppear()
        let bigThanks = tipJar.product("bigthanks").waitToAppear()

        XCTAssertEqual(coffee.label, "Coffee, $0.99")
        XCTAssertEqual(lunch.label, "Lunch, $2.99")
        XCTAssertEqual(bigThanks.label, "Big Thanks, $5.99")
        XCTAssertLessThan(coffee.frame.minY, lunch.frame.minY)
        XCTAssertLessThan(lunch.frame.minY, bigThanks.frame.minY)
        XCTAssertFalse(tipJar.loading.exists)
    }

    /// TJ-10 / TJ-18 / TJ-19: thank-you, the Settings row thanks too, tipping again thanks again.
    @MainActor
    func testPurchaseShowsThankYou() {
        let tipJar = openTipJar(scenario: "success")
        XCTAssertFalse(tipJar.thankYou.exists)
        tipJar.product("coffee").waitAndTap()
        tipJar.thankYou.waitToAppear()
        XCTAssertTrue(tipJar.thankYou.label.contains("Thank you!"), "card: \(tipJar.thankYou.label)")

        let settings = tipJar.goBack()
        settings.tipJarRow.waitForLabel(containing: "Thank you for your support!")

        let again = settings.openTipJar()
        XCTAssertFalse(again.thankYou.exists, "the card is gone after leaving the screen")
        again.product("lunch").waitAndTap()
        again.thankYou.waitToAppear()
    }

    /// TJ-13: cancelling shows nothing, the buttons work again.
    @MainActor
    func testCancelShowsNothing() {
        let tipJar = openTipJar(scenario: "cancel")
        let coffee = tipJar.product("coffee")
        coffee.waitAndTap()
        coffee.waitToBeHittable()
        XCTAssertTrue(coffee.isEnabled)
        XCTAssertFalse(tipJar.thankYou.exists)
        XCTAssertFalse(tipJar.pending.exists)
        XCTAssertEqual(tipJar.app.alerts.count, 0)
    }

    /// TJ-12: Ask to Buy → "Waiting for approval", no thank-you.
    @MainActor
    func testPendingShowsWaitingForApproval() {
        let tipJar = openTipJar(scenario: "pending")
        tipJar.product("bigthanks").waitAndTap()
        tipJar.pending.waitToAppear()
        XCTAssertTrue(tipJar.pending.label.contains("Waiting for approval"), "pending: \(tipJar.pending.label)")
        XCTAssertFalse(tipJar.thankYou.exists)
        XCTAssertEqual(tipJar.app.alerts.count, 0)
    }

    /// TJ-15: a store error → "Purchase failed" alert → OK → buttons active again.
    @MainActor
    func testFailedPurchaseShowsAlert() {
        let tipJar = openTipJar(scenario: "failed")
        tipJar.product("coffee").waitAndTap()
        let alert = tipJar.app.alerts["Purchase failed. Please try again."]
        alert.waitToAppear()
        alert.buttons.firstMatch.tap()
        alert.waitToDisappear()
        XCTAssertTrue(tipJar.product("coffee").isEnabled)
        XCTAssertFalse(tipJar.thankYou.exists)
    }

    /// TJ-11: unverified → the "couldn't be verified" alert, no thank-you.
    @MainActor
    func testUnverifiedPurchaseShowsAlert() {
        let tipJar = openTipJar(scenario: "unverified")
        tipJar.product("coffee").waitAndTap()
        tipJar.app.alerts["Purchase couldn't be verified"].waitToAppear()
        XCTAssertFalse(tipJar.thankYou.exists)
    }

    /// TJ-07: a load error shows "Try Again"; the retry loads the tips.
    @MainActor
    func testLoadErrorThenRetry() {
        let tipJar = openTipJar(scenario: "loadError")
        tipJar.retryButton.waitToAppear()
        XCTAssertFalse(tipJar.product("coffee").exists)
        tipJar.retryButton.tap()
        tipJar.product("coffee").waitToAppear()
        XCTAssertFalse(tipJar.retryButton.exists)
    }

    /// TJ-08: no products → "Tips are unavailable right now." with Try Again.
    @MainActor
    func testNoProductsShowsUnavailable() {
        let tipJar = openTipJar(scenario: "empty")
        tipJar.error.waitForLabel(containing: "Tips are unavailable right now.")
        tipJar.retryButton.waitToAppear()
    }

    /// TJ-06: while loading, a spinner and no buy buttons.
    @MainActor
    func testLoadingShowsSpinner() {
        let tipJar = openTipJar(scenario: "slowLoad")
        tipJar.loading.waitToAppear()
        XCTAssertFalse(tipJar.product("coffee").exists)
    }

    /// TJ-04 / TJ-22 in Russian: the footer, the screen title and the thank-you.
    @MainActor
    func testRussian() {
        let app = Launch.app(language: "ru", region: "ru_RU", tipJar: true, tipJarScenario: "success")
        let settings = HomeScreen(app: app).waitUntilShown().openSettings()
        settings.version.scrollIntoViewLazily(within: app.collectionViews.firstMatch)
        app.staticTexts["Чаевые ничего не открывают — приложение остаётся бесплатным."].waitToAppear()

        let tipJar = settings.openTipJar()
        XCTAssertTrue(app.navigationBars["Поддержать разработчика"].exists)
        tipJar.product("coffee").waitAndTap()
        tipJar.thankYou.waitToAppear()
        XCTAssertTrue(tipJar.thankYou.label.contains("Спасибо!"), "card: \(tipJar.thankYou.label)")
    }
}
