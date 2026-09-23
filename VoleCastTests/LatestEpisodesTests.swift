import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Unlike the other store suites, each test here builds its own container
/// rather than sharing `TestContainer`: this query is global by nature — the
/// newest episodes across everything — so another suite's episodes would show
/// up in the results.
@Suite(.serialized)
@MainActor
struct LatestEpisodesTests {

    private func makeShow(
        _ title: String,
        episodes: [(String, Date?)],
        in context: ModelContext
    ) -> Podcast {
        let podcast = Podcast(feedURL: "https://\(title).example.com/feed", feedIdentity: title, title: title)
        context.insert(podcast)
        for (episodeTitle, date) in episodes {
            let episode = Episode(guid: "\(title)-\(episodeTitle)", title: episodeTitle, audioURL: "https://a/\(episodeTitle).mp3")
            episode.publishedAt = date
            episode.podcast = podcast
            context.insert(episode)
        }
        return podcast
    }

    private func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_756_684_800 + TimeInterval(day) * 86_400)
    }

    /// "Latest" means what is still waiting for you. Something you listened to
    /// all the way through has stopped being new, and it lives in History now.
    @Test func omitsFinishedEpisodes() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow("Show", episodes: [("Done", day(2)), ("Waiting", day(1))], in: context)
        let done = try #require(show.episodes?.first { $0.title == "Done" })
        done.isPlayed = true

        let episodes = try context.fetch(LatestEpisodes.descriptor())

        #expect(episodes.map(\.title) == ["Waiting"])
    }

    /// Part-way through is still waiting for you.
    @Test func keepsAnEpisodeThatWasOnlyStarted() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow("Show", episodes: [("Started", day(1))], in: context)
        let started = try #require(show.episodes?.first)
        started.playbackPosition = 300
        started.lastPlayedAt = .now

        let episodes = try context.fetch(LatestEpisodes.descriptor())

        #expect(episodes.map(\.title) == ["Started"])
    }

    @Test func mixesShowsTogetherNewestFirst() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeShow("alpha", episodes: [("a-old", day(1)), ("a-new", day(5))], in: context)
        _ = makeShow("beta", episodes: [("b-mid", day(3)), ("b-newest", day(9))], in: context)

        let latest = try context.fetch(LatestEpisodes.descriptor())

        #expect(latest.map(\.title) == ["b-newest", "a-new", "b-mid", "a-old"])
    }

    @Test func keepsOnlyTheRequestedNumber() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeShow(
            "gamma",
            episodes: (1...30).map { ("episode-\($0)", day($0)) },
            in: context
        )

        let latest = try context.fetch(LatestEpisodes.descriptor(limit: 20))

        #expect(latest.count == 20)
        #expect(latest.first?.title == "episode-30")
        #expect(latest.last?.title == "episode-11")
    }

    @Test func skipsEpisodesWithNoDate() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeShow("delta", episodes: [("dated", day(2)), ("undated", nil)], in: context)

        let latest = try context.fetch(LatestEpisodes.descriptor())

        #expect(latest.map(\.title) == ["dated"])
    }

    @Test func unsubscribingRemovesItsEpisodesFromTheList() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow("epsilon", episodes: [("gone", day(4))], in: context)
        _ = makeShow("zeta", episodes: [("stays", day(6))], in: context)

        Subscriptions.unsubscribe(show, in: context)
        try context.save()

        let latest = try context.fetch(LatestEpisodes.descriptor())
        #expect(latest.map(\.title) == ["stays"])
    }

    @Test func defaultsToTwenty() {
        #expect(LatestEpisodes.defaultLimit == 20)
        #expect(LatestEpisodes.descriptor().fetchLimit == 20)
    }
}
