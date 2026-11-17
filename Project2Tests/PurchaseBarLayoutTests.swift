//
//  PurchaseBarLayoutTests.swift
//  Project2Tests
//
//  Spec 04 purchase bar: the pure layout (LD-20...LD-25, LD-27 hit testing),
//  its VoiceOver texts (LD-28) and the contrast of its colors (LD-29).
//  No UI: items are plain values with `String` ids.
//

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Project2

@Suite("Purchase bar", .tags(.money))
struct PurchaseBarLayoutTests {

    typealias Layout = PurchaseBarLayout<String>

    /// "Sofa 450", "Lamp 60✓", "Rug -" → items in list order ("-" = no price, "✓" = bought).
    static func items(_ specs: [String]) -> [Layout.Item] {
        specs.map { spec in
            let parts = spec.split(separator: " ").map(String.init)
            let isComplete = parts[1].hasSuffix("✓")
            let price = parts[1].replacingOccurrences(of: "✓", with: "")
            return Layout.Item(id: parts[0], lineTotal: price == "-" ? nil : dec(price), isComplete: isComplete)
        }
    }

    static func layout(_ specs: [String], width: CGFloat = 300,
                       metrics: Layout.Metrics = Layout.Metrics()) -> Layout {
        Layout(items: items(specs), width: width, metrics: metrics)
    }

    static func segment(_ layout: Layout, _ id: String) -> Layout.Segment? {
        layout.segments.first { $0.kind == .item(id) }
    }

    // MARK: - LD-21 proportions

    @Test("LD-21 one segment per priced item, width ∝ lineTotal / planned (±1 pt)")
    func proportionalWidths() throws {
        let layout = Self.layout(["Sofa 450", "Lamp 60", "Rug 240", "Chair 150"], width: 300)
        #expect(layout.segments.count == 4)
        let planned: Double = 900
        for (id, total) in [("Sofa", 450.0), ("Lamp", 60.0), ("Rug", 240.0), ("Chair", 150.0)] {
            let segment = try #require(Self.segment(layout, id))
            #expect(abs(segment.width - 300 * total / planned) <= 1, "\(id): \(segment.width)")
        }
    }

    @Test("LD-21 priced widths fill the bar minus the square zone; segments tile without gaps")
    func widthsFillPricedZone() {
        let metrics = Layout.Metrics(minSegmentWidth: 6, squareSize: 10, squareSpacing: 2, maxSquares: 3)
        let layout = Self.layout(["A 10", "B 20✓", "C -", "D 30", "E -"], width: 200, metrics: metrics)
        #expect(abs(layout.pricedWidth - 176) < 0.001, "200 − 2 squares × (10 + 2)")
        let sum = layout.segments.reduce(CGFloat(0)) { $0 + $1.width }
        #expect(abs(sum - layout.pricedWidth) < 0.001)
        #expect(layout.segments.first?.x == 0)
        for (left, right) in zip(layout.segments, layout.segments.dropFirst()) {
            #expect(abs(left.maxX - right.x) < 0.001)
        }
    }

    @Test("LD-21 money sums stay Decimal: a cent-level split is not lost to Double")
    func decimalTotals() {
        // 0.1 + 0.2 in Double is 0.30000000000000004; the "other" total must be exact.
        let layout = Self.layout(["Big 1000", "Gum 0.1", "Mint 0.2"], width: 300)
        let other = layout.segments.first { $0.isOther }
        #expect(other?.total == dec("0.3"))
    }

    // MARK: - LD-22 bought on the left

    @Test("LD-22 bought segments are left of all others; their width / priced width = boughtFraction")
    func boughtOnTheLeft() throws {
        let specs = ["Sofa 450", "Lamp 60✓", "Rug 240", "Chair 150✓", "Vase 9.99"]
        let layout = Self.layout(specs, width: 320)
        let boughtFlags = layout.segments.map(\.isBought)
        #expect(boughtFlags == boughtFlags.sorted { $0 && !$1 }, "all true before all false")
        #expect(layout.segments.prefix(2).map(\.kind) == [.item("Lamp"), .item("Chair")], "list order inside a side")

        let summary = BudgetCalculator.summary(
            of: Self.items(specs).map { BudgetLine(price: $0.lineTotal, isComplete: $0.isComplete) },
            listCurrencyCode: "USD")
        let fraction = Double(truncating: summary.boughtFraction as NSNumber)
        let boughtSum = layout.segments.filter(\.isBought).reduce(CGFloat(0)) { $0 + $1.width }
        #expect(abs(boughtSum / layout.pricedWidth - fraction) < 0.000_001)
        #expect(abs(layout.boughtWidth - boughtSum) < 0.001)
        // The same percent as "N% bought" (rounded down there).
        #expect(ListStatusText.percentRoundedDown(summary.boughtFraction) == Int(fraction * 100))
    }

