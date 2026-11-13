//
//  ItemDraft.swift
//  Project2
//
//  The values edited on the item details sheet (spec 05). Like `ListDraft`:
//  the sheet edits this copy, never the model, so ✕ throws every change away
//  and ✓ applies all of them in one save (ID-01). `PlannerStore` applies it.
//

import Foundation

struct ItemDraft: Equatable, Sendable {
    var name: String = ""
    /// `nil` = no price (ID-03).
    var price: Decimal?
    /// 1...999 (ID-05).
    var quantity: Int = 1
    var urlString: String = ""
    var notes: String = ""
    /// The group the item is in, or moves to on ✓ (ID-08).
    var groupID: UUID?

    /// Read-only in v1 (item currency is v1.1); kept so the total matches the row.
    private(set) var currencyCode: String?
    private(set) var exchangeRate: Decimal?

    /// A new item in `groupID`.
    init(groupID: UUID? = nil) {
        self.groupID = groupID
    }

    /// The current values of an existing item.
    init(item: ItemModel) {
        name = item.name
        price = item.price
        quantity = item.quantity
        urlString = item.urlString
        notes = item.notes
        groupID = item.group?.uuid
        currencyCode = item.currencyCode
        exchangeRate = item.exchangeRate
    }

    /// The name is not blank after trimming (ID-02).
    var hasValidName: Bool {
        PlannerStore.normalizedName(name) != nil
    }

    /// No price, or a price ≥ 0 (ID-03).
    var hasValidPrice: Bool {
        price.map { $0 >= 0 } ?? true
    }

    /// ✓ is enabled only for a draft the store will accept as is.
    var canSave: Bool {
        hasValidName && hasValidPrice
    }

    /// `price × quantity` in the list currency; `nil` without a price, shown as "—" (ID-04).
    func lineTotal(listCurrencyCode: String) -> Decimal? {
        BudgetCalculator.lineTotal(
            of: BudgetLine(price: price, quantity: quantity, currencyCode: currencyCode, exchangeRate: exchangeRate),
            listCurrencyCode: listCurrencyCode
        )
    }

    /// The link as a URL that can be opened, or `nil` (no link, or not a web address).
    var linkURL: URL? {
        ItemLink.url(from: urlString)
    }

    /// The quantity typed into the number field: digits only, clamped to 1...999 (ID-05).
    /// `nil` while the field is empty, so the user can retype the number.
    static func quantity(from text: String) -> Int? {
        let digits = text.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        // More digits than an Int holds is still "too many": the upper bound.
        guard let value = Int(digits) else { return PlannerStore.quantityRange.upperBound }
        return PlannerStore.clampedQuantity(value)
    }
}

/// Rules for an item's link (spec 05 Link, 06 LP-08). The preview card is M5.
enum ItemLink {
    /// "ikea.com/sofa" → "https://ikea.com/sofa". `nil` when blank or not a web address.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if !trimmed.contains("://"),
           trimmed.prefix(while: { $0 != "/" }).contains("@") {
            return nil // "mailto:a@b.com", "user@shop.com": not a web page
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".") else {
            return nil
        }
        return url
    }

    /// The host shown on the row's link chip: "www.ikea.com/…" → "ikea.com".
    static func displayHost(of text: String) -> String? {
        guard let host = url(from: text)?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
