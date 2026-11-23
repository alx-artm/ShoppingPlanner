//
//  Screens.swift
//  Project2UITests
//
//  Screen objects: one small type per screen that knows its accessibility
//  identifiers. Tests read like user stories ("open list, add group") and an
//  identifier change is fixed in one place.
//

import XCTest

@MainActor
struct HomeScreen {
    let app: XCUIApplication

    var newListButton: XCUIElement { app.buttons["home.newListButton"] }
    var settingsButton: XCUIElement { app.buttons["home.settingsButton"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["home.emptyState"].firstMatch }

    /// Pinned lists are tiles ("cards"), the others are rows.
    func card(_ name: String) -> XCUIElement { app.buttons["home.listCard.\(name)"] }
    func row(_ name: String) -> XCUIElement { app.buttons["home.listRow.\(name)"] }
    /// The formatted "to buy" amount of a card / row ("$340.00").
    func cardToBuy(_ name: String) -> XCUIElement { app.staticTexts["home.listCard.toBuy.\(name)"] }
    func rowToBuy(_ name: String) -> XCUIElement { app.staticTexts["home.listRow.toBuy.\(name)"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> HomeScreen {
        newListButton.waitToAppear(file: file, line: line)
        return self
    }

    /// Taps a tile; a tap the slow runner lost is sent again (see `tap(until:)`).
    func open(card name: String) -> ListDetailScreen {
        card(name).tap(until: .appears(ListDetailScreen.navigationBar(name, in: app)))
        return ListDetailScreen(app: app).waitUntilShown()
    }

    /// Taps a row; a tap the slow runner lost is sent again (CI run 44785776879, iPad).
    func open(row name: String) -> ListDetailScreen {
        row(name).tap(until: .appears(ListDetailScreen.navigationBar(name, in: app)))
        return ListDetailScreen(app: app).waitUntilShown()
    }

    /// Home → "+" → List Info: type a name → Done.
    @discardableResult
    func createList(named name: String) -> HomeScreen {
        newListButton.waitAndTap()
        let nameField = app.textFields["listEdit.nameField"].waitToAppear()
        nameField.tap()
        nameField.typeText(name)
        app.buttons["listEdit.doneButton"].waitAndTap()
        nameField.waitToDisappear()
        return self
    }

    /// Long press → "Delete" → confirm.
    /// Gear in the toolbar → Settings sheet (spec 08: no tab bar).
    func openSettings() -> SettingsScreen {
        settingsButton.waitAndTap()
        return SettingsScreen(app: app).waitUntilShown()
    }

    func deleteFromContextMenu(row name: String) {
        row(name).scrollIntoView(within: app.collectionViews.firstMatch)
            .perform("Long press", until: app.buttons["home.menu.delete"],
                     recover: { backFromMisfiredGesture(on: row(name)) }) {
            $0.press(forDuration: 1.5)
        }.waitAndTap()
        // Dialog buttons can expose their identifier twice; take the first match.
        app.buttons["home.deleteAlert.confirmButton"].firstMatch.waitAndTap()
    }
}

@MainActor
struct ListDetailScreen {
    let app: XCUIApplication

    var menuButton: XCUIElement { app.buttons["listDetail.menuButton"] }
    /// "＋ Add Group" at the end of the list.
    var addGroupRow: XCUIElement { app.buttons["listDetail.addGroupRow"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["listDetail.emptyState"].firstMatch }
    var undoToast: XCUIElement { app.descendants(matching: .any)["undoToast"].firstMatch }
    var undoButton: XCUIElement { app.buttons["undoToast.undoButton"] }
    /// "Copy of “Eva” created · Undo" after Duplicate (HM-41).
    var duplicateToast: XCUIElement { app.descendants(matching: .any)["duplicateToast"].firstMatch }
    var duplicateUndoButton: XCUIElement { app.buttons["duplicateToast.undoButton"] }
    func boughtRow(_ group: String) -> XCUIElement { app.buttons["group.boughtRow.\(group)"] }
    var total: XCUIElement { app.staticTexts["listDetail.total"] }
    /// Not scoped to `navigationBars`: on some devices (iPhone Duo) the system
    /// renders the back button in a side rail outside the navigation bar.
    var backButton: XCUIElement { app.buttons["BackButton"].firstMatch }

    /// Tapping the header collapses / expands the group (LD-02).
    func groupHeader(_ group: String) -> XCUIElement { app.buttons["group.header.\(group)"] }
    func groupMenu(_ group: String) -> XCUIElement { app.buttons["group.menu.\(group)"] }
    /// "(3)" next to a collapsed group's name (LD-04).
    func groupCount(_ group: String) -> XCUIElement { app.staticTexts["group.count.\(group)"] }
    func groupTotal(_ group: String) -> XCUIElement { app.staticTexts["group.total.\(group)"] }
    func addItemButton(_ group: String) -> XCUIElement { app.buttons["group.addItemButton.\(group)"] }
    /// The row without its checkbox: a button that opens item details.
    func itemRow(_ item: String) -> XCUIElement { app.buttons["item.row.\(item)"] }
    /// "2 × $55.00 · note" under the name.
    func itemDetail(_ item: String) -> XCUIElement { app.staticTexts["item.detail.\(item)"] }
    var summary: XCUIElement { app.descendants(matching: .any)["listDetail.summary"].firstMatch }
    var planned: XCUIElement { app.staticTexts["listDetail.planned"] }
    var progress: XCUIElement { app.staticTexts["listDetail.progress"] }
    var unpriced: XCUIElement { app.staticTexts["listDetail.unpriced"] }
    var budget: XCUIElement { app.staticTexts["listDetail.budget"] }
    /// The segmented purchase bar: one adjustable VoiceOver element (LD-28).
    var purchaseBar: XCUIElement { app.descendants(matching: .any)["listDetail.purchaseBar"].firstMatch }
    func checkbox(_ item: String) -> XCUIElement { app.buttons["item.checkbox.\(item)"] }
    func itemTotal(_ item: String) -> XCUIElement { app.staticTexts["item.total.\(item)"] }
    /// The name of a must-have row, with its ★ (spec 11, MH-03); missing for an unmarked row.
    func mustHaveMarker(_ item: String) -> XCUIElement {
        app.descendants(matching: .any)["item.mustHave.\(item)"].firstMatch
    }
    /// "★ Must-haves $60.00" under the budget line (MH-09).
    var mustHaves: XCUIElement { app.descendants(matching: .any)["listDetail.mustHaves"].firstMatch }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ListDetailScreen {
        menuButton.waitToAppear(file: file, line: line)
        return self
    }

    /// The navigation bar titled with the list's name. Unlike `menuButton` it tells which list
    /// is open: on iPad another list can already be showing in the detail column.
    static func navigationBar(_ listName: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars[listName]
    }

    /// Undoes a gesture that arrived as a tap and opened this list on top of `element`'s
    /// screen (Home, its search results, the Archive): Back, then wait for `element` again.
    /// The retry decides on the list itself (its ⋯ gone), not on the screen below, so a slow
    /// Back is never tapped twice into the screen before (the Archive has a Back button too).
    func backFromMisfiredGesture(on element: XCUIElement) {
        guard !element.isHittable, menuButton.exists, backButton.exists else { return }
        backButton.tap(until: .disappears(menuButton))
        element.waitToAppear()
    }

    /// ⋯ → Add Group → alert: type the name → Add. The group goes last (LD-01).
    @discardableResult
    func addGroup(named name: String) -> ListDetailScreen {
        menuAction("addGroup")
        typeGroupName(name)
        // The list scrolls to the new group by itself, also on small phones.
        groupHeader(name).waitToBeHittable()
        return self
    }

    /// Toolbar ⋯ → `action` (edit, addGroup, toggleCompleted, toggleExpanded, reorderGroups,
    /// share, duplicate, delete).
    func menuAction(_ action: String) {
        menuButton.waitAndTap()
        app.buttons["listDetail.menu.\(action)"].waitAndTap()
    }

    /// Long press a row → `action` of its context menu (edit, duplicate, openLink, delete).
    func contextMenu(_ item: String, _ action: String) {
        openContextMenu(item, showing: action).waitAndTap()
    }

    /// Long press a row until its context menu shows `action`; returns that menu button
    /// (not tapped). A press the slow runner took as a tap opened the item's details:
    /// it is closed before the next attempt (CI run 44764424769).
    @discardableResult
    func openContextMenu(_ item: String, showing action: String,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        reveal(itemRow(item)).perform("Long press", until: app.buttons["item.menu.\(action)"],
                                      file: file, line: line, recover: closeMisfiredItemDetails) {
            $0.press(forDuration: 1.2)
        }
    }

    /// A gesture on a row that the busy app (slow CI runner) received as a tap opens the
    /// item's details sheet over the list: close it so the gesture can be retried.
    /// Runs only before a retry, so a short wait for a sheet still sliding in costs nothing
    /// on a passing run; without it a late sheet would cover the row on the next attempt.
    func closeMisfiredItemDetails() {
        let details = ItemEditScreen(app: app)
        if details.cancelButton.waitForExistence(timeout: 2) { details.cancel() }
    }

    /// Swipe right on a row → Bought / Not Bought (LD-09), or with `action: "mustHave"`
    /// Must-Have / Unmark (spec 11, MH-03).
    func swipeToToggle(_ item: String, action: String = "toggle") {
        let button = app.buttons["item.swipe.\(action)"]
        reveal(itemRow(item)).perform("Swipe right", until: button, recover: closeMisfiredItemDetails) {
            let start = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            let end = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }.waitAndTap()
    }

    /// "＋ New Item" in `group` → inline: name, [Price], [Qty] → Done (spec 04 Inline add).
    @discardableResult
    func addItem(named name: String, price: String? = nil, quantity: Int = 1,
                 to group: String) -> ListDetailScreen {
        let field = startInline(in: group)
        field.typeText(name)
        if let price {
            tapAccessory("price")
            app.typeNumber(price, into: focusedInlineField("inline.priceField"))
        }
        if quantity > 1 {
            tapAccessory("quantity")
            let increment = app.buttons["inline.quantityStepper-Increment"].waitToAppear()
            for _ in 1..<quantity { increment.tap() }
        }
        inlineDone()
        itemRow(name).waitToAppear()
        return self
    }

    /// "＋ New Item" in `group` → the inline name field, focused.
    @discardableResult
    func startInline(in group: String) -> XCUIElement {
        reveal(addItemButton(group)).tap()
        let field = app.textFields["inline.nameField"].waitToAppear()
        XCTAssertTrue(field.waitForKeyboardFocus(), "the inline field has the keyboard")
        return field
    }

    /// An inline extra field ("inline.priceField", "inline.linkField") once it has the keyboard.
    /// The accessory button inserts the field first and moves the focus when it appears, so on
    /// a slow machine (CI) typing right after `waitToAppear` could land before the focus does.
    func focusedInlineField(_ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier].waitToAppear()
        XCTAssertTrue(field.waitForKeyboardFocus(), "\(identifier) has the keyboard")
        return field
    }

    /// A button of the inline accessory bar: "price", "quantity", "link", "details", "done".
    /// On iPad the price's number pad popover is closed first, or it would eat the tap.
    func tapAccessory(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        app.dismissNumberPadPopover(file: file, line: line)
        app.buttons["inline.accessory.\(name)"].waitAndTap(file: file, line: line)
    }

    /// Done on the keyboard's accessory bar: saves a non-empty draft and closes inline add.
    func inlineDone(file: StaticString = #filePath, line: UInt = #line) {
        tapAccessory("done", file: file, line: line)
        app.textFields["inline.nameField"].waitToDisappear(file: file, line: line)
    }

    /// Taps the purchase bar at `fraction` (0...1) of its width, in the middle of its 44 pt row.
    func tapPurchaseBar(at fraction: CGFloat) {
        purchaseBar.waitToBeHittable()
            .coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
    }

    /// Tap the row → item details sheet (LD-06).
    func openItem(_ name: String) -> ItemEditScreen {
        reveal(itemRow(name)).tap(until: .appears(ItemEditScreen(app: app).nameField))
        return ItemEditScreen(app: app).waitUntilShown()
    }

    /// Scrolls until `element` is on screen and not under the summary bar, which floats
    /// over the bottom of the list (rows under it exist and look hittable to XCTest).
    @discardableResult
    func reveal(_ element: XCUIElement, maxSwipes: Int = 5) -> XCUIElement {
        element.waitToAppear()
        let list = app.collectionViews.firstMatch
        for _ in 0..<maxSwipes {
            let limit = summary.exists ? summary.frame.minY : app.frame.maxY
            if element.isHittable && element.frame.maxY <= limit { break }
            list.swipeUp(velocity: .slow)
        }
        return element
    }

    /// Group ⋯ → `action` ("rename", "addItem", "delete").
    func groupMenuAction(_ group: String, _ action: String) {
        groupMenu(group).waitAndTap()
        app.buttons["group.menu.\(action)"].waitAndTap()
    }

    /// Group ⋯ → Delete Group → confirm (a group with items asks first, LD-05).
    func deleteGroup(_ name: String, confirm: Bool = true) {
        groupMenuAction(name, "delete")
        if confirm {
            app.buttons["groupDelete.confirmButton"].firstMatch.waitAndTap()
        }
        groupHeader(name).waitToDisappear()
    }

    /// Group ⋯ → Rename → alert with the name field → Save.
    func renameGroup(_ name: String, to newName: String) {
        groupMenuAction(name, "rename")
        typeGroupName(newName, replacing: name)
        groupHeader(newName).waitToAppear()
    }

    /// The New Group / Rename alert: type the name and confirm. Alerts don't expose
    /// the identifiers of their fields, so the field and buttons are found in the alert.
    func typeGroupName(_ newName: String, replacing old: String = "") {
        let alert = app.alerts.firstMatch.waitToAppear()
        let field = alert.textFields.firstMatch.waitToAppear()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + newName)
        alert.buttons.element(boundBy: 1).waitAndTap() // Cancel, then Save / Add
        alert.waitToDisappear()
    }

    func toggleShowCompleted() {
        menuAction("toggleCompleted")
    }

    /// Swipe left on a row and tap "Delete". A full swipe deletes at once, which also counts.
    func swipeToDelete(_ item: String) {
        let row = itemRow(item)
        let deleteButton = app.buttons["item.swipe.delete"]
        let result = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["item.swipe.delete", "undoToast"])).firstMatch
        reveal(row).perform("Swipe left", until: result, recover: closeMisfiredItemDetails) {
            let start = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            let end = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        if deleteButton.exists { deleteButton.tap() }
    }

    /// Menu → "Delete list" → confirm. The screen pops back to Home.
    @discardableResult
    func deleteList() -> HomeScreen {
        menuAction("delete")
        app.buttons["listDetail.deleteAlert.confirmButton"].firstMatch.waitAndTap()
        return HomeScreen(app: app).waitUntilShown()
    }

    func goBack() -> HomeScreen {
        backButton.tap(until: .appears(HomeScreen(app: app).newListButton))
        return HomeScreen(app: app).waitUntilShown()
    }
}

@MainActor
struct ItemEditScreen {
    let app: XCUIApplication

