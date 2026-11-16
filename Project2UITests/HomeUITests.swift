//
//  HomeUITests.swift
//  Project2UITests
//
//  Spec 02 / 08 end to end on the seed data (en_US): Alex is pinned (a tile),
//  Eva and Victoria are rows in All Lists (Eva first). Pin with a swipe and
//  unpin from the context menu (HM-08, HM-09), delete with a swipe and a
//  confirmation (HM-10), search (HM-13), Settings behind the gear (spec 08),
//  reordering from the ⋯ menu (HM-31…HM-35) and "List Info" naming (HM-36).
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

    /// BUG-27: List Info in the second tile's context menu opens List Info of that list, not the
    /// first one. HM-36: the item is called "List Info", and the menu has no "Edit".
    @MainActor
    func testContextMenuEditOfSecondTileOpensThatList() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.pinWithSwipe(row: "Victoria")
        home.card("Victoria").waitToAppear()

        let listInfoItem = home.openContextMenu(card: "Victoria", until: app.buttons["home.menu.edit"])
        XCTAssertEqual(listInfoItem.label, "List Info")
        XCTAssertFalse(app.buttons["Edit"].exists, "no \"Edit\" on Home (HM-36)")
        listInfoItem.tap()
        let info = ListInfoScreen(app: app).waitUntilShown()
        XCTAssertEqual(info.nameField.value as? String, "Victoria")
        info.cancel().card("Alex").waitToAppear()
    }

    /// HM-30: rows have three lines (name + to buy / progress / budget) and the same height
    /// whatever the budget state: Eva "No budget" next to Victoria "⚠ plan €15.00 over budget" (S5).
    @MainActor
    func testRowsHaveTheSameHeightInEveryBudgetState() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()
        let eva = home.row("Eva").waitToAppear()
        let victoria = home.row("Victoria").waitToAppear()
        XCTAssertEqual(eva.frame.height, victoria.frame.height, accuracy: 0.5)
        XCTAssertFalse(home.app.staticTexts["home.listRow.status.Victoria"].label.contains("·"),
                       "no '·' joining progress and budget")
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

    /// HM-03, HM-31…HM-34: ⋯ → Reorder Lists shows drag handles and only Done in the toolbar
    /// (outside this mode a long press is the context menu, so rows are not draggable there).
    /// There is no "Edit" button on Home.
    @MainActor
    func testReorderListsInEditMode() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        XCTAssertLessThan(home.top(of: home.row("Eva")), home.top(of: home.row("Victoria")))
        XCTAssertFalse(app.buttons["home.editButton"].exists, "HM-31: no Edit button")
        XCTAssertFalse(app.navigationBars.buttons["Edit"].exists, "HM-31: no Edit button")

        home.startReorderingLists()
        XCTAssertFalse(home.menuButton.exists, "HM-33: ⋯ is hidden while reordering")
        XCTAssertFalse(home.newListButton.exists, "HM-33: + is hidden while reordering")
        let handles = home.list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        // Pinned Alex is a row in reorder mode too: Alex, Eva, Victoria.
        let victoriaHandle = handles.element(boundBy: 2).waitToAppear()
        victoriaHandle.press(forDuration: 0.6, thenDragTo: handles.element(boundBy: 1),
                             withVelocity: .slow, thenHoldForDuration: 0.3)
        home.reorderDoneButton.waitAndTap()

        // HM-34: Done brings back the tiles, ⋯ and +; the new order stays.
        home.reorderDoneButton.waitToDisappear()
        home.card("Alex").waitToAppear()
        home.menuButton.waitToAppear()
        home.newListButton.waitToAppear()
        XCTAssertLessThan(home.top(of: home.row("Victoria")), home.top(of: home.row("Eva")))
    }

    /// HM-32: "Reorder Lists" is shown but disabled unless one section has two lists.
    /// 0 lists → disabled, 2 in All Lists → enabled, 1 pinned + 1 other → disabled.
    @MainActor
    func testReorderListsDisabledWithoutTwoListsInASection() {
        let app = Launch.app(emptyStore: true)
        let home = HomeScreen(app: app).waitUntilShown()
        home.emptyState.waitToAppear()
        XCTAssertFalse(home.isReorderListsEnabled(), "no lists")

        home.createList(named: "Garden")
        home.createList(named: "Kitchen")
        home.row("Garden").waitToAppear()
        XCTAssertTrue(home.isReorderListsEnabled(), "two lists in All Lists")

        home.pinWithSwipe(row: "Kitchen")
        home.card("Kitchen").waitToAppear()
        XCTAssertFalse(home.isReorderListsEnabled(), "one list in each section")
    }
}
