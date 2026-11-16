//
//  UITestSupport.swift
//  Project2UITests
//
//  Launching the app in test mode and small XCUIElement helpers.
//  Rule: never sleep. Every step waits for the element it needs.
//

import UIKit
import XCTest

enum Launch {
    /// Launch arguments understood by `LaunchConfiguration` in the app.
    static let uiTests = "-UITests"
    static let emptyStore = "-UITestsEmptyStore"

    /// Fixed language and region, so number formatting ("1,234.5") is the same on every machine.
    static func locale(language: String = "en", region: String = "en_US") -> [String] {
        ["-AppleLanguages", "(\(language))", "-AppleLocale", region]
    }

    /// In-memory store with `SeedData` (or empty with `emptyStore: true`), in English / en_US
    /// unless another language and region are given.
    @MainActor
    static func app(emptyStore: Bool = false, language: String = "en", region: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [uiTests] + (emptyStore ? [Launch.emptyStore] : [])
            + locale(language: language, region: region)
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

    /// Waits until this element is hittable or `other` exists, whichever comes first.
    /// Returns `true` if `other` showed up; fails the test if neither happens in time.
    @MainActor
    @discardableResult
    func waitToBeHittable(orUntil other: XCUIElement, timeout: TimeInterval = uiTimeout,
                          file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if other.exists { return true }
            if exists && isHittable { return false }
            // The wait for `other` paces the loop (no sleep) and ends early if it appears.
        } while !other.waitForExistence(timeout: 0.5) && Date() < deadline
        if other.exists { return true }
        XCTFail("\(self) is not hittable (and \(other) did not appear) after \(timeout)s",
                file: file, line: line)
        return false
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
    ///
    /// A missed gesture can also do something else: when the app is too busy to see the
    /// touch go down and up in time, a long press arrives as a tap (on a Home tile that runs
    /// the Menu's primary action and opens the list). `recover` runs before each retry and
    /// brings the screen back (e.g. goes back to Home) so the element can be pressed again.
    @MainActor
    @discardableResult
    func perform(_ gestureName: String,
                 until result: XCUIElement,
                 attempts: Int = 3,
                 resultTimeout: TimeInterval = 5,
                 file: StaticString = #filePath, line: UInt = #line,
                 recover: () -> Void = {},
                 _ gesture: (XCUIElement) -> Void) -> XCUIElement {
        for attempt in 1...max(attempts, 1) {
            // A late result from the previous attempt counts, and pressing again
            // on top of an open menu would dismiss it.
            if result.exists { return result }
            if attempt > 1 { recover() }
            // A menu that opens late covers this element (not hittable): wait for either.
            if waitToBeHittable(orUntil: result, file: file, line: line) { return result }
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

    /// Waits until the element has the keyboard focus; `false` after the timeout.
    @MainActor
    func waitForKeyboardFocus(timeout: TimeInterval = uiTimeout) -> Bool {
        let predicate = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until the element is (not) enabled, e.g. ✓ after a change.
    @MainActor
    func waitForEnabled(_ enabled: Bool, timeout: TimeInterval = uiTimeout,
                        file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: enabled))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(self) enabled != \(enabled)", file: file, line: line)
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

/// Contrast of the drawn content of a screenshot against its background (WCAG 2 formula).
/// The background is the top-left pixel; the result is the strongest contrast of any pixel
/// with it, so anti-aliased edges don't lower it. Used where colors matter (BUG-29).
enum ScreenshotContrast {
    static func strongest(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, !pixels.isEmpty else { return 0 }
        func luminance(_ offset: Int) -> Double {
            func channel(_ value: UInt8) -> Double {
                let c = Double(value) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(pixels[offset]) + 0.7152 * channel(pixels[offset + 1])
                + 0.0722 * channel(pixels[offset + 2])
        }
        let background = luminance(0)
        var best = 1.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let l = luminance(offset)
            let ratio = (max(l, background) + 0.05) / (min(l, background) + 0.05)
            best = max(best, ratio)
        }
        return best
    }
}
