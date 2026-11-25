//
//  ICloudSyncTests.swift
//  Project2Tests
//
//  M6 iCloud sync without CloudKit: the account status → Settings row mapping
//  (SC-10, DM-27), the DM-28 "Looking for your lists in iCloud…" wait, and the
//  monitor that feeds them (CKAccountChanged, CloudKit events, the 10 s limit).
//  The account status comes from a closure; no test creates a CKContainer.
//

import CloudKit
import Foundation
import Testing
@testable import Project2

extension Tag {
    /// iCloud sync: status, first import, store location (spec 01 Sync, 07 SC-10).
    @Tag static var iCloudSync: Self
}

@Suite("iCloud status mapping", .tags(.iCloudSync, .settings))
struct ICloudSyncStatusTests {

    @Test("SC-10 every account status maps to a row state when sync is on in the build",
          arguments: [
            (CKAccountStatus.available, ICloudSyncStatus.on),
            (.noAccount, .noAccount),
            (.restricted, .restricted),
            (.temporarilyUnavailable, .temporarilyUnavailable),
            (.couldNotDetermine, .couldNotDetermine),
          ])
    func mapping(account: CKAccountStatus, expected: ICloudSyncStatus) {
        #expect(ICloudSyncStatus(accountStatus: account, isSyncActive: true) == expected)
    }

    @Test("SC-10 a build without iCloud is Off even with an available account",
          arguments: [CKAccountStatus.available, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine])
    func offInBuild(account: CKAccountStatus) {
        #expect(ICloudSyncStatus(accountStatus: account, isSyncActive: false) == .offInThisBuild)
    }

    @Test("SC-10 only .on says On; account problems offer the system Settings, a build without iCloud doesn't")
    func rowContent() {
        #expect(ICloudSyncStatus.on.isOn)
        let off: [ICloudSyncStatus] = [.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine, .offInThisBuild]
        for status in off {
            #expect(!status.isOn)
            #expect(String(localized: status.valueText) == String(localized: "Off"), "\(status)")
        }
        #expect(ICloudSyncStatus.on.offersSystemSettings == false)
        #expect(ICloudSyncStatus.checking.offersSystemSettings == false)
        #expect(ICloudSyncStatus.offInThisBuild.offersSystemSettings == false)
        for status in [ICloudSyncStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine] {
            #expect(status.offersSystemSettings, "\(status)")
        }
    }

    @Test("SC-10 every state has its own explanation", .englishUI)
    func footers() {
        let texts = [ICloudSyncStatus.on, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine]
            .map { String(localized: $0.footerText) }
        #expect(Set(texts).count == texts.count)
        #expect(String(localized: ICloudSyncStatus.offInThisBuild.footerText) == "Data stays on this device.")
        #expect(String(localized: ICloudSyncStatus.on.valueText) == "On")
    }

    @Test("UI test override names are the CKAccountStatus case names")
    func overrideNames() {
        #expect(ICloudSyncStatus.accountStatus(named: "available") == .available)
        #expect(ICloudSyncStatus.accountStatus(named: "noAccount") == .noAccount)
        #expect(ICloudSyncStatus.accountStatus(named: "restricted") == .restricted)
        #expect(ICloudSyncStatus.accountStatus(named: "temporarilyUnavailable") == .temporarilyUnavailable)
        #expect(ICloudSyncStatus.accountStatus(named: "couldNotDetermine") == .couldNotDetermine)
        #expect(ICloudSyncStatus.accountStatus(named: "on") == nil)
    }
}

@Suite("DM-28 first import wait", .tags(.iCloudSync, .home))
struct FirstImportWaitTests {

    @Test("waits only while iCloud is on (or still checking) and no import has finished")
    func truthTable() {
        #expect(FirstImportWait.isWaiting(status: .on, hasEverImported: false, importFinishedThisLaunch: false, timedOut: false))
        #expect(FirstImportWait.isWaiting(status: .checking, hasEverImported: false, importFinishedThisLaunch: false, timedOut: false))
        // Any reason to stop waiting shows the onboarding.
        #expect(!FirstImportWait.isWaiting(status: .on, hasEverImported: true, importFinishedThisLaunch: false, timedOut: false))
        #expect(!FirstImportWait.isWaiting(status: .on, hasEverImported: false, importFinishedThisLaunch: true, timedOut: false))
        #expect(!FirstImportWait.isWaiting(status: .on, hasEverImported: false, importFinishedThisLaunch: false, timedOut: true))
        // DM-27: without iCloud there is nothing to wait for.
        for status in [ICloudSyncStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine, .offInThisBuild] {
            #expect(!FirstImportWait.isWaiting(status: status, hasEverImported: false, importFinishedThisLaunch: false, timedOut: false))
        }
    }

    @Test("the limit is 10 seconds")
    func limit() {
        #expect(FirstImportWait.limit == .seconds(10))
    }
}

/// Answers the account status the test sets, counting the calls.
private actor FakeAccount {
    var status: CKAccountStatus
    var error: (any Error)?
    private(set) var calls = 0

    init(_ status: CKAccountStatus) { self.status = status }

    func set(_ status: CKAccountStatus) { self.status = status }
    func fail(with error: any Error) { self.error = error }

    func fetch() throws -> CKAccountStatus {
        calls += 1
        if let error { throw error }
        return status
    }
}

@MainActor
@Suite("ICloudSyncMonitor", .tags(.iCloudSync))
final class ICloudSyncMonitorTests {
    struct Failure: Error {}

