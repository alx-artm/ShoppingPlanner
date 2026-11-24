//
//  ShareExtensionTests.swift
//  Project2Tests
//
//  Spec 06 Part B (M7, PR 1): the logic of the Share Extension, tested from the app's test
//  target because the files are shared by target membership (B7). Input parsing (SE-01a),
//  name cleaning (SE-02), defaults (SE-03, SE-04), the compose model and saving (SE-05,
//  SE-06, SE-09, SE-09b), the extension's store (SE-11a, SE-12), the app's inbox (SE-10b)
//  and the main-currency mirror (SE-18). Nothing here touches CloudKit or the real App Group.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

extension Tag {
    /// Share Extension (spec 06 Part B, SE-xx).
    @Tag static var shareExtension: Self
}

// MARK: - Input and name

@Suite("Share Extension: input and name", .tags(.shareExtension))
struct SharePayloadTests {
    private func payload(_ urls: [String], _ texts: [String] = []) -> SharePayload? {
        guard case .link(let payload) = ShareInput.from(urls: urls.compactMap(URL.init(string:)), texts: texts) else {
            return nil
        }
        return payload
    }

    @Test("SE-01a (b) only public.url: the link, normalized, without a text")
    func urlOnly() throws {
        let shared = try #require(payload(["https://www.IKEA.com/us/en/p/kivik?color=blue"]))
        #expect(shared.urlString == "https://www.IKEA.com/us/en/p/kivik?color=blue")
        #expect(shared.appText == nil)
        #expect(shared.host == "ikea.com")
    }

    @Test("SE-01a (c) public.url + public.plain-text: the text is a name candidate")
    func urlAndText() throws {
        let shared = try #require(payload(["https://shop.example.com/a"], ["  KIVIK 3-seat sofa \n"]))
        #expect(shared.appText == "KIVIK 3-seat sofa")
    }

    @Test("SE-01a (c) a text that is a link, contains the link, is blank or longer than 150 is no name")
    func textIgnored() throws {
        let url = "https://shop.example.com/a"
        #expect(try #require(payload([url], [url])).appText == nil)
        #expect(try #require(payload([url], ["Look: \(url)"])).appText == nil)
        #expect(try #require(payload([url], ["   "])).appText == nil)
        #expect(try #require(payload([url], [String(repeating: "a", count: 151)])).appText == nil)
        #expect(try #require(payload([url], [String(repeating: "a", count: 150)])).appText?.count == 150)
    }

    @Test("SE-01a (d) mailto:, file:// and a host without a dot are unsupported",
          arguments: ["mailto:shop@example.com", "file:///tmp/a.html", "https://localhost/a", "ftp://example.com/a"])
    func unsupported(_ link: String) {
        #expect(ShareInput.from(urls: [URL(string: link)!], texts: []) == .unsupported)
    }

    @Test("SE-01a no link at all is unsupported; a file URL before a web link is skipped")
    func noLinkAndMixed() throws {
        #expect(ShareInput.from(urls: [], texts: ["milk"]) == .unsupported)
        let shared = try #require(payload(["file:///tmp/a.html", "https://example.com/b"]))
        #expect(shared.urlString == "https://example.com/b")
    }

    @Test("SE-02 ShareTitle.clean", arguments: [
        ("KIVIK 3-seat sofa - IKEA", "ikea.com", "KIVIK 3-seat sofa"),
        ("Amazon.com: Apple AirPods Pro", "amazon.com", "Apple AirPods Pro"),
        ("Sofa | Shop", "ikea.com", "Sofa | Shop"),
        ("  Lamp\n\n  with   shade  ", "example.com", "Lamp with shade"),
        ("Диван угловой — Hoff", "hoff.ru", "Диван угловой"),
        ("Кресло | OZON", "ozon.ru", "Кресло"),
        ("Kettle - Argos", "argos.co.uk", "Kettle"),
        ("IKEA", "ikea.com", "IKEA"),
        ("iPhone 17 Pro - Apple", "apple.com", "iPhone 17 Pro"),
        ("Handmade mug · Etsy", "etsy.com", "Handmade mug"),
    ])
    func cleanTitle(_ raw: String, _ host: String, _ expected: String) {
        #expect(ShareTitle.clean(raw, host: host) == expected)
    }

