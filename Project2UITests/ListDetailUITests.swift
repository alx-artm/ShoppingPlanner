//
//  ListDetailUITests.swift
//  Project2UITests
//
//  Spec 04 list screen on the seed data: group headers (LD-02, LD-04, LD-05),
//  item rows (LD-06, LD-08) and the summary bar (LD-10, LD-11, LD-11a).
//  Alex (USD, budget 500): planned 370, bought 30. Eva (USD, no budget):
//  Jacket has no price. Victoria (EUR, budget 300): planned 315.
//

import XCTest

final class ListDetailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Group header

    /// LD-02 / LD-04: a tap anywhere on the header collapses the group; collapsed shows "(3)".
    @MainActor
    func testHeaderTapCollapsesAndShowsCount() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")
        alex.itemRow("Sunglasses").waitToAppear()
        XCTAssertFalse(alex.groupCount("Vacation").exists)

        alex.groupHeader("Vacation").tap()
        alex.itemRow("Sunglasses").waitToDisappear()
        alex.groupCount("Vacation").waitForLabel("(3)")
        alex.groupTotal("Vacation").waitForLabel("$145.00")

        alex.groupHeader("Vacation").tap()
        alex.itemRow("Sunglasses").waitToAppear()
    }

    /// Rename lives in the group's ⋯ menu, as an alert with a text field (owner decision).
    @MainActor
    func testRenameGroupFromMenu() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.renameGroup("Vacation", to: "Beach")

        alex.groupHeader("Beach").waitToAppear()
        XCTAssertFalse(alex.groupHeader("Vacation").exists)
        alex.groupTotal("Beach").waitForLabel("$145.00")
    }

    /// LD-05: a group with items asks "Delete group and N items?" before deleting.
    @MainActor
    func testDeleteGroupAsksFirst() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")

        alex.groupMenuAction("Vacation", "delete")
        app.staticTexts["Delete group and 3 items?"].waitToAppear()
        XCTAssertTrue(alex.groupHeader("Vacation").exists, "nothing is deleted before the confirmation")
        app.buttons["groupDelete.confirmButton"].firstMatch.waitAndTap()

        alex.groupHeader("Vacation").waitToDisappear()
        alex.total.waitForLabel("$225.00")
    }

    // MARK: - Rows

    /// LD-06: the checkbox toggles "bought", the rest of the row opens details.
    @MainActor
    func testRowTapOpensDetailsCheckboxToggles() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.checkbox("Swimsuit").waitAndTap()
        alex.checkbox("Swimsuit").waitForSelected(true)
        XCTAssertFalse(ItemEditScreen(app: alex.app).nameField.exists, "the checkbox doesn't open details")

        alex.openItem("Swimsuit").cancel()
    }

    /// LD-06 / BUG-20: the checkbox is at least 44 × 44 pt.
    @MainActor
    func testCheckboxHitArea() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")
        let frame = alex.checkbox("Sunglasses").waitToAppear().frame
        XCTAssertGreaterThanOrEqual(frame.width, 44)
        XCTAssertGreaterThanOrEqual(frame.height, 44)
    }

    /// LD-08: no price shows "—", not $0.00.
    @MainActor
    func testItemWithoutPriceShowsDash() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        eva.itemTotal("Jacket").waitForLabel("No price")
    }

    // MARK: - Summary bar

    /// LD-10 / LD-11a: to buy, planned, percent and the budget line, like Home.
    @MainActor
    func testSummaryBar() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")
        alex.total.waitForLabel("$340.00")
        alex.planned.waitForLabel("of $370.00")
        alex.progress.waitForLabel("8% bought")
        alex.budget.waitForLabel("$130.00 to spare of $500.00")
        XCTAssertFalse(alex.unpriced.exists)

        // Updates right after a change (LD-10).
        alex.checkbox("Sunglasses").waitAndTap()
        alex.total.waitForLabel("$280.00")
        alex.progress.waitForLabel("24% bought")
    }

    /// LD-11: "+1 without price"; LD-11a no budget.
    @MainActor
    func testSummaryBarUnpricedAndNoBudget() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        eva.unpriced.waitForLabel("+1 without price")
        eva.budget.waitForLabel("No budget")
    }

    /// LD-11a: over budget is the same text as Home (with ⚠ drawn as an image).
    @MainActor
    func testSummaryBarOverBudget() {
        let victoria = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Victoria")
        victoria.budget.waitForLabel(containing: "plan €15.00 over budget")
    }

    /// LD-11: no items, no summary bar.
    @MainActor
    func testSummaryBarHiddenWithoutItems() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.createList(named: "Party")
        let party = home.open(row: "Party")
        party.addGroup(named: "Food")
        XCTAssertFalse(party.summary.exists)
    }
}
