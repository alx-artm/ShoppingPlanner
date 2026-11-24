//
//  ShareComposerModel.swift
//  Project2
//
//  The state and rules of the Share Extension's compose screen (spec 06 B.2, SE-02...SE-09).
//  Independent of `NSExtensionContext`: in go a `SharePayload` and a `PlannerStore`, out comes
//  a saved item. The same screen runs in the app for UI tests (`-UITestsShareComposer`, B.5).
//
//  Memory (B.4 p.7): it fetches the active lists and the groups of the selected list only.
//  Items are never loaded, except the newest `createdAt` per group for the ⌘N rule.
//

import Foundation
import OSLog
import SwiftData

@MainActor
@Observable
final class ShareComposerModel {
    /// Where the item goes.
    enum Destination: Hashable {
        case list(UUID)
        /// "New List…", or no active list at all (SE-05).
        case newList
    }

    let payload: SharePayload
    /// Active lists in Home order (SE-04a). Empty → only "New list" mode.
    private(set) var lists: [ListModel] = []
    /// Groups of the selected list in display order; empty in "New list" mode.
    private(set) var groups: [GroupModel] = []

    var destination: Destination {
        didSet {
            guard destination != oldValue else { return }
            loadGroups() // SE-04: a new list starts from its own default group
        }
    }
    /// `nil`: "Items (new)", created on Save (LD-05a).
    var groupID: UUID?
    /// The new list's name; blank becomes "Untitled list" on Save (SE-05).
    var newListName = String(localized: "Wishlist", comment: "Prefilled name of the list the Share Extension creates.")

    /// The item name: prefilled (SE-02), then the user's.
    private(set) var name: String
    /// The user typed in the name: a late title no longer replaces it (SE-02a).
    private(set) var isNameEdited = false
    /// The page title for the card and `linkTitle`; `nil` until known.
    private(set) var pageTitle: String?

    /// The price as typed, parsed in the list currency (SE-06).
    var priceText = ""
    var isMustHave = false
    /// A failed save, shown under the form. The extension stays open.
    private(set) var saveError: String?

