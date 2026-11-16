//
//  ReorderGroupsView.swift
//  Project2
//
//  "Reorder Groups" (spec 04 LD-03, owner decision 2026-11-13): sections of the
//  list screen can't be dragged, so the groups are reordered here with drag
//  handles, like folders in Reminders. Each move is saved at once (DM-07).
//

import SwiftUI

struct ReorderGroupsView: View {
    let list: ListModel

    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = list.sortedGroups
        NavigationStack {
            List {
                ForEach(groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(verbatim: "\((group.items ?? []).count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reorderGroups.row.\(group.name)")
                }
                .onMove { source, destination in
                    store.moveGroup(in: list, fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .accessibilityIdentifier("reorderGroups.list")
            .navigationTitle("Reorder Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                    .accessibilityIdentifier("reorderGroups.doneButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationSizing(.form)
    }
}

#Preview {
    ReorderGroupsView(list: SampleData.shared.alexList)
        .sampleDataEnvironment()
}
