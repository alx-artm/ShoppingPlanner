//
//  Persistence.swift
//  Project2
//
//  One place that builds the SwiftData `ModelContainer` for the app,
//  previews, UI tests and unit tests, and decides where the store lives (M6:
//  the App Group folder, synced with iCloud).
//

import Foundation
import SwiftData

/// iCloud sync settings (spec 01 "Sync", M6).
///
/// The identifiers come from the permanent bundle id (DECISIONS Р-31) and can never
/// change: users' data lives in this iCloud container. They must match
/// `Project2.entitlements`.
enum SyncConfig {
    /// THE switch for CloudKit. On since M6 (paid Apple Developer Program).
    /// A build without the entitlements (CI's `CODE_SIGNING_ALLOWED=NO`) stays local anyway,
    /// see `StoreLocation.resolve`.
    static let isCloudKitEnabled = true

    static let cloudKitContainerIdentifier = "iCloud.com.aliakseiartsimuk.shoppingplanner"

    /// Shared with the Share Extension (spec 06, M7).
    static let appGroupIdentifier = "group.com.aliakseiartsimuk.shoppingplanner"
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

    /// The app is the host of the unit tests: in-memory store, never CloudKit.
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Together with `-UITests`: `-UITestsICloudStatus available` (or `noAccount`, `restricted`,
    /// `temporarilyUnavailable`, `couldNotDetermine`) shows that iCloud account status in Settings
    /// (SC-10). No CloudKit is touched: the store stays in memory.
    static let uiTestsICloudStatusArgument = "-UITestsICloudStatus"

    /// The account status asked for by a UI test, `nil` in a normal launch.
    static var iCloudStatusOverride: String? {
        value(after: uiTestsICloudStatusArgument)
    }

    /// Together with `-UITests -UITestsICloudStatus available`: `-UITestsICloudFirstImportSeconds 60`
    /// shows "Looking for your lists in iCloud…" on an empty Home that long, as on a first launch
    /// whose iCloud import hasn't finished yet (DM-28).
    static let uiTestsICloudFirstImportSecondsArgument = "-UITestsICloudFirstImportSeconds"

    static var iCloudFirstImportWaitOverride: Duration? {
        seconds(after: uiTestsICloudFirstImportSecondsArgument)
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

    /// Together with `-UITests`: the inline name field loses the keyboard once, inside a view
    /// update, when its first character arrives, so a UI test proves the field takes it back
    /// (a loss from inside an update, as on a slow CI runner) instead of closing inline add.
    static let uiTestsDropInlineNameFocusArgument = "-UITestsDropInlineNameFocus"

    static var dropsInlineNameFocusOnce: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains(uiTestsDropInlineNameFocusArgument)
    }

    /// Together with `-UITests`: `-UITestsLinkPreview stub` answers link previews from
    /// `StubLinkMetadataFetcher`. Without it a UI test gets no previews and no network (LP-13).
    static let uiTestsLinkPreviewArgument = "-UITestsLinkPreview"
    static let uiTestsLinkPreviewStubValue = "stub"

    /// Together with `-UITests`: links are recorded in `debug.lastOpenedLink` instead of
    /// opened, so a UI test never leaves the app for Safari (spec 06 A.5, `LinkOpener`).
    static let uiTestsRecordOpenedLinksArgument = "-UITestsRecordOpenedLinks"

    static func recordsOpenedLinks(arguments: [String]) -> Bool {
        arguments.contains(uiTestsArgument) && arguments.contains(uiTestsRecordOpenedLinksArgument)
    }

    /// Together with `-UITests`: `-UITestsShareComposer url` shows the Share Extension's compose
    /// screen in the app, in a sheet over Home, on the same in-memory store (spec 06 B.5).
    /// Scenarios: `ShareComposerScenario`. Add `-UITestsLinkPreview stub` for titles.
    static let uiTestsShareComposerArgument = "-UITestsShareComposer"

    /// The composer scenario asked for by a UI test, `nil` in a normal launch.
    static var shareComposerScenario: String? {
        value(after: uiTestsShareComposerArgument)
    }

    /// Together with `-UITests`: `-UITestsLinkRows 200` adds the list "Links" with that many
    /// items, most of them with links and pictures (`SeedData.populateLinkRows`, LP-19).
    static let uiTestsLinkRowsArgument = "-UITestsLinkRows"

    /// The number of link rows asked for by a UI test, `nil` in a normal launch.
    static var linkRowCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isUITesting,
              let index = arguments.firstIndex(of: uiTestsLinkRowsArgument),
              arguments.indices.contains(index + 1),
              let count = Int(arguments[index + 1]), count > 0 else { return nil }
        return count
    }

