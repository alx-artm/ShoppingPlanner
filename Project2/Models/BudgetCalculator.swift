//
//  BudgetCalculator.swift
//  Project2
//
//  Pure money math for lists and groups (spec 01, DM-20...DM-25).
//  No SwiftData, no UI: it takes value snapshots and returns values,
//  so it can be unit-tested with plain arrays.
//
//  All amounts are `Decimal` in the list currency and are never rounded here.
//  Rounding happens only when a value is formatted for display (DM-25).
//

import Foundation

/// The part of an item that matters for money math.
struct BudgetLine: Hashable, Sendable {
    /// Price per unit; `nil` = no price yet.
    var price: Decimal?
    var quantity: Int
    var isComplete: Bool
    /// A must-have (spec 11): counted in `mustHavePlanned` too.
    var isMustHave: Bool
    /// `nil` = same as the list currency.
    var currencyCode: String?
    /// 1 unit of `currencyCode` = `exchangeRate` units of the list currency.
    var exchangeRate: Decimal?

    init(
        price: Decimal?,
        quantity: Int = 1,
        isComplete: Bool = false,
        isMustHave: Bool = false,
        currencyCode: String? = nil,
        exchangeRate: Decimal? = nil
    ) {
        self.price = price
        self.quantity = quantity
        self.isComplete = isComplete
        self.isMustHave = isMustHave
        self.currencyCode = currencyCode
        self.exchangeRate = exchangeRate
    }
}

/// Totals of a set of items (a group or a whole list).
struct BudgetSummary: Equatable, Sendable {
    /// Σ line totals of all items.
    var planned: Decimal
    /// Σ line totals of completed items.
    var bought: Decimal
    /// `planned − bought`.
    var toBuy: Decimal
    /// `bought / planned`, 0 when nothing is planned. Range 0...1.
    var boughtFraction: Decimal
    var budget: Decimal?
    /// `budget − planned`, `nil` when there is no budget. Negative = over budget.
    var budgetLeft: Decimal?
    var isOverBudget: Bool
    /// Items without a price (they add 0 to the sums).
    var unpricedCount: Int
    /// Items in another currency without an exchange rate (excluded from the sums).
    var missingRateCount: Int
    var itemCount: Int
    var completedCount: Int
    /// Σ line totals of must-have items, bought or not (MH-02); same rules as `planned`.
    var mustHavePlanned: Decimal
    /// Must-have items, priced or not.
    var mustHaveCount: Int
    /// `mustHavePlanned − budget` when the must-haves alone are over the budget, else `nil` (MH-10).
    var mustHaveExcess: Decimal? {
        guard let budget, mustHavePlanned > budget else { return nil }
        return mustHavePlanned - budget
    }

    static let empty = BudgetCalculator.summary(of: [], listCurrencyCode: ListModel.fallbackCurrencyCode)
}

enum BudgetCalculator {
    /// `price × quantity × rate` in the list currency (DM-20).
    ///
    /// Returns `nil` when the item can't contribute to the sums:
    /// no price (DM-21), or a foreign currency without a rate (DM-22).
    static func lineTotal(of line: BudgetLine, listCurrencyCode: String) -> Decimal? {
        guard let price = line.price else { return nil }
        let base = price * Decimal(line.quantity)
        guard isForeign(line, listCurrencyCode: listCurrencyCode) else {
            // Same currency: the rate is ignored even if it is set.
            return base
        }
        guard let rate = line.exchangeRate else { return nil }
        return base * rate
    }

    /// Totals of `lines` in the list currency (DM-23). Group and list totals
    /// both go through this function, so the sum of groups equals the list (DM-24).
    static func summary(
        of lines: [BudgetLine],
        listCurrencyCode: String,
        budget: Decimal? = nil
    ) -> BudgetSummary {
        var planned: Decimal = 0
        var bought: Decimal = 0
        var unpriced = 0
        var missingRate = 0
        var completed = 0
        var mustHavePlanned: Decimal = 0
        var mustHaveCount = 0

        for line in lines {
            if line.isComplete { completed += 1 }
            if line.isMustHave { mustHaveCount += 1 }

            if line.price == nil {
                unpriced += 1
                continue
            }
            guard let total = lineTotal(of: line, listCurrencyCode: listCurrencyCode) else {
                missingRate += 1
                continue
            }
            planned += total
            if line.isComplete { bought += total }
            if line.isMustHave { mustHavePlanned += total }
        }

        let fraction: Decimal = planned == 0 ? 0 : bought / planned
        let budgetLeft = budget.map { $0 - planned }

        return BudgetSummary(
            planned: planned,
            bought: bought,
            toBuy: planned - bought,
            boughtFraction: fraction,
            budget: budget,
            budgetLeft: budgetLeft,
            isOverBudget: budget.map { planned > $0 } ?? false,
            unpricedCount: unpriced,
            missingRateCount: missingRate,
            itemCount: lines.count,
            completedCount: completed,
            mustHavePlanned: mustHavePlanned,
            mustHaveCount: mustHaveCount
        )
    }

    private static func isForeign(_ line: BudgetLine, listCurrencyCode: String) -> Bool {
        guard let code = line.currencyCode else { return false }
        return code.uppercased() != listCurrencyCode.uppercased()
    }
}

extension Decimal {
    /// For APIs that need `Double` (e.g. `Gauge`). Never use it for money math.
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
