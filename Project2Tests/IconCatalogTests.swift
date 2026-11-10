//
//  IconCatalogTests.swift
//  Project2Tests
//
//  Spec 03 LI-05 / LI-06 / LI-07: the curated icon grids and the rule for an
//  emoji typed into "Other…": exactly one grapheme cluster that is an emoji.
//

import Foundation
import Testing
import UIKit
@testable import Project2

@Suite("IconCatalog", .tags(.listInfo, .validation))
struct IconCatalogTests {

    // MARK: - Grids (LI-05, LI-06)

    @Test("LI-05 at least 36 distinct symbols, including the ones named in the spec")
    func symbols() {
        let symbols = IconCatalog.symbols
        #expect(symbols.count >= 36)
        #expect(Set(symbols).count == symbols.count, "duplicates in the grid")
        let required = ["cart", "bed.double", "sofa", "paintbrush", "hammer", "gift", "birthday.cake",
                        "airplane", "house", "tshirt", "figure.child", "fork.knife", "laptopcomputer",
                        "leaf", "pawprint"]
        for name in required {
            #expect(symbols.contains(name), "\(name) is missing")
        }
    }

    @Test("LI-05 every symbol exists in SF Symbols on this OS", arguments: IconCatalog.symbols)
    func symbolExists(_ name: String) {
        #expect(UIImage(systemName: name) != nil)
    }

    @Test("LI-06 at least 36 distinct emoji, each one passes the custom-emoji rule")
    func emojis() {
        let emojis = IconCatalog.emojis
        #expect(emojis.count >= 36)
        #expect(Set(emojis).count == emojis.count, "duplicates in the grid")
        for emoji in emojis {
            #expect(IconCatalog.isSingleEmoji(emoji), "\(emoji) would be rejected in Other…")
        }
    }

    // MARK: - "Other…" field (LI-06)

    struct Case: CustomTestStringConvertible, Sendable {
        let text: String
        let accepted: Bool
        let why: String
        var testDescription: String {
            "\(text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")) "
                + "(\(why)) → \(accepted ? "accepted" : "rejected")"
        }
    }

    static let accepted: [Case] = [
        Case(text: "🧸", accepted: true, why: "emoji presentation"),
        Case(text: "🫠", accepted: true, why: "Unicode 14 emoji"),
        Case(text: "👍🏽", accepted: true, why: "skin tone modifier"),
        Case(text: "❤️", accepted: true, why: "text default + FE0F"),
        Case(text: "✈️", accepted: true, why: "text default + FE0F"),
        Case(text: "👨‍👩‍👧", accepted: true, why: "ZWJ family"),
        Case(text: "👩🏽‍💻", accepted: true, why: "ZWJ + skin tone"),
        Case(text: "🏳️‍🌈", accepted: true, why: "ZWJ flag"),
        Case(text: "🇺🇸", accepted: true, why: "regional indicator pair flag"),
        Case(text: "1️⃣", accepted: true, why: "keycap sequence"),
    ]

    static let rejected: [Case] = [
        Case(text: "", accepted: false, why: "empty"),
        Case(text: "a", accepted: false, why: "letter"),
        Case(text: "Ж", accepted: false, why: "Cyrillic letter"),
        Case(text: "1", accepted: false, why: "digit has the Emoji property but renders as text"),
        Case(text: "#", accepted: false, why: "same for #"),
        Case(text: "*", accepted: false, why: "same for *"),
        Case(text: "©", accepted: false, why: "text-default symbol without FE0F"),
        Case(text: "™", accepted: false, why: "text-default symbol without FE0F"),
        Case(text: "↔", accepted: false, why: "text-default arrow without FE0F"),
        Case(text: "🧸🧸", accepted: false, why: "two emoji"),
        Case(text: "🇺🇸🇩🇪", accepted: false, why: "two flags"),
        Case(text: " 🧸", accepted: false, why: "leading space is a second grapheme"),
        Case(text: "🧸 ", accepted: false, why: "trailing space is a second grapheme"),
        Case(text: "ab", accepted: false, why: "text"),
        Case(text: "🧸a", accepted: false, why: "emoji + letter"),
    ]

    /// Behaviour pinned down, not required by the spec: these pass because Unicode
    /// marks them as emoji, even though they are unusual list icons.
    static let documented: [Case] = [
        Case(text: "❤", accepted: true, why: "text-default heart without FE0F (above U+238C)"),
        Case(text: "☺", accepted: true, why: "text-default smiley without FE0F"),
        Case(text: "©️", accepted: true, why: "© with FE0F is an emoji"),
        Case(text: "🇺", accepted: true, why: "a lone regional indicator has Emoji_Presentation"),
    ]

    @Test("LI-06 a single emoji grapheme is accepted", arguments: accepted)
    func acceptsSingleEmoji(_ c: Case) {
        #expect(c.text.count == 1)
        #expect(IconCatalog.isSingleEmoji(c.text))
    }

    @Test("LI-06 text, several emoji and padded input are rejected", arguments: rejected)
    func rejectsOthers(_ c: Case) {
        #expect(IconCatalog.isSingleEmoji(c.text) == false)
    }

    @Test("LI-06 documented edge cases", arguments: documented)
    func documentedEdgeCases(_ c: Case) {
        #expect(IconCatalog.isSingleEmoji(c.text) == c.accepted)
    }

    // MARK: - LI-07 / BUG-10

    @Test("LI-07 / BUG-10 no private keyboard API in the app sources", .tags(.regression))
    func noPrivateKeyboard() throws {
        // Sources are next to this file in the repo: <repo>/Project2Tests/IconCatalogTests.swift.
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sources = repo.appending(path: "Project2")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            Issue.record("can't read \(sources.path())")
            return
        }
        var checked = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            #expect(!text.contains("UIKeyboardType(rawValue"), "\(url.lastPathComponent)")
            #expect(!text.contains("UIScreen.main"), "\(url.lastPathComponent) (AD-07, BUG-13)")
        }
        #expect(checked > 20, "found only \(checked) Swift files under \(sources.path())")
    }
}
