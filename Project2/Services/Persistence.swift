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

    /// Together with `-UITests`: `-UITestsUndoToastSeconds 60` keeps the "Undo" toast that long.
    /// UI tests that act while the toast is shown would otherwise race its 4-second timer,
    /// which a slow CI runner can lose.
    static let uiTestsUndoToastSecondsArgument = "-UITestsUndoToastSeconds"

    /// The toast duration asked for by a UI test, `nil` in a normal launch.
    static var undoToastDurationOverride: Duration? {
        seconds(after: uiTestsUndoToastSecondsArgument)
    }

    /// Together with `-UITests`: `-UITestsRowHighlightSeconds 60` keeps the row highlight after
    /// a purchase bar tap (LD-27) that long instead of ~1 s, so a test can check it unhurried.
    static let uiTestsRowHighlightSecondsArgument = "-UITestsRowHighlightSeconds"

    /// The highlight duration asked for by a UI test, `nil` in a normal launch.
    static var rowHighlightDurationOverride: Duration? {
        seconds(after: uiTestsRowHighlightSecondsArgument)
    }

    /// Together with `-UITests`: `-UITestsInlineFieldDelaySeconds 1` inserts the inline price /
    /// link field that much later after [Price] / [Link], as on a slow device, so a UI test
    /// proves the keyboard still moves to it instead of staying in the name field.
    static let uiTestsInlineFieldDelaySecondsArgument = "-UITestsInlineFieldDelaySeconds"

    /// The delay asked for by a UI test, `nil` in a normal launch.
    static var inlineFieldDelayOverride: Duration? {
        seconds(after: uiTestsInlineFieldDelaySecondsArgument)
    }

    private static func seconds(after argument: String) -> Duration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isUITesting,
              let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1),
              let seconds = Int(arguments[index + 1]), seconds > 0 else { return nil }
        return .seconds(seconds)
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
