//
//  LinkPreviewService.swift
//  Project2
//
//  Fills the link preview cache of items (spec 06 A.1 p.3, LP-01...LP-03, LP-11).
//  Views only say "this item may need a preview" (saved, details opened, row shown);
//  the service decides whether to fetch:
//  - only items with a valid link and no preview yet (`linkFetchedAt == nil`), so a
//    cached preview never touches the network (LP-03);
//  - one fetch per item at a time; a new link replaces (cancels) the old fetch;
//  - at most 2 fetches at once, the rest wait in order (LP-01b);
//  - a failed item + link is retried automatically once per launch (LP-01a);
//  - an answer is dropped when the item was deleted or got another link meanwhile (LP-11).
//
//  Main actor: it reads models and writes through `PlannerStore`. The fetch itself
//  runs off the main actor inside the fetcher; only its `Sendable` result comes back.
//

import Foundation

@MainActor
@Observable
final class LinkPreviewService {
    /// Fetches running at the same time (LP-01b).
    static let maxConcurrentFetches = 2
    /// Automatic fetches of one item + link per launch: the first and one retry (LP-01a).
    static let maxAutomaticAttempts = 2

    /// One fetch: the item and the normalized link it is for.
    struct Request: Hashable, Sendable {
        let itemID: UUID
        let url: URL
    }

    private struct Running {
        let request: Request
        /// Tells this fetch's answer from that of a fetch it replaced.
        let token: UUID
        let task: Task<Void, Never>
    }

    /// Fetches in progress by item. Observed, so a view can show "loading" (spec 06 A.2).
    private var running: [UUID: Running] = [:]
    @ObservationIgnored private var waiting: [Request] = []
    /// Failed automatic fetches per item + link, for this launch only (LP-01a).
    @ObservationIgnored private var failures: [Request: Int] = [:]

    @ObservationIgnored private let fetcher: any LinkMetadataFetching
    @ObservationIgnored private let store: PlannerStore

    init(fetcher: any LinkMetadataFetching, store: PlannerStore) {
        self.fetcher = fetcher
        self.store = store
    }

    /// The preview of this item is being fetched right now.
    func isFetching(_ itemID: UUID) -> Bool {
        running[itemID] != nil
    }

    /// Fetches or waits to fetch something (for tests: "wait until idle").
    var hasWork: Bool {
        !running.isEmpty || !waiting.isEmpty
    }

    /// Starts (or queues) a fetch when the item has a valid link, no preview yet,
    /// and fewer than `maxAutomaticAttempts` failures for that link in this launch.
    /// Cheap to call often: from a row's `onAppear`, opening details, saving.
    func fetchIfNeeded(for item: ItemModel) {
        guard let request = request(for: item) else { return }
        guard failures[request, default: 0] < Self.maxAutomaticAttempts else { return }

        if let current = running[request.itemID] {
            if current.request == request { return } // already fetching this link
            // The link changed: the old answer is useless.
            current.task.cancel()
            running[request.itemID] = nil
        }
        if let index = waiting.firstIndex(where: { $0.itemID == request.itemID }) {
            if waiting[index] == request { return }
            waiting.remove(at: index)
        }
        waiting.append(request)
        startWaiting()
    }

    // MARK: - Queue

    /// What a fetch for the item would be, or `nil` when it needs none.
    private func request(for item: ItemModel) -> Request? {
        guard item.linkFetchedAt == nil, let url = ItemLink.url(from: item.urlString) else { return nil }
        return Request(itemID: item.uuid, url: url)
    }

    private func startWaiting() {
        while running.count < Self.maxConcurrentFetches, !waiting.isEmpty {
            let request = waiting.removeFirst()
            // It may have waited a while: skip it if the item is gone or no longer needs it.
            guard let item = store.item(withID: request.itemID),
                  self.request(for: item) == request,
                  running[request.itemID] == nil else { continue }
            start(request)
        }
    }

    private func start(_ request: Request) {
        let token = UUID()
        let fetcher = fetcher
        // Inherits the main actor; `fetcher.fetch` itself runs off it.
        let task = Task { [weak self] in
            let preview: LinkPreview?
            do {
                preview = try await fetcher.fetch(request.url)
            } catch {
                preview = nil
            }
            self?.finish(request, token: token, preview: preview)
        }
        running[request.itemID] = Running(request: request, token: token, task: task)
    }

    private func finish(_ request: Request, token: UUID, preview: LinkPreview?) {
        // Replaced by a fetch for a newer link: that one owns the item now.
        guard running[request.itemID]?.token == token else { return }
        running[request.itemID] = nil
        defer { startWaiting() }

        // LP-11: deleted, or the link changed while fetching → drop the answer.
        guard let item = store.item(withID: request.itemID),
              ItemLink.url(from: item.urlString) == request.url else { return }

        if let preview {
            failures[request] = nil
            store.applyLinkPreview(preview, to: item)
        } else {
            failures[request, default: 0] += 1
        }
    }
}
