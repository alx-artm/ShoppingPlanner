//
//  ListTileView.swift
//  Project2
//
//  A pinned list on Home (spec 02 "Tile", UX_REVIEW §13B), Reminders-style:
//  icon circle and the "to buy" number on top, the name below, then a thin
//  progress bar or an "Over budget" badge.
//
//  Only system colors: the tile background is `secondarySystemGroupedBackground`
//  and the list color appears just in the icon circle and the progress tint,
//  so the tile is correct in light and dark mode (BUG-09, HM-17).
//

import SwiftUI

struct ListTileView: View {
    let list: ListModel
    /// Highlighted while the list is open in the detail column.
    var isSelected = false

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title2) private var badgeDiameter: CGFloat = 36
    /// Keeps the bottom line the same height for a progress bar, a badge or a caption.
    @ScaledMetric(relativeTo: .caption) private var footerHeight: CGFloat = 16

    var body: some View {
        let summary = list.summary

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ListIconBadge(list: list, diameter: badgeDiameter)
                Spacer(minLength: 0)
                ToBuyText(summary: summary, currencyCode: list.currencyCode)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("home.listCard.toBuy.\(list.name)")
            }

            Text(list.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            footer(summary)
                .frame(minHeight: footerHeight)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func footer(_ summary: BudgetSummary) -> some View {
        if summary.isOverBudget {
            // Said in words, not only by color (HM-07).
            Label("Over budget", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
        } else if ListStatusText.hasPrices(summary) {
            ProgressView(value: summary.boughtFraction.doubleValue)
                .tint(list.color.color)
        } else {
            Text(ListStatusText.subtitle(summary, currencyCode: list.currencyCode, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        ListTileView(list: SampleData.shared.alexList, isSelected: true)
        ListTileView(list: SampleData.shared.victoriaList)
        ListTileView(list: SampleData.shared.evaList)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .sampleDataEnvironment()
}
