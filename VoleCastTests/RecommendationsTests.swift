import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// The rules behind the suggestions, tested without a network or a screen.
@Suite(.serialized)
@MainActor
struct RecommendationsTests {

    private func show(
        _ context: ModelContext, _ name: String,
        collectionID: Int? = 1, subscribedAt: Date = .now
    ) -> Podcast {
        let podcast = Podcast(
            feedURL: "https://\(name).example.com/feed",
            feedIdentity: "\(name).example.com/feed",
            title: name
        )
        podcast.itunesCollectionID = collectionID
        podcast.subscribedAt = subscribedAt
        context.insert(podcast)
        return podcast
    }

    // MARK: - Seeds

    @Test func ranksByHowMuchWasPlayed() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let little = show(context, "little", collectionID: 1)
        let lots = show(context, "lots", collectionID: 2)

        let seeds = Recommendations.seeds(
            from: [little, lots],
            playCounts: [little.persistentModelID: 2, lots.persistentModelID: 14],
            limit: 3
        )

        #expect(seeds.map(\.title) == ["lots", "little"])
    }

    /// Subscriptions say what you meant to listen to; play counts say what you
    /// did. A show never opened must come last.
    @Test func aNeverPlayedShowRanksBelowAPlayedOne() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let ignored = show(context, "ignored", collectionID: 1)
        let played = show(context, "played", collectionID: 2)

        let seeds = Recommendations.seeds(
            from: [ignored, played],
            playCounts: [played.persistentModelID: 1],
            limit: 3
        )

        #expect(seeds.first?.title == "played")
    }

    /// Before anything has been played there is still something to go on.
    /// This is why the section title must not claim you listen to the seed.
    @Test func withNothingPlayedTheNewestSubscriptionLeads() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let old = show(context, "old", collectionID: 1,
                       subscribedAt: Date(timeIntervalSince1970: 1000))
        let new = show(context, "new", collectionID: 2,
                       subscribedAt: Date(timeIntervalSince1970: 9000))

        let seeds = Recommendations.seeds(from: [old, new], playCounts: [:], limit: 3)

        #expect(seeds.map(\.title) == ["new", "old"])
    }

    /// A pasted feed has no collection id, so Apple cannot be asked about it —
    /// and must not be, since a private feed carries a token in its address.
    @Test func aShowWithNoCollectionIDSeedsNothing() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let pasted = show(context, "pasted", collectionID: nil)

        #expect(Recommendations.seeds(from: [pasted], playCounts: [:], limit: 3).isEmpty)
    }

    @Test func takesNoMoreSeedsThanAsked() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let shows = (1...5).map { show(context, "s\($0)", collectionID: $0) }

        #expect(Recommendations.seeds(from: shows, playCounts: [:], limit: 2).count == 2)
    }

    /// The filter must run before the limit. Reversed, the two pasted feeds
    /// would take both slots and the one show Apple actually knows about
    /// would be dropped. Every other seed test passes either way, so this is
    /// the one that pins the order.
    @Test func pastedFeedsCannotCrowdOutAnEligibleShow() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let eligible = show(context, "eligible", collectionID: 7,
                            subscribedAt: Date(timeIntervalSince1970: 1000))
        let pastedA = show(context, "pastedA", collectionID: nil,
                           subscribedAt: Date(timeIntervalSince1970: 8000))
        let pastedB = show(context, "pastedB", collectionID: nil,
                           subscribedAt: Date(timeIntervalSince1970: 9000))

        let seeds = Recommendations.seeds(
            from: [pastedA, pastedB, eligible], playCounts: [:], limit: 2
        )

        #expect(seeds.map(\.title) == ["eligible"])
    }

    /// Play count and subscribedAt can both tie — two shows added in the same
    /// batch, neither played. The array order they arrive in is a fetch's,
    /// and unspecified. Something stable has to break the tie, or the screen
    /// reshuffles between launches for no reason the reader can see.
    @Test func tiedShowsOrderStablyRegardlessOfInputOrder() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let sameTime = Date(timeIntervalSince1970: 5000)
        let alpha = show(context, "alpha", collectionID: 1, subscribedAt: sameTime)
        let beta = show(context, "beta", collectionID: 2, subscribedAt: sameTime)

        let forward = Recommendations.seeds(from: [alpha, beta], playCounts: [:], limit: 2)
        let backward = Recommendations.seeds(from: [beta, alpha], playCounts: [:], limit: 2)

        #expect(forward.map(\.title) == backward.map(\.title))
    }

    // MARK: - Subgenre

    /// The values are Apple's own, recorded from a live response. A wrong id
    /// does not error — it returns a perfectly valid chart of something else.
    @Test func prefersTheMostSpecificGenre() {
        let daily = [
            PodcastGenre(id: 1526, name: "Daily News"),
            PodcastGenre(id: 26, name: "Podcasts"),
            PodcastGenre(id: 1489, name: "News"),
        ]

        #expect(Recommendations.subgenre(from: daily)?.id == 1526)
    }

    /// 26 is the root every podcast carries and means nothing.
    @Test func neverChoosesTheRootGenre() {
        let only = [PodcastGenre(id: 26, name: "Podcasts")]

        #expect(Recommendations.subgenre(from: only) == nil)
    }

    /// A show filed only under a top level still charts, just more broadly.
    @Test func fallsBackToATopLevelGenre() {
        let broad = [
            PodcastGenre(id: 26, name: "Podcasts"),
            PodcastGenre(id: 1489, name: "News"),
        ]

        #expect(Recommendations.subgenre(from: broad)?.id == 1489)
    }

    @Test func hasNothingToChooseFromAnEmptyList() {
        #expect(Recommendations.subgenre(from: []) == nil)
    }

    // MARK: - Exclusion

    private func entry(_ collectionID: Int) -> ChartEntry {
        ChartEntry(
            id: "itunes:\(collectionID)", collectionID: collectionID, rank: 1,
            title: "t", author: "a", artworkURL: nil, storefront: "fi"
        )
    }

    @Test func dropsChartEntriesAlreadySubscribedTo() {
        let surviving = Recommendations.surviving(
            [entry(1), entry(2), entry(3)], excludingCollectionIDs: [2]
        )

        #expect(surviving.map(\.collectionID) == [1, 3])
    }

    private func result(_ collectionID: Int?, feed: String) -> PodcastSearchResult {
        PodcastSearchResult(
            id: "itunes:\(collectionID.map(String.init) ?? feed)", title: "t", author: "a",
            feedURL: URL(string: feed)!, artworkURL: nil, episodeCount: nil,
            genres: [], itunesCollectionID: collectionID
        )
    }

    /// A show can be subscribed to by a pasted URL and so have no collection
    /// id on record — the feed identity is the only thing both sides share.
    @Test func dropsResultsAlreadySubscribedToByFeed() {
        let surviving = Recommendations.surviving(
            [result(nil, feed: "https://a.example.com/feed"),
             result(nil, feed: "https://b.example.com/feed")],
            excludingCollectionIDs: [],
            excludingIdentities: ["a.example.com/feed"]
        )

        #expect(surviving.count == 1)
        #expect(surviving.first?.feedURL.absoluteString == "https://b.example.com/feed")
    }

    @Test func dropsResultsAlreadySubscribedToByCollectionID() {
        let surviving = Recommendations.surviving(
            [result(7, feed: "https://a.example.com/feed")],
            excludingCollectionIDs: [7],
            excludingIdentities: []
        )

        #expect(surviving.isEmpty)
    }
}
