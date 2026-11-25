//
//  TipJarStoreKitUITests.swift
//  Project2UITests
//
//  Spec 12 TJ-27 against real StoreKit: the app loads the three tips from
//  `TipJar.storekit`, the StoreKit configuration of the scheme's Run action.
//
//  Not in a CI shard: with Xcode 27.2 the iOS 26.5 simulator runtime (CI's pinned
//  one) ignores local StoreKit configurations, the products never load and the
//  test skips itself. It passes on an iOS 27.2 simulator; run it locally there.
//

import XCTest

final class TipJarStoreKitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTipsComeFromStoreKitConfiguration() throws {
        let app = Launch.app(tipJar: true)
        let tipJar = HomeScreen(app: app).waitUntilShown().openSettings().openTipJar()

        let coffee = tipJar.product("coffee")
        let appeared = coffee.waitForExistence(timeout: 20)
        if !appeared, tipJar.retryButton.exists {
            throw XCTSkip("StoreKit configuration isn't applied on this simulator runtime (see header)")
        }
        XCTAssertTrue(appeared, "no products and no error state")
        XCTAssertEqual(coffee.label, "Coffee, $0.99")
        XCTAssertEqual(tipJar.product("lunch").waitToAppear().label, "Lunch, $2.99")
        XCTAssertEqual(tipJar.product("bigthanks").waitToAppear().label, "Big Thanks, $5.99")
    }
}
