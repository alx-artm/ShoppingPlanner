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
        for (index, name) in names.enumerated() {
            // `app.typeText` types into whatever has the focus, like a user does; typing into the
            // element would tap it first and hide a lost focus.
            app.typeText(name + "\n")
            let row = party.itemRow(name).waitToAppear()
            XCTAssertTrue(field.waitForKeyboardFocus(timeout: 2), "focus kept after \(name)")
            XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "an empty new line")
            // In the order typed (checked pairwise: early rows scroll out of the lazy list).
            if index > 0 {
                let previous = party.itemRow(names[index - 1])
                if previous.exists {
                    XCTAssertLessThan(previous.frame.minY, row.frame.minY, "\(name) is below the previous item")
                }
            }
        }
        party.inlineDone()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    /// Typing faster than a person (one burst of keys with Returns) saves every line exactly
    /// once and unbroken: the field empties itself inside the Return key press.
    @MainActor
    func testFastTypingSavesEachLineOnce() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        eva.startInline(in: "Toys")
        app.typeText("Kite\nBall\nPuzzle\n")
        eva.inlineDone()

        for name in ["Kite", "Ball", "Puzzle"] {
            eva.itemRow(name).waitToAppear()
            XCTAssertEqual(app.buttons.matching(identifier: "item.row.\(name)").count, 1, name)
        }
    }

    /// Typed character by character at a normal pace, right after the field gets the focus
    /// and right after each Return: every name is saved exactly as typed.
    @MainActor
    func testCharacterByCharacterNamesAreExact() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        let names = ["Puzzle", "Kite", "Ball"]

        eva.startInline(in: "Toys")
        for name in names {
            for character in name { app.typeText(String(character)) }
            app.typeText("\n")
        }
        eva.inlineDone()

        for name in names {
            eva.itemRow(name).waitToAppear()
        }
        XCTAssertFalse(app.buttons["item.row.uzzleP"].exists)
    }

    /// The next letters arrive in the same burst as Return (fast typist, hardware keyboard).
    /// The screen rewrites the field after Return; the caret must stay at the end, so the
    /// text left in the field is exactly the last word typed, never "uzzleP" (5 rounds).
    @MainActor
    func testLetterRightAfterReturnKeepsCaretAtEnd() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        let field = eva.startInline(in: "Toys")
        for round in 1...5 {
            app.typeText((round == 1 ? "" : "\n") + "Kite\nBall\nPuzzle")
            XCTAssertEqual(field.value as? String, "Puzzle", "round \(round)")
        }
        app.typeText("\n")
        eva.inlineDone()

        // 3 seed toys + 15 new ones, none split in two (rows of a long list aren't all on screen).
        eva.groupHeader("Toys").tap()
        eva.groupCount("Toys").waitForLabel("(18)")
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

    /// LD-15 / LP-08: [Link] opens a URL field in the row; the saved item shows the host chip
    /// and its context menu offers "Open Link" (LD-09). The link isn't opened (Safari).
    @MainActor
    func testLinkFromAccessoryBar() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        let field = eva.startInline(in: "Toys")
        field.typeText("Kite")
        app.buttons["inline.accessory.link"].waitAndTap()
        app.textFields["inline.linkField"].waitToAppear().typeText("www.kites.example.com/red")
        eva.inlineDone()

        eva.app.descendants(matching: .any)["item.link.Kite"].firstMatch.waitForLabel(containing: "kites.example.com")
        eva.reveal(eva.itemRow("Kite")).perform("Long press", until: app.buttons["item.menu.openLink"]) {
            $0.press(forDuration: 1.2)
        }
        XCTAssertFalse(app.buttons["item.menu.openLink"].firstMatch.label.isEmpty)
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
