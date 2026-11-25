//
//  SharePage.swift
//  Project2
//
//  What Safari's preprocessing script (`ShareExtension/SharePreprocessing.js`) collected
//  from the shared page, and the rules that turn it into a price (spec 06 B.4 p.4, SE-01a,
//  SE-07). The script only collects strings; every choice is made here, in pure code that
//  the unit tests cover with fixtures.
//

import Foundation

/// The strings the script collected, limited and checked. Only Safari sends them.
struct SharePage: Equatable, Sendable {
    /// `document.URL`; used only when the request has no `public.url` of its own.
    var url: URL?
    /// `document.title`.
    var title: String?
    /// `<meta property="og:title">`.
    var ogTitle: String?
    /// `og:image:secure_url`, else `og:image`, made absolute by the script; http(s) only.
    /// Shopify stores put an `http://` address into `og:image` (App Transport Security blocks
    /// it in the extension) and the `https://` one into `og:image:secure_url`.
    var imageURL: URL?
    /// `<link rel="canonical">`. Collected, not stored: the item keeps the shared link,
    /// which still has the variant parameters (SE-09).
    var canonicalURL: URL?
    /// `product:price:amount` / `product:price:currency` values, every one on the page.
    var productPrice = MetaPrice()
    /// `og:price:amount` / `og:price:currency` values.
    var ogPrice = MetaPrice()
    /// Texts of `<script type="application/ld+json">`: at most `maxJSONLDBlocks`, each at
    /// most `maxJSONLDLength` characters (longer ones are dropped, not cut: half a JSON is no JSON).
    var jsonLD: [String] = []

    /// The `<meta>` price pair. Several values are kept so that a page with two different
    /// prices is seen as ambiguous instead of taking the first one.
    struct MetaPrice: Equatable, Sendable {
        var amounts: [String] = []
        var currencies: [String] = []
    }

    static let maxJSONLDBlocks = 5
    static let maxJSONLDLength = 50 * 1024
    /// Longest title or URL taken from the page; the name is cut to 150 later anyway.
    static let maxTextLength = 2048
    /// At most this many `<meta>` price values of one kind.
    static let maxMetaValues = 5

    /// The keys of the script's result. Keep in sync with `SharePreprocessing.js`.
    enum Key {
        static let url = "url"
        static let title = "title"
        static let ogTitle = "ogTitle"
        static let ogImage = "ogImage"
        static let ogImageSecure = "ogImageSecure"
        static let canonical = "canonical"
        static let productPriceAmount = "productPriceAmount"
        static let productPriceCurrency = "productPriceCurrency"
        static let ogPriceAmount = "ogPriceAmount"
        static let ogPriceCurrency = "ogPriceCurrency"
        static let jsonLD = "jsonLD"
    }

    init(url: URL? = nil, title: String? = nil, ogTitle: String? = nil, imageURL: URL? = nil,
         canonicalURL: URL? = nil, productPrice: MetaPrice = MetaPrice(), ogPrice: MetaPrice = MetaPrice(),
         jsonLD: [String] = []) {
        self.url = url
        self.title = title
        self.ogTitle = ogTitle
        self.imageURL = imageURL
        self.canonicalURL = canonicalURL
        self.productPrice = productPrice
        self.ogPrice = ogPrice
        self.jsonLD = jsonLD
    }

    /// Reads the dictionary Safari hands over (`NSExtensionJavaScriptPreprocessingResultsKey`).
    /// Anything of the wrong type or too long is ignored; this never fails (SE-01a (e)).
    init(results: [String: Any]) {
        func text(_ key: String) -> String? {
            guard let value = results[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(Self.maxTextLength))
        }
        func webURL(_ key: String) -> URL? {
            guard let value = text(key), let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host() != nil else { return nil }
            return url
        }
        func texts(_ key: String) -> [String] {
            let values = (results[key] as? [Any] ?? []).compactMap { $0 as? String }
            return values.prefix(Self.maxMetaValues).map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            }.filter { !$0.isEmpty }
        }

