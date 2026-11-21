//
//  LinkPreviewServiceTests.swift
//  Project2Tests
//
//  Spec 06 Part A, PR 2: when `LinkPreviewService` fetches and what it does with the
//  answer — LP-01 (one fetch after save), LP-01a (one retry per launch), LP-01b (at most
//  2 at once), LP-03 (no fetch with a cache), LP-11 (stale answers dropped). A counting
//  fake fetcher stands in for the network; it can hold answers back until released.
//

import Foundation
import Testing
@testable import Project2

@Suite("Link preview service", .tags(.linkPreview))
@MainActor
struct LinkPreviewServiceTests {

    @Test("LP-01 an item with a link gets one fetch, and the preview is stored")
    func fetchesOnce() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher()
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "www.ikea.com/sofa")

        service.fetchIfNeeded(for: item)
        #expect(service.isFetching(item.uuid))
        try await waitUntilIdle(service)

        #expect(await fetcher.callCount == 1)
        #expect(item.linkTitle == "Title of www.ikea.com")
        #expect(item.linkHost == "ikea.com")
        #expect(item.linkImageData == FakeLinkFetcher.imageData)
        #expect(item.linkFetchedAt == fixture.clock.now)
        #expect(!service.isFetching(item.uuid))

        // A shown row or opened details later: the cache is there, no new fetch (LP-03).
        service.fetchIfNeeded(for: item)
        try await waitUntilIdle(service)
        #expect(await fetcher.callCount == 1)
    }

    @Test("LP-03 no fetch for a cached item, no link, or a text that isn't a web link")
    func noFetchWithoutNeed() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher()
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let cached = try addItem(fixture, url: "https://ikea.com")
        fixture.store.applyLinkPreview(LinkPreview(title: "IKEA", imageData: nil), to: cached)
        let noLink = try addItem(fixture, url: "")
        let notWeb = try addItem(fixture, url: "mailto:a@b.com")

        for item in [cached, noLink, notWeb] {
            service.fetchIfNeeded(for: item)
        }
        #expect(!service.hasWork)
        // Negative check: a slower machine only gives a wrong extra fetch more time to show
        // up, so it can't make a correct service fail; it can only miss a bug, never invent one.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fetcher.callCount == 0)
    }

    @Test("LP-01 save, details and row together start one fetch for an item, not three")
    func deduplicates() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://ikea.com/sofa")

        service.fetchIfNeeded(for: item)
        service.fetchIfNeeded(for: item)
        await wait(for: fetcher, .held(1))
        service.fetchIfNeeded(for: item)
        // Negative check: a slower machine only gives a wrong extra fetch more time to show
        // up, so it can't make a correct service fail; it can only miss a bug, never invent one.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fetcher.callCount == 1)

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(await fetcher.callCount == 1)
        #expect(item.linkFetchedAt != nil)
    }

    @Test("LP-01b at most 2 fetches run at once; the rest wait their turn")
    func limitsConcurrency() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let items = try ["a", "b", "c", "d"].map { try addItem(fixture, url: "https://\($0).example.com") }

        for item in items {
            service.fetchIfNeeded(for: item)
        }
        await wait(for: fetcher, .held(2))
        // Negative check: a slower machine only gives a wrong extra fetch more time to show
        // up, so it can't make a correct service fail; it can only miss a bug, never invent one.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fetcher.callCount == 2)
        #expect(await fetcher.maxHeldAtOnce == 2)

        await fetcher.releaseOne()
        await wait(for: fetcher, .calls(3))
        #expect(await fetcher.heldCount == 2)

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(await fetcher.callCount == 4)
        #expect(await fetcher.maxHeldAtOnce == 2)
        #expect(items.allSatisfy { $0.linkFetchedAt != nil })
    }

    @Test("LP-01a a failed link is retried once per launch, then left alone; no cache is written")
    func retriesOnce() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(failingHosts: ["fail.example.com"])
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://fail.example.com/x")

        for _ in 0..<4 {
            service.fetchIfNeeded(for: item)
            try await waitUntilIdle(service)
        }
        #expect(await fetcher.callCount == LinkPreviewService.maxAutomaticAttempts)
        #expect(item.linkFetchedAt == nil)
        #expect(item.linkTitle == nil)

        // Another link of the same item is a new pair: it gets its own attempts.
        var draft = ItemDraft(item: item)
        draft.urlString = "https://ok.example.com"
        fixture.store.updateItem(item, with: draft)
        service.fetchIfNeeded(for: item)
        try await waitUntilIdle(service)
        #expect(await fetcher.callCount == LinkPreviewService.maxAutomaticAttempts + 1)
        #expect(item.linkTitle == "Title of ok.example.com")
    }

    @Test("LP-11 an answer for a link changed meanwhile is dropped")
    func dropsStaleAnswer() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://old.example.com")

        service.fetchIfNeeded(for: item)
        await wait(for: fetcher, .held(1))
        var draft = ItemDraft(item: item)
        draft.urlString = "https://new.example.com"
        fixture.store.updateItem(item, with: draft)

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(item.urlString == "https://new.example.com")
        #expect(item.linkTitle == nil)
        #expect(item.linkFetchedAt == nil)
    }

    @Test("LP-11 a new link replaces the running fetch; only the new answer is stored")
    func newLinkReplacesFetch() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://old.example.com")

        service.fetchIfNeeded(for: item)
        await wait(for: fetcher, .held(1))
        var draft = ItemDraft(item: item)
        draft.urlString = "https://new.example.com"
        fixture.store.updateItem(item, with: draft)
        service.fetchIfNeeded(for: item) // ✓ in item details
        await wait(for: fetcher, .calls(2))

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(item.linkTitle == "Title of new.example.com")
        #expect(await fetcher.requestedHosts == ["old.example.com", "new.example.com"])
    }

    @Test("LP-11 an answer for an item deleted meanwhile changes nothing and doesn't crash")
    func dropsAnswerForDeletedItem() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://ikea.com")
        let other = try addItem(fixture, url: "https://other.example.com")

        service.fetchIfNeeded(for: item)
        await wait(for: fetcher, .held(1))
        fixture.store.deleteItem(item)

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(try fixture.count(ItemModel.self) == 1)
        #expect(other.linkFetchedAt == nil, "the answer didn't land on another item")
    }

    @Test("LP-11 a waiting item deleted before its turn is never fetched")
    func skipsDeletedWaitingItem() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher(holdsAnswers: true)
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let items = try ["a", "b", "c"].map { try addItem(fixture, url: "https://\($0).example.com") }

        for item in items {
            service.fetchIfNeeded(for: item)
        }
        await wait(for: fetcher, .held(2))
        fixture.store.deleteItem(items[2])

        await fetcher.releaseAll()
        try await waitUntilIdle(service)
        #expect(await fetcher.requestedHosts == ["a.example.com", "b.example.com"])
    }

    @Test("LP-12 a duplicate of a cached item needs no fetch")
    func duplicateNeedsNoFetch() async throws {
        let fixture = try StoreFixture()
        let fetcher = FakeLinkFetcher()
        let service = LinkPreviewService(fetcher: fetcher, store: fixture.store)
        let item = try addItem(fixture, url: "https://ikea.com")
        fixture.store.applyLinkPreview(LinkPreview(title: "IKEA", imageData: nil), to: item)

        let copy = try #require(fixture.store.duplicateItem(item))
        service.fetchIfNeeded(for: copy)
        #expect(!service.hasWork)
        #expect(await fetcher.callCount == 0)
    }

    // MARK: - Helpers

    private func addItem(_ fixture: StoreFixture, url: String) throws -> ItemModel {
        let group = fixture.store.lists(pinned: false).first?.sortedGroups.first
            ?? fixture.makeGroup().1
        return try #require(fixture.store.addItem(name: "Item", to: group, urlString: url))
    }

    /// A failure guard only, never a pacing tool: a passing wait returns the moment its
    /// condition holds, so a long guard costs nothing. It is long because CI runs ~400
    /// tests in parallel on a slow runner and this main-actor suite can stall for seconds
    /// while the service itself is fine (a 5 s deadline used to flake there).
    private static let waitGuard: Duration = .seconds(60)

    /// Suspends until the fetcher reaches `condition` (no polling); fails the test only
    /// if that doesn't happen within `waitGuard`.
    private func wait(for fetcher: FakeLinkFetcher, _ condition: FakeLinkFetcher.Condition,
                      sourceLocation: SourceLocation = #_sourceLocation) async {
        let timeout = Task {
            try await Task.sleep(for: Self.waitGuard)
            await fetcher.expireWaiters()
        }
        let met = await fetcher.waitFor(condition)
        timeout.cancel()
        if !met {
            Issue.record("Timed out waiting for the fetcher to reach \(condition)",
                         sourceLocation: sourceLocation)
        }
    }

    /// `LinkPreviewService` has no completion signal (and app code stays as is), so this
    /// one polls; the guard is generous for the same reason as `waitGuard`.
    private func waitUntilIdle(_ service: LinkPreviewService,
                               sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await waitUntil(sourceLocation: sourceLocation) { !service.hasWork }
    }

    /// Polls `condition` every 10 ms; fails the test after `timeout`.
    private func waitUntil(timeout: Duration = LinkPreviewServiceTests.waitGuard,
                           sourceLocation: SourceLocation = #_sourceLocation,
                           _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Counts calls and, with `holdsAnswers`, keeps each answer until the test releases it.
private actor FakeLinkFetcher: LinkMetadataFetching {
    static let imageData = Data([0xFF, 0xD8, 0xFF])

    private(set) var requestedHosts: [String] = []
    private(set) var maxHeldAtOnce = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holdsAnswers: Bool
    private let failingHosts: Set<String>

    init(holdsAnswers: Bool = false, failingHosts: Set<String> = []) {
        self.holdsAnswers = holdsAnswers
        self.failingHosts = failingHosts
    }

    var callCount: Int { requestedHosts.count }
    var heldCount: Int { held.count }

    func fetch(_ url: URL) async throws -> LinkPreview {
        let host = url.host() ?? ""
        requestedHosts.append(host)
        resumeMetWaiters()
        if holdsAnswers {
            await withCheckedContinuation { continuation in
                held.append(continuation)
                maxHeldAtOnce = max(maxHeldAtOnce, held.count)
                resumeMetWaiters()
            }
        }
        if failingHosts.contains(host) {
            throw LinkPreviewError.stubFailure
        }
        return LinkPreview(title: "Title of \(host)", imageData: Self.imageData)
    }

    // MARK: Waiting for the fake's state (event-driven, see `wait(for:_:)` in the suite)

    enum Condition: Sendable, CustomStringConvertible {
        /// At least this many answers are held back right now.
        case held(Int)
        /// At least this many fetches were requested in total.
        case calls(Int)

        var description: String {
            switch self {
            case .held(let count): "\(count) held answer(s)"
            case .calls(let count): "\(count) fetch call(s)"
            }
        }
    }

    private var waiters: [(condition: Condition, continuation: CheckedContinuation<Bool, Never>)] = []

    private func isMet(_ condition: Condition) -> Bool {
        switch condition {
        case .held(let count): held.count >= count
        case .calls(let count): callCount >= count
        }
    }

    /// Returns `true` as soon as `condition` holds, or `false` when `expireWaiters()`
    /// gives up on it first.
    func waitFor(_ condition: Condition) async -> Bool {
        if isMet(condition) { return true }
        return await withCheckedContinuation { continuation in
            waiters.append((condition, continuation))
        }
    }

    /// The test's timeout guard: wakes every waiter with "not met".
    func expireWaiters() {
        let expired = waiters
        waiters = []
        for waiter in expired {
            waiter.continuation.resume(returning: false)
        }
    }

    /// Called after every change of `requestedHosts` or `held`.
    private func resumeMetWaiters() {
        let met = waiters.filter { isMet($0.condition) }
        waiters.removeAll { isMet($0.condition) }
        for waiter in met {
            waiter.continuation.resume(returning: true)
        }
    }

    // MARK: Releasing held answers

    func releaseOne() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume()
    }

    /// Lets every held and every later call answer at once.
    func releaseAll() {
        holdsAnswers = false
        let continuations = held
        held = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}
