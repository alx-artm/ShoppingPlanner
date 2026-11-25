//
//  ShareSafariTests.swift
//  Project2Tests
//
//  Spec 06 Part B (M7, PR 2): what Safari's preprocessing script collects and what the Share
//  Extension makes of it. The script itself only collects strings; every rule is Swift and is
//  tested here with fixtures (B.4 p.4): reading the result (SE-01a), the name order (SE-02),
//  the page price (SE-07), the picture (B3, SE-09, SE-13) and the duplicate hint (SE-15).
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import Project2

// MARK: - Reading the script's result

@Suite("Share Extension: Safari page", .tags(.shareExtension))
struct SharePageTests {
    @Test("SE-01a (a) every key of the script is read; blanks and wrong types are ignored")
    func readsResults() throws {
        let page = SharePage(results: [
            SharePage.Key.url: "https://www.ikea.com/p/kivik?color=blue",
            SharePage.Key.title: "  KIVIK sofa - IKEA \n",
            SharePage.Key.ogTitle: "KIVIK 3-seat sofa",
            SharePage.Key.ogImage: "https://www.ikea.com/images/kivik.jpg",
            SharePage.Key.canonical: "https://www.ikea.com/p/kivik",
            SharePage.Key.productPriceAmount: ["449.00"],
            SharePage.Key.productPriceCurrency: ["EUR"],
            SharePage.Key.ogPriceAmount: [] as [String],
            SharePage.Key.ogPriceCurrency: 42, // wrong type
            SharePage.Key.jsonLD: [#"{"@type":"Product"}"#, 7, ""],
        ])
        #expect(page.url?.absoluteString == "https://www.ikea.com/p/kivik?color=blue")
        #expect(page.title == "KIVIK sofa - IKEA")
        #expect(page.ogTitle == "KIVIK 3-seat sofa")
        #expect(page.imageURL?.absoluteString == "https://www.ikea.com/images/kivik.jpg")
        #expect(page.canonicalURL?.absoluteString == "https://www.ikea.com/p/kivik")
        #expect(page.productPrice == SharePage.MetaPrice(amounts: ["449.00"], currencies: ["EUR"]))
        #expect(page.ogPrice == SharePage.MetaPrice())
        #expect(page.jsonLD == [#"{"@type":"Product"}"#])
    }

    @Test("SE-01a (a) an empty result is an empty page, not a failure")
    func emptyResults() {
        let page = SharePage(results: [:])
        #expect(page == SharePage())
        #expect(page.cleanedTitle(host: "ikea.com") == nil)
    }

    @Test("B3 og:image:secure_url wins over an http:// og:image (Shopify)")
    func secureImage() {
        let page = SharePage(results: [
            SharePage.Key.ogImage: "http://shop.example.com/cdn/a.jpg",
            SharePage.Key.ogImageSecure: "https://shop.example.com/cdn/a.jpg",
        ])
        #expect(page.imageURL?.absoluteString == "https://shop.example.com/cdn/a.jpg")
        #expect(SharePage(results: [SharePage.Key.ogImage: "http://shop.example.com/a.jpg"]).imageURL?.scheme == "http")
    }

    @Test("SE-01a only http(s) links are kept for the page, picture and canonical URL",
          arguments: ["data:image/png;base64,AAAA", "javascript:alert(1)", "/relative.jpg", "file:///tmp/a.jpg", "   "])
    func nonWebLinksDropped(_ link: String) {
        let page = SharePage(results: [SharePage.Key.url: link, SharePage.Key.ogImage: link, SharePage.Key.canonical: link])
        #expect(page.url == nil)
        #expect(page.imageURL == nil)
        #expect(page.canonicalURL == nil)
    }

    @Test("SE-01a (e) JSON-LD over the limits: at most 5 blocks, a block over 50 KB is dropped, nothing crashes")
    func jsonLDLimits() {
        let big = String(repeating: "x", count: SharePage.maxJSONLDLength + 1)
        let exact = String(repeating: "y", count: SharePage.maxJSONLDLength)
        let blocks: [String] = [big, exact] + (1...8).map { "{\"n\":\($0)}" }
        let page = SharePage(results: [SharePage.Key.jsonLD: blocks])
        #expect(page.jsonLD.count == SharePage.maxJSONLDBlocks)
        #expect(page.jsonLD.first == exact)
        #expect(!page.jsonLD.contains(big))
        #expect(SharePrice.pagePrice(of: page) == nil)
    }

    @Test("SE-01a long titles and many meta values are cut, not rejected")
    func textLimits() {
        let page = SharePage(results: [
            SharePage.Key.title: String(repeating: "a", count: 10_000),
            SharePage.Key.productPriceAmount: Array(repeating: "1", count: 20),
        ])
        #expect(page.title?.count == SharePage.maxTextLength)
        #expect(page.productPrice.amounts.count == SharePage.maxMetaValues)
    }

    @Test("SE-01a the shared public.url wins over the page's document.URL; without it the page URL is the link")
    func linkChoice() throws {
        let page = SharePage(url: URL(string: "https://www.ikea.com/p/kivik#reviews"))
        guard case .link(let withURL) = ShareInput.from(urls: [URL(string: "https://www.ikea.com/p/kivik?color=blue")!],
                                                         texts: [], page: page) else {
            Issue.record("expected a link"); return
        }
        #expect(withURL.urlString == "https://www.ikea.com/p/kivik?color=blue")
        #expect(withURL.page == page)

        guard case .link(let pageOnly) = ShareInput.from(urls: [], texts: [], page: page) else {
            Issue.record("expected a link"); return
        }
        #expect(pageOnly.urlString == "https://www.ikea.com/p/kivik#reviews")
        #expect(ShareInput.from(urls: [], texts: [], page: SharePage()) == .unsupported)
    }

    @Test("SE-02 name order on a Safari page: og:title → document.title → the app's text → host", arguments: [
        // (og:title, title, app text, expected name)
        ("KIVIK 3-seat sofa - IKEA", "KIVIK sofa, beige - IKEA", "Shared text", "KIVIK 3-seat sofa"),
        ("   ", "KIVIK sofa, beige - IKEA", "Shared text", "KIVIK sofa, beige"),
        (nil, "IKEA - KIVIK sofa", nil, "KIVIK sofa"),
        (nil, nil, "Shared text", "Shared text"),
        (nil, nil, nil, "ikea.com"),
    ] as [(String?, String?, String?, String)])
    @MainActor
    func nameOrder(ogTitle: String?, title: String?, appText: String?, expected: String) throws {
        var results: [String: Any] = [:]
        results[SharePage.Key.ogTitle] = ogTitle
        results[SharePage.Key.title] = title
        let fixture = try StoreFixture()
        let composer = try ShareSafariFixture.model(fixture, page: SharePage(results: results), text: appText)
        #expect(composer.name == expected)
        #expect(composer.pageTitle == (expected == "ikea.com" ? nil : expected))
    }
}

// MARK: - Comparison key

@Suite("Share Extension: link comparison key", .tags(.shareExtension))
struct LinkComparisonKeyTests {
    @Test("SE-15 (d) tracking keys are removed, every other query item stays in order", arguments: [
        ("https://www.allbirds.com/products/runner?_su_rec=111&_su_rec_id=a", "https://www.allbirds.com/products/runner"),
        ("https://shop.com/p?_su_rec=1&size=M&utm_source=x&color=blue", "https://shop.com/p?size=M&color=blue"),
        ("https://shop.com/p?variant=42&gclid=abc", "https://shop.com/p?variant=42"),
        ("https://shop.com/p?UTM_Source=x&FBCLID=y&Size=L", "https://shop.com/p?Size=L"),
        ("https://shop.com/p?fbclid=1&dclid=2&gbraid=3&wbraid=4&msclkid=5&yclid=6&mc_cid=7&mc_eid=8&_ga=9&_gl=10&igshid=11&ref_src=12",
         "https://shop.com/p"),
        ("https://shop.com/p?id=7&ref=homepage", "https://shop.com/p?id=7&ref=homepage"),
        ("https://shop.com/p?q=a%20b&utm_medium=email", "https://shop.com/p?q=a%20b"),
        ("https://shop.com/p?utm_source=x#reviews", "https://shop.com/p#reviews"),
        ("https://shop.com/p", "https://shop.com/p"),
        ("shop.com/p?utm_source=x", "https://shop.com/p"),
        ("not a link", "not a link"),
    ])
    func comparisonKey(_ link: String, _ expected: String) {
        #expect(ItemLink.comparisonKey(link) == expected)
    }