    private static func seconds(after argument: String) -> Duration? {
        guard let value = value(after: argument), let seconds = Int(value), seconds > 0 else { return nil }
        return .seconds(seconds)
    }

    /// The argument that follows `argument` in a UI test launch, `nil` otherwise.
    private static func value(after argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isUITesting,
              let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Where the on-disk store lives in this launch and whether it syncs (spec 01 "Sync").
struct StoreLocation: Equatable, Sendable {
    /// The folder with `Planner.store` and its companion files (`StoreMigrator.fileNames`).
    let directory: URL
    /// `cloudKitDatabase: .automatic` (the private database of the entitled container) or `.none`.
    let usesCloudKit: Bool

    var storeURL: URL {
        directory.appending(path: "\(Persistence.storeName).store", directoryHint: .notDirectory)
    }

    /// - Parameters:
    ///   - appGroupContainer: the App Group folder, `nil` when the build has no App Group
    ///     entitlement. That is CI's unsigned build (`CODE_SIGNING_ALLOWED=NO`): it has no
    ///     iCloud entitlement either, so it keeps the store in the app's own folder, without
    ///     CloudKit. Both entitlements come from the same `Project2.entitlements`.
    ///   - applicationSupport: the app's own Application Support folder (the pre-M6 location).
    static func resolve(appGroupContainer: URL?, applicationSupport: URL, isCloudKitEnabled: Bool) -> StoreLocation {
        guard let appGroupContainer else {
            return StoreLocation(directory: applicationSupport, usesCloudKit: false)
        }
        // The same layout as SwiftData's own `groupContainer:` option.
        let directory = appGroupContainer.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return StoreLocation(directory: directory, usesCloudKit: isCloudKitEnabled)
    }

    /// The Share Extension's store (spec 06 B.4 p.1, SE-11a): the app's file in the App Group
    /// folder, but never synced: only the app talks to CloudKit, otherwise two processes would
    /// mirror one store and create duplicates. `nil` without the App Group (CI's unsigned
    /// build): the extension then says it is unavailable instead of writing to its own
    /// folder, where the app would never see the item.
    static func forShareExtension(appGroupContainer: URL?) -> StoreLocation? {
        guard let appGroupContainer else { return nil }
        return resolve(appGroupContainer: appGroupContainer, applicationSupport: appGroupContainer,
                       isCloudKitEnabled: false)
    }

    /// The location for a normal launch of this build.
    static func current(fileManager: FileManager = .default) -> StoreLocation {
        resolve(
            appGroupContainer: fileManager.containerURL(forSecurityApplicationGroupIdentifier: SyncConfig.appGroupIdentifier),
            applicationSupport: URL.applicationSupportDirectory,
            isCloudKitEnabled: SyncConfig.isCloudKitEnabled
        )
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

    /// In-memory container for previews, UI tests and unit tests: never CloudKit.
    /// Each one gets a unique name so two containers in one test process never share data.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "InMemory-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try makeContainer(configuration)
    }

    /// The on-disk store of a normal launch, synced with iCloud when `location.usesCloudKit`.
    static func makeContainer(at location: StoreLocation, fileManager: FileManager = .default) throws -> ModelContainer {
        try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: location.storeURL,
            cloudKitDatabase: location.usesCloudKit ? .automatic : .none
        )
        return try makeContainer(configuration)
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: PlannerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
