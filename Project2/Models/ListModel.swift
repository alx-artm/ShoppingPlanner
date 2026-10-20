//
//  ListModel.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import Foundation
import SwiftData

/// How `ListModel.iconName` should be rendered.
enum ListIconKind: String, CaseIterable, Codable, Sendable {
    case symbol
    case emoji
}

extension SchemaV1 {
    @Model
    final class ListModel {
        /// Stable identifier. Not unique-constrained: CloudKit does not support it.
        var uuid: UUID = UUID()
        var name: String = ""
        /// SF Symbol name or a single emoji, depending on `iconKindRaw`.
        var iconName: String = "cart"
        var iconKindRaw: String = ListIconKind.symbol.rawValue
        var colorRaw: String = FavoriteColor.blue.rawValue
        var isPinned: Bool = false
        /// Order inside its Home section (pinned / all).
        var sortIndex: Double = 0
        var budget: Decimal? = nil
        /// ISO 4217 code. All sums of the list are expressed in this currency.
        var currencyCode: String = "USD"
        var createdAt: Date = Date.now

        @Relationship(deleteRule: .cascade, inverse: \GroupModel.list)
        var groups: [GroupModel]? = []

        init(
            uuid: UUID = UUID(),
            name: String = "",
            iconName: String = "cart",
            iconKind: ListIconKind = .symbol,
            color: FavoriteColor = .blue,
            isPinned: Bool = false,
            sortIndex: Double = 0,
            budget: Decimal? = nil,
            currencyCode: String = "USD",
            createdAt: Date = .now
        ) {
            self.uuid = uuid
            self.name = name
            self.iconName = iconName
            self.iconKindRaw = iconKind.rawValue
            self.colorRaw = color.rawValue
            self.isPinned = isPinned
            self.sortIndex = sortIndex
            self.budget = budget
            self.currencyCode = currencyCode
            self.createdAt = createdAt
        }
    }
}

extension ListModel {
    /// Used when a group or item is not attached to a list (drafts, previews).
    static let fallbackCurrencyCode = "USD"

    /// Unknown raw values (e.g. written by a newer app version) fall back to `.symbol` (DM-09).
    var iconKind: ListIconKind {
        get { ListIconKind(rawValue: iconKindRaw) ?? .symbol }
        set { iconKindRaw = newValue.rawValue }
    }

    /// Unknown raw values fall back to `.blue` (DM-09).
    var color: FavoriteColor {
        get { FavoriteColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    /// Groups in display order (DM-06): `sortIndex`, then `createdAt`.
    var sortedGroups: [GroupModel] {
        PlannerOrdering.sortedGroups(groups ?? [])
    }

    var allItems: [ItemModel] {
        (groups ?? []).flatMap { $0.items ?? [] }
    }

    /// Totals of the whole list, in the list currency.
    var summary: BudgetSummary {
        BudgetCalculator.summary(
            of: allItems.map(\.budgetLine),
            listCurrencyCode: currencyCode,
            budget: budget
        )
    }
}
