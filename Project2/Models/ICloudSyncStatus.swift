//
//  ICloudSyncStatus.swift
//  Project2
//
//  What Settings says about iCloud sync (spec 07 SC-10, spec 01 DM-27) and when
//  an empty Home waits for the first iCloud import (DM-28). Pure logic, no
//  CloudKit calls: `ICloudSyncMonitor` feeds it.
//

import CloudKit
import Foundation

enum ICloudSyncStatus: Equatable, Sendable {
    /// The account status hasn't arrived yet.
    case checking
    /// Signed in to iCloud and this build syncs (SC-10 "On").
    case on
    /// Not signed in to iCloud, or iCloud is off for this app.
    case noAccount
    /// Parental controls / device management don't allow iCloud.
    case restricted
    /// Signed in, but iCloud isn't ready (e.g. the account needs verifying).
    case temporarilyUnavailable
    /// CloudKit couldn't tell (an error, or an unknown status).
    case couldNotDetermine
    /// This build has no iCloud (an unsigned CI build, previews, tests): data stays local.
    case offInThisBuild

    /// SC-10: "On" only when the account is available AND this build syncs.
    init(accountStatus: CKAccountStatus, isSyncActive: Bool) {
        guard isSyncActive else {
            self = .offInThisBuild
            return
        }
        switch accountStatus {
        case .available: self = .on
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .couldNotDetermine
        @unknown default: self = .couldNotDetermine
        }
    }

    /// `-UITestsICloudStatus <name>`: the names of `CKAccountStatus` cases.
    static func accountStatus(named name: String) -> CKAccountStatus? {
        switch name {
        case "available": .available
        case "noAccount": .noAccount
        case "restricted": .restricted
        case "temporarilyUnavailable": .temporarilyUnavailable
        case "couldNotDetermine": .couldNotDetermine
        default: nil
        }
    }

    var isOn: Bool { self == .on }

    /// The value of the "iCloud Sync" row.
    var valueText: LocalizedStringResource {
        switch self {
        case .checking: "Checking…"
        case .on: "On"
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine, .offInThisBuild: "Off"
        }
    }

    /// The explanation under the row (SC-10 "Off с пояснением").
    var footerText: LocalizedStringResource {
        switch self {
        case .checking, .offInThisBuild:
            "Data stays on this device."
        case .on:
            "Your lists sync to your other devices signed in to the same Apple Account."
        case .noAccount:
            "Sign in to iCloud in the Settings app to sync your lists. Until then, data stays on this device."
        case .restricted:
            "iCloud is restricted on this device, for example by Screen Time. Data stays on this device."
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable. Your lists are saved on this device and will sync when it's back."
        case .couldNotDetermine:
            "Couldn't check iCloud. Data stays on this device."
        }
    }

    /// SC-10: an "Off" caused by the account offers a button to the system Settings.
    /// Not for a build without iCloud: Settings can't change that.
    var offersSystemSettings: Bool {
        switch self {
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine: true
        case .checking, .on, .offInThisBuild: false
        }
    }
}

/// DM-28: on a new device, an empty Home first looks for lists in iCloud instead of
/// showing the onboarding, for at most `limit` or until the first import finishes.
enum FirstImportWait {
    static let limit: Duration = .seconds(10)

    static func isWaiting(status: ICloudSyncStatus, hasEverImported: Bool,
                          importFinishedThisLaunch: Bool, timedOut: Bool) -> Bool {
        // `.checking`: the account status takes a moment at launch; showing the
        // onboarding first and then "Looking…" would flash.
        guard status == .on || status == .checking else { return false }
        return !hasEverImported && !importFinishedThisLaunch && !timedOut
    }
}
