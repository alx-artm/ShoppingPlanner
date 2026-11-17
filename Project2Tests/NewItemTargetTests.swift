//
//  NewItemTargetTests.swift
//  Project2Tests
//
//  ⌘N on iPad (spec 08 AD-12, M4 plan Q5 → A): which group gets the new item.
//  The last-added group, else the first expanded, else the first; no groups → nil (LD-05a).
//

import Foundation
import Testing
@testable import Project2

@Suite("⌘N target group", .tags(.ordering))
@MainActor
struct NewItemTargetTests {

    typealias Candidate = NewItemTarget.Candidate

    static let ids = (0..<4).map { _ in UUID() }
    static func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test("no groups → nil, the caller makes the \"Items\" group (LD-05a)")
    func noGroups() {
        #expect(NewItemTarget.groupID(in: []) == nil)
    }

    @Test("the group with the newest item wins, even when it is collapsed or not first")
    func lastAddedWins() {
        let groups = [
            Candidate(id: Self.ids[0], isExpanded: true, lastItemAddedAt: Self.date(100)),
            Candidate(id: Self.ids[1], isExpanded: false, lastItemAddedAt: Self.date(300)),
            Candidate(id: Self.ids[2], isExpanded: true, lastItemAddedAt: Self.date(200)),
        ]
        #expect(NewItemTarget.groupID(in: groups) == Self.ids[1])
    }

    @Test("empty groups don't count as \"added to last\"")
    func emptyGroupsIgnored() {
        let groups = [
            Candidate(id: Self.ids[0], isExpanded: true, lastItemAddedAt: nil),
            Candidate(id: Self.ids[1], isExpanded: true, lastItemAddedAt: Self.date(100)),
            Candidate(id: Self.ids[2], isExpanded: true, lastItemAddedAt: nil),
        ]
        #expect(NewItemTarget.groupID(in: groups) == Self.ids[1])
    }

    @Test("a tie goes to the group shown first")
    func tieGoesToFirst() {
        let groups = [
            Candidate(id: Self.ids[0], isExpanded: true, lastItemAddedAt: Self.date(100)),
            Candidate(id: Self.ids[1], isExpanded: true, lastItemAddedAt: Self.date(100)),
        ]
        #expect(NewItemTarget.groupID(in: groups) == Self.ids[0])
    }

    @Test("no items anywhere → the first expanded group")
    func firstExpanded() {
        let groups = [
            Candidate(id: Self.ids[0], isExpanded: false, lastItemAddedAt: nil),
            Candidate(id: Self.ids[1], isExpanded: true, lastItemAddedAt: nil),
            Candidate(id: Self.ids[2], isExpanded: true, lastItemAddedAt: nil),
        ]
        #expect(NewItemTarget.groupID(in: groups) == Self.ids[1])
    }

    @Test("no items and every group collapsed → the first group")
    func allCollapsed() {
        let groups = [
            Candidate(id: Self.ids[0], isExpanded: false, lastItemAddedAt: nil),
            Candidate(id: Self.ids[1], isExpanded: false, lastItemAddedAt: nil),
        ]
        #expect(NewItemTarget.groupID(in: groups) == Self.ids[0])
    }

    @Test("a group's candidate takes the newest createdAt of the items in it now")
    func candidateFromGroup() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let old = fixture.addItem("Old", to: group)
        let new = fixture.addItem("New", to: group)
        old.createdAt = Self.date(100)
        new.createdAt = Self.date(500)

        let candidate = Candidate(group, isExpanded: false)
        #expect(candidate.id == group.uuid)
        #expect(candidate.lastItemAddedAt == Self.date(500))
        #expect(candidate.isExpanded == false)

        let (_, empty) = fixture.makeGroup()
        #expect(Candidate(empty, isExpanded: true).lastItemAddedAt == nil)
    }
}
