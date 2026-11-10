//
//  HomeUITests.swift
//  Project2UITests
//
//  Spec 02 / 08 end to end on the seed data (en_US): Alex is pinned (a tile),
//  Eva and Victoria are rows in All Lists (Eva first). Pin with a swipe and
//  unpin from the context menu (HM-08, HM-09), delete with a swipe and a
//  confirmation (HM-10), search (HM-13), Settings behind the gear (spec 08).
//

import XCTest

final class HomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// HM-01, HM-07: tiles for pinned lists, rows with a status for the others.
    @MainActor
    func testSeedSectionsAndStatus() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        home.card("Alex").waitForLabel(containing: "to buy $340.00")
        XCTAssertFalse(home.row("Alex").exists)
        home.row("Eva").waitForLabel(containing: "0% bought")
        home.row("Victoria").waitForLabel(containing: "Over budget by €15.00")
        XCTAssertLessThan(home.top(of: home.row("Eva")), home.top(of: home.row("Victoria")))
    }

    /// HM-08: swipe → Pin makes a tile, last in Pinned; HM-09: context menu → Unpin makes a row again,
    /// at the end of All Lists.
    @MainActor
    func testPinWithSwipeThenUnpinFromContextMenu() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        home.pinWithSwipe(row: "Eva")
        home.card("Eva").waitToAppear()
        home.row("Eva").waitToDisappear()
        let alexTile = home.card("Alex").frame
        let evaTile = home.card("Eva").frame
        XCTAssertTrue(evaTile.minY > alexTile.minY || evaTile.minX > alexTile.minX, "Eva comes after Alex")

        // The first tile's menu (see BUG-28 for the others).
        home.unpinFromContextMenu(card: "Alex")
        home.row("Alex").waitToAppear()
        home.card("Alex").waitToDisappear()
        home.card("Eva").waitToAppear()
        XCTAssertGreaterThan(home.top(of: home.row("Alex")), home.top(of: home.row("Victoria")),
                             "an unpinned list goes to the end of All Lists")
    }

    /// BUG-28 (new): with two or more tiles, the context menu of any tile acts on the
    /// first tile. Long press Eva (2nd tile) → Unpin unpins Alex; Edit opens Alex.
    @MainActor
    func testContextMenuOfSecondTileActsOnThatTile() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.pinWithSwipe(row: "Eva")
        home.card("Eva").waitToAppear()

        home.unpinFromContextMenu(card: "Eva")

        // Wait for whichever list was unpinned, then check it was the long-pressed one.
        app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                         ["home.listRow.Eva", "home.listRow.Alex"])).firstMatch.waitToAppear()
        XCTExpectFailure("BUG-28: a tile's context menu acts on the first tile in the Pinned grid")
        XCTAssertTrue(home.row("Eva").exists, "Eva should be a row again")
        XCTAssertTrue(home.card("Alex").exists, "Alex should stay pinned")
    }

    /// HM-10: swipe → Delete asks first; the row is deleted only after confirming.
    @MainActor
    func testSwipeDeleteAsksForConfirmation() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        let confirm = home.swipeToDelete(row: "Victoria")
        XCTAssertTrue(home.row("Victoria").exists, "not deleted before the confirmation")
        confirm.tap()

        home.row("Victoria").waitToDisappear()
        home.row("Eva").waitToAppear()
        home.card("Alex").waitToAppear()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// HM-13: search filters tiles and rows; no match shows the search empty state.
    @MainActor
    func testSearchFiltersBothSections() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        home.search("VIC")
        home.row("Victoria").waitToAppear()
        home.row("Eva").waitToDisappear()
        home.card("Alex").waitToDisappear()

        home.searchField.typeText("zzz")
        home.row("Victoria").waitToDisappear()
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Results")).firstMatch
            .waitToAppear()
    }

    /// Spec 08: no tab bar; Settings is a sheet behind the gear and closes back to Home.
    @MainActor
    func testSettingsOpensFromGearAndCloses() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        XCTAssertFalse(app.tabBars.firstMatch.exists, "the tab bar is gone (spec 08)")

        let settings = home.openSettings()
        settings.version.waitToAppear()
        settings.close().card("Alex").waitToAppear()
        XCTAssertTrue(home.settingsButton.isHittable)
    }
}
