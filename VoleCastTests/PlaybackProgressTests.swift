import Testing
import Foundation
import SwiftData
@testable import VoleCast

@Suite(.serialized)
@MainActor
struct PlaybackProgressTests {

    private func makeEpisode(_ context: ModelContext, guid: String) -> Episode {
        let episode = Episode(guid: guid, title: "Episode \(guid)", audioURL: "https://x.example.com/\(guid).mp3")
        episode.duration = 1800
        context.insert(episode)
        return episode
    }

    // MARK: - Where to resume

    /// A few seconds in is indistinguishable from not having started, and
    /// resuming there just replays the intro.
    @Test func aPositionNearTheStartCountsAsUnstarted() {
        #expect(PlaybackProgress.resumePosition(stored: 0, duration: 1800, isPlayed: false) == 0)
        #expect(PlaybackProgress.resumePosition(stored: 2.9, duration: 1800, isPlayed: false) == 0)
    }

    @Test func aPositionInTheMiddleResumesThere() {
        #expect(PlaybackProgress.resumePosition(stored: 900, duration: 1800, isPlayed: false) == 900)
    }

    /// Reaching the end and pressing play again means "play it again", not
    /// "replay the last twelve seconds".
    @Test func aPositionNearTheEndStartsOver() {
        #expect(PlaybackProgress.resumePosition(stored: 1790, duration: 1800, isPlayed: false) == 0)
    }

    @Test func aPlayedEpisodeStartsOverWhereverItWasLeft() {
        #expect(PlaybackProgress.resumePosition(stored: 900, duration: 1800, isPlayed: true) == 0)
    }

    /// A feed can shorten an episode between refreshes, stranding a position
    /// past the new end.
    @Test func aPositionBeyondTheEndStartsOver() {
        #expect(PlaybackProgress.resumePosition(stored: 5000, duration: 1800, isPlayed: false) == 0)
    }

    /// Without a duration there is no "near the end" to test against, so the
    /// stored position is all there is to go on.
    @Test func withoutADurationTheStoredPositionStands() {
        #expect(PlaybackProgress.resumePosition(stored: 900, duration: nil, isPlayed: false) == 900)
    }

    @Test(arguments: [-5.0, .infinity, -.infinity, .nan])
    func refusesAStoredPositionThatCannotBeReal(_ stored: TimeInterval) {
        #expect(PlaybackProgress.resumePosition(stored: stored, duration: 1800, isPlayed: false) == 0)
    }

    // MARK: - Writing

    @Test func recordingAPositionStampsWhenItHappened() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-record")

        PlaybackProgress.record(position: 321, for: episode, in: context)

        #expect(episode.playbackPosition == 321)
        #expect(episode.lastPlayedAt != nil)
    }

    /// The two fields must never disagree: a played episode with a position
    /// left on it would resume mid-way and claim to be finished.
    @Test func markingPlayedAlsoClearsThePosition() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-played")
        PlaybackProgress.record(position: 900, for: episode, in: context)

        PlaybackProgress.markPlayed(episode, in: context)

        #expect(episode.isPlayed)
        #expect(episode.playbackPosition == 0)
    }

    @Test func markingUnplayedIsTheExactInverse() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-unplayed")
        PlaybackProgress.markPlayed(episode, in: context)

        PlaybackProgress.markUnplayed(episode, in: context)

        #expect(!episode.isPlayed)
        #expect(episode.playbackPosition == 0)
    }

    /// Starting is not progress. Writing a position here would, at best,
    /// overwrite a resume point with itself.
    @Test func markingStartedStampsTheTimeWithoutTouchingThePosition() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-started")
        episode.playbackPosition = 900

        PlaybackProgress.markStarted(episode, in: context)

        #expect(episode.lastPlayedAt != nil)
        #expect(episode.playbackPosition == 900)
    }

    /// Replaying something finished must not half-unfinish it.
    @Test func markingStartedLeavesAFinishedEpisodeFinished() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-restart")
        PlaybackProgress.markPlayed(episode, in: context)

        PlaybackProgress.markStarted(episode, in: context)

        #expect(episode.isPlayed)
        #expect(episode.playbackPosition == 0)
    }

    @Test func aFreshEpisodeHasNoPlaybackState() {
        let context = ModelContext(TestContainer.shared)
        let episode = makeEpisode(context, guid: "p-fresh")

        #expect(episode.playbackPosition == 0)
        #expect(!episode.isPlayed)
        #expect(episode.lastPlayedAt == nil)
    }

    // MARK: - Cadence

    /// Every write invalidates the @Query behind the Latest list, so position
    /// is written on a coarse grid rather than on every tick.
    @Test func decidesWhenAPositionIsWorthWriting() {
        #expect(!PlaybackProgress.shouldWrite(position: 4, lastWritten: 0))
        #expect(!PlaybackProgress.shouldWrite(position: 9.9, lastWritten: 0))
        #expect(PlaybackProgress.shouldWrite(position: 10, lastWritten: 0))
        #expect(PlaybackProgress.shouldWrite(position: 25, lastWritten: 10))
        // Seeking backwards is a move worth recording however small.
        #expect(PlaybackProgress.shouldWrite(position: 5, lastWritten: 100))
    }

    // MARK: - The fraction

    @Test func aPartPlayedEpisodeHasAFraction() {
        let half = PlaybackProgress.fraction(stored: 900, duration: 1800, isPlayed: false)

        #expect(half == 0.5)
    }

    /// The point of defining it through `resumePosition`: the bar is drawn
    /// exactly when tapping the row would carry on from somewhere. Each of
    /// these is a position that plays from the beginning, so each must show
    /// nothing rather than a mark contradicting what the tap does.
    @Test(arguments: [
        // Never started.
        (0.0, 1800.0, false),
        // So early that resuming would replay the intro.
        (2.9, 1800.0, false),
        // Finished.
        (900.0, 1800.0, true),
        // Within `nearEnd` of the end.
        (1790.0, 1800.0, false),
        // Stranded past an end a refresh moved.
        (2000.0, 1800.0, false),
    ])
    func somethingThatWouldStartOverShowsNothing(
        _ stored: Double, _ duration: Double, _ isPlayed: Bool
    ) {
        #expect(
            PlaybackProgress.fraction(
                stored: stored, duration: duration, isPlayed: isPlayed
            ) == nil
        )
    }

    /// Its own refusal, not inherited: `resumePosition` is happy to resume at
    /// a stored position for a feed that declared no duration, but there is no
    /// fraction to take of an unknown whole.
    @Test func withoutADurationThereIsNoFraction() {
        #expect(PlaybackProgress.fraction(stored: 900, duration: nil, isPlayed: false) == nil)
        #expect(PlaybackProgress.fraction(stored: 900, duration: 0, isPlayed: false) == nil)
    }

    /// The phone's ring trims a circle with it and the car's percentage
    /// multiplies it by a hundred, so a value outside 0...1 is a drawing bug
    /// in one and a nonsense reading in the other.
    @Test func theFractionStaysInRange() {
        for stored in [3.0, 100, 899, 1700] {
            let f = PlaybackProgress.fraction(stored: stored, duration: 1800, isPlayed: false)
            #expect(f.map { $0 > 0 && $0 <= 1 } ?? true)
        }
    }
}
