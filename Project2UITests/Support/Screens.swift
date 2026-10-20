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
        row(name).waitToAppear().press(forDuration: 1.0)
        app.buttons["home.menu.delete"].waitAndTap()
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
    var backButton: XCUIElement { app.navigationBars.buttons["BackButton"] }

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
        itemRow(item).waitToAppear().swipeLeft()
        app.buttons["Delete"].firstMatch.waitAndTap()
    }

    /// Menu → "Delete list" → confirm. The screen pops back to Home.
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
