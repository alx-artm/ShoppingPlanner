//
//  PurchaseBarView.swift
//  Project2
//
//  The segmented purchase bar in the list summary bar (spec 04 "Purchase bar",
//  LD-20...LD-29): one segment per priced item, width ∝ its line total; bought
//  segments filled on the left, the rest outlined on the right, dashed squares
//  for items without a price. The geometry comes from `PurchaseBarLayout`, the
//  texts from `PurchaseBarText`, the colors from `PurchaseBarColors`.
//
//  - Checking an item off moves its segment to the bought side (≤ 0.35 s);
//    with Reduce Motion the bar crossfades instead of moving (LD-26).
//  - A tap on a segment shows its item in the list; "other" opens a popover
//    with the merged items (LD-27). The whole 44 pt row is the tap area.
//  - VoiceOver: one adjustable element; swipe up / down goes through the
//    items, "Show item" shows the picked one (LD-28).
//

import SwiftData
import SwiftUI

struct PurchaseBarView: View {
    let list: ListModel
    let summary: BudgetSummary
    /// Scrolls the list to the item and highlights its row (LD-27).
    let onShowItem: (PersistentIdentifier) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Twice the bar height (UX_REVIEW 14D-5): a narrower rounded segment reads as a "0", and two
    /// of them as "00". Narrower items merge into "other" or are widened (LD-23).
    @ScaledMetric(relativeTo: .subheadline) private var minSegmentWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var barHeight: CGFloat = 10

    @State private var width: CGFloat = 0
    @State private var otherPopover: OtherPopover?
    /// The item VoiceOver picked with swipe up / down; `nil` = the summary (LD-28).
    @State private var voiceOverIndex: Int?

    /// The tap area of every segment is the whole row, at least 44 pt high (LD-27).
    private static let rowHeight: CGFloat = 44
    /// Drawn space between two segments (not part of the layout: the widths stay exact).
    private static let gap: CGFloat = 1.5

    var body: some View {
        let items = list.sortedGroups.flatMap(\.sortedItems)
        let layout = PurchaseBarLayout(
            items: items.map { .init(id: $0.persistentModelID, lineTotal: $0.lineTotal, isComplete: $0.isComplete) },
            width: width,
            metrics: .init(minSegmentWidth: minSegmentWidth, squareSize: barHeight, squareSpacing: Self.gap)
        )
        let itemsByID = Dictionary(items.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        let voiceOverOrder = layout.itemIDsInBarOrder

        Color.clear
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .leading) { animatedBar(layout) }
            .contentShape(.rect)
            .onTapGesture { location in tap(at: location.x, in: layout) }
            .popover(item: $otherPopover,
                     attachmentAnchor: .rect(.rect(otherPopover?.rect ?? .zero)),
                     arrowEdge: .bottom) { popover in
                otherList(layout.segments.first { $0.kind == .other(isBought: popover.isBought) },
                          itemsByID: itemsByID)
            }
            // LD-28: one element; the labels next to it and the squares are not part of it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: PurchaseBarText.label))
            .accessibilityValue(Text(verbatim: voiceOverValue(order: voiceOverOrder, itemsByID: itemsByID)))
            .accessibilityAdjustableAction { direction in
                adjust(direction, count: voiceOverOrder.count)
            }
            .accessibilityActions {
                if let id = pickedID(in: voiceOverOrder) {
                    Button("Show item") { onShowItem(id) }
                }
            }
            .accessibilityIdentifier("listDetail.purchaseBar")
    }

    // MARK: - Drawing

