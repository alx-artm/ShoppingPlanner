//
//  ListDraftTests.swift
//  Project2Tests
//
//  Spec 03 List Info: the draft the screen edits (LI-01...LI-03, LI-08, LI-09),
//  how PlannerStore applies it on ✓ (createList(from:), updateList(_:with:)),
//  and parsing the budget field with the list currency's format style.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("ListDraft", .tags(.listInfo))
struct ListDraftTests {
    let f: StoreFixture
    init() throws { f = try StoreFixture(currency: "EUR") }

    // MARK: - Defaults (LI-03)

    @Test("LI-03 a new draft is blue, 'cart' symbol, not pinned, no budget, in the given currency")
    func newDraftDefaults() {
        let draft = ListDraft(currencyCode: "EUR")

        #expect(draft.name == "")
        #expect(draft.color == .blue)
        #expect(draft.iconKind == .symbol)
        #expect(draft.iconName == "cart")
        #expect(draft.isPinned == false)
        #expect(draft.budget == nil)
        #expect(draft.currencyCode == "EUR")
        #expect(draft.groupNames.isEmpty)
        #expect(draft.canSave == false, "an empty name can't be saved (LI-01)")
    }

    @Test("LI-02 a draft of an existing list copies every edited field")
    func draftFromList() {
        let list = f.store.createList(name: "Eva", iconName: "🧸", iconKind: .emoji, color: .magenta,
                                      isPinned: true, budget: dec("250.5"), currencyCode: "JPY")

        let draft = ListDraft(list: list)

        #expect(draft.name == "Eva")
        #expect(draft.iconName == "🧸")
        #expect(draft.iconKind == .emoji)
        #expect(draft.color == .magenta)
        #expect(draft.isPinned)
        #expect(draft.budget == dec("250.5"))
        #expect(draft.currencyCode == "JPY")
        #expect(draft.groupNames.isEmpty, "editing never adds template groups")
    }

    // MARK: - Validation (LI-01, LI-08)

    @Test("LI-01 ✓ needs a name that is not blank after trimming",
          arguments: [
            ("", false), (" ", false), ("\n\t  ", false), ("\u{00A0}", false),
            ("a", true), ("  Trip  ", true), ("🧳", true),
          ])
    func nameValidation(name: String, valid: Bool) {
        var draft = ListDraft(currencyCode: "USD")
        draft.name = name
        #expect(draft.hasValidName == valid)
        #expect(draft.canSave == valid)
    }

    @Test("LI-08 the budget may be empty or ≥ 0; a negative budget blocks ✓",
          arguments: [
            (nil, true), ("0", true), ("0.01", true), ("1000000", true),
            ("-0.01", false), ("-5", false),
          ] as [(String?, Bool)])
    func budgetValidation(budget: String?, valid: Bool) {
        var draft = ListDraft(currencyCode: "USD")
        draft.name = "Trip"
        draft.budget = budget.map(dec)
        #expect(draft.hasValidBudget == valid)
        #expect(draft.canSave == valid)
    }

    @Test("LI-02 drafts compare by value, so the screen knows when there are unsaved edits")
    func equality() {
        let list = f.store.createList(name: "Trip")
        let initial = ListDraft(list: list)
        var edited = initial
        #expect(edited == initial)
        edited.color = .mint
        #expect(edited != initial)
        edited.color = initial.color
        #expect(edited == initial)
    }

    // MARK: - Create (LI-01, LI-03, HM-03)

    @Test("LI-01 createList(from:) trims the name and copies every field", .tags(.validation))
    func createFromDraft() throws {
        var draft = ListDraft(currencyCode: "EUR")
        draft.name = "  Kids room \n"
        draft.color = .mint
        draft.iconName = "bed.double"
        draft.budget = dec("1500")

        let list = f.store.createList(from: draft)

        #expect(list.name == "Kids room")
        #expect(list.color == .mint)
        #expect(list.iconKind == .symbol)
        #expect(list.iconName == "bed.double")
        #expect(list.budget == dec("1500"))
        #expect(list.currencyCode == "EUR")
        #expect(list.isPinned == false)
        #expect(list.groups?.isEmpty ?? true)
        #expect(try f.count(ListModel.self) == 1)
    }

    @Test("LI-01 ✕ on a new list inserts nothing: only ✓ touches the store")
    func cancelCreatesNothing() throws {
        var draft = ListDraft(currencyCode: "EUR")
        draft.name = "Draft only"
        draft.groupNames = ["A", "B"]
        #expect(draft.canSave)
        // The screen is dismissed without calling the store.
        #expect(try f.count(ListModel.self) == 0)
        #expect(try f.count(GroupModel.self) == 0)
    }

