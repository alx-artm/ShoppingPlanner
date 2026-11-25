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
    /// Spec 11 (MH-05): toggled in the details, saved with ✓ like the other fields.
    var isMustHave = false
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
        isMustHave = item.isMustHave
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

/// Rules for an item's link (spec 05 Link, 06 LP-06, LP-08).
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

    /// The text stored in `urlString` (spec 06 LP-06, D7): a web address with its scheme
    /// ("ikea.com/sofa" → "https://ikea.com/sofa"); anything else only trimmed.
    /// One stored form makes "did the link change?" (LP-10) a plain comparison.
    static func normalized(_ text: String) -> String {
        if let url = url(from: text) {
            return url.absoluteString
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Query keys that only track where a visit came from (spec 06 SE-15, owner decision (d)),
    /// compared case-insensitively. Everything else (variant, size, colour, `id`…) names the product.
    /// - `utm_*`: Google Analytics campaign tags; `_su_rec*`: Shopify search & recommendations
    ///   (Allbirds `?_su_rec=…&_su_rec_id=…`).
    /// - Ad click ids: `fbclid` (Meta), `gclid` / `dclid` / `gbraid` / `wbraid` (Google),
    ///   `msclkid` (Microsoft), `yclid` (Yandex); `igshid` (Instagram share).
    /// - `mc_cid` / `mc_eid` (Mailchimp), `_ga` / `_gl` (Google cross-domain), `ref_src` (X/Twitter).
    static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "mc_cid", "mc_eid", "_ga", "_gl", "igshid", "ref_src",
    ]
    static let trackingKeyPrefixes = ["utm_", "_su_rec"]

    static func isTrackingKey(_ name: String) -> Bool {
        let key = name.lowercased()
        return trackingKeys.contains(key) || trackingKeyPrefixes.contains { key.hasPrefix($0) }
    }

    /// The link as compared for "the same product" (SE-15): `normalized`, minus the tracking
    /// query items above; the other items stay in their order, the fragment as `normalized` has it.
    /// Comparison only — the stored link is never changed (SE-09).
    /// "https://shop.com/p?_su_rec=1&size=M&utm_source=x" → "https://shop.com/p?size=M".
    static func comparisonKey(_ text: String) -> String {
        let link = normalized(text)
        guard var components = URLComponents(string: link),
              let items = components.percentEncodedQueryItems else { return link }
        let kept = items.filter { !isTrackingKey($0.name) }
        guard kept.count != items.count else { return link }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string ?? link
    }

    /// Scheme, host and path of a link, without query and fragment: every link with the same
    /// comparison key starts with it ("https://shop.com/p?x=1#a" → "https://shop.com/p").
    static func comparisonPrefix(_ text: String) -> String {
        let link = normalized(text)
        return String(link.prefix { $0 != "?" && $0 != "#" })
    }

    /// The host shown on the row's link chip: "www.ikea.com/…" → "ikea.com".
    static func displayHost(of text: String) -> String? {
        guard let host = url(from: text)?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Every stored value of an item, as a value: taken before a swipe-delete so
/// "Undo" can put the same item back (LD-09), and the base of a duplicate.
struct ItemSnapshot: Equatable, Sendable {
    var uuid: UUID
    var name: String
    var quantity: Int
    var price: Decimal?
    var actualPrice: Decimal?
    var currencyCode: String?
    var exchangeRate: Decimal?
    var urlString: String
    var linkTitle: String?
    var linkHost: String?
    var linkImageData: Data?
    var linkFetchedAt: Date?
    var notes: String
    var isComplete: Bool
    var completedAt: Date?
    var isMustHave: Bool
    var sortIndex: Double
    var createdAt: Date
    var groupID: UUID?

    init(_ item: ItemModel) {
        uuid = item.uuid
        name = item.name
        quantity = item.quantity
        price = item.price
        actualPrice = item.actualPrice
        currencyCode = item.currencyCode
        exchangeRate = item.exchangeRate
        urlString = item.urlString
        linkTitle = item.linkTitle
        linkHost = item.linkHost
        linkImageData = item.linkImageData
        linkFetchedAt = item.linkFetchedAt
        notes = item.notes
        isComplete = item.isComplete
        completedAt = item.completedAt
        isMustHave = item.isMustHave
        sortIndex = item.sortIndex
        createdAt = item.createdAt
        groupID = item.group?.uuid
    }

    /// A new, not yet inserted model with these values.
    func makeItem() -> ItemModel {
        let item = ItemModel(uuid: uuid, name: name, quantity: quantity, price: price,
                             currencyCode: currencyCode, exchangeRate: exchangeRate, urlString: urlString,
                             notes: notes, isComplete: isComplete, completedAt: completedAt,
                             isMustHave: isMustHave, sortIndex: sortIndex, createdAt: createdAt)
        item.actualPrice = actualPrice
        item.linkTitle = linkTitle
        item.linkHost = linkHost
        item.linkImageData = linkImageData
        item.linkFetchedAt = linkFetchedAt
        return item
    }
}
