//
//  ListTileView.swift
//  Project2
//
//  A pinned list on Home (spec 02 "Tile", UX_REVIEW §13B), Reminders-style.
//  Always four lines, so tiles of one row have the same height (HM-28):
//  icon circle and the "to buy" number / name / budget / progress bar and percent
//  (or "Empty" / "3 items" without prices). Texts come from `ListStatusText`.
//
//  Only system colors: the tile background is `secondarySystemGroupedBackground`
//  and the list color appears just in the icon circle and the progress tint,
//  so the tile is correct in light and dark mode (BUG-09, HM-17). Red is used
//  only for an over-budget plan, together with ⚠ and words (HM-22).
//

import SwiftUI

struct ListTileView: View {
    let list: ListModel
    /// Highlighted while the list is open in the detail column.
    var isSelected = false

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title2) private var badgeDiameter: CGFloat = 36
    /// Keeps the bottom line the same height for a progress bar or a caption.
    @ScaledMetric(relativeTo: .caption) private var footerHeight: CGFloat = 16

    var body: some View {
        let status = ListStatusText(list.summary, currencyCode: list.currencyCode, locale: locale)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ListIconBadge(list: list, diameter: badgeDiameter)
                Spacer(minLength: 0)
                ToBuyText(status: status)
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

            // A one-line name leaves the space above the budget, so the budget
            // and the bar line up across a row of tiles.
            Spacer(minLength: 0)

            BudgetText(status: status, form: .short)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("home.listCard.budget.\(list.name)")

            footer(status)
                .frame(minHeight: footerHeight)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(.rect(cornerRadius: 16))
    }

    /// Bar + percent bought (HM-19), or "Empty" / "3 items" without prices (HM-06).
    @ViewBuilder
    private func footer(_ status: ListStatusText) -> some View {
        if let percent = status.percentText {
            HStack(spacing: 6) {
                ProgressView(value: status.barFraction)
                    .tint(list.color.color)
                Text(verbatim: percent)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("home.listCard.percent.\(list.name)")
            }
        } else {
            Text(verbatim: status.progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The budget part of the status: secondary, or red with ⚠ when the plan is over budget (HM-22).
struct BudgetText: View {
    enum Form { case short, full }

    let status: ListStatusText
    let form: Form

    /// A `Text`, so the row can embed it in one wrapping line with the progress part.
    var text: Text {
        let words = form == .short ? status.budgetShort : status.budgetFull
        if status.isOverBudget {
            return Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(words)")
                .foregroundStyle(.red)
        }
        return Text(verbatim: words)
    }

    var body: some View {
        text.foregroundStyle(.secondary)
    }
}

#Preview {
    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
            ListTileView(list: SampleData.shared.alexList, isSelected: true)
            ListTileView(list: SampleData.shared.victoriaList)
        }
        GridRow {
            ListTileView(list: SampleData.shared.evaList)
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .sampleDataEnvironment()
}
