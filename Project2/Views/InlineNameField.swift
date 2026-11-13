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
//  state) and never writes it back, so a stale value can't overwrite typing.
//
//  SwiftUI's `.toolbar(placement: .keyboard)` doesn't reach a UIKit field, so
//  the accessory bar is hosted as the field's `inputAccessoryView`.
//

import SwiftUI
import UIKit

struct InlineNameField<Accessory: View>: UIViewRepresentable {
    /// Mirror of the typed text, for the draft. Read only from the SwiftUI side.
    @Binding var text: String
    /// The field has the keyboard. Set to `true` to focus it.
    @Binding var isEditing: Bool
    /// Return: the line typed (not trimmed; the store trims on commit, LD-16).
    /// The field is already empty when this is called.
    let onReturn: (String) -> Void
    /// Shown above the keyboard while this field is being edited.
    let accessory: Accessory

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
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
        // Focus only; the text is never written from here (see the file comment).
        if isEditing, !field.isFirstResponder {
            // After the field is in a window: becoming first responder before that is ignored.
            Task { @MainActor in field.becomeFirstResponder() }
        } else if !isEditing, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InlineNameField
        var accessoryHost: UIHostingController<Accessory>?

        init(parent: InlineNameField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isEditing { parent.isEditing = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
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
