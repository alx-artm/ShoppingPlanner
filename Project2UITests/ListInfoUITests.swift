//
//  ListInfoUITests.swift
//  Project2UITests
//
//  Spec 03 end to end: create a list in List Info (name, color, SF Symbol,
//  budget) and find it on Home (LI-01...LI-08, HM-03); cancel creates
//  nothing; the "Other…" emoji field; templates from the "+" menu and from
//  the empty state (LI-12). Seed data and en_US, see PlannerUITests.
//

import XCTest

final class ListInfoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// LI-01, LI-03, LI-04, LI-05, LI-08, HM-03, HM-06.
    @MainActor
    func testCreateListWithColorSymbolAndBudget() {
        let app = Launch.app()
        var home = HomeScreen(app: app).waitUntilShown()

        let info = home.openNewList()
        XCTAssertFalse(info.doneButton.isEnabled, "LI-01: ✓ is disabled without a name")
        info.color("blue").waitForSelected(true) // LI-03 default color
        info.typeName("Kids Room")
        XCTAssertTrue(info.doneButton.isEnabled)

        info.pickColor("mint")
        info.color("blue").waitForSelected(false)
        info.pickSymbol("bed.double")
        info.typeBudget("1500")
        home = info.done()

        // In All Lists, first (HM-03), with a status and "—" instead of "0" (HM-06).
        let row = home.row("Kids Room")
        row.waitForLabel(containing: "Empty")
        home.rowToBuy("Kids Room").waitForLabel("No prices yet")
        XCTAssertFalse(home.card("Kids Room").exists, "not pinned (LI-03)")
        XCTAssertLessThan(home.top(of: row), home.top(of: home.row("Eva")), "a new list comes first")

        // The values were saved: Edit shows them selected.
        let edit = home.editWithSwipe(row: "Kids Room")
        XCTAssertEqual(edit.nameField.value as? String, "Kids Room")
        edit.color("mint").scrollIntoViewLazily(within: edit.form).waitForSelected(true)
        edit.symbol("bed.double").scrollIntoViewLazily(within: edit.form).waitForSelected(true)
        let budget = edit.budgetField.scrollIntoViewLazily(within: edit.form, maxSwipes: 8)
        XCTAssertEqual(budget.value as? String, "$1,500.00", "LI-08: budget in the list currency")
        edit.cancel().row("Kids Room").waitToAppear()
    }

    /// LI-01: ✕ closes without creating anything.
    @MainActor
    func testCancelNewListCreatesNothing() {
        let home = HomeScreen(app: Launch.app()).waitUntilShown()

        let info = home.openNewList()
        info.typeName("Ghost")
        info.pickColor("red")
        _ = info.cancel()

        XCTAssertFalse(home.row("Ghost").exists)
        XCTAssertFalse(home.card("Ghost").exists)
        home.row("Eva").waitToAppear()
    }

    /// LI-06: a grid emoji is saved; text typed into "Other…" is flagged and not saved.
    @MainActor
    func testEmojiIconAndInvalidCustomEmoji() {
        let app = Launch.app()
        var home = HomeScreen(app: app).waitUntilShown()

        let info = home.openNewList()
        info.typeName("School")
        info.iconTab("Emoji").waitAndTap()
        info.emoji("🎒").scrollIntoViewLazily(within: info.form).tap()
        info.emoji("🎒").waitForSelected(true)

        let field = info.customEmojiField.scrollIntoViewLazily(within: info.form, maxSwipes: 8)
        field.tap()
        field.typeText("ab")
        app.staticTexts["Enter a single emoji."].waitToAppear()
        home = info.done()

        let edit = home.editWithSwipe(row: "School")
        // The icon is still the grid emoji; the text never replaced it.
        edit.emoji("🎒").scrollIntoViewLazily(within: edit.form).waitForSelected(true)
        XCTAssertEqual(edit.customEmojiField.scrollIntoViewLazily(within: edit.form, maxSwipes: 8).value as? String,
                       "Other…", "the invalid text was not saved")
        _ = edit.cancel()
    }

    /// LI-12: "+" menu → From Template → Trip → List Info prefilled → ✓ → list with empty groups.
    @MainActor
    func testCreateFromTemplateMenu() {
        let app = Launch.app()
        var home = HomeScreen(app: app).waitUntilShown()

        let info = home.openTemplatesFromMenu().pick("trip")
        XCTAssertEqual(info.nameField.value as? String, "Trip")
        info.color("mint").waitForSelected(true)
        XCTAssertTrue(info.doneButton.isEnabled)
        home = info.done()

        let trip = home.open(row: "Trip")
        for group in ["Tickets", "Accommodation", "Gear", "Food"] {
            trip.groupHeader(group).waitToAppear()
        }
        // Nothing planned yet: the summary bar is hidden, group totals show $0.00.
        trip.groupTotal("Tickets").waitForLabel("$0.00")
    }

    /// HM-14 + LI-12: the empty state offers "Start from Template" and "New List".
    @MainActor
    func testEmptyStateTemplateAndNewList() {
        let app = Launch.app(emptyStore: true)
        var home = HomeScreen(app: app).waitUntilShown()
        home.emptyState.waitToAppear()
        XCTAssertFalse(app.buttons["home.editButton"].isEnabled, "nothing to edit yet")

        home.emptyStateTemplateButton.waitAndTap()
        home = TemplatePickerScreen(app: app).waitUntilShown().pick("roomRenovation").done()
        home.row("Room Renovation").waitToAppear()
        home.emptyState.waitToDisappear()

        let room = home.open(row: "Room Renovation")
        for group in ["Furniture", "Materials", "Decor", "Lighting"] {
            room.groupHeader(group).waitToAppear()
        }
    }

    /// HM-14: "New List" in the empty state opens List Info.
    @MainActor
    func testEmptyStateNewList() {
        let app = Launch.app(emptyStore: true)
        let home = HomeScreen(app: app).waitUntilShown()

        home.emptyStateNewListButton.waitAndTap()
        _ = ListInfoScreen(app: app).waitUntilShown().typeName("First").done()

        home.row("First").waitForLabel(containing: "Empty")
        home.emptyState.waitToDisappear()
    }
}
