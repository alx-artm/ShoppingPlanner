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

    /// LD-07c / LD-07e: checking an item keeps its amounts as they were and says "Bought"
    /// on the checkbox and on the row; unchecking says "Not bought" again.
    @MainActor
    func testBoughtRowKeepsAmountsAndSaysBought() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        eva.itemTotal("T-Shirt").waitForLabel("$40.00")
        eva.itemDetail("T-Shirt").waitForLabel("2 × $20.00")
        XCTAssertEqual(eva.itemRow("T-Shirt").value as? String ?? "", "")

        eva.reveal(eva.checkbox("T-Shirt")).tap()
        eva.checkbox("T-Shirt").waitForSelected(true)
        XCTAssertEqual(eva.checkbox("T-Shirt").value as? String, "Bought")
        XCTAssertEqual(eva.itemRow("T-Shirt").value as? String, "Bought")
        eva.itemTotal("T-Shirt").waitForLabel("$40.00")
        eva.itemDetail("T-Shirt").waitForLabel("2 × $20.00")

        eva.checkbox("T-Shirt").tap()
        eva.checkbox("T-Shirt").waitForSelected(false)
        XCTAssertEqual(eva.checkbox("T-Shirt").value as? String, "Not bought")
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

    // MARK: - Groups (step 3b)

    /// LD-01: ⋯ → Add Group asks for the name; the new group goes last.
    @MainActor
    func testAddGroupGoesLast() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.addGroup(named: "Gifts")

        XCTAssertGreaterThan(alex.groupHeader("Gifts").frame.minY, alex.groupHeader("Birthday").frame.minY)
    }

    /// LD-03: Reorder Groups sheet with drag handles; the order is saved.
    @MainActor
    func testReorderGroups() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        XCTAssertLessThan(alex.groupHeader("Vacation").frame.minY, alex.groupHeader("Birthday").frame.minY)

        alex.menuAction("reorderGroups")
        let list = app.collectionViews["reorderGroups.list"].waitToAppear()
        let handles = list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        let birthdayHandle = handles.element(boundBy: 1).waitToAppear()
        let vacationHandle = handles.element(boundBy: 0)
        birthdayHandle.press(forDuration: 0.6, thenDragTo: vacationHandle,
                             withVelocity: .slow, thenHoldForDuration: 0.3)
        app.buttons["reorderGroups.doneButton"].waitAndTap()
        list.waitToDisappear()

        XCTAssertLessThan(alex.groupHeader("Birthday").frame.minY, alex.groupHeader("Vacation").frame.minY)
    }

    /// Owner decision: items of a group can be dragged into another order ("Reorder Items" mode).
    @MainActor
    func testReorderItemsInGroup() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        XCTAssertLessThan(alex.itemRow("Sunglasses").frame.minY, alex.itemRow("Swimsuit").frame.minY)

        alex.menuAction("reorderItems")
        let handles = app.collectionViews.firstMatch.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        let swimsuitHandle = handles.element(boundBy: 1).waitToAppear()
        swimsuitHandle.press(forDuration: 0.6, thenDragTo: handles.element(boundBy: 0),
                             withVelocity: .slow, thenHoldForDuration: 0.3)
        app.buttons["listDetail.reorderDoneButton"].waitAndTap()

        XCTAssertLessThan(alex.itemRow("Swimsuit").frame.minY, alex.itemRow("Sunglasses").frame.minY)
        // Leave and come back: the order was saved.
        let reopened = alex.goBack().open(card: "Alex")
        XCTAssertLessThan(reopened.itemRow("Swimsuit").waitToAppear().frame.minY,
                          reopened.itemRow("Sunglasses").frame.minY)
    }

    /// Collapse All / Expand All in the toolbar menu.
    @MainActor
    func testCollapseAll() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.menuAction("toggleExpanded")
        alex.groupCount("Vacation").waitToAppear()
        alex.groupCount("Birthday").waitToAppear()
        XCTAssertFalse(alex.itemRow("Sunglasses").exists)

        alex.menuAction("toggleExpanded")
        alex.itemRow("Sunglasses").waitToAppear()
    }

    // MARK: - Row actions (LD-07, LD-09)

    /// LD-09: swipe-delete without confirmation; the toast's Undo brings the item back.
    @MainActor
    func testSwipeDeleteThenUndo() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.swipeToDelete("Swimsuit")
        // The toast lives ~4 s: tap Undo first, check the totals after.
        alex.undoButton.waitAndTap()
        alex.itemRow("Swimsuit").waitToAppear()
        alex.total.waitForLabel("$340.00")
        alex.undoToast.waitToDisappear()
    }

    /// LD-09: the toast goes away by itself after a few seconds.
    @MainActor
    func testUndoToastDisappears() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.swipeToDelete("Swimsuit")
        alex.undoToast.waitToAppear()
        alex.itemRow("Swimsuit").waitToDisappear()
        alex.total.waitForLabel("$285.00")
        alex.undoToast.waitToDisappear(timeout: 8)
        XCTAssertFalse(alex.itemRow("Swimsuit").exists)
    }

    /// LD-09: leading swipe marks bought / not bought.
    @MainActor
    func testSwipeToMarkBought() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.swipeToToggle("Sunglasses")
        alex.checkbox("Sunglasses").waitForSelected(true)
        alex.total.waitForLabel("$280.00")
    }

    /// LD-09: context menu Duplicate puts a copy right after the item.
    @MainActor
    func testContextMenuDuplicate() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.contextMenu("Sunglasses", "duplicate")

        alex.groupTotal("Vacation").waitForLabel("$205.00")
        XCTAssertEqual(alex.app.buttons.matching(identifier: "item.row.Sunglasses").count, 2)
    }

    /// LD-09: context menu Move to Group…
    @MainActor
    func testContextMenuMoveToGroup() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")

        alex.contextMenu("Sunglasses", "move")
        app.buttons["Birthday"].firstMatch.waitAndTap()

        alex.groupTotal("Vacation").waitForLabel("$85.00")
        alex.groupTotal("Birthday").waitForLabel("$285.00")
    }

    /// LD-09: context menu Delete also offers Undo.
    @MainActor
    func testContextMenuDelete() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.contextMenu("Appetizers", "delete")
        alex.itemRow("Appetizers").waitToDisappear()
        alex.undoToast.waitToAppear()
    }

    /// LD-07: with bought items hidden, "N bought" stays at the bottom of the group and shows them.
    @MainActor
    func testHiddenBoughtRow() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.toggleShowCompleted()
        alex.itemRow("Flip-flops").waitToDisappear()
        alex.boughtRow("Vacation").waitForLabel(containing: "1 bought")
        XCTAssertFalse(alex.boughtRow("Birthday").exists, "nothing bought there")

        alex.boughtRow("Vacation").tap()
        alex.itemRow("Flip-flops").waitToAppear()
    }

    // MARK: - Empty list (LD-18, LD-05a)

    /// LD-18: a new list shows "Add Item" and "Add Group"; Add Group creates the first group.
    @MainActor
    func testEmptyListAddGroup() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.createList(named: "Party")
        let party = home.open(row: "Party")

        party.emptyState.waitToAppear()
        app.buttons["listDetail.emptyState.addGroupButton"].waitAndTap()
        party.typeGroupName("Food")

        party.groupHeader("Food").waitToAppear()
        party.emptyState.waitToDisappear()
    }
}
