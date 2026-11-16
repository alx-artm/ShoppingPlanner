//
//  ListStatusText.swift
//  Project2
//
//  The status of a list on Home (spec 02 "Status model", HM-16, HM-18…HM-30):
//  one pure function of `BudgetSummary` + currency + locale, whose parts the
//  tile, the row and VoiceOver lay out. Views never decide texts themselves.
//
//  Two independent axes:
//  - shopping progress: share of the planned money already bought (bar and %);
//  - budget of the plan: `budget − planned` "to spare", or `planned − budget` "over".
//  The budget part is always present, so all tiles have the same lines (HM-28).
//

import Foundation

struct ListStatusText: Equatable, Sendable {
    /// "Empty", "3 items", "13% bought" or "All bought".
    enum Progress: Equatable, Sendable {
        /// S1: no items.
        case empty
        /// S2: items, but none has a price.
        case items(Int)
        /// S3–S5: percent of the planned money bought, rounded down (99.6 % → 99).
        case bought(percent: Int)
        /// S6: every item is checked off.
        case allBought
    }

    /// The budget part, always present (HM-28).
    enum Budget: Equatable, Sendable {
        case none
        /// A budget, but no prices yet: the plan is unknown, not zero (S1/S2).
        case notPlanned(budget: Decimal)
        /// `planned ≤ budget`: `budget − planned` can still be planned (S4, HM-23).
        case toSpare(Decimal, of: Decimal)
        /// `planned > budget` by this amount (S5, HM-21).
        case over(Decimal)
    }

    let progress: Progress
    let budget: Budget

    /// "$340.00", or "—" when no item has a price (HM-06).
    let amount: String
    /// Row: "13% bought", "All bought", "Empty", "3 items".
    let progressText: String
    /// Tile footer next to the bar: "13%". `nil` in S1/S2, where the footer shows `progressText` instead.
    let percentText: String?
    /// Tile: "No budget", "Budget €500", "€160 to spare", "€15 over" (no cents, HM-29; ⚠ is drawn by the view).
    let budgetShort: String
    /// Row and list summary bar: "No budget", "budget €500.00", "€160.00 to spare of €500.00",
    /// "plan €15.00 over budget".
    let budgetFull: String
    /// The VoiceOver form of the budget part ("… of €500.00 budget", "no budget").
    let budgetSpoken: String

    /// At least one item has a price: the tile shows the bar and the percent (S3–S6).
    var hasPrices: Bool {
        switch progress {
        case .empty, .items: false
        case .bought, .allBought: true
        }
    }

    var isAllBought: Bool { progress == .allBought }

    /// Only this part is red, with ⚠ (HM-22).
    var isOverBudget: Bool {
        if case .over = budget { true } else { false }
    }

    /// The bar, the same value as the percent (HM-19).
    var barFraction: Double {
        switch progress {
        case .empty, .items: 0
        case .bought(let percent): Double(percent) / 100
        case .allBought: 1
        }
    }