    @Test("SE-02 an empty title gives nil (the caller uses the host); at most 150 characters")
    func cleanLimits() {
        #expect(ShareTitle.clean("  \n ", host: "ikea.com") == nil)
        #expect(ShareTitle.clean(nil, host: "ikea.com") == nil)
        #expect(ShareTitle.clean(String(repeating: "x", count: 400), host: "ikea.com")?.count == 150)
    }
}

// MARK: - Defaults

@Suite("Share Extension: defaults", .tags(.shareExtension))
final class ShareDefaultsTests {
    private let suiteName = "ShareDefaultsTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private let a = UUID(), b = UUID(), c = UUID()

    @Test("SE-03 the last list if it is still active, else the first in Home order, else nil")
    func listRule() {
        let lists: [ShareDefaults.ListCandidate] = [.init(id: a), .init(id: b)]
        #expect(ShareDefaults.listID(last: b, lists: lists) == b)
        #expect(ShareDefaults.listID(last: c, lists: lists) == a) // archived or deleted
        #expect(ShareDefaults.listID(last: nil, lists: lists) == a)
        #expect(ShareDefaults.listID(last: a, lists: []) == nil)
    }

    @Test("SE-04 the last group of the list, else the ⌘N rule with every group expanded, else nil")
    func groupRule() {
        let date = Date(timeIntervalSince1970: 1000)
        let groups: [NewItemTarget.Candidate] = [
            .init(id: a, isExpanded: true, lastItemAddedAt: date),
            .init(id: b, isExpanded: true, lastItemAddedAt: date.addingTimeInterval(60)),
        ]
        #expect(ShareDefaults.groupID(last: a, groups: groups) == a)
        #expect(ShareDefaults.groupID(last: c, groups: groups) == b) // newest item
        #expect(ShareDefaults.groupID(last: nil, groups: []) == nil)
    }

    @Test("SE-03 keys share.lastListID and share.lastGroupID.<listID>")
    func keys() {
        let store = ShareDefaults(defaults: defaults)
        store.recordSave(listID: a, groupID: b)
        #expect(defaults.string(forKey: "share.lastListID") == a.uuidString)
        #expect(defaults.string(forKey: "share.lastGroupID.\(a.uuidString)") == b.uuidString)
        #expect(store.lastListID == a)
        #expect(store.lastGroupID(in: a) == b)
        #expect(store.lastGroupID(in: c) == nil)
    }

    @Test("SE-18 the extension reads the main currency from the group, else the region default")
    func mainCurrency() {
        #expect(SharedDefaults.mainCurrencyCode(in: defaults, locale: Locale(identifier: "de_DE")) == "EUR")
        defaults.set("JPY", forKey: SharedDefaults.mainCurrencyKey)
        #expect(SharedDefaults.mainCurrencyCode(in: defaults, locale: Locale(identifier: "de_DE")) == "JPY")
    }

    @Test("SE-18 AppSettings mirrors the main currency at launch and on every change")
    @MainActor
    func appSettingsMirror() throws {
        let appSuite = "ShareDefaultsTests.app.\(UUID().uuidString)"
        let appDefaults = try #require(UserDefaults(suiteName: appSuite))
        defer { UserDefaults().removePersistentDomain(forName: appSuite) }
        let settings = AppSettings(defaults: appDefaults, sharedDefaults: defaults, locale: Locale(identifier: "ru_RU"))
        #expect(defaults.string(forKey: "mainCurrencyCode") == "RUB")
        settings.mainCurrencyCode = "GBP"
        #expect(defaults.string(forKey: "mainCurrencyCode") == "GBP")
    }
}

// MARK: - Compose and save

@MainActor
@Suite("Share Extension: compose and save", .tags(.shareExtension))
final class ShareComposerTests {
    private let suiteName = "ShareComposerTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let fixture: StoreFixture

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        fixture = try StoreFixture(currency: "USD")
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private var shareDefaults: ShareDefaults { ShareDefaults(defaults: defaults) }

    // The app's strings in the language the test host runs in (see `UILanguage`).
    private let items = String(localized: "Items", comment: "Name of the group created for the first item of a list without groups.")
    private let wishlist = String(localized: "Wishlist", comment: "Prefilled name of the list the Share Extension creates.")
    private let untitled = String(localized: "Untitled list")