    private let suiteName = "ICloudSyncMonitorTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    /// A private center: the tests post `CKAccountChanged` without touching the app's observers.
    private let center = NotificationCenter()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func monitor(_ account: FakeAccount, wait: Duration? = FirstImportWait.limit) -> ICloudSyncMonitor {
        ICloudSyncMonitor(accountStatus: { try await account.fetch() }, firstImportWait: wait,
                          defaults: defaults, notificationCenter: center)
    }

    /// Polls a condition the monitor reaches through its own tasks.
    private func eventually(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("DM-27 without iCloud in the build: Off, no waiting, start() does nothing")
    func noSyncInBuild() {
        let monitor = ICloudSyncMonitor(accountStatus: nil, defaults: defaults, notificationCenter: center)
        monitor.start()
        #expect(!monitor.isSyncActive)
        #expect(monitor.status == .offInThisBuild)
        #expect(!monitor.isLookingForFirstImport)
    }

    @Test("SC-10 starts as Checking, then shows the account status")
    func initialStatus() async {
        let account = FakeAccount(.available)
        let monitor = monitor(account)
        #expect(monitor.status == .checking)
        monitor.start()
        #expect(await eventually { monitor.status == .on })
    }

    @Test("SC-10 CKAccountChanged refreshes the status (sign out, sign back in)")
    func accountChanged() async {
        let account = FakeAccount(.available)
        let monitor = monitor(account)
        monitor.start()
        #expect(await eventually { monitor.status == .on })

        await account.set(.noAccount)
        center.post(name: .CKAccountChanged, object: nil)
        #expect(await eventually { monitor.status == .noAccount })

        await account.set(.available)
        center.post(name: .CKAccountChanged, object: nil)
        #expect(await eventually { monitor.status == .on })
    }

    @Test("SC-10 an account status error shows Off (could not determine)")
    func accountError() async {
        let account = FakeAccount(.available)
        await account.fail(with: Failure())
        let monitor = monitor(account)
        await monitor.refreshAccountStatus()
        #expect(monitor.status == .couldNotDetermine)
        #expect(monitor.status.offersSystemSettings)
    }

    @Test("start() twice observes once: one CKAccountChanged → one refresh")
    func startIsIdempotent() async {
        let account = FakeAccount(.available)
        let monitor = monitor(account)
        monitor.start()
        monitor.start()
        #expect(await eventually { monitor.status == .on })
        let before = await account.calls
        center.post(name: .CKAccountChanged, object: nil)
        // Give a second observer (if there were one) time to refresh too.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await account.calls == before + 1)
    }

    @Test("DM-28 a successful import ends the wait for good on this device")
    func successfulImport() async {
        let account = FakeAccount(.available)
        let monitor = monitor(account)
        monitor.start()
        #expect(await eventually { monitor.status == .on })
        #expect(monitor.isLookingForFirstImport)

        monitor.handle(.init(kind: .export, succeeded: true))
        #expect(monitor.isLookingForFirstImport, "an export is not the import")

        monitor.handle(.init(kind: .import, succeeded: true))
        #expect(!monitor.isLookingForFirstImport)
        #expect(defaults.bool(forKey: ICloudSyncMonitor.hasImportedKey))

        // The next launch on this device doesn't wait at all.
        let next = self.monitor(FakeAccount(.available))
        #expect(next.hasEverImported)
        #expect(!next.isLookingForFirstImport)
    }

    @Test("DM-28 a failed import or setup ends this launch's wait, but not for good")
    func failedEvents() {
        let first = monitor(FakeAccount(.available))
        first.handle(.init(kind: .import, succeeded: false))
        #expect(!first.isLookingForFirstImport)
        #expect(!defaults.bool(forKey: ICloudSyncMonitor.hasImportedKey))

        let second = monitor(FakeAccount(.available))
        #expect(second.isLookingForFirstImport)
        second.handle(.init(kind: .setup, succeeded: true))
        #expect(second.isLookingForFirstImport, "a successful setup is followed by the import")
        second.handle(.init(kind: .setup, succeeded: false))
        #expect(!second.isLookingForFirstImport)
    }

    @Test("DM-28 no import event: the wait ends after the limit")
    func timeout() async {
        let monitor = monitor(FakeAccount(.available), wait: .milliseconds(100))
        monitor.start()
        #expect(await eventually { monitor.status == .on })
        #expect(await eventually { !monitor.isLookingForFirstImport })
        #expect(monitor.firstImportTimedOut)
        #expect(!monitor.hasEverImported)
    }

    @Test("DM-28 no wait limit given: never waits (UI tests without the override)")
    func noWait() {
        let monitor = monitor(FakeAccount(.available), wait: nil)
        #expect(!monitor.isLookingForFirstImport)
    }

    @Test("DM-27 no account: never waits for an import")
    func noAccountNoWait() async {
        let monitor = monitor(FakeAccount(.noAccount))
        monitor.start()
        #expect(await eventually { monitor.status == .noAccount })
        #expect(!monitor.isLookingForFirstImport)
    }

    @Test("the unit test host and other launches without CloudKit never create a CKContainer")
    func forLaunchWithoutCloudKit() {
        let local = StoreLocation(directory: URL.temporaryDirectory, usesCloudKit: false)
        #expect(ICloudSyncMonitor.forLaunch(location: local).status == .offInThisBuild)
        #expect(ICloudSyncMonitor.forLaunch(location: nil).status == .offInThisBuild)
    }

    @Test("an unfinished CloudKit event or an unrelated notification is ignored")
    func finishedEventParsing() {
        #expect(ICloudSyncMonitor.finishedEvent(in: Notification(name: .CKAccountChanged)) == nil)
        let noEvent = Notification(name: .init("event"), object: nil, userInfo: ["other": 1])
        #expect(ICloudSyncMonitor.finishedEvent(in: noEvent) == nil)
    }
}
