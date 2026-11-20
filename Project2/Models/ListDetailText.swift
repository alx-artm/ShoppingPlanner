//
//  ListDetailText.swift
//  Project2
//
//  Texts of the list screen (spec 04) as pure functions, like `ListStatusText`
//  for Home: the item row's second line, a group header's amount and the
//  summary bar. Views only lay them out.
//

import Foundation

/// The item row (LD-06...LD-08, LP-08).
enum ItemRowText {
    /// The second line before the link chip: "2 × $55.00 · first line of the note".
    /// "qty × unit price" only when qty > 1 and there is a price; `nil` when there is nothing to show.
    static func detail(quantity: Int, price: Decimal?, currencyCode: String, notes: String,
                       locale: Locale) -> String? {
        var parts: [String] = []
        if quantity > 1, let price {
            parts.append("\(quantity.formatted(.number.locale(locale))) × "
                         + MoneyFormat.string(price, currencyCode: currencyCode, locale: locale))
        }
        if let note = notePreview(notes) {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The first non-empty line of the note, trimmed.
    static func notePreview(_ notes: String) -> String? {
        notes.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// The row's amount: the line total, or "—" without a price, never "0" (LD-08).
    static func total(_ lineTotal: Decimal?, currencyCode: String, locale: Locale) -> String {
        lineTotal.map { MoneyFormat.string($0, currencyCode: currencyCode, locale: locale) } ?? "—"
    }
}

/// How a row looks when its item is bought (spec 04 LD-07a, owner decision 2026-11-13,
/// option C): the name is struck through, the whole row is secondary, the amounts are not
/// struck, so they stay easy to read and compare. The checkbox shape (filled / empty) tells
/// bought rows apart without color (LD-07d).
struct ItemRowStyle: Equatable, Sendable {
    let nameStrikethrough: Bool
    let amountStrikethrough: Bool
    /// The whole row in the secondary color.
    let isDimmed: Bool

    init(isComplete: Bool) {
        nameStrikethrough = isComplete
        amountStrikethrough = false
        isDimmed = isComplete
    }
}

/// The summary bar at the bottom of the list (LD-10, LD-11, LD-11a) and its
/// one-line form while the keyboard is open (owner decision 2026-11-13).
struct ListSummaryText: Equatable, Sendable {
    /// The Home status of the same list: budget texts and percent are shared (LD-11a).
    let status: ListStatusText
    /// "$788.79", or "—" without prices.
    let toBuy: String
    /// "of $909.79"; `nil` without prices.
    let ofPlanned: String?
    /// "13% bought", "All bought", "3 items".
    let progress: String
    /// 0...1, the same value as the percent (HM-19).
    let barFraction: Double
    /// "+3 without price"; `nil` when every item has a price (LD-11, LD-24). When no item has
    /// a price, the only label of the bar's line: "3 items without price" (LD-25).
    let unpriced: String?
    /// The purchase bar and "13% bought" are shown: at least one item has a price (LD-25).
    var showsProgress: Bool { status.hasPrices }
    /// While typing: "To buy $788.79 · 13%".
    let compact: String

    /// Hidden when the list has no items (LD-11).
    let isVisible: Bool

    init(_ summary: BudgetSummary, currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        let status = ListStatusText(summary, currencyCode: currencyCode, locale: locale)
        self.status = status
        toBuy = status.amount
        ofPlanned = status.hasPrices
            ? String(localized: "of \(MoneyFormat.string(summary.planned, currencyCode: currencyCode, locale: locale))",
                     comment: "List summary bar, after the amount to buy: the planned total (\"of €909.79\").")
            : nil
        progress = status.progressText
        barFraction = status.barFraction
        if summary.unpricedCount == 0 {
            unpriced = nil
        } else if status.hasPrices {
            unpriced = String(localized: "+\(summary.unpricedCount) without price",
                              comment: "List summary bar: number of items that have no price yet.")
        } else {
            unpriced = String(localized: "\(summary.unpricedCount) items without price",
                              comment: "List summary bar when no item has a price: no purchase bar, only this.")
        }
        let amount = String(localized: "To buy \(status.amount)",
                            comment: "List summary bar while the keyboard is open (\"To buy €788.79\").")
        compact = status.percentText.map { "\(amount) · \($0)" } ?? amount
        isVisible = summary.itemCount > 0
    }
}

/// The amount in a group header: the group's planned total (LD-04), "—" without prices.
enum GroupHeaderText {
    static func amount(_ summary: BudgetSummary, currencyCode: String, locale: Locale) -> String {
        ListStatusText.hasPrices(summary)
            ? MoneyFormat.string(summary.planned, currencyCode: currencyCode, locale: locale)
            : "—"
    }

    /// VoiceOver label of the header button (LD-31): "Vacation, 3 items, $145.00", or
    /// "Home, 0 items, No price" without prices. No "(3)" brackets, which VoiceOver reads aloud.
    ///
    /// - Parameter bundle: where the translation comes from. The app passes `.main`; tests pass
    ///   a language bundle (`ru.lproj`) to check the exact text in another language.
    static func accessibilityLabel(name: String, itemCount: Int, summary: BudgetSummary,
                                   currencyCode: String, locale: Locale, bundle: Bundle = .main) -> String {
        let count = String(localized: "\(itemCount) items", bundle: bundle, locale: locale)
        let amount = ListStatusText.hasPrices(summary)
            ? MoneyFormat.string(summary.planned, currencyCode: currencyCode, locale: locale)
            : String(localized: "No price", bundle: bundle, locale: locale,
                     comment: "VoiceOver: the total of an item without a price (shown as \"—\").")
        return [name, count, amount].joined(separator: ", ")
    }
}


/// VoiceOver of the purchase bar (LD-28): one adjustable element. Its value is the
/// summary, or the item picked with swipe up / down.
enum PurchaseBarText {
    static var label: String {
        String(localized: "Purchase progress", comment: "VoiceOver label of the segmented purchase bar.")
    }

    /// "13% bought, 5 of 12 items, $788.79 to buy".
    static func summary(_ summary: BudgetSummary, currencyCode: String,
                        locale: Locale = .autoupdatingCurrent) -> String {
        let status = ListStatusText(summary, currencyCode: currencyCode, locale: locale)
        let items = String(localized: "\(summary.completedCount) of \(summary.itemCount) items",
                           comment: "Purchase bar, VoiceOver: bought items of all items (\"5 of 12 items\").")
        let toBuy = String(localized: "\(status.amount) to buy",
                           comment: "Purchase bar, VoiceOver: the amount still to buy (\"$788.79 to buy\").")
        return [status.progressText, items, toBuy].joined(separator: ", ")
    }

    /// One segment: "Sofa, $450.00, bought" / "Lamp, $60.00, not bought".
    static func item(name: String, lineTotal: Decimal, isComplete: Bool, currencyCode: String,
                     locale: Locale = .autoupdatingCurrent) -> String {
        let state = isComplete
            ? String(localized: "purchaseBar.voice.bought", defaultValue: "bought",
                     comment: "Purchase bar, VoiceOver: state of an item, after its name and amount.")
            : String(localized: "purchaseBar.voice.notBought", defaultValue: "not bought",
                     comment: "Purchase bar, VoiceOver: state of an item, after its name and amount.")
        return [name, MoneyFormat.string(lineTotal, currencyCode: currencyCode, locale: locale), state]
            .joined(separator: ", ")
    }
}
