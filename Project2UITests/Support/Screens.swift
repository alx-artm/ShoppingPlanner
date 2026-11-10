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

    var addGroupButton: XCUIElement { app.buttons["listDetail.addGroupButton"] }
    var menuButton: XCUIElement { app.buttons["listDetail.menuButton"] }
    var total: XCUIElement { app.staticTexts["listDetail.total"] }
    /// Not scoped to `navigationBars`: on some devices (iPhone Duo) the system
    /// renders the back button in a side rail outside the navigation bar.
    var backButton: XCUIElement { app.buttons["BackButton"].firstMatch }

    func groupHeader(_ group: String) -> XCUIElement { app.buttons["group.editButton.\(group)"] }
    func groupTotal(_ group: String) -> XCUIElement { app.staticTexts["group.total.\(group)"] }
    func addItemButton(_ group: String) -> XCUIElement { app.buttons["group.addItemButton.\(group)"] }
    func itemRow(_ item: String) -> XCUIElement { app.otherElements["item.row.\(item)"] }
    func checkbox(_ item: String) -> XCUIElement { app.buttons["item.checkbox.\(item)"] }
    func itemTotal(_ item: String) -> XCUIElement { app.staticTexts["item.total.\(item)"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ListDetailScreen {
        addGroupButton.waitToAppear(file: file, line: line)
        return self
    }

    @discardableResult
    func addGroup(named name: String) -> ListDetailScreen {
        addGroupButton.waitAndTap()
        let nameField = app.textFields["groupEdit.nameField"].waitToAppear()
        nameField.tap()
        nameField.typeText(name)
        app.buttons["groupEdit.doneButton"].waitAndTap()
        groupHeader(name).waitToAppear()
        return self
    }

    /// "Add new item..." in `group` → name, price, quantity → Done.
    @discardableResult
    func addItem(named name: String, price: String? = nil, quantity: Int = 1,
                 to group: String) -> ListDetailScreen {
        addItemButton(group).waitAndTap()
        let editor = ItemEditScreen(app: app).waitUntilShown()
        editor.nameField.tap()
        editor.nameField.typeText(name)
        if let price {
            editor.priceField.tap()
            editor.priceField.typeText(price)
        }
        for _ in 1..<max(quantity, 1) { editor.quantityIncrement.tap() }
        editor.doneButton.waitAndTap()
        itemRow(name).waitToAppear()
        return self
    }

    /// Tap the item name → item details sheet.
    func openItem(_ name: String) -> ItemEditScreen {
        itemRow(name).waitToAppear().staticTexts[name].tap()
        return ItemEditScreen(app: app).waitUntilShown()
    }

    func openGroup(_ name: String) -> GroupEditScreen {
        groupHeader(name).waitAndTap()
        return GroupEditScreen(app: app).waitUntilShown()
    }

    func toggleShowCompleted() {
        menuButton.waitAndTap()
        app.buttons["listDetail.menu.toggleCompleted"].waitAndTap()
    }

    /// Swipe left on a row and tap the system "Delete" action.
    func swipeToDelete(_ item: String) {
        itemRow(item).scrollIntoView(within: app.collectionViews.firstMatch)
            .perform("Swipe left", until: app.buttons["Delete"].firstMatch) {
            $0.swipeLeft()
        }.waitAndTap()
    }

    /// Menu → "Delete list" → confirm. The screen pops back to Home.
    @discardableResult
    func deleteList() -> HomeScreen {
        menuButton.waitAndTap()
        app.buttons["listDetail.menu.delete"].waitAndTap()
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

    var nameField: XCUIElement { app.textFields["itemEdit.nameField"] }
    var priceField: XCUIElement { app.textFields["itemEdit.priceField"] }
    var total: XCUIElement { app.staticTexts["itemEdit.total"] }
    var quantityIncrement: XCUIElement { app.buttons["itemEdit.quantityStepper-Increment"] }
    var doneButton: XCUIElement { app.buttons["itemEdit.doneButton"] }
    var deleteButton: XCUIElement { app.buttons["itemEdit.deleteButton"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> ItemEditScreen {
        nameField.waitToAppear(file: file, line: line)
        return self
    }

    func delete() {
        deleteButton.waitAndTap()
        nameField.waitToDisappear()
    }
}

@MainActor
struct GroupEditScreen {
    let app: XCUIApplication

    var nameField: XCUIElement { app.textFields["groupEdit.nameField"] }
    var deleteButton: XCUIElement { app.buttons["groupEdit.deleteButton"] }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> GroupEditScreen {
        nameField.waitToAppear(file: file, line: line)
        return self
    }

    /// "Delete Group" → confirm in the alert.
    func delete() {
        deleteButton.waitAndTap()
        app.buttons["groupEdit.deleteAlert.confirmButton"].firstMatch.waitAndTap()
        nameField.waitToDisappear()
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
        card(name).scrollIntoView(within: list)
            .perform("Long press", until: app.buttons["home.menu.togglePin"]) {
                $0.press(forDuration: 1.5)
            }.waitAndTap()
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
