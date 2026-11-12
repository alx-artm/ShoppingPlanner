//
//  ListDraft.swift
//  Project2
//
//  The values edited on the List Info screen (spec 03). The screen edits this
//  copy, never the model, so Cancel throws every change away (LI-02) and
//  nothing is inserted before ✓ (LI-01). `PlannerStore` applies it on ✓.
//

import Foundation

struct ListDraft: Equatable, Sendable {
    var name: String = ""
    var iconName: String = "cart"
    var iconKind: ListIconKind = .symbol
    var color: FavoriteColor = .blue
    /// `nil` = no budget; 0 is a real budget (LI-08).
    var budget: Decimal?
    var isPinned: Bool = false
    /// Read-only on the screen in v1 (changing a list's currency is v1.1).
    var currencyCode: String
    /// Empty groups created together with a new list (templates, LI-12).
    var groupNames: [String] = []

    /// A new list: blue, "cart" symbol, main currency, not pinned (LI-03).
    init(currencyCode: String) {
        self.currencyCode = currencyCode
    }

    /// The current values of an existing list.
    init(list: ListModel) {
        name = list.name
        iconName = list.iconName
        iconKind = list.iconKind
        color = list.color
        budget = list.budget
        isPinned = list.isPinned
        currencyCode = list.currencyCode
    }

    /// A new list prefilled from a template (LI-12).
    init(template: ListTemplate, currencyCode: String) {
        self.init(currencyCode: currencyCode)
        name = template.name
        iconName = template.iconName
        iconKind = .symbol
        color = template.color
        groupNames = template.groupNames
    }

    /// The name is not blank after trimming (LI-01).
    var hasValidName: Bool {
        PlannerStore.normalizedName(name) != nil
    }

    /// No budget, or a budget ≥ 0 (LI-08).
    var hasValidBudget: Bool {
        budget.map { $0 >= 0 } ?? true
    }

    /// ✓ is enabled only for a draft the store will accept as is.
    var canSave: Bool {
        hasValidName && hasValidBudget
    }
}
