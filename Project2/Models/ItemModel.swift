//
//  Models.swift
//  Project #2
//
//

import SwiftData
import Foundation

@Model
final class ItemModel {
    var name: String
    var quantity: Int
    var price: Decimal?
    
    var totalPrice: Decimal {
        (price ?? 0) * Decimal(quantity)
    }
    
    var url: String = ""
    var notes: String = ""
    var isComplete: Bool = false
    
    var group: GroupModel?
    
    var createdAt: Date
    var completedAt: Date?
    
    init(name: String, quantity: Int = 1, price: Decimal? = nil, url: String = "", notes: String = "", isComplete: Bool = false, group: GroupModel? = nil, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.name = name
        self.quantity = quantity
        self.price = price
        self.url = url
        self.notes = notes
        self.isComplete = isComplete
        self.group = group
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

    // MARK: тут можем узнать к какому листу принадлежит Item, также смотри как можно узнать это другим способом в файле вью "ItemView"
extension ItemModel {
    var parentList: ListModel? {
        return group?.list
    }
    
    var listName: String {
        return parentList?.name ?? "No list"
    }
}
