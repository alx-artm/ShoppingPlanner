//
//  QuickItemModel.swift
//  Project #2
//
//  Created by Alex on 11.06.25.
//

import Foundation
import SwiftData

@Model
final class QuickItemModel {
    var name: String
    var quantity: Int
    var isComplete: Bool
    var createdAt: Date
    var completedAt: Date?
    var position: Int
    
    
    init(name: String, quantity: Int = 1, isComplete: Bool = false, createdAt: Date = Date(), completedAt: Date? = nil, position: Int = 0) {
        self.name = name
        self.quantity = quantity
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.position = position
    }
}

extension QuickItemModel: Comparable {
    static func < (lhs: QuickItemModel, rhs: QuickItemModel) -> Bool {
        (lhs.isComplete, lhs.name) < (rhs.isComplete, rhs.name)
    }
}
