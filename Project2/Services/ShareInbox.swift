//
//  ShareInbox.swift
//  Project2
//
//  The app's side of the Share Extension (spec 06 B.4 p.2, SE-10, SE-10a, SE-10b).
//
//  The extension writes into the same store file with its own container and the transaction
//  author "shareExtension". The app reads the store's history after the last token it handled,
//  keeps only the extension's transactions (its own edits and the CloudKit import are skipped)
//  and returns the items the extension inserted, so the app can fetch their link previews at
//  once. Reading the history through the main context also brings the new rows into it, so
//  Home and the list update without a relaunch (checked in the M7 spike, DECISIONS Р-33).
//
//  The token lives in the app's own `UserDefaults.standard`: only the app reads history.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class ShareInbox {
    /// The transaction author of every write of the Share Extension.
    nonisolated static let author = "shareExtension"
    nonisolated static let tokenKey = "share.historyToken"

    private let context: ModelContext
    private let defaults: UserDefaults

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "ShareInbox")

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    /// The `uuid`s of the items the extension inserted since the last call (still existing),
    /// in history order. Empty when there is nothing new. Moves the token past everything read.
    func pull() -> [UUID] {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token = savedToken {
            descriptor.predicate = #Predicate { $0.token > token }
        }
        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try context.fetchHistory(descriptor)
        } catch {
            Self.logger.error("Reading the store history failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard let last = transactions.last else { return [] }
        save(last.token)

        var ids: [UUID] = []
        for transaction in transactions where transaction.author == Self.author {
            for change in transaction.changes {
                guard case .insert(let insert) = change,
                      let itemInsert = insert as? DefaultHistoryInsert<ItemModel>,
                      let item = existingItem(itemInsert.changedPersistentIdentifier),
                      !ids.contains(item.uuid) else { continue }
                ids.append(item.uuid)
                attachToLoadedGroup(item)
            }
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                Self.logger.error("Saving shared items failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return ids
    }

    /// A remote insert doesn't reach a to-many relationship this context has already loaded:
    /// the item itself can be fetched, but its group's `items` (what the list screen and Home
    /// show) stays without it until a relaunch. Found in the M7 manual check, covered by
    /// `ShareStoreTests.loadedRelationshipIsUpdated`. Adding the item to the group again updates
    /// the loaded side; the store already has that link, so the save changes no data. It also
    /// makes the change the app's own transaction, which CloudKit exports for sure (Р-33).
    /// The same for a group the extension created ("Items") in a list the app has loaded.
    private func attachToLoadedGroup(_ item: ItemModel) {
        guard let group = item.group else { return }
        if !(group.items ?? []).contains(where: { $0.persistentModelID == item.persistentModelID }) {
            group.items = (group.items ?? []) + [item]
        }
        if let list = group.list,
           !(list.groups ?? []).contains(where: { $0.persistentModelID == group.persistentModelID }) {
            list.groups = (list.groups ?? []) + [group]
        }
    }

    /// The item if it still exists (it may have been deleted since the extension saved it).
    private func existingItem(_ id: PersistentIdentifier) -> ItemModel? {
        var descriptor = FetchDescriptor<ItemModel>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private var savedToken: DefaultHistoryToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
    }

    private func save(_ token: DefaultHistoryToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