    /// LD-26: segments keep their identity (the item), so a checked-off one slides to the
    /// bought side. With Reduce Motion the whole bar is replaced with a crossfade.
    @ViewBuilder
    private func animatedBar(_ layout: PurchaseBarLayout<PersistentIdentifier>) -> some View {
        ZStack(alignment: .leading) {
            if reduceMotion {
                bar(layout)
                    .id(layout)
                    .transition(.opacity)
            } else {
                bar(layout)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: layout)
    }

    private func bar(_ layout: PurchaseBarLayout<PersistentIdentifier>) -> some View {
        let color = PurchaseBarColors.segment(list.color)
        return ZStack(alignment: .leading) {
            ForEach(layout.segments) { segment in
                let drawn = max(segment.width - Self.gap, min(segment.width, 1))
                SegmentShape(isBought: segment.isBought, color: color)
                    .frame(width: drawn, height: barHeight)
                    .offset(x: segment.x + (segment.width - drawn) / 2)
            }
            ForEach(Array(layout.squareXs.enumerated()), id: \.offset) { _, x in
                UnpricedSquare()
                    .frame(width: layout.squareSize, height: layout.squareSize)
                    .offset(x: x)
            }
        }
        .frame(width: layout.width, height: barHeight, alignment: .leading)
    }

    // MARK: - Tap (LD-27)

    private func tap(at x: CGFloat, in layout: PurchaseBarLayout<PersistentIdentifier>) {
        guard let index = layout.segmentIndex(at: x) else { return }
        let segment = layout.segments[index]
        if segment.isOther {
            otherPopover = OtherPopover(
                isBought: segment.isBought,
                rect: CGRect(x: segment.x, y: (Self.rowHeight - barHeight) / 2,
                             width: segment.width, height: barHeight)
            )
        } else if let id = segment.itemIDs.first {
            onShowItem(id)
        }
    }

    /// The items merged into "other", with their amounts.
    private func otherList(_ segment: PurchaseBarLayout<PersistentIdentifier>.Segment?,
                           itemsByID: [PersistentIdentifier: ItemModel]) -> some View {
        let items = (segment?.itemIDs ?? []).compactMap { itemsByID[$0] }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Other items")
                        .font(.headline)
                    (segment?.isBought == true ? Text("Bought") : Text("To buy"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: ItemRowText.total(item.lineTotal, currencyCode: list.currencyCode,
                                                         locale: locale))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("purchaseBar.other.\(item.name)")
                }
            }
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 280, maxHeight: 400)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("purchaseBar.otherPopover")
    }

    // MARK: - VoiceOver (LD-28)

    private func pickedID(in order: [PersistentIdentifier]) -> PersistentIdentifier? {
        guard let index = voiceOverIndex, order.indices.contains(index) else { return nil }
        return order[index]
    }

    private func voiceOverValue(order: [PersistentIdentifier],
                                itemsByID: [PersistentIdentifier: ItemModel]) -> String {
        if let id = pickedID(in: order), let item = itemsByID[id], let total = item.lineTotal {
            return PurchaseBarText.item(name: item.name, lineTotal: total, isComplete: item.isComplete,
                                        currencyCode: list.currencyCode, locale: locale)
        }
        return PurchaseBarText.summary(summary, currencyCode: list.currencyCode, locale: locale)
    }

    /// Up: the next item, left to right. Down: the previous one, and from the first back to the summary.
    private func adjust(_ direction: AccessibilityAdjustmentDirection, count: Int) {
        guard count > 0 else { return }
        let current = voiceOverIndex.map { min($0, count - 1) }
        switch direction {
        case .increment:
            voiceOverIndex = min((current ?? -1) + 1, count - 1)
        case .decrement:
            voiceOverIndex = current.flatMap { $0 > 0 ? $0 - 1 : nil }
        @unknown default:
            break
        }
    }
}

/// Segments and unpriced squares share one look: corner radius and line width.
private enum BarStyle {
    static let cornerRadius: CGFloat = 3
    static let lineWidth: CGFloat = 1.5
}

/// Filled in the list color when bought, outlined when not (LD-29). The fill fades, so
/// checking an item off animates from outline to fill.
private struct SegmentShape: View {
    let isBought: Bool
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BarStyle.cornerRadius, style: .continuous)
        shape
            .fill(color.opacity(isBought ? 1 : 0))
            .overlay { shape.strokeBorder(color, lineWidth: BarStyle.lineWidth) }
    }
}

/// An item without a price (LD-24): a square with a dashed outline, no fill. The dashes
/// are fitted to the square's size: one on each corner and one in the middle of each
/// side, so the pattern stays readable at 10 pt and scales with Dynamic Type.
private struct UnpricedSquare: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // `strokeBorder` strokes the shape inset by half the line width.
            let inset = side - BarStyle.lineWidth
            let radius = max(BarStyle.cornerRadius - BarStyle.lineWidth / 2, 0)
            let perimeter = 4 * (inset - 2 * radius) + 2 * .pi * radius
            // 8 dashes and 8 gaps of equal length. The path starts in the middle of the
            // right side, so a half-dash phase centers a dash there (and on every corner).
            let unit = perimeter / 16
            RoundedRectangle(cornerRadius: BarStyle.cornerRadius, style: .continuous)
                .strokeBorder(PurchaseBarColors.unpriced,
                              style: StrokeStyle(lineWidth: BarStyle.lineWidth, lineCap: .butt,
                                                 dash: [unit, unit], dashPhase: unit / 2))
        }
    }
}

/// The "other" popover of one side of the bar, anchored to its segment.
private struct OtherPopover: Identifiable {
    let isBought: Bool
    let rect: CGRect
    var id: Bool { isBought }
}