    @ObservationIgnored private let store: PlannerStore
    @ObservationIgnored private let shareDefaults: ShareDefaults
    @ObservationIgnored private let mainCurrencyCode: String
    @ObservationIgnored private let titleFetcher: (any LinkMetadataFetching)?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<LinkPreview?, Never>?
    @ObservationIgnored private let titleTimeout: Duration

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "ShareComposer")

    /// - Parameters:
    ///   - mainCurrencyCode: the currency of a list created here (SE-18).
    ///   - titleFetcher: loads the page title when the payload has none (B2); `nil` = never.
    ///   - titleTimeout: how long the title may take (B.4 p.5: 5 s); later answers are dropped.
    init(payload: SharePayload, store: PlannerStore, shareDefaults: ShareDefaults, mainCurrencyCode: String,
         titleFetcher: (any LinkMetadataFetching)?, titleTimeout: Duration = .seconds(5),
         locale: Locale = .current) {
        self.payload = payload
        self.store = store
        self.shareDefaults = shareDefaults
        self.mainCurrencyCode = mainCurrencyCode
        self.titleFetcher = titleFetcher
        self.titleTimeout = titleTimeout
        self.locale = locale
        // The sharing app's text is usually the page title (Safari puts it into the item).
        let appTitle = ShareTitle.clean(payload.appText, host: payload.host)
        name = appTitle ?? payload.host

        let active = store.lists(pinned: true) + store.lists(pinned: false)
        let listID = ShareDefaults.listID(last: shareDefaults.lastListID, lists: active.map { .init(id: $0.uuid) })
        destination = listID.map(Destination.list) ?? .newList
        lists = active
        pageTitle = appTitle
        loadGroups()
    }

    // MARK: Derived state

    var selectedList: ListModel? {
        guard case .list(let id) = destination else { return nil }
        return lists.first { $0.uuid == id }
    }

    /// The currency of the price field: the selected list's, or the main one for a new list.
    var currencyCode: String {
        selectedList?.currencyCode ?? mainCurrencyCode
    }

    var parsedPrice: MoneyInput.Parsed {
        MoneyInput.parse(priceText, currencyCode: currencyCode, locale: locale)
    }

    /// "Not a price" under the field (SE-06).
    var hasPriceError: Bool { parsedPrice == .invalid }

    /// Save is off only for a blank name or an invalid price (SE-09a).
    var canSave: Bool {
        PlannerStore.normalizedName(name) != nil && !hasPriceError
    }

    var selectedGroup: GroupModel? {
        groups.first { $0.uuid == groupID }
    }

    // MARK: Input

    /// The user's own text in the name field (SE-02a).
    func editName(_ text: String) {
        name = text
        isNameEdited = true
    }

    /// Loads the page title (B2): replaces the prefilled name unless the user edited it.
    /// Given up after `titleTimeout` (LinkPresentation's own timeout was not honoured in the
    /// extension: a heavy page kept loading for 10+ s) and on Save or Cancel (`cancel()`).
    func start() {
        guard titleTask == nil, let titleFetcher else { return }
        let url = payload.url
        let fetch = Task { try? await titleFetcher.fetch(url) }
        fetchTask = fetch
        let timeout = titleTimeout
        titleTask = Task { [weak self] in
            let deadline = Task {
                try? await Task.sleep(for: timeout)
                fetch.cancel()
            }
            let preview = await fetch.value
            deadline.cancel()
            guard !Task.isCancelled, let self else { return }
            self.titleArrived(preview?.title)
        }
    }

    /// A title came in (the fetch, or tests).
    func titleArrived(_ raw: String?) {
        guard let title = ShareTitle.clean(raw, host: payload.host) else { return }
        pageTitle = title
        if !isNameEdited { name = title }
    }

    /// Stops the title fetch: the extension is closing.
    func cancel() {
        fetchTask?.cancel()
        titleTask?.cancel()
        fetchTask = nil
        titleTask = nil
    }

    // MARK: Save

    /// Writes exactly one item (SE-09) and remembers the list and group (SE-03).
    /// `nil` when nothing could be saved (`saveError` says why).
    @discardableResult
    func save() -> ItemModel? {
        guard canSave else { return nil }
        cancel()
        let price: Decimal? = if case .amount(let amount) = parsedPrice { amount } else { nil }

        let list: ListModel
        if let selectedList {
            list = selectedList
        } else {
            list = store.createList(name: newListName, currencyCode: mainCurrencyCode)
        }
        let group = selectedGroup ?? store.createGroup(
            name: String(localized: "Items", comment: "Name of the group created for the first item of a list without groups."),
            in: list)
        guard let item = store.addSharedItem(name: name, to: group, price: price, urlString: payload.urlString,
                                             pageTitle: pageTitle, isMustHave: isMustHave) else {
            saveError = store.lastErrorMessage ?? String(localized: "Couldn't save your changes. Please try again.")
            Self.logger.error("The shared item was not saved")
            return nil
        }
        shareDefaults.recordSave(listID: list.uuid, groupID: group.uuid)
        return item
    }

    // MARK: Helpers

    private func loadGroups() {
        guard let list = selectedList else {
            groups = []
            groupID = nil
            return
        }
        groups = list.sortedGroups
        let candidates = groups.map {
            NewItemTarget.Candidate(id: $0.uuid, isExpanded: true, lastItemAddedAt: newestItemDate(in: $0))
        }
        groupID = ShareDefaults.groupID(last: shareDefaults.lastGroupID(in: list.uuid), groups: candidates)
    }

    /// The `createdAt` of the newest item of the group, without loading the items.
    private func newestItemDate(in group: GroupModel) -> Date? {
        let id = group.uuid
        var descriptor = FetchDescriptor<ItemModel>(
            predicate: #Predicate { $0.group?.uuid == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.createdAt]
        return (try? store.context.fetch(descriptor))?.first?.createdAt
    }
}
