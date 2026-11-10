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
                case .failure(let error):
                    StartupErrorView(error: error)
                }
            }
            .preferredColorScheme(selectedTheme.colorScheme)
        }
    }
}

/// Everything the views need from the data layer.
@MainActor
struct AppEnvironment {
    let container: ModelContainer
    let store: PlannerStore
    let uiState: LocalUIState
    let settings: AppSettings

    /// Normal launch: on-disk store. `-UITests`: in-memory store with `SeedData`.
    static func make() throws -> AppEnvironment {
        if LaunchConfiguration.isUITesting {
            let container = try Persistence.makeContainer(inMemory: true)
            if !LaunchConfiguration.wantsEmptyStore {
                try SeedData.populate(container.mainContext)
            }
            // Volatile settings: the main currency comes from the test's -AppleLocale.
            return make(container: container, uiState: .inMemory(), settings: .inMemory())
        }

        let container = try Persistence.makeContainer(inMemory: false)
        return make(container: container, uiState: LocalUIState(), settings: AppSettings())
    }

    private static func make(container: ModelContainer, uiState: LocalUIState, settings: AppSettings) -> AppEnvironment {
        let store = PlannerStore(
            context: container.mainContext,
            mainCurrencyCode: { [settings] in settings.mainCurrencyCode }
        )
        return AppEnvironment(container: container, store: store, uiState: uiState, settings: settings)
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
