//
//  ItemRowView.swift
//  Project2
//
//  A row of the list screen (spec 04 "Row", UX_REVIEW §6): checkbox · name ·
//  line total, and a secondary line "qty × unit price · note · 🔗 host".
//  The checkbox toggles "bought"; the rest of the row opens item details.
//  Texts come from `ItemRowText`.
//
//  An item with a link also gets the link tile (spec 06 D1 variant A, D1-v2 addendum F):
//  under the name, at the start of the details line, with "qty × price" and the host chip
//  in two lines next to it, at every text size. So every name starts right after the
//  checkbox, and names, amounts and separators line up with rows without a link (LP-15).
//  The row's button keeps an empty slot of the tile's size and the tile is laid over that
//  slot, outside the button: a tap on the tile opens the page, not the details, and the
//  row is as high with or without the picture (LP-17).
//
//  A must-have (spec 11) gets an orange ★ as the first glyph of the name, inside the same
//  `Text`: it wraps with the name and never moves the checkbox, the tile or the amounts.
//

import SwiftUI

struct ItemRowView: View {
    let item: ItemModel
    /// Opens item details (spec 05).
    let onOpen: () -> Void

    @Environment(PlannerStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.linkOpener) private var linkOpener
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .title2) private var checkboxSize = ListRowGrid.iconColumnWidth
    /// Scaled like the checkbox (LD-35); used below the accessibility sizes.
    @ScaledMetric(relativeTo: .title2) private var scaledTileSide = ListRowGrid.linkTileSide

    /// The item's link when it is a web link: only then the row has a tile (LP-15).
    private var linkURL: URL? { ItemLink.url(from: item.urlString) }

    /// The scaled 44 pt would be about 100 pt at accessibility sizes: fixed 56 pt there.
    private var tileSide: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? ListRowGrid.linkTileAccessibilitySide : scaledTileSide
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ListRowGrid.spacing) {
            checkbox
            Button(action: onOpen) {
                content
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // LD-07e / MH-14: "Must-have" and "Bought" are read on the row; the star and the
            // strike aren't. Nothing extra for a plain row still to buy.
            .accessibilityValue(Text(verbatim: ItemRowText.accessibilityValue(
                isComplete: item.isComplete, isMustHave: item.isMustHave, locale: locale)))
            // LP-18: the tile is no VoiceOver stop; its action lives on the row.
            .accessibilityActions {
                if linkURL != nil {
                    Button("Open Link", action: openLinkInApp)
                }
            }
            .accessibilityIdentifier("item.row.\(item.name)")
        }
        .overlayPreferenceValue(LinkTileSlot.self) { slot in
            if let slot {
                GeometryReader { proxy in
                    let frame = proxy[slot]
                    LinkThumbnailTile(item: item, side: tileSide, action: openLinkInApp)
                        // LD-07: a bought row is dimmed, its picture too (LP-17).
                        .opacity(item.isComplete ? 0.5 : 1)
                        .grayscale(item.isComplete ? 1 : 0)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }

    /// The tile and the row's "Open Link" action: the page in the app (D4).
    private func openLinkInApp() {
        if let linkURL { linkOpener.open(linkURL, .inApp, using: openURL) }
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
                // Gray ring, not `.secondary`: inside a tinted Button that is a faded tint
                // (~2.1:1 against the background); the ring needs ≥ 3:1 (BUG-29, LD-07a).
                .foregroundStyle(item.isComplete ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondaryLabel)))
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
        return VStack(alignment: .leading, spacing: ListRowGrid.detailsSpacing) {
            // M7.5: at accessibility sizes the amount goes under the name, as in the group
            // header (LD-32), so the name gets the whole width instead of hyphenating.
            nameAndAmountLayout {
                name(style)
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
            if linkURL != nil {
                // D1-v2 F: the tile, and the details and the host under each other next to it.
                HStack(alignment: .top, spacing: ListRowGrid.linkTileGap) {
                    tileSlot
                    secondLine
                }
                .padding(.top, ListRowGrid.linkTileTopInset)
            } else {
                secondLine
            }
        }
        .foregroundStyle(style.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.vertical, ListRowGrid.rowVerticalPadding)
    }

    /// Name and amount side by side; under each other at accessibility sizes.
    private var nameAndAmountLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ListRowGrid.detailsSpacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    /// The name, with "★ " in front for a must-have (MH-07). The star is orange, or secondary
    /// with the rest of a bought row, and never struck through (MH-08).
    @ViewBuilder
    private func name(_ style: ItemRowStyle) -> some View {
        let name = Text(item.name).strikethrough(style.nameStrikethrough)
        if item.isMustHave {
            let star = Text(Image(systemName: "star.fill"))
                .font(.footnote)
                .foregroundStyle(style.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            Text("\(star) \(name)")
                .accessibilityLabel(Text(item.name))
                // The marker is inside the name, so the name carries its id (MH-03).
                .accessibilityIdentifier("item.mustHave.\(item.name)")
        } else {
            name
        }
    }

    /// The empty place of the tile in the row's button; the tile is drawn over it.
    private var tileSlot: some View {
        Color.clear
            .frame(width: tileSide, height: tileSide)
            .anchorPreference(key: LinkTileSlot.self, value: .bounds) { $0 }
            .accessibilityHidden(true)
    }

    /// "qty × unit price · note", and under it the host chip when the item has a link: two
    /// lines next to the tile, so neither is truncated by the other.
    @ViewBuilder
    private var secondLine: some View {
        let detail = ItemRowText.detail(quantity: item.quantity, price: item.price,
                                        currencyCode: item.listCurrencyCode, notes: item.notes, locale: locale)
        let host = ItemLink.displayHost(of: item.urlString)
        if detail != nil || host != nil {
            VStack(alignment: .leading, spacing: ListRowGrid.linkDetailsLineSpacing) {
                if let detail {
                    Text(verbatim: detail)
                        .lineLimit(1)
                        .accessibilityIdentifier("item.detail.\(item.name)")
                }
                if let host {
                    // LP-08: the link chip; the tile, the context menu and item details open it.
                    Label(host, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .accessibilityIdentifier("item.link.\(item.name)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// Where the row's button keeps the place of the link tile.
private struct LinkTileSlot: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
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
