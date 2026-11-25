//
//  SharePayload.swift
//  Project2
//
//  What the Share Extension received (spec 06 Part B, SE-01a, SE-02): one web link and,
//  sometimes, a short text from the sharing app. Pure values and rules, shared by the
//  extension and the app (in-app composer for UI tests, unit tests).
//
//  From Safari it also carries what the JavaScript preprocessing collected (`SharePage`).
//

import Foundation

/// A link that can become an item.
struct SharePayload: Equatable, Sendable {
    /// The link as shared, normalized (`ItemLink.normalized`): this is what the item stores.
    let url: URL
    /// Text the sharing app sent next to the link (often the page or product title),
    /// trimmed and at most `maxAppTextLength`; `nil` when there was none or it was the link itself.
    let appText: String?
    /// What Safari's preprocessing script found on the page; `nil` from other apps (B2).
    let page: SharePage?

    init(url: URL, appText: String?, page: SharePage? = nil) {
        self.url = url
        self.appText = appText
        self.page = page
    }

    /// Longer texts are a description or a message, not a name (B.2).
    static let maxAppTextLength = 150

    /// The address stored in `urlString`.
    var urlString: String { url.absoluteString }

    /// "ikea.com": shown on the card and the last-resort name.
    var host: String {
        ItemLink.displayHost(of: urlString) ?? url.host() ?? urlString
    }
}

/// What the extension shows for an input.
enum ShareInput: Equatable, Sendable {
    /// A web link: the compose screen.
    case link(SharePayload)
    /// Not a web link (`mailto:`, `file://`, no host): "This link can't be added" (B.2).
    case unsupported

    /// Reads the attachments of the share request (SE-01a).
    /// - Parameters:
    ///   - urls: `public.url` items, in the order they came. The activation rule allows only
    ///     one web URL, but a file URL can still come along; the first web link wins.
    ///   - texts: `public.plain-text` items. A text is a name candidate only when it is
    ///     not a link and not longer than `SharePayload.maxAppTextLength`.
    ///   - page: Safari's preprocessing result. Its `document.URL` is the link only when
    ///     the request has no `public.url` (the shared link wins, SE-09).
    static func from(urls: [URL], texts: [String], page: SharePage? = nil) -> ShareInput {
        let candidates = urls + [page?.url].compactMap { $0 }
        guard let shared = candidates.lazy.compactMap({ ItemLink.url(from: $0.absoluteString) }).first,
              let url = URL(string: ItemLink.normalized(shared.absoluteString)) else {
            return .unsupported
        }
        let appText = texts.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { text in
                !text.isEmpty && text.count <= SharePayload.maxAppTextLength
                    && ItemLink.url(from: text) == nil
                    && !text.contains(url.absoluteString)
            }
        return .link(SharePayload(url: url, appText: appText, page: page))
    }
}

/// Cleans a page title into an item name (SE-02).
enum ShareTitle {
    /// The longest name the extension suggests.
    static let maxLength = 150

    /// Separators sites put between the product and the site name.
    private static let separators = [" - ", " – ", " — ", " | ", " · ", ": "]

    /// Trims, joins lines and repeated spaces, drops a site name prefix or suffix that matches
    /// the domain label ("KIVIK sofa - IKEA" + ikea.com → "KIVIK sofa";
    /// "Amazon.com: AirPods Pro" + amazon.com → "AirPods Pro"), and keeps at most 150 characters.
    /// `nil` when nothing is left: the caller falls back to the host.
    static func clean(_ raw: String?, host: String) -> String? {
        guard let raw else { return nil }
        var title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !title.isEmpty else { return nil }

        let site = siteLabel(of: host)
        if !site.isEmpty {
            for separator in separators {
                // Suffix: "Product - IKEA".
                if let range = title.range(of: separator, options: .backwards),
                   matchesSite(title[range.upperBound...], site: site) {
                    let rest = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { title = rest; break }
                }
                // Prefix: "Amazon.com: Product".
                if let range = title.range(of: separator),
                   matchesSite(title[..<range.lowerBound], site: site) {
                    let rest = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { title = rest; break }
                }
            }
        }
        let limited = String(title.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }

    /// "www.ikea.com" → "ikea", "amazon.co.uk" → "amazon", "m.ozon.ru" → "ozon".
    static func siteLabel(of host: String) -> String {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return labels.first ?? "" }
        // Second-level public suffixes like co.uk, com.au: the label before them.
        let secondLevel: Set<String> = ["co", "com", "net", "org", "gov", "ac", "edu"]
        if labels.count >= 3, secondLevel.contains(labels[labels.count - 2]) {
            return labels[labels.count - 3]
        }
        return labels[labels.count - 2]
    }

    /// "IKEA", "Amazon.com", "ikea.com" match the label "ikea"/"amazon"; "Shop" does not.
    private static func matchesSite(_ part: Substring, site: String) -> Bool {
        let words = part.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return false }
        let stripped = words.hasPrefix("www.") ? String(words.dropFirst(4)) : words
        return stripped == site || stripped.hasPrefix(site + ".")
    }
}
