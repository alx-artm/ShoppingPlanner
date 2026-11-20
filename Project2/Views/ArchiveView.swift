//
//  ArchiveView.swift
//  Project2
//
//  The Archive screen (spec 10, AR-14…AR-21): archived lists, the last archived
//  first, with Home's rows and search. It is pushed in Home's column (iPhone:
//  over Home; iPad: inside the sidebar), and a tapped list opens like on Home
//  (iPhone: push; iPad: the detail column). No Pin, no List Info, no reorder.
//

import SwiftData
import SwiftUI

struct ArchiveView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    @Query(filter: #Predicate<ListModel> { $0.archivedAt != nil }) private var archived: [ListModel]

    @State private var query = ""
    @State private var listToDelete: ListModel?

    var body: some View {
        let lists = HomeSections.archived(archived, query: query)

        // No `selection:` here: Home's list in this column already drives the selection
        // (see ArchivedListRow).
        List {
            ForEach(lists) { list in
                ArchivedListRow(list: list) { listToDelete = list }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("archive.list")
        .overlay {
            if archived.isEmpty {
                // AR-21: the last list left while the screen is open; it stays open.
                emptyState
            } else if lists.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Archive")
        .searchable(text: $query, prompt: Text("Search Archive"))
        .deleteListConfirmation($listToDelete, identifierPrefix: "archive") { list in
            // Closes the detail first if this list is open there (DM-18).
            navigation.requestDeletion(of: list, using: store)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Archived Lists", systemImage: "archivebox")
        } description: {
            Text("Archived lists keep all their items and prices.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive.emptyState")
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
    }
    .sampleDataEnvironment()
}
