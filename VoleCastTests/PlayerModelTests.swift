import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// Serialized and sharing one container, per `TestContainer`'s rule. Each test
/// uses its own feed identity and guids so the shared store can't leak between
/// them.
@Suite(.serialized)
@MainActor
struct PlayerModelTests {

    private func makeShow(
        _ context: ModelContext,
        identity: String,
        episodes: [String]
    ) -> Podcast {
        let show = Podcast()
        show.feedURL = "https://\(identity)/feed.xml"
        show.feedIdentity = identity
        show.title = "Show \(identity)"
        context.insert(show)

        for guid in episodes {
            let episode = Episode(guid: guid, title: "Episode \(guid)", audioURL: "https://\(identity)/\(guid).mp3")
            episode.duration = 1800
            episode.podcast = show
            context.insert(episode)
        }
        return show
    }

    private func model(_ playback: FakeAudioPlayback, _ context: ModelContext) -> PlayerModel {
        PlayerModel(playback: playback, context: context)
    }

    @Test func playingAFreshEpisodeLoadsIt() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "a.example.com", episodes: ["a1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)

        #expect(fake.loaded?.audioURL.absoluteString == "https://a.example.com/a1.mp3")
        #expect(fake.loaded?.title == "Episode a1")
        #expect(fake.loaded?.showTitle == "Show a.example.com")
        #expect(player.isCurrent(episode))
    }

    /// Tapping the control on the episode that is already playing must pause
    /// it, not start it over.
    @Test func togglingTheCurrentEpisodePausesRatherThanReloading() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "b.example.com", episodes: ["b1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.phase(.playing))
        fake.forget()

        player.toggle(episode)

        #expect(fake.commands == [.pause])
    }

    @Test func togglingAPausedCurrentEpisodeResumes() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "c.example.com", episodes: ["c1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.phase(.paused))
        fake.forget()

        player.toggle(episode)

        #expect(fake.commands == [.play])
    }

