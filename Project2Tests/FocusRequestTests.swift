//
//  FocusRequestTests.swift
//  Project2Tests
//
//  The inline name field asks for the keyboard once per request (spec 04 LD-13, LD-15).
//  Regression for CI run 44129716390: after [Price] the keyboard moved to the price field
//  and the name field took it back, because "editing but not first responder" (a stale
//  value for one update) counted as a request.
//

import Testing
@testable import Project2

@Suite("FocusRequest", .tags(.regression))
struct FocusRequestTests {

    @Test("the first request asks for the keyboard")
    func firstRequest() {
        var request = FocusRequest()
        request.receive(1)
        #expect(request.isPending)
    }

    @Test("a granted request is used up; the same value again doesn't ask")
    func grantedRequest() {
        var request = FocusRequest()
        request.receive(1)
        request.editingChanged() // began editing
        request.receive(1)
        #expect(!request.isPending)
    }

    @Test("keyboard moved to the price field: later updates don't take it back")
    func keyboardMovedElsewhere() {
        var request = FocusRequest()
        request.receive(1)
        request.editingChanged() // began editing
        request.editingChanged() // ended: [Price] took the keyboard
        for _ in 1...3 { request.receive(1) } // more updates, possibly with a stale "is editing"
        #expect(!request.isPending)
    }

    @Test("a new request (inline add opened again) asks again")
    func newRequest() {
        var request = FocusRequest()
        request.receive(1)
        request.editingChanged()
        request.receive(2)
        #expect(request.isPending)
    }

    @Test("a request not granted yet survives updates until editing begins")
    func pendingSurvivesUpdates() {
        var request = FocusRequest()
        request.receive(1)
        request.receive(1)
        #expect(request.isPending)
    }
}
