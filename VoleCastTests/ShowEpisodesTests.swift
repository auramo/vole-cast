import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Own container per test: the descriptor is scoped to one show, but it looks
/// at every episode in the store to find them.
@Suite(.serialized)
@MainActor
struct ShowEpisodesTests {

    @discardableResult
    private func makeShow(
        _ context: ModelContext,
        identity: String,
        episodes: [(title: String, day: Int)]
    ) -> Podcast {
        let show = Podcast(
            feedURL: "https://\(identity)/feed",
            feedIdentity: identity,
            title: "Show \(identity)"
        )
        context.insert(show)
        for episode in episodes {
            let stored = Episode(
                guid: "\(identity)-\(episode.title)",
                title: episode.title,
                audioURL: "https://\(identity)/a.mp3"
            )
            stored.publishedAt = Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(episode.day) * 86_400)
            stored.podcast = show
            context.insert(stored)
        }
        return show
    }

    @Test func returnsOnlyTheShowsOwnEpisodesNewestFirst() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "mine", episodes: [("Older", 1), ("Newer", 5)])
        makeShow(context, identity: "theirs", episodes: [("Not Mine", 9)])

        let episodes = try context.fetch(ShowEpisodes.descriptor(feedIdentity: "mine"))

        #expect(episodes.map(\.title) == ["Newer", "Older"])
    }

    /// The point of the feature: seven hundred episodes deep, finding a series
    /// by eye is hopeless.
    @Test func filtersByTitle() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "rih", episodes: [
            ("The French Revolution: The Storming of the Bastille", 3),
            ("The French Revolution: The Terror", 2),
            ("The Fall of Rome", 1),
        ])

        let episodes = try context.fetch(
            ShowEpisodes.descriptor(feedIdentity: "rih", matching: "french revolution")
        )

        #expect(episodes.count == 2)
        #expect(episodes.allSatisfy { $0.title.contains("French Revolution") })
    }

    /// Nobody types the capitals.
    @Test func ignoresCase() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "case", episodes: [("The FRENCH Revolution", 1)])

        let episodes = try context.fetch(
            ShowEpisodes.descriptor(feedIdentity: "case", matching: "french")
        )

        #expect(episodes.count == 1)
    }

    /// A search still only sees the show you are looking at.
    @Test func staysWithinTheShow() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "a", episodes: [("Napoleon", 1)])
        makeShow(context, identity: "b", episodes: [("Napoleon", 1)])

        let episodes = try context.fetch(
            ShowEpisodes.descriptor(feedIdentity: "a", matching: "napoleon")
        )

        #expect(episodes.count == 1)
        #expect(episodes.first?.podcast?.feedIdentity == "a")
    }

    /// An empty field is not a filter — clearing the search brings everything
    /// back rather than matching nothing.
    @Test func anEmptySearchMatchesEverything() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "empty", episodes: [("One", 1), ("Two", 2)])

        #expect(try context.fetch(ShowEpisodes.descriptor(feedIdentity: "empty", matching: "")).count == 2)
        #expect(try context.fetch(ShowEpisodes.descriptor(feedIdentity: "empty", matching: "   ")).count == 2)
    }

    @Test func findsNothingWhenNothingMatches() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        makeShow(context, identity: "none", episodes: [("Napoleon", 1)])

        let episodes = try context.fetch(
            ShowEpisodes.descriptor(feedIdentity: "none", matching: "byzantium")
        )

        #expect(episodes.isEmpty)
    }

    /// Unlike Latest, an undated episode is still one of the show's episodes.
    @Test func keepsUndatedEpisodes() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let show = makeShow(context, identity: "undated", episodes: [("Dated", 1)])
        let orphanDate = Episode(guid: "u-1", title: "Undated", audioURL: "https://u/a.mp3")
        orphanDate.podcast = show
        context.insert(orphanDate)

        let episodes = try context.fetch(ShowEpisodes.descriptor(feedIdentity: "undated"))

        #expect(episodes.count == 2)
    }
}
