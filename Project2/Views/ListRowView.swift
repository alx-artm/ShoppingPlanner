//
//  ListRowView.swift
//  Project2
//
//  A row of Home's "All Lists" section (spec 02 "Row"). Also used for pinned
//  lists at accessibility text sizes and in Edit mode, where tiles become rows.
//  Name and "to buy" on the first line, progress and budget on their own lines
//  under it (HM-30); the texts come from `ListStatusText`.
//

import SwiftUI

struct ListRowView: View {
    let list: ListModel

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var badgeDiameter: CGFloat = 32

    var body: some View {
        let status = ListStatusText(list.summary, currencyCode: list.currencyCode, locale: locale)

        if dynamicTypeSize.isAccessibilitySize {
            // Large text: stack everything, so the name and the amount never share a line.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ListIconBadge(list: list, diameter: badgeDiameter)
                    name
                }
                amount(status)
                statusLine(status)
            }
            .padding(.vertical, 4)
        } else {
            // The amount shares the name's line, so the status lines get the full width.
            HStack(spacing: 12) {
                ListIconBadge(list: list, diameter: badgeDiameter)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        name
                        Spacer(minLength: 8)
                        amount(status)
                    }
                    statusLine(status)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var name: some View {
        Text(list.name)
            .lineLimit(2)
    }

    /// "To buy" of the list, or "—" without prices (HM-05, HM-06).
    private func amount(_ status: ListStatusText) -> some View {
        ToBuyText(status: status)
            .accessibilityIdentifier("home.listRow.toBuy.\(list.name)")
    }

    /// Progress and budget on their own lines, so every row has the same height and a
    /// budget phrase never breaks mid-way: "13% bought" / "$160.00 to spare of $500.00",
    /// "0% bought" / "⚠ plan €15.00 over budget". Only the budget part turns red (HM-22).
    private func statusLine(_ status: ListStatusText) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: status.progressText)
            BudgetText(status: status, form: .full).text
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        // Standard sizes: one line each; narrow rows (Edit mode handles, small iPhones) shrink a
        // little first. Accessibility sizes: the lines wrap, so nothing is cut off (HM-25).
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.listRow.status.\(list.name)")
    }
}

/// The "to buy" amount of a list; "—" when no item has a price (HM-06),
/// secondary when everything is bought (S6, HM-24).
struct ToBuyText: View {
    let status: ListStatusText

    var body: some View {
        if status.hasPrices {
            Text(verbatim: status.amount)
                .monospacedDigit()
                .foregroundStyle(status.isAllBought ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        } else {
            Text(verbatim: status.amount)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("No prices yet"))
        }
    }
}

#Preview {
    List {
        ListRowView(list: SampleData.shared.evaList)
        ListRowView(list: SampleData.shared.victoriaList)
        ListRowView(list: SampleData.shared.alexList)
    }
    .sampleDataEnvironment()
}
