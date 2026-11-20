//
//  InlineNameField.swift
//  Project2
//
//  The name field of inline add (spec 04 LD-13). A `UITextField`, because the
//  field must be emptied *inside* the Return key press.
//
//  With a SwiftUI text binding, "save and clear after Return" reaches the text
//  view on a later render pass. Keys typed in that gap (a fast typist, a
//  hardware keyboard) were already in the field, and the late write scrambled
//  them or moved the caret: "Ball⏎Puzzle" left "uzzleP" (seen in UI tests).
//  `textFieldShouldReturn` runs in the key event itself, so the field is empty
//  before the next key arrives; returning `false` keeps the keyboard up.
//
//  The UIKit field owns its text: SwiftUI only reads it (draft name, live ⓘ
//  state) and never writes it back while the field has the keyboard, so a
//  stale value can't overwrite typing.
//
//  SwiftUI's `.toolbar(placement: .keyboard)` doesn't reach a UIKit field, so
//  the accessory bar is hosted as the field's `inputAccessoryView`.
//
//  Focus: the field doesn't decide who has the keyboard. The screen's
//  `InlineFocus` does; this field becomes or resigns first responder to match
//  it (`NameFieldFocus.action`) and reports the user's changes back through
//  `onFocusChange`.
//

import SwiftUI
import UIKit

struct InlineNameField<Accessory: View>: UIViewRepresentable {
    /// Mirror of the typed text, for the draft. Read only from the SwiftUI side.
    @Binding var text: String
    /// The inline field that should have the keyboard (`InlineFocus.field`): the field takes
    /// it for `.name`, gives it up for `nil`, and leaves it alone while the price or link field
    /// takes it.
    let focus: InlineField?
    /// Each new value asks for the keyboard once (`InlineFocus.nameRequest`).
    let focusRequest: Int
    /// The field got (`true`) or lost (`false`) the keyboard: the one path back to the owner.
    let onFocusChange: (Bool) -> Void
    /// Return: the line typed (not trimmed; the store trims on commit, LD-16).
    /// The field is already empty when this is called.
    let onReturn: (String) -> Void
    /// Shown above the keyboard while this field is being edited.
    let accessory: Accessory

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = WindowAwareTextField()
        // A request made before the field was in a window (just inserted into the list) was
        // ignored by UIKit; it is granted once the field is in one.
        field.onMoveToWindow = { [weak coordinator = context.coordinator] field in
            coordinator?.grantFocusRequest(to: field)
        }
        field.text = text
        field.placeholder = String(localized: "Item name")
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .next
        field.autocapitalizationType = .sentences
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityIdentifier = "inline.nameField"

        let host = UIHostingController(rootView: accessory)
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame = CGRect(x: 0, y: 0, width: 0, height: 56)
        context.coordinator.accessoryHost = host
        field.inputAccessoryView = host.view
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // The bar's state (ⓘ enabled only with a name) follows the screen.
        context.coordinator.accessoryHost?.rootView = accessory
        // The text is written from here only to empty a field that isn't being typed in: when
        // inline add closes (Done) and opens again in the same group, SwiftUI reuses this
        // UITextField, which still held the previous name ("Gum" + "Mints" → "GumMints").
        // Without the keyboard there is no typing for a late write to scramble.
        if text.isEmpty, !field.isFirstResponder, field.text?.isEmpty == false {
            field.text = ""
        }
        let coordinator = context.coordinator
        if LaunchConfiguration.dropsInlineNameFocusOnce, !coordinator.droppedFocusForUITest,
           !text.isEmpty, field.isFirstResponder {
            // UI tests only: lose the keyboard inside this update, as the list sometimes does.
            coordinator.droppedFocusForUITest = true
            field.resignFirstResponder()
        }
        coordinator.focusRequest.receive(focusRequest)
        switch NameFieldFocus.action(focus: focus, requestPending: coordinator.focusRequest.isPending,
                                     isFirstResponder: field.isFirstResponder) {
        case .grantRequest:
            coordinator.grantFocusRequest(to: field)
        case .reclaimIfUnclaimed:
            // This update still says "name", yet the field lost the keyboard: the loss came
            // from inside an update (the list re-laying out the row), not from the user. See
            // `FocusRequest.shouldReclaim`.
            coordinator.reclaimFocusIfUnclaimed(field)
        case .resign:
            field.resignFirstResponder()
        case .none:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InlineNameField
        var accessoryHost: UIHostingController<Accessory>?
        var focusRequest = FocusRequest()
        /// `-UITestsDropInlineNameFocus` already took the keyboard away once.
        var droppedFocusForUITest = false

        init(parent: InlineNameField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        /// Becomes first responder for a pending request, in the next main-actor turn (not
        /// during a SwiftUI update) and only if the request is still pending then.
        func grantFocusRequest(to field: UITextField) {
            guard focusRequest.isPending, !field.isFirstResponder else { return }
            Task { @MainActor in
                if self.focusRequest.isPending, field.window != nil, !field.isFirstResponder {
                    field.becomeFirstResponder()
                }
            }
        }

        /// The field lost the keyboard inside a view update: takes it back in the next main-actor
        /// turn, unless another field (price, link) has it by then.
        func reclaimFocusIfUnclaimed(_ field: UITextField) {
            Task { @MainActor in
                let reclaim = FocusRequest.shouldReclaim(
                    updateSaysEditing: true,
                    isInWindow: field.window != nil,
                    isFirstResponder: field.isFirstResponder,
                    anotherFieldHasKeyboard: UIResponder.currentFirstResponder is UITextInput)
                if reclaim { field.becomeFirstResponder() }
            }
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            focusRequest.editingChanged()
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            focusRequest.editingChanged()
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            let line = field.text ?? ""
            // Emptied right here, inside the key press, before any next key (LD-13).
            field.text = ""
            parent.text = ""
            parent.onReturn(line)
            return false // keep the keyboard for the next item
        }
    }
}

/// What the name field does in a view update to match the owner of the focus (`InlineFocus`).
enum NameFieldFocus: Equatable {
    /// Take the keyboard for a new request (opening inline add), once the field is in a window.
    case grantRequest
    /// The owner says "name" but the field lost the keyboard: take it back if nobody else has it.
    case reclaimIfUnclaimed
    /// The owner says no inline field has the keyboard (inline add closed): give it up.
    case resign
    case none

