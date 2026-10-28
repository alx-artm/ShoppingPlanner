//
//  Project__2App.swift
//  Project #2
//
//  Created by Alex on 8.05.25.
//

import SwiftUI
import SwiftData

@main
struct Project2App: App {
    
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ItemModel.self,
            GroupModel.self,
            ListModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
        
    }
}
