//
//  PlannerOrdering.swift
//  Project2
//
//  Explicit ordering rules (spec 01 "Sorting", DM-06, DM-07, DM-15).
//
//  SwiftData (and CloudKit) to-many relationships are unordered sets, so the
//  array order of `list.groups` / `group.items` means nothing. Every screen
//  sorts with these functions instead.
//

import Foundation

enum PlannerOrdering {

    // MARK: - Sort keys (value types, easy to unit-test)

    struct ItemKey: Equatable, Sendable {
        var isComplete: Bool
        var sortIndex: Double
        var createdAt: Date
        var completedAt: Date?
    }

    struct EntryKey: Equatable, Sendable {
        var sortIndex: Double
        var createdAt: Date
    }

    /// Not completed items first, by `sortIndex` then `createdAt`.
    /// Completed items after them, by `completedAt` (missing dates last).
    static func itemPrecedes(_ lhs: ItemKey, _ rhs: ItemKey) -> Bool {
        if lhs.isComplete != rhs.isComplete {
            return !lhs.isComplete
        }
        if lhs.isComplete {
            let left = lhs.completedAt ?? .distantFuture
            let right = rhs.completedAt ?? .distantFuture
            if left != right { return left < right }
        }
        return entryPrecedes(
            EntryKey(sortIndex: lhs.sortIndex, createdAt: lhs.createdAt),
            EntryKey(sortIndex: rhs.sortIndex, createdAt: rhs.createdAt)
        )
    }

    /// Lists and groups: `sortIndex`, then `createdAt`.
    static func entryPrecedes(_ lhs: EntryKey, _ rhs: EntryKey) -> Bool {
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        return lhs.createdAt < rhs.createdAt
    }

    // MARK: - Model helpers

    static func sortedItems(_ items: [ItemModel]) -> [ItemModel] {
        items.sorted { itemPrecedes($0.sortKey, $1.sortKey) }
    }

    static func sortedGroups(_ groups: [GroupModel]) -> [GroupModel] {
        groups.sorted {
            entryPrecedes(.init(sortIndex: $0.sortIndex, createdAt: $0.createdAt),
                          .init(sortIndex: $1.sortIndex, createdAt: $1.createdAt))
        }
    }

    static func sortedLists(_ lists: [ListModel]) -> [ListModel] {
        lists.sorted {
            entryPrecedes(.init(sortIndex: $0.sortIndex, createdAt: $0.createdAt),
                          .init(sortIndex: $1.sortIndex, createdAt: $1.createdAt))
        }
    }

    // MARK: - sortIndex arithmetic

    /// Smallest gap between neighbours before a section has to be renumbered.
    static let minimumGap = 1e-6

    /// `sortIndex` for a new element appended after `existing`: max + 1 (0 for an empty section).
    static func indexAfter(_ existing: [Double]) -> Double {
        (existing.max() ?? -1) + 1
    }

    /// `sortIndex` for an element placed between two neighbours (`nil` = no neighbour on that side).
    /// Returns `nil` when the gap is too small and the section must be renumbered.
    static func indexBetween(_ lower: Double?, _ upper: Double?) -> Double? {
        switch (lower, upper) {
        case (nil, nil):
            return 0
        case let (lower?, nil):
            return lower + 1
        case let (nil, upper?):
            return upper - 1
        case let (lower?, upper?):
            guard upper - lower >= minimumGap else { return nil }
            return (lower + upper) / 2
        }
    }

    /// New `sortIndex` values after moving elements of an already sorted section,
    /// with the semantics of SwiftUI's `onMove(fromOffsets:toOffset:)`.
    ///
    /// The result maps an element's offset in `sortIndices` (the old order) to its
    /// new `sortIndex`, and contains only elements that change. Moving a single
    /// element changes only that element (DM-07); if the gap is exhausted, or
    /// several elements move at once, the section is renumbered 0, 1, 2, ...
    static func reindexForMove(
        sortIndices: [Double],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Int: Double] {
        let order = movedOrder(count: sortIndices.count, fromOffsets: source, toOffset: destination)

        if source.count == 1, let moved = source.first,
           let position = order.firstIndex(of: moved) {
            let lower = position > 0 ? sortIndices[order[position - 1]] : nil
            let upper = position < order.count - 1 ? sortIndices[order[position + 1]] : nil
            if let index = indexBetween(lower, upper) {
                return index == sortIndices[moved] ? [:] : [moved: index]
            }
        }

        var changes: [Int: Double] = [:]
        for (position, original) in order.enumerated() where sortIndices[original] != Double(position) {
            changes[original] = Double(position)
        }
        return changes
    }

    /// Old offsets in their new order after the move (same rules as `onMove`).
    static func movedOrder(count: Int, fromOffsets source: IndexSet, toOffset destination: Int) -> [Int] {
        let valid = source.filteredIndexSet { $0 >= 0 && $0 < count }
        let moving = Array(valid)
        var remaining = (0..<count).filter { !valid.contains($0) }
        let clamped = min(max(destination, 0), count)
        let insertAt = clamped - valid.count(in: 0..<clamped)
        remaining.insert(contentsOf: moving, at: insertAt)
        return remaining
    }
}
