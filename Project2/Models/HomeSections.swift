//
//  HomeSections.swift
//  Project2
//
//  What Home shows (spec 02): pinned lists as tiles, the others as rows, both
//  in `sortIndex` order (HM-01, HM-03), filtered by the search text (HM-13).
//

import Foundation

struct HomeSections {
    /// Above this many pinned lists Home shows a gentle hint (HM-15); pinning is never blocked.
    static let pinnedSoftLimit = 6

    let pinned: [ListModel]
    let others: [ListModel]

    init(lists: [ListModel], query: String = "") {
        let matching = lists.filter { Self.matches($0.name, query: query) }
        pinned = PlannerOrdering.sortedLists(matching.filter(\.isPinned))
        others = PlannerOrdering.sortedLists(matching.filter { !$0.isPinned })
    }

    var isEmpty: Bool { pinned.isEmpty && others.isEmpty }

    /// More pinned lists than the soft limit (HM-15).
    var exceedsPinnedSoftLimit: Bool { pinned.count > Self.pinnedSoftLimit }

    /// Substring match ignoring case and diacritics ("cafe" finds "Café"). A blank query matches everything.
    static func matches(_ name: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
