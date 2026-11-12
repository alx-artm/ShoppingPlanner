//
//  ContentView.swift
//  Project2
//
//  Root of a window (spec 08): a two-column `NavigationSplitView`.
//  Sidebar = Home (lists), detail = the selected list or a placeholder.
//  On a compact iPhone the split view collapses into a stack by itself
//  (Home → push list); on iPad and the unfolded iPhone Duo both columns show.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(PlannerStore.self) private var store
    @Query private var lists: [ListModel]

    /// One per window, at the root, so the selection survives size-class changes (AD-04).
    @State private var navigation = AppNavigation()
    /// The selection after the system relaunches the app (spec 08 "Structure").
    @SceneStorage("selectedListID") private var storedSelection = ""

    var body: some View {
        NavigationSplitView {
            HomeView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 480)
        } detail: {
            detail
        }
        .environment(navigation)
        .safeAreaInset(edge: .top) {
            if let message = store.lastErrorMessage {
                ErrorBanner(message: message) { store.clearError() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.lastErrorMessage)
        .onAppear {
            navigation.selectedListID = UUID(uuidString: storedSelection)
            navigation.dropSelectionIfMissing(existing: Set(lists.map(\.uuid)))
        }
        .onChange(of: navigation.selectedListID) { _, id in
            storedSelection = id?.uuidString ?? ""
        }
        .onChange(of: lists.map(\.uuid)) { _, ids in
            navigation.dropSelectionIfMissing(existing: Set(ids))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = navigation.selectedListID, let list = lists.first(where: { $0.uuid == id }) {
            ListViewInside(list: list)
                .id(list.uuid)
                // A list deleted while open is deleted only now (DM-18, AD-05).
                .onDisappear { navigation.detailDidClose(using: store) }
        } else {
            ContentUnavailableView {
                Label("Select a List", systemImage: "cart")
            } description: {
                Text("Choose a list to see its groups and items.")
            }
            .accessibilityIdentifier("detail.placeholder")
            .onAppear { navigation.detailDidClose(using: store) }
        }
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

#Preview {
    ContentView()
        .sampleDataEnvironment()
}