        url = webURL(Key.url)
        title = text(Key.title)
        ogTitle = text(Key.ogTitle)
        imageURL = webURL(Key.ogImageSecure) ?? webURL(Key.ogImage)
        canonicalURL = webURL(Key.canonical)
        productPrice = MetaPrice(amounts: texts(Key.productPriceAmount), currencies: texts(Key.productPriceCurrency))
        ogPrice = MetaPrice(amounts: texts(Key.ogPriceAmount), currencies: texts(Key.ogPriceCurrency))
        jsonLD = (results[Key.jsonLD] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .filter { !$0.isEmpty && $0.count <= Self.maxJSONLDLength }
            .prefix(Self.maxJSONLDBlocks)
            .map { $0 }
    }

    /// The name candidate of the page (SE-02): og:title, else the document title, cleaned.
    func cleanedTitle(host: String) -> String? {
        ShareTitle.clean(ogTitle, host: host) ?? ShareTitle.clean(title, host: host)
    }
}

/// A price the page states: an amount in one currency.
struct PagePrice: Equatable, Sendable {
    let amount: Decimal
    /// ISO 4217, upper case, in current use.
    let currencyCode: String
}

/// Turns the page's machine-readable price into a suggestion for the price field (SE-07, B1 = A).
enum SharePrice {
    /// What the price field gets.
    enum Suggestion: Equatable, Sendable {
        /// Nothing found, or nothing unambiguous: the field stays empty.
        case none
        /// The page price is in the list currency: the field is prefilled with this amount,
        /// rounded to the currency's fraction digits.
        case prefill(Decimal)
        /// The page price is in another currency: the field stays empty, the hint shows it.
        case hint(PagePrice)
    }

    /// The suggestion for a list in `listCurrency`. No conversion between currencies (B1, C is out).
    static func suggestion(for price: PagePrice?, listCurrency: String) -> Suggestion {
        guard let price else { return .none }
        guard price.currencyCode == listCurrency.uppercased() else { return .hint(price) }
        let digits = CurrencyAffix(currencyCode: price.currencyCode, locale: Locale(identifier: "en_US_POSIX"))
            .fractionDigits
        return .prefill(MoneyInput.rounded(price.amount, fractionDigits: digits))
    }

    /// The one price of the page, or `nil` when there is none or it is ambiguous (SE-07):
    /// - JSON-LD `Product` offers win. Every offer of every product must name the same amount
    ///   and currency; an `AggregateOffer` (a price range), a missing currency, a price ≤ 0 or
    ///   one that isn't a number makes the whole page ambiguous — the `<meta>` tags are not
    ///   asked then, because the page itself said the price is not one number.
    /// - Without JSON-LD offers: `product:price:*`, else `og:price:*`, again only when every
    ///   value of the pair agrees.
    static func pagePrice(of page: SharePage) -> PagePrice? {
        switch jsonLDPrice(page.jsonLD) {
        case .price(let price): return price
        case .ambiguous: return nil
        case .notFound: break
        }
        if !page.productPrice.amounts.isEmpty || !page.productPrice.currencies.isEmpty {
            return metaPrice(page.productPrice)
        }
        return metaPrice(page.ogPrice)
    }

    // MARK: Numbers and currencies

