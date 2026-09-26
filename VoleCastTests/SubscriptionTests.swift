import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Serialized and sharing one in-memory container, per `TestContainer`. Each
/// test uses its own feed URLs so the shared store can't leak between them.
@Suite(.serialized)
@MainActor
struct SubscriptionTests {

    private func context() -> ModelContext { ModelContext(TestContainer.shared) }

    private func loaded(
        _ fixture: String = "feed-minimal",
        at url: String
    ) throws -> LoadedFeed {
        LoadedFeed(
            feed: try FeedParser.parse(try Fixtures.feed(fixture)),
            resolvedURL: try #require(FeedURL.normalize(url))
        )
    }

    @Test func subscribingStoresTheShowAndItsEpisodes() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://one.example.com/feed"),
            in: context
        )

        #expect(podcast.title == "Minimal Show")
        #expect(podcast.feedIdentity == "one.example.com/feed")
        #expect(podcast.episodeCount == 2)
        #expect(podcast.orderedEpisodes.first?.title == "Episode Two")
        #expect(podcast.lastEpisodeAt == Date(timeIntervalSince1970: 1_756_796_400))
        #expect(podcast.lastRefreshedAt != nil)
    }

    @Test func aDirectoryResultFillsGapsTheFeedLeaves() throws {
        let context = context()
        let result = PodcastSearchResult(
            id: "itunes:1",
            title: "Directory Title",
            author: "Directory Author",
            feedURL: URL(string: "https://two.example.com/feed")!,
            artworkURL: URL(string: "https://cdn.example.com/itunes.jpg"),
            episodeCount: 2,
            genres: ["Technology"],
            itunesCollectionID: 1
        )
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://two.example.com/feed"),
            directoryResult: result,
            in: context
        )

        // The feed is the authority on its own title...
        #expect(podcast.title == "Minimal Show")
        // ...but it has no author, so the directory's fills in.
        #expect(podcast.author == "Directory Author")
        #expect(podcast.artworkURL == "https://cdn.example.com/itunes.jpg")
        #expect(podcast.itunesCollectionID == 1)
    }

    @Test func subscribingTwiceThroughEquivalentURLsIsRefused() throws {
        let context = context()
        try Subscriptions.subscribe(to: try loaded(at: "http://www.three.example.com/feed/"), in: context)

        #expect(throws: SubscriptionError.alreadySubscribed) {
            try Subscriptions.subscribe(
                to: try loaded(at: "https://three.example.com/feed"),
                in: context
            )
        }
    }

    @Test func differentShowsCoexist() throws {
        let context = context()
        try Subscriptions.subscribe(to: try loaded(at: "https://four.example.com/a"), in: context)
        try Subscriptions.subscribe(to: try loaded(at: "https://four.example.com/b"), in: context)

        #expect(Subscriptions.existing(identity: "four.example.com/a", in: context) != nil)
        #expect(Subscriptions.existing(identity: "four.example.com/b", in: context) != nil)
    }

    @Test func refreshUpdatesEpisodesInPlaceAndAppendsNewOnes() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://five.example.com/feed"),
            in: context
        )
        let originalIDs = Set(podcast.orderedEpisodes.map(\.persistentModelID))

        var feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))
        feed.episodes[0].title = "Episode Two (remastered)"
        feed.episodes.insert(
            ParsedEpisode(
                guid: "episode-3",
                title: "Episode Three",
                publishedAt: Date(timeIntervalSince1970: 1_756_882_800),
                audioURL: "https://cdn.example.com/3.mp3"
            ),
            at: 0
        )
        Subscriptions.refresh(
            LoadedFeed(feed: feed, resolvedURL: URL(string: "https://five.example.com/feed")!),
            into: podcast,
            in: context
        )

        #expect(podcast.episodeCount == 3)
        #expect(podcast.orderedEpisodes.first?.title == "Episode Three")
        // Same rows, edited — not duplicates keyed on a changed title.
        #expect(originalIDs.isSubset(of: Set(podcast.orderedEpisodes.map(\.persistentModelID))))
        #expect(podcast.orderedEpisodes.contains { $0.title == "Episode Two (remastered)" })
    }

    /// A refresh used to reassign all nine fields of every episode whether or
    /// not anything had changed, dirtying them all and re-running every query
    /// watching them. With the Latest list driven by one of those queries, an
    /// unchanged feed cost a full re-render for nothing.
    @Test func refreshingAnUnchangedFeedLeavesItsEpisodesAlone() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://nine.example.com/feed"),
            in: context
        )
        try context.save()

        let feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))
        Subscriptions.refresh(
            LoadedFeed(feed: feed, resolvedURL: URL(string: "https://nine.example.com/feed")!),
            into: podcast,
            in: context
        )

        let dirtied = context.changedModelsArray.compactMap { $0 as? Episode }
        #expect(dirtied.isEmpty)
    }

    /// The other half: skipping unchanged writes must not skip real ones.
    @Test func refreshingStillWritesAFieldThatActuallyChanged() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://ten.example.com/feed"),
            in: context
        )
        try context.save()

        var feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))
        feed.episodes[0].summary = "Rewritten show notes"
        Subscriptions.refresh(
            LoadedFeed(feed: feed, resolvedURL: URL(string: "https://ten.example.com/feed")!),
            into: podcast,
            in: context
        )

        #expect(podcast.orderedEpisodes.contains { $0.summary == "Rewritten show notes" })
        let dirtied = context.changedModelsArray.compactMap { $0 as? Episode }
        #expect(dirtied.count == 1)
    }

    @Test func refreshKeepsEpisodesThatFellOffTheFeed() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://six.example.com/feed"),
            in: context
        )

        var feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))
        feed.episodes.removeLast()
        Subscriptions.refresh(
            LoadedFeed(feed: feed, resolvedURL: URL(string: "https://six.example.com/feed")!),
            into: podcast,
            in: context
        )

        // Dropping them would one day throw away playback state.
        #expect(podcast.episodeCount == 2)
    }

    @Test func aMovedFeedKeepsItsSubscription() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://seven.example.com/feed"),
            in: context
        )

        let feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))
        Subscriptions.refresh(
            LoadedFeed(feed: feed, resolvedURL: URL(string: "https://newhost.example.net/rss")!),
            into: podcast,
            in: context
        )

        #expect(podcast.feedURL == "https://newhost.example.net/rss")
        #expect(podcast.feedIdentity == "newhost.example.net/rss")
        #expect(Subscriptions.existing(identity: "newhost.example.net/rss", in: context) != nil)
    }

    @Test func unsubscribingTakesTheEpisodesWithIt() throws {
        let context = context()
        let podcast = try Subscriptions.subscribe(
            to: try loaded(at: "https://eight.example.com/feed"),
            in: context
        )
        let guids = Set(podcast.orderedEpisodes.map(\.guid))

        Subscriptions.unsubscribe(podcast, in: context)
        try context.save()

        #expect(Subscriptions.existing(identity: "eight.example.com/feed", in: context) == nil)
        let remaining = try context.fetch(FetchDescriptor<Episode>())
            .filter { guids.contains($0.guid) && $0.podcast == nil }
        #expect(remaining.isEmpty)
    }
}