    init(_ summary: BudgetSummary, currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        func money(_ value: Decimal) -> String {
            MoneyFormat.string(value, currencyCode: currencyCode, locale: locale)
        }

        // Progress.
        let hasPrices = Self.hasPrices(summary)
        if summary.itemCount == 0 {
            progress = .empty
        } else if !hasPrices {
            progress = .items(summary.itemCount)
        } else if summary.completedCount == summary.itemCount {
            progress = .allBought
        } else {
            progress = .bought(percent: Self.percentRoundedDown(summary.boughtFraction))
        }

        // Budget.
        if let limit = summary.budget {
            if !hasPrices {
                budget = .notPlanned(budget: limit)
            } else if summary.planned > limit {
                budget = .over(summary.planned - limit)
            } else {
                budget = .toSpare(limit - summary.planned, of: limit)
            }
        } else {
            budget = .none
        }

        amount = hasPrices ? money(summary.toBuy) : "—"

        let percent: Int? = switch progress {
        case .bought(let value): value
        case .allBought: 100
        case .empty, .items: nil
        }
        percentText = percent.map { Self.percentString($0, locale: locale) }

        progressText = switch progress {
        case .empty: String(localized: "Empty")
        case .items(let count): String(localized: "\(count) items")
        case .bought(let value): String(localized: "\(Self.percentString(value, locale: locale)) bought")
        case .allBought: String(localized: "All bought")
        }

        budgetShort = Self.shortBudgetText(budget, currencyCode: currencyCode, locale: locale)
        switch budget {
        case .none:
            budgetFull = String(localized: "status.row.noBudget", defaultValue: "No budget")
            budgetSpoken = String(localized: "status.voice.noBudget", defaultValue: "no budget")
        case .notPlanned(let limit):
            budgetFull = String(localized: "budget \(money(limit))")
            budgetSpoken = budgetFull
        case .toSpare(let left, let limit):
            budgetFull = String(localized: "\(money(left)) to spare of \(money(limit))")
            budgetSpoken = String(localized: "\(money(left)) to spare of \(money(limit)) budget")
        case .over(let excess):
            budgetFull = String(localized: "plan \(money(excess)) over budget")
            budgetSpoken = budgetFull
        }
    }

    /// One VoiceOver sentence, identical for the tile and the row (HM-16):
    /// "Kitchen, to buy €340.00, 13% bought, €160.00 to spare of €500.00 budget".
    func accessibilityLabel(name: String) -> String {
        var parts = [name]
        switch progress {
        case .empty:
            parts.append(String(localized: "status.voice.empty", defaultValue: "empty"))
        case .items:
            parts.append(progressText)
            parts.append(String(localized: "status.voice.noPrices", defaultValue: "no prices yet"))
        case .bought:
            parts.append(String(localized: "to buy \(amount)"))
            parts.append(progressText)
        case .allBought:
            parts.append(String(localized: "status.voice.allBought", defaultValue: "all bought"))
        }
        parts.append(budgetSpoken)
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    /// The tile form of the budget part, without cents (HM-29): "No budget", "Budget €500",
    /// "€160 to spare" / «запас 160 €», "€15 over". "To spare" rounds down and "over" rounds up,
    /// so the tile never promises more money than there is.
    ///
    /// - Parameter bundle: where the translation comes from. The app passes `.main`; tests pass
    ///   a language bundle (`ru.lproj`) to check the exact text in another language.
    static func shortBudgetText(_ budget: Budget, currencyCode: String, locale: Locale,
                                bundle: Bundle = .main) -> String {
        func whole(_ value: Decimal, _ rule: FloatingPointRoundingRule) -> String {
            MoneyFormat.wholeString(value, currencyCode: currencyCode, locale: locale, rounding: rule)
        }
        return switch budget {
        case .none:
            String(localized: "No budget", bundle: bundle)
        case .notPlanned(let limit):
            String(localized: "Budget \(whole(limit, .toNearestOrAwayFromZero))", bundle: bundle)
        case .toSpare(let left, _):
            String(localized: "\(whole(left, .down)) to spare", bundle: bundle)
        case .over(let excess):
            String(localized: "\(whole(excess, .up)) over", bundle: bundle)
        }
    }

    /// At least one item has a price. Without one, Home shows "—" instead of "0" (HM-06).
    static func hasPrices(_ summary: BudgetSummary) -> Bool {
        summary.itemCount - summary.unpricedCount > 0
    }

    /// 0...100, rounded down, so 99.6 % is 99 and 100 means everything is bought (HM-24).
    static func percentRoundedDown(_ fraction: Decimal) -> Int {
        var scaled = fraction * 100
        var result = Decimal()
        NSDecimalRound(&result, &scaled, 0, .down)
        return min(max(NSDecimalNumber(decimal: result).intValue, 0), 100)
    }

    /// "13%" in en_US, "13 %" in ru_RU.
    static func percentString(_ percent: Int, locale: Locale) -> String {
        (Decimal(percent) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
