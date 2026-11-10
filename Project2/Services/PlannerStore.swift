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
    @discardableResult func createList(from draft: ListDraft) -> ListModel
    func updateList(_ list: ListModel, with draft: ListDraft)
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
    /// Reads the user's main currency (spec 07) at the moment a list is created.
    @ObservationIgnored private let mainCurrencyCode: @MainActor () -> String

    /// Currency copied into new lists: the main currency right now (SC-05).
    var defaultCurrencyCode: String {
        mainCurrencyCode()
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Project2",
        category: "PlannerStore"
    )

    /// - Parameters:
    ///   - context: usually `container.mainContext`; tests pass an in-memory one.
    ///   - mainCurrencyCode: asked on every `createList`, so a changed setting is
    ///     used for the next list without rebuilding the store.
    ///   - now: clock, injectable so tests can control `completedAt` / `createdAt`.
    init(
        context: ModelContext,
        mainCurrencyCode: @escaping @MainActor () -> String,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.mainCurrencyCode = mainCurrencyCode
        self.now = now
    }

    /// A store whose new lists always get `defaultCurrencyCode` (tests, previews).
    convenience init(
        context: ModelContext,
        defaultCurrencyCode: String = ListModel.fallbackCurrencyCode,
        now: @escaping () -> Date = { .now }
    ) {
        self.init(context: context, mainCurrencyCode: { defaultCurrencyCode }, now: now)
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
            sortIndex: newListSortIndex(pinned: isPinned),
            budget: Self.validBudget(budget) ?? nil,
            currencyCode: currencyCode ?? defaultCurrencyCode,
            createdAt: now()
        )
        context.insert(list)
        save()
        return list
    }

    /// Creates the list from List Info (spec 03), with the template's empty groups in order.
    @discardableResult
    func createList(from draft: ListDraft) -> ListModel {
        let list = createList(
            name: draft.name,
            iconName: draft.iconName,
            iconKind: draft.iconKind,
            color: draft.color,
            isPinned: draft.isPinned,
            budget: draft.budget,
            currencyCode: draft.currencyCode
        )
        for name in draft.groupNames {
            createGroup(name: name, in: list)
        }
        return list
    }

    /// Applies List Info's ✓ to an existing list in one save (LI-02).
    /// The currency is not changed (v1.1); a negative budget keeps the old one.
    func updateList(_ list: ListModel, with draft: ListDraft) {
        list.name = Self.normalizedName(draft.name) ?? String(localized: "Untitled list")
        if draft.iconName.isEmpty {
            list.iconName = "cart"
            list.iconKind = .symbol
        } else {
            list.iconName = draft.iconName
            list.iconKind = draft.iconKind
        }
        list.color = draft.color
        if let budget = Self.validBudget(draft.budget) {
            list.budget = budget
        }
        if list.isPinned != draft.isPinned {
            movePin(of: list, to: draft.isPinned)
        }
        save()
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

    /// Pins/unpins and puts the list at the end of the section it moves into (HM-08).
    func togglePin(_ list: ListModel) {
        movePin(of: list, to: !list.isPinned)
        save()
    }

    /// `section` must be the lists of one Home section in display order.
    func moveList(in section: [ListModel], fromOffsets source: IndexSet, toOffset destination: Int) {
        applyMove(section, fromOffsets: source, toOffset: destination)
    }

    /// Copies the list with all groups and items (DM-19). Items come back not completed.
    /// The copy is not pinned and comes first in "All Lists" (HM-11).
    @discardableResult
    func duplicateList(_ list: ListModel) -> ListModel {
        let copy = ListModel(
            name: String(localized: "\(list.name) copy"),
            iconName: list.iconName,
            iconKind: list.iconKind,
            color: list.color,
            isPinned: false,
            sortIndex: newListSortIndex(pinned: false),
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

    /// A new list goes first in "All Lists" (HM-03), or last in "Pinned".
    private func newListSortIndex(pinned: Bool) -> Double {
        let section = lists(pinned: pinned).map(\.sortIndex)
        return pinned ? PlannerOrdering.indexAfter(section) : PlannerOrdering.indexBefore(section)
    }

    /// Moves the list to the end of the pinned / all section. Doesn't save.
    private func movePin(of list: ListModel, to pinned: Bool) {
        list.sortIndex = PlannerOrdering.indexAfter(
            lists(pinned: pinned).filter { $0 !== list }.map(\.sortIndex)
        )
        list.isPinned = pinned
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
