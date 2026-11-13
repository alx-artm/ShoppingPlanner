//
//  ItemRowView.swift
//  Project2
//
//  A row of the list screen (spec 04 "Row", UX_REVIEW §6): checkbox · name ·
//  line total, and a secondary line "qty × unit price · note · 🔗 host".
//  The checkbox toggles "bought"; the rest of the row opens item details.
//  Texts come from `ItemRowText`.
//

import SwiftUI

struct ItemRowView: View {
    let item: ItemModel
    /// Opens item details (spec 05).
    let onOpen: () -> Void

    @Environment(PlannerStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var checkboxSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            checkbox
            Button(action: onOpen) {
                content
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // LD-07e: "Bought" is read on the row too, not only on the checkbox; the strike
            // isn't read by VoiceOver. Nothing extra for a row still to buy.
            .accessibilityValue(item.isComplete ? Text("Bought") : Text(verbatim: ""))
            .accessibilityIdentifier("item.row.\(item.name)")
        }
    }

    /// ≥ 44×44 pt hit area (LD-06, BUG-20).
    private var checkbox: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                // Also sets / clears completedAt (DM-16).
                store.toggleComplete(item)
            }
        } label: {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(item.isComplete ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: checkboxSize, height: checkboxSize)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        // Keeps the checkbox on the first line when the name wraps.
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
        .sensoryFeedback(trigger: item.isComplete) { _, isComplete in
            isComplete ? .success : .selection
        }
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(item.isComplete ? Text("Bought") : Text("Not bought"))
        .accessibilityAddTraits(item.isComplete ? .isSelected : [])
        .accessibilityIdentifier("item.checkbox.\(item.name)")
    }

    private var content: some View {
        let style = ItemRowStyle(isComplete: item.isComplete)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .strikethrough(style.nameStrikethrough)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: ItemRowText.total(item.lineTotal, currencyCode: item.listCurrencyCode, locale: locale))
                    .monospacedDigit()
                    .strikethrough(style.amountStrikethrough)
                    // The name wraps instead of the amount being cut ("$3…").
                    .fixedSize()
                    .accessibilityLabel(item.lineTotal == nil ? Text("No price") : Text(verbatim: ItemRowText.total(
                        item.lineTotal, currencyCode: item.listCurrencyCode, locale: locale)))
                    .accessibilityIdentifier("item.total.\(item.name)")
            }
            secondLine
        }
        .foregroundStyle(style.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var secondLine: some View {
        let detail = ItemRowText.detail(quantity: item.quantity, price: item.price,
                                        currencyCode: item.listCurrencyCode, notes: item.notes, locale: locale)
        let host = ItemLink.displayHost(of: item.urlString)
        if detail != nil || host != nil {
            HStack(spacing: 6) {
                if let detail {
                    Text(verbatim: detail)
                        .lineLimit(1)
                        .accessibilityIdentifier("item.detail.\(item.name)")
                }
                if let host {
                    // LP-08: the link chip; "Open Link" is in the context menu and item details.
                    Label(host, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .layoutPriority(-1)
                        .accessibilityIdentifier("item.link.\(item.name)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    List {
        ForEach(SampleData.shared.alexList.sortedGroups[1].sortedItems) { item in
            ItemRowView(item: item, onOpen: {})
        }
    }
    .listStyle(.plain)
    .sampleDataEnvironment()
}
