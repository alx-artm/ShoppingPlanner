//
//  NewView.swift
//  Project #2
//
//  Created by Yelisei Kadol on 14/05/2025.
//

import SwiftUI

struct ContentView: View {
    @Environment(PlannerStore.self) private var store

    var body: some View {
        TabView {
            Tab("Shopping Lists", systemImage: "checkmark.rectangle.stack") {
                HomeTab()
            }
            Tab("Settings", systemImage: "switch.2") {
                SettingsView()
            }
        }
        .safeAreaInset(edge: .top) {
            if let message = store.lastErrorMessage {
                ErrorBanner(message: message) { store.clearError() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.lastErrorMessage)
    }
}

/// Non-blocking message for a failed save (DM-17).
private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("errorBanner.dismissButton")
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("errorBanner")
    }
}

extension UIKeyboardType {
    static let emoji = UIKeyboardType(rawValue: 124)
}

#Preview {
    ContentView()
        .sampleDataEnvironment()
}