    @Test("LI-08 budget 0 is a real budget: any planned amount is over budget", .tags(.money))
    func zeroBudget() throws {
        var draft = ListDraft(currencyCode: "EUR")
        draft.name = "Zero"
        draft.budget = 0
        let list = f.store.createList(from: draft)
        #expect(list.budget == 0)
        #expect(list.summary.isOverBudget == false, "nothing planned yet")

        let group = f.store.createGroup(name: "G", in: list)
        f.addItem("Pen", to: group, price: dec("0.01"))
        #expect(list.summary.isOverBudget)
    }

    @Test("HM-03 a list created from List Info comes first in All Lists; pinned goes last in Pinned",
          .tags(.home, .ordering))
    func createdListPlacement() {
        f.store.createList(name: "Old")
        f.store.createList(name: "Pinned old", isPinned: true)

        var draft = ListDraft(currencyCode: "EUR")
        draft.name = "New"
        f.store.createList(from: draft)
        draft.name = "New pinned"
        draft.isPinned = true
        f.store.createList(from: draft)

        #expect(f.store.lists(pinned: false).map(\.name) == ["New", "Old"])
        #expect(f.store.lists(pinned: true).map(\.name) == ["Pinned old", "New pinned"])
    }

    // MARK: - Edit (LI-02, LI-09)

    @Test("LI-02 edits stay in the draft until ✓; ✕ leaves the list unchanged")
    func cancelKeepsModel() {
        let list = f.store.createList(name: "Trip", color: .blue, budget: dec("100"))
        var draft = ListDraft(list: list)
        draft.name = "Changed"
        draft.color = .red
        draft.budget = nil
        draft.isPinned = true

        // ✕: the draft is dropped.
        #expect(list.name == "Trip")
        #expect(list.color == .blue)
        #expect(list.budget == dec("100"))
        #expect(list.isPinned == false)
    }

    @Test("LI-02 updateList applies name (trimmed), icon, color and budget in one go")
    func updateApplies() {
        let list = f.store.createList(name: "Trip", budget: dec("100"))
        var draft = ListDraft(list: list)
        draft.name = "  Summer trip "
        draft.iconName = "🏖️"
        draft.iconKind = .emoji
        draft.color = .orange
        draft.budget = dec("250.75")

        f.store.updateList(list, with: draft)

        #expect(list.name == "Summer trip")
        #expect(list.iconName == "🏖️")
        #expect(list.iconKind == .emoji)
        #expect(list.color == .orange)
        #expect(list.budget == dec("250.75"))
        #expect(f.store.lastErrorMessage == nil)
    }

    @Test("LI-08 clearing the budget field removes the budget")
    func updateClearsBudget() {
        let list = f.store.createList(name: "Trip", budget: dec("100"))
        var draft = ListDraft(list: list)
        draft.budget = nil
        f.store.updateList(list, with: draft)
        #expect(list.budget == nil)
    }

    @Test("LI-08 a negative budget never reaches the model; the old one stays", .tags(.validation))
    func updateRejectsNegativeBudget() {
        let list = f.store.createList(name: "Trip", budget: dec("100"))
        var draft = ListDraft(list: list)
        draft.budget = dec("-1")
        f.store.updateList(list, with: draft)
        #expect(list.budget == dec("100"))
    }

    @Test("DM-12 a blank name on ✓ keeps a non-empty placeholder; an empty icon resets to 'cart'",
          .tags(.validation))
    func updateBlankNameAndIcon() {
        let list = f.store.createList(name: "Trip", iconName: "🧳", iconKind: .emoji)
        var draft = ListDraft(list: list)
        draft.name = "   "
        draft.iconName = ""
        f.store.updateList(list, with: draft)

        #expect(!list.name.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(list.iconName == "cart")
        #expect(list.iconKind == .symbol)
    }

    @Test("Currency is read-only in v1: updateList keeps the list currency")
    func updateKeepsCurrency() {
        let list = f.store.createList(name: "Trip", currencyCode: "EUR")
        var draft = ListDraft(list: list)
        draft.currencyCode = "JPY"
        f.store.updateList(list, with: draft)
        #expect(list.currencyCode == "EUR")
    }

    @Test("LI-09 'Pin to Home' on ✓ moves the list to the end of Pinned and back to the end of All Lists",
          .tags(.home, .ordering))
    func updatePin() {
        f.store.createList(name: "P1", isPinned: true)
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B") // All Lists: B, A

        var draft = ListDraft(list: a)
        draft.isPinned = true
        f.store.updateList(a, with: draft)
        #expect(a.isPinned)
        #expect(f.store.lists(pinned: true).map(\.name) == ["P1", "A"])
        #expect(f.store.lists(pinned: false).map(\.name) == ["B"])

        draft.isPinned = false
        f.store.updateList(a, with: draft)
        #expect(f.store.lists(pinned: false).map(\.name) == ["B", "A"])
    }

