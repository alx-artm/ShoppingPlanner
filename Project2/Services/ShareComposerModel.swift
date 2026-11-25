//
//  ShareComposerModel.swift
//  Project2
//
//  The state and rules of the Share Extension's compose screen (spec 06 B.2, SE-02...SE-09).
//  Independent of `NSExtensionContext`: in go a `SharePayload` and a `PlannerStore`, out comes
//  a saved item. The same screen runs in the app for UI tests (`-UITestsShareComposer`, B.5).
//
//  Memory (B.4 p.7): it fetches the active lists and the groups of the selected list only.
//  Items are never loaded, except the newest `createdAt` per group for the ⌘N rule and the
//  items with the shared link for the duplicate hint (SE-15).
//
//  From Safari (PR 2) the page data prefills the name (og:title, title), the picture
//  (og:image, `ShareImageLoading`) and the price (`SharePrice`, B1).
//

import CoreGraphics
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
            applyPriceSuggestion() // SE-07: the rule depends on the list currency
            findDuplicate() // SE-15
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

    /// The price as typed, parsed in the list currency (SE-06); prefilled from the page (SE-07).
    private(set) var priceText = ""
    /// The user typed in the price field: the page price no longer changes it (SE-07).
    private(set) var isPriceEdited = false
    /// The one price the page states (Safari only), or `nil`.
    let pagePrice: PagePrice?
    var isMustHave = false

    /// The page picture, shrunk for `linkImageData` (≤ 800 px, ≤ 200 KB); `nil` until loaded.
    private(set) var imageData: Data?
    /// The same picture decoded at the card's size.
    private(set) var cardImage: CGImage?
    /// The group of the selected list that already has an item with this link (SE-15).
    private(set) var duplicateGroupName: String?
    /// A failed save, shown under the form. The extension stays open.
    private(set) var saveError: String?

    @ObservationIgnored private let store: PlannerStore
    @ObservationIgnored private let shareDefaults: ShareDefaults
    @ObservationIgnored private let mainCurrencyCode: String
    @ObservationIgnored private let titleFetcher: (any LinkMetadataFetching)?
    @ObservationIgnored private let imageLoader: (any ShareImageLoading)?
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    /// A list and group a failed Save already created: a retry reuses them, so it doesn't
    /// add a second "Wishlist" (PR 1 review note).
    @ObservationIgnored private var unsavedList: ListModel?
    @ObservationIgnored private var unsavedGroup: GroupModel?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<LinkPreview?, Never>?
    @ObservationIgnored private let titleTimeout: Duration

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Project2", category: "ShareComposer")

    /// - Parameters:
    ///   - mainCurrencyCode: the currency of a list created here (SE-18).
    ///   - titleFetcher: loads the page title when the payload has none (B2); `nil` = never.
    ///   - titleTimeout: how long the title may take (B.4 p.5: 5 s); later answers are dropped.
    ///   - imageLoader: loads Safari's og:image (B3); `nil` = never.
    init(payload: SharePayload, store: PlannerStore, shareDefaults: ShareDefaults, mainCurrencyCode: String,
         titleFetcher: (any LinkMetadataFetching)?, titleTimeout: Duration = .seconds(5),
         imageLoader: (any ShareImageLoading)? = nil, locale: Locale = .current) {
        self.payload = payload
        self.store = store
        self.shareDefaults = shareDefaults
        self.mainCurrencyCode = mainCurrencyCode
        self.titleFetcher = titleFetcher
        self.titleTimeout = titleTimeout
        self.imageLoader = imageLoader
        self.locale = locale
        // SE-02: og:title → document.title (Safari) → [LinkPresentation, later] → the app's
        // text (Safari also puts the title into the item) → host.
        let title = payload.page?.cleanedTitle(host: payload.host)
            ?? ShareTitle.clean(payload.appText, host: payload.host)
        name = title ?? payload.host
        pagePrice = payload.page.flatMap(SharePrice.pagePrice(of:))

        let active = store.lists(pinned: true) + store.lists(pinned: false)
        let listID = ShareDefaults.listID(last: shareDefaults.lastListID, lists: active.map { .init(id: $0.uuid) })
        destination = listID.map(Destination.list) ?? .newList
        lists = active
        pageTitle = title
        loadGroups()
        applyPriceSuggestion()
        findDuplicate()
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

    /// What the page price means for the selected list (SE-07).
    var priceSuggestion: SharePrice.Suggestion {
        SharePrice.suggestion(for: pagePrice, listCurrency: currencyCode)
    }

    /// "Page price: $499.00" under an empty field when the page's currency is another one (SE-07).
    var pagePriceHint: String? {
        guard case .hint(let price) = priceSuggestion else { return nil }
        let amount = MoneyFormat.string(price.amount, currencyCode: price.currencyCode, locale: locale)
        return String(localized: "Page price: \(amount)",
                      comment: "Share Extension: under the price field when the page's price is in another currency.")
    }

    // MARK: Input

    /// The user's own text in the name field (SE-02a).
    func editName(_ text: String) {
        name = text
        isNameEdited = true
    }

    /// The user's own text in the price field (SE-07).
    func editPrice(_ text: String) {
        priceText = text
        isPriceEdited = true
    }

    /// Starts what loads after the first frame: the page title (B2) and the picture (B3).
    func start() {
        startTitle()
        startImage()
    }

    /// Loads the page title (B2) when Safari gave none: replaces the prefilled name unless the
    /// user edited it. Given up after `titleTimeout` (LinkPresentation's own timeout was not
    /// honoured in the extension: a heavy page kept loading for 10+ s) and on Save or Cancel.
    private func startTitle() {
        guard titleTask == nil, let titleFetcher,
              payload.page?.cleanedTitle(host: payload.host) == nil else { return }
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

    /// Loads Safari's og:image (B3). Only Safari has one; from other apps the app loads the
    /// picture later (B2, LP-01b). The loader keeps to 10 MB and 3 s itself (SE-13).
    private func startImage() {
        guard imageTask == nil, let imageLoader, let url = payload.page?.imageURL else { return }
        imageTask = Task { [weak self] in
            let data = await imageLoader.thumbnail(for: url)
            guard !Task.isCancelled, let self else { return }
            self.imageArrived(data)
        }
    }

    /// The card's picture side in pixels: 64 pt at 3×.
    static let cardImagePixelSize = 192

    /// A picture came in (the loader, or tests): kept for Save and decoded at the card's size.
    func imageArrived(_ data: Data?) {
        guard let data else { return }
        imageData = data
        cardImage = LinkThumbnail.displayImage(from: data, maxPixelSize: Self.cardImagePixelSize)
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
        imageTask?.cancel()
        fetchTask = nil
        titleTask = nil
        imageTask = nil
    }

    // MARK: Save

    /// Writes exactly one item (SE-09) and remembers the list and group (SE-03).
    /// `nil` when nothing could be saved (`saveError` says why).
    @discardableResult
    func save() -> ItemModel? {
        guard canSave else { return nil }
        cancel()
        let price: Decimal? = if case .amount(let amount) = parsedPrice { amount } else { nil }

        let (list, group) = resolveDestination()
        // The picture only if it is already here (SE-09): Save never waits for it.
        guard let item = store.addSharedItem(name: name, to: group, price: price, urlString: payload.urlString,
                                             pageTitle: pageTitle, isMustHave: isMustHave,
                                             imageData: imageData) else {
            saveError = store.lastErrorMessage ?? String(localized: "Couldn't save your changes. Please try again.")
            Self.logger.error("The shared item was not saved")
            return nil
        }
        shareDefaults.recordSave(listID: list.uuid, groupID: group.uuid)
        return item
    }

    // MARK: Helpers

    /// The list and group Save writes to, created when needed. A list or group a failed Save
    /// created is reused (and the list renamed to the current name), never created twice.
    func resolveDestination() -> (list: ListModel, group: GroupModel) {
        let list: ListModel
        if let selectedList {
            list = selectedList
        } else if let unsavedList {
            if let name = PlannerStore.normalizedName(newListName), name != unsavedList.name {
                store.renameList(unsavedList, to: name)
            }
            list = unsavedList
        } else {
            list = store.createList(name: newListName, currencyCode: mainCurrencyCode)
            unsavedList = list
        }
        let group: GroupModel
        if let selectedGroup {
            group = selectedGroup
        } else if let unsavedGroup, unsavedGroup.list?.uuid == list.uuid {
            group = unsavedGroup
        } else {
            group = store.createGroup(
                name: String(localized: "Items", comment: "Name of the group created for the first item of a list without groups."),
                in: list)
            unsavedGroup = group
        }
        return (list, group)
    }

    /// Prefills the price from the page while the user hasn't typed (SE-07): the amount when the
    /// currencies match, otherwise an empty field (the hint shows the page price).
    private func applyPriceSuggestion() {
        guard !isPriceEdited else { return }
        if case .prefill(let amount) = priceSuggestion {
            priceText = MoneyInput.editingText(for: amount, currencyCode: currencyCode, locale: locale)
        } else {
            priceText = ""
        }
    }

    /// SE-15: an item of the selected list with the shared link or the page's canonical URL
    /// (`payload.duplicateCandidates`, owner decision (b)). Items of a new list can't match.
    /// Stored links are normalized the same way. Only items with these exact links are fetched
    /// (a handful at most), and their pictures stay on disk (`.externalStorage`). The list is
    /// checked in memory: a predicate through `group?.list?.uuid` (two optional relationships)
    /// threw an Objective-C exception in Core Data.
    private func findDuplicate() {
        guard let list = selectedList else {
            duplicateGroupName = nil
            return
        }
        let listID = list.uuid
        let links = payload.duplicateCandidates
        let descriptor = FetchDescriptor<ItemModel>(predicate: #Predicate { links.contains($0.urlString) })
        let matches = (try? store.context.fetch(descriptor)) ?? []
        duplicateGroupName = matches.lazy.compactMap(\.group).first { $0.list?.uuid == listID }?.name
    }

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
