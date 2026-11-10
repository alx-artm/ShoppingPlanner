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

    /// Waits until the element exists *and* is hittable (on screen, not covered,
    /// not mid-animation). Gestures sent before that can be silently lost.
    @MainActor
    @discardableResult
    func waitToBeHittable(timeout: TimeInterval = uiTimeout,
                          file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(self) is not hittable after \(timeout)s", file: file, line: line)
        return self
    }

    /// Scrolls `container` until this element is hittable, at most `maxSwipes` times.
    ///
    /// An element can exist but sit under the floating tab bar or below the fold
    /// (smaller screens, CI simulators); gestures on it would hit something else.
    /// Each swipe is a deliberate scroll, so it stops as soon as the element is reachable.
    @MainActor
    @discardableResult
    func scrollIntoView(within container: XCUIElement, maxSwipes: Int = 4,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        waitToAppear(file: file, line: line)
        var swipes = 0
        while !isHittable && swipes < maxSwipes {
            container.swipeUp(velocity: .slow)
            swipes += 1
        }
        return self
    }

    /// Like `scrollIntoView`, for lazy containers (Form, LazyVGrid) where the element
    /// is not even in the hierarchy until it is scrolled near the screen.
    @MainActor
    @discardableResult
    func scrollIntoViewLazily(within container: XCUIElement, maxSwipes: Int = 6,
                              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var swipes = 0
        while !(exists && isHittable) && swipes < maxSwipes {
            container.swipeUp(velocity: .slow)
            swipes += 1
        }
        return waitToBeHittable(file: file, line: line)
    }

    /// Performs a gesture on this element until `result` appears, at most `attempts` times.
    ///
    /// Gestures (long press, swipe) are timing-sensitive: on a slow machine (CI) the
    /// system can drop one that lands while the view is still settling. A tap is
    /// re-sent automatically by XCTest, a gesture is not, so we retry it ourselves.
    /// Each attempt waits for the element to be hittable first; no sleeps.
    @MainActor
    @discardableResult
    func perform(_ gestureName: String,
                 until result: XCUIElement,
                 attempts: Int = 3,
                 resultTimeout: TimeInterval = 5,
                 file: StaticString = #filePath, line: UInt = #line,
                 _ gesture: (XCUIElement) -> Void) -> XCUIElement {
        for _ in 1...max(attempts, 1) {
            // A late result from the previous attempt counts, and pressing again
            // on top of an open menu would dismiss it.
            if result.exists { return result }
            waitToBeHittable(file: file, line: line)
            gesture(self)
            if result.waitForExistence(timeout: resultTimeout) { return result }
        }
        XCTFail("\(gestureName) on \(self) did not reveal \(result) after \(attempts) attempts "
                + "(\(resultTimeout)s each)", file: file, line: line)
        return result
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
