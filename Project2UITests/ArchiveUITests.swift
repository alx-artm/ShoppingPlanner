//
//  ArchiveUITests.swift
//  Project2UITests
//
//  Spec 10 (List Archive) end to end on the seed data (en_US): Alex is pinned
//  (a tile), Eva and Victoria are rows in All Lists. Archive from a swipe, a
//  tile's menu and the open list's ⋯ (AR-10…AR-12); the Archive row and screen
//  (AR-08, AR-14, AR-21); the banner of an archived list and its Restore
//  (AR-16, AR-17); "No Active Lists" (AR-13); "In Archive" in Home's search
//  and deleting from it (AR-18, AR-20). Runs on iPhone and iPad.
//

import UIKit
import XCTest

final class ArchiveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// AR-08, AR-10, AR-11, AR-14, AR-17, AR-21: swipe → Archive hides the row and shows
    /// "Archive 1"; in the Archive, swipe → Restore empties it (the screen stays), and back on
    /// Home the list is first in All Lists and the Archive row is gone.
    @MainActor
    func testArchiveWithSwipeThenRestoreFromArchive() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        XCTAssertFalse(home.archiveRow.exists, "no Archive row without archived lists")

        home.archiveWithSwipe(row: "Victoria")
        home.row("Victoria").waitToDisappear()
        home.archiveRow.waitForLabel("Archive, 1 list")

        let archive = home.openArchive()
        archive.row("Victoria").waitToAppear()
        archive.restoreWithSwipe("Victoria")
        archive.emptyState.waitToAppear()
        archive.row("Victoria").waitToDisappear()

        _ = archive.goBack()
        home.archiveRow.waitToDisappear()
        XCTAssertLessThan(home.top(of: home.row("Victoria")), home.top(of: home.row("Eva")),
                          "a restored list is first in All Lists (AR-03)")
    }

    /// AR-10, AR-11, AR-16, AR-17, AR-22: a pinned list archived from its tile's menu; opened
    /// from the Archive it shows the banner and stays editable; Restore in the banner keeps it
    /// open, the banner goes, and on Home it is a row (not pinned) first in All Lists.
    @MainActor
    func testArchivedListShowsBannerAndRestoresFromIt() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        home.archiveFromContextMenu(card: "Alex")
        home.card("Alex").waitToDisappear()

        let archive = home.openArchive()
        let alex = archive.open("Alex")
        alex.archivedBanner.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Archived on"))
            .firstMatch.waitToAppear()
        alex.archivedBannerRestoreButton.waitToBeHittable()

        // AR-22: editing works in an archived list.
        alex.checkbox("Sunglasses").waitAndTap()
        alex.checkbox("Sunglasses").waitForSelected(true)
        alex.archivedBanner.waitToAppear()

        alex.archivedBannerRestoreButton.tap()
        alex.archivedBanner.waitToDisappear()
        alex.menuButton.waitToAppear()
        alex.checkbox("Sunglasses").waitForSelected(true)

        if !isPad {
            alex.backButton.waitAndTap()
        }
        archive.emptyState.waitToAppear()
        _ = archive.goBack()
        home.row("Alex").waitToAppear()
        XCTAssertFalse(home.card("Alex").exists, "restored lists are not pinned (AR-06)")
        XCTAssertLessThan(home.top(of: home.row("Alex")), home.top(of: home.row("Eva")))
    }

    /// AR-10, AR-12: ⋯ → Archive in the open list closes it first (iPhone: back to Home;
    /// iPad: "Select a List"), then the list is in the Archive.
    @MainActor
    func testArchiveOpenListFromItsMenu() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()

        let eva = home.open(row: "Eva")
        eva.menuAction("archive")

        if isPad {
            app.descendants(matching: .any)["detail.placeholder"].firstMatch.waitToAppear()
        }
        eva.menuButton.waitToDisappear()
        home.row("Eva").waitToDisappear()
        home.archiveRow.waitForLabel("Archive, 1 list")
        XCTAssertEqual(app.state, .runningForeground)

        let archive = home.openArchive()
        archive.row("Eva").waitToAppear()
    }

    /// AR-13: archiving the only list shows "No Active Lists" (not the onboarding state)
    /// with a working Archive row; HM-14 is only for a store without lists.
    @MainActor
    func testArchivingTheOnlyListShowsNoActiveLists() {
        let app = Launch.app(emptyStore: true)
        let home = HomeScreen(app: app).waitUntilShown()
        home.emptyState.waitToAppear()

        home.createList(named: "Garden")
        home.archiveFromContextMenu(row: "Garden")

        home.emptyActiveState.waitToAppear()
        XCTAssertFalse(home.emptyState.exists, "not the onboarding empty state")
        app.buttons["home.emptyActiveState.newListButton"].waitToAppear()
        let archive = home.openArchive()
        archive.row("Garden").waitToAppear()
    }

    /// AR-18, AR-20: a search also finds archived lists in "In Archive" (no "No Results" when
    /// only they match); Delete there asks first and removes the list for good.
    @MainActor
    func testSearchShowsInArchiveSectionAndDeletesFromIt() {
        let app = Launch.app()
        let home = HomeScreen(app: app).waitUntilShown()
        home.archiveWithSwipe(row: "Victoria")
        home.archiveRow.waitToAppear()

        home.search("vic")
        home.searchArchiveSection.waitToAppear()
        let victoria = home.archivedRow("Victoria").waitToAppear()
        XCTAssertFalse(home.archiveRow.exists, "the section replaces the Archive row while searching")
        XCTAssertFalse(app.staticTexts["No Results"].exists)
        home.row("Eva").waitToDisappear()

        victoria.perform("Long press", until: app.buttons["archive.menu.delete"]) {
            $0.press(forDuration: 1.5)
        }.waitAndTap()
        app.buttons["home.deleteAlert.confirmButton"].firstMatch.waitAndTap()

        home.archivedRow("Victoria").waitToDisappear()
        home.searchArchiveSection.waitToDisappear()
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Results")).firstMatch
            .waitToAppear()
    }
}
