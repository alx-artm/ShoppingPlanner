//
//  GroupHeaderView.swift
//  Project2
//
//  The header of a group on the list screen (spec 04 LD-02, LD-04): the whole
//  header collapses / expands the group; ⋯ has Rename, Add Item, Delete Group.
//  The amount is the group's planned total; a collapsed group shows "(3)".
//
//  M4.6 (LD-30...LD-32, LD-35): the leading chevron sits in the list's icon
//  column (`ListRowGrid`), so it is centered over the checkboxes and the name
//  starts where item names start. At accessibility sizes the header has two
//  lines: [chevron, name without a line limit] / ["(3)", amount … ⋯].
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var menuSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var iconColumn = ListRowGrid.iconColumnWidth

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The menu floats over the button's second line, so the name gets the whole
                // width of the first one (LD-32).
                toggleButton
                    .overlay(alignment: .bottomTrailing) { menu }
            } else {
                HStack(spacing: 4) {
                    toggleButton
                    menu
                }
            }
        }
        .textCase(nil)
    }

    private var isExpanded: Bool { uiState.isExpanded(group.uuid) }
    private var itemCount: Int { group.items?.count ?? 0 }

    private var toggleButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                uiState.setExpanded(!isExpanded, for: group.uuid)
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: ListRowGrid.spacing) {
                        chevron
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            name.lineLimit(2)
                            count
                            Spacer(minLength: 0)
                            amount
                        }
                    }
                }
            }
            // LD-31: ≥ 44 pt at every size.
            .frame(minHeight: menuSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // LD-31: read as "Vacation, 3 items, $145.00", found with the Headings rotor.
        .accessibilityLabel(Text(verbatim: GroupHeaderText.accessibilityLabel(
            name: group.name, itemCount: itemCount, summary: group.summary,
            currencyCode: group.listCurrencyCode, locale: locale)))
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("group.header.\(group.name)")
    }

    /// Two lines at accessibility sizes (LD-32): the name is never cut or squeezed by the
    /// amount and ⋯; the second line leaves room for ⋯ on its trailing edge.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: ListRowGrid.spacing) {
                chevron
                name
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                count
                amount
                Spacer(minLength: 0)
            }
            .padding(.leading, iconColumn + ListRowGrid.spacing)
            .padding(.trailing, menuSize)
            .frame(minHeight: menuSize)
        }
    }

    /// `chevron.right`, turned down when the group is open (UX_REVIEW 14B, variant A), centered
    /// in the icon column like the checkboxes below it (LD-35).
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: iconColumn)
            .accessibilityIdentifier("group.chevron.\(group.name)")
    }

    // Explicit label colors: a List section header would otherwise dim them.
    private var name: some View {
        Text(group.name)
            .font(.headline)
            .foregroundStyle(Color(.label))
            .accessibilityIdentifier("group.name.\(group.name)")
    }

    @ViewBuilder
    private var count: some View {
        if !isExpanded {
            Text(verbatim: "(\(itemCount.formatted(.number.locale(locale))))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("group.count.\(group.name)")
        }
    }

    private var amount: some View {
        Text(verbatim: GroupHeaderText.amount(group.summary, currencyCode: group.listCurrencyCode,
                                              locale: locale))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Color(.secondaryLabel))
            .fixedSize()
            .accessibilityIdentifier("group.total.\(group.name)")
    }

    private var menu: some View {
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
}

/// The list screen's leading grid (LD-35): every row starts with an icon column as wide as
/// the item checkbox (chevron, checkbox, "＋", folder icon centered in it), then the text.
/// Views scale the width with `@ScaledMetric(relativeTo: .title2)`, as the checkbox does.
enum ListRowGrid {
    /// The checkbox's hit area (LD-06) at the default text size.
    static let iconColumnWidth: CGFloat = 44
    /// Between the icon column and the text.
    static let spacing: CGFloat = 4

    // An item row (spec 04 "Row") and its link tile (spec 06 D1-v2 F, LP-15...LP-18).

    /// Above and below the texts of an item row.
    static let rowVerticalPadding: CGFloat = 4
    /// Between the name line and the details line.
    static let detailsSpacing: CGFloat = 2
    /// Side of the tile at the default text size; scaled like the checkbox.
    static let linkTileSide: CGFloat = 44
    /// Side of the tile at accessibility sizes. Fixed: the scaled 44 pt would be about 100 pt.
    static let linkTileAccessibilitySide: CGFloat = 56
    static let linkTileCornerRadius: CGFloat = 10
    /// From the tile to the details and host next to it.
    static let linkTileGap: CGFloat = 8
    /// Added above the tile, so it sits clear of the name line and the checkbox (LP-16).
    static let linkTileTopInset: CGFloat = 4
    /// Between "qty × price" and the host chip next to the tile.
    static let linkDetailsLineSpacing: CGFloat = 4
}
