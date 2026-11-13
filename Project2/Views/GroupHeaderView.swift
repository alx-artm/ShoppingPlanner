//
//  GroupHeaderView.swift
//  Project2
//
//  The header of a group on the list screen (spec 04 LD-02, LD-04): the whole
//  header collapses / expands the group; ⋯ has Rename, Add Item, Delete Group.
//  The amount is the group's planned total; a collapsed group shows "(3)".
//

import SwiftUI

struct GroupHeaderView: View {
    let group: GroupModel
    let onRename: () -> Void
    let onAddItem: () -> Void
    let onDelete: () -> Void

    @Environment(LocalUIState.self) private var uiState
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var menuSize: CGFloat = 44

    var body: some View {
        let isExpanded = uiState.isExpanded(group.uuid)
        let itemCount = group.items?.count ?? 0

        HStack(spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    uiState.setExpanded(!isExpanded, for: group.uuid)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    // Explicit label colors: a List section header would otherwise dim them.
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                    if !isExpanded {
                        Text(verbatim: "(\(itemCount.formatted(.number.locale(locale))))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("group.count.\(group.name)")
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: GroupHeaderText.amount(group.summary, currencyCode: group.listCurrencyCode,
                                                          locale: locale))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize()
                        .accessibilityIdentifier("group.total.\(group.name)")
                }
                .frame(minHeight: menuSize)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("group.header.\(group.name)")

            Menu {
                Button("Rename", systemImage: "pencil", action: onRename)
                    .accessibilityIdentifier("group.menu.rename")
                Button("Add Item", systemImage: "plus", action: onAddItem)
                    .accessibilityIdentifier("group.menu.addItem")
                Divider()
                Button("Delete Group", systemImage: "trash", role: .destructive, action: onDelete)
                    .accessibilityIdentifier("group.menu.delete")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: menuSize, height: menuSize)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Group Actions"))
            .accessibilityIdentifier("group.menu.\(group.name)")
        }
        .textCase(nil)
    }
}