    @Test("SE-15 (d) the fetch prefix is scheme + host + path", arguments: [
        ("https://shop.com/p?x=1#a", "https://shop.com/p"),
        ("https://shop.com/p#a", "https://shop.com/p"),
        ("shop.com", "https://shop.com"),
    ])
    func comparisonPrefix(_ link: String, _ expected: String) {
        #expect(ItemLink.comparisonPrefix(link) == expected)
        #expect(ItemLink.comparisonKey(link).hasPrefix(expected))
    }
}

// MARK: - Price

@Suite("Share Extension: page price", .tags(.shareExtension))
struct SharePriceTests {
    @Test("SE-07 amounts are read in POSIX format, never in the device's locale", arguments: [
        ("1299.00", "1299"), ("1299", "1299"), ("449.99", "449.99"), (" 0.5 ", "0.5"), ("0", "0"),
    ])
    func posixAmounts(_ text: String, _ expected: String) {
        #expect(SharePrice.amount(posix: text) == dec(expected))
    }

    @Test("SE-07 anything else is not an amount",
          arguments: ["1,299.00", "1 299", "449,00", "$12", "-3", "12.", ".5", "1e3", "", "abc", "12.5.1", "١٢٣"])
    func notAmounts(_ text: String) {
        #expect(SharePrice.amount(posix: text) == nil)
    }

