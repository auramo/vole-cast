import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// The wiring the app actually runs with.
///
/// `PlayerModelTests` hands the player the very context its episodes were
/// inserted into, which the app never does: a row's episode arrives from the
/// view's `@Query`, so it is registered in the container's `mainContext`. If
/// the player writes through some other context it resolves nothing and every
/// write is silently skipped — history stops updating and positions stop being
/// kept. That is invisible to a test that supplies both sides itself, so it is
/// pinned here instead.
///
/// Its own container per test, like `PlayerRestoreTests`: these touch the
/// main context, and a shared store would carry that into other suites.
@Suite(.serialized)
@MainActor
struct PlaybackHostTests {

    /// An episode as a view would hand one over: fetched through the context
    /// SwiftUI puts in the environment.
    private func episodeFromAView(in container: ModelContainer) throws -> Episode {
        let context = container.mainContext
        let show = Podcast(feedURL: "https://h.example.com/feed", feedIdentity: "h", title: "Show")
        context.insert(show)
        let episode = Episode(
            guid: "h1",
            title: "Episode h1",
            audioURL: "https://h.example.com/h1.mp3"
        )
        episode.duration = 1800
        episode.podcast = show
        context.insert(episode)
        try context.save()

        // Deliberately re-fetched rather than returned directly, so the test
        // holds what a `@Query` would hand a row rather than the object it
        // just built.
        let fetched = try context.fetch(FetchDescriptor<Episode>())
        return try #require(fetched.first { $0.guid == "h1" })
    }

    @Test func playingAnEpisodeFromAViewPutsItInTheHistory() throws {
        let container = VoleCastModelContainer.makeInMemory()
        let episode = try episodeFromAView(in: container)
        let fake = FakeAudioPlayback()
        let player = PlaybackHost.makePlayer(for: container, playback: fake)

        player.toggle(episode)
        fake.emit(.phase(.playing))

        #expect(episode.lastPlayedAt != nil)
    }

    @Test func progressOnAnEpisodeFromAViewIsKept() throws {
        let container = VoleCastModelContainer.makeInMemory()
        let episode = try episodeFromAView(in: container)
        let fake = FakeAudioPlayback()
        let player = PlaybackHost.makePlayer(for: container, playback: fake)

        player.toggle(episode)
        fake.emit(.phase(.playing))
        fake.emit(.time(300))

        #expect(episode.playbackPosition == 300)
    }

    /// The context registers models weakly. A view holds its `@Query` results
    /// for as long as it is on screen, which hides this everywhere on the
    /// phone — but the car fetches a list, builds rows from identifiers and
    /// lets the episodes go, and an app launched straight into CarPlay has no
    /// view holding anything. Whatever the player is told to play has to stay
    /// resolvable after the fetch that produced it is gone.
    @Test func keepsRecordingWhenNothingElseHoldsTheEpisode() throws {
        let container = VoleCastModelContainer.makeInMemory()
        let context = container.mainContext
        // Built inside a scope that ends, so this test holds nothing either —
        // a local `let` here would retain the episode and hide the bug.
        try {
            let show = Podcast(
                feedURL: "https://h2.example.com/feed",
                feedIdentity: "h2",
                title: "Show"
            )
            context.insert(show)
            let episode = Episode(
                guid: "h2",
                title: "Episode h2",
                audioURL: "https://h2.example.com/h2.mp3"
            )
            episode.duration = 1800
            episode.podcast = show
            context.insert(episode)
            try context.save()
        }()

        let fake = FakeAudioPlayback()
        let player = PlaybackHost.makePlayer(for: container, playback: fake)

        // Fetched, handed over, and released — exactly what the car does.
        try {
            let fetched = try context.fetch(FetchDescriptor<Episode>())
            player.play(try #require(fetched.first { $0.guid == "h2" }))
        }()

        fake.emit(.phase(.playing))
        fake.emit(.time(300))

        let after = try #require(
            try context.fetch(FetchDescriptor<Episode>()).first { $0.guid == "h2" }
        )
        #expect(after.lastPlayedAt != nil)
        #expect(after.playbackPosition == 300)
    }

    @Test func finishingAnEpisodeFromAViewMarksItPlayed() throws {
        let container = VoleCastModelContainer.makeInMemory()
        let episode = try episodeFromAView(in: container)
        let fake = FakeAudioPlayback()
        let player = PlaybackHost.makePlayer(for: container, playback: fake)

        player.toggle(episode)
        fake.emit(.phase(.playing))
        fake.emit(.reachedEnd)

        #expect(episode.isPlayed)
    }
}
