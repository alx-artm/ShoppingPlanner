//
//  GroupModel.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftData
import Foundation

@Model
final class GroupModel {
    var name: String

    var isExpanded: Bool
    
    var list: ListModel?

    @Relationship(deleteRule: .cascade, inverse: \ItemModel.group)
    var items: [ItemModel] = [ItemModel]()

    var sortedItems: [ItemModel] { items.sorted() }

    var itemsNotComplete: [ItemModel] { sortedItems.filter { !$0.isComplete } }

    // MARK: ИСПРАВЛЕНИЕ 1: totalAmount должен быть суммой ВСЕХ товаров в группе
    var totalAmount: Decimal {
        items.reduce(0) { $0 + $1.totalPrice }
    }

    // MARK: ИСПРАВЛЕНИЕ 2: Добавлено completedAmount для группы
    var completedAmount: Decimal {
        items.filter { $0.isComplete }.reduce(0) { $0 + $1.totalPrice }
    }

    var remainingAmount: Decimal {
        totalAmount - completedAmount
    }
    
    init(name: String = "", isExpanded: Bool = true, list: ListModel? = nil, items: [ItemModel] = []) {
        self.name = name
        self.isExpanded = isExpanded
        self.list = list
        self.items = items
    }
}



/*
- Сначала false < true, т.е. невыполненные выше.
- Среди невыполненных: сортируем по createdAt ↑ (старее выше).
- Среди выполненных: сортируем по completedAt ↑ (кто раньше выполнил — выше).
- Если completedAt у кого-то nil (что в принципе не должно быть), мы ставим .distantFuture, чтобы они оказались в конце.
 */

extension ItemModel: Comparable {
    static func < (lhs: ItemModel, rhs: ItemModel) -> Bool {
        switch (lhs.isComplete, rhs.isComplete) {
        case (false, true):
            return true
        case (true, false):
            return false
        case (false, false):
            return lhs.createdAt < rhs.createdAt
        case (true, true):
            // Безопасно сравним completedAt — если нет даты, считаем "меньше"
            return (lhs.completedAt ?? .distantFuture) < (rhs.completedAt ?? .distantFuture)
        }
    }
}

// важно для сравнения Bool, иначе расширение выше вообще не будет компилиться
// тут  false < true
extension Bool: @retroactive Comparable {
    public static func <(lhs: Self, rhs: Self) -> Bool {
        !lhs && rhs
    }
}

extension Decimal {
    var doubleValue: Double {
        (self as NSDecimalNumber).doubleValue
    }
}
