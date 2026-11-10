//
//  ListRowView.swift
//  Project2
//
//  A row of Home's "All Lists" section (spec 02 "Row"). Also used for pinned
//  lists at accessibility text sizes and in Edit mode, where tiles become rows.
//  Name with the status "progress · budget" under it, "to buy" on the right
//  (HM-30); the texts come from `ListStatusText`.
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
            HStack(spacing: 12) {
                ListIconBadge(list: list, diameter: badgeDiameter)
                VStack(alignment: .leading, spacing: 2) {
                    name
                    statusLine(status)
                }
                Spacer(minLength: 8)
                amount(status)
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

    /// "13% bought · $160.00 to spare of $500.00", "0% bought · ⚠ plan €15.00 over budget",
    /// "3 items · budget €500.00". Only the budget part turns red (HM-22); up to 2 lines (HM-25).
    private func statusLine(_ status: ListStatusText) -> some View {
        let budget = BudgetText(status: status, form: .full)
        return Text("\(status.progressText) · \(budget.text)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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