    @Test("updateList without a pin change keeps the position in the section", .tags(.ordering))
    func updateKeepsPosition() {
        let a = f.store.createList(name: "A")
        f.store.createList(name: "B")
        let before = a.sortIndex
        var draft = ListDraft(list: a)
        draft.name = "A2"
        f.store.updateList(a, with: draft)
        #expect(a.sortIndex == before)
        #expect(f.store.lists(pinned: false).map(\.name) == ["B", "A2"])
    }
}

// MARK: - Budget field parsing (LI-08)

/// List Info binds the budget to `TextField(value:format: MoneyFormat.style(currencyCode: list currency, locale:))`.
/// These tests pin down what that format style accepts, with explicit locales.
@Suite("List Info budget parsing", .tags(.listInfo, .money))
struct BudgetParsingTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let input: String
        let currency: String
        let locale: String
        /// `nil` = the text is rejected (the field keeps its previous value).
        let expected: String?

        var testDescription: String { "\"\(input)\" \(currency) in \(locale) → \(expected ?? "rejected")" }
    }

    static func parse(_ c: Case) -> Decimal? {
        let style = MoneyFormat.style(currencyCode: c.currency, locale: Locale(identifier: c.locale))
        return try? style.parseStrategy.parse(c.input)
    }

    static let cases: [Case] = [
        // The formatted value round-trips (what the field shows after editing).
        Case(input: "€1,234.50", currency: "EUR", locale: "en_US", expected: "1234.5"),
        Case(input: "1 234,50 €", currency: "EUR", locale: "ru_RU", expected: "1234.5"),
        Case(input: "1.234,50 €", currency: "EUR", locale: "de_DE", expected: "1234.5"),
        Case(input: "¥1,234", currency: "JPY", locale: "en_US", expected: "1234"),
        // A bare number typed on the decimal pad, in the locale's separator.
        Case(input: "250", currency: "EUR", locale: "en_US", expected: "250"),
        Case(input: "1234.5", currency: "USD", locale: "en_US", expected: "1234.5"),
        Case(input: "250,5", currency: "EUR", locale: "ru_RU", expected: "250.5"),
        // 0 is a valid budget (LI-08).
        Case(input: "0", currency: "USD", locale: "en_US", expected: "0"),
        // A negative value parses; ListDraft.hasValidBudget then blocks ✓.
        Case(input: "-5", currency: "USD", locale: "en_US", expected: "-5"),
        // Not a number, or another currency's symbol: rejected.
        Case(input: "abc", currency: "USD", locale: "en_US", expected: nil),
        Case(input: "$12", currency: "EUR", locale: "en_US", expected: nil),
        Case(input: "", currency: "USD", locale: "en_US", expected: nil),
    ]

    @Test("LI-08 the budget field parses amounts in the list currency and the locale", arguments: cases)
    func parsing(_ c: Case) {
        #expect(Self.parse(c) == c.expected.map(dec))
    }

    @Test("LI-08 JPY keeps the typed fraction; it is rounded only on display (DM-25)")
    func jpyFraction() {
        let c = Case(input: "1234.5", currency: "JPY", locale: "en_US", expected: "1234.5")
        #expect(Self.parse(c) == dec("1234.5"))
        #expect(MoneyFormat.string(dec("1234.5"), currencyCode: "JPY", locale: Locale(identifier: "en_US")) == "¥1,235")
    }

    @Test("A negative parsed budget is invalid in the draft")
    func negativeParsedIsInvalid() {
        var draft = ListDraft(currencyCode: "USD")
        draft.name = "Trip"
        draft.budget = Self.parse(Case(input: "-5", currency: "USD", locale: "en_US", expected: nil))
        #expect(draft.hasValidBudget == false)
    }

    /// BUG-28 (new): in ru_RU a "." is not a decimal separator, and "250.5" silently
    /// becomes 250 instead of being rejected or read as 250.5. Users get "." from a
    /// hardware keyboard or paste. Same family as BUG-26 (the plan there: accept both
    /// "," and "."). Kept as a known issue until the M4 money input lands.
    @Test("BUG-28 ru_RU '250.5' must not silently become 250", .tags(.regression))
    func ruDotSeparator() {
        let parsed = Self.parse(Case(input: "250.5", currency: "EUR", locale: "ru_RU", expected: nil))
        withKnownIssue("BUG-28: ru_RU drops the fraction after '.' (parses as 250)") {
            #expect(parsed == dec("250.5") || parsed == nil,
                    "parsed \(String(describing: parsed)); the fraction was lost silently")
        }
    }
}
