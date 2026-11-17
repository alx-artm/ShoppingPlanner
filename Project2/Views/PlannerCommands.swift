//
//  PlannerCommands.swift
//  Project2
//
//  iPad keyboard shortcuts (spec 08 AD-12, M4 plan step 6, Q5 → A):
//  ⌘N new item, ⇧⌘N new group, ⌘⌫ delete the item in an open item sheet
//  (it asks first). There is deliberately no shortcut for deleting a list.
//
//  Commands live on the scene, so they show in the iPadOS menu bar and in
//  the overlay that appears while ⌘ is held. The list screen publishes what
//  the commands act on with `focusedSceneValue`; a command whose value is
//  missing is disabled. The item action is published by the list screen too:
//  a value published from inside a sheet doesn't reach the scene's commands.
//

import SwiftUI

/// What the list screen offers to the commands; `nil` while a sheet or an alert covers it.
struct ListShortcutActions {
    let newItem: @MainActor () -> Void
    let newGroup: @MainActor () -> Void
}

/// Item details are open (published by the list screen that presents them).
struct ItemShortcutActions {
    /// Asks "Delete …?" first, like the Delete Item button (ID-11).
    let requestDelete: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var listShortcutActions: ListShortcutActions?
    @Entry var itemShortcutActions: ItemShortcutActions?
}

struct PlannerCommands: Commands {
    @FocusedValue(\.listShortcutActions) private var listActions
    @FocusedValue(\.itemShortcutActions) private var itemActions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Item") { listActions?.newItem() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(listActions == nil)
            Button("New Group") { listActions?.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(listActions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Delete Item") { itemActions?.requestDelete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(itemActions == nil)
        }
    }
}