    /// "1299.00", "1299", "0.5" → the amount; "1,299.00", "1 299", "$12", "-3", "" → `nil`.
    /// Machine-readable prices use the POSIX format, never the device's locale (SE-07).
    static func amount(posix raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.wholeMatch(of: /[0-9]{1,12}(\.[0-9]{1,6})?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// "usd " → "USD"; "$", "руб", "XYZ", "DEM" (not in use) → `nil`.
    static func currencyCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.wholeMatch(of: /[A-Z]{3}/) != nil, CurrencyCatalog.isActive(code) else { return nil }
        return code
    }

    // MARK: JSON-LD

    enum JSONLDResult: Equatable {
        case price(PagePrice)
        /// Products with offers, but not one clear price.
        case ambiguous
        /// No product with offers in any block.
        case notFound
    }

    static func jsonLDPrice(_ blocks: [String]) -> JSONLDResult {
        var prices: [PagePrice] = []
        var sawOffers = false
        var isAmbiguous = false
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                continue // broken JSON: some sites ship it; the block is skipped
            }
            for product in products(in: json, depth: 0) {
                guard let offers = product["offers"] else { continue }
                sawOffers = true
                for offer in list(offers) {
                    guard let offer = offer as? [String: Any], let price = offerPrice(offer) else {
                        isAmbiguous = true
                        continue
                    }
                    prices.append(price)
                }
            }
        }
        guard sawOffers else { return .notFound }
        guard !isAmbiguous, let first = prices.first, prices.allSatisfy({ $0 == first }) else { return .ambiguous }
        return .price(first)
    }

    /// `Product` nodes: the block itself, an array, `@graph`, or nested in other nodes
    /// (`mainEntity`, `itemListElement`). A product's own children (`isSimilarTo`,
    /// `isRelatedTo`) are not searched: those are other products.
    private static func products(in json: Any, depth: Int) -> [[String: Any]] {
        guard depth < 8 else { return [] }
        if let array = json as? [Any] {
            return array.flatMap { products(in: $0, depth: depth + 1) }
        }
        guard let object = json as? [String: Any] else { return [] }
        if isType(object, "Product") { return [object] }
        return object.values.flatMap { products(in: $0, depth: depth + 1) }
    }

    /// The offer's price, or `nil` when it is a range or anything is missing or wrong.
    private static func offerPrice(_ offer: [String: Any]) -> PagePrice? {
        if isType(offer, "AggregateOffer") || offer["lowPrice"] != nil || offer["highPrice"] != nil {
            return nil
        }
        // `price` + `priceCurrency` on the offer, or in `priceSpecification`. IKEA lists the
        // current price there next to the old one (`priceType: StrikethroughPrice`): reference
        // prices are skipped, and exactly one price must be left.
        var source = offer
        if offer["price"] == nil, let specifications = offer["priceSpecification"] {
            let current = list(specifications).compactMap { $0 as? [String: Any] }.filter { !isReferencePrice($0) }
            guard current.count == 1, let specification = current.first else { return nil }
            source = specification
        }
        guard let amountText = scalarText(source["price"]), let amount = amount(posix: amountText), amount > 0,
              let currencyText = scalarText(source["priceCurrency"] ?? offer["priceCurrency"]),
              let currency = currencyCode(currencyText) else { return nil }
        return PagePrice(amount: amount, currencyCode: currency)
    }

    /// Schema.org `priceType`s that name a price the buyer doesn't pay now (old, list, suggested).
    private static let referencePriceTypes: Set<String> = [
        "StrikethroughPrice", "ListPrice", "MSRP", "SRP", "MinimumAdvertisedPrice", "InvoicePrice",
    ]

    private static func isReferencePrice(_ specification: [String: Any]) -> Bool {
        guard let type = specification["priceType"] as? String else { return false }
        let name = type.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? type
        return referencePriceTypes.contains(name)
    }

    /// `"@type": "Product"`, `["Product", "Thing"]`, `"schema:Product"`, `"https://schema.org/Product"`.
    private static func isType(_ object: [String: Any], _ type: String) -> Bool {
        let types = list(object["@type"] ?? []).compactMap { $0 as? String }
        return types.contains { value in
            value == type || value.hasSuffix("/" + type) || value.hasSuffix(":" + type)
        }
    }

    private static func list(_ value: Any) -> [Any] {
        value as? [Any] ?? [value]
    }

    /// A JSON string or number as text; numbers keep their JSON spelling ("449.99", not a double).
    private static func scalarText(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.stringValue
    }

    // MARK: Meta tags

    private static func metaPrice(_ meta: SharePage.MetaPrice) -> PagePrice? {
        guard let amountText = meta.amounts.first, meta.amounts.allSatisfy({ $0 == amountText }),
              let currencyText = meta.currencies.first,
              meta.currencies.allSatisfy({ $0.uppercased() == currencyText.uppercased() }),
              let amount = amount(posix: amountText), amount > 0,
              let currency = currencyCode(currencyText) else { return nil }
        return PagePrice(amount: amount, currencyCode: currency)
    }
}