    @Test("SE-07 currency codes: ISO 4217 in use, any case", arguments: [
        ("EUR", "EUR"), ("usd ", "USD"), ("jpy", "JPY"),
    ])
    func currencies(_ text: String, _ expected: String) {
        #expect(SharePrice.currencyCode(text) == expected)
    }

    @Test("SE-07 symbols, words and old or made-up codes are no currency", arguments: ["$", "€", "руб", "EURO", "XYZ", "DEM", ""])
    func notCurrencies(_ text: String) {
        #expect(SharePrice.currencyCode(text) == nil)
    }

    // One case = JSON-LD blocks, meta pairs, and the expected price ("449.00 EUR") or nil.
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        var jsonLD: [String] = []
        var productMeta: ([String], [String]) = ([], [])
        var ogMeta: ([String], [String]) = ([], [])
        let expected: String?

        var testDescription: String { name }

        var page: SharePage {
            SharePage(productPrice: .init(amounts: productMeta.0, currencies: productMeta.1),
                      ogPrice: .init(amounts: ogMeta.0, currencies: ogMeta.1), jsonLD: jsonLD)
        }
    }

    static let offer = #"{"@context":"https://schema.org","@type":"Product","name":"KIVIK","offers":{"@type":"Offer","price":"449.00","priceCurrency":"EUR"}}"#

