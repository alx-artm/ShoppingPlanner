//
//  Persistence.swift
//  Project2
//
//  One place that builds the SwiftData `ModelContainer` for the app,
//  previews, UI tests and unit tests.
//

import Foundation
import SwiftData

/// iCloud sync feature flag (spec 01 "Sync", ROADMAP prerequisites).
///
/// This is THE switch for CloudKit. It stays `false` until the project moves
/// from the free Personal Team to the paid Apple Developer Program: without it
/// the iCloud capability can't be signed. Turning it on (M6) also needs the
/// iCloud + Background Modes capabilities and an App Group container.
enum SyncConfig {
    static let isCloudKitEnabled = false
}

/// How the current process should set up its data.
enum LaunchConfiguration {
    /// Launch argument used by XCUITest: in-memory store + deterministic seed data.
    static let uiTestsArgument = "-UITests"
    /// Together with `-UITests`: in-memory store without seed data (empty state).
    static let uiTestsEmptyStoreArgument = "-UITestsEmptyStore"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestsArgument)
    }

    static var wantsEmptyStore: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestsEmptyStoreArgument)
    }
}

enum Persistence {
    /// File name of the on-disk store. A new name (instead of SwiftData's
    /// `default.store`) starts the versioned schema with a clean file: the app
    /// is not released, and pre-M1 development stores are not migrated.
    static let storeName = "Planner"

    static var schema: Schema {
        Schema(versionedSchema: SchemaV1.self)
    }

    /// Builds the container. `inMemory` is used by previews, UI tests and unit tests.
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        // In-memory stores get a unique name so two containers in one test
        // process never share data.
        let configuration = ModelConfiguration(
            inMemory ? "InMemory-\(UUID().uuidString)" : storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: (SyncConfig.isCloudKitEnabled && !inMemory) ? .automatic : .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: PlannerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
