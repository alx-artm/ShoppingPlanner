//
//  HomeUITests.swift
//  Project2UITests
//
//  Spec 02 / 08 end to end on the seed data (en_US): Alex is pinned (a tile),
//  Eva and Victoria are rows in All Lists (Eva first). Pin with a swipe and
//  unpin from the context menu (HM-08, HM-09), delete with a swipe and a
//  confirmation (HM-10), search (HM-13), Settings behind the gear (spec 08),
//  reordering from the ⋯ menu (HM-31…HM-35), "List Info" naming (HM-36) and
//  Duplicate opening the copy with an Undo toast (HM-39…HM-42).
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
        // Drop in the upper part of Eva's row, not on its center: on the center the list
        // sometimes keeps the order (CI, run 44061691931), as in testReorderItemsInGroup.
        let start = victoriaHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = handles.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -24))
        start.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
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

    // MARK: - Duplicate (HM-39...HM-42)

    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// HM-39, HM-41, HM-42: Duplicate on a Home row opens the copy (iPhone: pushed, iPad: in the
    /// detail) with "Copy of “Eva” created · Undo"; Undo deletes the copy and goes back to Home
    /// (iPad: "Select a List"), Eva stays where it was. The toast is kept long by a launch
    /// argument, so the test doesn't race its 4 s timer.
    @MainActor
    func testDuplicateOpensCopyAndUndoGoesBack() {
        let app = Launch.app(longUndoToast: true)
        let home = HomeScreen(app: app).waitUntilShown()
        let evaTop = home.top(of: home.row("Eva").waitToAppear())

        let copy = home.duplicateFromContextMenu(row: "Eva")
        app.navigationBars["Eva copy"].waitToAppear()
        copy.duplicateToast.waitToAppear()
        XCTAssertTrue(app.staticTexts["Copy of “Eva” created"].exists, "the toast names the original")

        copy.duplicateUndoButton.waitAndTap()
        if isPad {
            app.descendants(matching: .any)["detail.placeholder"].firstMatch.waitToAppear()
        } else {
            home.newListButton.waitToBeHittable()
        }
        home.row("Eva copy").waitToDisappear()
        XCTAssertEqual(home.top(of: home.row("Eva").waitToAppear()), evaTop, accuracy: 1,
                       "the original keeps its place")
    }

    /// HM-39: from search results too; without Undo the copy stays (HM-43).
    @MainActor
    func testDuplicateFromSearchOpensCopy() {
        // 12 s, not 4: long enough to be seen on a slow runner, short enough to watch it go.
        let app = Launch.app(toastSeconds: 12)
        let home = HomeScreen(app: app).waitUntilShown()
        home.search("vic")

        let copy = home.duplicateFromContextMenu(row: "Victoria")
        app.navigationBars["Victoria copy"].waitToAppear()
        copy.duplicateToast.waitToAppear()
        copy.duplicateToast.waitToDisappear(timeout: 25)
        if !isPad {
            copy.backButton.waitAndTap()
        }
        home.row("Victoria copy").waitToAppear()
    }

    /// HM-39, HM-42 from the open list's ⋯: Undo shows the original again (iPad: in the
    /// detail; iPhone: the list the user was on).
    @MainActor
    func testDuplicateFromOpenListUndoShowsOriginal() {
        let app = Launch.app(longUndoToast: true)
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        eva.menuAction("duplicate")
        app.navigationBars["Eva copy"].waitToAppear()
        eva.duplicateUndoButton.waitAndTap()

        app.navigationBars["Eva"].waitToAppear()
        app.navigationBars["Eva copy"].waitToDisappear()
        XCTAssertFalse(eva.duplicateToast.exists)
    }

    /// HM-41 regression (CI run 44802851831): after Eva was opened and closed, the copy's
    /// screen was rebuilt during the push and its onDisappear killed the toast before it showed.
    @MainActor
    func testDuplicateAfterOpeningOriginalShowsToast() {
        let app = Launch.app(longUndoToast: true)
        let home = HomeScreen(app: app).waitUntilShown()
        let eva = home.open(row: "Eva")
        if !isPad { eva.backButton.waitAndTap() }
        home.row("Eva").waitToAppear()
        let copy = home.duplicateFromContextMenu(row: "Eva")
        app.navigationBars["Eva copy"].waitToAppear()
        copy.duplicateToast.waitToAppear()
    }
}
