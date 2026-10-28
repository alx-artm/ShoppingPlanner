//
//  PlannerOrderingTests.swift
//  Project2Tests
//
//  Spec 01 "Sorting": DM-06 (order only from sortIndex/createdAt),
//  DM-07 (a move changes one sortIndex, or renumbers), DM-15 (explicit comparator).
//

import Foundation
import Testing
@testable import Project2

@Suite("PlannerOrdering", .tags(.ordering))
struct PlannerOrderingTests {

    private let t0 = SeedData.baseDate

    // MARK: - Comparators (DM-15, DM-06)

    @Test("DM-15 not completed items come before completed ones")
    func incompleteBeforeComplete() {
        let open = PlannerOrdering.ItemKey(isComplete: false, sortIndex: 99, createdAt: t0, completedAt: nil)
        let done = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 0, createdAt: t0, completedAt: t0)

        #expect(PlannerOrdering.itemPrecedes(open, done))
        #expect(!PlannerOrdering.itemPrecedes(done, open))
    }

    @Test("DM-15 not completed items: by sortIndex, then createdAt")
    func incompleteBySortIndexThenCreatedAt() {
        let a = PlannerOrdering.ItemKey(isComplete: false, sortIndex: 1, createdAt: t0.addingTimeInterval(100), completedAt: nil)
        let b = PlannerOrdering.ItemKey(isComplete: false, sortIndex: 2, createdAt: t0, completedAt: nil)
        let c = PlannerOrdering.ItemKey(isComplete: false, sortIndex: 2, createdAt: t0.addingTimeInterval(1), completedAt: nil)

        #expect(PlannerOrdering.itemPrecedes(a, b))
        #expect(PlannerOrdering.itemPrecedes(b, c))
        #expect(!PlannerOrdering.itemPrecedes(c, b))
    }

    @Test("DM-15 completed items: by completedAt, missing dates last")
    func completedByCompletedAt() {
        let early = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 5, createdAt: t0, completedAt: t0)
        let late = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 0, createdAt: t0, completedAt: t0.addingTimeInterval(60))
        let undated = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 0, createdAt: t0, completedAt: nil)

        #expect(PlannerOrdering.itemPrecedes(early, late))
        #expect(PlannerOrdering.itemPrecedes(late, undated))
        #expect(!PlannerOrdering.itemPrecedes(undated, early))
    }

    @Test("DM-15 completed with equal completedAt fall back to sortIndex")
    func completedTieBreak() {
        let a = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 0, createdAt: t0, completedAt: t0)
        let b = PlannerOrdering.ItemKey(isComplete: true, sortIndex: 1, createdAt: t0, completedAt: t0)
        #expect(PlannerOrdering.itemPrecedes(a, b))
    }

    @Test("DM-06 entries: sortIndex first, createdAt breaks ties, irreflexive")
    func entryOrder() {
        let a = PlannerOrdering.EntryKey(sortIndex: 0, createdAt: t0.addingTimeInterval(10))
        let b = PlannerOrdering.EntryKey(sortIndex: 1, createdAt: t0)
        let c = PlannerOrdering.EntryKey(sortIndex: 1, createdAt: t0.addingTimeInterval(1))

        #expect(PlannerOrdering.entryPrecedes(a, b))
        #expect(PlannerOrdering.entryPrecedes(b, c))
        #expect(!PlannerOrdering.entryPrecedes(b, b))
    }

    // MARK: - indexAfter / indexBetween

    @Test("indexAfter: max + 1, 0 for an empty section", arguments: [
        ([Double](), 0.0),
        ([0], 1),
        ([3, 1, 2], 4),
        ([-5, -2.5], -1.5),
    ] as [([Double], Double)])
    func indexAfter(existing: [Double], expected: Double) {
        #expect(PlannerOrdering.indexAfter(existing) == expected)
    }

    @Test("DM-07 indexBetween: insert between neighbours", arguments: [
        (nil, nil, 0.0),
        (2.0, nil, 3.0),
        (nil, 2.0, 1.0),
        (1.0, 2.0, 1.5),
        (-1.0, 0.0, -0.5),
    ] as [(Double?, Double?, Double?)])
    func indexBetween(lower: Double?, upper: Double?, expected: Double?) throws {
        let index = try #require(PlannerOrdering.indexBetween(lower, upper))
        #expect(index == expected)
        if let lower { #expect(index > lower) }
        if let upper { #expect(index < upper) }
    }

    @Test("DM-07 indexBetween returns nil when the gap is exhausted")
    func gapExhausted() {
        #expect(PlannerOrdering.indexBetween(1, 1 + PlannerOrdering.minimumGap / 2) == nil)
        #expect(PlannerOrdering.indexBetween(1, 1) == nil)
        #expect(PlannerOrdering.indexBetween(1, 1 + 2 * PlannerOrdering.minimumGap) != nil)
    }

    @Test("DM-07 repeated inserts at the front eventually need renumbering, never return a wrong value")
    func repeatedBisection() {
        var lower = 0.0
        let upper = 1.0
        var steps = 0
        while let mid = PlannerOrdering.indexBetween(lower, upper) {
            #expect(mid > lower && mid < upper)
            lower = mid
            steps += 1
            if steps > 100 { break }
        }
        #expect(steps < 100, "minimumGap must stop the bisection")
    }

    // MARK: - movedOrder (onMove semantics)

    @Test("movedOrder follows onMove(fromOffsets:toOffset:)", arguments: [
        (4, [0], 2, [1, 0, 2, 3]),
        (4, [0], 4, [1, 2, 3, 0]),
        (4, [3], 0, [3, 0, 1, 2]),
        (4, [1], 1, [0, 1, 2, 3]),
        (5, [0, 2], 5, [1, 3, 4, 0, 2]),
        (3, [1], 99, [0, 2, 1]),
    ] as [(Int, [Int], Int, [Int])])
    func movedOrder(count: Int, source: [Int], destination: Int, expected: [Int]) {
        let order = PlannerOrdering.movedOrder(count: count, fromOffsets: IndexSet(source), toOffset: destination)
        #expect(order == expected)
    }

    // MARK: - reindexForMove (DM-07)

    @Test("DM-07 moving one element changes only that element's sortIndex")
    func singleMoveChangesOneIndex() {
        // [0, 1, 2, 3]: move offset 3 between offsets 0 and 1.
        let changes = PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2, 3], fromOffsets: [3], toOffset: 1)
        #expect(changes == [3: 0.5])
    }

    @Test("DM-07 moving to the end / start uses neighbour ± 1")
    func moveToEdges() {
        #expect(PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2], fromOffsets: [0], toOffset: 3) == [0: 3])
        #expect(PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2], fromOffsets: [2], toOffset: 0) == [2: -1])
    }

    @Test("DM-07 a move onto its own place changes nothing")
    func noOpMove() {
        #expect(PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2], fromOffsets: [1], toOffset: 1).isEmpty)
        #expect(PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2], fromOffsets: [1], toOffset: 2).isEmpty)
    }

    @Test("DM-07 exhausted gap renumbers the section 0, 1, 2, ...")
    func renumberWhenGapExhausted() {
        let indices = [0, 1e-7, 2e-7, 1]
        let changes = PlannerOrdering.reindexForMove(sortIndices: indices, fromOffsets: [3], toOffset: 1)
        // New order: [0, 3, 1, 2] → sortIndex 0, 1, 2, 3. Offsets 0 and 3 already
        // have the right value (0 and 1), so only 1 and 2 are written.
        #expect(changes == [1: 2, 2: 3])
        let result = applying(changes, to: indices)
        #expect(result[0] < result[3] && result[3] < result[1] && result[1] < result[2])
    }

    @Test("DM-07 moving several elements at once renumbers the section")
    func multiMoveRenumbers() {
        let changes = PlannerOrdering.reindexForMove(sortIndices: [0, 1, 2, 3], fromOffsets: [0, 1], toOffset: 4)
        // New order: [2, 3, 0, 1].
        #expect(changes == [2: 0, 3: 1, 0: 2, 1: 3])
    }

    @Test("DM-07 any single move keeps the relative order of the other elements",
          arguments: 0..<5, 0...5)
    func singleMovePreservesOthers(from: Int, to: Int) {
        let indices: [Double] = [0, 1, 2, 3, 4]
        let changes = PlannerOrdering.reindexForMove(sortIndices: indices, fromOffsets: [from], toOffset: to)
        let result = applying(changes, to: indices)
        let expected = PlannerOrdering.movedOrder(count: 5, fromOffsets: [from], toOffset: to)
        let actual = result.indices.sorted { result[$0] < result[$1] }
        #expect(actual == expected)
        #expect(changes.count <= 1)
    }

    private func applying(_ changes: [Int: Double], to indices: [Double]) -> [Double] {
        var result = indices
        for (offset, value) in changes { result[offset] = value }
        return result
    }
}
