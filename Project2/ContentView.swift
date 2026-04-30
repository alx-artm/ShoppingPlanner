//
//  NewView.swift
//  Project #2
//
//  Created by Yelisei Kadol on 14/05/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) var context
    @Query private var lists: [ListModel]
    
    
    var body: some View {
        TabView {
            Tab("Shopping Lists", systemImage: "checkmark.rectangle.stack") {
                HomeTab()
            }
            Tab("Quick List", systemImage: "bolt") {
                QuickListView()
            }
            Tab("Settings", systemImage: "switch.2") {
                SettingsView()
            }
            
        }
        
    }
}


extension UIKeyboardType {
    static let emoji = UIKeyboardType(rawValue: 124)
}


#Preview {
    ContentView()
        .modelContainer(SampleData.shared.modelContainer)
}
