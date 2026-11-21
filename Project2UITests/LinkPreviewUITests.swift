//
//  LinkPreviewUITests.swift
//  Project2UITests
//
//  Spec 06 Part A, PR 3: the link card in item details, on the stub fetcher
//  (`-UITestsLinkPreview stub`, no network) with links recorded instead of opened
//  (`-UITestsRecordOpenedLinks` → `debug.lastOpenedLink`), so Safari never opens.
//  Stub hosts: fail.example.com fails, slow.example.com answers after 2 s,
//  noimage.example.com has no picture, any other host "Preview: <host>" + a picture.
//  Seed data: Eva → Toys → Scooter (no link).
//

import XCTest

final class LinkPreviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// LP-01 / LP-09: after ✓ the preview is fetched; reopened details show the card,
    /// one VoiceOver element "Link: <title>, <host>" that is a button.
    @MainActor
    func testSavedLinkShowsCard() {
        let (app, eva) = openEva()
        save(link: "kites.example.com/red", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        let card = revealLinkSection(of: editor, showing: linkCard(in: app))
        card.waitForLabel("Link: Preview: kites.example.com, kites.example.com")
        XCTAssertEqual(card.elementType, .button, "the card reads as a button")
        XCTAssertFalse(compactRow(in: app).exists)
        // LP-06: stored normalized; the field shows what was saved.
        editor.urlField.waitForValue("https://kites.example.com/red")
        attachScreenshot(of: app, named: "card-light")
    }

    /// LP-05 / D4: a tap on the card opens the link in the app; "Open in Safari" outside it.
    @MainActor
    func testCardOpensInAppAndButtonOpensInSafari() {
        let (app, eva) = openEva()
        save(link: "https://kites.example.com/red", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        let opened = lastOpenedLink(in: app)
        opened.waitForLabel("none")
        revealLinkSection(of: editor, showing: linkCard(in: app)).tap()
        opened.waitForLabel("inApp https://kites.example.com/red")

        app.buttons["itemEdit.openLinkButton"].scrollIntoViewLazily(within: editor.form).tap()
        opened.waitForLabel("external https://kites.example.com/red")

        // The same from the card's context menu.
        openCardMenu(in: app, editor: editor, showing: "openInSafari").tap()
        opened.waitForLabel("external https://kites.example.com/red")
    }

    /// LP-01a / D5: a failed fetch shows the compact "host" row, no error, no alert.
    @MainActor
    func testFailedFetchShowsCompactRowWithoutError() {
        let (app, eva) = openEva()
        save(link: "https://fail.example.com/x", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        revealLinkSection(of: editor, showing: compactRow(in: app))
            .waitForLabel("Link: fail.example.com")
        XCTAssertFalse(linkCard(in: app).exists)
        XCTAssertEqual(app.alerts.count, 0, "no error alert")
        XCTAssertFalse(app.staticTexts["itemEdit.linkError"].exists, "the link itself is fine")

        // The compact row opens the link like the card.
        compactRow(in: app).tap()
        lastOpenedLink(in: app).waitForLabel("inApp https://fail.example.com/x")
    }

    /// Spec 06 A.2: while the fetch runs the compact row has a spinner; then the card replaces it.
    @MainActor
    func testSlowFetchShowsLoadingThenCard() {
        let (app, eva) = openEva()
        save(link: "https://slow.example.com/kite", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        editor.urlField.scrollIntoViewLazily(within: editor.form)
        let card = linkCard(in: app)
        let compact = compactRow(in: app)
        // The stub answers 2 s after ✓. A slow runner may reopen the sheet later than that,
        // so the loading state is checked only when it is still there; the card must come.
        if compact.waitForExistence(timeout: 2), !card.exists {
            XCTAssertTrue(app.descendants(matching: .any)["itemEdit.linkLoading"].exists || card.exists,
                          "a spinner while the preview loads")
        }
        card.waitToAppear(timeout: 15)
        card.waitForLabel("Link: Preview: slow.example.com, slow.example.com")
        XCTAssertEqual(editor.urlField.value as? String, "https://slow.example.com/kite")
    }

    /// Spec 06 A.2: a page without a picture still gets a card with its title.
    @MainActor
    func testPageWithoutPictureShowsCard() {
        let (app, eva) = openEva()
        save(link: "noimage.example.com", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        revealLinkSection(of: editor, showing: linkCard(in: app))
            .waitForLabel("Link: Preview: noimage.example.com, noimage.example.com")
    }

    /// LP-07: Remove Link changes the draft — ✕ keeps the link, ✓ removes it with its card.
    /// Refresh Preview keeps the card (the stub answers the same).
    @MainActor
    func testMenuRefreshAndRemoveLink() {
        let (app, eva) = openEva()
        save(link: "https://kites.example.com", on: "Scooter", in: eva)

        var editor = eva.openItem("Scooter")
        openCardMenu(in: app, editor: editor, showing: "refresh").tap()
        linkCard(in: app).waitForLabel("Link: Preview: kites.example.com, kites.example.com")

        openCardMenu(in: app, editor: editor, showing: "remove").tap()
        linkCard(in: app).waitToDisappear()
        editor.urlField.waitForValue(editor.urlField.placeholderValue ?? "")
        editor.cancel()

        editor = eva.openItem("Scooter")
        revealLinkSection(of: editor, showing: linkCard(in: app))
        openCardMenu(in: app, editor: editor, showing: "remove").tap()
        linkCard(in: app).waitToDisappear()
        editor.done()

        editor = eva.openItem("Scooter")
        editor.urlField.scrollIntoViewLazily(within: editor.form)
        XCTAssertFalse(linkCard(in: app).exists)
        XCTAssertFalse(compactRow(in: app).exists)
        XCTAssertFalse(app.buttons["itemEdit.openLinkButton"].exists)
    }

    /// LP-05: text that isn't a web link gets "Not a web link" and no Open button;
    /// an empty field gets no caption; an edited link hides the card of the saved one.
    @MainActor
    func testInvalidLinkShowsCaption() {
        let (app, eva) = openEva()
        save(link: "https://kites.example.com", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        revealLinkSection(of: editor, showing: linkCard(in: app))
        editor.replaceText(of: editor.urlField, with: "shop")
        app.staticTexts["itemEdit.linkError"].waitForLabel("Not a web link")
        XCTAssertFalse(app.buttons["itemEdit.openLinkButton"].exists)
        XCTAssertFalse(linkCard(in: app).exists, "the card describes the saved link, not this text")

        editor.replaceText(of: editor.urlField, with: "other.example.com")
        app.staticTexts["itemEdit.linkError"].waitToDisappear()
        app.buttons["itemEdit.openLinkButton"].waitToAppear()
        XCTAssertFalse(linkCard(in: app).exists, "an unsaved link has no card yet")

        editor.replaceText(of: editor.urlField, with: "")
        XCTAssertFalse(app.staticTexts["itemEdit.linkError"].exists)
        editor.cancel()
    }

    /// LP-14: at AX3, in Russian and in dark mode the card fits the sheet, nothing is cut.
    @MainActor
    func testCardAtAccessibilitySizeInRussianDarkMode() {
        let app = Self.launch(language: "ru", region: "ru_RU",
                              contentSize: UIContentSizeCategory.accessibilityExtraLarge.rawValue,
                              dark: true)
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        save(link: "https://kites.example.com/red", on: "Scooter", in: eva)

        let editor = eva.openItem("Scooter")
        let card = revealLinkSection(of: editor, showing: linkCard(in: app))
        card.waitForLabel("Ссылка: Preview: kites.example.com, kites.example.com")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(card.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(card.frame.maxX, window.maxX, "the card is not wider than the screen")
        attachScreenshot(of: app, named: "card-ax3-ru-dark")
    }

    // MARK: - Helpers

    /// `-UITests` with the stub fetcher and recorded links; English unless asked otherwise.
    @MainActor
    private static func launch(language: String = "en", region: String = "en_US",
                               contentSize: String? = nil, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // Appended one by one, not one long `+` chain (type-checker time, DECISIONS Р-26).
        var arguments = [Launch.uiTests]
        arguments += ["-UITestsLinkPreview", "stub"]
        arguments.append("-UITestsRecordOpenedLinks")
        if let contentSize { arguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        if dark { arguments += ["-selectedTheme", "dark"] }
        arguments += Launch.locale(language: language, region: region)
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func openEva() -> (XCUIApplication, ListDetailScreen) {
        let app = Self.launch()
        return (app, HomeScreen(app: app).waitUntilShown().open(row: "Eva"))
    }

    /// Types `link` into the item's details and saves (✓): the fetch starts on save (LP-01).
    @MainActor
    private func save(link: String, on item: String, in list: ListDetailScreen) {
        let editor = list.openItem(item)
        editor.urlField.scrollIntoViewLazily(within: editor.form)
        editor.replaceText(of: editor.urlField, with: link)
        editor.done()
    }

    /// Scrolls the Form until the link field is on screen, so the whole card above it is
    /// too (the Form builds rows lazily: a row far below isn't even in the hierarchy).
    @MainActor
    @discardableResult
    private func revealLinkSection(of editor: ItemEditScreen, showing element: XCUIElement) -> XCUIElement {
        editor.urlField.scrollIntoViewLazily(within: editor.form)
        return element.waitToAppear()
    }

    @MainActor
    private func linkCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["itemEdit.linkCard"].firstMatch
    }

    @MainActor
    private func compactRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["itemEdit.linkCompact"].firstMatch
    }

    @MainActor
    private func lastOpenedLink(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["debug.lastOpenedLink"].firstMatch
    }

    /// Long press on the card → its context menu, showing `action`. A press taken as a tap
    /// only records an in-app open (no browser in this mode), so it is simply retried.
    @MainActor
    private func openCardMenu(in app: XCUIApplication, editor: ItemEditScreen,
                              showing action: String) -> XCUIElement {
        revealLinkSection(of: editor, showing: linkCard(in: app))
            .perform("Long press", until: app.buttons["itemEdit.linkMenu.\(action)"]) {
                $0.press(forDuration: 1.2)
            }
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
