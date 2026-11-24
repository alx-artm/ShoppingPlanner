//
//  ShareComposerView.swift
//  Project2
//
//  The Share Extension's screens (spec 06 B.2): the compose form, "This link can't be
//  added" and "isn't available right now". Shown by `ShareViewController` in the extension
//  and, for UI tests, in a sheet of the app (`-UITestsShareComposer`, B.5).
//

import SwiftUI

/// What the extension shows.
enum ShareScreen {
    case compose(ShareComposerModel)
    case unsupported
    case unavailable
}

struct ShareRootView: View {
    let screen: ShareScreen
    /// The item was saved: close (and, in the extension, signal the app).
    let onSave: () -> Void
    /// Cancel, Close, or swipe down: nothing was written.
    let onCancel: () -> Void

    var body: some View {
        switch screen {
        case .compose(let model):
            ShareComposerView(model: model, onSave: onSave, onCancel: onCancel)
        case .unsupported:
            ShareMessageView(
                title: "This link can't be added",
                message: "Share a web page link, like a product page in Safari.",
                systemImage: "link.badge.plus",
                identifier: "share.unsupported",
                onClose: onCancel)
        case .unavailable:
            ShareMessageView(
                title: "Shopping Planner isn't available right now",
                message: "Open the app and try again.",
                systemImage: "exclamationmark.triangle",
                identifier: "share.unavailable",
                onClose: onCancel)
        }
    }
}

struct ShareComposerView: View {
    @Bindable var model: ShareComposerModel
    let onSave: () -> Void
    let onCancel: () -> Void

    private enum Field: Hashable { case name, newList, price }
    @FocusState private var focus: Field?
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLinkCard(title: model.pageTitle, host: model.payload.host)
                }
                Section("Name") {
                    TextField("Item name", text: Binding(get: { model.name }, set: { model.editName($0) }),
                              axis: .vertical)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("share.nameField")
                }
                Section {
                    destinationRows
                }
                Section {
                    priceRow
                    Toggle(isOn: $model.isMustHave) {
                        Label("Must-Have", systemImage: "star.fill")
                    }
                    // Orange like the ★ of the row (M7.5): the switch, and the icon (a Form
                    // tints row icons with the accent unless `listItemTint` says otherwise).
                    .tint(.orange)
                    .listItemTint(.orange)
                    .accessibilityIdentifier("share.mustHaveToggle")
                } footer: {
                    if model.hasPriceError {
                        Text("Not a price")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("share.priceError")
                    }
                }
                if let error = model.saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("share.saveError")
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        model.cancel()
                        onCancel()
                    }
                    .accessibilityIdentifier("share.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() != nil { onSave() }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("share.saveButton")
                }
            }
            .navigationDestination(for: SharePickerRoute.self) { route in
                switch route {
                case .lists: ShareListPicker(model: model)
                case .groups: ShareGroupPicker(model: model)
                }
            }
        }
        .task { model.start() }
    }

    // MARK: List and group

    @ViewBuilder
    private var destinationRows: some View {
        if model.lists.isEmpty {
            // SE-05: no active list → the extension creates one.
            newListField
        } else {
            NavigationLink(value: SharePickerRoute.lists) {
                LabeledContent("List") {
                    if let list = model.selectedList {
                        ShareListLabel(list: list)
                    } else {
                        Text("New List")
                    }
                }
            }
            .accessibilityIdentifier("share.listPicker")
            if model.selectedList == nil {
                newListField
            } else if model.groups.isEmpty {
                LabeledContent("Group", value: String(localized: "Items (new)",
                    comment: "Share Extension: the group that will be created for the item, in a list without groups."))
                    .accessibilityIdentifier("share.groupPicker")
            } else {
                NavigationLink(value: SharePickerRoute.groups) {
                    LabeledContent("Group", value: model.selectedGroup?.name ?? "")
                }
                .accessibilityIdentifier("share.groupPicker")
            }
        }
    }

    private var newListField: some View {
        LabeledContent("New List Name") {
            TextField("List name", text: $model.newListName)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: .newList)
                .accessibilityIdentifier("share.newListName")
        }
    }

    // MARK: Price

    private var priceRow: some View {
        let affix = CurrencyAffix(currencyCode: model.currencyCode, locale: locale)
        return LabeledContent("Price") {
            HStack(spacing: 4) {
                if affix.position == .prefix { symbol(affix) }
                TextField("Price", text: $model.priceText)
                    .keyboardType(affix.fractionDigits == 0 ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, alignment: .trailing)
                    .focused($focus, equals: .price)
                    .accessibilityIdentifier("share.priceField")
                if affix.position == .suffix { symbol(affix) }
            }
        }
        // The field hugs its digits; a tap anywhere on the row starts typing.
        .contentShape(.rect)
        .onTapGesture { focus = .price }
    }

    private func symbol(_ affix: CurrencyAffix) -> some View {
        Text(verbatim: affix.symbol)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            .accessibilityIdentifier("share.priceField.symbol")
    }
}

private enum SharePickerRoute: Hashable {
    case lists, groups
}

/// The page: tile, title, host (B.2). PR 2 puts the og:image into the tile.
private struct ShareLinkCard: View {
    let title: String?
    let host: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                // Without a page title yet, the host alone (not twice).
                Text(verbatim: title ?? host)
                    .font(.headline)
                    .lineLimit(3)
                if title != nil {
                    Text(verbatim: host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Link: \(title ?? host), \(host)"))
        .accessibilityIdentifier("share.linkCard")
    }
}

/// "🏠 Apartment (EUR)" in the List row and the picker.
private struct ShareListLabel: View {
    let list: ListModel

    var body: some View {
        HStack(spacing: 8) {
            ListIconBadge(list: list, diameter: 24)
            Text(verbatim: list.name)
                .foregroundStyle(.primary)
            Text(verbatim: list.currencyCode)
                .foregroundStyle(.secondary)
        }
    }
}

/// Active lists, pinned first, then "New List…" (SE-04a).
private struct ShareListPicker: View {
    @Bindable var model: ShareComposerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(model.lists) { list in
                Button {
                    model.destination = .list(list.uuid)
                    dismiss()
                } label: {
                    HStack {
                        ShareListLabel(list: list)
                        Spacer()
                        if model.destination == .list(list.uuid) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(model.destination == .list(list.uuid) ? .isSelected : [])
                .accessibilityIdentifier("share.listRow.\(list.name)")
            }
            Button {
                model.destination = .newList
                dismiss()
            } label: {
                Label("New List…", systemImage: "plus")
            }
            .accessibilityIdentifier("share.newListRow")
        }
        .navigationTitle("List")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The selected list's groups in display order (SE-04).
private struct ShareGroupPicker: View {
    @Bindable var model: ShareComposerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(model.groups) { group in
            Button {
                model.groupID = group.uuid
                dismiss()
            } label: {
                HStack {
                    Text(verbatim: group.name).foregroundStyle(.primary)
                    Spacer()
                    if model.groupID == group.uuid {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityAddTraits(model.groupID == group.uuid ? .isSelected : [])
            .accessibilityIdentifier("share.groupRow.\(group.name)")
        }
        .navigationTitle("Group")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "This link can't be added" / "isn't available right now" + Close.
private struct ShareMessageView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    let identifier: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
            .accessibilityIdentifier(identifier)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier("share.closeButton")
                }
            }
        }
    }
}
