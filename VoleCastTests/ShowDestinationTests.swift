import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Its own container per test: these build shows and episodes and care only
/// about the values that address them.
@Suite(.serialized)
@MainActor
struct ShowDestinationTests {

    private func makeShow(_ context: ModelContext, guids: [String]) throws -> Podcast {
        let show = Podcast(feedURL: "https://d.example.com/feed", feedIdentity: "d", title: "Show")
        context.insert(show)
        for guid in guids {
            let episode = Episode(guid: guid, title: guid, audioURL: "https://d.example.com/\(guid).mp3")
            episode.podcast = show
            context.insert(episode)
        }
        return show
    }

    /// Opening a show for its own sake lands nowhere in particular.
    @Test func focusesNothingByDefault() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = try makeShow(context, guids: ["a"])

        #expect(ShowDestination(podcast: show).focus == nil)
    }

    /// Navigation compares values, so arriving at one episode has to be a
    /// different destination from arriving at another — otherwise pushing the
    /// show again from a different episode would be treated as the same place
    /// and land where it did last time.
    @Test func differentEpisodesAreDifferentDestinations() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = try makeShow(context, guids: ["a", "b"])
        let episodes = try #require(show.episodes)
        let first = try #require(episodes.first { $0.guid == "a" })
        let second = try #require(episodes.first { $0.guid == "b" })

        let toFirst = ShowDestination(podcast: show, focus: first.persistentModelID)
        let toSecond = ShowDestination(podcast: show, focus: second.persistentModelID)

        #expect(toFirst != toSecond)
        #expect(toFirst != ShowDestination(podcast: show))
    }

    @Test func theSameEpisodeIsTheSameDestination() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = try makeShow(context, guids: ["a"])
        let episode = try #require(show.episodes?.first)

        let one = ShowDestination(podcast: show, focus: episode.persistentModelID)
        let two = ShowDestination(podcast: show, focus: episode.persistentModelID)

        #expect(one == two)
        #expect(one.hashValue == two.hashValue)
    }

    /// The rows are keyed by the store's identifier, which is what the focus
    /// carries — so what is pushed can actually be found on arrival.
    @Test func theFocusMatchesTheIdentityTheListRowsUse() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = try makeShow(context, guids: ["a", "b", "c"])
        let target = try #require(show.orderedEpisodes.last)

        let destination = ShowDestination(podcast: show, focus: target.persistentModelID)

        #expect(show.orderedEpisodes.contains { $0.id == destination.focus })
    }
}
