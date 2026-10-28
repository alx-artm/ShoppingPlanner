//
//  LocalUIState.swift
//  Project2
//
//  Device-local UI state keyed by model `uuid` (DM-10): which groups are
//  collapsed and which lists hide completed items. It lives in UserDefaults,
//  not in the SwiftData models, so it never syncs between devices.
//

import Foundation
import Observation

@MainActor
@Observable
final class LocalUIState {
    private static let collapsedGroupsKey = "collapsedGroupIDs"
    private static let hideCompletedListsKey = "hideCompletedListIDs"

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var collapsedGroupIDs: Set<UUID>
    private(set) var hideCompletedListIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedGroupIDs = Self.read(Self.collapsedGroupsKey, from: defaults)
        hideCompletedListIDs = Self.read(Self.hideCompletedListsKey, from: defaults)
    }

    /// Volatile state for previews and UI tests: nothing is read from or written to disk.
    static func inMemory() -> LocalUIState {
        let suiteName = "LocalUIState.inMemory"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return LocalUIState(defaults: defaults)
    }

    func isExpanded(_ groupID: UUID) -> Bool {
        !collapsedGroupIDs.contains(groupID)
    }

    func setExpanded(_ isExpanded: Bool, for groupID: UUID) {
        if isExpanded {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
        Self.write(collapsedGroupIDs, Self.collapsedGroupsKey, to: defaults)
    }

    func showsCompleted(_ listID: UUID) -> Bool {
        !hideCompletedListIDs.contains(listID)
    }

    func setShowsCompleted(_ showsCompleted: Bool, for listID: UUID) {
        if showsCompleted {
            hideCompletedListIDs.remove(listID)
        } else {
            hideCompletedListIDs.insert(listID)
        }
        Self.write(hideCompletedListIDs, Self.hideCompletedListsKey, to: defaults)
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> Set<UUID> {
        let strings = defaults.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private static func write(_ ids: Set<UUID>, _ key: String, to defaults: UserDefaults) {
        defaults.set(ids.map(\.uuidString).sorted(), forKey: key)
    }
}
