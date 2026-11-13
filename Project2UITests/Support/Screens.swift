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

    func open(card name: String) -> ListDetailScreen {
        card(name).waitAndTap()
        return ListDetailScreen(app: app).waitUntilShown()
    }

    func open(row name: String) -> ListDetailScreen {
        row(name).waitAndTap()
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
            .perform("Long press", until: app.buttons["home.menu.delete"]) {
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
    func checkbox(_ item: String) -> XCUIElement { app.buttons["item.checkbox.\(item)"] }
    func itemTotal(_ item: String) -> XCUIElement { app.staticTexts["item.total.\(item)"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ListDetailScreen {
        menuButton.waitToAppear(file: file, line: line)
        return self
    }

    /// ⋯ → Add Group → alert: type the name → Add. The group goes last (LD-01).
    @discardableResult
    func addGroup(named name: String) -> ListDetailScreen {
        menuAction("addGroup")
        typeGroupName(name)
        groupHeader(name).waitToAppear()
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
        reveal(itemRow(item)).perform("Long press", until: app.buttons["item.menu.\(action)"]) {
            $0.press(forDuration: 1.2)
        }.waitAndTap()
    }

    /// Swipe right on a row → Bought / Not Bought (LD-09).
    func swipeToToggle(_ item: String) {
        let button = app.buttons["item.swipe.toggle"]
        reveal(itemRow(item)).perform("Swipe right", until: button) {
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
            app.buttons["inline.accessory.price"].waitAndTap()
            app.textFields["inline.priceField"].waitToAppear().typeText(price)
        }
        if quantity > 1 {
            app.buttons["inline.accessory.quantity"].waitAndTap()
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

    /// Done on the keyboard's accessory bar: saves a non-empty draft and closes inline add.
    func inlineDone() {
        app.buttons["inline.accessory.done"].waitAndTap()
        app.textFields["inline.nameField"].waitToDisappear()
    }

    /// Tap the row → item details sheet (LD-06).
    func openItem(_ name: String) -> ItemEditScreen {
        reveal(itemRow(name)).tap()
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
        reveal(row).perform("Swipe left", until: result) {
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
        backButton.waitAndTap()
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
    var deleteButton: XCUIElement { app.buttons["itemEdit.deleteButton"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ItemEditScreen {
        nameField.waitToAppear(file: file, line: line)
        return self
    }

    /// Replaces the text of a field (select all is not reliable, so delete key by key).
    /// The tap goes to the field's right end, so the cursor lands after the text
    /// in both leading- and trailing-aligned fields.
    func replaceText(of field: XCUIElement, with text: String) {
        field.waitToBeHittable()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    /// "Delete Item" → confirm. The sheet closes, then the item is deleted (ID-11).
    func delete() {
        deleteButton.scrollIntoViewLazily(within: form).tap()
        app.buttons["itemEdit.deleteAlert.confirmButton"].firstMatch.waitAndTap()
        nameField.waitToDisappear()
    }

    /// ✓ → the sheet closes.
    func done() {
        doneButton.waitAndTap()
        nameField.waitToDisappear()
    }

    /// ✕ → the sheet closes without saving.
    func cancel() {
        cancelButton.waitAndTap()
        nameField.waitToDisappear()
    }

    /// Group picker → choose `group`.
    func moveToGroup(_ group: String) {
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
        row(name).scrollIntoView(within: list).perform("Swipe right", until: result) {
            $0.swipeRight()
        }
        if pinButton.exists { pinButton.tap() }
    }

    /// Long press a tile → "Unpin" (HM-09).
    func unpinFromContextMenu(card name: String) {
        openContextMenu(card: name, until: app.buttons["home.menu.togglePin"]).waitAndTap()
    }

    /// Long press a tile → Edit → List Info of that list (HM-09, BUG-27).
    func editFromContextMenu(card name: String) -> ListInfoScreen {
        openContextMenu(card: name, until: app.buttons["home.menu.edit"]).waitAndTap()
        return ListInfoScreen(app: app).waitUntilShown()
    }

    /// Long press a tile until `item` of its context menu shows up; returns `item`.
    private func openContextMenu(card name: String, until item: XCUIElement) -> XCUIElement {
        card(name).scrollIntoView(within: list)
            .perform("Long press", until: item) {
                $0.press(forDuration: 1.5)
            }
    }

    /// Swipe left on a row → "Delete" → confirmation dialog (HM-10).
    /// A full swipe runs Delete at once, which also just opens the dialog.
    func swipeToDelete(row name: String) -> XCUIElement {
        let confirm = app.buttons["home.deleteAlert.confirmButton"].firstMatch
        let deleteButton = app.buttons["home.swipe.delete"]
        let result = app.buttons.matching(NSPredicate(
            format: "identifier IN %@", ["home.swipe.delete", "home.deleteAlert.confirmButton"])).firstMatch
        row(name).scrollIntoView(within: list).perform("Swipe left", until: result) {
            $0.swipeLeft()
        }
        if deleteButton.exists && !confirm.exists { deleteButton.tap() }
        return confirm.waitToAppear()
    }

    /// Swipe left on a row → gray "Edit" → List Info in edit mode (LI-11).
    func editWithSwipe(row name: String) -> ListInfoScreen {
        // A partial drag: a full swipe would run the first trailing action (Delete).
        row(name).scrollIntoView(within: list).perform("Partial swipe left", until: app.buttons["home.swipe.edit"]) {
            let start = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            let end = $0.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }.waitAndTap()
        return ListInfoScreen(app: app).waitUntilShown()
    }

    @discardableResult
    func search(_ text: String) -> HomeScreen {
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
        budgetField.typeText(amount)
        return self
    }

    /// ✓ → the sheet closes.
    @discardableResult
    func done() -> HomeScreen {
        doneButton.waitAndTap()
        nameField.waitToDisappear()
        return HomeScreen(app: app).waitUntilShown()
    }

    /// ✕ → the sheet closes without saving.
    @discardableResult
    func cancel() -> HomeScreen {
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
