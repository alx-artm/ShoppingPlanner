//
//  LocalUIStateTests.swift
//  Project2Tests
//
//  DM-10: collapsed groups and "Hide completed" are device-local (UserDefaults,
//  keyed by uuid) and survive a relaunch. Each test gets its own defaults suite.
//

import Foundation
import Testing
@testable import Project2

@MainActor
@Suite("LocalUIState")
struct LocalUIStateTests {
    private let suiteName = "LocalUIStateTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    // Swift Testing creates a new instance per test, so cleanup goes into a
    // helper called at the end of each test (structs have no deinit).
    private func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("DM-10 by default groups are expanded and completed items are shown")
    func defaultsAreExpandedAndShown() {
        defer { cleanUp() }
        let state = LocalUIState(defaults: defaults)
        #expect(state.isExpanded(UUID()))
        #expect(state.showsCompleted(UUID()))
        #expect(state.collapsedGroupIDs.isEmpty)
        #expect(state.hideCompletedListIDs.isEmpty)
    }

    @Test("DM-10 collapsing a group affects only that group and can be undone")
    func collapseGroup() {
        defer { cleanUp() }
        let state = LocalUIState(defaults: defaults)
        let group = UUID(), other = UUID()

        state.setExpanded(false, for: group)
        #expect(!state.isExpanded(group))
        #expect(state.isExpanded(other))

        state.setExpanded(true, for: group)
        #expect(state.isExpanded(group))
        #expect(state.collapsedGroupIDs.isEmpty)
    }

    @Test("DM-10 hide completed is per list")
    func hideCompletedPerList() {
        defer { cleanUp() }
        let state = LocalUIState(defaults: defaults)
        let list = UUID(), other = UUID()

        state.setShowsCompleted(false, for: list)
        #expect(!state.showsCompleted(list))
        #expect(state.showsCompleted(other))

        state.setShowsCompleted(true, for: list)
        #expect(state.showsCompleted(list))
    }

    @Test("DM-10 state is restored after a relaunch (new instance, same defaults)")
    func persistsAcrossInstances() {
        defer { cleanUp() }
        let group = UUID(), list = UUID()
        do {
            let state = LocalUIState(defaults: defaults)
            state.setExpanded(false, for: group)
            state.setShowsCompleted(false, for: list)
        }

        let relaunched = LocalUIState(defaults: defaults)
        #expect(!relaunched.isExpanded(group))
        #expect(!relaunched.showsCompleted(list))
    }

    @Test("Corrupted stored values are ignored instead of crashing")
    func corruptedValuesIgnored() {
        defer { cleanUp() }
        let valid = UUID()
        defaults.set(["not-a-uuid", valid.uuidString, ""], forKey: "collapsedGroupIDs")
        defaults.set(42, forKey: "hideCompletedListIDs")

        let state = LocalUIState(defaults: defaults)
        #expect(state.collapsedGroupIDs == [valid])
        #expect(state.hideCompletedListIDs.isEmpty)
    }

    @Test("inMemory() starts clean every time (used by previews and UI tests)")
    func inMemoryStartsClean() {
        defer { cleanUp() }
        let first = LocalUIState.inMemory()
        first.setExpanded(false, for: UUID())

        let second = LocalUIState.inMemory()
        #expect(second.collapsedGroupIDs.isEmpty)
    }
}
