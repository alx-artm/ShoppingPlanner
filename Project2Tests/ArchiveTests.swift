//
//  ArchiveTests.swift
//  Project2Tests
//
//  Spec 10 (List Archive): the store's archive / restore rules (AR-01…AR-06),
//  what Home shows with archived lists (AR-07, AR-08, AR-13, AR-20), the
//  Archive order and search (AR-15, AR-19), and closing an open list before
//  it is archived (AR-12).
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("List Archive", .tags(.archive))
struct ArchiveTests {
    let f: StoreFixture
    init() throws { f = try StoreFixture() }

    /// Every list in the store, in no particular order (like `@Query` without a sort).
    func allLists() throws -> [ListModel] {
        var rng = SeededGenerator(seed: 10)
        return try f.context.fetch(FetchDescriptor<ListModel>()).shuffled(using: &rng)
    }

    func sections(query: String = "") throws -> HomeSections {
        HomeSections(lists: try allLists(), query: query)
    }

    /// Everything AR-02 says archiving must not change.
    struct ContentSnapshot: Equatable {
        struct Item: Equatable {
            var name: String
            var price: Decimal?
            var quantity: Int
            var isComplete: Bool
        }
        var name: String
        var groups: [String]
        var items: [Item]
        var budget: Decimal?
        var currencyCode: String
        var iconName: String
        var iconKind: ListIconKind
        var color: FavoriteColor

        @MainActor
        init(_ list: ListModel) {
            name = list.name
            groups = list.sortedGroups.map(\.name)
            items = list.sortedGroups.flatMap(\.sortedItems).map {
                Item(name: $0.name, price: $0.price, quantity: $0.quantity, isComplete: $0.isComplete)
            }
            budget = list.budget
            currencyCode = list.currencyCode
            iconName = list.iconName
            iconKind = list.iconKind
            color = list.color
        }
    }

    /// A pinned list with two groups, prices, a bought item, a budget, an emoji and a color.
    func makeFullList(name: String = "Kitchen") -> ListModel {
        let list = f.store.createList(name: name, iconName: "🍳", iconKind: .emoji, color: .green,
                                      isPinned: true, budget: dec("3000"), currencyCode: "EUR")
        let tiles = f.store.createGroup(name: "Tiles", in: list)
        let light = f.store.createGroup(name: "Light", in: list)
        f.addItem("Floor tiles", to: tiles, quantity: 12, price: dec("45.90"))
        let lamp = f.addItem("Lamp", to: light, price: dec("120"))
        f.addItem("Bulbs", to: light, quantity: 4)
        f.store.toggleComplete(lamp)
        return list
    }

    // MARK: - Data & store

    @Test("AR-01 a list starts active; createList and templates never archive")
    func newListsAreActive() {
        #expect(ListModel().isArchived == false)
        #expect(f.store.createList(name: "A").archivedAt == nil)

        var draft = ListDraft(currencyCode: "USD")
        draft.name = "From template"
        draft.groupNames = ["Kitchen", "Bath"]
        #expect(f.store.createList(from: draft).archivedAt == nil)
    }

    @Test("AR-02 archive stamps the date, unpins, and leaves the content as it was")
    func archiveKeepsContent() throws {
        let list = makeFullList()
        let before = ContentSnapshot(list)
        f.clock.advance(by: 3600)

        f.store.archiveList(list)

        #expect(list.archivedAt == f.clock.now)
        #expect(list.isArchived)
        #expect(list.isPinned == false)
        #expect(ContentSnapshot(list) == before)
        #expect(try f.count(GroupModel.self) == 2)
        #expect(try f.count(ItemModel.self) == 3)
        #expect(f.store.lastErrorMessage == nil)
    }

    @Test("AR-02 archiving an archived list keeps the first date")
    func archiveTwice() {
        let list = f.store.createList(name: "A")
        f.store.archiveList(list)
        let first = list.archivedAt
        f.clock.advance(by: 86_400)

        f.store.archiveList(list)

        #expect(list.archivedAt == first)
    }

    @Test("AR-03 restore makes the list active, not pinned, first in All Lists", .tags(.ordering))
    func restoreGoesFirst() throws {
        let old = f.store.createList(name: "Old")
        f.store.createList(name: "B")
        f.store.createList(name: "C", isPinned: true)
        f.store.archiveList(old)
        f.store.createList(name: "Newest")

        f.store.restoreList(old)

        #expect(old.archivedAt == nil)
        #expect(old.isPinned == false)
        let home = try sections()
        #expect(home.others.map(\.name) == ["Old", "Newest", "B"])
        #expect(home.pinned.map(\.name) == ["C"])
        #expect(home.archivedCount == 0)
    }

