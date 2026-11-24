//
//  KeyboardShortcutsUITests.swift
//  Project2UITests
//
//  iPad keyboard shortcuts (spec 08 AD-12, M4 plan step 6, Q5 → A): ⌘N new item
//  (inline, in the group an item was added to last), ⇧⌘N new group; both are off
//  while item details are open; ⇧⌘M toggles Must-Have in item details (spec 11, MH-15).
//  ⌘⌫ can't be sent by XCUITest (see testCommandNIsOffWhileItemDetailsAreOpen).
//  iPad only: the commands live in the iPad menu bar; on iPhone the tests are skipped.
//  Seed data: in Eva the newest item is Jacket in Clothes (the last group).
//

import UIKit
import XCTest

final class KeyboardShortcutsUITests: XCTestCase {

    override func setUpWithError() throws {
        // XCTest calls setUp on the main thread.
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "Keyboard shortcuts are tested on iPad (AD-12)")
        continueAfterFailure = false
    }

    // MARK: - ⌘N

    /// ⌘N opens inline add in the group an item was added to last (Clothes in the seed),
    /// Return saves the item there; Return on the empty line closes inline add.
    @MainActor
    func testCommandNAddsItemToTheLastAddedGroup() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        eva.itemRow("Scooter").waitToAppear()

        let field = commandN(in: app)
        XCTAssertGreaterThan(field.frame.minY, eva.groupHeader("Clothes").frame.maxY,
                             "the new line is in Clothes, the group added to last")
        field.typeText("Hat\n")
        eva.itemRow("Hat").waitToAppear()
        field.typeText("\n")
        field.waitToDisappear()
        XCTAssertGreaterThan(eva.itemRow("Hat").frame.minY, eva.groupHeader("Clothes").frame.maxY)
    }

    /// After adding an item to Toys, ⌘N goes to Toys, not to the last group.
    @MainActor
    func testCommandNFollowsTheGroupAddedToLast() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")

        let inline = eva.startInline(in: "Toys")
        inline.typeText("Ball\n")
        eva.itemRow("Ball").waitToAppear()
        inline.typeText("\n")
        inline.waitToDisappear()

        let field = commandN(in: app)
        XCTAssertGreaterThan(field.frame.minY, eva.itemRow("Ball").frame.minY, "below Toys' items")
        XCTAssertLessThan(field.frame.maxY, eva.groupHeader("Clothes").frame.minY, "above Clothes")
    }

    /// LD-05a: in a list without groups ⌘N makes the "Items" group for the first item.
    @MainActor
    func testCommandNInAListWithoutGroupsMakesTheItemsGroup() {
        let app = Launch.app(emptyStore: true)
        let list = HomeScreen(app: app).waitUntilShown().createList(named: "Trip").open(row: "Trip")
        list.emptyState.waitToAppear()

        let field = commandN(in: app)
        list.groupHeader("Items").waitToAppear()
        field.typeText("Tent\n")
        list.itemRow("Tent").waitToAppear()
        field.typeText("\n")
        field.waitToDisappear()
        list.groupHeader("Items").waitToAppear()
    }

    // MARK: - ⇧⌘N

    /// ⇧⌘N asks for a group name and adds the group last (LD-01).
    @MainActor
    func testShiftCommandNAddsGroup() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        eva.itemRow("Scooter").waitToAppear()

        press("n", [.command, .shift], in: app, until: app.alerts.firstMatch)
        eva.typeGroupName("Shoes")
        eva.groupHeader("Shoes").waitToAppear()
        XCTAssertGreaterThan(eva.groupHeader("Shoes").frame.minY, eva.groupHeader("Clothes").frame.maxY)
    }

    // MARK: - While item details are open

    /// ⌘N doesn't start inline add behind an open item sheet. ⌘⌫ (delete the open item after
    /// a confirmation) can't be tested here: `typeKey` on the iPad simulator doesn't deliver
    /// Backspace with a modifier at all (⌘⌫ / ⌥⌫ don't even edit a text field), while ⌘ + a
    /// letter works. Its path (command → list screen → sheet → confirmation) was checked
    /// by hand with the command bound to ⌘D.
    @MainActor
    func testCommandNIsOffWhileItemDetailsAreOpen() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        let editor = eva.openItem("Scooter")

        press("n", .command, in: app)
        press("n", [.command, .shift], in: app)
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "no New Group alert")
        editor.cancel()
        XCTAssertFalse(app.textFields["inline.nameField"].exists, "no inline add behind the sheet")
    }

    /// MH-15: ⇧⌘M toggles Must-Have in the open item details (a draft change: ✓ saves it).
    @MainActor
    func testShiftCommandMTogglesMustHaveInItemDetails() {
        let app = Launch.app()
        let eva = HomeScreen(app: app).waitUntilShown().open(row: "Eva")
        let editor = eva.openItem("Scooter")
        editor.mustHaveToggle.waitForValue("0")

        press("m", [.command, .shift], in: app, untilValueOf: editor.mustHaveToggle, is: "1")
        editor.done()
        eva.mustHaveMarker("Scooter").waitToAppear()
    }

    // MARK: - Helpers

    /// Presses a shortcut like a user with a hardware keyboard. A lone Shift press goes first:
    /// on the iPadOS 26 simulator the first key event after the on-screen keyboard was in use
    /// (or after launch) only switches iPad to hardware-keyboard mode and never reaches the
    /// app, so ⌘N / ⇧⌘N were lost even seconds after launch. Shift alone does nothing in
    /// the app. `typeText` doesn't count: it types on the on-screen keyboard.
    @MainActor
    private func press(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication) {
        app.typeKey(XCUIKeyboardKey.shift, modifierFlags: [])
        app.typeKey(key, modifierFlags: modifiers)
    }

    /// Presses the shortcut until `result` appears. On a slow runner (CI, run 44061691931)
    /// a hardware key can still be lost after the Shift warm-up; a lost key changes nothing,
    /// and once `result` is up the shortcut isn't sent again, so retrying is safe.
    @MainActor
    private func press(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication,
                       until result: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            press(key, modifiers, in: app)
            if result.waitForExistence(timeout: 4) { return }
        }
        XCTFail("\(result) did not appear after 3 presses", file: file, line: line)
    }

    /// Presses the shortcut until `element`'s value is `expected`, for a shortcut that flips a
    /// switch. CI run 45367661367 (iPad): ⇧⌘M was sent once after the Shift warm-up and the
    /// recording shows the Must-Have switch still off 12 s later: the key was lost, not late.
    /// A retry must not undo a press that did arrive, so the value is read before each press
    /// and a press goes out only while the switch still shows the old value. Each press is a
    /// named step in the test report, so a run that needed a retry shows it.
    @MainActor
    private func press(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication,
                       untilValueOf element: XCUIElement, is expected: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let isExpected = NSPredicate(format: "value == %@", expected)
        for attempt in 1...3 {
            if element.value as? String == expected { return }
            XCTContext.runActivity(named: "Press \(key) (attempt \(attempt))") { _ in
                press(key, modifiers, in: app)
            }
            let changed = XCTNSPredicateExpectation(predicate: isExpected, object: element)
            if XCTWaiter().wait(for: [changed], timeout: 5) == .completed { return }
        }
        XCTFail("\(element) value is '\(element.value as? String ?? "nil")', expected '\(expected)' "
                + "after 3 presses", file: file, line: line)
    }

    /// ⌘N → the inline name field, with the keyboard focus.
    @MainActor
    private func commandN(in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let field = app.textFields["inline.nameField"]
        press("n", .command, in: app, until: field, file: file, line: line)
        XCTAssertTrue(field.waitForKeyboardFocus(), "the inline field has the keyboard",
                      file: file, line: line)
        return field
    }
}
