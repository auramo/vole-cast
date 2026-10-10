import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Its own container per test rather than `TestContainer`: this fetches every
/// podcast in the store, so another suite's subscriptions would be grouped in
/// with these.
@Suite(.serialized)
@MainActor
struct DuplicateSubscriptionsTests {

    private typealias State = DuplicateSubscriptions.PlaybackState

    // MARK: - The rule

    @Test func keepsTheFurthestPosition() {
        let merged = DuplicateSubscriptions.merging(
            State(position: 900, isPlayed: false, lastPlayedAt: nil),
            State(position: 120, isPlayed: false, lastPlayedAt: nil)
        )

        #expect(merged.position == 900)
    }

    /// Finished beats part-played, and takes the position down with it.
    /// `markPlayed` zeroes the two together precisely so they cannot
    /// contradict each other, and keeping 900 here would produce an episode
    /// both finished and fifteen minutes in.
    @Test func finishedWinsAndZeroesThePosition() {
        let merged = DuplicateSubscriptions.merging(
            State(position: 900, isPlayed: false, lastPlayedAt: nil),
            State(position: 0, isPlayed: true, lastPlayedAt: nil)
        )

        #expect(merged.isPlayed)
        #expect(merged.position == 0)
    }

    @Test func keepsTheLaterTimestamp() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 9000)

        let merged = DuplicateSubscriptions.merging(
            State(position: 0, isPlayed: false, lastPlayedAt: older),
            State(position: 0, isPlayed: false, lastPlayedAt: newer)
        )

        #expect(merged.lastPlayedAt == newer)
    }

    @Test func survivesNeitherCopyHavingBeenPlayed() {
        let merged = DuplicateSubscriptions.merging(
            State(position: 0, isPlayed: false, lastPlayedAt: nil),
            State(position: 0, isPlayed: false, lastPlayedAt: nil)
        )

        #expect(merged == State(position: 0, isPlayed: false, lastPlayedAt: nil))
    }

    // MARK: - The pass

    private func show(
        _ context: ModelContext,
        subscribedAt: Date,
        episodes: [(guid: String, position: Double, isPlayed: Bool)]
    ) -> Podcast {
        let podcast = Podcast(
            feedURL: "https://twice.example.com/feed",
            feedIdentity: "twice.example.com/feed",
            title: "Doubled Show"
        )
        podcast.subscribedAt = subscribedAt
        context.insert(podcast)
        for e in episodes {
            let episode = Episode(
                guid: e.guid,
                title: "Episode \(e.guid)",
                audioURL: "https://twice.example.com/\(e.guid).mp3"
            )
            episode.playbackPosition = e.position
            episode.isPlayed = e.isPlayed
            episode.podcast = podcast
            context.insert(episode)
        }
        return podcast
    }

    @Test func leavesAStoreWithNoDuplicatesAlone() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = show(context, subscribedAt: .now, episodes: [("a", 0, false)])

        #expect(DuplicateSubscriptions.merge(in: context) == 0)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 1)
    }

    @Test func foldsTwoCopiesIntoOne() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 1000),
                 episodes: [("a", 0, false)])
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 9000),
                 episodes: [("a", 0, false)])

        #expect(DuplicateSubscriptions.merge(in: context) == 1)

        let left = try context.fetch(FetchDescriptor<Podcast>())
        #expect(left.count == 1)
        // The older subscription survives: other devices have most likely seen
        // it already.
        #expect(left.first?.subscribedAt == Date(timeIntervalSince1970: 1000))
    }

    /// The whole point of the pass. One device was fifteen minutes into an
    /// episode; the other copy had never been touched. Afterwards there is one
    /// episode, and it remembers.
    @Test func keepsTheProgressFromWhicheverCopyHasIt() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 1000),
                 episodes: [("a", 0, false)])
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 9000),
                 episodes: [("a", 900, false)])

        DuplicateSubscriptions.merge(in: context)

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.count == 1)
        #expect(episodes.first?.playbackPosition == 900)
    }

    /// The copies can have refreshed at different moments, so the loser may
    /// hold an episode the keeper genuinely does not have. It moves across
    /// rather than going down with the cascade.
    @Test func carriesOverAnEpisodeTheKeeperNeverSaw() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 1000),
                 episodes: [("a", 0, false)])
        _ = show(context, subscribedAt: Date(timeIntervalSince1970: 9000),
                 episodes: [("a", 0, false), ("b", 0, false)])

        DuplicateSubscriptions.merge(in: context)

        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(Set(episodes.map(\.guid)) == ["a", "b"])
        #expect(episodes.allSatisfy { $0.podcast != nil })
    }

    /// Three is not a special case, but it is the one an off-by-one would
    /// leave behind.
    @Test func foldsAwayMoreThanOneDuplicate() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        for seconds in [1000.0, 5000, 9000] {
            _ = show(context, subscribedAt: Date(timeIntervalSince1970: seconds),
                     episodes: [("a", 0, false)])
        }

        #expect(DuplicateSubscriptions.merge(in: context) == 2)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 1)
    }

    /// Different shows are not duplicates of each other, however similar.
    @Test func doesNotTouchDifferentShows() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = show(context, subscribedAt: .now, episodes: [("a", 0, false)])
        let other = Podcast(
            feedURL: "https://elsewhere.example.com/feed",
            feedIdentity: "elsewhere.example.com/feed",
            title: "Doubled Show"
        )
        context.insert(other)

        #expect(DuplicateSubscriptions.merge(in: context) == 0)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 2)
    }
}
