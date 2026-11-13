//
//  ItemDetailsUITests.swift
//  Project2UITests
//
//  Spec 05 item details on the seed data: the sheet edits a draft (✓ saves,
//  ✕ discards), total and "—", quantity limits, moving to another group,
//  delete with confirmation. Eva (USD): Toys = Teddy Bear 30, Puss in Boots 25,
//  Scooter 40; Clothes = T-Shirt 20 × 2, Sneakers 45, Jacket (no price).
//

import XCTest

final class ItemDetailsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// ID-01: ✕ throws the changes away.
    @MainActor
    func testCancelDiscardsChanges() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let editor = eva.openItem("Scooter")
        editor.replaceText(of: editor.nameField, with: "Bike")
        editor.replaceText(of: editor.priceField, with: "99")
        editor.cancel()

        eva.itemRow("Scooter").waitToAppear()
        XCTAssertFalse(eva.itemRow("Bike").exists)
        eva.itemTotal("Scooter").waitForLabel("$40.00")
    }

    /// ID-01 / ID-04: ✓ saves all fields at once; the total follows price × quantity live.
    @MainActor
    func testDoneSavesPriceAndQuantity() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let editor = eva.openItem("Scooter")
        editor.replaceText(of: editor.priceField, with: "12.5")
        editor.quantityIncrement.waitAndTap()
        editor.total.waitForLabel(containing: "$25.00")
        editor.done()

        eva.itemTotal("Scooter").waitForLabel("$25.00")
    }

    /// BUG-30 / ID-03a: in en_US the "$" prefix belongs next to the amount. The price field used to
    /// fill the row and right-align its text, so "$" sat by the label "Price per unit" and the
    /// digits at the far right ("Price per unit $ ……… 60.00"). The field's own frame can't show it:
    /// `LabeledContent` merges the label into the field's accessibility element, so that frame
    /// starts at the label in any layout. The test measures from the symbol to the field's right
    /// edge (where right-aligned digits end): only the digits may lie in between.
    @MainActor
    func testPricePrefixStaysNextToTheAmount() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        let editor = eva.openItem("Scooter")
        let field = editor.priceField.waitToAppear().frame
        let symbol = editor.app.descendants(matching: .any)["itemEdit.priceField.symbol"].firstMatch
            .waitToAppear().frame
        let row = editor.form.frame
        XCTAssertGreaterThan(symbol.minX, row.midX, "the symbol is on the right, by the digits")
        XCTAssertLessThan(field.maxX - symbol.minX, row.width / 3,
                          "symbol at \(symbol.minX), digits end at \(field.maxX) of \(row.width) pt")
        editor.cancel()
    }

    /// ID-04 / LD-08: an item without a price shows "—", not 0.
    @MainActor
    func testItemWithoutPriceShowsDash() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let editor = eva.openItem("Jacket")
        editor.total.waitForLabel(containing: "No price")
        XCTAssertEqual(editor.priceField.value as? String ?? "", editor.priceField.placeholderValue ?? "",
                       "an empty price field, not 0")
    }

    /// ID-05: the quantity field clamps to 1...999.
    @MainActor
    func testQuantityFieldIsClamped() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let editor = eva.openItem("Scooter")
        editor.replaceText(of: editor.quantityField, with: "5000")
        editor.total.waitForLabel(containing: "$39,960.00") // 40 × 999
        editor.replaceText(of: editor.quantityField, with: "0")
        editor.total.waitForLabel(containing: "$40.00")     // 0 → 1
    }

    /// ID-02: ✓ is disabled for a blank name.
    @MainActor
    func testBlankNameCannotBeSaved() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")

        let editor = eva.openItem("Scooter")
        editor.replaceText(of: editor.nameField, with: "   ")
        XCTAssertEqual((editor.nameField.value as? String)?.trimmingCharacters(in: .whitespaces), "")
        editor.doneButton.waitForEnabled(false)
    }

    /// ID-08: the group picker moves the item on ✓.
    @MainActor
    func testGroupPickerMovesItem() {
        let eva = HomeScreen(app: Launch.app()).waitUntilShown().open(row: "Eva")
        eva.groupTotal("Toys").waitForLabel("$95.00")

        let editor = eva.openItem("Scooter")
        editor.moveToGroup("Clothes")
        editor.done()

        eva.groupTotal("Toys").waitForLabel("$55.00")
        eva.groupTotal("Clothes").waitForLabel("$125.00")
    }
}
