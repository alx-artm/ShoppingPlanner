//
//  ListDetailUITests.swift
//  Project2UITests
//
//  Spec 04 list screen on the seed data: group headers (LD-02, LD-04, LD-05),
//  item rows (LD-06, LD-08), the summary bar (LD-10, LD-11, LD-11a) and its
//  purchase bar (LD-21, LD-23, LD-27...LD-29).
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

        // DM-10: the collapsed state survives leaving the list and coming back.
        let reopened = alex.goBack().open(card: "Alex")
        reopened.groupCount("Vacation").waitForLabel("(3)")
        XCTAssertFalse(reopened.itemRow("Sunglasses").exists)

        reopened.groupHeader("Vacation").tap()
        reopened.itemRow("Sunglasses").waitToAppear()
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

    /// LD-05: an empty group is deleted at once, without the "Delete group and N items?" question.
    @MainActor
    func testDeleteEmptyGroupAtOnce() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        alex.addGroup(named: "Gifts")

        alex.groupMenuAction("Gifts", "delete")

        alex.groupHeader("Gifts").waitToDisappear()
        XCTAssertFalse(app.buttons["groupDelete.confirmButton"].exists, "no confirmation for an empty group")
        alex.total.waitForLabel("$340.00")
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

        // A bought item moves to the end of its group (DM-15), maybe under the summary bar.
        eva.reveal(eva.checkbox("T-Shirt")).tap()
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

    /// BUG-29 / LD-07a / WCAG 1.4.11: the ring of a not-bought checkbox needs ≥ 3:1 contrast with
    /// the row background. It was drawn in the list color at reduced opacity (`.secondary` inside a
    /// tinted Button is hierarchical, not gray): about 2.1:1 for Eva (magenta); now gray.
    @MainActor
    func testUncheckedCheckboxRingHasEnoughContrast() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        let checkbox = eva.checkbox("Sneakers").waitToBeHittable()
        let contrast = ScreenshotContrast.strongest(in: checkbox.screenshot().image)
        XCTAssertGreaterThanOrEqual(contrast, 3, "ring contrast \(contrast)")
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

    /// LD-10: the summary bar floats over the list, so the list must be able to scroll its
    /// last rows ("＋ New Item" of the last group, "＋ Add Group") above it, also while the
    /// "Undo" toast makes the bottom inset taller (small screens: iPhone 17e / SE).
    @MainActor
    func testBottomRowsScrollAboveSummaryBarAndToast() {
        let app = Launch.app(longUndoToast: true)
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        // A list longer than the screen.
        eva.startInline(in: "Clothes")
        app.typeText((1...8).map { "Extra \($0)\n" }.joined())
        eva.inlineDone()

        let lastNewItem = eva.addItemButton("Clothes")
        eva.reveal(eva.addGroupRow, maxSwipes: 8)
        XCTAssertTrue(eva.addGroupRow.isHittable)
        XCTAssertLessThanOrEqual(eva.addGroupRow.frame.maxY, eva.summary.frame.minY,
                                 "Add Group scrolls fully above the summary bar")
        XCTAssertLessThanOrEqual(lastNewItem.frame.maxY, eva.summary.frame.minY)

        // With the toast on screen, the last rows still scroll above it.
        eva.swipeToDelete("Extra 8")
        eva.undoToast.waitToAppear()
        let list = app.collectionViews.firstMatch
        list.swipeUp(velocity: .fast)
        let toastTop = eva.undoToast.frame.minY
        XCTAssertLessThan(toastTop, eva.summary.frame.minY, "the toast sits above the summary bar")
        XCTAssertLessThanOrEqual(eva.addGroupRow.frame.maxY, toastTop,
                                 "Add Group is not hidden behind the toast")
        eva.addGroupRow.tap()
        app.alerts.firstMatch.waitToAppear()
    }

    // MARK: - Purchase bar (LD-20...LD-29)
    // Alex in bar order: Flip-flops 30 (bought) | Sunglasses 60, Swimsuit 55, Appetizers 30,
    // BBQ food 110, Country house rental 85 — of 370, so Country house is the last 23 %.

    /// LD-21 / LD-28: the bar replaces the simple progress bar, next to "8% bought"; for
    /// VoiceOver it is one element that reads the summary.
    @MainActor
    func testPurchaseBarIsOneVoiceOverElement() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        let bar = alex.purchaseBar.waitToAppear()
        alex.progress.waitForLabel("8% bought")
        XCTAssertEqual(bar.label, "Purchase progress")
        XCTAssertEqual(bar.value as? String, "8% bought, 1 of 6 items, $340.00 to buy")
        XCTAssertGreaterThanOrEqual(bar.frame.height, 44, "LD-27: the tap area is the 44 pt row")

        // Checking an item off updates the same element (the segment moves to the bought side).
        alex.checkbox("Sunglasses").waitAndTap()
        alex.progress.waitForLabel("24% bought")
        XCTAssertEqual(bar.value as? String, "24% bought, 2 of 6 items, $280.00 to buy")
    }

    /// LD-27: a tap on a segment shows its item: the collapsed group opens, the row is
    /// scrolled above the summary bar and highlighted. The highlight is kept long by a
    /// launch argument, so the check doesn't race its ~1 s timer.
    @MainActor
    func testPurchaseBarTapShowsAndHighlightsItem() {
        let app = Launch.app(longRowHighlight: true)
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        alex.groupHeader("Birthday").waitAndTap()
        alex.itemRow("Country house rental").waitToDisappear()

        alex.tapPurchaseBar(at: 0.9)

        let row = alex.itemRow("Country house rental").waitToBeHittable()
        XCTAssertLessThanOrEqual(row.frame.maxY, alex.summary.frame.minY, "not under the summary bar")
        let highlighted = ScreenshotPixel.nearTopLeft(of: row.screenshot().image)
        let plain = ScreenshotPixel.nearTopLeft(of: alex.itemRow("Appetizers").waitToBeHittable().screenshot().image)
        XCTAssertFalse(highlighted.isEmpty)
        XCTAssertNotEqual(highlighted, plain, "the picked row has a tinted background")
    }

    /// LD-23 / LD-27: two tiny items merge into "other" at the end of the "to buy" side;
    /// a tap on it lists them with their amounts in a popover.
    @MainActor
    func testPurchaseBarOtherOpensPopover() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        alex.addItem(named: "Gum", price: "0.5", to: "Birthday")
        alex.addItem(named: "Mints", price: "0.5", to: "Birthday")

        alex.tapPurchaseBar(at: 0.998)

        let gum = app.descendants(matching: .any)["purchaseBar.other.Gum"].waitToAppear()
        XCTAssertTrue(gum.label.contains("$0.50"), gum.label)
        app.descendants(matching: .any)["purchaseBar.other.Mints"].waitToAppear()
        XCTAssertFalse(app.descendants(matching: .any)["purchaseBar.other.BBQ food"].exists)
    }

    /// LD-29: the outline of a "to buy" segment needs ≥ 3:1 against the summary bar. Victoria
    /// is green, about 2.2:1 on white as the plain system color.
    @MainActor
    func testPurchaseBarOutlineHasEnoughContrast() {
        let victoria = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Victoria")
        let bar = victoria.purchaseBar.waitToBeHittable()
        let contrast = ScreenshotContrast.strongest(in: bar.screenshot().image)
        XCTAssertGreaterThanOrEqual(contrast, 3, "outline contrast \(contrast)")
    }

    // MARK: - Groups (step 3b)

    /// LD-01: ⋯ → Add Group asks for the name; the new group goes last.
    @MainActor
    func testAddGroupGoesLast() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.addGroup(named: "Gifts")

        XCTAssertGreaterThan(alex.groupHeader("Gifts").frame.minY, alex.groupHeader("Birthday").frame.minY)
    }

    /// Owner decision 2026-11-13: in a list longer than the screen, a new group (added last)
    /// is scrolled into view, so its header can be used without scrolling by hand.
    @MainActor
    func testNewGroupIsScrolledIntoView() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        // Make the list longer than any iPhone screen.
        alex.startInline(in: "Vacation")
        app.typeText((1...8).map { "Extra \($0)\n" }.joined())
        alex.inlineDone()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast) // back to the top
        XCTAssertFalse(alex.addGroupRow.exists && alex.addGroupRow.isHittable, "the end of the list is off screen")

        alex.menuAction("addGroup")
        alex.typeGroupName("Gifts")

        alex.groupHeader("Gifts").waitToBeHittable()
        let summaryTop = alex.summary.exists ? alex.summary.frame.minY : app.frame.maxY
        XCTAssertLessThanOrEqual(alex.groupHeader("Gifts").frame.maxY, summaryTop, "not under the summary bar")
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
        // Leave and come back: the order was saved (DM-07).
        let reopened = alex.goBack().open(card: "Alex")
        XCTAssertLessThan(reopened.groupHeader("Birthday").waitToAppear().frame.minY,
                          reopened.groupHeader("Vacation").waitToAppear().frame.minY)
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
        // Drop in the upper part of the first row, not on its center: a row dropped exactly on
        // the center of the row above sometimes stays in place (CI, iOS 26: Swimsuit didn't move).
        let firstHandle = handles.element(boundBy: 0)
        let start = swimsuitHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = firstHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -24))
        start.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
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
        let alex = HomeScreen(app: Launch.app(longUndoToast: true)).waitUntilShown().open(card: "Alex")

        alex.swipeToDelete("Swimsuit")
        alex.undoButton.waitAndTap()
        alex.itemRow("Swimsuit").waitToAppear()
        alex.total.waitForLabel("$340.00")
        alex.undoToast.waitToDisappear() // Undo closes the toast at once
        // The same item in the same place: price, group total, between its neighbours.
        alex.itemTotal("Swimsuit").waitForLabel("$55.00")
        alex.groupTotal("Vacation").waitForLabel("$145.00")
        let swimsuit = alex.itemRow("Swimsuit").frame.minY
        XCTAssertLessThan(alex.itemRow("Sunglasses").frame.minY, swimsuit)
        XCTAssertLessThan(swimsuit, alex.itemRow("Flip-flops").frame.minY)
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

    // MARK: - Must-have (spec 11)

    /// MH-03 / MH-06 / MH-09: the leading swipe's second action marks a must-have: the ★ shows,
    /// the order stays, the summary bar gets "Must-haves $60.00". "Unmark" takes it all back.
    @MainActor
    func testSwipeMarksMustHaveAndShowsSummaryLine() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")
        let names = ["Sunglasses", "Swimsuit"]
        func order() -> [String] { names.sorted { alex.itemRow($0).frame.minY < alex.itemRow($1).frame.minY } }
        let before = order()
        XCTAssertFalse(alex.mustHaves.exists, "no must-haves, no line")

        alex.swipeToToggle("Swimsuit", action: "mustHave")
        alex.mustHaveMarker("Swimsuit").waitToAppear()
        alex.mustHaves.waitForLabel("Must-haves $55.00")
        XCTAssertEqual(order(), before, "no auto-sort")
        XCTAssertFalse(alex.checkbox("Swimsuit").isSelected, "a full swipe would be Bought; this isn't")
        XCTAssertEqual(alex.itemRow("Swimsuit").value as? String, "Must-have")

        alex.swipeToToggle("Swimsuit", action: "mustHave")
        alex.mustHaveMarker("Swimsuit").waitToDisappear()
        alex.mustHaves.waitToDisappear()
        XCTAssertEqual(order(), before)
    }

    /// MH-04: the context menu's Must-Have toggles the mark and shows it switched on.
    @MainActor
    func testContextMenuTogglesMustHave() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.contextMenu("Sunglasses", "mustHave")
        alex.mustHaveMarker("Sunglasses").waitToAppear()
        alex.mustHaves.waitForLabel("Must-haves $60.00")

        let toggle = alex.openContextMenu("Sunglasses", showing: "mustHave")
        XCTAssertTrue(toggle.isSelected || (toggle.value as? String) == "1", "shown switched on")
        toggle.tap()
        alex.mustHaveMarker("Sunglasses").waitToDisappear()
    }

    /// MH-05: the details switch shows the mark; ✕ drops a change, ✓ saves it.
    @MainActor
    func testItemDetailsMustHaveToggleSavesAndCancels() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        var editor = alex.openItem("Appetizers")
        XCTAssertEqual(editor.mustHaveToggle.waitToAppear().value as? String, "0")
        // The flip alone is an unsaved change (MH-05, unit-tested on `ItemDraft`).
        editor.flipMustHave()
        editor.cancel()
        XCTAssertFalse(alex.mustHaveMarker("Appetizers").exists, "✕ doesn't save")

        editor = alex.openItem("Appetizers")
        editor.flipMustHave()
        editor.done()
        alex.mustHaveMarker("Appetizers").waitToAppear()

        editor = alex.openItem("Appetizers")
        XCTAssertEqual(editor.mustHaveToggle.waitToAppear().value as? String, "1")
        editor.cancel()
    }
}
