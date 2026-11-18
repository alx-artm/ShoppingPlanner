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

import SwiftUI
import UIKit

struct InlineNameField<Accessory: View>: UIViewRepresentable {
    /// Mirror of the typed text, for the draft. Read only from the SwiftUI side.
    @Binding var text: String
    /// The field has the keyboard (reported by the field). Set to `false` to close the keyboard.
    @Binding var isEditing: Bool
    /// Each new value asks for the keyboard once (opening inline add). Not `isEditing`: that
    /// value can be stale for one update after the keyboard moved to the price or link field,
    /// and "editing but not first responder" then took the keyboard back (CI run 44129716390).
    let focusRequest: Int
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
        coordinator.focusRequest.receive(focusRequest)
        if coordinator.focusRequest.isPending {
            coordinator.grantFocusRequest(to: field)
        } else if !isEditing, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InlineNameField
        var accessoryHost: UIHostingController<Accessory>?
        var focusRequest = FocusRequest()

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

        func textFieldDidBeginEditing(_ field: UITextField) {
            focusRequest.editingChanged()
            if !parent.isEditing { parent.isEditing = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            focusRequest.editingChanged()
            if parent.isEditing { parent.isEditing = false }
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

/// When a field asks for the keyboard: once for each new request value, until it begins or
/// ends editing. After the keyboard has moved on ([Price] / [Link], Done), only the user or a
/// new request brings it back; a stale "is editing" never does (CI run 44129716390).
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
