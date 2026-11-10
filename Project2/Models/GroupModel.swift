//
//  GroupModel.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class GroupModel {
        /// Key for device-local UI state (collapsed or not), see `LocalUIState`.
        var uuid: UUID = UUID()
        var name: String = ""
        var sortIndex: Double = 0
        /// Per-group budget limit. UI arrives in v1.x; the field is in the schema already.
        var budget: Decimal? = nil
        var createdAt: Date = Date.now

        var list: ListModel? = nil

        @Relationship(deleteRule: .cascade, inverse: \ItemModel.group)
        var items: [ItemModel]? = []

        init(
            uuid: UUID = UUID(),
            name: String = "",
            sortIndex: Double = 0,
            budget: Decimal? = nil,
            createdAt: Date = .now
        ) {
            self.uuid = uuid
            self.name = name
            self.sortIndex = sortIndex
            self.budget = budget
            self.createdAt = createdAt
        }
    }
}

extension GroupModel {
    /// Items in display order: not completed first (manual order), then completed.
    var sortedItems: [ItemModel] {
        PlannerOrdering.sortedItems(items ?? [])
    }

    var incompleteItems: [ItemModel] {
        sortedItems.filter { !$0.isComplete }
    }

    /// Totals of this group, in the currency of its list.
    var summary: BudgetSummary {
        BudgetCalculator.summary(
            of: (items ?? []).map(\.budgetLine),
            listCurrencyCode: list?.currencyCode ?? ListModel.fallbackCurrencyCode,
            budget: budget
        )
    }
}
