//
//  ICloudSyncUITests.swift
//  Project2UITests
//
//  M6 without CloudKit: the account status is fixed by `-UITestsICloudStatus`,
//  the store stays in memory. Settings' iCloud row in every state (spec 07
//  SC-10, spec 01 DM-27) and the empty Home on a first launch (DM-28).
//  Real two-device sync (DM-26, DM-29...DM-31) is a manual test.
//

import XCTest

final class ICloudSyncUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func settings(iCloudStatus: String?, language: String = "en", region: String = "en_US") -> SettingsScreen {
        let app = Launch.app(language: language, region: region, iCloudStatus: iCloudStatus)
        return HomeScreen(app: app).waitUntilShown().openSettings()
    }

    /// SC-10: signed in to iCloud → "On", no button.
    @MainActor
    func testAvailableAccountShowsOn() {
        let settings = settings(iCloudStatus: "available")
        settings.icloudStatus.waitForLabel(containing: "On")
        XCTAssertFalse(settings.icloudStatus.label.contains("Off"), settings.icloudStatus.label)
        settings.icloudFooter.waitForLabel(containing: "sync to your other devices")
        XCTAssertFalse(settings.icloudOpenSettings.exists, "nothing to fix while sync is on")
    }

    /// SC-10 / DM-27: not signed in → "Off", why, and a way to the system Settings.
    @MainActor
    func testNoAccountShowsOffWithReasonAndSettingsButton() {
        let settings = settings(iCloudStatus: "noAccount")
        settings.icloudStatus.waitForLabel(containing: "Off")
        settings.icloudFooter.waitForLabel(containing: "Sign in to iCloud")
        settings.icloudOpenSettings.waitToAppear()
        XCTAssertTrue(settings.icloudOpenSettings.isHittable)
    }

    /// SC-10: iCloud restricted (Screen Time, MDM) → "Off" with its own reason.
    @MainActor
    func testRestrictedShowsOffWithReason() {
        let settings = settings(iCloudStatus: "restricted")
        settings.icloudStatus.waitForLabel(containing: "Off")
        settings.icloudFooter.waitForLabel(containing: "restricted")
        settings.icloudOpenSettings.waitToAppear()
    }

    /// A build without iCloud (UI tests by default, CI's unsigned build): "Off", no button.
    @MainActor
    func testBuildWithoutICloudShowsOffWithoutButton() {
        let settings = settings(iCloudStatus: nil)
        settings.icloudStatus.waitForLabel(containing: "Off")
        settings.icloudFooter.waitForLabel("Data stays on this device.")
        XCTAssertFalse(settings.icloudOpenSettings.exists)
    }

    /// SC-10 in Russian.
    @MainActor
    func testRussianTexts() {
        let settings = settings(iCloudStatus: "noAccount", language: "ru", region: "ru_RU")
        settings.icloudStatus.waitForLabel(containing: "Выкл.")
        settings.icloudFooter.waitForLabel(containing: "войдите в iCloud")
        settings.icloudOpenSettings.waitForLabel("Открыть Настройки")
    }

    /// DM-28: an empty first launch with iCloud on waits for the lists instead of the onboarding.
    @MainActor
    func testEmptyFirstLaunchLooksForListsInICloud() {
        let app = Launch.app(emptyStore: true, iCloudStatus: "available", iCloudFirstImportSeconds: 60)
        let home = HomeScreen(app: app).waitUntilShown()
        home.icloudLookingState.waitToAppear()
        XCTAssertTrue(app.staticTexts["Looking for your lists in iCloud…"].exists)
        XCTAssertFalse(home.emptyState.exists, "no onboarding while iCloud may still bring lists")
        XCTAssertFalse(home.emptyStateTemplateButton.exists)
    }

    /// DM-27 / DM-28: without an iCloud account there is nothing to wait for: the onboarding at once.
    @MainActor
    func testEmptyLaunchWithoutAccountShowsOnboarding() {
        let app = Launch.app(emptyStore: true, iCloudStatus: "noAccount", iCloudFirstImportSeconds: 60)
        let home = HomeScreen(app: app).waitUntilShown()
        home.emptyState.waitToAppear()
        XCTAssertFalse(home.icloudLookingState.exists)
    }

    /// DM-28: the wait ends (here after 3 s, in the app after 10 s or the first import); then the onboarding.
    @MainActor
    func testLookingStateEndsWithOnboarding() {
        let app = Launch.app(emptyStore: true, iCloudStatus: "available", iCloudFirstImportSeconds: 3)
        let home = HomeScreen(app: app).waitUntilShown()
        // Whether a slow runner still sees "Looking…" is timing; the end state is not.
        home.emptyState.waitToAppear(timeout: 20)
        XCTAssertFalse(home.icloudLookingState.exists)
    }
}
