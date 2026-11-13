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
    /// "+3 without price"; `nil` when every item has a price (LD-11).
    let unpriced: String?
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
        unpriced = summary.unpricedCount > 0
            ? String(localized: "+\(summary.unpricedCount) without price",
                     comment: "List summary bar: number of items that have no price yet.")
            : nil
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
}

/// The text of the inline name field (spec 04 Inline add). The field is multi-line, so
/// Return arrives as a newline: every line before the last newline is a finished item,
/// the text after it is the next draft. Names are trimmed only here, at commit (LD-16),
/// and never parsed ("Sofa 450 x2" is a name, LD-17).
///
/// Typing fast, the text view can report its old text once more ("Ball\nP") after the
/// screen has already saved "Ball" and cleared the field. `saved` is that already-saved
/// part; when the text still starts with it, it is skipped, so nothing is saved twice.
struct InlineEntry: Equatable, Sendable {
    /// Names to save, trimmed, blank lines dropped.
    let finishedLines: [String]
    /// What stays in the field, untouched.
    let rest: String
    /// The text had at least one new Return.
    let hasReturn: Bool
    /// The part of the text that this entry saves (up to the last newline), to pass as
    /// `saved` with the next change.
    let consumed: String
    /// The text started with the already-saved part, which was skipped.
    let skippedSaved: Bool

    init(_ text: String, saved: String = "") {
        skippedSaved = !saved.isEmpty && text.hasPrefix(saved)
        let fresh = skippedSaved ? String(text.dropFirst(saved.count)) : text
        let lines = fresh.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        hasReturn = lines.count > 1
        rest = hasReturn ? (lines.last ?? "") : fresh
        finishedLines = lines.dropLast().compactMap(PlannerStore.normalizedName)
        consumed = hasReturn ? String(fresh.dropLast(rest.count)) : ""
    }
}
