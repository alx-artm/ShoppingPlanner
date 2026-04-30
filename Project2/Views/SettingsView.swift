//
//  SettingsView.swift
//  Project2
//
//  Created by Alex on 1.09.25.
//

import SwiftUI

struct SettingsView: View {
    
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    
    var body: some View {
        
        NavigationStack {
            Form {
                Section(header: Text("Theme")) {
                    Picker("", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline) // красивый стиль списка
                }
            }
            .navigationTitle("Settings")
        }
        
        
    }
}

#Preview {
    SettingsView()
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "Match device"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
