//
//  InlineFocusTests.swift
//  Project2Tests
//
//  The one owner of the inline add row's focus (spec 04 LD-13, LD-15; DECISIONS.md Р-9):
//  the screen's commands and the fields' reports both go through `InlineFocus`, and the
//  name field only carries it out (`NameFieldFocus`). Regressions of PR #8: the name field
//  taking the keyboard back from the price field (CI run 44129716390), and the row losing
//  the keyboard while a slow price / link field is still being inserted.
//

import Testing
@testable import Project2

@Suite("InlineFocus", .tags(.regression))
struct InlineFocusTests {

    /// Inline add just opened: the name field has the keyboard.
    private func opened() -> InlineFocus {
        var focus = InlineFocus()
        focus.focusName()
        focus.began(.name) // the name field took it
        return focus
    }

    // MARK: - Commands

    @Test("closed by default: nobody types")
    func closedByDefault() {
        let focus = InlineFocus()
        #expect(focus.field == nil)
        #expect(!focus.isTyping)
    }

    @Test("opening asks the name field for the keyboard, with a new request each time")
    func openingRequestsName() {
        var focus = InlineFocus()
        focus.focusName()
        #expect(focus.field == .name)
        #expect(focus.isTyping)
        let first = focus.nameRequest
        focus.close()
        focus.focusName()
        #expect(focus.nameRequest == first + 1)
    }

    @Test("[Price] with the field already in the row: it gets the keyboard at once")
    func requestShownField() {
        var focus = opened()
        focus.request(.price, isShown: true)
        #expect(focus.field == .price)
        #expect(focus.pending == nil)
    }

    @Test("[Price] with a field not in the row yet: the name keeps the keyboard until it appears")
    func requestLateField() {
        var focus = opened()
        focus.request(.price, isShown: false)
        #expect(focus.field == .name) // the row is never without a keyboard (300 ms grace)
        #expect(focus.pending == .price)
        focus.fieldAppeared(.price)
        #expect(focus.field == .price)
        #expect(focus.pending == nil)
    }

    @Test("a field that appears without being asked for (scrolled back) doesn't take the keyboard")
    func unaskedAppearance() {
        var focus = opened()
        focus.fieldAppeared(.link)
        #expect(focus.field == .name)
        focus.request(.price, isShown: false)
        focus.fieldAppeared(.link)
        #expect(focus.field == .name)
        #expect(focus.pending == .price)
    }

    @Test("Return: nothing waits for a field of the previous line; the name keeps the keyboard")
    func nextItemDropsPending() {
        var focus = opened()
        focus.request(.link, isShown: false)
        focus.nextItem()
        focus.fieldAppeared(.link)
        #expect(focus.field == .name)
        #expect(focus.pending == nil)
    }

    @Test("closing: nobody has the keyboard and nothing waits")
    func closeClearsAll() {
        var focus = opened()
        focus.request(.price, isShown: false)
        focus.close()
        #expect(focus.field == nil)
        #expect(focus.pending == nil)
    }

    // MARK: - Reports

    @Test("the name field ends editing after the price field took the keyboard: price keeps it (CI run 44129716390)")
    func lateEndOfNameIsIgnored() {
        var focus = opened()
        focus.request(.price, isShown: false)
        focus.fieldAppeared(.price)
        focus.began(.price)
        focus.ended(.name) // the name field's late report
        #expect(focus.field == .price)
    }

    @Test("the user taps the price field: the name ends, then price begins")
    func userTapsPrice() {
        var focus = opened()
        focus.ended(.name)
        #expect(!focus.isTyping) // for a moment; the 300 ms grace covers it
        focus.began(.price)
        #expect(focus.field == .price)
    }

    @Test("the user taps the name while the link field has the keyboard")
    func userTapsNameFromLink() {
        var focus = opened()
        focus.request(.link, isShown: true)
        focus.began(.name)
        focus.ended(.link) // SwiftUI reports the link field's loss later
        #expect(focus.field == .name)
    }

    @Test("the user dismisses the keyboard: nobody types")
    func userDismisses() {
        var focus = opened()
        focus.ended(.name)
        #expect(focus.field == nil)
        #expect(!focus.isTyping)
    }

    @Test("the user taps the name while a late field is still coming: it still gets the keyboard")
    func pendingSurvivesUserTap() {
        var focus = opened()
        focus.request(.price, isShown: false)
        focus.began(.name)
        focus.fieldAppeared(.price)
        #expect(focus.field == .price)
    }
}

@Suite("NameFieldFocus", .tags(.regression))
struct NameFieldFocusTests {

    @Test("owner says name, request pending: grant it")
    func grantPendingRequest() {
        #expect(NameFieldFocus.action(focus: .name, requestPending: true, isFirstResponder: false) == .grantRequest)
    }

    @Test("owner says name and the field has the keyboard: nothing to do")
    func alreadyFocused() {
        #expect(NameFieldFocus.action(focus: .name, requestPending: false, isFirstResponder: true) == .none)
    }

    @Test("owner says name but the field lost the keyboard: reclaim if nobody else has it")
    func reclaimAfterLoss() {
        #expect(NameFieldFocus.action(focus: .name, requestPending: false, isFirstResponder: false)
                == .reclaimIfUnclaimed)
    }

    @Test("owner says nobody (inline add closed): give the keyboard up")
    func resignWhenClosed() {
        #expect(NameFieldFocus.action(focus: nil, requestPending: false, isFirstResponder: true) == .resign)
        #expect(NameFieldFocus.action(focus: nil, requestPending: false, isFirstResponder: false) == .none)
    }

    @Test("owner says price or link: never take the keyboard back (CI run 44129716390), never drop it first",
          arguments: [InlineField.price, .link])
    func otherFieldOwnsFocus(field: InlineField) {
        for isFirstResponder in [false, true] {
            for requestPending in [false, true] {
                #expect(NameFieldFocus.action(focus: field, requestPending: requestPending,
                                              isFirstResponder: isFirstResponder) == .none)
            }
        }
    }
}
