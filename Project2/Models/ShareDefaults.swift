//
//  ShareDefaults.swift
//  Project2
//
//  Which list and group the Share Extension preselects (SE-03, SE-04), and the values the
//  app and the extension share through the App Group's UserDefaults (SE-18).
//
//  The extension can't read the app's `UserDefaults.standard` (`AppSettings`,
//  `LocalUIState`), so everything it needs from the app is mirrored into the group's defaults.
//

import Foundation

/// The App Group's `UserDefaults`, shared by the app and the Share Extension.
enum SharedDefaults {
    /// The main currency, written by `AppSettings` at launch and on every change (SE-18).
    static let mainCurrencyKey = "mainCurrencyCode"

    /// The group's defaults. A build without the App Group entitlement (CI's unsigned build)
    /// still gets a working, process-local suite, so nothing crashes there.
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: SyncConfig.appGroupIdentifier) ?? .standard
    }

    /// The main currency for a list the extension creates: the app's choice, or the region's
    /// default when the app never ran (or ran before M7) on this device.
    static func mainCurrencyCode(in defaults: UserDefaults, locale: Locale) -> String {
        CurrencyCatalog.resolvedMainCurrency(stored: defaults.string(forKey: mainCurrencyKey), locale: locale)
    }
}

/// "Last used" list and group of the Share Extension (SE-03, SE-04). Written only after a
/// successful Save; Cancel leaves them as they are.
struct ShareDefaults {
    static let lastListKey = "share.lastListID"
    static let lastGroupKeyPrefix = "share.lastGroupID."

    /// What the rule needs to know about an active list.
    struct ListCandidate: Equatable, Sendable {
        let id: UUID
    }

    let defaults: UserDefaults

    var lastListID: UUID? {
        defaults.string(forKey: Self.lastListKey).flatMap(UUID.init(uuidString:))
    }

    func lastGroupID(in listID: UUID) -> UUID? {
        defaults.string(forKey: Self.lastGroupKeyPrefix + listID.uuidString).flatMap(UUID.init(uuidString:))
    }

    /// Remembers where the item went. Called after the save succeeded.
    func recordSave(listID: UUID, groupID: UUID) {
        defaults.set(listID.uuidString, forKey: Self.lastListKey)
        defaults.set(groupID.uuidString, forKey: Self.lastGroupKeyPrefix + listID.uuidString)
    }

    /// The preselected list (SE-03): the last one saved to, if it is still active; otherwise
    /// the first in Home order (pinned first, then by `sortIndex`); `nil` without active lists
    /// ("New list" mode).
    /// - Parameter lists: the active lists in Home order. Archived lists must not be in it.
    static func listID(last: UUID?, lists: [ListCandidate]) -> UUID? {
        if let last, lists.contains(where: { $0.id == last }) { return last }
        return lists.first?.id
    }

    /// The preselected group (SE-04): the last one used in this list, if it still exists;
    /// otherwise the ⌘N rule (`NewItemTarget`) with every group treated as expanded (the
    /// extension doesn't know what is collapsed); `nil` when the list has no groups
    /// ("Items (new)", created on Save).
    /// - Parameter groups: the list's groups in display order.
    static func groupID(last: UUID?, groups: [NewItemTarget.Candidate]) -> UUID? {
        if let last, groups.contains(where: { $0.id == last }) { return last }
        return NewItemTarget.groupID(in: groups)
    }
}
