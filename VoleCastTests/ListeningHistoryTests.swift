import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Like `LatestEpisodesTests`, each test builds its own container rather than
/// sharing `TestContainer`: this query is global by nature — everything you
/// have listened to, across every show — so another suite's episodes would show
/// up in the results.
@Suite(.serialized)
@MainActor
struct ListeningHistoryTests {

    private func makeShow(
        _ title: String,
        episodes: [(title: String, playedAt: Date?, isPlayed: Bool)],
        in context: ModelContext
    ) -> Podcast {
        let podcast = Podcast(feedURL: "https://\(title).example.com/feed", feedIdentity: title, title: title)
        context.insert(podcast)
        for episode in episodes {
            let stored = Episode(
                guid: "\(title)-\(episode.title)",
                title: episode.title,
                audioURL: "https://a/\(episode.title).mp3"
            )
            stored.publishedAt = minute(0)
            stored.lastPlayedAt = episode.playedAt
            stored.isPlayed = episode.isPlayed
            stored.podcast = podcast
            context.insert(stored)
        }
        return podcast
    }

    private func minute(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: 1_756_684_800 + TimeInterval(minute) * 60)
    }

    @Test func ordersByWhenItWasLastPlayedNewestFirst() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeShow("One", episodes: [
            ("Oldest", minute(1), false),
            ("Newest", minute(9), false),
        ], in: context)
        _ = makeShow("Two", episodes: [
            ("Middle", minute(5), false),
        ], in: context)

        let episodes = try context.fetch(ListeningHistory.descriptor())

        #expect(episodes.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    /// A position without a stamp shouldn't happen, but if it did, History is
    /// the list of things you played — and nothing says this one was.
    @Test func omitsEpisodesThatWereNeverPlayed() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow("Show", episodes: [
            ("Played", minute(1), false),
            ("Untouched", nil, false),
        ], in: context)
        let untouched = try #require(show.episodes?.first { $0.title == "Untouched" })
        untouched.playbackPosition = 300

        let episodes = try context.fetch(ListeningHistory.descriptor())

        #expect(episodes.map(\.title) == ["Played"])
    }

    /// Finishing something doesn't evict it — the whole point is "what have I
    /// been listening to", whether or not you got to the end.
    @Test func includesFinishedEpisodes() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeShow("Show", episodes: [("Finished", minute(1), true)], in: context)

        let episodes = try context.fetch(ListeningHistory.descriptor())

        #expect(episodes.map(\.title) == ["Finished"])
    }

    /// Deliberately unlike `LatestEpisodes`, which drops undated episodes
    /// because it can't place them on a "newest first" list. This list sorts on
    /// when you played it, where an undated episode has a perfectly good spot.
    @Test func includesAnEpisodeWithNoPublishDate() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow("Show", episodes: [("Undated", minute(1), false)], in: context)
        try #require(show.episodes?.first).publishedAt = nil

        let episodes = try context.fetch(ListeningHistory.descriptor())

        #expect(episodes.map(\.title) == ["Undated"])
    }

    @Test func keepsOnlyTheRequestedNumber() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let many = (1...30).map { (title: "Episode \($0)", playedAt: minute($0), isPlayed: false) }
        _ = makeShow("Show", episodes: many, in: context)

        let episodes = try context.fetch(ListeningHistory.descriptor(limit: 20))

        #expect(episodes.count == 20)
        #expect(episodes.first?.title == "Episode 30")
        #expect(episodes.last?.title == "Episode 11")
    }

    @Test func defaultsToTwenty() {
        #expect(ListeningHistory.defaultLimit == 20)
        #expect(ListeningHistory.descriptor().fetchLimit == 20)
    }

    /// The one way an entry leaves History, and not by design: `Podcast` cascades
    /// its episodes away, so an episode-backed query cannot outlive them.
    /// Asserted so it stays a known property rather than a surprise.
    @Test func unsubscribingTakesItsEpisodesOutOfHistory() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let leaving = makeShow("Leaving", episodes: [("Gone", minute(2), false)], in: context)
        _ = makeShow("Staying", episodes: [("Kept", minute(1), false)], in: context)

        Subscriptions.unsubscribe(leaving, in: context)
        try context.save()

        let episodes = try context.fetch(ListeningHistory.descriptor())

        #expect(episodes.map(\.title) == ["Kept"])
    }
}
