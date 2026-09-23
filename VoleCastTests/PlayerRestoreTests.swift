import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Its own container per test rather than `TestContainer`: restoring asks the
/// store for the most recently played episode across everything, so another
/// suite's episodes would answer the question instead.
@Suite(.serialized)
@MainActor
struct PlayerRestoreTests {

    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        playedAt: Date?,
        position: TimeInterval = 0,
        isPlayed: Bool = false
    ) -> Episode {
        let show = Podcast(feedURL: "https://s.example.com/feed", feedIdentity: "s", title: "Show")
        context.insert(show)
        let episode = Episode(guid: guid, title: "Episode \(guid)", audioURL: "https://a.example.com/\(guid).mp3")
        episode.duration = 1800
        episode.lastPlayedAt = playedAt
        episode.playbackPosition = position
        episode.isPlayed = isPlayed
        episode.podcast = show
        context.insert(episode)
        return episode
    }

    /// The app is killed while paused far more often than anyone notices — a
    /// few hours in the background is enough. The bar has to come back.
    @Test func restoresTheLastPlayedEpisode() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "r1", playedAt: .now, position: 900)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.restoreLastPlayed()

        #expect(player.current?.title == "Episode r1")
        #expect(player.position == 900)
        #expect(player.duration == 1800)
    }

    /// Restoring must not make a sound. The app has just launched, possibly in
    /// someone's pocket.
    @Test func restoringDoesNotStartPlaying() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "r2", playedAt: .now, position: 900)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.restoreLastPlayed()

        #expect(fake.commands.isEmpty)
        #expect(!player.isPlaying)
    }

    /// The engine was never given the episode, so resuming has to hand it over
    /// rather than just asking it to play.
    @Test func resumingARestoredEpisodeLoadsItWhereItWasLeft() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "r3", playedAt: .now, position: 900)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)
        player.restoreLastPlayed()

        player.resume()

        #expect(fake.loaded?.startAt == 900)
        #expect(fake.loaded?.audioURL.absoluteString == "https://a.example.com/r3.mp3")
    }

    @Test func picksTheMostRecentlyPlayed() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "older", playedAt: Date(timeIntervalSince1970: 1000))
        _ = makeEpisode(context, guid: "newer", playedAt: Date(timeIntervalSince1970: 2000))
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.restoreLastPlayed()

        #expect(player.current?.title == "Episode newer")
    }

    @Test func restoresNothingWhenNothingWasEverPlayed() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "never", playedAt: nil)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.restoreLastPlayed()

        #expect(player.current == nil)
    }

    /// Restoring is a launch-time act. It must never elbow aside something
    /// that is already loaded.
    @Test func leavesAnAlreadyLoadedEpisodeAlone() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let playing = makeEpisode(context, guid: "playing", playedAt: Date(timeIntervalSince1970: 1000))
        _ = makeEpisode(context, guid: "other", playedAt: Date(timeIntervalSince1970: 9000))
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.toggle(playing)
        player.restoreLastPlayed()

        #expect(player.current?.title == "Episode playing")
    }

    /// The bar stays put until something else is started — which is the only
    /// thing that should replace it.
    @Test func startingAnotherEpisodeReplacesTheRestoredOne() throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "restored", playedAt: .now, position: 900)
        let next = makeEpisode(context, guid: "next", playedAt: nil)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)
        player.restoreLastPlayed()

        player.toggle(next)

        #expect(player.current?.title == "Episode next")
        #expect(player.isCurrent(next))
    }

    /// Scrubbing before pressing play should start from where you dragged to,
    /// not from where the episode was left.
    @Test func seekingBeforeResumingMovesWhereItWillStart() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "r4", playedAt: .now, position: 900)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)
        player.restoreLastPlayed()

        player.seek(to: 120)
        player.resume()

        #expect(player.position == 120)
        #expect(fake.loaded?.startAt == 120)
    }

    /// A finished episode resumes from the start, as it would anywhere else.
    @Test func restoringAFinishedEpisodeStartsItOver() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = makeEpisode(context, guid: "done", playedAt: .now, position: 0, isPlayed: true)
        let fake = FakeAudioPlayback()
        let player = PlayerModel(playback: fake, context: context)

        player.restoreLastPlayed()
        player.resume()

        #expect(player.current?.title == "Episode done")
        #expect(fake.loaded?.startAt == 0)
    }
}
