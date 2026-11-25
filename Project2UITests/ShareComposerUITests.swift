//
//  ShareComposerUITests.swift
//  Project2UITests
//
//  Spec 06 Part B (M7, PR 1 + PR 2): the Share Extension's compose screen, shown in the app by
//  `-UITestsShareComposer <scenario>` on the seeded in-memory store (B.5). The real share
//  sheet and the extension process are checked by hand (SE-01, SE-10); this class checks
//  the screen and what Save writes. Runs on iPhone and iPad (form sheet).
//
//  Seed (`SeedData`): Alex (pinned, USD; Vacation, Birthday — Birthday has the newest item),
//  Eva (USD), Victoria (EUR). Titles come from the stub fetcher, never the network.
//

import XCTest

final class ShareComposerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Save

    /// SE-02 name from the app's text, SE-03/SE-04 defaults, SE-06 price, SE-08 ★, SE-09 one item.
    @MainActor
    func testSaveAddsTheItemToTheDefaultListAndGroup() {
        let app = Self.launch(scenario: "appText")
        let composer = ShareComposer(app: app).waitUntilShown()
        XCTAssertEqual(composer.nameField.value as? String, "KIVIK 3-seat sofa")
        XCTAssertTrue(composer.listPicker.label.contains("Alex"), composer.listPicker.label)
        XCTAssertTrue(composer.groupPicker.label.contains("Birthday"), composer.groupPicker.label)
        XCTAssertTrue(composer.priceSymbol.label.hasSuffix("$"), composer.priceSymbol.label)
        XCTAssertEqual(composer.mustHaveToggle.value as? String, "0", "★ is off by default (B6)")
        attachScreenshot(of: app, named: "composer-light")

        // Before typing: the keyboard would cover the row. The switch sits at its trailing edge.
        composer.mustHaveToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        composer.mustHaveToggle.waitForValue("1")
        composer.priceField.tap()
        // iPad: the price is typed on the number pad popover, and the popover is closed before
        // Save, or its dismiss region eats the tap and the sheet stays (CI, PR #26).
        app.typeNumber("449", into: composer.priceField)
        app.dismissNumberPadPopover()
        composer.save.waitAndTap()
        composer.nameField.waitToDisappear()

        let list = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        list.itemRow("KIVIK 3-seat sofa").waitToAppear()
        list.mustHaveMarker("KIVIK 3-seat sofa").waitToAppear()
        XCTAssertEqual(list.itemTotal("KIVIK 3-seat sofa").waitToAppear().label, "$449.00")
    }

    /// SE-04a picker: active lists, pinned first, "New List…" last; SE-04/SE-06 a new list
    /// changes the group and the currency; "New List…" saves into a new list.
    @MainActor
    func testListPickerAndNewList() {
        let app = Self.launch(scenario: "appText")
        let composer = ShareComposer(app: app).waitUntilShown()
        composer.listPicker.waitAndTap()
        let rows = ["Alex", "Eva", "Victoria"].map { app.buttons["share.listRow.\($0)"].waitToAppear() }
        let newList = app.buttons["share.newListRow"].waitToAppear()
        XCTAssertLessThan(rows[0].frame.minY, rows[1].frame.minY)
        XCTAssertLessThan(rows[1].frame.minY, rows[2].frame.minY)
        XCTAssertLessThan(rows[2].frame.minY, newList.frame.minY)

        rows[2].tap() // Victoria, EUR
        XCTAssertTrue(composer.listPicker.waitToAppear().label.contains("Victoria"))
        XCTAssertTrue(composer.priceSymbol.label.hasSuffix("€"), composer.priceSymbol.label)
        XCTAssertTrue(composer.groupPicker.label.contains("Birthday"), composer.groupPicker.label)

        composer.groupPicker.tap()
        app.buttons["share.groupRow.Vacation"].waitAndTap()
        XCTAssertTrue(composer.groupPicker.waitToAppear().label.contains("Vacation"))

        composer.listPicker.tap()
        app.buttons["share.newListRow"].waitAndTap()
        let newListName = composer.newListName.waitToAppear()
        XCTAssertEqual(newListName.value as? String, "Wishlist")
        XCTAssertFalse(composer.groupPicker.exists, "a new list has no group to pick")
        composer.save.waitAndTap()
        composer.nameField.waitToDisappear()

        let home = HomeScreen(app: app).waitUntilShown()
        home.open(row: "Wishlist").itemRow("KIVIK 3-seat sofa").waitToAppear()
    }

    /// SE-05: no active list → name field "Wishlist", no pickers; Save creates list + "Items" + item.
    @MainActor
    func testEmptyStoreCreatesAList() {
        let app = Self.launch(scenario: "appText", emptyStore: true)
        let composer = ShareComposer(app: app).waitUntilShown()
        XCTAssertEqual(composer.newListName.waitToAppear().value as? String, "Wishlist")
        XCTAssertFalse(composer.listPicker.exists)
        XCTAssertFalse(composer.groupPicker.exists)
        composer.save.waitAndTap()
        composer.nameField.waitToDisappear()

        let home = HomeScreen(app: app).waitUntilShown()
        let list = home.open(row: "Wishlist")
        list.groupHeader("Items").waitToAppear()
        list.itemRow("KIVIK 3-seat sofa").waitToAppear()
    }

    // MARK: - Safari page (PR 2)

    /// SE-02 og:title, SE-02b picture on the card, SE-07 page price: a hint in the USD list,
    /// prefilled in the EUR list; Save stores the price and the picture (B3, SE-09).
    @MainActor
    func testSafariPagePrefillsNamePictureAndPrice() {
        let app = Self.launch(scenario: "safari")
        let composer = ShareComposer(app: app).waitUntilShown()
        XCTAssertEqual(composer.nameField.value as? String, "KIVIK 3-seat sofa")
        let pictured = NSPredicate(format: "value == %@", "Picture")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: pictured, object: composer.linkCard)],
                                        timeout: uiTimeout), .completed, "the og:image is on the card")
        XCTAssertTrue(composer.listPicker.label.contains("Alex"), composer.listPicker.label)
        XCTAssertEqual(composer.pagePriceHint.waitToAppear().label, "Page price: €449.00")
        // Empty field: XCUITest reports the placeholder as its value.
        XCTAssertTrue(["", "Price"].contains(composer.priceField.value as? String ?? ""), "USD list: the field stays empty")
        attachScreenshot(of: app, named: "composer-safari-hint")

        composer.listPicker.tap()
        app.buttons["share.listRow.Victoria"].waitAndTap()
        XCTAssertTrue(composer.listPicker.waitToAppear().label.contains("Victoria"))
        XCTAssertEqual(composer.priceField.value as? String, "449.00", "EUR list: prefilled from the page")
        XCTAssertFalse(composer.pagePriceHint.exists)
        attachScreenshot(of: app, named: "composer-safari-prefill")
        composer.save.waitAndTap()
        composer.nameField.waitToDisappear()

        let list = HomeScreen(app: app).waitUntilShown().open(row: "Victoria")
        list.itemRow("KIVIK 3-seat sofa").waitToAppear()
        XCTAssertEqual(list.itemTotal("KIVIK 3-seat sofa").waitToAppear().label, "€449.00")
        let thumb = app.buttons["item.linkThumb.KIVIK 3-seat sofa"].waitToAppear()
        XCTAssertEqual(thumb.value as? String, "Picture", "the picture was saved with the item")
    }

    // MARK: - Validation and Cancel

    /// SE-06: text that is not a price shows "Not a price" and turns Save off until fixed.
    @MainActor
    func testInvalidPriceDisablesSave() {
        let app = Self.launch(scenario: "appText")
        let composer = ShareComposer(app: app).waitUntilShown()
        composer.priceField.tap()
        composer.priceField.typeText("12-3")
        composer.priceError.waitToAppear()
        XCTAssertFalse(composer.save.isEnabled)
        composer.priceField.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue)
        composer.priceError.waitToDisappear()
        XCTAssertTrue(composer.save.isEnabled)
    }

    /// SE-09b: Cancel writes nothing.
    @MainActor
    func testCancelWritesNothing() {
        let app = Self.launch(scenario: "appText")
        let composer = ShareComposer(app: app).waitUntilShown()
        composer.cancel.waitAndTap()
        composer.nameField.waitToDisappear()
        let list = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        list.itemRow("Sunglasses").waitToAppear()
        XCTAssertFalse(list.itemRow("KIVIK 3-seat sofa").exists)
    }

    // MARK: - Name

    /// SE-02a: untouched, the name follows the late title; the card shows it too.
    @MainActor
    func testLateTitleReplacesAnUntouchedName() {
        let app = Self.launch(scenario: "urlOnly")
        let composer = ShareComposer(app: app).waitUntilShown()
        let titled = NSPredicate(format: "value == %@", "Preview: slow.example.com")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: titled, object: composer.nameField)],
                                        timeout: uiTimeout), .completed, "the late title replaces the host")
        XCTAssertTrue(composer.linkCard.label.contains("Preview: slow.example.com"), composer.linkCard.label)
    }

    /// SE-02a: once the user typed, the late title only reaches the card, not the name.
    @MainActor
    func testLateTitleKeepsAnEditedName() {
        let app = Self.launch(scenario: "urlOnlyEdit")
        let composer = ShareComposer(app: app).waitUntilShown()
        XCTAssertEqual(composer.nameField.value as? String, "veryslow.example.com", "the host until the title comes")
        // At the end of the text, so the typed word is appended.
        composer.nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        composer.nameField.typeText(" lamp")
        let carded = NSPredicate(format: "label CONTAINS %@", "Preview: veryslow.example.com")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: carded, object: composer.linkCard)],
                                        timeout: 15), .completed)
        XCTAssertEqual(composer.nameField.value as? String, "veryslow.example.com lamp")
    }

    // MARK: - Other screens, language, size

    /// B.2: a link that isn't a web page, and a store that can't be opened.
    @MainActor
    func testUnsupportedAndUnavailableScreens() {
        let app = Self.launch(scenario: "bad")
        app.descendants(matching: .any)["share.unsupported"].firstMatch.waitToAppear()
        XCTAssertTrue(app.staticTexts["This link can't be added"].exists)
        app.buttons["share.closeButton"].waitAndTap()
        HomeScreen(app: app).waitUntilShown()

        let unavailable = Self.launch(scenario: "unavailable")
        unavailable.descendants(matching: .any)["share.unavailable"].firstMatch.waitToAppear()
        unavailable.buttons["share.closeButton"].waitAndTap()
        HomeScreen(app: unavailable).waitUntilShown()
    }

    /// SE-16: Russian strings; dark mode screenshot.
    @MainActor
    func testRussianAndDark() {
        let app = Self.launch(scenario: "appText", emptyStore: true, language: "ru", region: "ru_RU", dark: true)
        let composer = ShareComposer(app: app).waitUntilShown()
        XCTAssertEqual(composer.newListName.waitToAppear().value as? String, "Хочу купить")
        XCTAssertTrue(app.navigationBars["Добавить в список"].exists)
        XCTAssertTrue(composer.priceSymbol.label.hasSuffix("₽"), composer.priceSymbol.label)
        composer.priceField.tap()
        composer.priceField.typeText("abc")
        XCTAssertEqual(composer.priceError.waitToAppear().label, "Это не цена")
        attachScreenshot(of: app, named: "composer-ru-dark")
    }

    /// SE-16: at AX5 the name wraps and Save / Cancel stay reachable.
    @MainActor
    func testAccessibilitySize() {
        let app = Self.launch(scenario: "appText", contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let composer = ShareComposer(app: app).waitUntilShown()
        composer.save.waitToBeHittable()
        composer.cancel.waitToBeHittable()
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(composer.nameField.frame.maxX, window.maxX)
        attachScreenshot(of: app, named: "composer-ax5")
        composer.save.tap()
        composer.nameField.waitToDisappear()
    }

    // MARK: - Helpers

    @MainActor
    private static func launch(scenario: String, emptyStore: Bool = false, language: String = "en",
                               region: String = "en_US", dark: Bool = false,
                               contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Appended one by one, not one long `+` chain (type-checker time, DECISIONS Р-26).
        var arguments = [Launch.uiTests]
        if emptyStore { arguments.append(Launch.emptyStore) }
        arguments += ["-UITestsShareComposer", scenario]
        arguments += ["-UITestsLinkPreview", "stub"]
        if dark { arguments += ["-selectedTheme", "dark"] }
        if let contentSize { arguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        arguments += Launch.locale(language: language, region: region)
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The compose screen of the Share Extension.
@MainActor
private struct ShareComposer {
    let app: XCUIApplication

    var nameField: XCUIElement { app.textViews["share.nameField"].firstMatch.exists
        ? app.textViews["share.nameField"].firstMatch : app.textFields["share.nameField"].firstMatch }
    var listPicker: XCUIElement { app.buttons["share.listPicker"].firstMatch }
    var groupPicker: XCUIElement { app.descendants(matching: .any)["share.groupPicker"].firstMatch }
    var newListName: XCUIElement { app.textFields["share.newListName"].firstMatch }
    var priceField: XCUIElement { app.textFields["share.priceField"].firstMatch }
    var priceSymbol: XCUIElement { app.staticTexts["share.priceField.symbol"].firstMatch }
    var priceError: XCUIElement { app.staticTexts["share.priceError"].firstMatch }
    var pagePriceHint: XCUIElement { app.staticTexts["share.pagePriceHint"].firstMatch }
    var mustHaveToggle: XCUIElement { app.switches["share.mustHaveToggle"].firstMatch }
    var linkCard: XCUIElement { app.descendants(matching: .any)["share.linkCard"].firstMatch }
    var save: XCUIElement { app.buttons["share.saveButton"].firstMatch }
    var cancel: XCUIElement { app.buttons["share.cancelButton"].firstMatch }

    @discardableResult
    func waitUntilShown() -> ShareComposer {
        save.waitToAppear()
        return self
    }
}
