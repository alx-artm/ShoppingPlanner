//
//  ListSummaryBar.swift
//  Project2
//
//  The totals of the list, pinned above the bottom edge (spec 04 LD-10,
//  LD-11, LD-11a): "To buy €788.79 of €909.79", progress, "+N without price"
//  and the budget line (same texts as Home). While the keyboard is open it
//  shrinks to one line "To buy €788.79 · 13%" (owner decision 2026-11-13).
//  Line 2 is the segmented purchase bar (LD-20...LD-29, `PurchaseBarView`);
//  Home tiles keep the simple bar.
//

import SwiftData
import SwiftUI

struct ListSummaryBar: View {
    let list: ListModel
    /// One line, while the keyboard is open.
    var isCompact = false
    /// A tap on a purchase bar segment: show the item in the list (LD-27).
    var onShowItem: (PersistentIdentifier) -> Void = { _ in }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let summary = list.summary
        let text = ListSummaryText(summary, currencyCode: list.currencyCode, locale: locale)
        if text.isVisible {
            Group {
                if isCompact {
                    Text(verbatim: text.compact)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("listDetail.summary.compact")
                } else {
                    full(text, summary: summary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isCompact ? 8 : 12)
            .frame(maxWidth: 600)
            .glassEffect(.regular, in: .rect(cornerRadius: isCompact ? 20 : 24))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("listDetail.summary")
        }
    }

    private func full(_ text: ListSummaryText, summary: BudgetSummary) -> some View {
        // No spacing: the bar's row is 44 pt high (its tap area, LD-27), which already
        // leaves room above and below the texts.
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    toBuy(text)
                    Spacer(minLength: 8)
                    ofPlanned(text)
                }
                VStack(alignment: .leading, spacing: 2) {
                    toBuy(text)
                    ofPlanned(text)
                }
            }

            Group {
                if text.showsProgress, dynamicTypeSize.isAccessibilitySize {
                    // Accessibility sizes: the labels would squeeze the bar to nothing in one
                    // row, so the bar gets the full width and the labels go below it.
                    VStack(alignment: .leading, spacing: 0) {
                        PurchaseBarView(list: list, summary: summary, onShowItem: onShowItem)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            progress(text)
                            unpriced(text)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        if text.showsProgress {
                            PurchaseBarView(list: list, summary: summary, onShowItem: onShowItem)
                            progress(text)
                                .fixedSize()
                        }
                        unpriced(text)
                            .fixedSize()
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, text.showsProgress ? 0 : 6)

            BudgetText(status: text.status, form: .full)
                .font(.subheadline)
                .accessibilityIdentifier("listDetail.budget")
        }
    }

    private func progress(_ text: ListSummaryText) -> some View {
        Text(verbatim: text.progress)
            .monospacedDigit()
            .accessibilityIdentifier("listDetail.progress")
    }

    /// "+2 without price", or alone "3 items without price" without a bar (LD-24, LD-25).
    @ViewBuilder
    private func unpriced(_ text: ListSummaryText) -> some View {
        if let unpriced = text.unpriced {
            Text(verbatim: unpriced)
                .accessibilityIdentifier("listDetail.unpriced")
        }
    }

    private func toBuy(_ text: ListSummaryText) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("To buy")
                .foregroundStyle(.secondary)
            Text(verbatim: text.toBuy)
                .font(.title3.bold())
                .monospacedDigit()
                .accessibilityIdentifier("listDetail.total")
        }
    }

    @ViewBuilder
    private func ofPlanned(_ text: ListSummaryText) -> some View {
        if let ofPlanned = text.ofPlanned {
            Text(verbatim: ofPlanned)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("listDetail.planned")
        }
    }
}
