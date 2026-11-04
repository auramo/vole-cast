import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// The car's History tab, tested the way `CarPlayLatestListTests` tests its
/// Latest one: as values, with no car or template.
@Suite(.serialized)
@MainActor
struct CarPlayHistoryListTests {

    private func makeEpisode(_ context: ModelContext, guid: String) -> Episode {
        let show = Podcast(feedURL: "https://h.example.com/feed", feedIdentity: "h", title: "Show")
        context.insert(show)
        let episode = Episode(guid: guid, title: "Episode \(guid)", audioURL: "https://h.example.com/\(guid).mp3")
        // Undated, so the subtitle is a fixed string to assert on.
        episode.publishedAt = nil
        episode.duration = 2520
        episode.lastPlayedAt = .now
        episode.podcast = show
        context.insert(episode)
        return episode
    }

    /// The phone marks it with a checkmark. A car row has no place for one of
    /// its own, so it is said in the line that already carries the details.
    @Test func aFinishedEpisodeSaysPlayed() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "h1")
        episode.isPlayed = true

        let row = CarPlayHistoryList.sections(history: [episode], current: nil).first?.rows.first

        #expect(row?.subtitle.hasSuffix(CarPlayHistoryList.playedLabel) == true)
        #expect(row?.subtitle.hasPrefix("Show") == true)
    }

    @Test func aPartPlayedEpisodeSaysHowFarInInstead() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "h1")
        episode.playbackPosition = 630

        let row = CarPlayHistoryList.sections(history: [episode], current: nil).first?.rows.first

        #expect(row?.subtitle.hasSuffix("%") == true)
        #expect(row?.subtitle.contains(CarPlayHistoryList.playedLabel) == false)
    }

    @Test func marksTheLoadedEpisodeAndNoOther() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let first = makeEpisode(context, guid: "h1")
        let second = makeEpisode(context, guid: "h2")

        let rows = CarPlayHistoryList.sections(
            history: [first, second], current: second.persistentModelID
        ).first?.rows

        #expect(rows?.map(\.isPlaying) == [false, true])
    }

    /// Most recently played first is the query's job, and the list keeps it.
    @Test func keepsTheOrderItIsGiven() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let first = makeEpisode(context, guid: "h1")
        let second = makeEpisode(context, guid: "h2")

        let rows = CarPlayHistoryList.sections(history: [second, first], current: nil).first?.rows

        #expect(rows?.map(\.id) == [second.persistentModelID, first.persistentModelID])
    }

    /// The tab already names the list, so a heading over it would say History
    /// twice.
    @Test func isOneSectionWithNoHeading() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "h1")

        let sections = CarPlayHistoryList.sections(history: [episode], current: nil)

        #expect(sections.count == 1)
        #expect(sections.first?.title == nil)
    }

    /// Refreshing brings in new episodes, which land in Latest, not here.
    @Test func offersNoRefresh() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "h1")

        let sections = CarPlayHistoryList.sections(history: [episode], current: nil)

        #expect(sections.first?.offersRefresh == false)
    }

    @Test func nothingPlayedMakesAnEmptyList() {
        #expect(CarPlayHistoryList.sections(history: [], current: nil).first?.rows.isEmpty == true)
    }
}
