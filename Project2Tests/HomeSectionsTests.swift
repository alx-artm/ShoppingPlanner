//
//  HomeSectionsTests.swift
//  Project2Tests
//
//  Spec 02: what Home shows. Pinned lists as tiles and the others as rows
//  (HM-01), each section in sortIndex order with a new list first (HM-03,
//  BUG-18), duplicates first (HM-11), search over both sections (HM-13),
//  and the soft pin limit hint (HM-15).
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("HomeSections", .tags(.home))
struct HomeSectionsTests {
    let f: StoreFixture
    init() throws { f = try StoreFixture() }

    /// Every list in the store, in no particular order (like `@Query` without a sort).
    /// Shuffled with a fixed seed, so the test proves HomeSections sorts by itself.
    func allLists() throws -> [ListModel] {
        var rng = SeededGenerator(seed: 2026)
        return try f.context.fetch(FetchDescriptor<ListModel>()).shuffled(using: &rng)
    }

    // MARK: - HM-01 / HM-03

    @Test("HM-01 pinned lists are tiles, the others rows; no list is in both")
    func split() throws {
        f.store.createList(name: "A")
        f.store.createList(name: "P", isPinned: true)
        f.store.createList(name: "B")

        let sections = HomeSections(lists: try allLists())

        #expect(sections.pinned.map(\.name) == ["P"])
        #expect(Set(sections.others.map(\.name)) == ["A", "B"])
        #expect(sections.isEmpty == false)
    }

    @Test("HM-01 a section without lists is empty (Home hides it)")
    func emptySections() throws {
        #expect(HomeSections(lists: []).isEmpty)

        f.store.createList(name: "A")
        let noPinned = HomeSections(lists: try allLists())
        #expect(noPinned.pinned.isEmpty)
        #expect(noPinned.others.count == 1)
    }

    @Test("HM-03 each section follows sortIndex; a new list comes first in All Lists",
          .tags(.ordering))
    func newListFirst() throws {
        for name in ["First", "Second", "Third"] {
            f.store.createList(name: name)
            f.clock.advance(by: 60)
        }
        var draft = ListDraft(currencyCode: "USD")
        draft.name = "From List Info"
        f.store.createList(from: draft)

        let sections = HomeSections(lists: try allLists())
        #expect(sections.others.map(\.name) == ["From List Info", "Third", "Second", "First"])
    }

    @Test("BUG-18 order is sortIndex then createdAt, never the name", .tags(.ordering, .regression))
    func notByName() throws {
        // Same sortIndex: the older list comes first, whatever the names are.
        let date = SeedData.baseDate
        for (offset, name) in ["Zulu", "alpha", "Mike"].enumerated() {
            f.context.insert(ListModel(name: name, sortIndex: 5, createdAt: date.addingTimeInterval(Double(offset))))
        }
        f.context.insert(ListModel(name: "Yankee", sortIndex: 1, createdAt: date.addingTimeInterval(100)))
        try f.context.save()

        let sections = HomeSections(lists: try allLists())
        #expect(sections.others.map(\.name) == ["Yankee", "Zulu", "alpha", "Mike"])
    }

    @Test("HM-08 pinning moves a list to the end of Pinned and out of All Lists", .tags(.ordering))
    func pinMovesSection() throws {
        f.store.createList(name: "P1", isPinned: true)
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B")

        f.store.togglePin(a)
        var sections = HomeSections(lists: try allLists())
        #expect(sections.pinned.map(\.name) == ["P1", "A"])
        #expect(sections.others.map(\.name) == ["B"])

        f.store.togglePin(a)
        sections = HomeSections(lists: try allLists())
        #expect(sections.pinned.map(\.name) == ["P1"])
        #expect(sections.others.map(\.name) == ["B", "A"])
    }

    @Test("HM-11 a duplicate is unpinned and comes first in All Lists", .tags(.ordering))
    func duplicateFirst() throws {
        let pinned = f.store.createList(name: "Trip", isPinned: true)
        f.store.createList(name: "Other")

        let copy = f.store.duplicateList(pinned)

        let sections = HomeSections(lists: try allLists())
        #expect(sections.pinned.map(\.name) == ["Trip"])
        #expect(sections.others.first === copy)
        #expect(sections.others.count == 2)
    }

    @Test("HM-03 the order after moveList is what Home shows", .tags(.ordering))
    func moveIsShown() throws {
        for name in ["A", "B", "C"] { f.store.createList(name: name) } // C, B, A
        f.store.moveList(in: HomeSections(lists: try allLists()).others, fromOffsets: [0], toOffset: 3)
        #expect(HomeSections(lists: try allLists()).others.map(\.name) == ["B", "A", "C"])
    }

    // MARK: - HM-15

    @Test("HM-15 the pinned hint shows above 6 pinned lists; pinning is never blocked",
          arguments: [(0, false), (5, false), (6, false), (7, true), (9, true)])
    func pinnedSoftLimit(count: Int, hint: Bool) throws {
        for index in 0..<count { f.store.createList(name: "P\(index)", isPinned: true) }
        let sections = HomeSections(lists: try allLists())
        #expect(sections.pinned.count == count)
        #expect(sections.exceedsPinnedSoftLimit == hint)
    }

    // MARK: - HM-13 search

    struct SearchCase: CustomTestStringConvertible, Sendable {
        let name: String
        let query: String
        let matches: Bool
        var testDescription: String { "\"\(query)\" in \"\(name)\" → \(matches)" }
    }

    nonisolated static let searchCases: [SearchCase] = [
        SearchCase(name: "Kids Room", query: "", matches: true),
        SearchCase(name: "Kids Room", query: "   ", matches: true),
        SearchCase(name: "Kids Room", query: "room", matches: true),
        SearchCase(name: "Kids Room", query: "ROOM", matches: true),
        SearchCase(name: "Kids Room", query: "ds ro", matches: true),
        SearchCase(name: "Kids Room", query: "  kids  ", matches: true),
        SearchCase(name: "Kids Room", query: "rooms", matches: false),
        SearchCase(name: "Café", query: "cafe", matches: true),
        SearchCase(name: "Cafe", query: "café", matches: true),
        SearchCase(name: "Ёлка", query: "елка", matches: true),
        SearchCase(name: "Детская комната", query: "КОМН", matches: true),
        SearchCase(name: "Trip 🏖️", query: "🏖️", matches: true),
        SearchCase(name: "Trip", query: "x", matches: false),
    ]

    @Test("HM-13 search is a substring match ignoring case and diacritics; blank matches all",
          arguments: searchCases)
    func matching(_ c: SearchCase) {
        #expect(HomeSections.matches(c.name, query: c.query) == c.matches)
    }

    @Test("HM-13 search filters both sections and keeps their order")
    func searchBothSections() throws {
        f.store.createList(name: "Garden tools", isPinned: true)
        f.store.createList(name: "Kitchen", isPinned: true)
        f.store.createList(name: "Garden plants")
        f.store.createList(name: "Gifts")
        f.store.createList(name: "Garden furniture") // first in All Lists

        let sections = HomeSections(lists: try allLists(), query: "GARDEN")

        #expect(sections.pinned.map(\.name) == ["Garden tools"])
        #expect(sections.others.map(\.name) == ["Garden furniture", "Garden plants"])
    }

    @Test("HM-13 no match: both sections are empty (Home shows ContentUnavailableView.search)")
    func searchNoResults() throws {
        f.store.createList(name: "A", isPinned: true)
        f.store.createList(name: "B")
        let sections = HomeSections(lists: try allLists(), query: "zzz")
        #expect(sections.isEmpty)
    }
}
