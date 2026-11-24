//
//  ICloudSyncMonitor.swift
//  Project2
//
//  Watches the iCloud account (SC-10, DM-27) and the first CloudKit import (DM-28).
//
//  - Account: `CKContainer.accountStatus()` at launch and after every
//    `.CKAccountChanged` (sign in / out while the app runs).
//  - Import: SwiftData syncs through `NSPersistentCloudKitContainer`, which posts
//    `eventChangedNotification` for its setup / import / export events.
//
//  Without iCloud in the build (tests, previews, CI's unsigned build) it never
//  creates a `CKContainer`: that call needs the iCloud entitlement.
//

import CloudKit
import CoreData
import Foundation
import OSLog

@MainActor
@Observable
final class ICloudSyncMonitor {

    /// One finished CloudKit mirroring event, copied out of the notification.
    struct SyncEvent: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case setup, `import`, export }
        let kind: Kind
        let succeeded: Bool
    }

    typealias AccountStatusProvider = @Sendable () async throws -> CKAccountStatus

    /// UserDefaults key: an iCloud import has finished on this device once (DM-28 is for the first launch).
    static let hasImportedKey = "iCloudSync.hasFinishedFirstImport"

    let isSyncActive: Bool
    private(set) var status: ICloudSyncStatus
    private(set) var hasEverImported: Bool
    private(set) var importFinishedThisLaunch = false
    private(set) var firstImportTimedOut: Bool

    /// DM-28: an empty Home shows "Looking for your lists in iCloud…" instead of the onboarding.
    var isLookingForFirstImport: Bool {
        FirstImportWait.isWaiting(status: status, hasEverImported: hasEverImported,
                                  importFinishedThisLaunch: importFinishedThisLaunch,
                                  timedOut: firstImportTimedOut)
    }

    @ObservationIgnored private let accountStatus: AccountStatusProvider?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let firstImportWait: Duration?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "iCloudSync")

    /// - Parameters:
    ///   - accountStatus: `nil` when this build doesn't sync: the status is `.offInThisBuild`.
    ///   - firstImportWait: how long an empty Home may wait for the first import (DM-28);
    ///     `nil` never waits.
    init(accountStatus: AccountStatusProvider?, firstImportWait: Duration? = FirstImportWait.limit,
         defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.accountStatus = accountStatus
        self.isSyncActive = accountStatus != nil
        self.status = accountStatus == nil ? .offInThisBuild : .checking
        self.firstImportWait = firstImportWait
        self.firstImportTimedOut = firstImportWait == nil
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.hasEverImported = defaults.bool(forKey: Self.hasImportedKey)
    }

    isolated deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Starts watching; a second call does nothing. Does nothing in a build without iCloud.
    func start() {
        guard isSyncActive, !isStarted else { return }
        isStarted = true

        observers.append(notificationCenter.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAccountStatus() }
            }
        })
        observers.append(notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let event = Self.finishedEvent(in: notification)
            MainActor.assumeIsolated {
                guard let self, let event else { return }
                self.handle(event)
            }
        })

        Task { await refreshAccountStatus() }
        if let firstImportWait, !hasEverImported {
            Task { [weak self] in
                try? await Task.sleep(for: firstImportWait)
                self?.firstImportTimedOut = true
            }
        }
    }

    /// Asks CloudKit for the account status again.
    func refreshAccountStatus() async {
        guard let accountStatus else { return }
        do {
            status = ICloudSyncStatus(accountStatus: try await accountStatus(), isSyncActive: true)
        } catch {
            logger.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            status = .couldNotDetermine
        }
    }

    /// A finished import ends the DM-28 wait; a successful one also ends it for good on this
    /// device. A failed setup means no import will come this launch.
    func handle(_ event: SyncEvent) {
        switch event.kind {
        case .import:
            importFinishedThisLaunch = true
            if event.succeeded, !hasEverImported {
                hasEverImported = true
                defaults.set(true, forKey: Self.hasImportedKey)
            }
        case .setup:
            if !event.succeeded { importFinishedThisLaunch = true }
        case .export:
            break
        }
        if !event.succeeded {
            logger.error("CloudKit \(String(describing: event.kind), privacy: .public) event failed")
        }
    }

    /// The finished event in a `NSPersistentCloudKitContainer.eventChangedNotification`;
    /// `nil` while it is still running (`endDate == nil`).
    nonisolated static func finishedEvent(in notification: Notification) -> SyncEvent? {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil else { return nil }
        let kind: SyncEvent.Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: return nil
        }
        return SyncEvent(kind: kind, succeeded: event.succeeded)
    }
}

extension ICloudSyncMonitor {
    /// The monitor for this launch.
    /// - Normal launch with CloudKit on: the real account status of our container.
    /// - `-UITests -UITestsICloudStatus <name>`: that status, no CloudKit (SC-10 UI tests);
    ///   with `-UITestsICloudFirstImportSeconds N` an empty Home waits N seconds (DM-28).
    /// - Otherwise (unit tests, other UI tests, unsigned build): `.offInThisBuild`.
    static func forLaunch(location: StoreLocation?) -> ICloudSyncMonitor {
        if LaunchConfiguration.isUITesting {
            guard let name = LaunchConfiguration.iCloudStatusOverride,
                  let fixed = ICloudSyncStatus.accountStatus(named: name) else {
                return ICloudSyncMonitor(accountStatus: nil)
            }
            return ICloudSyncMonitor(
                accountStatus: { fixed },
                firstImportWait: LaunchConfiguration.iCloudFirstImportWaitOverride,
                defaults: volatileDefaults()
            )
        }
        guard let location, location.usesCloudKit else {
            return ICloudSyncMonitor(accountStatus: nil)
        }
        let identifier = SyncConfig.cloudKitContainerIdentifier
        return ICloudSyncMonitor(accountStatus: {
            try await CKContainer(identifier: identifier).accountStatus()
        })
    }

    /// Fresh, empty defaults for a UI test launch (the "first import done" mark never sticks).
    static func volatileDefaults() -> UserDefaults {
        let suiteName = "iCloudSync.volatile"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
