//
//  LinkTileImageCache.swift
//  Project2
//
//  The pictures of the link tiles in list rows (spec 06 A.1 p.7, LP-19). A row never decodes
//  in `body`: its tile asks this cache, and on a miss decodes the stored JPEG off the main
//  actor, at the tile's pixel size, once. Scrolling back to a row takes the picture from
//  memory. The key holds `linkFetchedAt`, so a refreshed preview gets a new picture, and the
//  pixel size, so the larger AX tile doesn't show a blurry small one.
//

import Foundation
import UIKit

final class LinkTileImageCache: Sendable {
    /// What one tile picture is decoded for.
    struct Key: Hashable, Sendable {
        let itemID: UUID
        let fetchedAt: Date
        let pixelSize: Int

        fileprivate var cacheKey: NSString {
            "\(itemID.uuidString)|\(fetchedAt.timeIntervalSinceReferenceDate)|\(pixelSize)" as NSString
        }
    }

    /// The one cache of the app's rows. Not main-actor isolated: tiles decode off the main actor.
    static let shared = LinkTileImageCache()

    /// `NSCache` is thread-safe (documented) but not marked `Sendable`; it evicts under memory pressure.
    private nonisolated(unsafe) let cache = NSCache<NSString, UIImage>()

    init(countLimit: Int = 400) {
        cache.countLimit = countLimit
    }

    /// The picture already decoded for `key`; a dictionary lookup, cheap enough for `body`.
    func image(for key: Key) -> UIImage? {
        cache.object(forKey: key.cacheKey)
    }

    /// The cached picture, or `data` decoded for `key` off the main actor and cached.
    /// `nil` for data that isn't an image.
    @concurrent
    func image(for key: Key, decoding data: Data) async -> UIImage? {
        if let cached = image(for: key) { return cached }
        guard let decoded = LinkThumbnail.displayImage(from: data, maxPixelSize: key.pixelSize) else { return nil }
        let image = UIImage(cgImage: decoded)
        cache.setObject(image, forKey: key.cacheKey)
        return image
    }
}