    private func model(_ link: String = "https://www.ikea.com/p/kivik", text: String? = nil,
                       mainCurrency: String = "EUR", locale: String = "en_US",
                       fetcher: (any LinkMetadataFetching)? = nil,
                       titleTimeout: Duration = .seconds(5)) throws -> ShareComposerModel {
        guard case .link(let payload) = ShareInput.from(urls: [try #require(URL(string: link))],
                                                        texts: text.map { [$0] } ?? []) else {
            throw CancellationError()
        }
        return ShareComposerModel(payload: payload, store: fixture.store, shareDefaults: shareDefaults,
                                  mainCurrencyCode: mainCurrency, titleFetcher: fetcher,
                                  titleTimeout: titleTimeout, locale: Locale(identifier: locale))
    }

    /// Home order: "Pinned" (pinned), then "Second", "First" (a new list goes first in All Lists).
    private func makeLists() -> (pinned: ListModel, second: ListModel, first: ListModel) {
        let first = fixture.store.createList(name: "First")
        let second = fixture.store.createList(name: "Second", currencyCode: "JPY")
        let pinned = fixture.store.createList(name: "Pinned", isPinned: true, currencyCode: "EUR")
        return (pinned, second, first)
    }

    @Test("SE-04a active lists in Home order, archived ones left out; default = first pinned (SE-03)")
    func listsAndDefault() throws {
        let lists = makeLists()
        fixture.store.archiveList(lists.first)
        let composer = try model()
        #expect(composer.lists.map(\.name) == ["Pinned", "Second"])
        #expect(composer.destination == .list(lists.pinned.uuid))
        #expect(composer.currencyCode == "EUR")
    }

    @Test("SE-03 the last list saved to is preselected next time; an archived one is not")
    func lastList() throws {
        let lists = makeLists()
        let group = fixture.store.createGroup(name: "G", in: lists.second)
        shareDefaults.recordSave(listID: lists.second.uuid, groupID: group.uuid)
        #expect(try model().destination == .list(lists.second.uuid))
        fixture.store.archiveList(lists.second)
        #expect(try model().destination == .list(lists.pinned.uuid))
    }

    @Test("SE-04 group default: last used → newest item → first; changing the list resets it")
    func groups() throws {
        let lists = makeLists()
        let a = fixture.store.createGroup(name: "A", in: lists.pinned)
        let b = fixture.store.createGroup(name: "B", in: lists.pinned)
        fixture.clock.advance(by: 60)
        fixture.addItem("x", to: b)
        let composer = try model()
        #expect(composer.groups.map(\.name) == ["A", "B"])
        #expect(composer.groupID == b.uuid)

        shareDefaults.recordSave(listID: lists.pinned.uuid, groupID: a.uuid)
        let again = try model()
        #expect(again.groupID == a.uuid)
        again.destination = .list(lists.second.uuid) // no groups
        #expect(again.groups.isEmpty)
        #expect(again.groupID == nil)
        #expect(again.currencyCode == "JPY")
        again.destination = .list(lists.pinned.uuid)
        #expect(again.groupID == a.uuid)
    }

    @Test("SE-09 Save writes exactly one item at the end of the group with the shared link")
    func save() throws {
        let lists = makeLists()
        let group = fixture.store.createGroup(name: "Living room", in: lists.pinned)
        fixture.addItem("Old", to: group)
        let before = try fixture.count(ItemModel.self)

        let composer = try model("https://www.ikea.com/p/kivik?color=blue")
        composer.titleArrived("KIVIK 3-seat sofa - IKEA")
        composer.editName("  Sofa for the living room ")
        composer.priceText = "449.004"
        composer.isMustHave = true
        let item = try #require(composer.save())

        #expect(try fixture.count(ItemModel.self) == before + 1)
        #expect(item.group === group)
        #expect(group.sortedItems.last === item)
        #expect(item.name == "Sofa for the living room")
        #expect(item.quantity == 1)
        #expect(item.price == Decimal(string: "449"))
        #expect(item.isMustHave)
        #expect(!item.isComplete)
        #expect(item.notes.isEmpty)
        #expect(item.urlString == "https://www.ikea.com/p/kivik?color=blue")
        #expect(item.linkHost == "ikea.com")
        #expect(item.linkTitle == "KIVIK 3-seat sofa") // the page's, not the edited name
        #expect(item.linkImageData == nil)
        #expect(item.linkFetchedAt == nil) // the app loads the picture (LP-01b)
        #expect(shareDefaults.lastListID == lists.pinned.uuid)
        #expect(shareDefaults.lastGroupID(in: lists.pinned.uuid) == group.uuid)
    }

    @Test("SE-09 a list without groups gets the group \"Items\"; no price stays nil, ★ off by default")
    func saveWithoutGroups() throws {
        let lists = makeLists()
        let composer = try model()
        composer.destination = .list(lists.first.uuid)
        #expect(!composer.isMustHave)
        let item = try #require(composer.save())
        #expect(item.group?.name == items)
        #expect(item.group?.list === lists.first)
        #expect(item.price == nil)
        #expect(!item.isMustHave)
        #expect(item.name == "ikea.com") // no title, no text: the host (SE-02)
    }

    @Test("SE-05 no active list: a new list in the main currency with \"Items\" and the item")
    func newListWhenEmpty() throws {
        let composer = try model(text: "Lamp - IKEA", mainCurrency: "GBP")
        #expect(composer.lists.isEmpty)
        #expect(composer.destination == .newList)
        #expect(composer.newListName == wishlist)
        #expect(composer.currencyCode == "GBP")
        #expect(composer.name == "Lamp")
        #expect(composer.pageTitle == "Lamp") // also the card and `linkTitle`
        composer.priceText = "12.5"
        let item = try #require(composer.save())
        let list = try #require(item.parentList)
        #expect(try fixture.count(ListModel.self) == 1)
        #expect(list.name == wishlist)
        #expect(list.currencyCode == "GBP")
        #expect(list.groups?.map(\.name) == [items])
        #expect(item.price == Decimal(string: "12.5"))
    }

    @Test("SE-05 a blank new list name becomes \"Untitled list\" and doesn't block Save")
    func blankNewListName() throws {
        let composer = try model()
        composer.newListName = "   "
        #expect(composer.canSave)
        #expect(try #require(composer.save()).parentList?.name == untitled)
    }

    @Test("\"New List…\" with existing lists creates a new list instead")
    func newListChosen() throws {
        _ = makeLists()
        let composer = try model()
        composer.destination = .newList
        composer.newListName = "Gifts"
        #expect(composer.groups.isEmpty)
        let item = try #require(composer.save())
        #expect(item.parentList?.name == "Gifts")
        #expect(try fixture.count(ListModel.self) == 4)
    }

    @Test("SE-06 price: empty → nil, invalid → error and no Save, rounded to the list currency")
    func price() throws {
        let lists = makeLists()
        let composer = try model(locale: "ru_RU")
        #expect(!composer.hasPriceError)
        composer.priceText = "abc"
        #expect(composer.hasPriceError)
        #expect(!composer.canSave)
        #expect(composer.save() == nil)
        composer.priceText = "-5"
        #expect(composer.hasPriceError)
        composer.priceText = "1299,5"
        #expect(composer.parsedPrice == .amount(Decimal(string: "1299.5")!))
        composer.destination = .list(lists.second.uuid) // JPY: no fraction digits
        #expect(composer.parsedPrice == .amount(Decimal(1300)))
        composer.priceText = ""
        #expect(composer.parsedPrice == .empty)
        #expect(composer.canSave)
    }

    @Test("SE-09a Save is off for a blank name")
    func blankName() throws {
        let composer = try model()
        composer.editName("   ")
        #expect(!composer.canSave)
        #expect(composer.save() == nil)
        #expect(try fixture.count(ItemModel.self) == 0)
    }

    @Test("SE-02a a late title replaces the prefilled name, never the user's own")
    func lateTitle() throws {
        let composer = try model(text: "From the app")
        #expect(composer.name == "From the app")
        composer.titleArrived("Page title - IKEA")
        #expect(composer.name == "Page title")
        composer.editName("Mine")
        composer.titleArrived("Other title")
        #expect(composer.name == "Mine")
        #expect(composer.pageTitle == "Other title")
    }

    /// Answers with `title` after `delay`; a cancelled wait throws at once.
    private struct DelayedFetcher: LinkMetadataFetching {
        let delay: Duration
        let title: String

        func fetch(_ url: URL) async throws -> LinkPreview {
            try await Task.sleep(for: delay)
            return LinkPreview(title: title, imageData: nil)
        }
    }

    @Test("B2 the page title from the fetcher replaces the prefilled host")
    func fetchedTitle() async throws {
        let composer = try model(fetcher: DelayedFetcher(delay: .milliseconds(10), title: "KIVIK sofa - IKEA"))
        composer.start()
        for _ in 0..<200 where composer.pageTitle == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(composer.name == "KIVIK sofa")
    }

    @Test("B.4 p.5 a title slower than the timeout is dropped; the name stays the host")
    func titleTimeout() async throws {
        let composer = try model(fetcher: DelayedFetcher(delay: .seconds(30), title: "Late"),
                                 titleTimeout: .milliseconds(50))
        composer.start()
        try await Task.sleep(for: .milliseconds(500))
        #expect(composer.pageTitle == nil)
        #expect(composer.name == "ikea.com")
    }

    @Test("SE-09b not saving (Cancel) writes nothing and keeps the last list")
    func cancel() throws {
        let lists = makeLists()
        let group = fixture.store.createGroup(name: "G", in: lists.second)
        shareDefaults.recordSave(listID: lists.second.uuid, groupID: group.uuid)
        let lists0 = try fixture.count(ListModel.self), items0 = try fixture.count(ItemModel.self)
        let composer = try model()
        composer.destination = .list(lists.pinned.uuid)
        composer.cancel()
        #expect(try fixture.count(ListModel.self) == lists0)
        #expect(try fixture.count(ItemModel.self) == items0)
        #expect(shareDefaults.lastListID == lists.second.uuid)
    }
}

// MARK: - Extension store and the app's inbox

@MainActor
@Suite("Share Extension: shared store and inbox", .tags(.shareExtension, .iCloudSync))
final class ShareStoreTests {
    private let root = URL.temporaryDirectory.appending(path: "ShareStoreTests-\(UUID().uuidString)",
                                                       directoryHint: .isDirectory)
    private let suiteName = "ShareStoreTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("SE-11a the extension uses the group's store, never CloudKit; no App Group → unavailable")
    func extensionLocation() throws {
        let group = root.appending(path: "Group", directoryHint: .isDirectory)
        let location = try #require(StoreLocation.forShareExtension(appGroupContainer: group))
        let app = StoreLocation.resolve(appGroupContainer: group, applicationSupport: root, isCloudKitEnabled: true)
        #expect(location.storeURL == app.storeURL)
        #expect(!location.usesCloudKit)
        #expect(app.usesCloudKit)
        #expect(StoreLocation.forShareExtension(appGroupContainer: nil) == nil)
    }

