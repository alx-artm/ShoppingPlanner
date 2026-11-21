//
//  LinkMetadataFetching.swift
//  Project2
//
//  Where a link preview comes from (spec 06 A.1, A.5). The protocol is the seam for
//  tests: the app uses LinkPresentation, UI tests use a deterministic stub or no
//  network at all (LP-13), unit tests use their own counting fake.
//
//  Every implementation is `nonisolated` and runs its work off the main actor
//  (`@concurrent`). It returns a `Sendable` `LinkPreview`, never `LPLinkMetadata`
//  or `NSItemProvider`, which are not `Sendable`. Only `PlannerStore` (main actor)
//  writes the result into SwiftData.
//

import CoreGraphics
import Foundation
import ImageIO
import LinkPresentation
import UniformTypeIdentifiers

protocol LinkMetadataFetching: Sendable {
    /// The title and a shrunk image of the page. Throws when there is nothing to show.
    func fetch(_ url: URL) async throws -> LinkPreview
}

// MARK: - LinkPresentation

/// The real fetcher. A new `LPMetadataProvider` for every request: it is a one-shot
/// object, and starting it twice throws an Objective-C exception (spec 06 A.1 p.1).
struct LPLinkMetadataFetcher: LinkMetadataFetching {
    /// Shop pages are heavy; 10 s was too short, the system default 30 s too long (A.1 p.1).
    static let timeout: TimeInterval = 15

    @concurrent
    func fetch(_ url: URL) async throws -> LinkPreview {
        // Not `Sendable`, but only touched by this call and its cancel handler;
        // `cancel()` is meant to be called while a fetch runs.
        nonisolated(unsafe) let provider = LPMetadataProvider()
        provider.timeout = Self.timeout
        let metadata = try await withTaskCancellationHandler {
            try await provider.startFetchingMetadata(for: url)
        } onCancel: {
            provider.cancel()
        }
        try Task.checkCancellation()

        let title = metadata.title
        // The page image, else its icon (favicon); none → placeholder in the UI.
        var imageData: Data?
        if let imageProvider = metadata.imageProvider ?? metadata.iconProvider {
            imageData = try? await Self.loadImageData(from: imageProvider)
        }
        try Task.checkCancellation()
        // Shrunk here, still off the main actor (LP-04).
        let thumbnail = imageData.flatMap(LinkThumbnail.jpegData(from:))
        return LinkPreview(title: title, imageData: thumbnail)
    }

    private static func loadImageData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}

// MARK: - UI tests

/// `-UITestsLinkPreview stub`: answers by host, without the network (spec 06 A.5).
struct StubLinkMetadataFetcher: LinkMetadataFetching {
    static let failHost = "fail.example.com"
    static let slowHost = "slow.example.com"
    static let noImageHost = "noimage.example.com"
    /// How long `slow.example.com` takes, so a UI test can see the "loading" state.
    static let slowDelay: Duration = .seconds(2)

    @concurrent
    func fetch(_ url: URL) async throws -> LinkPreview {
        let host = url.host()?.lowercased() ?? ""
        switch host {
        case Self.failHost:
            throw LinkPreviewError.stubFailure
        case Self.slowHost:
            try await Task.sleep(for: Self.slowDelay)
            return LinkPreview(title: Self.title(for: host), imageData: Self.sampleImageData())
        case Self.noImageHost:
            return LinkPreview(title: Self.title(for: host), imageData: nil)
        default:
            return LinkPreview(title: Self.title(for: host), imageData: Self.sampleImageData())
        }
    }

    /// "Preview: kites.example.com".
    static func title(for host: String) -> String {
        "Preview: \(host)"
    }

    /// An 8×8 PNG of one color, made on the fly.
    static func sampleImageData() -> Data? {
        let side = 8
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// `-UITests` without the stub, and the unit test host: every fetch fails at once,
/// so tests never touch the network (LP-13).
struct NoNetworkLinkMetadataFetcher: LinkMetadataFetching {
    func fetch(_ url: URL) async throws -> LinkPreview {
        throw LinkPreviewError.networkDisabled
    }
}

// MARK: - Choice at launch

/// Which fetcher this process uses (spec 06 A.5, LP-13).
enum LinkFetcherKind: Equatable, Sendable {
    case live, stub, noNetwork

    /// - `-UITests -UITestsLinkPreview stub` → stub;
    /// - `-UITests` otherwise, or a unit test host (`XCTestConfigurationFilePath`) → no network;
    /// - a normal launch → LinkPresentation.
    static func forLaunch(arguments: [String], environment: [String: String]) -> LinkFetcherKind {
        if arguments.contains(LaunchConfiguration.uiTestsArgument) {
            if let index = arguments.firstIndex(of: LaunchConfiguration.uiTestsLinkPreviewArgument),
               arguments.indices.contains(index + 1),
               arguments[index + 1] == LaunchConfiguration.uiTestsLinkPreviewStubValue {
                return .stub
            }
            return .noNetwork
        }
        if environment["XCTestConfigurationFilePath"] != nil {
            return .noNetwork
        }
        return .live
    }

    static var current: LinkFetcherKind {
        let process = ProcessInfo.processInfo
        return forLaunch(arguments: process.arguments, environment: process.environment)
    }

    func makeFetcher() -> any LinkMetadataFetching {
        switch self {
        case .live: LPLinkMetadataFetcher()
        case .stub: StubLinkMetadataFetcher()
        case .noNetwork: NoNetworkLinkMetadataFetcher()
        }
    }
}
