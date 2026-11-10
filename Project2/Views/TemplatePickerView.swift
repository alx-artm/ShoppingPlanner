//
//  TemplatePickerView.swift
//  Project2
//
//  "Start from Template" (spec 03 LI-12): five quick starts. Picking one opens
//  List Info in create mode with the template's name, icon, color and groups.
//

import SwiftUI

struct TemplatePickerView: View {
    let onPick: (ListTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ListTemplate.allCases) { template in
                        Button {
                            onPick(template)
                        } label: {
                            HStack(spacing: 12) {
                                ListIconBadge(iconName: template.iconName, iconKind: .symbol,
                                              color: template.color, diameter: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(template.groupNames.formatted(.list(type: .and, width: .narrow)))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityIdentifier("templates.row.\(template.rawValue)")
                    }
                } footer: {
                    Text("A template fills in the name, icon and empty groups. You can change all of it.")
                }
            }
            .navigationTitle("Start from Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier("templates.cancelButton")
                }
            }
        }
    }
}

#Preview {
    TemplatePickerView { _ in }
}
