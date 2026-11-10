//
//  PlannerStore.swift
//  Project2
//
//  The service layer (spec 01 "Service layer", DM-11...DM-19).
//
//  Views read data with `@Query` / model properties, but every create, delete,
//  move and validated change goes through this store. That keeps business rules
//  (trimming, ranges, sortIndex, completedAt, cascade, error handling) in one
//  testable place instead of spreading them over SwiftUI views.
//
//  Plain text fields of an existing object (name, notes, link) may still be bound
//  directly to the model in edit forms; SwiftData autosaves them. Their final
//  value is normalised by `rename...` when the form is closed.
//

import Foundation
import OSLog
import SwiftData

/// The operations the UI needs. A protocol so tests (and a future v2 storage
/// based on CKSyncEngine / Core Data sharing) can provide another implementation.
@MainActor
protocol PlannerStoring: AnyObject {
    var lastErrorMessage: String? { get }
    func clearError()

    // Lists
    @discardableResult
    func createList(name: String, iconName: String?, iconKind: ListIconKind, color: FavoriteColor,
                    isPinned: Bool, budget: Decimal?, currencyCode: String?) -> ListModel
    func renameList(_ list: ListModel, to name: String)
    func setIcon(_ iconName: String, kind: ListIconKind, for list: ListModel)
    func setColor(_ color: FavoriteColor, for list: ListModel)
    @discardableResult func setBudget(_ budget: Decimal?, for list: ListModel) -> Bool
    func togglePin(_ list: ListModel)
    func moveList(in section: [ListModel], fromOffsets source: IndexSet, toOffset destination: Int)
    @discardableResult func duplicateList(_ list: ListModel) -> ListModel
    func deleteList(_ list: ListModel)

    // Groups
    @discardableResult func createGroup(name: String, in list: ListModel) -> GroupModel
    func renameGroup(_ group: GroupModel, to name: String)
    func moveGroup(in list: ListModel, fromOffsets source: IndexSet, toOffset destination: Int)
    func deleteGroup(_ group: GroupModel)

    // Items
    @discardableResult
    func addItem(name: String, to group: GroupModel, quantity: Int, price: Decimal?,
                 urlString: String, notes: String) -> ItemModel?
    func renameItem(_ item: ItemModel, to name: String)
    func setQuantity(_ quantity: Int, for item: ItemModel)
    @discardableResult func setPrice(_ price: Decimal?, for item: ItemModel) -> Bool
    func toggleComplete(_ item: ItemModel)
    func moveItem(_ item: ItemModel, to group: GroupModel)
    func moveItems(in group: GroupModel, fromOffsets source: IndexSet, toOffset destination: Int)
    func deleteItem(_ item: ItemModel)
}

@MainActor
@Observable
final class PlannerStore: PlannerStoring {

    // MARK: Validation rules

    nonisolated static let quantityRange = 1...999

    /// Trims leading/trailing whitespace; `nil` if nothing is left (DM-12).
    nonisolated static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func clampedQuantity(_ quantity: Int) -> Int {
        min(max(quantity, quantityRange.lowerBound), quantityRange.upperBound)
    }

    // MARK: State

