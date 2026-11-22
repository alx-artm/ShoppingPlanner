//
//  LinkTileUITests.swift
//  Project2UITests
//
//  Spec 06 Part A, PR 4: the link tile in a list row (LP-15...LP-19, LP-08 regression), on
//  the stub fetcher (`-UITestsLinkPreview stub`, no network) with links recorded instead of
//  opened (`-UITestsRecordOpenedLinks` → `debug.lastOpenedLink`), so Safari never opens.
//  Stub hosts: fail.example.com fails, slow.example.com answers after 2 s,
//  noimage.example.com has no picture, any other host "Preview: <host>" + a picture.
//  Seed data: Eva → Toys → Teddy Bear $30, Puss in Boots $25, Scooter $40 (no links).
//

import XCTest

final class LinkTileUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// LP-15 / LP-16: a saved link gets a 44 pt tile with the picture, 8 pt after the checkbox;
    /// the amounts of rows with and without a tile end at the same x. A tap on the tile opens
    /// the page in the app and not the details; a tap on the name still opens the details.
    @MainActor
    func testTileShowsPictureAndOpensPageInApp() {
        let (app, eva) = openEva()
        XCTAssertFalse(tile("Scooter", in: app).exists, "no link, no tile")
        save(link: "kites.example.com/red", on: "Scooter", in: eva)

        let tile = tile("Scooter", in: app)
        tile.waitForValue("Picture")
        XCTAssertEqual(tile.frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(tile.frame.height, 44, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(tile.frame.minX - eva.checkbox("Scooter").frame.maxX, 8 - 0.5,
                                    "at least 8 pt between the checkbox and the tile")
        XCTAssertEqual(eva.itemTotal("Scooter").frame.maxX, eva.itemTotal("Puss in Boots").frame.maxX,
                       accuracy: 0.5, "the tile doesn't move the amount column")
        XCTAssertGreaterThan(eva.itemRow("Scooter").label.count, 0)
        attachScreenshot(of: app, named: "tile-light")

        let opened = lastOpenedLink(in: app)
        opened.waitForLabel("none")
        tile.tap()
        opened.waitForLabel("inApp https://kites.example.com/red")
        XCTAssertFalse(ItemEditScreen(app: app).cancelButton.waitForExistence(timeout: 2),
                       "a tap on the tile doesn't open the details")

        let editor = eva.openItem("Scooter")
        editor.cancel()
    }

    /// LP-15 / LP-17: without a picture (page has none, fetch failed) the tile shows the link
    /// symbol; a row without a link or with text that isn't a web link has no tile.
    @MainActor
    func testTileWithoutPictureAndRowsWithoutTile() {
        let (app, eva) = openEva()
        save(link: "noimage.example.com", on: "Scooter", in: eva)
        save(link: "https://fail.example.com/x", on: "Puss in Boots", in: eva)
        save(link: "shop", on: "Teddy Bear", in: eva)

        let noImage = tile("Scooter", in: app)
        noImage.waitToAppear()
        let failed = tile("Puss in Boots", in: app)
        failed.waitToAppear()
        // Both previews are done (or failed) once the details show them; the value stays empty.
        XCTAssertEqual(noImage.value as? String ?? "", "")
        XCTAssertEqual(failed.value as? String ?? "", "")
        XCTAssertFalse(tile("Teddy Bear", in: app).exists, "not a web link: no tile")
        XCTAssertEqual(noImage.frame.height, failed.frame.height, accuracy: 0.5)
        XCTAssertEqual(eva.itemTotal("Scooter").frame.maxX, eva.itemTotal("Teddy Bear").frame.maxX,
                       accuracy: 0.5)
    }

    /// LP-17: the row is as high before the picture arrives as after.
    @MainActor
    func testRowHeightDoesNotJumpWhenPictureArrives() {
        let (app, eva) = openEva()
        save(link: "https://slow.example.com/kite", on: "Scooter", in: eva)

        let tile = tile("Scooter", in: app)
        let row = eva.itemRow("Scooter")
        tile.waitToAppear()
        // The stub answers 2 s after ✓; a slow runner may come back later than that.
        let heightBefore = row.frame.height
        let hadPicture = (tile.value as? String) == "Picture"
        tile.waitForValue("Picture", timeout: 15)
        if !hadPicture {
            XCTAssertEqual(row.frame.height, heightBefore, accuracy: 0.5, "the row doesn't jump")
        }
        // A row with the symbol tile is as high as one with the picture.
        save(link: "noimage.example.com", on: "Puss in Boots", in: eva)
        self.tile("Puss in Boots", in: app).waitToAppear()
        XCTAssertEqual(eva.itemRow("Puss in Boots").frame.height, row.frame.height, accuracy: 0.5)
    }

    /// D4 / LP-08: the context menu's "Open Link" opens the shop's app or Safari, not the
    /// in-app browser. (LP-18's VoiceOver action "Open Link" isn't visible to XCUITest — no
    /// public API lists custom actions; it was checked in the simulator's accessibility tree.)
    @MainActor
    func testContextMenuOpenLinkOpensExternally() {
        let (app, eva) = openEva()
        save(link: "https://kites.example.com/red", on: "Scooter", in: eva)
        tile("Scooter", in: app).waitToAppear()

        eva.contextMenu("Scooter", "openLink")
        lastOpenedLink(in: app).waitForLabel("external https://kites.example.com/red")
    }

    /// LP-18: at AX3, in Russian and in dark mode the tile (56 pt) is in the details line under
    /// the name, at the text's leading edge, and the row fits the screen.
    @MainActor
    func testTileAtAccessibilitySizeInRussianDarkMode() {
        let app = Self.launch(language: "ru", region: "ru_RU",
                              contentSize: UIContentSizeCategory.accessibilityExtraLarge.rawValue,
                              dark: true)
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        save(link: "https://kites.example.com/red", on: "Scooter", in: eva)

        let tile = tile("Scooter", in: app)
        eva.reveal(tile)
        tile.waitForValue("Картинка")
        let row = eva.itemRow("Scooter").frame
        let total = eva.itemTotal("Scooter").frame
        XCTAssertEqual(tile.frame.width, 56, accuracy: 0.5)
        XCTAssertEqual(tile.frame.minX, row.minX, accuracy: 1, "the tile starts the details line")
        XCTAssertGreaterThanOrEqual(tile.frame.minY, total.maxY - 0.5, "the tile is under the name line")
        XCTAssertLessThanOrEqual(tile.frame.maxY, row.maxY + 0.5)
        XCTAssertLessThanOrEqual(row.maxX, app.windows.firstMatch.frame.maxX)
        attachScreenshot(of: app, named: "tile-ax3-ru-dark")
    }

    /// LP-19: a list of 200 items, most with tiles (stored 800 px pictures, stub fetches,
    /// symbols), scrolls to the end and back; tiles keep their pictures.
    @MainActor
    func testLongListWithTilesScrolls() {
        let app = Self.launch(linkRows: 200)
        _ = HomeScreen(app: app).waitUntilShown().open(row: "Links")
        let first = tile("Item 1", in: app)
        first.waitForValue("Picture")
        attachScreenshot(of: app, named: "tile-long-list")

        // Fast flings to the end: the rows on the way decode their tiles. `exists`, not
        // `isHittable`: it doesn't retry, so each check stays cheap in a long list.
        let list = app.collectionViews.firstMatch
        let last = tile("Item 197", in: app)
        for _ in 0..<40 where !last.exists { list.swipeUp(velocity: .fast) }
        last.waitForValue("Picture")
        XCTAssertFalse(tile("Item 200", in: app).exists, "every 4th item has no link")
        // A row scrolled away and back shows its picture again.
        list.swipeDown(velocity: .fast)
        list.swipeUp(velocity: .fast)
        last.waitForValue("Picture")
    }

    // MARK: - Helpers

    /// `-UITests` with the stub fetcher and recorded links; English unless asked otherwise.
    @MainActor
    private static func launch(language: String = "en", region: String = "en_US",
                               contentSize: String? = nil, dark: Bool = false,
                               linkRows: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Appended one by one, not one long `+` chain (type-checker time, DECISIONS Р-26).
        var arguments = [Launch.uiTests]
        arguments += ["-UITestsLinkPreview", "stub"]
        arguments.append("-UITestsRecordOpenedLinks")
        if let linkRows { arguments += ["-UITestsLinkRows", String(linkRows)] }
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

    @MainActor
    private func tile(_ item: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["item.linkThumb.\(item)"]
    }

    @MainActor
    private func lastOpenedLink(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["debug.lastOpenedLink"].firstMatch
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
