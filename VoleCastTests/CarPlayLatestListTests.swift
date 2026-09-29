import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// The rules behind the car's list, tested without the CarPlay framework —
/// the rows are values, so none of this needs a car or a template.
@Suite(.serialized)
@MainActor
struct CarPlayLatestListTests {

    /// Its own container per test, like `PlayerRestoreTests`.
    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        title: String,
        duration: Double? = 2520
    ) -> Episode {
        let show = Podcast(feedURL: "https://c.example.com/feed", feedIdentity: "c", title: "Show")
        context.insert(show)
        let episode = Episode(guid: guid, title: title, audioURL: "https://c.example.com/\(guid).mp3")
        // Left nil deliberately: a relative date ("3 days ago") is not a
        // deterministic string to assert on.
        episode.publishedAt = nil
        episode.duration = duration
        episode.podcast = show
        context.insert(episode)
        return episode
    }

    @Test func aRowCarriesTheTitleAndTheSharedSubtitle() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "Episode One")

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Episode One")
        // The same line the phone shows, from `EpisodeSubtitle`.
        #expect(rows.first?.subtitle == "42m")
    }

    @Test func marksTheLoadedEpisodeAndNoOther() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let first = makeEpisode(context, guid: "c1", title: "One")
        let second = makeEpisode(context, guid: "c2", title: "Two")

        let rows = CarPlayLatestList.rows(
            for: [first, second],
            current: second.persistentModelID
        )

        #expect(rows.map(\.isPlaying) == [false, true])
    }

    @Test func marksNothingWhenThePlayerIsEmpty() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "One")

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        #expect(rows.allSatisfy { !$0.isPlaying })
    }

    @Test func anEmptyStoreMakesAnEmptyList() {
        #expect(CarPlayLatestList.rows(for: [], current: nil).isEmpty)
    }

    @Test func selectingAnotherEpisodePlaysIt() {
        #expect(CarPlayLatestList.selection(isCurrent: false) == .playThenShowPlayer)
    }

    /// The one that would be easy to get wrong. On connect the restored
    /// episode sits in the list part-listened; tapping it must take the driver
    /// to the player, not restart it from zero and not pause it.
    @Test func selectingTheLoadedEpisodeLeavesPlaybackAlone() {
        #expect(CarPlayLatestList.selection(isCurrent: true) == .showPlayer)
    }
}
