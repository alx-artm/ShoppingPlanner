//
//  ShareImageLoader.swift
//  Project2
//
//  The page picture in the Share Extension (spec 06 B3 = A, B.4 p.6, SE-13): Safari's
//  og:image is downloaded into a file (never into one `Data`), at most 10 MB and 3 seconds,
//  then shrunk by `LinkThumbnail` straight from the file with ImageIO. A share extension is
//  killed at about 120 MB; `UIImage(data:)` on a 4000×3000 photo alone is ~48 MB decoded.
//

import Foundation
import Synchronization

/// Loads the picture of a page for the compose card and `linkImageData`.
protocol ShareImageLoading: Sendable {
    /// A JPEG of at most 800 px / 200 KB (`LinkThumbnail`), or `nil`: too big, too slow,
    /// not an image, offline, or cancelled. Never throws: no picture is not an error (D5).
    func thumbnail(for url: URL) async -> Data?
}

/// The real loader: `URLSession` download task into a temporary file.
struct ShareImageDownloader: ShareImageLoading {
    /// Larger downloads are cancelled, by `Content-Length` or by the bytes received (SE-13).
    static let maxByteCount: Int64 = 10 * 1024 * 1024
    /// The whole download, from the request to the last byte (SE-13).
    static let timeBudget: TimeInterval = 3

    var maxByteCount = Self.maxByteCount
    var timeBudget = Self.timeBudget

    @concurrent
    func thumbnail(for url: URL) async -> Data? {
        guard let file = await download(url) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard !Task.isCancelled else { return nil }
        return LinkThumbnail.jpegData(fromFileAt: file, maxSourceByteCount: Int(maxByteCount))
    }

    /// The downloaded file (the caller deletes it), or `nil`.
    private func download(_ url: URL) async -> URL? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeBudget
        configuration.timeoutIntervalForRequest = timeBudget
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        let delegate = DownloadDelegate(maxByteCount: maxByteCount)
        // The session keeps its delegate until it is invalidated.
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: url)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// Watches one download: cancels it past the size limit and keeps the finished file.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private struct State {
        var continuation: CheckedContinuation<URL?, Never>?
        var file: URL?
    }

    private let maxByteCount: Int64
    private let state = Mutex(State())

    init(maxByteCount: Int64) {
        self.maxByteCount = maxByteCount
    }

    func start(_ continuation: CheckedContinuation<URL?, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maxByteCount || totalBytesExpectedToWrite > maxByteCount {
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this method returns: move it first.
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-image-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            state.withLock { $0.file = file }
        } catch {
            return
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, file) = state.withLock { state in
            defer { state.continuation = nil }
            return (state.continuation, state.file)
        }
        if error != nil, let file {
            try? FileManager.default.removeItem(at: file)
            continuation?.resume(returning: nil)
        } else {
            continuation?.resume(returning: error == nil ? file : nil)
        }
    }
}

// MARK: - Tests

/// `-UITestsShareComposer safari…`: an 8×8 picture at once, without the network.
struct StubShareImageLoader: ShareImageLoading {
    func thumbnail(for url: URL) async -> Data? {
        StubLinkMetadataFetcher.sampleImageData().flatMap(LinkThumbnail.jpegData(from:))
    }
}
