//
//  ItemModel.swift
//  Project #2
//

import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class ItemModel {
        var uuid: UUID = UUID()
        var name: String = ""
        /// 1...999, enforced by `PlannerStore` (DM-13).
        var quantity: Int = 1
        /// Planned price per unit. `nil` means "no price yet", which is not the same as 0.
        var price: Decimal? = nil
        /// Actual price per unit. UI in v1.x.
        var actualPrice: Decimal? = nil
        /// `nil` means "same as the list currency". UI in v1.1.
        var currencyCode: String? = nil
        /// "1 unit of item currency = X list currency". UI in v1.1.
        var exchangeRate: Decimal? = nil
        var urlString: String = ""

        // Link preview cache (M5).
        var linkTitle: String? = nil
        var linkHost: String? = nil
        @Attribute(.externalStorage) var linkImageData: Data? = nil
        var linkFetchedAt: Date? = nil

        var notes: String = ""
        var isComplete: Bool = false
        var completedAt: Date? = nil
        /// Manual order inside the group.
        var sortIndex: Double = 0
        var createdAt: Date = Date.now

        var group: GroupModel? = nil

        init(
            uuid: UUID = UUID(),
            name: String = "",
            quantity: Int = 1,
            price: Decimal? = nil,
            currencyCode: String? = nil,
            exchangeRate: Decimal? = nil,
            urlString: String = "",
            notes: String = "",
            isComplete: Bool = false,
            completedAt: Date? = nil,
            sortIndex: Double = 0,
            createdAt: Date = .now
        ) {
            self.uuid = uuid
            self.name = name
            self.quantity = quantity
            self.price = price
            self.currencyCode = currencyCode
            self.exchangeRate = exchangeRate
            self.urlString = urlString
            self.notes = notes
            self.isComplete = isComplete
            self.completedAt = completedAt
            self.sortIndex = sortIndex
            self.createdAt = createdAt
        }
    }
}

extension ItemModel {
    var parentList: ListModel? {
        group?.list
    }

    /// Value snapshot for `BudgetCalculator`, which knows nothing about SwiftData.
    var budgetLine: BudgetLine {
        BudgetLine(
            price: price,
            quantity: quantity,
            isComplete: isComplete,
            currencyCode: currencyCode,
            exchangeRate: exchangeRate
        )
    }

    /// `price × quantity` in the list currency, or `nil` when it can't be computed
    /// (no price, or a foreign currency without a rate).
    var lineTotal: Decimal? {
        BudgetCalculator.lineTotal(
            of: budgetLine,
            listCurrencyCode: parentList?.currencyCode ?? ListModel.fallbackCurrencyCode
        )
    }

    var sortKey: PlannerOrdering.ItemKey {
        .init(isComplete: isComplete, sortIndex: sortIndex, createdAt: createdAt, completedAt: completedAt)
    }
}
