//
//  ListModel.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftData
import Foundation

@Model
final class ListModel {
    @Attribute(.unique) var uuid: UUID = UUID()

    var name: String
    var iconName: String = "🛒"
    var isFavorited: Bool
    var showCompleted: Bool = true
    var color: FavoriteColor = FavoriteColor.gray
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \GroupModel.list)
    var groups: [GroupModel] = [GroupModel]()

    // Используем totalAmount из GroupModel, который теперь суммирует ВСЕ товары
    var totalAmount: Decimal { groups.reduce(0) { $0 + $1.totalAmount } }

    
    // Используем completedAmount из GroupModel, который суммирует ТОЛЬКО завершенные товары
    var completedAmount: Decimal {
        groups.reduce(0) { result, group in
            result + group.completedAmount
        }
    }

    var remainingAmount: Decimal {
        totalAmount - completedAmount
    }
    
    init(name: String = "", isFavorited: Bool = false, groups: [GroupModel] = [], createdAt: Date = Date()) {
        self.name = name
        self.isFavorited = isFavorited
        self.groups = groups
        self.createdAt = createdAt
    }
}
