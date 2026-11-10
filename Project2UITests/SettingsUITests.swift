//
//  SettingsUITests.swift
//  Project2UITests
//
//  Spec 07 end to end: pick the main currency in Settings (SC-03), a new list
//  uses it (SC-05), existing lists keep theirs (SC-06), and amounts are
//  formatted by MoneyFormat (SC-08). Launched in en_US with the seed data, so
//  the main currency starts as USD.
//

import XCTest

final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// SC-03 / SC-05 / SC-06 / SC-08.
    @MainActor
    func testPickEuroThenNewListUsesEuroAndSeedListsKeepTheirCurrency() {
        let app = Launch.app()
        let tabs = TabBar(app: app)
        HomeScreen(app: app).waitUntilShown()

        // Settings shows the locale default (SC-01: en_US → USD).
        var settings = tabs.openSettings()
        settings.mainCurrency.waitForLabel(containing: "USD")

        // Picker: the current choice is checked; search "eur" → Euro → back.
        let picker = settings.openCurrencyPicker()
        picker.row("USD").waitForSelected(true)
        picker.search("eur")
        picker.row("USD").waitToDisappear()   // filtered out
        XCTAssertTrue(picker.row("EUR").label.contains("Euro"), "row: \(picker.row("EUR").label)")
        settings = picker.select("EUR")
        settings.mainCurrency.waitForLabel(containing: "EUR")
        settings.mainCurrency.waitForLabel(containing: "€")

        // SC-05: a new list is in euros.
        let home = tabs.openLists()
        home.createList(named: "Trip")
        home.rowToBuy("Trip").waitForLabel("€0.00")

        let trip = home.open(row: "Trip")
        trip.addGroup(named: "Food")
        // Whole-number price: typing "12.5" into the decimal pad is flaky (see BUG-26).
        trip.addItem(named: "Cake", price: "12", quantity: 2, to: "Food")
        trip.itemTotal("Cake").waitForLabel("€24.00")
        trip.total.waitForLabel("€24.00")
        trip.goBack().rowToBuy("Trip").waitForLabel("€24.00")

        // SC-06: seed lists keep their own currency.
        home.cardToBuy("Alex").waitForLabel("$340.00")
        home.rowToBuy("Eva").waitForLabel("$180.00")
        home.rowToBuy("Victoria").waitForLabel("€315.00")
        let eva = home.open(row: "Eva")
        eva.total.waitForLabel("$180.00")
    }

    /// Spec 07 "Layout": the General / iCloud / About rows exist; SC-03 search by symbol.
    @MainActor
    func testSettingsRowsAndPickerSearchBySymbol() {
        let app = Launch.app()
        let settings = TabBar(app: app).openSettings()

        settings.appearancePicker.waitToAppear()
        settings.icloudStatus.waitToAppear()
        settings.version.waitToAppear()

        // SC-03: "€" finds EUR, and a query without results hides every row.
        let picker = settings.openCurrencyPicker()
        picker.search("€")
        picker.row("EUR").waitToAppear()
        picker.row("JPY").waitToDisappear()
        picker.searchField.typeText("qwerty")
        picker.row("EUR").waitToDisappear()
    }
}
