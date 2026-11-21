//
//  LinkTileTests.swift
//  Project2Tests
//
//  Spec 06 Part A, PR 4: the picture of the link tile in a list row (A.1 p.7, LP-19) —
//  decoded at the tile's pixel size, never the stored 800 px picture, and cached by
//  item + preview date + size, so a refreshed preview or the larger AX tile decode again.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Project2

@Suite("Link tile", .tags(.linkPreview))
struct LinkTileTests {

    /// A `width`×`height` JPEG of one color.
    private static func jpeg(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("LP-19 the tile picture is decoded at the tile's size, not 800 px")
    func decodesAtTileSize() throws {
        let data = try Self.jpeg(width: 800, height: 600)
        let image = try #require(LinkThumbnail.displayImage(from: data, maxPixelSize: 132))
        #expect(max(image.width, image.height) == 132)
        #expect(image.width > image.height, "proportions are kept")
    }

    @Test("A small picture is never scaled up")
    func neverUpscales() throws {
        let data = try Self.jpeg(width: 8, height: 8)
        let image = try #require(LinkThumbnail.displayImage(from: data, maxPixelSize: 132))
        #expect(image.width == 8)
    }

    @Test("Data that isn't a picture gives no tile picture", arguments: [Data(), Data("not an image".utf8)])
    func brokenData(data: Data) {
        #expect(LinkThumbnail.displayImage(from: data, maxPixelSize: 132) == nil)
    }

    @Test("The cache answers a decoded picture again without decoding")
    func cachesByKey() async throws {
        let cache = LinkTileImageCache()
        let key = LinkTileImageCache.Key(itemID: UUID(), fetchedAt: .now, pixelSize: 132)
        #expect(cache.image(for: key) == nil)
        let image = try #require(await cache.image(for: key, decoding: Self.jpeg(width: 800, height: 600)))
        #expect(cache.image(for: key) === image)
        // Already cached: even broken data now returns the cached picture.
        #expect(await cache.image(for: key, decoding: Data()) === image)
    }

    @Test("A refreshed preview or another tile size is a new picture")
    func keyHoldsDateAndSize() async throws {
        let cache = LinkTileImageCache()
        let id = UUID()
        let fetchedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let key = LinkTileImageCache.Key(itemID: id, fetchedAt: fetchedAt, pixelSize: 132)
        _ = await cache.image(for: key, decoding: try Self.jpeg(width: 800, height: 600))
        #expect(cache.image(for: key) != nil)
        #expect(cache.image(for: .init(itemID: id, fetchedAt: fetchedAt.addingTimeInterval(1), pixelSize: 132)) == nil)
        #expect(cache.image(for: .init(itemID: id, fetchedAt: fetchedAt, pixelSize: 168)) == nil)
        #expect(cache.image(for: .init(itemID: UUID(), fetchedAt: fetchedAt, pixelSize: 132)) == nil)
    }

    @Test("Broken data isn't cached")
    func brokenDataNotCached() async {
        let cache = LinkTileImageCache()
        let key = LinkTileImageCache.Key(itemID: UUID(), fetchedAt: .now, pixelSize: 132)
        #expect(await cache.image(for: key, decoding: Data("x".utf8)) == nil)
        #expect(cache.image(for: key) == nil)
    }

    @Test("The tile starts 8 pt after the checkbox (LP-16) and is 44 pt, 56 pt at AX sizes")
    func gridConstants() {
        #expect(ListRowGrid.spacing + ListRowGrid.linkTileLeadingInset == ListRowGrid.linkTileGap)
        #expect(ListRowGrid.linkTileGap >= 8)
        #expect(ListRowGrid.linkTileSide == ListRowGrid.iconColumnWidth)
        #expect(ListRowGrid.linkTileAccessibilitySide == 56)
    }
}
