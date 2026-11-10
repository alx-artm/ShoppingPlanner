//
//  PlannerUITests.swift
//  Project2UITests
//
//  End-to-end flows on the deterministic seed data (`-UITests`, see the table
//  in SampleData.swift): Alex (pinned, USD, planned 370 / bought 30 → 340 to buy),
//  Eva (180), Victoria (EUR, 315).
//

import XCTest

final class PlannerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch / empty state

    /// `-UITests -UITestsEmptyStore`: Home shows the empty state (spec 02).
    @MainActor
    func testEmptyStoreShowsEmptyState() {
        let home = HomeScreen(app: Launch.app(emptyStore: true)).waitUntilShown()

        home.emptyState.waitToAppear()
        XCTAssertFalse(home.card("Alex").exists, "no seed data in the empty store")
        XCTAssertFalse(home.row("Eva").exists)
    }

    // MARK: - Totals (DM-23 / DM-24 on screen)

    @MainActor
    func testSeedTotalsAreVisible() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()
        XCTAssertFalse(home.emptyState.exists)

        // Home: "to buy" per list.
        home.card("Alex").waitForLabel(containing: "340")
        home.row("Eva").waitForLabel(containing: "180")
        home.row("Victoria").waitForLabel(containing: "315")

        // Detail: list total and group totals add up (115 + 225 = 340).
        let alex = home.open(card: "Alex")
        alex.total.waitForLabel("340")
        alex.groupTotal("Vacation").waitForLabel("115")
        alex.groupTotal("Birthday").waitForLabel("225")
        alex.itemTotal("BBQ food").waitForLabel("110") // 55 × 2
        alex.checkbox("Flip-flops").waitForSelected(true)
    }

    // MARK: - Create list → group → item

    @MainActor
    func testCreateListGroupAndItem() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        home.createList(named: "Party")
        let party = home.open(row: "Party")

        party.addGroup(named: "Food")
        party.addItem(named: "Cake", price: "12.5", quantity: 2, to: "Food")

        party.itemTotal("Cake").waitForLabel("25")
        party.groupTotal("Food").waitForLabel("25")
        party.total.waitForLabel("25")
        XCTAssertEqual(app.buttons["item.quantityButton.Cake"].label, "2")

        party.goBack().row("Party").waitForLabel(containing: "25")
    }

    /// DM-12: a new item needs a name, Done stays disabled for a blank one.
    @MainActor
    func testNewItemWithoutNameCannotBeSaved() {
        let app = Launch.app()
        let list = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        list.addItemButton("Toys").waitAndTap()
        let editor = ItemEditScreen(app: app).waitUntilShown()
        editor.nameField.typeText("   ")
        XCTAssertFalse(editor.doneButton.isEnabled)
    }

    // MARK: - Complete (DM-16, DM-23)

    @MainActor
    func testCompletingAnItemUpdatesTotals() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")
        alex.total.waitForLabel("340")

        alex.checkbox("Sunglasses").waitAndTap()
        alex.checkbox("Sunglasses").waitForSelected(true)
        alex.total.waitForLabel("280")
        alex.groupTotal("Vacation").waitForLabel("55")

        alex.checkbox("Sunglasses").tap()
        alex.checkbox("Sunglasses").waitForSelected(false)
        alex.total.waitForLabel("340")
    }

    // MARK: - Delete (DM-08, DM-18, BUG-01, BUG-04)

    @MainActor
    func testDeleteItemFromDetails() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")

        alex.openItem("Swimsuit").delete()

        alex.itemRow("Swimsuit").waitToDisappear()
        alex.total.waitForLabel("285")
        alex.groupTotal("Vacation").waitForLabel("60")
        XCTAssertEqual(app.state, .runningForeground, "no crash after deleting the open item (BUG-04)")
    }

    /// BUG-01: with "Hide completed" on, swipe-delete must remove the row that was swiped.
    @MainActor
    func testSwipeDeleteWithHiddenCompletedDeletesTheSwipedItem() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.toggleShowCompleted()
        alex.itemRow("Flip-flops").waitToDisappear()

        alex.swipeToDelete("Swimsuit")

        alex.itemRow("Swimsuit").waitToDisappear()
        XCTAssertTrue(alex.itemRow("Sunglasses").exists)
        alex.total.waitForLabel("285")

        alex.toggleShowCompleted()
        alex.itemRow("Flip-flops").waitToAppear() // the hidden completed item survived
    }

    @MainActor
    func testDeleteGroupThenReopenList() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.openGroup("Vacation").delete()

        alex.groupHeader("Vacation").waitToDisappear()
        alex.itemRow("Sunglasses").waitToDisappear()
        alex.total.waitForLabel("225")

        // Leave and come back: the list opens fine and the group is still gone.
        let reopened = alex.goBack().open(card: "Alex")
        reopened.groupHeader("Birthday").waitToAppear()
        XCTAssertFalse(reopened.groupHeader("Vacation").exists)
        reopened.total.waitForLabel("225")
    }

    /// DM-18: deleting the open list first leaves the screen, then deletes; no crash.
    @MainActor
    func testDeleteOpenListReturnsHome() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        home.open(row: "Eva").deleteList()

        home.row("Eva").waitToDisappear()
        XCTAssertEqual(app.state, .runningForeground)
        // Other lists still open normally.
        home.open(row: "Victoria").groupHeader("Vacation").waitToAppear()
    }

    @MainActor
    func testDeleteListFromHomeContextMenu() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        home.deleteFromContextMenu(row: "Victoria")

        home.row("Victoria").waitToDisappear()
        home.row("Eva").waitToAppear()
        home.card("Alex").waitToAppear()
    }
}