    @Test("LD-22 nothing bought / everything bought")
    func noneOrAllBought() {
        let none = Self.layout(["A 10", "B 20"])
        #expect(none.boughtWidth == 0)
        #expect(none.segments.allSatisfy { !$0.isBought })
        let all = Self.layout(["A 10✓", "B 20✓"])
        #expect(all.boughtWidth == all.pricedWidth)
        #expect(all.segments.allSatisfy { $0.isBought })
    }

    // MARK: - LD-23 minimum width and "other"

    @Test("LD-23 narrow segments merge into 'other', separately for bought and not bought")
    func otherPerSide() throws {
        // 300 pt; 1 unit ≈ 0.3 pt, so 5-unit items (1.5 pt) are below the 6 pt minimum.
        let layout = Self.layout(["Big 500", "Gum 5", "Mint 5", "Done 400✓", "Pen 5✓", "Clip 5✓"])
        let others = layout.segments.filter(\.isOther)
        #expect(others.count == 2)
        let boughtOther = try #require(others.first { $0.isBought })
        let toBuyOther = try #require(others.first { !$0.isBought })
        #expect(boughtOther.itemIDs == ["Pen", "Clip"])
        #expect(toBuyOther.itemIDs == ["Gum", "Mint"])
        #expect(boughtOther.total == 10)
        // "other" is the last segment of its side.
        #expect(layout.segments.last?.kind == .other(isBought: false))
        #expect(layout.segments[1].kind == .other(isBought: true))
        #expect(layout.itemIDsInBarOrder == ["Done", "Pen", "Clip", "Big", "Gum", "Mint"])
    }

    @Test("LD-23 the width of 'other' is the sum of its items' shares")
    func otherWidthIsSumOfShares() throws {
        // Four items of 1 % each = 3 pt each, 12 pt together (above the 6 pt minimum).
        let layout = Self.layout(["Big 96", "A 1", "B 1", "C 1", "D 1"], width: 300)
        let other = try #require(layout.segments.first { $0.isOther })
        #expect(abs(other.width - 12) < 0.001)
        #expect(other.itemIDs.count == 4)
    }

    @Test("LD-23 a single narrow item is not merged: it is widened to the minimum")
    func singleNarrowIsStretched() throws {
        let layout = Self.layout(["Big 990", "Gum 1"], width: 300,
                                 metrics: .init(minSegmentWidth: 6))
        #expect(!layout.segments.contains { $0.isOther })
        let gum = try #require(Self.segment(layout, "Gum"))
        #expect(abs(gum.width - 6) < 0.001)
        let big = try #require(Self.segment(layout, "Big"))
        #expect(abs(big.width + gum.width - 300) < 0.001, "the side keeps its width")
    }

    @Test("LD-23 widening never pushes the bought / not bought edge (LD-22 wins)")
    func wideningKeepsTheEdge() throws {
        let layout = Self.layout(["Gum 1✓", "Big 999"], width: 300)
        let gum = try #require(Self.segment(layout, "Gum"))
        // The bought side is 0.3 pt: Gum fills it and stays that narrow.
        #expect(abs(gum.width - 0.3) < 0.001)
        #expect(abs(layout.boughtWidth - 0.3) < 0.001)
    }

    @Test("LD-23 no wide segment widens below the minimum while giving width away")
    func donorsKeepMinimum() {
        let layout = Self.layout(["A 7", "B 7", "C 1", "D 1", "E 1"], width: 100,
                                 metrics: .init(minSegmentWidth: 30))
        #expect(layout.segments.allSatisfy { $0.width >= 30 - 0.001 || $0.isOther })
        let sum = layout.segments.reduce(CGFloat(0)) { $0 + $1.width }
        #expect(abs(sum - 100) < 0.001)
    }

