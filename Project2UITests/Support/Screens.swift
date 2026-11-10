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
    var emptyState: XCUIElement { app.descendants(matching: .any)["home.emptyState"].firstMatch }

    /// Pinned lists are cards, the others are rows.
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

    /// Home → "+" → type a name → Done.
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

    /// Long press → "Delete list" → confirm.
    func deleteFromContextMenu(row name: String) {
        row(name).perform("Long press", until: app.buttons["home.menu.delete"]) {
            $0.press(forDuration: 1.5)
        }.waitAndTap()
        // Alert buttons expose their identifier twice; take the first match.
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
        itemRow(item).perform("Swipe left", until: app.buttons["Delete"].firstMatch) {
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

// MARK: - Tabs, Settings, currency picker (spec 07)

/// The two tabs of `ContentView`.
@MainActor
struct TabBar {
    let app: XCUIApplication

    var listsTab: XCUIElement { app.tabBars.buttons["Shopping Lists"] }
    var settingsTab: XCUIElement { app.tabBars.buttons["Settings"] }

    func openSettings() -> SettingsScreen {
        settingsTab.waitAndTap()
        return SettingsScreen(app: app).waitUntilShown()
    }

    func openLists() -> HomeScreen {
        listsTab.waitAndTap()
        return HomeScreen(app: app).waitUntilShown()
    }
}

@MainActor
struct SettingsScreen {
    let app: XCUIApplication

    /// Navigation row "Main Currency  Euro · EUR · €".
    var mainCurrency: XCUIElement { app.buttons["settings.mainCurrency"] }
    var appearancePicker: XCUIElement { app.descendants(matching: .any)["settings.appearancePicker"].firstMatch }
    var icloudStatus: XCUIElement { app.descendants(matching: .any)["settings.icloudStatus"].firstMatch }
    var version: XCUIElement { app.descendants(matching: .any)["settings.version"].firstMatch }

    @discardableResult
    func waitUntilShown(file: StaticString = #filePath, line: UInt = #line) -> SettingsScreen {
        mainCurrency.waitToAppear(file: file, line: line)
        return self
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
        searchField.waitToDisappear()
        return SettingsScreen(app: app).waitUntilShown()
    }
}
