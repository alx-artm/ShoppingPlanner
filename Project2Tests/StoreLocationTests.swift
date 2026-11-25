//
//  StoreLocationTests.swift
//  Project2Tests
//
//  M6: where the on-disk store lives (App Group folder vs. the app's own folder
//  in a build without entitlements), the one-time move between them, and the
//  identifiers shared by `SyncConfig` and `Project2.entitlements`.
//  Every test works in its own temporary folder; nothing here touches CloudKit.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@Suite("Store location and migration", .tags(.iCloudSync, .schema))
final class StoreLocationTests {
    private let root: URL
    private let source: URL
    private let destination: URL
    private let fileManager = FileManager.default

    init() throws {
        root = URL.temporaryDirectory.appending(path: "StoreLocationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        source = root.appending(path: "App/Library/Application Support", directoryHint: .isDirectory)
        destination = root.appending(path: "Group/Library/Application Support", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// A fake store: the SQLite file, its journals and an external-storage blob.
    private func writeStore(in folder: URL, marker: String = "old") throws {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["Planner.store", "Planner.store-shm", "Planner.store-wal"] {
            try Data("\(marker) \(name)".utf8).write(to: folder.appending(path: name))
        }
        let blobs = folder.appending(path: ".Planner_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: blobs, withIntermediateDirectories: true)
        try Data("\(marker) thumbnail".utf8).write(to: blobs.appending(path: "ABC"))
    }

    private func text(_ folder: URL, _ path: String) throws -> String {
        String(decoding: try Data(contentsOf: folder.appending(path: path)), as: UTF8.self)
    }

    private func exists(_ folder: URL, _ path: String) -> Bool {
        fileManager.fileExists(atPath: folder.appending(path: path).path)
    }

    // MARK: - StoreLocation

    @Test("with the App Group: the group's Application Support folder, synced")
    func appGroupLocation() {
        let group = root.appending(path: "Group", directoryHint: .isDirectory)
        let location = StoreLocation.resolve(appGroupContainer: group, applicationSupport: source, isCloudKitEnabled: true)
        #expect(location.directory.standardizedFileURL == destination.standardizedFileURL)
        #expect(location.usesCloudKit)
        #expect(location.storeURL.lastPathComponent == "Planner.store")

        let flagOff = StoreLocation.resolve(appGroupContainer: group, applicationSupport: source, isCloudKitEnabled: false)
        #expect(flagOff.directory == location.directory, "the Share Extension needs the group folder even without sync")
        #expect(!flagOff.usesCloudKit)
    }

    @Test("without the App Group entitlement (CI's unsigned build): the app's own folder, never CloudKit")
    func unsignedLocation() {
        let location = StoreLocation.resolve(appGroupContainer: nil, applicationSupport: source, isCloudKitEnabled: true)
        #expect(location.directory == source)
        #expect(!location.usesCloudKit)
    }

    @Test("DM-05 an on-disk container without CloudKit opens, saves and reopens")
    @MainActor
    func onDiskContainer() throws {
        let location = StoreLocation(directory: destination, usesCloudKit: false)
        do {
            let container = try Persistence.makeContainer(at: location)
            container.mainContext.insert(ListModel(name: "Saved"))
            try container.mainContext.save()
        }
        #expect(exists(destination, "Planner.store"))
        let reopened = try Persistence.makeContainer(at: location)
        let names = try reopened.mainContext.fetch(FetchDescriptor<ListModel>()).map(\.name)
        #expect(names == ["Saved"])
    }

    // MARK: - StoreMigrator

    @Test("the store, its journals and its external-storage folder move to the App Group")
    func movesEverything() throws {
        try writeStore(in: source)
        let outcome = try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination)
        #expect(outcome == .moved(StoreMigrator.fileNames(storeName: "Planner")))
        #expect(try text(destination, "Planner.store") == "old Planner.store")
        #expect(try text(destination, "Planner.store-wal") == "old Planner.store-wal")
        #expect(try text(destination, ".Planner_SUPPORT/_EXTERNAL_DATA/ABC") == "old thumbnail")
        for name in StoreMigrator.fileNames(storeName: "Planner") {
            #expect(!exists(source, name), "\(name) is left in the old folder")
        }
    }

    @Test("a store without journal files moves too")
    func movesPartialSet() throws {
        try Data("db".utf8).write(to: source.appending(path: "Planner.store"))
        let outcome = try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination)
        #expect(outcome == .moved(["Planner.store"]))
        #expect(exists(destination, "Planner.store"))
    }

    @Test("nothing in the old folder: nothing happens (a fresh install)")
    func nothingToMove() throws {
        #expect(try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination) == .nothingToMove)
        #expect(!exists(destination, ""))
    }

    @Test("the same folder (unsigned build): nothing happens")
    func sameFolder() throws {
        try writeStore(in: source)
        #expect(try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: source) == .nothingToMove)
        #expect(exists(source, "Planner.store"))
    }

    @Test("a store already in the App Group wins; the old files are left alone")
    func destinationWins() throws {
        try writeStore(in: source, marker: "old")
        try writeStore(in: destination, marker: "new")
        #expect(try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination) == .destinationExists)
        #expect(try text(destination, "Planner.store") == "new Planner.store")
        #expect(try text(source, "Planner.store") == "old Planner.store")
    }

    @Test("a failed copy is rolled back: the store stays complete in the old folder")
    func rollback() throws {
        try writeStore(in: source)
        // The external-storage folder can't be copied: one with that name is already there.
        try fileManager.createDirectory(at: destination.appending(path: ".Planner_SUPPORT"), withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination)
        }
        for name in ["Planner.store", "Planner.store-shm", "Planner.store-wal"] {
            #expect(!exists(destination, name), "\(name) copy was not rolled back")
        }
        for name in StoreMigrator.fileNames(storeName: "Planner") {
            #expect(exists(source, name), "\(name) is gone from the old folder")
        }
    }

    @Test("a real SwiftData store still opens with its data after the move")
    @MainActor
    func realStoreSurvivesMove() throws {
        do {
            let old = try Persistence.makeContainer(at: StoreLocation(directory: source, usesCloudKit: false))
            let list = ListModel(name: "Groceries")
            old.mainContext.insert(list)
            let group = GroupModel(name: "Fruit")
            group.list = list
            old.mainContext.insert(group)
            try old.mainContext.save()
        }
        guard case .moved = try StoreMigrator.moveStoreIfNeeded(named: "Planner", from: source, to: destination) else {
            Issue.record("the store was not moved")
            return
        }
        let moved = try Persistence.makeContainer(at: StoreLocation(directory: destination, usesCloudKit: false))
        let lists = try moved.mainContext.fetch(FetchDescriptor<ListModel>())
        #expect(lists.map(\.name) == ["Groceries"])
        #expect(lists.first?.groups?.map(\.name) == ["Fruit"])
    }

    // MARK: - Identifiers

    @Test("Р-31 the iCloud container and App Group are derived from the app's bundle id")
    func identifiersFollowBundleID() throws {
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(bundleID == "com.aliakseiartsimuk.shoppingplanner")
        #expect(SyncConfig.cloudKitContainerIdentifier == "iCloud.\(bundleID)")
        #expect(SyncConfig.appGroupIdentifier == "group.\(bundleID)")
        #expect(TipKind.productIDPrefix == "\(bundleID).tip.")
    }

    @Test("Project2.entitlements declares exactly the container and group SyncConfig uses")
    func entitlementsMatchSyncConfig() throws {
        // The source file (the built app has the entitlements only in its signature).
        let file = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Project2/Project2.entitlements")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
        #expect(plist["com.apple.developer.icloud-container-identifiers"] as? [String] == [SyncConfig.cloudKitContainerIdentifier])
        #expect(plist["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"])
        #expect(plist["com.apple.security.application-groups"] as? [String] == [SyncConfig.appGroupIdentifier])
        #expect(plist["aps-environment"] != nil, "CloudKit needs push for silent sync notifications")
    }

    @Test("Background Modes: remote notifications, so CloudKit changes arrive while in the background")
    func remoteNotificationBackgroundMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("remote-notification"))
    }
}