    @Test("50 equal items: every segment is too narrow, one 'other' fills the bar")
    func fiftyEqualItems() {
        let layout = Self.layout((1...50).map { "Item\($0) 10" }, width: 280)
        #expect(layout.segments.count == 1)
        #expect(layout.segments.first?.itemIDs.count == 50)
        #expect(abs((layout.segments.first?.width ?? 0) - 280) < 0.001)
    }

    // MARK: - LD-24 / LD-25 items without a price

    @Test("LD-24 unpriced items are fixed-size squares at the end, at most 3",
          arguments: [(0, 0), (1, 1), (3, 3), (7, 3)])
    func squares(unpriced: Int, expectedSquares: Int) {
        let metrics = Layout.Metrics(minSegmentWidth: 6, squareSize: 10, squareSpacing: 2, maxSquares: 3)
        let specs = ["A 10", "B 20"] + (0..<unpriced).map { "U\($0) -" }
        let layout = Self.layout(specs, width: 200, metrics: metrics)
        #expect(layout.unpricedCount == unpriced)
        #expect(layout.squareSize == 10)
        #expect(abs(layout.pricedWidth - (200 - CGFloat(expectedSquares) * 12)) < 0.001)
        // Each square is centred in a slot of size + spacing, like a segment in its width,
        // so the drawn gaps (half spacing on each side) all equal the spacing.
        #expect(layout.squareXs.count == expectedSquares)
        #expect(layout.squareXs == (0..<expectedSquares).map { layout.pricedWidth + 1 + CGFloat($0) * 12 })
        if let last = layout.squareXs.last {
            #expect(abs(last + 10 - 199) < 0.001, "the last square ends half a gap before the bar's end")
        }
        #expect(layout.squareXs.allSatisfy { $0 >= layout.pricedWidth }, "after every priced segment")
    }

    @Test("LD-24 a bar too narrow for every square shows fewer, never past its end")
    func squaresFitTheBar() {
        let metrics = Layout.Metrics(minSegmentWidth: 6, squareSize: 10, squareSpacing: 2, maxSquares: 3)
        let layout = Self.layout(["A 10", "U0 -", "U1 -", "U2 -"], width: 30, metrics: metrics)
        #expect(layout.squareXs.count == 2, "30 pt fits two 12 pt slots")
        #expect(layout.unpricedCount == 3, "the label still counts all of them")
        #expect(layout.squareXs.allSatisfy { $0 + 10 <= 30 })
        #expect(Self.layout(["A 10", "U0 -"], width: 0, metrics: metrics).squareXs.isEmpty)
    }

    @Test("LD-25 all items without a price: no bar")
    func allUnpriced() {
        let layout = Self.layout(["A -", "B -", "C -"])
        #expect(!layout.isBarVisible)
        #expect(layout.segments.isEmpty)
        #expect(layout.squareXs.isEmpty)
        #expect(layout.unpricedCount == 3)
        #expect(layout.segmentIndex(at: 10) == nil)
    }

    @Test("LD-25 / LD-24 labels: '3 items without price' alone, '+2 without price' next to the bar",
          .englishUI)
    func unpricedLabels() {
        func text(_ specs: [String]) -> ListSummaryText {
            let lines = Self.items(specs).map { BudgetLine(price: $0.lineTotal, isComplete: $0.isComplete) }
            return ListSummaryText(BudgetCalculator.summary(of: lines, listCurrencyCode: "USD"),
                                   currencyCode: "USD", locale: Locale(identifier: "en_US"))
        }
        let none = text(["A -", "B -", "C -"])
        #expect(!none.showsProgress)
        #expect(none.unpriced == "3 items without price")
        #expect(text(["A -"]).unpriced == "1 item without price")

        let some = text(["A 10", "B -", "C -"])
        #expect(some.showsProgress)
        #expect(some.unpriced == "+2 without price")
        #expect(text(["A 10"]).unpriced == nil)
    }

    @Test("A price of 0 is a price; a list of only zero prices splits the bar equally")
    func zeroPrices() {
        let layout = Self.layout(["A 0", "B 0✓"], width: 100, metrics: .init(minSegmentWidth: 6))
        #expect(layout.isBarVisible)
        #expect(layout.segments.map(\.width) == [50, 50])
    }

    @Test("Zero width (before the first layout pass) draws nothing wider than 0")
    func zeroWidth() {
        let layout = Self.layout(["A 10", "B -"], width: 0)
        #expect(layout.pricedWidth == 0)
        #expect(layout.segments.allSatisfy { $0.width == 0 })
    }

