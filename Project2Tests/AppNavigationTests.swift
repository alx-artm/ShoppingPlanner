//
//  AppNavigationTests.swift
//  Project2Tests
//
//  Spec 08 (AD-04, AD-05) and spec 01 DM-18 / spec 02 HM-10 / spec 03 LI-10:
//  the split-view selection, and deleting a list that is open in the detail
//  column only after that column has closed, so no view reads a deleted model.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("AppNavigation", .tags(.navigation, .deletion))
struct AppNavigationTests {
    let f: StoreFixture
    let navigation = AppNavigation()
    init() throws { f = try StoreFixture() }

    func names() throws -> Set<String> {
        Set(try f.context.fetch(FetchDescriptor<ListModel>()).map(\.name))
    }

    // MARK: - Selection

    @Test("AD-03 selecting a list stores its uuid; isSelected follows it")
    func select() {
        let a = f.store.createList(name: "A")
        let b = f.store.createList(name: "B")
        #expect(navigation.selectedListID == nil)

        navigation.select(a)
        #expect(navigation.selectedListID == a.uuid)
        #expect(navigation.isSelected(a))
        #expect(!navigation.isSelected(b))

        navigation.select(b)
        #expect(navigation.isSelected(b))
        #expect(!navigation.isSelected(a))
    }

    @Test("AD-04 a restored selection is kept when its list exists")
    func restoredSelectionKept() {
        let a = f.store.createList(name: "A")
        let restored = AppNavigation(selectedListID: a.uuid)
        restored.dropSelectionIfMissing(existing: [a.uuid])
        #expect(restored.selectedListID == a.uuid)
    }

    @Test("AD-05 a selection pointing to a missing list is dropped (detail shows the placeholder)")
    func missingSelectionDropped() {
        let a = f.store.createList(name: "A")
        let restored = AppNavigation(selectedListID: UUID())
        restored.dropSelectionIfMissing(existing: [a.uuid])
        #expect(restored.selectedListID == nil)

        let none = AppNavigation()
        none.dropSelectionIfMissing(existing: [])
        #expect(none.selectedListID == nil)
    }

    // MARK: - DM-18 deleting the open list

    @Test("DM-18 the selected list is deleted only after the detail closes")
    func selectedListWaitsForDetail() throws {
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B")
        navigation.select(a)

        navigation.requestDeletion(of: a, using: f.store)

        // Step 1: the detail is asked to close; the model is still alive for it.
        #expect(navigation.selectedListID == nil)
        #expect(try names() == ["A", "B"])
        #expect(a.name == "A", "the open screen can still read the list")

        // Step 2: the detail is gone → now it is deleted.
        navigation.detailDidClose(using: f.store)
        #expect(try names() == ["B"])
        #expect(f.store.lastErrorMessage == nil)
    }

    @Test("DM-18 a list that isn't open is deleted at once; the selection stays")
    func otherListDeletedImmediately() throws {
        let a = f.store.createList(name: "A")
        let b = f.store.createList(name: "B")
        navigation.select(a)

        navigation.requestDeletion(of: b, using: f.store)

        #expect(try names() == ["A"])
        #expect(navigation.selectedListID == a.uuid)

        // A later close of A's detail must not delete A.
        navigation.detailDidClose(using: f.store)
        #expect(try names() == ["A"])
    }

    @Test("DM-18 with nothing selected the list is deleted at once")
    func nothingSelected() throws {
        let a = f.store.createList(name: "A")
        navigation.requestDeletion(of: a, using: f.store)
        #expect(try names().isEmpty)
    }

    @Test("DM-18 closing the detail without a pending deletion deletes nothing")
    func closeWithoutPending() throws {
        let a = f.store.createList(name: "A")
        navigation.select(a)
        navigation.selectedListID = nil // back button
        navigation.detailDidClose(using: f.store)
        #expect(try names() == ["A"])
    }

    @Test("DM-18 the pending deletion runs once, even if detailDidClose is called again")
    func deletesOnce() throws {
        let (a, group) = f.makeGroup(listName: "A")
        f.addItem("Item", to: group)
        f.store.createList(name: "B")
        navigation.select(a)

        navigation.requestDeletion(of: a, using: f.store)
        navigation.detailDidClose(using: f.store)
        navigation.detailDidClose(using: f.store) // placeholder onAppear after the list's onDisappear

        #expect(try names() == ["B"])
        #expect(try f.count(GroupModel.self) == 0, "cascade (DM-08)")
        #expect(try f.count(ItemModel.self) == 0)
        #expect(f.store.lastErrorMessage == nil)
    }

    @Test("AD-05 after the deletion the selection can't point to the deleted list")
    func selectionAfterDeletion() throws {
        let a = f.store.createList(name: "A")
        let b = f.store.createList(name: "B")
        navigation.select(a)
        navigation.requestDeletion(of: a, using: f.store)
        navigation.detailDidClose(using: f.store)

        let ids = Set(try f.context.fetch(FetchDescriptor<ListModel>()).map(\.uuid))
        navigation.dropSelectionIfMissing(existing: ids)
        #expect(navigation.selectedListID == nil)

        navigation.select(b)
        navigation.dropSelectionIfMissing(existing: ids)
        #expect(navigation.selectedListID == b.uuid)
    }

    @Test("LI-10 deleting from List Info of a list that is open waits for the detail too")
    func deleteFromListInfo() throws {
        // ListInfoView calls requestDeletion in onDisappear (after the sheet is gone).
        let a = f.store.createList(name: "A")
        navigation.select(a)
        navigation.requestDeletion(of: a, using: f.store)
        #expect(try names() == ["A"])
        navigation.detailDidClose(using: f.store)
        #expect(try names().isEmpty)
    }
}
