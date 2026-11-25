//
//  Project__2App.swift
//  Project #2
//
//  Created by Alex on 8.05.25.
//

import OSLog
import SwiftData
import SwiftUI

@main
struct Project2App: App {

    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    @Environment(\.scenePhase) private var scenePhase

    /// Built once at launch. A failure shows an error screen instead of crashing (DM-17).
    private let environment: Result<AppEnvironment, any Error>

    init() {
        environment = Result { try AppEnvironment.make() }
        if case .failure(let error) = environment {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "App")
                .fault("Could not open the data store: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch environment {
                case .success(let environment):
                    ContentView()
                        .modelContainer(environment.container)
                        .environment(environment.store)
                        .environment(environment.uiState)
                        .environment(environment.settings)
                        .environment(environment.linkPreviews)
                        .environment(\.linkOpener, environment.linkOpener)
                        .environment(environment.tipJar)
                        .environment(environment.iCloudSync)
                        // Items saved by the Share Extension (SE-10, SE-10a).
                        .onAppear { environment.startShareInbox() }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { environment.pullSharedItems() }
                        }
                case .failure(let error):
                    StartupErrorView(error: error)
                }
            }
            .preferredColorScheme(selectedTheme.colorScheme)
        }
        .commands { PlannerCommands() }
    }
}

/// Everything the views need from the data layer.
@MainActor
struct AppEnvironment {
    let container: ModelContainer
    let store: PlannerStore
    let uiState: LocalUIState
    let settings: AppSettings
    let linkPreviews: LinkPreviewService
    let linkOpener: LinkOpener
    /// `nil` unless the Tip Jar is on (spec 12, `TipJarConfig`).
    let tipJar: TipJar?
    /// iCloud account status and the first import (SC-10, DM-27, DM-28).
    let iCloudSync: ICloudSyncMonitor
    /// Items saved by the Share Extension; `nil` in tests (in-memory store, no extension).
    let shareInbox: ShareInbox?

    /// Normal launch: on-disk store in the App Group folder, synced with iCloud (M6).
    /// `-UITests`: in-memory store with `SeedData`. Unit test host: empty in-memory store.
    /// Tests never touch CloudKit.
    static func make() throws -> AppEnvironment {
        if LaunchConfiguration.isUITesting {
            let container = try Persistence.makeInMemoryContainer()
            if !LaunchConfiguration.wantsEmptyStore {
                try SeedData.populate(container.mainContext)
                if let count = LaunchConfiguration.linkRowCount {
                    try SeedData.populateLinkRows(container.mainContext, count: count)
                }
            }
            // Volatile settings: the main currency comes from the test's -AppleLocale.
            return make(container: container, uiState: .inMemory(), settings: .inMemory(), location: nil)
        }
        if LaunchConfiguration.isUnitTestHost {
            // The unit tests build their own containers; the host app only needs to start.
            return make(container: try Persistence.makeInMemoryContainer(), uiState: .inMemory(),
                        settings: .inMemory(), location: nil)
        }

        let location = storeLocationAfterMigration()
        let container = try Persistence.makeContainer(at: location)
        // The main currency is mirrored into the App Group for the Share Extension (SE-18).
        return make(container: container, uiState: LocalUIState(),
                    settings: AppSettings(sharedDefaults: SharedDefaults.appGroup), location: location,
                    shareInbox: ShareInbox(context: container.mainContext))
    }

    /// The store location for this launch, after moving a store left in the app's own
    /// folder by a build without the App Group (`StoreMigrator`). If the move fails, this
    /// launch keeps the old folder so no data is left behind; the next launch tries again.
    private static func storeLocationAfterMigration() -> StoreLocation {
        let location = StoreLocation.current()
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "Persistence")
        do {
            let outcome = try StoreMigrator.moveStoreIfNeeded(
                named: Persistence.storeName, from: URL.applicationSupportDirectory, to: location.directory)
            if case .moved(let names) = outcome {
                logger.notice("Moved the store to the App Group folder: \(names, privacy: .public)")
            }
            return location
        } catch {
            logger.error("Could not move the store to the App Group folder: \(error.localizedDescription, privacy: .public)")
            return StoreLocation(directory: URL.applicationSupportDirectory, usesCloudKit: location.usesCloudKit)
        }
    }

    private static func make(container: ModelContainer, uiState: LocalUIState, settings: AppSettings,
                             location: StoreLocation?, shareInbox: ShareInbox? = nil) -> AppEnvironment {
        let store = PlannerStore(
            context: container.mainContext,
            mainCurrencyCode: { [settings] in settings.mainCurrencyCode }
        )
        // `-UITests` and unit test hosts never fetch from the network (LP-13).
        let linkPreviews = LinkPreviewService(fetcher: LinkFetcherKind.current.makeFetcher(), store: store)
        // `-UITests -UITestsRecordOpenedLinks` records links instead of opening Safari.
        let linkOpener = LinkOpener.forLaunch(arguments: ProcessInfo.processInfo.arguments)
        // Flag off: no store, no `Transaction.updates` listener, no StoreKit call (TJ-02).
        // UI tests get a fresh "has tipped" mark every launch.
        let tipJar = TipJar.forLaunch(
            isEnabled: TipJarConfig.isEnabled(),
            defaults: LaunchConfiguration.isUITesting ? TipJar.volatileDefaults() : .standard,
            makeStore: { TipJarConfig.makeStore() }
        )
        let iCloudSync = ICloudSyncMonitor.forLaunch(location: location)
        iCloudSync.start()
        return AppEnvironment(container: container, store: store, uiState: uiState, settings: settings,
                              linkPreviews: linkPreviews, linkOpener: linkOpener, tipJar: tipJar,
                              iCloudSync: iCloudSync, shareInbox: shareInbox)
    }

    /// Listens for the extension's "saved" signal and picks up what it saved while the app
    /// was not running.
    func startShareInbox() {
        guard shareInbox != nil else { return }
        ShareSignal.observe { [self] in pullSharedItems() }
        pullSharedItems()
    }

    /// Brings the extension's new items into the app and fetches their pictures right away
    /// instead of waiting for their rows to appear (LP-01b).
    func pullSharedItems() {
        guard let shareInbox else { return }
        for id in shareInbox.pull() {
            if let item = store.item(withID: id) {
                linkPreviews.fetchIfNeeded(for: item)
            }
        }
    }
}

private struct StartupErrorView: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your lists", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Something went wrong while opening the app data. Restart the app; if it keeps happening, please contact support.")
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("startup.error")
    }
}
