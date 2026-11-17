//
//  PurchaseBarLayout.swift
//  Project2
//
//  The segmented purchase bar of the list summary bar (spec 04 LD-20...LD-25)
//  as a pure function: items (id, line total, bought) + width → segments.
//  No SwiftUI and no SwiftData, so every rule is unit-tested with plain arrays.
//
//  [ bought (filled) | to buy (outlined) | ▢ ▢ ▢ ]
//  └──── priced zone, ∝ line totals ────┘ └ squares: items without a price
//
//  Money stays `Decimal`: shares are computed as `lineTotal / planned` in
//  `Decimal` and only the resulting fraction becomes a width in points.
//

import CoreGraphics
import Foundation

struct PurchaseBarLayout<ItemID: Hashable & Sendable>: Hashable, Sendable {
    /// One item of the list, in list order (groups, then items).
    struct Item: Hashable, Sendable {
        var id: ItemID
        /// `nil` = no price: drawn as a square, not part of the proportions (LD-24).
        var lineTotal: Decimal?
        var isComplete: Bool
    }

    /// What a segment stands for; also its identity, so a checked-off item keeps its
    /// view and the move to the bought side can be animated (LD-26).
    enum Kind: Hashable, Sendable {
        case item(ItemID)
        /// Items narrower than the minimum width, merged (LD-23); one per side.
        case other(isBought: Bool)
    }

    struct Segment: Identifiable, Hashable, Sendable {
        let kind: Kind
        /// The item, or the items merged into "other", in list order.
        let itemIDs: [ItemID]
        let isBought: Bool
        /// Σ line totals of `itemIDs`, in the list currency.
        let total: Decimal
        let x: CGFloat
        let width: CGFloat

        var id: Kind { kind }
        var maxX: CGFloat { x + width }
        var isOther: Bool {
            if case .other = kind { true } else { false }
        }
    }

    /// Sizes in points; the view passes scaled values (`@ScaledMetric`).
    struct Metrics: Hashable, Sendable {
        /// Narrower segments are merged into "other" (LD-23).
        var minSegmentWidth: CGFloat = 6
        /// Side of an unpriced square; the view passes the bar height (LD-24).
        var squareSize: CGFloat = 10
        /// Space between two squares and between the priced zone and the first one; the
        /// view passes the gap it draws between segments.
        var squareSpacing: CGFloat = 1.5
        /// More unpriced items are only counted in the label (LD-24).
        var maxSquares = 3
    }

    let width: CGFloat
    /// Left to right: bought segments, then the ones to buy (LD-22).
    let segments: [Segment]
    /// Width of the proportional part: `width` minus the square zone (LD-21).
    let pricedWidth: CGFloat
    /// Width of the bought side; `boughtWidth / pricedWidth == boughtFraction` (LD-22).
    let boughtWidth: CGFloat
    /// Items without a price.
    let unpricedCount: Int
    /// Left edges of the unpriced squares, at most `maxSquares` (LD-24).
    let squareXs: [CGFloat]
    let squareSize: CGFloat

    /// No item has a price: no bar, only the label "N items without price" (LD-25).
    var isBarVisible: Bool { !segments.isEmpty }

    /// Every priced item in bar order, "other" expanded (VoiceOver goes through these, LD-28).
    var itemIDsInBarOrder: [ItemID] { segments.flatMap(\.itemIDs) }

