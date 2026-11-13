//
//  InlineItemRow.swift
//  Project2
//
//  "＋ New Item" turned into a text field (spec 04 "Inline add", LD-12...LD-17):
//  type a name, Return saves it and leaves the keyboard up for the next one.
//  Price, quantity and link open in the same row from the keyboard's
//  accessory bar. The text is kept as typed: no trimming until commit (LD-16)
//  and no parsing ("Sofa 450 x2" is a name, LD-17).
//
//  The draft and the focus belong to the list screen, which commits them
//  through `PlannerStore`; this view only lays the fields out.
//

import SwiftUI

/// Which SwiftUI inline field has the keyboard (the name field is tracked separately,
/// it is a UIKit field).
enum InlineField: Hashable {
    case price, link
}

/// The extra fields shown in the inline row, opened from the accessory bar.
struct InlineExtras: Equatable {
    var showsPrice = false
    var showsQuantity = false
    var showsLink = false
}

struct InlineItemRow<Accessory: View>: View {
    @Binding var draft: ItemDraft
    /// The name field has the keyboard (it is a UIKit field, see `InlineNameField`).
    @Binding var isEditingName: Bool
    let extras: InlineExtras
    let currencyCode: String
    let focus: FocusState<InlineField?>.Binding
    /// Return in the name field, with the line typed.
    let onReturn: (String) -> Void
    /// The keyboard accessory bar of the name field.
    let accessory: Accessory

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title2) private var checkboxSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                    .frame(width: checkboxSize, height: checkboxSize)
                    .accessibilityHidden(true)
                InlineNameField(text: $draft.name, isEditing: $isEditingName, onReturn: onReturn,
                                accessory: accessory)
                    .frame(minHeight: 44)
            }

            Group {
                if extras.showsPrice {
                    HStack {
                        MoneyField("Price", value: $draft.price, currencyCode: currencyCode,
                                   focus: focus, field: .price, identifier: "inline.priceField")
                        if let total = draft.lineTotal(listCurrencyCode: currencyCode) {
                            // The live line total (spec 04 Inline add, step 3).
                            Text(verbatim: "= " + MoneyFormat.string(total, currencyCode: currencyCode, locale: locale))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .accessibilityIdentifier("inline.total")
                        }
                    }
                }
                if extras.showsQuantity {
                    Stepper(value: $draft.quantity, in: PlannerStore.quantityRange) {
                        Text("Quantity: \(draft.quantity)")
                            .monospacedDigit()
                    }
                    .sensoryFeedback(.selection, trigger: draft.quantity)
                    .accessibilityIdentifier("inline.quantityStepper")
                }
                if extras.showsLink {
                    TextField("https://…", text: $draft.urlString)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused(focus, equals: .link)
                        .accessibilityLabel(Text("Link"))
                        .accessibilityIdentifier("inline.linkField")
                }
            }
            .padding(.leading, checkboxSize + 4)
        }
        .padding(.vertical, 2)
    }
}