    /// Last save error, shown by the UI as a non-blocking message (DM-17).
    private(set) var lastErrorMessage: String?

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    /// Currency for new lists. Spec 07 (M2) will feed the user's main currency here.
    @ObservationIgnored var defaultCurrencyCode: String

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Project2",
        category: "PlannerStore"
    )

    /// - Parameters:
    ///   - context: usually `container.mainContext`; tests pass an in-memory one.
    ///   - now: clock, injectable so tests can control `completedAt` / `createdAt`.
    init(
        context: ModelContext,
        defaultCurrencyCode: String = ListModel.fallbackCurrencyCode,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.defaultCurrencyCode = defaultCurrencyCode
        self.now = now
    }

    func clearError() {
        lastErrorMessage = nil
    }

    /// Saves pending changes. Never crashes: errors are logged and surfaced (DM-17).
    @discardableResult
    func save() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            Self.logger.error("Saving failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = String(localized: "Couldn't save your changes. Please try again.")
            return false
        }
    }

    // MARK: - Lists

    @discardableResult
    func createList(
        name: String,
        iconName: String? = nil,
        iconKind: ListIconKind = .symbol,
        color: FavoriteColor = .blue,
        isPinned: Bool = false,
        budget: Decimal? = nil,
        currencyCode: String? = nil
    ) -> ListModel {
        let list = ListModel(
            name: Self.normalizedName(name) ?? String(localized: "Untitled list"),
            iconName: iconName ?? "cart",
            iconKind: iconKind,
            color: color,
            isPinned: isPinned,
            sortIndex: PlannerOrdering.indexAfter(lists(pinned: isPinned).map(\.sortIndex)),
            budget: Self.validBudget(budget) ?? nil,
            currencyCode: currencyCode ?? defaultCurrencyCode,
            createdAt: now()
        )
        context.insert(list)
        save()
        return list
    }

    func renameList(_ list: ListModel, to name: String) {
        list.name = Self.normalizedName(name) ?? String(localized: "Untitled list")
        save()
    }

    func setIcon(_ iconName: String, kind: ListIconKind, for list: ListModel) {
        if iconName.isEmpty {
            list.iconName = "cart"
            list.iconKind = .symbol
        } else {
            list.iconName = iconName
            list.iconKind = kind
        }
        save()
    }

    func setColor(_ color: FavoriteColor, for list: ListModel) {
        list.color = color
        save()
    }

    /// Rejects a negative budget (the old value stays). `nil` removes the budget.
    @discardableResult
    func setBudget(_ budget: Decimal?, for list: ListModel) -> Bool {
        guard let valid = Self.validBudget(budget) else { return false }
        list.budget = valid
        save()
        return true
    }

    /// Pins/unpins and puts the list at the end of the section it moves into.
    func togglePin(_ list: ListModel) {
        let target = !list.isPinned
        list.sortIndex = PlannerOrdering.indexAfter(
            lists(pinned: target).filter { $0 !== list }.map(\.sortIndex)
        )
        list.isPinned = target
        save()
    }

    /// `section` must be the lists of one Home section in display order.
    func moveList(in section: [ListModel], fromOffsets source: IndexSet, toOffset destination: Int) {
        applyMove(section, fromOffsets: source, toOffset: destination)
    }

    /// Copies the list with all groups and items (DM-19). Items come back not completed.
    @discardableResult
    func duplicateList(_ list: ListModel) -> ListModel {
        let copy = ListModel(
            name: String(localized: "\(list.name) copy"),
            iconName: list.iconName,
            iconKind: list.iconKind,
            color: list.color,
            isPinned: list.isPinned,
            sortIndex: PlannerOrdering.indexAfter(lists(pinned: list.isPinned).map(\.sortIndex)),
            budget: list.budget,
            currencyCode: list.currencyCode,
            createdAt: now()
        )
        context.insert(copy)

        for group in list.sortedGroups {
            let groupCopy = GroupModel(
                name: group.name,
                sortIndex: group.sortIndex,
                budget: group.budget,
                createdAt: group.createdAt
            )
            context.insert(groupCopy)
            groupCopy.list = copy

            for item in group.items ?? [] {
                let itemCopy = ItemModel(
                    name: item.name,
                    quantity: item.quantity,
                    price: item.price,
                    currencyCode: item.currencyCode,
                    exchangeRate: item.exchangeRate,
                    urlString: item.urlString,
                    notes: item.notes,
                    isComplete: false,
                    completedAt: nil,
                    sortIndex: item.sortIndex,
                    createdAt: item.createdAt
                )
                itemCopy.linkTitle = item.linkTitle
                itemCopy.linkHost = item.linkHost
                itemCopy.linkImageData = item.linkImageData
                itemCopy.linkFetchedAt = item.linkFetchedAt
                context.insert(itemCopy)
                itemCopy.group = groupCopy
            }
        }
        save()
        return copy
    }

    /// Deletes the list with its groups and items (cascade, DM-08).
    /// The caller must close any screen that shows the list first (DM-18).
    func deleteList(_ list: ListModel) {
        context.delete(list)
        save()
    }

    // MARK: - Groups

    @discardableResult
    func createGroup(name: String, in list: ListModel) -> GroupModel {
        let group = GroupModel(
            name: Self.normalizedName(name) ?? String(localized: "Untitled group"),
            sortIndex: PlannerOrdering.indexAfter((list.groups ?? []).map(\.sortIndex)),
            createdAt: now()
        )
        context.insert(group)
        group.list = list
        save()
        return group
    }

    func renameGroup(_ group: GroupModel, to name: String) {
        group.name = Self.normalizedName(name) ?? String(localized: "Untitled group")
        save()
    }

    func moveGroup(in list: ListModel, fromOffsets source: IndexSet, toOffset destination: Int) {
        applyMove(list.sortedGroups, fromOffsets: source, toOffset: destination)
    }

    /// Deletes the group with its items (cascade, DM-08).
    func deleteGroup(_ group: GroupModel) {
        context.delete(group)
        save()
    }

    // MARK: - Items

    /// Adds an item at the end of the group. Returns `nil` for a blank name (DM-12).
    @discardableResult
    func addItem(
        name: String,
        to group: GroupModel,
        quantity: Int = 1,
        price: Decimal? = nil,
        urlString: String = "",
        notes: String = ""
    ) -> ItemModel? {
        guard let name = Self.normalizedName(name) else { return nil }
        let item = ItemModel(
            name: name,
            quantity: Self.clampedQuantity(quantity),
            price: Self.validPrice(price) ?? nil, // a negative price becomes "no price"
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            sortIndex: PlannerOrdering.indexAfter((group.items ?? []).map(\.sortIndex)),
            createdAt: now()
        )
        context.insert(item)
        item.group = group
        save()
        return item
    }

    func renameItem(_ item: ItemModel, to name: String) {
        item.name = Self.normalizedName(name) ?? String(localized: "Untitled item")
        save()
    }

    /// Out-of-range values are clamped to 1...999 (DM-13).
    func setQuantity(_ quantity: Int, for item: ItemModel) {
        let clamped = Self.clampedQuantity(quantity)
        guard item.quantity != clamped else { return }
        item.quantity = clamped
        save()
    }

    /// A negative price is rejected and the old value stays; `nil` stays `nil` (DM-14).
    @discardableResult
    func setPrice(_ price: Decimal?, for item: ItemModel) -> Bool {
        guard let valid = Self.validPrice(price) else { return false }
        guard item.price != valid else { return true }
        item.price = valid
        save()
        return true
    }

    /// Sets `completedAt` when checked and clears it when unchecked (DM-16).
    func toggleComplete(_ item: ItemModel) {
        item.isComplete.toggle()
        item.completedAt = item.isComplete ? now() : nil
        save()
    }

    /// Moves the item to the end of another group.
    func moveItem(_ item: ItemModel, to group: GroupModel) {
        guard item.group !== group else { return }
        item.sortIndex = PlannerOrdering.indexAfter((group.items ?? []).map(\.sortIndex))
        item.group = group
        save()
    }

    /// Reorders the not-completed items of a group (completed ones are ordered by `completedAt`).
    func moveItems(in group: GroupModel, fromOffsets source: IndexSet, toOffset destination: Int) {
        applyMove(group.incompleteItems, fromOffsets: source, toOffset: destination)
    }

    func deleteItem(_ item: ItemModel) {
        context.delete(item)
        save()
    }

    // MARK: - Helpers

    /// Lists of one Home section in display order.
    func lists(pinned: Bool) -> [ListModel] {
        let descriptor = FetchDescriptor<ListModel>(predicate: #Predicate { $0.isPinned == pinned })
        do {
            return PlannerOrdering.sortedLists(try context.fetch(descriptor))
        } catch {
            Self.logger.error("Fetching lists failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// `.some(value)` when acceptable (including `nil` = "no price"), `.none` when negative.
    private static func validPrice(_ price: Decimal?) -> Decimal?? {
        guard let price else { return .some(nil) }
        return price < 0 ? .none : .some(price)
    }

    private static func validBudget(_ budget: Decimal?) -> Decimal?? {
        validPrice(budget)
    }

    private func applyMove<Element: SortIndexed>(
        _ section: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        let changes = PlannerOrdering.reindexForMove(
            sortIndices: section.map(\.sortIndex),
            fromOffsets: source,
            toOffset: destination
        )
        guard !changes.isEmpty else { return }
        for (offset, index) in changes {
            section[offset].sortIndex = index
        }
        save()
    }
}

/// Models that are ordered by `sortIndex`.
protocol SortIndexed: AnyObject {
    var sortIndex: Double { get set }
}

extension ListModel: SortIndexed {}
extension GroupModel: SortIndexed {}
extension ItemModel: SortIndexed {}