    var form: XCUIElement { app.collectionViews["itemEdit.form"] }
    var nameField: XCUIElement { app.textFields["itemEdit.nameField"] }
    var priceField: XCUIElement { app.textFields["itemEdit.priceField"] }
    var quantityField: XCUIElement { app.textFields["itemEdit.quantityField"] }
    var urlField: XCUIElement { app.textFields["itemEdit.urlField"] }
    var notesField: XCUIElement { app.textFields["itemEdit.notesField"] }
    var total: XCUIElement { app.staticTexts["itemEdit.total"] }
    var quantityIncrement: XCUIElement { app.buttons["itemEdit.quantityStepper-Increment"] }
    var groupPicker: XCUIElement { app.buttons["itemEdit.groupPicker"] }
    var doneButton: XCUIElement { app.buttons["itemEdit.doneButton"] }
    var cancelButton: XCUIElement { app.buttons["itemEdit.cancelButton"] }
    var mustHaveToggle: XCUIElement { app.switches["itemEdit.mustHaveToggle"].firstMatch }

    /// Flips the Must-Have switch: a tap on its trailing edge, where the switch is (the
    /// middle of the row is the label).
    func flipMustHave() {
        let before = mustHaveToggle.waitToAppear().value as? String
        mustHaveToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        mustHaveToggle.waitForValue(before == "1" ? "0" : "1")
    }
    var deleteButton: XCUIElement { app.buttons["itemEdit.deleteButton"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ItemEditScreen {
        nameField.waitToAppear(file: file, line: line)
        return self
    }

    /// Replaces the text of a field (select all is not reliable, so delete key by key).
    /// The tap goes to the field's right end, so the cursor lands after the text
    /// in both leading- and trailing-aligned fields.
    /// Price and quantity are typed on the iPad number pad popover (see `typeNumber`).
    func replaceText(of field: XCUIElement, with text: String) {
        app.dismissNumberPadPopover()
        field.waitToBeHittable()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        let keys = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text
        if ["itemEdit.priceField", "itemEdit.quantityField"].contains(field.identifier) {
            app.typeNumber(keys, into: field)
        } else {
            field.typeText(keys)
        }
    }

    /// "Delete Item" → confirm. The sheet closes, then the item is deleted (ID-11).
    func delete() {
        app.dismissNumberPadPopover()
        deleteButton.scrollIntoViewLazily(within: form).tap()
        app.buttons["itemEdit.deleteAlert.confirmButton"].firstMatch.waitAndTap()
        nameField.waitToDisappear()
    }

    /// ✓ → the sheet closes.
    func done() {
        app.dismissNumberPadPopover()
        doneButton.waitAndTap()
        nameField.waitToDisappear()
    }

    /// ✕ → the sheet closes without saving. From inline ⓘ the price field has the focus, so
    /// on iPad its number pad popover is open and is closed first.
    func cancel() {
        app.dismissNumberPadPopover()
        cancelButton.waitAndTap()
        nameField.waitToDisappear()
    }

    /// Stepper "+" once. After a typed price or quantity the iPad keyboard is settled first
    /// (see `settleKeyboardBeforeTapInSheet`).
    func incrementQuantity(file: StaticString = #filePath, line: UInt = #line) {
        app.settleKeyboardBeforeTapInSheet(file: file, line: line)
        quantityIncrement.waitToBeHittable(file: file, line: line).tap()
    }

    /// Group picker → choose `group`.
    func moveToGroup(_ group: String) {
        app.dismissNumberPadPopover()
        groupPicker.scrollIntoViewLazily(within: form).tap()
        app.buttons[group].firstMatch.waitAndTap()
    }
}

// MARK: - Settings, currency picker (spec 07)

@MainActor
struct SettingsScreen {
    let app: XCUIApplication

    /// Navigation row "Main Currency  Euro · EUR · €".
    var mainCurrency: XCUIElement { app.buttons["settings.mainCurrency"] }
    var appearancePicker: XCUIElement { app.descendants(matching: .any)["settings.appearancePicker"].firstMatch }
    var icloudStatus: XCUIElement { app.descendants(matching: .any)["settings.icloudStatus"].firstMatch }
    var version: XCUIElement { app.descendants(matching: .any)["settings.version"].firstMatch }
    var doneButton: XCUIElement { app.buttons["settings.doneButton"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> SettingsScreen {
        mainCurrency.waitToAppear(file: file, line: line)
        return self
    }

    /// Done → back to Home.
    func close() -> HomeScreen {
        doneButton.waitAndTap()
        mainCurrency.waitToDisappear()
        return HomeScreen(app: app).waitUntilShown()
    }

    func openCurrencyPicker() -> CurrencyPickerScreen {
        mainCurrency.waitAndTap()
        return CurrencyPickerScreen(app: app).waitUntilShown()
    }
}

@MainActor
struct CurrencyPickerScreen {
    let app: XCUIApplication

    var list: XCUIElement { app.descendants(matching: .any)["currencyPicker.list"].firstMatch }
    var searchField: XCUIElement { app.searchFields.firstMatch }

    func row(_ code: String) -> XCUIElement { app.buttons["currencyPicker.row.\(code)"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> CurrencyPickerScreen {
        searchField.waitToAppear(file: file, line: line)
        return self
    }

    @discardableResult
    func search(_ text: String) -> CurrencyPickerScreen {
        searchField.waitAndTap()
        searchField.typeText(text)
        return self
    }

    /// Taps a currency; the picker pops back to Settings.
    @discardableResult
    func select(_ code: String) -> SettingsScreen {
        row(code).waitAndTap()
        // Not the search field: Home's own search field stays under the Settings sheet.
        row(code).waitToDisappear()
        return SettingsScreen(app: app).waitUntilShown()
    }
}

// MARK: - Home actions of M3 (spec 02): swipe, context menu, search, templates

extension HomeScreen {
    var list: XCUIElement { app.collectionViews.firstMatch }
    var searchField: XCUIElement { app.searchFields.firstMatch }
    var emptyStateNewListButton: XCUIElement { app.buttons["home.emptyState.newListButton"] }
    var emptyStateTemplateButton: XCUIElement { app.buttons["home.emptyState.templateButton"] }

    /// "+" → New List → List Info in create mode.
    func openNewList() -> ListInfoScreen {
        newListButton.waitAndTap()
        return ListInfoScreen(app: app).waitUntilShown()
    }

    /// ⋯ in the toolbar (HM-31) and its items (HM-32, HM-38).
    var menuButton: XCUIElement { app.buttons["home.menuButton"] }
    var reorderListsItem: XCUIElement { app.buttons["home.menu.reorderLists"] }
    var reorderDoneButton: XCUIElement { app.buttons["home.reorderDoneButton"] }

    /// ⋯ → "New from Template" → template picker (HM-38).
    func openTemplatesFromMoreMenu() -> TemplatePickerScreen {
        menuButton.waitAndTap()
        app.buttons["home.menu.newFromTemplate"].waitAndTap()
        return TemplatePickerScreen(app: app).waitUntilShown()
    }

    /// ⋯ → "Reorder Lists": rows with drag handles and only Done in the toolbar (HM-33).
    func startReorderingLists() {
        menuButton.waitAndTap()
        reorderListsItem.waitAndTap()
        reorderDoneButton.waitToAppear()
    }

    /// ⋯ open: is "Reorder Lists" enabled? Closes the menu again (HM-32).
    func isReorderListsEnabled() -> Bool {
        menuButton.waitAndTap()
        let enabled = reorderListsItem.waitToAppear().isEnabled
        // A tap outside the menu closes it without choosing anything.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        reorderListsItem.waitToDisappear()
        return enabled
    }

    /// Long press "+" → "From Template" → template picker (LI-12).
    func openTemplatesFromMenu() -> TemplatePickerScreen {
        newListButton.perform("Long press", until: app.buttons["home.menu.fromTemplate"]) {
            $0.press(forDuration: 1.2)
        }.waitAndTap()
        return TemplatePickerScreen(app: app).waitUntilShown()
    }

    /// Swipe right on a row → yellow "Pin" (HM-08). A full swipe may pin at once,
    /// so the gesture counts as done when either the button or the tile shows up.
    func pinWithSwipe(row name: String) {
        let pinButton = app.buttons["home.swipe.togglePin"]
        let result = app.buttons.matching(NSPredicate(
            format: "identifier IN %@", ["home.swipe.togglePin", "home.listCard.\(name)"])).firstMatch
        row(name).scrollIntoView(within: list).perform("Swipe right", until: result,
                                                       recover: { backFromMisfiredGesture(on: row(name)) }) {
            $0.swipeRight()
        }
        if pinButton.exists { pinButton.tap(until: .appears(card(name))) }
    }

    /// Long press a tile → "Unpin" (HM-09).
    func unpinFromContextMenu(card name: String) {
        openContextMenu(card: name, until: app.buttons["home.menu.togglePin"]).waitAndTap()
    }

    /// Long press a tile → "List Info" → List Info of that list (HM-09, HM-36, BUG-27).
    func editFromContextMenu(card name: String) -> ListInfoScreen {
        openContextMenu(card: name, until: app.buttons["home.menu.edit"]).waitAndTap()
        return ListInfoScreen(app: app).waitUntilShown()
    }

    /// Long press a tile until `item` of its context menu shows up; returns `item`.
    func openContextMenu(card name: String, until item: XCUIElement) -> XCUIElement {
        card(name).scrollIntoView(within: list)
            .perform("Long press", until: item,
                     recover: { backFromMisfiredGesture(on: card(name)) }) {
                $0.press(forDuration: 1.5)
            }
    }

    /// A long press or swipe that a busy app (slow CI runner) received as a tap opens the
    /// list (a tile's Menu primary action, a row's link) and Home's tile or row is no longer
    /// on screen. Go back so the gesture can be retried. On iPad the list opens beside
    /// Home and `element` stays hittable: nothing to undo.
    ///
    /// Back returns to wherever `element` was: plain Home or Home's search results, where
    /// "+" is hidden (CI run 44802851831). So it waits for `element`, not for Home's "+".
    func backFromMisfiredGesture(on element: XCUIElement) {
        ListDetailScreen(app: app).backFromMisfiredGesture(on: element)
    }

    /// Swipe left on a row → "Delete" → confirmation dialog (HM-10).
    /// A full swipe runs Delete at once, which also just opens the dialog.
    func swipeToDelete(row name: String) -> XCUIElement {
        let confirm = app.buttons["home.deleteAlert.confirmButton"].firstMatch
        let deleteButton = app.buttons["home.swipe.delete"]
        let result = app.buttons.matching(NSPredicate(
            format: "identifier IN %@", ["home.swipe.delete", "home.deleteAlert.confirmButton"])).firstMatch
        row(name).scrollIntoView(within: list).perform("Swipe left", until: result,
                                                       recover: { backFromMisfiredGesture(on: row(name)) }) {
            $0.swipeLeft()
        }
        if deleteButton.exists && !confirm.exists { deleteButton.tap(until: .appears(confirm)) }
        return confirm.waitToAppear()
    }

    /// Swipe left on a row → gray "List Info" → List Info in edit mode (LI-11, HM-36).
    func editWithSwipe(row name: String) -> ListInfoScreen {
        // A partial drag: a full swipe would run the first trailing action (Delete).
        row(name).scrollIntoView(within: list).perform("Partial swipe left", until: app.buttons["home.swipe.edit"],
                                                       recover: { backFromMisfiredGesture(on: row(name)) }) {
            let start = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            let end = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }.tap(until: .appears(ListInfoScreen(app: app).nameField))
        return ListInfoScreen(app: app).waitUntilShown()
    }

    /// Types `text` into Home's search field. On iPad the sidebar keeps the field hidden
    /// above the first row until the list is pulled down, as the user would do.
    @discardableResult
    func search(_ text: String) -> HomeScreen {
        if !searchField.waitForExistence(timeout: 2) {
            list.swipeDown(velocity: .slow)
        }
        searchField.waitAndTap()
        searchField.typeText(text)
        return self
    }

    /// The top edge of a row or tile, to check the order on screen.
    func top(of element: XCUIElement) -> CGFloat {
        element.waitToAppear().frame.minY
    }
}

// MARK: - List Info (spec 03)

@MainActor
struct ListInfoScreen {
    let app: XCUIApplication

    var form: XCUIElement { app.collectionViews["listEdit.form"] }
    var nameField: XCUIElement { app.textFields["listEdit.nameField"] }
    var budgetField: XCUIElement { app.textFields["listEdit.budgetField"] }
    var customEmojiField: XCUIElement { app.textFields["listEdit.customEmojiField"] }
    var pinToggle: XCUIElement { app.switches["listEdit.pinToggle"] }
    var doneButton: XCUIElement { app.buttons["listEdit.doneButton"] }
    var cancelButton: XCUIElement { app.buttons["listEdit.cancelButton"] }
    var deleteButton: XCUIElement { app.buttons["listEdit.deleteButton"] }

    func color(_ raw: String) -> XCUIElement { app.buttons["listEdit.color.\(raw)"] }
    func symbol(_ name: String) -> XCUIElement { app.buttons["listEdit.symbol.\(name)"] }
    func emoji(_ emoji: String) -> XCUIElement { app.buttons["listEdit.emoji.\(emoji)"] }
    /// "Symbols | Emoji" segmented control.
    func iconTab(_ title: String) -> XCUIElement {
        app.segmentedControls["listEdit.iconTabs"].buttons[title]
    }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ListInfoScreen {
        nameField.waitToAppear(file: file, line: line)
        return self
    }

    @discardableResult
    func typeName(_ name: String) -> ListInfoScreen {
        nameField.waitAndTap()
        // Return ends editing, so the keyboard doesn't cover the color and icon grids.
        nameField.typeText(name + "\n")
        return self
    }

    @discardableResult
    func pickColor(_ raw: String) -> ListInfoScreen {
        color(raw).scrollIntoViewLazily(within: form).tap()
        color(raw).waitForSelected(true)
        return self
    }

    @discardableResult
    func pickSymbol(_ name: String) -> ListInfoScreen {
        symbol(name).scrollIntoViewLazily(within: form).tap()
        symbol(name).waitForSelected(true)
        return self
    }

    @discardableResult
    func typeBudget(_ amount: String) -> ListInfoScreen {
        budgetField.scrollIntoViewLazily(within: form, maxSwipes: 8).tap()
        app.typeNumber(amount, into: budgetField)
        return self
    }

    /// ✓ → the sheet closes.
    @discardableResult
    func done() -> HomeScreen {
        app.dismissNumberPadPopover()
        doneButton.waitAndTap()
        nameField.waitToDisappear()
        return HomeScreen(app: app).waitUntilShown()
    }

    /// ✕ → the sheet closes without saving.
    @discardableResult
    func cancel() -> HomeScreen {
        app.dismissNumberPadPopover()
        cancelButton.waitAndTap()
        nameField.waitToDisappear()
        return HomeScreen(app: app).waitUntilShown()
    }
}

// MARK: - Template picker (spec 03 LI-12)

@MainActor
struct TemplatePickerScreen {
    let app: XCUIApplication

    var cancelButton: XCUIElement { app.buttons["templates.cancelButton"] }
    func row(_ rawValue: String) -> XCUIElement { app.buttons["templates.row.\(rawValue)"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> TemplatePickerScreen {
        cancelButton.waitToAppear(file: file, line: line)
        return self
    }

    /// Picks a template → List Info opens prefilled, in create mode.
    func pick(_ rawValue: String) -> ListInfoScreen {
        row(rawValue).waitAndTap()
        return ListInfoScreen(app: app).waitUntilShown()
    }
}

// MARK: - List Archive (spec 10)

extension HomeScreen {
    /// "Archive N" at the end of Home (AR-08).
    var archiveRow: XCUIElement { app.buttons["home.archiveRow"] }
    /// "No Active Lists": every list is archived (AR-13).
    var emptyActiveState: XCUIElement { app.descendants(matching: .any)["home.emptyActiveState"].firstMatch }
    /// The "In Archive" header of the search results (AR-20).
    var searchArchiveSection: XCUIElement { app.staticTexts["home.searchArchiveSection"] }

    /// An archived list's row in the search results (AR-20).
    func archivedRow(_ name: String) -> XCUIElement { ArchiveScreen.row(name, in: app) }

    /// Swipe right on a row → "Archive" (AR-10). A full swipe would run Pin, the first action.
    func archiveWithSwipe(row name: String) {
        let archiveButton = app.buttons["home.swipe.archive"]
        row(name).scrollIntoView(within: list).perform("Partial swipe right", until: archiveButton,
                                                       recover: { backFromMisfiredGesture(on: row(name)) }) {
            let start = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            let end = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }.tap(until: .disappears(row(name))) // CI run 44785776879: tap lost, actions stayed open
    }

    /// Long press a tile → "Archive" (AR-10).
    func archiveFromContextMenu(card name: String) {
        openContextMenu(card: name, until: app.buttons["home.menu.archive"]).waitAndTap()
    }

    /// Long press a row → "Duplicate": the copy opens (HM-39).
    func duplicateFromContextMenu(row name: String) -> ListDetailScreen {
        row(name).scrollIntoView(within: list)
            .perform("Long press", until: app.buttons["home.menu.duplicate"],
                     recover: { backFromMisfiredGesture(on: row(name)) }) {
                $0.press(forDuration: 1.5)
            }.waitAndTap()
        return ListDetailScreen(app: app).waitUntilShown()
    }

    /// Long press a row → "Archive" (AR-10).
    func archiveFromContextMenu(row name: String) {
        row(name).scrollIntoView(within: list)
            .perform("Long press", until: app.buttons["home.menu.archive"],
                     recover: { backFromMisfiredGesture(on: row(name)) }) {
                $0.press(forDuration: 1.5)
            }.waitAndTap()
    }

    /// Long press an "In Archive" search row until its menu shows `item` (AR-18, AR-20).
    /// A press received as a tap opens the list: go back and press again.
    @discardableResult
    func openArchivedRowMenu(_ name: String, until item: XCUIElement) -> XCUIElement {
        archivedRow(name).scrollIntoView(within: list)
            .perform("Long press", until: item,
                     recover: { backFromMisfiredGesture(on: archivedRow(name)) }) {
                $0.press(forDuration: 1.5)
            }
    }

    /// The Archive row → the Archive screen (AR-14).
    func openArchive() -> ArchiveScreen {
        archiveRow.scrollIntoView(within: list).tap(until: .appears(app.navigationBars["Archive"]))
        return ArchiveScreen(app: app).waitUntilShown()
    }
}

@MainActor
struct ArchiveScreen {
    let app: XCUIApplication

    var list: XCUIElement { app.collectionViews["archive.list"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["archive.emptyState"].firstMatch }
    var searchField: XCUIElement { app.searchFields["Search Archive"] }

    /// Rows are identified by uuid ("archive.row.<uuid>"); the VoiceOver label starts with the name.
    static func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                         "archive.row.", "\(name),")).firstMatch
    }

    func row(_ name: String) -> XCUIElement { Self.row(name, in: app) }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ArchiveScreen {
        app.navigationBars["Archive"].waitToAppear(file: file, line: line)
        return self
    }

    /// Tap a row → the archived list (iPhone: push; iPad: the detail column).
    func open(_ name: String) -> ListDetailScreen {
        row(name).tap(until: .appears(ListDetailScreen.navigationBar(name, in: app)))
        return ListDetailScreen(app: app).waitUntilShown()
    }

    /// Swipe right on a row → "Restore" (AR-17). A full swipe runs Restore at once.
    func restoreWithSwipe(_ name: String) {
        let restoreButton = app.buttons["archive.swipe.restore"]
        let target = row(name)
        let result = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["archive.swipe.restore", "archive.emptyState"])).firstMatch
        target.waitToAppear().perform("Swipe right", until: result, recover: { backFromMisfiredGesture(on: target) }) {
            $0.swipeRight()
        }
        if restoreButton.exists { restoreButton.tap(until: .disappears(target)) }
    }

    /// Long press a row → `action` of its context menu (restore, duplicate, share, delete).
    func contextMenu(_ name: String, _ action: String) {
        let target = row(name)
        target.waitToAppear().perform("Long press", until: app.buttons["archive.menu.\(action)"],
                                      recover: { backFromMisfiredGesture(on: target) }) {
            $0.press(forDuration: 1.5)
        }.waitAndTap()
    }

    /// A gesture received as a tap opened the list: go back to the Archive (iPhone).
    func backFromMisfiredGesture(on element: XCUIElement) {
        ListDetailScreen(app: app).backFromMisfiredGesture(on: element)
    }

    /// Back to Home (the Archive's back button).
    @discardableResult
    func goBack() -> HomeScreen {
        let bar = app.navigationBars["Archive"]
        bar.buttons["BackButton"].tap(until: .disappears(bar))
        return HomeScreen(app: app).waitUntilShown()
    }
}

extension ListDetailScreen {
    /// "Archived on <date>" with Restore, on top of an archived list (AR-16).
    var archivedBanner: XCUIElement { app.descendants(matching: .any)["list.archivedBanner"].firstMatch }
    var archivedBannerRestoreButton: XCUIElement { app.buttons["list.archivedBanner.restoreButton"] }
}