    // MARK: - LD-27 hit testing

    @Test("LD-27 a tap goes to the segment under it; past the priced zone nothing is hit")
    func hitTesting() throws {
        let metrics = Layout.Metrics(minSegmentWidth: 6, squareSize: 10, squareSpacing: 2, maxSquares: 3)
        let layout = Self.layout(["A 50✓", "B 50", "C -"], width: 112, metrics: metrics)
        #expect(layout.pricedWidth == 100)
        #expect(layout.segmentIndex(at: 10) == 0)
        #expect(layout.segmentIndex(at: 60) == 1)
        #expect(layout.segmentIndex(at: 100) == 1, "the right edge belongs to the last segment")
        #expect(layout.segmentIndex(at: -5) == 0, "left of the bar: the nearest segment")
        #expect(layout.segmentIndex(at: 106) == nil, "an unpriced square")
    }

    // MARK: - LD-28 VoiceOver texts

    @Test("LD-28 summary value: percent, items, amount to buy", .englishUI)
    func voiceOverSummary() {
        let lines = Self.items(["Sofa 450", "Lamp 60✓", "Rug -"])
            .map { BudgetLine(price: $0.lineTotal, isComplete: $0.isComplete) }
        let summary = BudgetCalculator.summary(of: lines, listCurrencyCode: "EUR")
        let text = PurchaseBarText.summary(summary, currencyCode: "EUR", locale: Locale(identifier: "en_US"))
        #expect(text == "11% bought, 1 of 3 items, €450.00 to buy")
        #expect(PurchaseBarText.label == "Purchase progress")
    }

    @Test("LD-28 one segment: 'Sofa, €450.00, bought' / 'not bought'", .englishUI)
    func voiceOverItem() {
        let enUS = Locale(identifier: "en_US")
        #expect(PurchaseBarText.item(name: "Sofa", lineTotal: 450, isComplete: true, currencyCode: "EUR",
                                     locale: enUS) == "Sofa, €450.00, bought")
        #expect(PurchaseBarText.item(name: "Lamp", lineTotal: 60, isComplete: false, currencyCode: "EUR",
                                     locale: enUS) == "Lamp, €60.00, not bought")
    }

    // MARK: - LD-29 colors

    static let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    static let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

    @Test("LD-29 every list color has ≥ 3:1 segment contrast in light and dark mode",
          arguments: FavoriteColor.allCases)
    func segmentContrast(color: FavoriteColor) {
        for traits in [Self.lightTraits, Self.darkTraits] {
            let rgb = PurchaseBarColors.segmentRGB(color, traits: traits)
            let contrast = PurchaseBarColors.worstContrast(rgb, against: PurchaseBarColors.backgrounds(traits: traits))
            #expect(contrast >= 3, "\(color) \(traits.userInterfaceStyle == .dark ? "dark" : "light"): \(contrast)")
        }
    }

    @Test("LD-29 a color that already has enough contrast is used as it is")
    func keepsListColorWhenEnough() {
        // System blue on white is about 4:1.
        let blue = ColorContrast.RGB(UIColor.systemBlue, traits: Self.lightTraits)
        #expect(PurchaseBarColors.segmentRGB(.blue, traits: Self.lightTraits) == blue)
    }

    @Test("LD-29 yellow on white is too light; the bar uses a darker yellow")
    func yellowIsDarkened() {
        let yellow = ColorContrast.RGB(UIColor.systemYellow, traits: Self.lightTraits)
        let white = ColorContrast.RGB(red: 1, green: 1, blue: 1)
        #expect(ColorContrast.ratio(yellow, white) < 3)
        let segment = PurchaseBarColors.segmentRGB(.yellow, traits: Self.lightTraits)
        #expect(segment != yellow)
        #expect(ColorContrast.ratio(segment, white) >= 3)
    }

    @Test("WCAG contrast formula: black on white is 21:1, a color on itself 1:1")
    func contrastFormula() {
        let black = ColorContrast.RGB(red: 0, green: 0, blue: 0)
        let white = ColorContrast.RGB(red: 1, green: 1, blue: 1)
        #expect(abs(ColorContrast.ratio(black, white) - 21) < 0.001)
        #expect(ColorContrast.ratio(white, white) == 1)
    }
}