    /// The extension's stack: its own container on the file, author "shareExtension".
    private func extensionStore(at location: StoreLocation) throws -> (ModelContainer, PlannerStore) {
        let container = try Persistence.makeContainer(at: location)
        container.mainContext.author = ShareInbox.author
        return (container, PlannerStore(context: container.mainContext, defaultCurrencyCode: "EUR"))
    }

    @Test("SE-12 the extension creates the store file; then the app opens it with the same schema")
    func extensionCreatesStore() throws {
        let location = try #require(StoreLocation.forShareExtension(appGroupContainer: root))
        #expect(!FileManager.default.fileExists(atPath: location.storeURL.path))
        do {
            // The container must outlive its context (`_` would release it at once).
            let (container, store) = try extensionStore(at: location)
            withExtendedLifetime(container) {
                let list = store.createList(name: "Wishlist")
                let group = store.createGroup(name: "Items", in: list)
                #expect(store.addSharedItem(name: "Lamp", to: group, price: 10, urlString: "https://example.com/lamp",
                                            pageTitle: nil, isMustHave: false) != nil)
            }
        }
        #expect(FileManager.default.fileExists(atPath: location.storeURL.path))
        // The app's container (`.none` here: tests never use CloudKit).
        let app = try Persistence.makeContainer(at: location)
        let items = try app.mainContext.fetch(FetchDescriptor<ItemModel>())
        #expect(items.map(\.name) == ["Lamp"])
    }

    @Test("SE-10 a group already loaded in the app shows the extension's item after pull")
    func loadedRelationshipIsUpdated() throws {
        let location = try #require(StoreLocation.forShareExtension(appGroupContainer: root))
        let app = try Persistence.makeContainer(at: location)
        let appStore = PlannerStore(context: app.mainContext, defaultCurrencyCode: "EUR")
        let appList = appStore.createList(name: "Mine")
        let appGroup = appStore.createGroup(name: "G", in: appList)
        appStore.addItem(name: "App item", to: appGroup)
        #expect(appGroup.items?.count == 1) // loaded, as on the list screen

        let (extensionContainer, store) = try extensionStore(at: location)
        let group = try #require(try extensionContainer.mainContext.fetch(FetchDescriptor<GroupModel>()).first)
        #expect(store.addSharedItem(name: "Shared", to: group, price: nil, urlString: "https://example.com/a",
                                    pageTitle: nil, isMustHave: false) != nil)

        let ids = ShareInbox(context: app.mainContext, defaults: defaults).pull()
        #expect(ids.count == 1)
        #expect(appGroup.items?.map(\.name).sorted() == ["App item", "Shared"])
        #expect(appList.allItems.count == 2)
    }

    @Test("SE-10 a list already loaded in the app shows the group the extension created")
    func loadedListGetsNewGroup() throws {
        let location = try #require(StoreLocation.forShareExtension(appGroupContainer: root))
        let app = try Persistence.makeContainer(at: location)
        let appStore = PlannerStore(context: app.mainContext, defaultCurrencyCode: "EUR")
        let appList = appStore.createList(name: "Empty")
        #expect(appList.groups?.isEmpty == true)

        let (extensionContainer, store) = try extensionStore(at: location)
        let list = try #require(try extensionContainer.mainContext.fetch(FetchDescriptor<ListModel>()).first)
        let group = store.createGroup(name: "Items", in: list)
        #expect(store.addSharedItem(name: "Shared", to: group, price: nil, urlString: "https://example.com/a",
                                    pageTitle: nil, isMustHave: false) != nil)

        #expect(ShareInbox(context: app.mainContext, defaults: defaults).pull().count == 1)
        #expect(appList.sortedGroups.map(\.name) == ["Items"])
        #expect(appList.allItems.map(\.name) == ["Shared"])
    }

    @Test("SE-10b the inbox returns the extension's new items once and ignores the app's own")
    func inbox() throws {
        let location = try #require(StoreLocation.forShareExtension(appGroupContainer: root))
        let app = try Persistence.makeContainer(at: location)
        let appStore = PlannerStore(context: app.mainContext, defaultCurrencyCode: "EUR")
        let appList = appStore.createList(name: "Mine")
        let appGroup = appStore.createGroup(name: "G", in: appList)
        appStore.addItem(name: "App item", to: appGroup)

        let inbox = ShareInbox(context: app.mainContext, defaults: defaults)
        #expect(inbox.pull().isEmpty) // only the app's transactions so far

        let (extensionContainer, store) = try extensionStore(at: location)
        let list = try #require(try extensionContainer.mainContext.fetch(FetchDescriptor<ListModel>()).first)
        let group = try #require(list.groups?.first)
        let shared = try #require(store.addSharedItem(name: "Shared", to: group, price: nil,
                                                       urlString: "https://example.com/a", pageTitle: nil,
                                                       isMustHave: false))
        let sharedID = shared.uuid

        #expect(inbox.pull() == [sharedID])
        #expect(inbox.pull().isEmpty) // the token moved on
        // The app's context sees the item without a new container.
        let names = try app.mainContext.fetch(FetchDescriptor<ItemModel>()).map(\.name).sorted()
        #expect(names == ["App item", "Shared"])

        appStore.addItem(name: "Another app item", to: appGroup)
        #expect(inbox.pull().isEmpty)
        // A new inbox with the same defaults continues from the saved token.
        #expect(ShareInbox(context: app.mainContext, defaults: defaults).pull().isEmpty)
    }
}
