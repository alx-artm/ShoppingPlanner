//
//  InlineFocus.swift
//  Project2
//
//  Who has the keyboard in the inline add row (spec 04 LD-13, LD-15): the one
//  owner of that focus. The list screen keeps one `InlineFocus` value; the
//  fields only carry it out. The UIKit name field becomes or resigns first
//  responder to match it (`InlineNameField`), the SwiftUI price and link
//  fields follow a `@FocusState` the screen sets from it. What the user does
//  (taps a field, dismisses the keyboard) comes back as `began` / `ended`.
//
//  Before, the name field's focus lived in a flag of its own next to the
//  `@FocusState` of price and link, and the two disagreed for an update at
//  every hand-off: the keyboard-steal and keyboard-loss bugs of PR #8
//  (DECISIONS.md Р-9, LESSONS.md lesson 20).
//

/// A field of the inline add row that can have the keyboard.
enum InlineField: Hashable {
    case name, price, link
}

/// The focus of the inline add row. A pure value: the screen changes it, the fields execute it.
struct InlineFocus: Equatable {
    /// The field that has the keyboard, or is being given it; `nil` = no inline field has it.
    private(set) var field: InlineField?
    /// [Price] / [Link] asked for this field before it was in the row: it gets the keyboard
    /// when it appears (`fieldAppeared`). Until then the keyboard stays where it is.
    private(set) var pending: InlineField?
    /// Bumped each time the screen asks for the name field's keyboard (opening inline add).
    /// The name field grants each value once (`FocusRequest`).
    private(set) var nameRequest = 0

    /// Any inline field has the keyboard.
    var isTyping: Bool { field != nil }

    // MARK: - Commands from the screen

    /// Inline add opened: the name field gets the keyboard.
    mutating func focusName() {
        pending = nil
        field = .name
        nameRequest += 1
    }

    /// [Price] / [Link]: a field already in the row gets the keyboard now; a new one when it
    /// appears. The keyboard isn't taken from the name field before then, so the row never
    /// goes without one (the 300 ms grace close would end inline add).
    mutating func request(_ requested: InlineField, isShown: Bool) {
        if isShown {
            pending = nil
            field = requested
        } else {
            pending = requested
        }
    }

    /// A field is in the row now: it takes the keyboard if it was asked for.
    mutating func fieldAppeared(_ appeared: InlineField) {
        guard pending == appeared else { return }
        pending = nil
        field = appeared
    }

    /// Return saved the item: the next empty line starts without extra fields, so nothing is
    /// waiting for one. The keyboard stays with the name field.
    mutating func nextItem() {
        pending = nil
    }

    /// Inline add closed (Done, ⓘ, focus left).
    mutating func close() {
        pending = nil
        field = nil
    }

    // MARK: - Reports from the fields (the user moved the keyboard)

    /// A field got the keyboard (a tap, or a command carried out).
    mutating func began(_ focused: InlineField) {
        field = focused
    }

    /// A field lost the keyboard. Ignored when the focus has already moved on: the name field
    /// ends editing *after* [Price] gave the keyboard to the price field, and that late report
    /// must not take it back (CI run 44129716390).
    mutating func ended(_ unfocused: InlineField) {
        guard field == unfocused else { return }
        field = nil
    }
}