    /// - Parameters:
    ///   - focus: the owner's field in this update.
    ///   - requestPending: a name request not granted yet (`FocusRequest.isPending`).
    ///   - isFirstResponder: the field has the keyboard.
    ///
    /// While the owner says price or link, the name field does nothing: the other field takes
    /// the keyboard, which ends editing here by itself. Resigning first would drop the keyboard
    /// between the two fields; taking it back would steal it (CI run 44129716390).
    static func action(focus: InlineField?, requestPending: Bool, isFirstResponder: Bool) -> NameFieldFocus {
        switch focus {
        case .name:
            if requestPending { return .grantRequest }
            return isFirstResponder ? .none : .reclaimIfUnclaimed
        case nil:
            return isFirstResponder ? .resign : .none
        case .price, .link:
            return .none
        }
    }
}

/// When the name field takes the keyboard for a request (`InlineFocus.nameRequest`): once for
/// each new value, until it begins or ends editing. Unlike a reclaim, a request takes the
/// keyboard even from another field (inline add opened in another group while its price field
/// had it). The field may not be in a window yet; `WindowAwareTextField` grants it then.
struct FocusRequest: Equatable {
    /// The last request value seen; `nil` before the first one.
    private(set) var handled: Int?
    /// A request not granted yet.
    private(set) var isPending = false

    /// The request value from the latest update; a new value asks for the keyboard.
    mutating func receive(_ request: Int) {
        guard request != handled else { return }
        handled = request
        isPending = true
    }

    /// The field began or ended editing: the request is used up or superseded.
    mutating func editingChanged() {
        isPending = false
    }

    /// Takes the keyboard back after losing it, without a request? Only when a view update
    /// still said the name field has it (`InlineFocus.field == .name`) (the loss happened inside an update, e.g. the list
    /// re-laying out the row: CI run on PR #8, `testDetailsButtonSavesAndOpensDetails`) and,
    /// checked a turn later, no other responder holds the keyboard.
    ///
    /// - A user dismissal (scroll, the iPad hide-keyboard key, Back) reaches SwiftUI before
    ///   the next update, so `updateSaysEditing` is false: the inline row closes as specified.
    /// - A hand-off to the price or link field leaves another first responder: never taken
    ///   back (CI run 44129716390). A non-text first responder (on iPad, the hosting view
    ///   for keyboard shortcuts) doesn't hold the keyboard and doesn't count.
    static func shouldReclaim(updateSaysEditing: Bool, isInWindow: Bool, isFirstResponder: Bool,
                              anotherFieldHasKeyboard: Bool) -> Bool {
        updateSaysEditing && isInWindow && !isFirstResponder && !anotherFieldHasKeyboard
    }
}

extension UIResponder {
    private static weak var foundFirstResponder: UIResponder?

    /// The current first responder of the app, if any (an action sent to `nil` goes to it).
    static var currentFirstResponder: UIResponder? {
        foundFirstResponder = nil
        UIApplication.shared.sendAction(#selector(reportAsFirstResponder), to: nil, from: nil, for: nil)
        return foundFirstResponder
    }

    @objc private func reportAsFirstResponder() {
        UIResponder.foundFirstResponder = self
    }
}

/// A `UITextField` that reports when it is added to a window, the earliest moment it can
/// become first responder.
final class WindowAwareTextField: UITextField {
    var onMoveToWindow: ((UITextField) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onMoveToWindow?(self) }
    }
}
