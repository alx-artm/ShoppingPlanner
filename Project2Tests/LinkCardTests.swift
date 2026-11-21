//
//  LinkCardTests.swift
//  Project2Tests
//
//  Spec 06 Part A, PR 3: the rules behind the link card in item details — what the
//  Link section shows for the field text (LP-05), the picture's size, and `LinkOpener`
//  recording links instead of opening them (`-UITestsRecordOpenedLinks`).
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Project2

@Suite("Link card", .tags(.linkPreview))
struct LinkCardTests {

    // MARK: - ItemLinkDisplay

    @Test("An empty or blank field shows nothing", arguments: ["", "   ", "\n"])
    func emptyField(text: String) {
        #expect(ItemLinkDisplay.make(fieldText: text, savedText: "https://ikea.com", hasPreview: true) == .empty)
    }

    @Test("LP-05 text that isn't a web link gets the caption",
          arguments: ["https://", "ftp://shop.com", "mailto:a@b.com", "shop", "two words.com"])
    func invalidText(text: String) {
        #expect(ItemLinkDisplay.make(fieldText: text, savedText: text, hasPreview: false) == .invalid)
    }

    @Test("The saved link shows the card with a preview, the compact row without one")
    func savedLink() {
        #expect(ItemLinkDisplay.make(fieldText: "https://ikea.com/sofa", savedText: "https://ikea.com/sofa",
                                     hasPreview: true) == .card)
        #expect(ItemLinkDisplay.make(fieldText: "https://ikea.com/sofa", savedText: "https://ikea.com/sofa",
                                     hasPreview: false) == .compact)
    }

    @Test("A link saved before M5 as typed is still the same link")
    func typedFormMatchesNormalized() {
        #expect(ItemLinkDisplay.make(fieldText: "https://ikea.com/sofa", savedText: "ikea.com/sofa",
                                     hasPreview: true) == .card)
        #expect(ItemLinkDisplay.make(fieldText: " ikea.com/sofa ", savedText: "https://ikea.com/sofa",
                                     hasPreview: true) == .card)
    }

    @Test("An edited, not yet saved link has no card: it would describe the old link")
    func unsavedLink() {
        #expect(ItemLinkDisplay.make(fieldText: "https://ikea.com/chair", savedText: "https://ikea.com/sofa",
                                     hasPreview: true) == .unsaved)
        #expect(ItemLinkDisplay.make(fieldText: "ikea.com", savedText: "", hasPreview: false) == .unsaved)
    }

    @Test("Only the card and the compact row show a preview")
    func showsPreview() {
        #expect(ItemLinkDisplay.card.showsPreview)
        #expect(ItemLinkDisplay.compact.showsPreview)
        #expect(!ItemLinkDisplay.empty.showsPreview)
        #expect(!ItemLinkDisplay.invalid.showsPreview)
        #expect(!ItemLinkDisplay.unsaved.showsPreview)
    }

    // MARK: - Picture size

    @Test("The picture is 1.91:1 and never higher than 180 pt", arguments: [
        (CGFloat(191), CGFloat(100)),
        (CGFloat(300), CGFloat(300) / 1.91),
        (CGFloat(343.8), CGFloat(180)),   // exactly the cap
        (CGFloat(361), CGFloat(180)),     // iPhone form row
        (CGFloat(560), CGFloat(180)),     // iPad form sheet
        (CGFloat(0), CGFloat(0)),
    ])
    func heroHeight(width: CGFloat, expected: CGFloat) {
        #expect(abs(LinkCardMetrics.heroHeight(forWidth: width) - expected) < 0.01)
    }

    // MARK: - LinkOpener

    @Test("Recording writes what would open; nothing is recorded before")
    @MainActor
    func recorderFormat() throws {
        let recorder = OpenedLinkRecorder()
        #expect(recorder.lastOpenedLink == "none")
        let url = try #require(URL(string: "https://kites.example.com/red"))
        recorder.record(url, .inApp)
        #expect(recorder.lastOpenedLink == "inApp https://kites.example.com/red")
        recorder.record(url, .external)
        #expect(recorder.lastOpenedLink == "external https://kites.example.com/red")
    }

    @Test("LP-05 .inApp goes to the in-app browser, .external to the system; nothing is lost")
    @MainActor
    func routing() throws {
        let url = try #require(URL(string: "https://kites.example.com/red"))
        var systemOpened: [URL] = []
        var browserOpened: [URL] = []
        let openURL = OpenURLAction { url in
            systemOpened.append(url)
            return .handled
        }
        let opener = LinkOpener().presentingInApp { browserOpened.append($0) }

        opener.open(url, .inApp, using: openURL)
        #expect(browserOpened == [url])
        #expect(systemOpened.isEmpty)

        opener.open(url, .external, using: openURL)
        #expect(systemOpened == [url])

        // No in-app browser on this screen: the link still opens, outside the app.
        LinkOpener().open(url, .inApp, using: openURL)
        #expect(systemOpened == [url, url])
    }

    @Test("While recording, nothing opens, not even the in-app browser")
    @MainActor
    func recordingOpensNothing() throws {
        let url = try #require(URL(string: "https://kites.example.com/red"))
        var opened = 0
        let openURL = OpenURLAction { _ in
            opened += 1
            return .handled
        }
        let recorder = OpenedLinkRecorder()
        let opener = LinkOpener(recorder: recorder).presentingInApp { _ in opened += 1 }
        opener.open(url, .inApp, using: openURL)
        opener.open(url, .external, using: openURL)
        #expect(opened == 0)
        #expect(recorder.lastOpenedLink == "external https://kites.example.com/red")
    }

    @Test("Links are recorded only with -UITests -UITestsRecordOpenedLinks", arguments: [
        (["app"], false),
        (["app", "-UITests"], false),
        (["app", "-UITestsRecordOpenedLinks"], false),
        (["app", "-UITests", "-UITestsRecordOpenedLinks"], true),
    ])
    @MainActor
    func recordingNeedsUITests(arguments: [String], records: Bool) {
        #expect(LaunchConfiguration.recordsOpenedLinks(arguments: arguments) == records)
        #expect((LinkOpener.forLaunch(arguments: arguments).recorder != nil) == records)
    }
}