    @Test("AR-03 restoring an active list changes nothing")
    func restoreActive() throws {
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B")
        let index = a.sortIndex

        f.store.restoreList(a)

        #expect(a.sortIndex == index)
        #expect(try sections().others.map(\.name) == ["B", "A"])
    }

    @Test("AR-04 duplicating an archived list makes an active copy, first in All Lists; the original stays archived")
    func duplicateArchived() throws {
        let list = makeFullList()
        f.store.createList(name: "Other")
        f.store.archiveList(list)

        let copy = f.store.duplicateList(list)

        #expect(copy.archivedAt == nil)
        #expect(copy.isPinned == false)
        #expect(list.isArchived)
        let home = try sections()
        #expect(home.others.first === copy)
        #expect(home.archivedCount == 1)
        #expect(HomeSections.archived(try allLists()).map(\.uuid) == [list.uuid])
    }

    @Test("AR-05 deleting an archived list cascades; nothing is kept anywhere", .tags(.deletion))
    func deleteArchived() throws {
        let list = makeFullList()
        f.store.createList(name: "Other")
        f.store.archiveList(list)

        f.store.deleteList(list)

        #expect(try f.count(ListModel.self) == 1)
        #expect(try f.count(GroupModel.self) == 0)
        #expect(try f.count(ItemModel.self) == 0)
        #expect(try sections().archivedCount == 0)
    }

    @Test("AR-06 archive → restore returns the same content; a pinned list comes back in All Lists")
    func roundTrip() throws {
        let list = makeFullList()
        let before = ContentSnapshot(list)

        f.store.archiveList(list)
        f.store.restoreList(list)

        #expect(ContentSnapshot(list) == before)
        #expect(list.isPinned == false)
        #expect(list.isArchived == false)
        let home = try sections()
        #expect(home.pinned.isEmpty)
        #expect(home.others.map(\.uuid) == [list.uuid])
    }

    @Test("An archived list can't be pinned, from the store or from List Info")
    func archivedNeverPinned() {
        let list = f.store.createList(name: "A")
        f.store.archiveList(list)

        f.store.togglePin(list)
        #expect(list.isPinned == false)

        var draft = ListDraft(list: list)
        draft.isPinned = true
        draft.name = "Renamed"
        f.store.updateList(list, with: draft)
        #expect(list.isPinned == false)
        #expect(list.name == "Renamed", "the rest of List Info still applies (AR-22)")
    }

    @Test("A new list and a new pinned list ignore the sortIndex of archived lists", .tags(.ordering))
    func newListPlacementIgnoresArchive() throws {
        let archived = f.store.createList(name: "Archived")
        f.store.archiveList(archived)
        archived.sortIndex = -100 // whatever it was, it must not matter
        f.store.createList(name: "A")

        let pinned = f.store.createList(name: "P", isPinned: true)
        let b = f.store.createList(name: "B")

        #expect(pinned.sortIndex == 0, "first pinned list")
        #expect(b.sortIndex == -1, "before A, not before the archived list")
    }

    // MARK: - Home

    @Test("AR-07 Home sections and lists(pinned:) leave archived lists out")
    func sectionsWithoutArchived() throws {
        let pinned = f.store.createList(name: "Pinned", isPinned: true)
        f.store.createList(name: "Active")
        let archived = f.store.createList(name: "Gone", isPinned: true)
        f.store.archiveList(archived)
        _ = pinned

        let home = try sections()
        #expect(home.pinned.map(\.name) == ["Pinned"])
        #expect(home.others.map(\.name) == ["Active"])
        #expect(f.store.lists(pinned: true).map(\.name) == ["Pinned"])
        #expect(f.store.lists(pinned: false).map(\.name) == ["Active"])
    }

    @Test("AR-08 the Archive row shows with ≥ 1 archived list and counts them")
    func archiveRow() throws {
        let a = f.store.createList(name: "A")
        let b = f.store.createList(name: "B")
        #expect(try sections().showsArchiveRow == false)

        f.store.archiveList(a)
        f.store.archiveList(b)
        var home = try sections()
        #expect(home.showsArchiveRow)
        #expect(home.archivedCount == 2)

        f.store.restoreList(a)
        f.store.deleteList(b)
        home = try sections()
        #expect(home.showsArchiveRow == false, "gone after the last archived list leaves")
    }

