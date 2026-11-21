//
//  LinkPreviewCoreTests.swift
//  Project2Tests
//
//  Spec 06 Part A, PR 1: the link preview core without UI and without network —
//  URL normalization (LP-06), the ImageIO thumbnail (LP-04), the store's cache rules
//  (LP-07 Remove, LP-10, LP-12), the UI test stub and the fetcher choice (LP-13).
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Project2

@Suite("Link preview core", .tags(.linkPreview))
@MainActor
struct LinkPreviewCoreTests {

    // MARK: - LP-06 normalization

    @Test("LP-06 a web address is stored with its scheme; other text only trimmed",
          arguments: [
            ("ikea.com/sofa", "https://ikea.com/sofa"),
            ("  https://www.ikea.com  ", "https://www.ikea.com"),
            ("http://shop.example.org/a?b=1", "http://shop.example.org/a?b=1"),
            ("  shop  ", "shop"),
            ("ftp://shop.com", "ftp://shop.com"),
            ("mailto:a@b.com", "mailto:a@b.com"),
            ("https://", "https://"),
            ("   ", ""),
          ] as [(String, String)])
    func normalized(text: String, expected: String) {
        #expect(ItemLink.normalized(text) == expected)
    }

    @Test("LP-06 inline add stores the normalized link")
    func addItemNormalizes() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = try #require(fixture.store.addItem(name: "Sofa", to: group, urlString: " ikea.com/sofa "))
        #expect(item.urlString == "https://ikea.com/sofa")
        let other = try #require(fixture.store.addItem(name: "Note", to: group, urlString: " shop "))
        #expect(other.urlString == "shop")
    }

    // MARK: - LP-10 cache reset on ✓

    @Test("LP-10 another link on ✓ clears all link fields")
    func changedLinkClearsCache() throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com/sofa")

        var draft = ItemDraft(item: item)
        draft.urlString = "ikea.com/lamp"
        fixture.store.updateItem(item, with: draft)

        #expect(item.urlString == "https://ikea.com/lamp")
        expectNoCache(item)
    }

    @Test("LP-10 the same link (spaces, missing scheme) keeps the cache",
          arguments: ["https://ikea.com/sofa", "  https://ikea.com/sofa ", "ikea.com/sofa"])
    func sameLinkKeepsCache(text: String) throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com/sofa")

        var draft = ItemDraft(item: item)
        draft.urlString = text
        draft.notes = "changed"
        fixture.store.updateItem(item, with: draft)

        #expect(item.linkFetchedAt != nil)
        #expect(item.linkTitle == "Sofa page")
    }

    @Test("LP-10 a link saved before M5 as typed counts as the same link")
    func legacyLinkKeepsCache() throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com")
        item.urlString = "ikea.com" // how pre-M5 builds stored it

        var draft = ItemDraft(item: item)
        draft.name = "Sofa 2"
        fixture.store.updateItem(item, with: draft)

        #expect(item.urlString == "https://ikea.com")
        #expect(item.linkFetchedAt != nil)
    }

    @Test("LP-07 Remove + ✓ clears the link and all four link fields")
    func removeLinkClearsCache() throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com/sofa")

        var draft = ItemDraft(item: item)
        draft.urlString = ""
        fixture.store.updateItem(item, with: draft)

        #expect(item.urlString.isEmpty)
        expectNoCache(item)
        #expect(!fixture.context.hasChanges, "saved")
    }

    // MARK: - applyLinkPreview / clearLinkPreview

    @Test("applyLinkPreview stores the title, the host of the user's link, the image and the time")
    func applyPreview() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = try #require(fixture.store.addItem(name: "Sofa", to: group, urlString: "www.ikea.com/sofa"))

        fixture.store.applyLinkPreview(LinkPreview(title: "  KIVIK sofa \n", imageData: Data([1, 2])), to: item)

        #expect(item.linkTitle == "KIVIK sofa")
        #expect(item.linkHost == "ikea.com")
        #expect(item.linkImageData == Data([1, 2]))
        #expect(item.linkFetchedAt == fixture.clock.now)
        #expect(!fixture.context.hasChanges, "saved")
    }

    @Test("A blank title is stored as nil, a long one is cut to 300 characters")
    func storedTitle() {
        #expect(LinkPreview.storedTitle(nil) == nil)
        #expect(LinkPreview.storedTitle("  \n ") == nil)
        let long = String(repeating: "a", count: 500)
        #expect(LinkPreview.storedTitle(long)?.count == LinkPreview.maxTitleLength)
    }

    @Test("clearLinkPreview forgets the preview but keeps the link")
    func clearPreview() throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com/sofa")

        fixture.store.clearLinkPreview(of: item)

        #expect(item.urlString == "https://ikea.com/sofa")
        expectNoCache(item)
        #expect(!fixture.context.hasChanges, "saved")
    }

    @Test("item(withID:) finds an item and gives nil once it is deleted")
    func itemByID() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Sofa", to: group)
        let id = item.uuid
        #expect(fixture.store.item(withID: id) === item)
        fixture.store.deleteItem(item)
        #expect(fixture.store.item(withID: id) == nil)
    }

    // MARK: - LP-12 duplicate / undo keep the cache

    @Test("LP-12 Duplicate and Undo of a delete keep the preview")
    func duplicateAndRestoreKeepCache() throws {
        let fixture = try StoreFixture()
        let item = try makeCachedItem(fixture, url: "https://ikea.com/sofa")
        let list = try #require(item.parentList)

        let copy = try #require(fixture.store.duplicateItem(item))
        #expect(copy.linkTitle == "Sofa page")
        #expect(copy.linkImageData == item.linkImageData)
        #expect(copy.linkFetchedAt == item.linkFetchedAt)

        let snapshot = ItemSnapshot(item)
        fixture.store.deleteItem(item)
        let restored = try #require(fixture.store.restoreItem(snapshot, in: list))
        #expect(restored.linkTitle == "Sofa page")
        #expect(restored.linkHost == "ikea.com")
        #expect(restored.linkFetchedAt != nil)
    }

    // MARK: - LP-04 thumbnail

    @Test("LP-04 a 4000×3000 photo becomes a JPEG ≤ 200 KB, ≤ 800 px on the long side")
    func thumbnailOfLargePhoto() throws {
        let source = try #require(Self.photoLikeJPEG(width: 4000, height: 3000))
        let jpeg = try #require(LinkThumbnail.jpegData(from: source))

        #expect(jpeg.count <= LinkThumbnail.maxByteCount)
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(max(size.width, size.height) <= LinkThumbnail.maxPixelSize)
        #expect(size.width == 800 && size.height == 600, "keeps the aspect ratio")
        #expect(Self.typeIdentifier(of: jpeg) == UTType.jpeg.identifier)
    }

    @Test("LP-04 a heavy noisy image (several MB) still fits 200 KB")
    func thumbnailOfNoise() throws {
        let source = try #require(Self.noiseImage(width: 2400, height: 1800))
        #expect(source.count > 2_000_000, "a heavy source")
        let jpeg = try #require(LinkThumbnail.jpegData(from: source))

        #expect(jpeg.count <= LinkThumbnail.maxByteCount)
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(max(size.width, size.height) <= LinkThumbnail.maxPixelSize)
    }

    @Test("LP-04 a small image is not scaled up")
    func thumbnailOfSmallImage() throws {
        let png = try #require(StubLinkMetadataFetcher.sampleImageData())
        let jpeg = try #require(LinkThumbnail.jpegData(from: png))
        let size = try #require(Self.pixelSize(of: jpeg))
        #expect(size.width == 8 && size.height == 8)
    }

    @Test("LP-04 broken, empty or too big data gives no image")
    func thumbnailOfBadData() {
        #expect(LinkThumbnail.jpegData(from: Data()) == nil)
        #expect(LinkThumbnail.jpegData(from: Data("not an image".utf8)) == nil)
        #expect(LinkThumbnail.jpegData(from: Data(count: LinkThumbnail.maxSourceByteCount + 1)) == nil)
    }

    // MARK: - Stub fetcher (spec 06 A.5)

    @Test("Stub: any host → \"Preview: <host>\" with an 8×8 image")
    func stubDefault() async throws {
        let preview = try await StubLinkMetadataFetcher().fetch(try #require(URL(string: "https://kites.example.com/a")))
        #expect(preview.title == "Preview: kites.example.com")
        let image = try #require(preview.imageData)
        #expect(Self.pixelSize(of: image).map { $0.width == 8 && $0.height == 8 } == true)
    }

    @Test("Stub: noimage.example.com → title without an image")
    func stubNoImage() async throws {
        let preview = try await StubLinkMetadataFetcher().fetch(try #require(URL(string: "https://noimage.example.com")))
        #expect(preview.title == "Preview: noimage.example.com")
        #expect(preview.imageData == nil)
    }

    @Test("Stub: fail.example.com → error at once")
    func stubFail() async throws {
        let url = try #require(URL(string: "https://fail.example.com/x"))
        await #expect(throws: LinkPreviewError.stubFailure) {
            try await StubLinkMetadataFetcher().fetch(url)
        }
    }

    @Test("Stub: slow.example.com answers after about 2 s")
    func stubSlow() async throws {
        let url = try #require(URL(string: "https://slow.example.com"))
        let clock = ContinuousClock()
        let start = clock.now
        let preview = try await StubLinkMetadataFetcher().fetch(url)
        #expect(clock.now - start >= .seconds(2))
        #expect(preview.title == "Preview: slow.example.com")
    }

    @Test("LP-13 the no-network fetcher always fails")
    func noNetworkFails() async throws {
        let url = try #require(URL(string: "https://ikea.com"))
        await #expect(throws: LinkPreviewError.networkDisabled) {
            try await NoNetworkLinkMetadataFetcher().fetch(url)
        }
    }

    // MARK: - LP-13 fetcher choice

    @Test("LP-13 -UITests never uses the network; the stub only on request; a test host has no network",
          arguments: [
            (["app", "-UITests"], [:], LinkFetcherKind.noNetwork),
            (["app", "-UITests", "-UITestsLinkPreview", "stub"], [:], .stub),
            (["app", "-UITests", "-UITestsLinkPreview", "other"], [:], .noNetwork),
            (["app", "-UITests", "-UITestsLinkPreview"], [:], .noNetwork),
            (["app", "-UITestsLinkPreview", "stub"], [:], .live),
            (["app"], ["XCTestConfigurationFilePath": "/x.xctestconfiguration"], .noNetwork),
            (["app"], [:], .live),
          ] as [([String], [String: String], LinkFetcherKind)])
    func fetcherChoice(arguments: [String], environment: [String: String], expected: LinkFetcherKind) {
        #expect(LinkFetcherKind.forLaunch(arguments: arguments, environment: environment) == expected)
    }

    @Test("LP-13 this unit test host itself gets no network")
    func currentHostHasNoNetwork() {
        #expect(LinkFetcherKind.current == .noNetwork)
        #expect(LinkFetcherKind.current.makeFetcher() is NoNetworkLinkMetadataFetcher)
    }

    // MARK: - Helpers

    private func makeCachedItem(_ fixture: StoreFixture, url: String) throws -> ItemModel {
        let (_, group) = fixture.makeGroup()
        let item = try #require(fixture.store.addItem(name: "Sofa", to: group, urlString: url))
        fixture.store.applyLinkPreview(LinkPreview(title: "Sofa page", imageData: Data([7])), to: item)
        try #require(item.linkFetchedAt != nil)
        return item
    }

    private func expectNoCache(_ item: ItemModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(item.linkTitle == nil, sourceLocation: sourceLocation)
        #expect(item.linkHost == nil, sourceLocation: sourceLocation)
        #expect(item.linkImageData == nil, sourceLocation: sourceLocation)
        #expect(item.linkFetchedAt == nil, sourceLocation: sourceLocation)
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private static func typeIdentifier(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    /// Random colored ellipses on a gradient: compresses like a product photo.
    private static func photoLikeJPEG(width: Int, height: Int) -> Data? {
        guard let context = makeContext(width: width, height: height) else { return nil }
        var random = SeededGenerator(seed: 4000)
        for _ in 0..<400 {
            context.setFillColor(CGColor(red: .random(in: 0...1, using: &random),
                                         green: .random(in: 0...1, using: &random),
                                         blue: .random(in: 0...1, using: &random), alpha: 1))
            let side = CGFloat.random(in: 50...900, using: &random)
            let x = CGFloat.random(in: 0...CGFloat(width), using: &random)
            let y = CGFloat.random(in: 0...CGFloat(height), using: &random)
            context.fillEllipse(in: CGRect(x: x, y: y, width: side, height: side * 0.8))
        }
        return context.makeImage().flatMap { encode($0, type: .jpeg, quality: 1) }
    }

    /// Every pixel random: the worst case for JPEG.
    private static func noiseImage(width: Int, height: Int) -> Data? {
        guard let context = makeContext(width: width, height: height),
              let buffer = context.data else { return nil }
        var random = SeededGenerator(seed: 10)
        let words = context.bytesPerRow * height / 8
        let pointer = buffer.bindMemory(to: UInt64.self, capacity: words)
        for index in 0..<words {
            pointer[index] = random.next()
        }
        return context.makeImage().flatMap { encode($0, type: .jpeg, quality: 0.95) }
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    private static func encode(_ image: CGImage, type: UTType, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
