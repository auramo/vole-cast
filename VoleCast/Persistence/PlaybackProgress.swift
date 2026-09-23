import Foundation
import SwiftData

/// Everything that writes playback state to the store, so the rules have one
/// home and the views stay free of persistence logic — the same arrangement as
/// `Subscriptions`.
@MainActor
enum PlaybackProgress {

    /// Below this, resuming would just replay the intro.
    static let nearStart: TimeInterval = 3
    /// Within this of the end, the episode counts as finished.
    static let nearEnd: TimeInterval = 15
    /// How far playback must move before a position is written again.
    ///
    /// Deliberately coarse. `LatestEpisodesView` is driven by a `@Query`, and
    /// every write to an episode in its results invalidates that query and
    /// re-renders the list; once a second would be visible churn while someone
    /// is just browsing. Live progress in the UI comes from `PlayerModel`, not
    /// from the store, so writing rarely costs nothing on screen.
    static let writeInterval: TimeInterval = 10

    // MARK: - Rules

    /// Where playing this episode should actually start.
    ///
    /// Pure, so the rules can be checked without a store.
    static func resumePosition(
        stored: TimeInterval,
        duration: TimeInterval?,
        isPlayed: Bool
    ) -> TimeInterval {
        guard !isPlayed, stored.isFinite, stored >= nearStart else { return 0 }
        guard let duration, duration > 0 else { return stored }
        // Finished, or stranded past an end that a refresh moved.
        guard stored <= duration - nearEnd else { return 0 }
        return stored
    }

    /// Whether a position has moved far enough to be worth a write.
    ///
    /// Any backwards move counts however small: that is a seek, and losing it
    /// would send the listener back to where they had just left.
    static func shouldWrite(position: TimeInterval, lastWritten: TimeInterval) -> Bool {
        guard position.isFinite else { return false }
        if position < lastWritten { return true }
        return position - lastWritten >= writeInterval
    }

    // MARK: - Writes

    static func record(position: TimeInterval, for episode: Episode, in context: ModelContext) {
        guard position.isFinite, position >= 0 else { return }
        episode.playbackPosition = position
        episode.lastPlayedAt = .now
    }

    /// An episode joins the listening history the moment audio actually flows,
    /// rather than when its position first crosses `writeInterval`. "I started
    /// this" is the event worth recording, and waiting ten seconds for it would
    /// lose every short listen — which is most of the ones you want to find
    /// again.
    ///
    /// The position is deliberately untouched: starting is not progress, and
    /// writing one here would overwrite a resume point with itself at best.
    static func markStarted(_ episode: Episode, in context: ModelContext) {
        episode.lastPlayedAt = .now
    }

    static func markPlayed(_ episode: Episode, in context: ModelContext) {
        episode.isPlayed = true
        // Zeroed together, so a replay starts clean and the fields cannot
        // contradict each other.
        episode.playbackPosition = 0
        episode.lastPlayedAt = .now
    }

    /// Note what this does *not* do: `lastPlayedAt` is left alone, so the
    /// episode stays in the listening history. That is deliberate — you did
    /// play it — but it is the decision to revisit if a "Mark as Unplayed"
    /// action ever ships and people expect it to forget the episode entirely.
    static func markUnplayed(_ episode: Episode, in context: ModelContext) {
        episode.isPlayed = false
        episode.playbackPosition = 0
    }

    /// The one place in the app that saves explicitly.
    ///
    /// Everywhere else relies on autosave, which is fine when the app is on
    /// screen. Background audio breaks that assumption: the app can be
    /// suspended while playing and killed later without another pass of the
    /// main runloop, taking the last few seconds of position with it. Called
    /// only when the scene leaves `.active`, and on interruption.
    static func flush(in context: ModelContext) {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