    init(items: [Item], width: CGFloat, metrics: Metrics = Metrics()) {
        let width = max(width, 0)
        self.width = width
        squareSize = metrics.squareSize

        let priced = items.compactMap { item in item.lineTotal.map { (item: item, total: $0) } }
        unpricedCount = items.count - priced.count

        guard !priced.isEmpty else {
            // LD-25: nothing to draw.
            segments = []
            pricedWidth = 0
            boughtWidth = 0
            squareXs = []
            return
        }

        // LD-24: squares have a fixed size, at the end. Each one takes a slot of
        // size + spacing and sits in its middle, the same way the view insets every
        // segment by half the gap on both sides, so all the drawn gaps are equal.
        // A bar too narrow for them shows fewer, so they never spill past its end.
        let step = metrics.squareSize + metrics.squareSpacing
        let fitting = step > 0 ? Int((width / step).rounded(.down)) : 0
        let squareCount = min(unpricedCount, max(metrics.maxSquares, 0), fitting)
        let pricedWidth = max(width - CGFloat(squareCount) * step, 0)
        self.pricedWidth = pricedWidth
        squareXs = (0..<squareCount).map { pricedWidth + metrics.squareSpacing / 2 + CGFloat($0) * step }

        // LD-21: width ∝ lineTotal / planned. If every price is 0, the plan is 0 and
        // nothing is proportional: each item gets an equal share instead.
        let planned = priced.reduce(Decimal(0)) { $0 + $1.total }
        func share(_ total: Decimal) -> Decimal {
            planned > 0 ? total / planned : 1 / Decimal(priced.count)
        }
        func points(_ fraction: Decimal) -> CGFloat {
            CGFloat(NSDecimalNumber(decimal: fraction).doubleValue) * pricedWidth
        }

        let bought = priced.filter { $0.item.isComplete }
        let toBuy = priced.filter { !$0.item.isComplete }
        // The side widths come from the money sums, so the edge between them is exactly
        // `boughtFraction` (LD-22) whatever the minimum width does inside each side.
        let boughtShare = bought.reduce(Decimal(0)) { $0 + share($1.total) }
        let boughtWidth = bought.isEmpty ? 0 : (toBuy.isEmpty ? pricedWidth : points(boughtShare))
        self.boughtWidth = boughtWidth

        func side(_ entries: [(item: Item, total: Decimal)]) -> [Side.Entry] {
            entries.map { Side.Entry(id: $0.item.id, total: $0.total, width: points(share($0.total))) }
        }
        segments = Side.layout(side(bought), isBought: true, x: 0, width: boughtWidth,
                               minWidth: metrics.minSegmentWidth)
            + Side.layout(side(toBuy), isBought: false, x: boughtWidth, width: pricedWidth - boughtWidth,
                          minWidth: metrics.minSegmentWidth)
    }

    /// The segment under a tap at `x` (LD-27). Segments tile the priced zone, so a tap on a
    /// narrow one or between two (the drawn gap) goes to the nearest. Taps on the squares
    /// hit nothing: those items have no amount to show.
    func segmentIndex(at x: CGFloat) -> Int? {
        guard isBarVisible, x <= pricedWidth else { return nil }
        if let index = segments.firstIndex(where: { x >= $0.x && x < $0.maxX }) { return index }
        return segments.indices.min { distance(x, to: segments[$0]) < distance(x, to: segments[$1]) }
    }

    private func distance(_ x: CGFloat, to segment: Segment) -> CGFloat {
        x < segment.x ? segment.x - x : max(x - segment.maxX, 0)
    }

    /// One side of the bar (bought or to buy).
    private enum Side {
        struct Entry {
            let id: ItemID
            let total: Decimal
            var width: CGFloat
        }

        /// LD-23: segments narrower than `minWidth` are merged into "other" (at the end of
        /// the side); a single narrow one stays itself. Either is widened to `minWidth` with
        /// width taken from the wide segments (never below the minimum themselves), so the
        /// side keeps its width. A side narrower than the minimum stays as narrow as it is.
        static func layout(_ entries: [Entry], isBought: Bool, x start: CGFloat, width: CGFloat,
                           minWidth: CGFloat) -> [Segment] {
            guard !entries.isEmpty else { return [] }

            var wide = entries.filter { $0.width >= minWidth }
            let narrow = entries.filter { $0.width < minWidth }

            // Width of the merged / single narrow segment.
            var smallWidth = narrow.reduce(CGFloat(0)) { $0 + $1.width }
            if wide.isEmpty {
                smallWidth = width
            } else if !narrow.isEmpty, smallWidth < minWidth {
                let slack = wide.reduce(CGFloat(0)) { $0 + ($1.width - minWidth) }
                let taken = min(minWidth - smallWidth, slack)
                if slack > 0 {
                    for index in wide.indices {
                        wide[index].width -= taken * (wide[index].width - minWidth) / slack
                    }
                }
                smallWidth += taken
            }

            // Sizes keyed by id, then laid out in list order.
            var widths: [ItemID: CGFloat] = [:]
            for entry in wide { widths[entry.id] = entry.width }

            var result: [Segment] = []
            var x = start
            func append(_ kind: Kind, ids: [ItemID], total: Decimal, width: CGFloat) {
                result.append(Segment(kind: kind, itemIDs: ids, isBought: isBought, total: total,
                                      x: x, width: width))
                x += width
            }

            let single = narrow.count == 1 ? narrow.first : nil
            for entry in entries {
                if let width = widths[entry.id] {
                    append(.item(entry.id), ids: [entry.id], total: entry.total, width: width)
                } else if let single, single.id == entry.id {
                    // One narrow item is not merged, only widened (LD-23).
                    append(.item(entry.id), ids: [entry.id], total: entry.total, width: smallWidth)
                }
            }
            if narrow.count > 1 {
                append(.other(isBought: isBought), ids: narrow.map(\.id),
                       total: narrow.reduce(Decimal(0)) { $0 + $1.total }, width: smallWidth)
            }
            return result
        }
    }
}
