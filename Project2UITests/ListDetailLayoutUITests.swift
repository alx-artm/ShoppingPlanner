//
//  ListDetailLayoutUITests.swift
//  Project2UITests
//
//  Spec 04 M4.6 "UI polish: list detail" (LD-30...LD-35), measured on frames:
//  the rhythm of group headers, the header's VoiceOver label and size, the
//  two-line header and compact summary bar at accessibility text sizes, the
//  last row above the summary bar and the single leading grid.
//  Alex (seed data) gets two more groups, Groceries and Home, for 4 groups.
//

import XCTest

final class ListDetailLayoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let groups = ["Vacation", "Birthday", "Groceries", "Home"]
    private static let accessibilityLarge = UIContentSizeCategory.accessibilityLarge.rawValue

    /// Alex with 4 groups: Vacation (3 items), Birthday (3), Groceries and Home (empty).
    @MainActor
    private func alexWithFourGroups(_ app: XCUIApplication) -> ListDetailScreen {
        let home = HomeScreen(app: app).waitUntilShown()
        // At accessibility sizes pinned lists are rows, not tiles (HM-02).
        let alex = home.card("Alex").waitForExistence(timeout: 2)
            ? home.open(card: "Alex") : home.open(row: "Alex")
        alex.addGroup(named: "Groceries")
        alex.addGroup(named: "Home")
        return alex
    }

    /// Scrolls the list back to its top.
    @MainActor
    private func scrollToTop(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 { list.swipeDown(velocity: .fast) }
    }

    /// Drags the list up in short steps until `element` is on screen above the summary bar.
    /// Short drags, not swipes: the row above `element` must stay on screen too, and a lazy
    /// list doesn't have `element` at all until it is scrolled near it.
    @MainActor
    private func scrollUntilVisible(_ element: XCUIElement, in screen: ListDetailScreen,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let list = screen.app.collectionViews.firstMatch
        for _ in 0..<12 {
            if element.exists, element.isHittable, element.frame.maxY <= screen.summary.frame.minY { return }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = start.withOffset(CGVector(dx: 0, dy: -150))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("\(element) is not on screen", file: file, line: line)
    }

    // MARK: - LD-30 rhythm

    /// LD-30: collapsed groups read as a table of contents, 16 pt between two header buttons.
    @MainActor
    func testCollapsedHeadersHaveCompactRhythm() {
        let app = Launch.app()
        let alex = alexWithFourGroups(app)
        alex.menuAction("toggleExpanded")
        alex.groupCount("Home").waitToAppear()
        scrollToTop(app)

        for (upper, lower) in zip(Self.groups, Self.groups.dropFirst()) {
            let top = alex.groupHeader(upper).waitToBeHittable().frame
            let bottom = alex.groupHeader(lower).waitToBeHittable().frame
            XCTAssertEqual(bottom.minY - top.maxY, 16, accuracy: 2, "gap \(upper) → \(lower)")
            XCTAssertEqual(bottom.minY - top.minY, 60, accuracy: 2, "step \(upper) → \(lower)")
        }
    }

    /// LD-30: after an expanded group, 24 pt from its last row ("＋ New Item") to the next header.
    @MainActor
    func testHeaderAfterExpandedGroupHasMoreAir() {
        let app = Launch.app()
        let alex = alexWithFourGroups(app)
        scrollToTop(app)

        for (upper, lower) in zip(Self.groups, Self.groups.dropFirst()) {
            let lastRow = alex.addItemButton(upper)
            let header = alex.groupHeader(lower)
            scrollUntilVisible(header, in: alex)
            XCTAssertTrue(lastRow.isHittable, "\(upper)'s last row is on screen")
            XCTAssertEqual(header.frame.minY - lastRow.frame.maxY, 24, accuracy: 2, "\(upper) → \(lower)")
        }
    }

    // MARK: - LD-31 header

    /// LD-31: a ≥ 44 pt header button, read as "Vacation, 3 items, $145.00" with value
    /// Expanded / Collapsed; singular "1 item" and "No price" without prices.
    @MainActor
    func testHeaderAccessibilityLabelAndValue() {
        let app = Launch.app()
        let alex = alexWithFourGroups(app)
        alex.addItem(named: "Milk", to: "Groceries")
        scrollToTop(app)

        let vacation = alex.groupHeader("Vacation").waitToBeHittable()
        XCTAssertEqual(vacation.label, "Vacation, 3 items, $145.00")
        XCTAssertEqual(vacation.value as? String, "Expanded")
        XCTAssertGreaterThanOrEqual(vacation.frame.height, 44)

        vacation.tap()
        alex.groupCount("Vacation").waitToAppear()
        XCTAssertEqual(vacation.value as? String, "Collapsed")
        XCTAssertEqual(vacation.label, "Vacation, 3 items, $145.00", "no '(3)' in the label")

        let groceries = alex.groupHeader("Groceries")
        scrollUntilVisible(groceries, in: alex)
        XCTAssertEqual(groceries.label, "Groceries, 1 item, No price")
    }

    // MARK: - LD-34 summary bar

    /// LD-34: at the end of the list "＋ Add Group" scrolls fully above the summary bar.
    @MainActor
    func testLastRowScrollsAboveSummaryBar() {
        let app = Launch.app()
        let alex = alexWithFourGroups(app)
        alex.reveal(alex.addGroupRow, maxSwipes: 8)
        app.collectionViews.firstMatch.swipeUp(velocity: .fast)

        XCTAssertTrue(alex.addGroupRow.isHittable)
        XCTAssertLessThanOrEqual(alex.addGroupRow.frame.maxY, alex.summary.frame.minY,
                                 "Add Group is fully above the summary bar")
    }

    // MARK: - LD-35 grid

    /// LD-35: chevron, checkbox, "＋" of New Item and the Add Group icon are centered on one
    /// vertical; group name, item name, "New Item", "N bought" and "Add Group" start on another.
    @MainActor
    func testRowsShareOneLeadingGrid() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        alex.toggleShowCompleted()
        alex.boughtRow("Vacation").waitToAppear()

        func element(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)[identifier].firstMatch.waitToAppear()
        }
        let iconCenters: [(String, CGFloat)] = [
            ("chevron", element("group.chevron.Vacation").frame.midX),
            ("checkbox", alex.checkbox("Sunglasses").waitToAppear().frame.midX),
            ("New Item +", element("group.addItemButton.Vacation.icon").frame.midX),
        ]
        // "folder.badge.plus" is centered by its layout frame; its badge on the right makes the
        // drawn bounds ~3 pt wider to the right, while the folder itself is on the axis.
        let addGroupIcon = element("listDetail.addGroupRow.icon").frame
        XCTAssertTrue((iconCenters[0].1 - 1...iconCenters[0].1 + 4).contains(addGroupIcon.midX),
                      "Add Group icon center \(addGroupIcon.midX) vs chevron \(iconCenters[0].1)")
        let textEdges: [(String, CGFloat)] = [
            ("group name", element("group.name.Vacation").frame.minX),
            ("item name", alex.itemRow("Sunglasses").waitToAppear().frame.minX),
            ("New Item", element("group.addItemButton.Vacation.title").frame.minX),
            ("N bought", element("group.boughtRow.Vacation.title").frame.minX),
            ("Add Group", element("listDetail.addGroupRow.title").frame.minX),
        ]
        for (name, x) in iconCenters.dropFirst() {
            XCTAssertEqual(x, iconCenters[0].1, accuracy: 1, "\(name) center vs chevron")
        }
        for (name, x) in textEdges.dropFirst() {
            XCTAssertEqual(x, textEdges[0].1, accuracy: 1, "\(name) leading edge vs group name")
        }
    }

    /// Spec 06 D1-v2 F (M5.1): a link tile doesn't break the grid. The tile sits under the
    /// name, so names start at one x (no "staircase"), amounts end at one x, and the tile
    /// starts at the names' leading edge.
    @MainActor
    func testLinkTileKeepsNamesAndAmountsAligned() {
        let app = Launch.app()
        let alex = HomeScreen(app: app).waitUntilShown().open(card: "Alex")
        let editor = alex.openItem("Swimsuit")
        editor.urlField.scrollIntoViewLazily(within: editor.form)
        editor.replaceText(of: editor.urlField, with: "https://shop.example.com/swimsuit")
        editor.done()

        let tile = app.buttons["item.linkThumb.Swimsuit"].waitToAppear().frame
        let groupName = app.descendants(matching: .any)["group.name.Vacation"].firstMatch.waitToAppear()
        let withLink = alex.itemRow("Swimsuit").frame
        for plain in ["Sunglasses", "Appetizers"] {
            XCTAssertEqual(alex.itemRow(plain).frame.minX, withLink.minX, accuracy: 0.5, "name of \(plain)")
            XCTAssertEqual(alex.itemTotal(plain).frame.maxX, alex.itemTotal("Swimsuit").frame.maxX,
                           accuracy: 0.5, "amount of \(plain)")
        }
        XCTAssertEqual(withLink.minX, groupName.frame.minX, accuracy: 1, "item names vs group name")
        XCTAssertEqual(tile.minX, withLink.minX, accuracy: 0.5, "the tile starts at the names' edge")
        XCTAssertGreaterThanOrEqual(tile.minY, alex.itemTotal("Swimsuit").frame.maxY - 0.5,
                                    "the tile is under the name line")
        XCTAssertGreaterThan(withLink.height, alex.itemRow("Sunglasses").frame.height,
                             "a row with a link is taller")
    }

    // MARK: - Accessibility sizes (LD-32, LD-33)

    /// LD-32: at AX-L the group name has its own line: never cut, ⋯ still a 44 pt target.
    @MainActor
    func testHeaderAtAccessibilitySizeKeepsFullName() {
        let app = Launch.app(contentSize: Self.accessibilityLarge)
        let alex = alexWithFourGroups(app)
        scrollToTop(app)

        let header = alex.groupHeader("Vacation").waitToBeHittable()
        XCTAssertTrue(header.label.hasPrefix("Vacation, "), header.label)
        let name = app.descendants(matching: .any)["group.name.Vacation"].firstMatch.waitToAppear()
        let total = alex.groupTotal("Vacation").waitToAppear()
        XCTAssertGreaterThan(total.frame.minY, name.frame.minY, "the amount is on the second line")
        let menu = alex.groupMenu("Vacation").waitToBeHittable()
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        // ⋯ sits beside the name or below it, never over it.
        XCTAssertFalse(name.frame.insetBy(dx: 1, dy: 1).intersects(menu.frame), "⋯ covers the name")
    }

    /// LD-33: at AX-L the summary bar starts as one line and a tap shows the full form; with
    /// all 4 groups collapsed, "＋ Add Group" scrolls fully above it.
    @MainActor
    func testSummaryBarIsCompactAtAccessibilitySize() {
        let app = Launch.app(contentSize: Self.accessibilityLarge)
        let alex = alexWithFourGroups(app)
        let toggle = app.buttons["listDetail.summary.toggleForm"]

        toggle.waitToAppear()
        XCTAssertFalse(alex.budget.exists, "compact: no budget line")
        toggle.tap()
        alex.budget.waitToAppear()
        app.buttons["listDetail.summary.toggleForm"].firstMatch.waitAndTap()
        alex.budget.waitToDisappear()

        alex.menuAction("toggleExpanded")
        alex.groupCount("Home").waitToAppear()
        alex.reveal(alex.addGroupRow, maxSwipes: 8)
        XCTAssertTrue(alex.addGroupRow.isHittable)
        XCTAssertLessThanOrEqual(alex.addGroupRow.frame.maxY, alex.summary.frame.minY,
                                 "Add Group is fully above the summary bar")
    }
}
