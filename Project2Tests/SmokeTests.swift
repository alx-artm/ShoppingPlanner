//
//  SmokeTests.swift
//  Project2Tests
//

import Testing
@testable import Project2

/// Placeholder suite that proves the unit-test target builds, links
/// against the app module and runs. Real tests are added by QA.
struct SmokeTests {
    @Test func appModuleIsReachable() {
        #expect(FavoriteColor(rawValue: "blue") == .blue)
    }
}
