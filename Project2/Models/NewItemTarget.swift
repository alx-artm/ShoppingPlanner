//
//  NewItemTarget.swift
//  Project2
//
//  Which group ⌘N adds a new item to (spec 08 AD-12, M4 plan Q5 → A):
//  the group an item was added to last; otherwise the first expanded group;
//  otherwise the first group. `nil` means the list has no groups, and the
//  caller follows LD-05a (a new "Items" group for the first item).
//

import Foundation

enum NewItemTarget {
    /// What the rule needs to know about one group, in display order.
    struct Candidate: Equatable {
        let id: UUID
        let isExpanded: Bool
        /// When the newest item that is in this group now was added; `nil` for an empty group.
        let lastItemAddedAt: Date?
    }

    /// The group for ⌘N, or `nil` when there are no groups (LD-05a).
    /// - Parameter groups: the list's groups in display order.
    static func groupID(in groups: [Candidate]) -> UUID? {
        // `max(by:)` returns the last of equal elements; keep the first in display order instead.
        let lastAdded = groups.reduce(nil as Candidate?) { best, group in
            guard let date = group.lastItemAddedAt else { return best }
            guard let bestDate = best?.lastItemAddedAt else { return group }
            return date > bestDate ? group : best
        }
        if let lastAdded { return lastAdded.id }
        // Only empty groups: the first one the user can see, else simply the first.
        return (groups.first(where: \.isExpanded) ?? groups.first)?.id
    }
}

extension NewItemTarget.Candidate {
    /// A group of the list with its expanded state from `LocalUIState`.
    init(_ group: GroupModel, isExpanded: Bool) {
        self.init(id: group.uuid, isExpanded: isExpanded,
                  lastItemAddedAt: (group.items ?? []).map(\.createdAt).max())
    }
}
