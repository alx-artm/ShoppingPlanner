//
//  ListRowView.swift
//  Project2
//
//  A row of Home's "All Lists" section (spec 02 "Row"). Also used for pinned
//  lists at accessibility text sizes and in Edit mode, where tiles become rows.
//

import SwiftUI

struct ListRowView: View {
    let list: ListModel

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var badgeDiameter: CGFloat = 32

    var body: some View {
        let summary = list.summary

        if dynamicTypeSize.isAccessibilitySize {
            // Large text: stack everything, so the name and the amount never share a line.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ListIconBadge(list: list, diameter: badgeDiameter)
                    name
                }
                amount(summary)
                status(summary)
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                ListIconBadge(list: list, diameter: badgeDiameter)
                VStack(alignment: .leading, spacing: 2) {
                    name
                    status(summary)
                }
                Spacer(minLength: 8)
                amount(summary)
            }
            .padding(.vertical, 2)
        }
    }

    private var name: some View {
        Text(list.name)
            .lineLimit(2)
    }

    /// "To buy" of the list, or "—" without prices (HM-05, HM-06).
    private func amount(_ summary: BudgetSummary) -> some View {
        ToBuyText(summary: summary, currencyCode: list.currencyCode)
            .accessibilityIdentifier("home.listRow.toBuy.\(list.name)")
    }

    /// "8% bought", "$130.00 left of $500.00", "Over budget by €15.00", "Empty", "3 items".
    private func status(_ summary: BudgetSummary) -> some View {
        HStack(spacing: 4) {
            if summary.isOverBudget {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
            }
            Text(ListStatusText.subtitle(summary, currencyCode: list.currencyCode, locale: locale))
        }
        .font(.subheadline)
        .foregroundStyle(summary.isOverBudget ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }
}

/// The "to buy" amount of a list; "—" when no item has a price (HM-06).
struct ToBuyText: View {
    let summary: BudgetSummary
    let currencyCode: String

    var body: some View {
        if ListStatusText.hasPrices(summary) {
            MoneyText(summary.toBuy, currencyCode: currencyCode)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("No prices yet"))
        }
    }
}

#Preview {
    List {
        ListRowView(list: SampleData.shared.evaList)
        ListRowView(list: SampleData.shared.victoriaList)
    }
    .sampleDataEnvironment()
}
