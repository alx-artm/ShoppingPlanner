//
//  InlineAddUITests.swift
//  Project2UITests
//
//  Spec 04 inline add (LD-12...LD-17, LD-05a, 05 ID-09): "＋ New Item"
//  becomes a text field, Return saves and keeps the keyboard, the accessory
//  bar adds price / quantity / link, Done and ⓘ save, an empty draft is
//  dropped, and the summary bar is one line while typing.
//

import XCTest

final class InlineAddUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// LD-13: ten items in a row without a modal; they appear in the order typed.
    @MainActor
    func testTenItemsInARowKeepFocus() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.createList(named: "Party")
        let party = home.open(row: "Party")
        party.addGroup(named: "Food")

        let field = party.startInline(in: "Food")
        let names = (1...10).map { "Item \($0)" }
        for name in names {
            // `app.typeText` types into whatever has the focus, like a user does; typing into the
            // element would tap it first and hide a lost focus.
            app.typeText(name + "\n")
            party.itemRow(name).waitToAppear()
            XCTAssertTrue(field.waitForKeyboardFocus(timeout: 2), "focus kept after \(name)")
            XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "an empty new line")
        }
        party.inlineDone()

        var lastTop: CGFloat = -1
        for name in names {
            let row = party.itemRow(name).waitToAppear()
            XCTAssertGreaterThan(row.frame.minY, lastTop, "\(name) is below the previous item")
            lastTop = row.frame.minY
        }
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    /// Fast typing, line after line with no pause, saves every line exactly once.
    /// (One `typeText` per line: XCUITest's single-call burst of hundreds of keys per second
    /// can still split a word around the field reset after Return; people don't type that fast.)
    @MainActor
    func testFastTypingSavesEachLineOnce() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        eva.startInline(in: "Toys")
        for line in ["Kite\n", "Ball\n", "Puzzle\n"] {
            app.typeText(line)
        }
        eva.inlineDone()

        for name in ["Kite", "Ball", "Puzzle"] {
            eva.itemRow(name).waitToAppear()
            XCTAssertEqual(app.buttons.matching(identifier: "item.row.\(name)").count, 1, name)
        }
    }

    /// LD-12 / LD-16 / LD-17: trimmed on commit, typed text kept as a name, no parsing.
    @MainActor
    func testTextIsTakenAsTyped() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let field = eva.startInline(in: "Toys")
        field.typeText("  Sofa 450 x2  \n")
        eva.inlineDone()

        eva.itemTotal("Sofa 450 x2").waitForLabel("No price")
        XCTAssertFalse(eva.itemDetail("Sofa 450 x2").exists, "quantity 1, no price: no second line")
    }

    /// LD-15 / LD-15a: [Price] and [Qty] in the row, with a live line total.
    @MainActor
    func testPriceAndQuantityFromAccessoryBar() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let field = eva.startInline(in: "Toys")
        field.typeText("Kite")
        eva.app.buttons["inline.accessory.price"].waitAndTap()
        eva.app.textFields["inline.priceField"].waitToAppear().typeText("12.5")
        eva.app.buttons["inline.accessory.quantity"].waitAndTap()
        eva.app.buttons["inline.quantityStepper-Increment"].waitAndTap()
        eva.app.staticTexts["inline.total"].waitForLabel("= $25.00")
        eva.inlineDone()

        eva.itemTotal("Kite").waitForLabel("$25.00")
        eva.itemDetail("Kite").waitForLabel("2 × $12.50")
    }

    /// LD-12: Done with an empty draft creates nothing.
    @MainActor
    func testEmptyDraftIsDropped() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        let before = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.row.'")).count

        let field = eva.startInline(in: "Toys")
        field.typeText("   ")
        eva.inlineDone()

        eva.addItemButton("Toys").waitToAppear()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.row.'")).count, before)
    }

    /// Owner decision: while typing, the summary bar is one line "To buy $X · N%".
    @MainActor
    func testCompactSummaryWhileTyping() {
        let alex = HomeScreen(app: Launch.app()).waitUntilShown().open(card: "Alex")

        alex.startInline(in: "Vacation")
        alex.app.staticTexts["listDetail.summary.compact"].waitForLabel("To buy $340.00 · 8%")
        XCTAssertFalse(alex.budget.exists)

        alex.inlineDone()
        alex.budget.waitToAppear()
    }

    /// ID-09: ⓘ saves the draft and opens details on the first empty field (Price).
    @MainActor
    func testDetailsButtonSavesAndOpensDetails() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let field = eva.startInline(in: "Toys")
        field.typeText("Kite")
        eva.app.buttons["inline.accessory.details"].waitAndTap()

        let editor = ItemEditScreen(app: eva.app).waitUntilShown()
        XCTAssertEqual(editor.nameField.value as? String, "Kite")
        XCTAssertTrue(editor.priceField.waitToAppear().value(forKey: "hasKeyboardFocus") as? Bool ?? false,
                      "the price field has the focus")
        editor.cancel()
        eva.itemRow("Kite").waitToAppear()
    }

    /// LD-05a: in a list without groups, the first item creates the group "Items".
    @MainActor
    func testFirstItemCreatesGroup() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.createList(named: "Party")
        let party = home.open(row: "Party")

        app.buttons["listDetail.emptyState.addItemButton"].waitAndTap()
        app.textFields["inline.nameField"].waitToAppear().typeText("Cake\n")
        party.inlineDone()

        party.groupHeader("Items").waitToAppear()
        party.itemRow("Cake").waitToAppear()
    }

    /// LD-05a: the "Items" group goes away again if nothing was added.
    @MainActor
    func testFirstItemCancelledLeavesNoGroup() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.createList(named: "Party")
        let party = home.open(row: "Party")

        app.buttons["listDetail.emptyState.addItemButton"].waitAndTap()
        app.textFields["inline.nameField"].waitToAppear()
        party.inlineDone()

        party.emptyState.waitToAppear()
        XCTAssertFalse(party.groupHeader("Items").exists)
    }
}
