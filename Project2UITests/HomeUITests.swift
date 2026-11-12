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

    /// HM-01, HM-16, HM-20: tiles for pinned lists, rows with a status for the others.
    @MainActor
    func testSeedSectionsAndStatus() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        home.card("Alex").waitForLabel(containing: "to buy $340.00, 8% bought, $130.00 to spare of $500.00 budget")
        XCTAssertFalse(home.row("Alex").exists)
        home.row("Eva").waitForLabel(containing: "0% bought, no budget")
        home.row("Victoria").waitForLabel(containing: "0% bought, plan €15.00 over budget")
        XCTAssertLessThan(home.top(of: home.row("Eva")), home.top(of: home.row("Victoria")))
    }

    /// HM-08: swipe → Pin makes a tile, last in Pinned; HM-09: context menu → Unpin makes a row again,
    /// first in All Lists (HM-26).
    @MainActor
    func testPinWithSwipeThenUnpinFromContextMenu() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        home.pinWithSwipe(row: "Eva")
        home.card("Eva").waitToAppear()
        home.row("Eva").waitToDisappear()
        let alexTile = home.card("Alex").frame
        let evaTile = home.card("Eva").frame
        XCTAssertTrue(evaTile.minY > alexTile.minY || evaTile.minX > alexTile.minX, "Eva comes after Alex")

        home.unpinFromContextMenu(card: "Alex")
        home.row("Alex").waitToAppear()
        home.card("Alex").waitToDisappear()
        home.card("Eva").waitToAppear()
        XCTAssertLessThan(home.top(of: home.row("Alex")), home.top(of: home.row("Victoria")),
                          "an unpinned list goes to the top of All Lists (HM-26)")
    }

    /// BUG-27 / HM-27: with two tiles in one row, the context menu of the right tile
    /// acts on that tile. Long press Eva (2nd tile) → Unpin unpins Eva; Alex stays pinned.
    @MainActor
    func testContextMenuOfSecondTileActsOnThatTile() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.pinWithSwipe(row: "Eva")
        home.card("Eva").waitToAppear()
        XCTAssertEqual(home.card("Eva").frame.minY, home.card("Alex").frame.minY, accuracy: 1,
                       "both tiles are in one grid row")

        home.unpinFromContextMenu(card: "Eva")

        // Wait for whichever list was unpinned, then check it was the long-pressed one.
        app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                         ["home.listRow.Eva", "home.listRow.Alex"])).firstMatch.waitToAppear()
        XCTAssertTrue(home.row("Eva").exists, "Eva should be a row again")
        XCTAssertTrue(home.card("Alex").exists, "Alex should stay pinned")
        XCTAssertFalse(home.row("Alex").exists)
    }

    /// BUG-27: Edit in the second tile's context menu opens List Info of that list, not the first one.
    @MainActor
    func testContextMenuEditOfSecondTileOpensThatList() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.pinWithSwipe(row: "Victoria")
        home.card("Victoria").waitToAppear()

        let info = home.editFromContextMenu(card: "Victoria")
        XCTAssertEqual(info.nameField.value as? String, "Victoria")
        info.cancel().card("Alex").waitToAppear()
    }

    /// HM-28: tiles of one row have the same height, whatever their budget state
    /// (Alex: to spare, Victoria: over budget).
    @MainActor
    func testTilesInOneRowHaveTheSameHeight() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()
        home.pinWithSwipe(row: "Victoria")
        home.card("Victoria").waitToAppear()
        XCTAssertEqual(home.card("Victoria").frame.height, home.card("Alex").frame.height, accuracy: 0.5)
        XCTAssertEqual(home.card("Victoria").frame.minY, home.card("Alex").frame.minY, accuracy: 1)
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