    static let cases: [Case] = [
        Case(name: "Product with one Offer", jsonLD: [offer], expected: "449 EUR"),
        Case(name: "numeric price", jsonLD: [#"{"@type":"Product","offers":{"@type":"Offer","price":1299,"priceCurrency":"USD"}}"#],
             expected: "1299 USD"),
        Case(name: "numeric decimal price keeps its digits",
             jsonLD: [#"{"@type":"Product","offers":{"price":449.99,"priceCurrency":"USD"}}"#], expected: "449.99 USD"),
        Case(name: "offers array with one Offer",
             jsonLD: [#"{"@type":"Product","offers":[{"@type":"Offer","price":"10.50","priceCurrency":"GBP"}]}"#],
             expected: "10.5 GBP"),
        Case(name: "several offers with the same price",
             jsonLD: [#"{"@type":"Product","offers":[{"price":"10","priceCurrency":"GBP"},{"price":"10.00","priceCurrency":"gbp"}]}"#],
             expected: "10 GBP"),
        Case(name: "several different prices", jsonLD: [#"{"@type":"Product","offers":[{"price":"10","priceCurrency":"GBP"},{"price":"12","priceCurrency":"GBP"}]}"#],
             expected: nil),
        Case(name: "AggregateOffer", jsonLD: [#"{"@type":"Product","offers":{"@type":"AggregateOffer","lowPrice":"10","highPrice":"20","priceCurrency":"USD"}}"#],
             expected: nil),
        Case(name: "range without a type", jsonLD: [#"{"@type":"Product","offers":{"lowPrice":"10","price":"10","priceCurrency":"USD"}}"#],
             expected: nil),
        Case(name: "price 0", jsonLD: [#"{"@type":"Product","offers":{"price":"0","priceCurrency":"USD"}}"#], expected: nil),
        Case(name: "negative price", jsonLD: [#"{"@type":"Product","offers":{"price":"-5","priceCurrency":"USD"}}"#], expected: nil),
        Case(name: "price not a number", jsonLD: [#"{"@type":"Product","offers":{"price":"Call us","priceCurrency":"USD"}}"#],
             expected: nil),
        Case(name: "price with a thousands comma", jsonLD: [#"{"@type":"Product","offers":{"price":"1,299.00","priceCurrency":"USD"}}"#],
             expected: nil),
        Case(name: "no currency", jsonLD: [#"{"@type":"Product","offers":{"price":"449"}}"#], expected: nil),
        Case(name: "boolean price", jsonLD: [#"{"@type":"Product","offers":{"price":true,"priceCurrency":"USD"}}"#], expected: nil),
        Case(name: "@graph", jsonLD: [#"{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"Product","offers":{"price":"79.95","priceCurrency":"EUR"}}]}"#],
             expected: "79.95 EUR"),
        Case(name: "top-level array", jsonLD: [#"[{"@type":"BreadcrumbList"},{"@type":"Product","offers":{"price":"5","priceCurrency":"CHF"}}]"#],
             expected: "5 CHF"),
        Case(name: "@type as an array", jsonLD: [#"{"@type":["Product","Thing"],"offers":{"price":"5","priceCurrency":"CHF"}}"#],
             expected: "5 CHF"),
        Case(name: "prefixed and full IRI types", jsonLD: [
            #"{"@type":"schema:Product","offers":{"price":"5","priceCurrency":"CHF"}}"#,
            #"{"@type":"https://schema.org/Product","offers":{"price":"5.00","priceCurrency":"CHF"}}"#,
        ], expected: "5 CHF"),
        Case(name: "nested in mainEntity", jsonLD: [#"{"@type":"ItemPage","mainEntity":{"@type":"Product","offers":{"price":"20","priceCurrency":"PLN"}}}"#],
             expected: "20 PLN"),
        Case(name: "priceSpecification", jsonLD: [#"{"@type":"Product","offers":{"@type":"Offer","priceSpecification":{"price":"99.90","priceCurrency":"EUR"}}}"#],
             expected: "99.9 EUR"),
        Case(name: "IKEA: current price next to a StrikethroughPrice",
             jsonLD: [#"{"@type":"Product","offers":{"@type":"Offer","priceSpecification":[{"@type":"UnitPriceSpecification","price":"49.99","priceCurrency":"EUR","validFrom":"2026-09-01Z"},{"@type":"UnitPriceSpecification","price":"59.99","priceCurrency":"EUR","priceType":"https://schema.org/StrikethroughPrice"}]}}"#],
             expected: "49.99 EUR"),
        Case(name: "two current prices in priceSpecification",
             jsonLD: [#"{"@type":"Product","offers":{"priceSpecification":[{"price":"10","priceCurrency":"EUR"},{"price":"12","priceCurrency":"EUR"}]}}"#],
             expected: nil),
        Case(name: "only reference prices in priceSpecification",
             jsonLD: [#"{"@type":"Product","offers":{"priceSpecification":[{"price":"10","priceCurrency":"EUR","priceType":"ListPrice"}]}}"#],
             expected: nil),
        Case(name: "related products of the product are not read",
             jsonLD: [#"{"@type":"Product","offers":{"price":"10","priceCurrency":"USD"},"isSimilarTo":[{"@type":"Product","offers":{"price":"99","priceCurrency":"USD"}}]}"#],
             expected: "10 USD"),
        Case(name: "two products on the page with different prices",
             jsonLD: [#"{"@type":"Product","offers":{"price":"10","priceCurrency":"USD"}}"#,
                      #"{"@type":"Product","offers":{"price":"20","priceCurrency":"USD"}}"#],
             expected: nil),
        Case(name: "broken JSON is skipped, the next block counts",
             jsonLD: ["{\"@type\":\"Product\",", offer], expected: "449 EUR"),
        Case(name: "JPY without fraction digits", jsonLD: [#"{"@type":"Product","offers":{"price":"12800","priceCurrency":"JPY"}}"#],
             expected: "12800 JPY"),
        Case(name: "JSON-LD wins over meta", jsonLD: [offer], productMeta: (["499.00"], ["USD"]), expected: "449 EUR"),
        Case(name: "ambiguous JSON-LD doesn't fall back to meta",
             jsonLD: [#"{"@type":"Product","offers":{"@type":"AggregateOffer","lowPrice":"10","highPrice":"20","priceCurrency":"USD"}}"#],
             productMeta: (["15"], ["USD"]), expected: nil),
        Case(name: "JSON-LD without a product: meta", jsonLD: [#"{"@type":"Organization","name":"IKEA"}"#],
             productMeta: (["499.00"], ["USD"]), expected: "499 USD"),
        Case(name: "product:price meta", productMeta: (["499.00"], ["usd"]), expected: "499 USD"),
        Case(name: "og:price meta when product:price is missing", ogMeta: (["35"], ["SEK"]), expected: "35 SEK"),
        Case(name: "product:price wins over og:price", productMeta: (["1"], ["SEK"]), ogMeta: (["2"], ["SEK"]), expected: "1 SEK"),
        Case(name: "product:price without currency: no price (og:price not asked)", productMeta: (["1"], []),
             ogMeta: (["2"], ["SEK"]), expected: nil),
        Case(name: "meta with two different amounts", productMeta: (["1", "2"], ["SEK"]), expected: nil),
        Case(name: "meta with two different currencies", productMeta: (["1"], ["SEK", "EUR"]), expected: nil),
        Case(name: "meta repeated with the same values", productMeta: (["1", "1"], ["SEK", "sek"]), expected: "1 SEK"),
        Case(name: "nothing on the page", expected: nil),
    ]

    @Test("SE-07 the page price: JSON-LD Product offers, else product:price, else og:price; ambiguous → none",
          arguments: cases)
    func pagePrice(_ testCase: Case) {
        let price = SharePrice.pagePrice(of: testCase.page)
        let text = price.map { "\($0.amount) \($0.currencyCode)" }
        #expect(text == testCase.expected)
    }

    @Test("SE-07 the suggestion: prefill in the list currency (rounded), a hint in another, nothing without a price",
          arguments: [
            ("449.004", "EUR", "EUR", "prefill 449"),
            ("449.005", "EUR", "eur", "prefill 449.01"),
            ("12800.5", "JPY", "JPY", "prefill 12801"),
            ("499", "USD", "EUR", "hint 499 USD"),
          ])
    func suggestion(amount: String, currency: String, listCurrency: String, expected: String) {
        let price = PagePrice(amount: dec(amount), currencyCode: currency)
        let text = switch SharePrice.suggestion(for: price, listCurrency: listCurrency) {
        case .none: "none"
        case .prefill(let value): "prefill \(value)"
        case .hint(let price): "hint \(price.amount) \(price.currencyCode)"
        }
        #expect(text == expected)
        #expect(SharePrice.suggestion(for: nil, listCurrency: listCurrency) == .none)
    }
}

// MARK: - Compose with a Safari page

/// Builds a composer on a Safari page.
@MainActor
enum ShareSafariFixture {
    static let link = "https://www.ikea.com/p/kivik?color=blue"

    static func page(price: String? = nil, currency: String = "EUR", image: Bool = false) -> SharePage {
        var page = SharePage(ogTitle: "KIVIK 3-seat sofa - IKEA")
        if let price {
            page.jsonLD = [#"{"@type":"Product","offers":{"price":"\#(price)","priceCurrency":"\#(currency)"}}"#]
        }
        if image { page.imageURL = URL(string: "https://www.ikea.com/images/kivik.jpg") }
        return page
    }

    static func model(_ fixture: StoreFixture, page: SharePage?, link: String = link, text: String? = nil,
                      mainCurrency: String = "EUR",
                      locale: String = "en_US", fetcher: (any LinkMetadataFetching)? = nil,
                      imageLoader: (any ShareImageLoading)? = nil,
                      defaults: UserDefaults = UserDefaults(suiteName: "ShareSafariTests.\(UUID().uuidString)")!)
        throws -> ShareComposerModel {
        guard case .link(let payload) = ShareInput.from(urls: [try #require(URL(string: link))],
                                                        texts: text.map { [$0] } ?? [], page: page) else {
            throw CancellationError()
        }
        return ShareComposerModel(payload: payload, store: fixture.store, shareDefaults: ShareDefaults(defaults: defaults),
                                  mainCurrencyCode: mainCurrency, titleFetcher: fetcher, imageLoader: imageLoader,
                                  locale: Locale(identifier: locale))
    }
}

@MainActor
@Suite("Share Extension: Safari compose", .tags(.shareExtension))
final class ShareSafariComposeTests {
    private let fixture: StoreFixture
    private let usd: ListModel
    private let eur: ListModel

    /// Home order: "Dollars" (pinned, USD, preselected), then "Euros" (EUR).
    init() throws {
        fixture = try StoreFixture(currency: "USD")
        eur = fixture.store.createList(name: "Euros", currencyCode: "EUR")
        usd = fixture.store.createList(name: "Dollars", isPinned: true, currencyCode: "USD")
    }

    private func model(_ page: SharePage?, mainCurrency: String = "EUR", locale: String = "en_US",
                       fetcher: (any LinkMetadataFetching)? = nil,
                       imageLoader: (any ShareImageLoading)? = nil) throws -> ShareComposerModel {
        try ShareSafariFixture.model(fixture, page: page, mainCurrency: mainCurrency, locale: locale,
                                     fetcher: fetcher, imageLoader: imageLoader)
    }

    @Test("SE-07 page price in another currency: empty field and the hint; the list in its currency: prefilled")
    func prefillFollowsTheList() throws {
        let composer = try model(ShareSafariFixture.page(price: "449.00", currency: "EUR"))
        #expect(composer.selectedList === usd)
        #expect(composer.priceText.isEmpty)
        #expect(composer.parsedPrice == .empty)
        #expect(composer.pagePriceHint?.plainSpaces == "Page price: €449.00" || !UILanguage.isEnglish)
        #expect(composer.pagePriceHint?.contains("€449.00") == true)

        composer.destination = .list(eur.uuid)
        #expect(composer.priceText == "449.00")
        #expect(composer.parsedPrice == .amount(dec("449")))
        #expect(composer.pagePriceHint == nil)

        composer.destination = .list(usd.uuid)
        #expect(composer.priceText.isEmpty, "back to a list in another currency: empty again")
    }

    @Test("SE-07 the prefill uses the device's decimal separator and the currency's digits")
    func prefillFormat() throws {
        let composer = try model(ShareSafariFixture.page(price: "449.5", currency: "EUR"), locale: "ru_RU")
        composer.destination = .list(eur.uuid)
        #expect(composer.priceText == "449,50")
        #expect(composer.parsedPrice == .amount(dec("449.5")))
    }

    @Test("SE-07 once the user typed a price, changing the list keeps it")
    func userPriceStays() throws {
        let composer = try model(ShareSafariFixture.page(price: "449.00", currency: "EUR"))
        composer.destination = .list(eur.uuid)
        composer.editPrice("399")
        composer.destination = .list(usd.uuid)
        #expect(composer.priceText == "399")
        composer.destination = .list(eur.uuid)
        #expect(composer.priceText == "399")
        #expect(composer.isPriceEdited)
    }

    @Test("SE-07 a new list uses the main currency for the rule")
    func newListUsesMainCurrency() throws {
        let composer = try model(ShareSafariFixture.page(price: "20", currency: "GBP"), mainCurrency: "GBP")
        #expect(composer.priceText.isEmpty)
        composer.destination = .newList
        #expect(composer.priceText == "20.00")
        let item = try #require(composer.save())
        #expect(item.price == dec("20"))
        #expect(item.group?.list?.currencyCode == "GBP")
    }

    @Test("SE-07 no price on the page: nothing prefilled, no hint")
    func noPagePrice() throws {
        let composer = try model(ShareSafariFixture.page())
        composer.destination = .list(eur.uuid)
        #expect(composer.pagePrice == nil)
        #expect(composer.priceText.isEmpty)
        #expect(composer.pagePriceHint == nil)
    }

    @Test("SE-09 the prefilled price is saved like a typed one")
    func savePrefilled() throws {
        let composer = try model(ShareSafariFixture.page(price: "449.00", currency: "USD"))
        let item = try #require(composer.save())
        #expect(item.price == dec("449"))
        #expect(item.linkTitle == "KIVIK 3-seat sofa")
    }

    @Test("B2 a Safari page with a title doesn't ask LinkPresentation")
    func noFetchWithSafariTitle() async throws {
        let counter = CountingFetcher()
        let composer = try model(ShareSafariFixture.page(), fetcher: counter)
        composer.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.calls == 0)
        #expect(composer.name == "KIVIK 3-seat sofa")
    }

    // MARK: Picture

    @Test("B3 the og:image is loaded at start; once here it is on the card and saved with linkFetchedAt (SE-09)")
    func pictureSaved() async throws {
        let loader = InstantImageLoader()
        let composer = try model(ShareSafariFixture.page(image: true), imageLoader: loader)
        #expect(composer.imageData == nil)
        composer.start()
        for _ in 0..<200 where composer.imageData == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(loader.requested == [URL(string: "https://www.ikea.com/images/kivik.jpg")!])
        let data = try #require(composer.imageData)
        let card = try #require(composer.cardImage)
        #expect(max(card.width, card.height) <= ShareComposerModel.cardImagePixelSize)

        fixture.clock.advance(by: 60)
        let item = try #require(composer.save())
        #expect(item.linkImageData == data)
        #expect(item.linkFetchedAt == fixture.clock.now)
    }

    @Test("SE-09 Save doesn't wait for the picture: without it both fields stay nil for the app (LP-01b)")
    func pictureNotReady() throws {
        let composer = try model(ShareSafariFixture.page(image: true), imageLoader: InstantImageLoader())
        // Not started: the picture never came.
        let item = try #require(composer.save())
        #expect(item.linkImageData == nil)
        #expect(item.linkFetchedAt == nil)
    }

    @Test("B3 no og:image (or not Safari): the loader is not asked; a failed load leaves the symbol")
    func noPicture() async throws {
        let loader = InstantImageLoader()
        let composer = try model(ShareSafariFixture.page(), imageLoader: loader)
        composer.start()
        composer.imageArrived(nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(loader.requested.isEmpty)
        #expect(composer.cardImage == nil)
    }

    // MARK: Duplicate

    @Test("SE-15 a link already in the selected list names its group; other lists don't; Save still adds a second one")
    func duplicateHint() throws {
        let living = fixture.store.createGroup(name: "Living room", in: usd)
        _ = try #require(fixture.store.addItem(name: "Sofa", to: living, urlString: ShareSafariFixture.link))
        _ = fixture.store.createGroup(name: "Other", in: eur)

        let composer = try model(ShareSafariFixture.page())
        #expect(composer.duplicateGroupName == "Living room")
        composer.destination = .list(eur.uuid)
        #expect(composer.duplicateGroupName == nil)
        composer.destination = .newList
        #expect(composer.duplicateGroupName == nil)
        composer.destination = .list(usd.uuid)
        #expect(composer.duplicateGroupName == "Living room")

        let before = try fixture.count(ItemModel.self)
        #expect(composer.canSave)
        _ = try #require(composer.save())
        #expect(try fixture.count(ItemModel.self) == before + 1)
    }

    @Test("SE-15 a different link (another variant) is no duplicate")
    func notADuplicate() throws {
        let group = fixture.store.createGroup(name: "Living room", in: usd)
        _ = try #require(fixture.store.addItem(name: "Sofa", to: group, urlString: "https://www.ikea.com/p/kivik?color=red"))
        let composer = try model(ShareSafariFixture.page())
        #expect(composer.duplicateGroupName == nil)
    }

    @Test("SE-15 (b) Allbirds: a tracking parameter in the shared link, the stored item has the canonical link")
    func duplicateByCanonical() throws {
        let group = fixture.store.createGroup(name: "Shoes", in: usd)
        let canonical = "https://www.allbirds.com/products/mens-wool-runner"
        _ = try #require(fixture.store.addItem(name: "Runner", to: group, urlString: canonical))
        let page = SharePage(ogTitle: "Wool Runner", canonicalURL: URL(string: canonical))
        let composer = try ShareSafariFixture.model(fixture, page: page,
                                                    link: canonical + "?_su_rec=DW1cJggm&_su_rec_id=efe2d6f0")
        #expect(composer.payload.duplicateCandidates == [canonical + "?_su_rec=DW1cJggm&_su_rec_id=efe2d6f0", canonical])
        #expect(composer.duplicateGroupName == "Shoes")
        composer.destination = .list(eur.uuid)
        #expect(composer.duplicateGroupName == nil, "only the selected list counts")
    }

    @Test("SE-15 (b) a canonical URL on a foreign host, or not http(s), is ignored", arguments: [
        "https://cdn.example.net/products/mens-wool-runner", "ftp://www.allbirds.com/products/mens-wool-runner",
    ])
    func foreignCanonicalIgnored(_ canonical: String) throws {
        let group = fixture.store.createGroup(name: "Shoes", in: usd)
        _ = try #require(fixture.store.addItem(name: "Runner", to: group, urlString: canonical))
        let page = SharePage(ogTitle: "Wool Runner", canonicalURL: URL(string: canonical))
        let composer = try ShareSafariFixture.model(fixture, page: page,
                                                    link: "https://www.allbirds.com/products/mens-wool-runner?_su_rec=x")
        #expect(composer.payload.duplicateCandidates == ["https://www.allbirds.com/products/mens-wool-runner?_su_rec=x"])
        #expect(composer.duplicateGroupName == nil)
    }

    @Test("SE-15 (b) a subdomain of the same shop counts; no canonical: only the shared link")
    func canonicalHostRules() throws {
        let shared = "https://m.ikea.com/de/p/kallax?utm_source=x"
        let sameShop = SharePage(canonicalURL: URL(string: "https://www.ikea.com/de/p/kallax"))
        guard case .link(let withCanonical) = ShareInput.from(urls: [URL(string: shared)!], texts: [], page: sameShop),
              case .link(let without) = ShareInput.from(urls: [URL(string: shared)!], texts: [], page: SharePage()),
              case .link(let notSafari) = ShareInput.from(urls: [URL(string: shared)!], texts: []) else {
            Issue.record("expected links"); return
        }
        #expect(withCanonical.duplicateCandidates == [shared, "https://www.ikea.com/de/p/kallax"])
        #expect(without.duplicateCandidates == [shared])
        #expect(notSafari.duplicateCandidates == [shared])
        #expect(ShareTitle.registrableDomain(of: "shop.amazon.co.uk") == "amazon.co.uk")
        #expect(ShareTitle.registrableDomain(of: "WWW.IKEA.COM") == "ikea.com")
    }

    @Test("SE-15 (d) stored and shared links are compared without tracking parameters", arguments: [
        // (stored link, shared link, hint expected)
        ("https://www.allbirds.com/products/runner?_su_rec=111&_su_rec_id=a",
         "https://www.allbirds.com/products/runner?_su_rec=222&_su_rec_id=b", true),
        ("https://shop.example.com/p/lamp?utm_source=newsletter&utm_medium=email",
         "https://shop.example.com/p/lamp?utm_campaign=bf&fbclid=XYZ", true),
        ("https://shop.example.com/p/lamp", "https://shop.example.com/p/lamp?gclid=1", true),
        ("https://shop.example.com/p/lamp?UTM_Source=x&Variant=7", "https://shop.example.com/p/lamp?Variant=7", true),
        ("https://shop.example.com/p/shirt?variant=1", "https://shop.example.com/p/shirt?variant=2", false),
        ("https://shop.example.com/p/shirt?variant=1&utm_source=x", "https://shop.example.com/p/shirt?utm_source=y&variant=2", false),
        ("https://shop.example.com/p/lamp-xl", "https://shop.example.com/p/lamp", false),
        ("https://shop.example.com/p/lamp", "https://shop.example.com/p/lamp", true),
    ])
    func duplicateWithoutTracking(stored: String, shared: String, expected: Bool) throws {
        let group = fixture.store.createGroup(name: "Shoes", in: usd)
        _ = try #require(fixture.store.addItem(name: "Stored", to: group, urlString: stored))
        let composer = try ShareSafariFixture.model(fixture, page: nil, link: shared)
        #expect((composer.duplicateGroupName == "Shoes") == expected)
        #expect(fixture.store.lists(pinned: true).first?.sortedGroups.first?.sortedItems.first?.urlString == stored,
                "the stored link is never rewritten (SE-09)")
    }

    // MARK: Retry

    @Test("A retry after a failed Save reuses the list and group it created, renamed to the current name")
    func retryReusesTheNewList() throws {
        let composer = try model(ShareSafariFixture.page())
        composer.destination = .newList
        let lists = try fixture.count(ListModel.self)
        let groups = try fixture.count(GroupModel.self)
        let first = composer.resolveDestination()
        composer.newListName = "Sofa ideas"
        let second = composer.resolveDestination()
        #expect(first.list === second.list)
        #expect(first.group === second.group)
        #expect(second.list.name == "Sofa ideas")
        #expect(try fixture.count(ListModel.self) == lists + 1)
        #expect(try fixture.count(GroupModel.self) == groups + 1)
    }
}

// MARK: - Thumbnail from a file

@Suite("Share Extension: picture from a file", .tags(.shareExtension))
struct ShareThumbnailFileTests {
    private func writeJPEG(width: Int, height: Int, quality: Double = 0.95) throws -> URL {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        // Noise-like stripes so the JPEG is big, like a product photo.
        for x in stride(from: 0, to: width, by: 3) {
            context.setFillColor(CGColor(red: Double(x % 255) / 255, green: Double((x * 7) % 255) / 255,
                                         blue: Double((x * 13) % 255) / 255, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 3, height: height))
        }
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test("SE-13 a 4000×3000 photo becomes ≤ 800 px and ≤ 200 KB, read straight from the file")
    func bigPhoto() throws {
        let url = try writeJPEG(width: 4000, height: 3000)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(LinkThumbnail.jpegData(fromFileAt: url))
        #expect(data.count <= LinkThumbnail.maxByteCount)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) <= LinkThumbnail.maxPixelSize)
    }

    @Test("SE-13 a file over the limit, an empty file or a non-image gives no picture")
    func rejected() throws {
        let photo = try writeJPEG(width: 400, height: 300)
        defer { try? FileManager.default.removeItem(at: photo) }
        #expect(LinkThumbnail.jpegData(fromFileAt: photo, maxSourceByteCount: 10) == nil)

        let text = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).txt")
        try Data("<html>not an image</html>".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        #expect(LinkThumbnail.jpegData(fromFileAt: text) == nil)

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(LinkThumbnail.jpegData(fromFileAt: empty) == nil)
        #expect(LinkThumbnail.jpegData(fromFileAt: URL(fileURLWithPath: "/nonexistent/x.jpg")) == nil)
    }
}

// MARK: - Fakes

/// Counts fetches; never answers with a title.
private final class CountingFetcher: LinkMetadataFetching {
    private let count = Mutex(0)
    var calls: Int { count.withLock { $0 } }

    func fetch(_ url: URL) async throws -> LinkPreview {
        count.withLock { $0 += 1 }
        throw LinkPreviewError.networkDisabled
    }
}

/// Answers at once with the stub picture and remembers what was asked.
private final class InstantImageLoader: ShareImageLoading {
    private let urls = Mutex<[URL]>([])
    var requested: [URL] { urls.withLock { $0 } }

    func thumbnail(for url: URL) async -> Data? {
        urls.withLock { $0.append(url) }
        return StubLinkMetadataFetcher.sampleImageData().flatMap(LinkThumbnail.jpegData(from:))
    }
}