    @Test func playingADifferentEpisodeSwitchesToIt() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "d.example.com", episodes: ["d1", "d2"])
        let episodes = try #require(show.episodes)
        let first = try #require(episodes.first { $0.guid == "d1" })
        let second = try #require(episodes.first { $0.guid == "d2" })
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(first)
        fake.emit(.phase(.playing))
        player.toggle(second)

        #expect(fake.loaded?.audioURL.absoluteString == "https://d.example.com/d2.mp3")
        #expect(player.isCurrent(second))
        #expect(!player.isCurrent(first))
    }

    @Test func tracksPositionAndDurationFromTheEngine() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "e.example.com", episodes: ["e1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.time(42))
        fake.emit(.duration(2400))

        #expect(player.position == 42)
        #expect(player.duration == 2400)
    }

    /// The feed's claim is a placeholder so the scrubber has a range at once;
    /// the asset's real duration replaces it.
    @Test func theAssetsDurationBeatsTheFeeds() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "f.example.com", episodes: ["f1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        #expect(player.duration == 1800)

        fake.emit(.duration(1855))
        #expect(player.duration == 1855)
    }

    @Test func surfacesAFailure() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "g.example.com", episodes: ["g1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.phase(.failed(.offline)))

        #expect(player.error == .offline)
        #expect(!player.isBuffering)
    }

    @Test func clearsAFailureWhenSomethingElseIsPlayed() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "h.example.com", episodes: ["h1", "h2"])
        let episodes = try #require(show.episodes)
        let first = try #require(episodes.first { $0.guid == "h1" })
        let second = try #require(episodes.first { $0.guid == "h2" })
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(first)
        fake.emit(.phase(.failed(.unplayable)))
        player.toggle(second)

        #expect(player.error == nil)
    }

    @Test func reportsBufferingSeparatelyFromPlaying() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "i.example.com", episodes: ["i1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.phase(.buffering))
        #expect(player.isBuffering)
        #expect(!player.isPlaying)

        fake.emit(.phase(.playing))
        #expect(!player.isBuffering)
        #expect(player.isPlaying)
    }

    /// Unsubscribing cascades the show's episodes away, and the player must let
    /// go before that happens or it will read a deleted model.
    @Test func stopsOnlyWhenTheShowBeingLeftIsTheOnePlaying() throws {
        let context = ModelContext(TestContainer.shared)
        let playing = makeShow(context, identity: "j.example.com", episodes: ["j1"])
        let other = makeShow(context, identity: "k.example.com", episodes: ["k1"])
        let episode = try #require(playing.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)

        player.stopIfPlaying(from: other)
        #expect(player.current != nil)

        player.stopIfPlaying(from: playing)
        #expect(player.current == nil)
        #expect(fake.commands.contains(.stop))
    }

    /// The bar's controls act on whatever is loaded, without an `Episode` in
    /// hand — it only has the snapshot.
    @Test func resumesAndPausesWhatIsLoadedWithoutAnEpisode() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "m.example.com", episodes: ["m1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.phase(.playing))
        fake.forget()

        player.pause()
        #expect(fake.commands == [.pause])

        fake.emit(.phase(.paused))
        fake.forget()
        player.resume()
        #expect(fake.commands == [.play])
    }

    @Test func resumeDoesNothingWithNothingLoaded() {
        let fake = FakeAudioPlayback()
        let player = model(fake, ModelContext(TestContainer.shared))

        player.resume()
        player.pause()

        #expect(fake.commands.isEmpty)
    }

    // MARK: - Persistence

    @Test func startsWhereItWasLeftOff() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "n.example.com", episodes: ["n1"])
        let episode = try #require(show.episodes?.first)
        episode.playbackPosition = 900
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)

        #expect(fake.loaded?.startAt == 900)
        #expect(player.position == 900)
    }

    /// Writing on every tick would invalidate the Latest query once a second.
    @Test func writesPositionOnTheGridRatherThanEveryTick() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "o.example.com", episodes: ["o1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        for second in 1...9 { fake.emit(.time(TimeInterval(second))) }
        #expect(episode.playbackPosition == 0)

        fake.emit(.time(10))
        #expect(episode.playbackPosition == 10)
    }

    /// Pausing is a moment worth keeping however little has moved.
    @Test func pausingWritesThePositionImmediately() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "p.example.com", episodes: ["p1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.time(7))
        #expect(episode.playbackPosition == 0)

        player.pause()
        #expect(episode.playbackPosition == 7)
    }

    @Test func switchingEpisodesKeepsWhereTheOutgoingOneGotTo() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "q.example.com", episodes: ["q1", "q2"])
        let episodes = try #require(show.episodes)
        let first = try #require(episodes.first { $0.guid == "q1" })
        let second = try #require(episodes.first { $0.guid == "q2" })
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(first)
        fake.emit(.time(123))
        player.toggle(second)

        #expect(first.playbackPosition == 123)
    }

    @Test func reachingTheEndMarksItPlayedAndClearsThePosition() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "r.example.com", episodes: ["r1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.time(1700))
        fake.emit(.reachedEnd)

        #expect(episode.isPlayed)
        #expect(episode.playbackPosition == 0)
    }

    /// A call or an alarm can be followed by the app being killed, so the
    /// position has to be down before control is handed back.
    @Test func anInterruptionWritesThePosition() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "s.example.com", episodes: ["s1"])
        let episode = try #require(show.episodes?.first)
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)
        fake.emit(.time(55))
        fake.emit(.interrupted(resumable: true))

        #expect(episode.playbackPosition == 55)
    }

    @Test func aFinishedEpisodePlayedAgainStartsFromTheBeginning() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "t.example.com", episodes: ["t1"])
        let episode = try #require(show.episodes?.first)
        episode.isPlayed = true
        episode.playbackPosition = 0
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)

        #expect(fake.loaded?.startAt == 0)
    }

    @Test func refusesAnEpisodeWithNoUsableAudioURL() throws {
        let context = ModelContext(TestContainer.shared)
        let show = makeShow(context, identity: "l.example.com", episodes: ["l1"])
        let episode = try #require(show.episodes?.first)
        episode.audioURL = ""
        let fake = FakeAudioPlayback()
        let player = model(fake, context)

        player.toggle(episode)

        #expect(fake.commands.isEmpty)
        #expect(player.current == nil)
    }
}
