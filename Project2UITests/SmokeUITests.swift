//
//  SmokeUITests.swift
//  Project2UITests
//

import XCTest

/// Placeholder UI test that proves the app launches under XCUITest.
/// Real UI tests are added by QA.
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
