import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Its own container per test: this counts across every show in the store, so
/// another suite's episodes would be counted in with these.
@Suite(.serialized)
@MainActor
struct ListeningTotalsTests {

    private func show(_ context: ModelContext, _ name: String) -> Podcast {
        let podcast = Podcast(
            feedURL: "https://\(name).example.com/feed",
            feedIdentity: "\(name).example.com/feed",
            title: name
        )
        context.insert(podcast)
        return podcast
    }

    private func episode(
        _ context: ModelContext, _ show: Podcast, guid: String, played: Bool
    ) {
        let episode = Episode(
            guid: guid, title: guid, audioURL: "https://x.example.com/\(guid).mp3"
        )
        episode.podcast = show
        episode.lastPlayedAt = played ? .now : nil
        context.insert(episode)
    }

    /// `lastPlayedAt` is the app's own marker that something was played, the
    /// same one `ListeningHistory` uses.
    @Test func countsOnlyWhatWasPlayed() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let a = show(context, "a")
        episode(context, a, guid: "a1", played: true)
        episode(context, a, guid: "a2", played: true)
        episode(context, a, guid: "a3", played: false)

        #expect(ListeningTotals.playCounts(in: context)[a.persistentModelID] == 2)
    }

    /// The point of counting at all: a show subscribed to and never opened
    /// must not outrank one actually listened to.
    @Test func aShowNeverPlayedIsAbsentRatherThanZero() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let ignored = show(context, "ignored")
        episode(context, ignored, guid: "i1", played: false)

        #expect(ListeningTotals.playCounts(in: context)[ignored.persistentModelID] == nil)
    }

    @Test func countsEachShowSeparately() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let a = show(context, "a")
        let b = show(context, "b")
        episode(context, a, guid: "a1", played: true)
        episode(context, b, guid: "b1", played: true)
        episode(context, b, guid: "b2", played: true)

        let counts = ListeningTotals.playCounts(in: context)
        #expect(counts[a.persistentModelID] == 1)
        #expect(counts[b.persistentModelID] == 2)
    }
}