    @Test("Archived lists never make Reorder Lists available (HM-32)")
    func reorderIgnoresArchive() throws {
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B")
        #expect(try sections().canReorder)

        f.store.archiveList(a)
        let home = try sections()
        #expect(home.canReorder == false, "one active list and one archived: nothing to reorder")
    }

    @Test("AR-13 all lists archived: 'No Active Lists' and the Archive row, not the onboarding state")
    func noActiveLists() throws {
        #expect(try sections().showsNoActiveLists == false, "no lists at all: onboarding (HM-14)")

        let a = f.store.createList(name: "A")
        #expect(try sections().showsNoActiveLists == false)

        f.store.archiveList(a)
        let home = try sections()
        #expect(home.showsNoActiveLists)
        #expect(home.showsArchiveRow)
        #expect(home.isEmpty)
        #expect(home.hasActiveLists == false)
    }

    @Test("AR-20 a search also lists matching archived lists; no 'No Results' when only they match")
    func searchInArchive() throws {
        f.store.createList(name: "Gifts 2026")
        let old = f.store.createList(name: "Gifts 2025")
        let trip = f.store.createList(name: "Trip")
        f.store.archiveList(old)
        f.store.archiveList(trip)

        var home = try sections(query: "gifts")
        #expect(home.others.map(\.name) == ["Gifts 2026"])
        #expect(home.archiveMatches.map(\.name) == ["Gifts 2025"])
        #expect(home.showsArchiveRow == false, "the section replaces the row while searching")
        #expect(home.showsNoSearchResults == false)

        home = try sections(query: "TRÍP")
        #expect(home.isEmpty)
        #expect(home.archiveMatches.map(\.name) == ["Trip"])
        #expect(home.showsNoSearchResults == false)
        #expect(home.showsNoActiveLists == false)

        home = try sections(query: "zzz")
        #expect(home.showsNoSearchResults)

        home = try sections(query: "  ")
        #expect(home.archiveMatches.isEmpty, "no section for a blank query")
        #expect(home.showsArchiveRow)
    }

    // MARK: - Archive screen

    @Test("AR-15 the Archive lists the last archived first; AR-19 its search uses Home's rules")
    func archiveOrderAndSearch() throws {
        let first = f.store.createList(name: "Kitchen renovation")
        let second = f.store.createList(name: "Gifts 2025")
        let third = f.store.createList(name: "Café trip")
        f.store.createList(name: "Active")
        for list in [first, second, third] {
            f.clock.advance(by: 60)
            f.store.archiveList(list)
        }

        #expect(HomeSections.archived(try allLists()).map(\.name)
                == ["Café trip", "Gifts 2025", "Kitchen renovation"])
        #expect(HomeSections.archived(try allLists(), query: "cafe").map(\.name) == ["Café trip"])
        #expect(HomeSections.archived(try allLists(), query: "zzz").isEmpty)

