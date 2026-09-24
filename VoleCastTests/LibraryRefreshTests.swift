import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Its own container per test: refreshing asks the store for every
/// subscription, so another suite's shows would be swept in too.
@Suite(.serialized)
@MainActor
struct LibraryRefreshTests {

    /// Serves `feed-minimal` for any URL, and records what it was asked for.
    private struct StubLoader: FeedLoading {
        let failing: Set<String>
        let seen: Mutex<[String]>
        let fixture: String

        init(
            failing: Set<String> = [],
            seen: Mutex<[String]> = Mutex([]),
            fixture: String = "feed-minimal"
        ) {
            self.failing = failing
            self.seen = seen
            self.fixture = fixture
        }

        func load(_ url: URL, revalidating: Bool) async throws -> LoadedFeed {
            seen.withLock { $0.append(url.absoluteString) }
            if failing.contains(url.host() ?? "") { throw NetworkError.offline }
            return LoadedFeed(
                feed: try FeedParser.parse(try Fixtures.feed(fixture)),
                resolvedURL: url
            )
        }
    }

    @discardableResult
    private func subscribe(_ context: ModelContext, host: String, refreshedAt: Date?) throws -> Podcast {
        let podcast = try Subscriptions.subscribe(
            to: LoadedFeed(
                feed: try FeedParser.parse(try Fixtures.feed("feed-minimal")),
                resolvedURL: try #require(URL(string: "https://\(host)/feed"))
            ),
            in: context
        )
        podcast.lastRefreshedAt = refreshedAt
        return podcast
    }

    /// Fetching a feed and doing nothing with it looks identical from the
    /// outside — the earlier tests here checked only what was asked for, and a
    /// version that threw every result away passed all of them.
    @Test func appliesWhatItFetched() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let podcast = try subscribe(context, host: "applied.example.com", refreshedAt: nil)
        podcast.title = "Stale Title"
        for episode in podcast.episodes ?? [] { episode.title = "Stale Episode" }

        let refresher = LibraryRefresh(feedLoader: StubLoader(), context: context)
        await refresher.refreshAll(force: true)

        #expect(podcast.title == "Minimal Show")
        #expect(podcast.orderedEpisodes.allSatisfy { $0.title != "Stale Episode" })
    }

    /// A feed that has gained an episode must put it in the store, which is the
    /// entire point of the Latest list refreshing.
    @Test func bringsInEpisodesThatAreNew() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let podcast = try subscribe(context, host: "new.example.com", refreshedAt: nil)
        let before = podcast.episodeCount

        let refresher = LibraryRefresh(
            feedLoader: StubLoader(fixture: "feed-itunes-full"),
            context: context
        )
        await refresher.refreshAll(force: true)

        #expect(podcast.episodeCount > before)
    }

    @Test func refreshesEverySubscription() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "a.example.com", refreshedAt: nil)
        try subscribe(context, host: "b.example.com", refreshedAt: nil)
        let seen = Mutex<[String]>([])
        let refresher = LibraryRefresh(feedLoader: StubLoader(seen: seen), context: context)

        await refresher.refreshAll(force: true)

        #expect(seen.current.count == 2)
        #expect(seen.current.contains { $0.contains("a.example.com") })
        #expect(seen.current.contains { $0.contains("b.example.com") })
    }

    /// Opening Latest shouldn't hammer every feed. Anything refreshed recently
    /// is left alone unless the refresh was asked for explicitly.
    @Test func skipsShowsRefreshedRecentlyUnlessForced() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "fresh.example.com", refreshedAt: .now)
        try subscribe(
            context,
            host: "stale.example.com",
            refreshedAt: Date.now.addingTimeInterval(-LibraryRefresh.staleAfter - 60)
        )
        let seen = Mutex<[String]>([])
        let refresher = LibraryRefresh(feedLoader: StubLoader(seen: seen), context: context)

        await refresher.refreshAll(force: false)

        #expect(seen.current.count == 1)
        #expect(seen.current.first?.contains("stale.example.com") == true)
    }

    @Test func forcingRefreshesEvenSomethingJustChecked() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "fresh.example.com", refreshedAt: .now)
        let seen = Mutex<[String]>([])
        let refresher = LibraryRefresh(feedLoader: StubLoader(seen: seen), context: context)

        await refresher.refreshAll(force: true)

        #expect(seen.current.count == 1)
    }

    /// One dead feed must not cost you the others.
    @Test func oneFailingShowDoesNotStopTheRest() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "good.example.com", refreshedAt: nil)
        let broken = try subscribe(context, host: "broken.example.com", refreshedAt: nil)
        let refresher = LibraryRefresh(
            feedLoader: StubLoader(failing: ["broken.example.com"]),
            context: context
        )

        await refresher.refreshAll(force: true)

        #expect(refresher.failureCount == 1)
        // The one that worked was still applied.
        #expect(Subscriptions.existing(identity: "good.example.com/feed", in: context)?.lastRefreshedAt != nil)
        #expect(broken.title == "Minimal Show")
    }

    @Test func reportsNoFailureWhenEverythingWorks() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "c.example.com", refreshedAt: nil)
        let refresher = LibraryRefresh(feedLoader: StubLoader(), context: context)

        await refresher.refreshAll(force: true)

        #expect(refresher.failureCount == 0)
    }

    /// A failure that is fixed shouldn't keep being reported.
    @Test func clearsAnEarlierFailureOnASuccessfulRefresh() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "flaky.example.com", refreshedAt: nil)
        let failing = LibraryRefresh(
            feedLoader: StubLoader(failing: ["flaky.example.com"]),
            context: context
        )
        await failing.refreshAll(force: true)
        #expect(failing.failureCount == 1)

        let working = LibraryRefresh(feedLoader: StubLoader(), context: context)
        await working.refreshAll(force: true)

        #expect(working.failureCount == 0)
    }

    @Test func doesNothingWithNoSubscriptions() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let seen = Mutex<[String]>([])
        let refresher = LibraryRefresh(feedLoader: StubLoader(seen: seen), context: context)

        await refresher.refreshAll(force: true)

        #expect(seen.current.isEmpty)
        #expect(!refresher.isRefreshing)
    }

    @Test func isNotRefreshingOnceItHasFinished() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        try subscribe(context, host: "d.example.com", refreshedAt: nil)
        let refresher = LibraryRefresh(feedLoader: StubLoader(), context: context)

        await refresher.refreshAll(force: true)

        #expect(!refresher.isRefreshing)
    }
}
