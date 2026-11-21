//
//  ItemLinkDisplay.swift
//  Project2
//
//  What the Link section of item details shows (spec 06 A.2, LP-05): the preview card
//  describes the *saved* link, so it is shown only while the field still holds that link.
//  Plain values, so the rules are unit-tested without a view.
//

import CoreGraphics
import Foundation

enum ItemLinkDisplay: Equatable {
    /// The field is empty: no card, no caption.
    case empty
    /// Text that isn't a web link: "Not a web link" under the field, no Open button.
    case invalid
    /// A web link that differs from the saved one: no card (it would describe the old link).
    case unsaved
    /// The saved link without a preview (loading or failed): the compact "🔗 host" row.
    case compact
    /// The saved link with its preview: the card.
    case card

    /// - Parameters:
    ///   - fieldText: the text in the link field (the draft).
    ///   - savedText: the item's stored `urlString`.
    ///   - hasPreview: the item has a fetched preview (`linkFetchedAt != nil`).
    static func make(fieldText: String, savedText: String, hasPreview: Bool) -> ItemLinkDisplay {
        if fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        guard ItemLink.url(from: fieldText) != nil else { return .invalid }
        // Compared normalized: "ikea.com" typed and "https://ikea.com" stored are the same link.
        guard ItemLink.normalized(fieldText) == ItemLink.normalized(savedText) else { return .unsaved }
        return hasPreview ? .card : .compact
    }

    /// The card (or compact row) is shown.
    var showsPreview: Bool {
        self == .card || self == .compact
    }
}

/// Sizes of the link card (spec 06 A.2).
enum LinkCardMetrics {
    /// og:image proportions: the picture is 1.91 times wider than high.
    static let heroAspectRatio: CGFloat = 1.91
    /// The picture is never higher than this, also in a wide iPad form sheet.
    static let heroMaxHeight: CGFloat = 180
    /// Corner radius of the picture.
    static let heroCornerRadius: CGFloat = 12
    /// The square tile with the link symbol of a preview without a picture.
    static let tileSide: CGFloat = 64
    static let tileCornerRadius: CGFloat = 10

    /// Height of the picture for a card `width` points wide.
    static func heroHeight(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(width / heroAspectRatio, heroMaxHeight)
    }
}