        // Restored and archived again: it moves to the top.
        f.store.restoreList(first)
        f.clock.advance(by: 60)
        f.store.archiveList(first)
        #expect(HomeSections.archived(try allLists()).first === first)
    }

    // MARK: - AR-12 archiving the open list

    @Test("AR-12 the open list is archived only after its screen closed")
    func archiveOpenList() throws {
        let navigation = AppNavigation()
        let a = f.store.createList(name: "A")
        navigation.select(a)

        navigation.requestArchive(of: a, using: f.store)

        #expect(navigation.selectedListID == nil, "the detail closes first")
        #expect(navigation.pendingAction == .archive)
        #expect(a.isArchived == false)

        navigation.detailDidClose(using: f.store)
        navigation.detailDidClose(using: f.store) // placeholder onAppear: runs once
        #expect(a.isArchived)
        #expect(navigation.pendingAction == nil)
        #expect(try f.count(ListModel.self) == 1, "archived, not deleted")
    }

    @Test("AR-12 a list that isn't open is archived at once; the selection stays")
    func archiveOtherList() {
        let navigation = AppNavigation()
        let a = f.store.createList(name: "A")
        let b = f.store.createList(name: "B")
        navigation.select(a)

        navigation.requestArchive(of: b, using: f.store)

        #expect(b.isArchived)
        #expect(navigation.selectedListID == a.uuid)
        navigation.detailDidClose(using: f.store)
        #expect(a.isArchived == false)
    }

    @Test("AR-14 the Archive opens in Home's column and keeps the detail's selection")
    func showArchive() {
        let navigation = AppNavigation()
        let a = f.store.createList(name: "A")
        navigation.select(a)

        navigation.showArchive()

        #expect(navigation.sidebarPath == [.archive])
        #expect(navigation.selectedListID == a.uuid)
    }

    @Test("AR-04 Duplicate from the Archive opens the active copy; the Archive stays in Home's column")
    func duplicateOpensCopy() throws {
        let navigation = AppNavigation()
        let list = makeFullList()
        f.store.archiveList(list)
        navigation.showArchive()

        let copy = navigation.openDuplicate(of: list, using: f.store)

        #expect(navigation.selectedListID == copy.uuid, "iPhone pushes the copy, iPad shows it in the detail")
        #expect(copy.uuid != list.uuid)
        #expect(copy.isArchived == false)
        #expect(list.isArchived, "the original stays archived")
        #expect(navigation.sidebarPath == [.archive], "back from the copy returns to the Archive")
        #expect(navigation.pendingAction == nil)
        #expect(try f.count(ListModel.self) == 2)
    }

    @Test("AR-26 an archived list keeps its selection: the open screen stays (with the banner)")
    func archivedSelectionKept() throws {
        let navigation = AppNavigation()
        let a = f.store.createList(name: "A")
        navigation.select(a)
        f.store.archiveList(a) // e.g. on another device

        navigation.dropSelectionIfMissing(existing: Set(try allLists().map(\.uuid)))
        #expect(navigation.selectedListID == a.uuid)
    }

    // MARK: - AR-23, AR-25 texts

    /// The `.lproj` of one language, so a text is checked in that language whatever the
    /// test host runs in.
    static func languageBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// The same key as Home's Archive row (`HomeView.archiveRow`): an `Int` is `%lld`.
    static func archiveRowLabel(_ count: Int, language: String, locale: String) throws -> String {
        String(localized: "Archive, \(count) lists", bundle: try languageBundle(language),
               locale: Locale(identifier: locale))
    }

    @Test("AR-23 RU: the Archive row's VoiceOver count uses список / списка / списков",
          arguments: [(1, "Архив, 1 список"), (2, "Архив, 2 списка"), (4, "Архив, 4 списка"),
                      (5, "Архив, 5 списков"), (11, "Архив, 11 списков"), (12, "Архив, 12 списков"),
                      (21, "Архив, 21 список"), (22, "Архив, 22 списка"), (25, "Архив, 25 списков"),
                      (101, "Архив, 101 список"), (111, "Архив, 111 списков")])
    func archiveRowPluralRussian(count: Int, expected: String) throws {
        #expect(try Self.archiveRowLabel(count, language: "ru", locale: "ru_RU") == expected)
    }

    @Test("AR-23 EN: 'Archive, 1 list', 'Archive, N lists'",
          arguments: [(1, "Archive, 1 list"), (2, "Archive, 2 lists"), (11, "Archive, 11 lists"),
                      (21, "Archive, 21 lists")])
    func archiveRowPluralEnglish(count: Int, expected: String) throws {
        #expect(try Self.archiveRowLabel(count, language: "en", locale: "en_US") == expected)
    }

    /// The RU column of spec 10's Texts table. A key missing from the catalog would come back
    /// as the English key itself.
    nonisolated static let russianTexts: [(key: String, ru: String)] = [
        ("action.archive", "В архив"),
        ("Archive", "Архив"),
        ("Restore", "Вернуть"),
        ("Archived on %@", "В архиве с %@"),
        ("Search Archive", "Поиск в архиве"),
        ("In Archive", "В архиве"),
        ("No Archived Lists", "Архив пуст"),
        ("Archived lists keep all their items and prices.",
         "В архиве списки хранятся со всеми товарами и ценами."),
        ("No Active Lists", "Нет активных списков"),
        ("Create a new list or restore one from the Archive.",
         "Создайте новый список или верните его из архива."),
        ("“%@” archived", "Список «%@» перемещён в архив"),
        ("“%@” restored", "Список «%@» возвращён"),
    ]

    @Test("AR-25 every text of spec 10 has its Russian translation", arguments: russianTexts)
    func russianCatalog(key: String, ru: String) throws {
        let bundle = try Self.languageBundle("ru")
        #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == ru)
    }
}

