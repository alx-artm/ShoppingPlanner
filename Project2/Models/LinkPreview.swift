//
//  LinkPreview.swift
//  Project2
//
//  What a page tells about itself for the link preview (spec 06 A.1): a title
//  and a small image. A plain `Sendable` value, so it can come back from the
//  fetcher's background work to the main actor, where `PlannerStore` stores it.
//

import Foundation

struct LinkPreview: Equatable, Sendable {
    /// The page title as the site gives it; cleaned by `storedTitle(_:)` before saving.
    var title: String?
    /// JPEG from `LinkThumbnail` (≤ 800 px, ≤ 200 KB), or `nil` when the page has no image.
    var imageData: Data?

    /// Longest title kept in the model (spec 06 A.1 p.4).
    static let maxTitleLength = 300

    /// The title saved in `linkTitle`: trimmed, `nil` when blank, at most 300 characters.
    static func storedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTitleLength))
    }
}

/// Why a preview fetch gave nothing. Never shown to the user (spec 06 D5).
enum LinkPreviewError: Error, Equatable {
    /// `-UITests` without the stub, or a unit test host: no network for previews (LP-13).
    case networkDisabled
    /// The stub's `fail.example.com`.
    case stubFailure
}
