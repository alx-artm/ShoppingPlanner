//
//  HomeSections.swift
//  Project2
//
//  What Home shows (spec 02): pinned lists as tiles, the others as rows, both
//  in `sortIndex` order (HM-01, HM-03), filtered by the search text (HM-13).
//  Archived lists (spec 10) are in neither section: Home shows only an
//  "Archive" row for them, and a separate "In Archive" section while searching.
//

import Foundation

struct HomeSections {
    /// Above this many pinned lists Home shows a gentle hint (HM-15); pinning is never blocked.
    static let pinnedSoftLimit = 6

    /// Active pinned lists that match the query.
    let pinned: [ListModel]
    /// Active not pinned lists that match the query.
    let others: [ListModel]
    /// Archived lists that match a non-blank query, newest archived first (AR-20).
    /// Empty without a query: then Home shows the Archive row instead.
    let archiveMatches: [ListModel]
    /// All archived lists, whatever the query: the counter of the Archive row (AR-08).
    let archivedCount: Int
    /// At least one active list exists, whatever the query.
    let hasActiveLists: Bool
    /// The query is not blank.
    let isSearching: Bool

    init(lists: [ListModel], query: String = "") {
        let active = lists.filter { !$0.isArchived }
        let archived = lists.filter(\.isArchived)
        let matching = active.filter { Self.matches($0.name, query: query) }
        pinned = PlannerOrdering.sortedLists(matching.filter(\.isPinned))
        others = PlannerOrdering.sortedLists(matching.filter { !$0.isPinned })
        isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        archiveMatches = isSearching ? Self.archived(archived, query: query) : []
        archivedCount = archived.count
        hasActiveLists = !active.isEmpty
    }

    /// No active list matches (or none exists).
    var isEmpty: Bool { pinned.isEmpty && others.isEmpty }

    /// More pinned lists than the soft limit (HM-15).
    var exceedsPinnedSoftLimit: Bool { pinned.count > Self.pinnedSoftLimit }

    /// "Reorder Lists" has something to do: a list moves only inside its section,
    /// so at least one section needs two lists (HM-32, HM-35). Archived lists are
    /// in no section, so they never count.
    var canReorder: Bool { pinned.count >= 2 || others.count >= 2 }

    /// The "Archive N" row, last on Home: only with archived lists (AR-08), and not while
    /// searching, where the "In Archive" section shows the matching ones (AR-20).
    var showsArchiveRow: Bool { archivedCount > 0 && !isSearching }

    /// "No Active Lists" (AR-13): every list is archived. The onboarding empty state
    /// (HM-14) is only for a store without any list.
    var showsNoActiveLists: Bool { !hasActiveLists && archivedCount > 0 && !isSearching }

    /// "No Results" for a search: nothing matches, neither active nor archived (AR-20).
    var showsNoSearchResults: Bool { isSearching && isEmpty && archiveMatches.isEmpty }

    /// Archived lists matching `query` (all for a blank one), the last archived first (AR-15).
    static func archived(_ lists: [ListModel], query: String = "") -> [ListModel] {
        PlannerOrdering.sortedArchivedLists(
            lists.filter { $0.isArchived && matches($0.name, query: query) }
        )
    }

    /// Substring match ignoring case and diacritics ("cafe" finds "Café"). A blank query matches everything.
    static func matches(_ name: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
