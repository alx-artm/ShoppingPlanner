//
//  UITestSupport.swift
//  Project2UITests
//
//  Launching the app in test mode and small XCUIElement helpers.
//  Rule: never sleep. Every step waits for the element it needs.
//

import XCTest

enum Launch {
    /// Launch arguments understood by `LaunchConfiguration` in the app.
    static let uiTests = "-UITests"
    static let emptyStore = "-UITestsEmptyStore"

    /// Fixed language and region, so number formatting ("1,234.5") is the same on every machine.
    static let locale = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    /// In-memory store with `SeedData` (or empty with `emptyStore: true`).
    @MainActor
    static func app(emptyStore: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [uiTests] + (emptyStore ? [Launch.emptyStore] : []) + locale
        app.launch()
        return app
    }
}

/// Default timeout for UI to appear. Generous for slow CI, but the wait ends
/// as soon as the element shows up, so passing tests stay fast.
let uiTimeout: TimeInterval = 10

extension XCUIElement {
    /// Waits until the element exists, fails the test (at the caller's line) otherwise.
    @MainActor
    @discardableResult
    func waitToAppear(timeout: TimeInterval = uiTimeout,
                      file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout),
                      "\(self) did not appear in \(timeout)s", file: file, line: line)
        return self
    }

    /// Waits until the element is gone.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = uiTimeout,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForNonExistence(timeout: timeout),
                      "\(self) is still on screen after \(timeout)s", file: file, line: line)
    }

    /// Waits for the element and taps it.
    @MainActor
    func waitAndTap(timeout: TimeInterval = uiTimeout,
                    file: StaticString = #filePath, line: UInt = #line) {
        waitToAppear(timeout: timeout, file: file, line: line).tap()
    }

    /// Waits until `label` equals `expected` (labels update asynchronously after a tap).
    @MainActor
    func waitForLabel(_ expected: String, timeout: TimeInterval = uiTimeout,
                      file: StaticString = #filePath, line: UInt = #line) {
        waitToAppear(timeout: timeout, file: file, line: line)
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "label is '\(label)', expected '\(expected)'", file: file, line: line)
    }

    /// Waits until `label` contains `fragment`.
    @MainActor
    func waitForLabel(containing fragment: String, timeout: TimeInterval = uiTimeout,
                      file: StaticString = #filePath, line: UInt = #line) {
        waitToAppear(timeout: timeout, file: file, line: line)
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "label is '\(label)', expected it to contain '\(fragment)'", file: file, line: line)
    }

    /// Waits until the element is (not) selected, e.g. a checkbox.
    @MainActor
    func waitForSelected(_ selected: Bool, timeout: TimeInterval = uiTimeout,
                         file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "selected == %@", NSNumber(value: selected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(self) selected != \(selected)", file: file, line: line)
    }
}
