import Foundation
import SwiftData

/// One row of the car's episode list.
///
/// A value rather than a `CPListItem`, for the reason `Playback/` speaks in
/// `PlayableEpisode`: the rules stay testable without the framework, and the
/// identifier is carried instead of the model, so nothing here can trap by
/// reading an `Episode` that unsubscribing has already deleted.
struct CarPlayRow: Equatable, Identifiable {
    let id: PersistentIdentifier
    let title: String
    /// The "ev.news · 3 days ago · 42 min" line.
    let subtitle: String
    /// Marks the episode the player is holding, so it is visibly the one the
    /// car is on.
    let isPlaying: Bool
    /// The episode's own picture when the feed gave it one, the show's
    /// otherwise — the same rule the phone's row follows. A string rather than
    /// a `URL` because that is how the models hold it, and resolving it is the
    /// scene's job, not this one's.
    let artworkURL: String?
    /// How far through, 0...1, or nil for a row with nothing to show — which
    /// `CPListItem` draws as the system's own bar under the row, the same mark
    /// every other car audio app uses.
    let progress: Double?
}

/// A titled group of rows. `title` is nil for a list that needs no heading.
struct CarPlaySection: Equatable {
    let title: String?
    let rows: [CarPlayRow]
}

/// What selecting a row should do.
enum CarPlaySelection: Equatable {
    case playThenShowPlayer
    case resumeThenShowPlayer
    case showPlayer
}

/// The rules behind the car's list. Pure, so they can be checked without a
/// car, a template or an interface controller.
enum CarPlayLatestList {
    static let continueTitle = "Continue"
    static let latestTitle = "Latest"

    /// The whole list: what you were in the middle of, then what is new.
    ///
    /// The current episode is given a row of its own rather than being left to
    /// its place in Latest. Two reasons, both learned from the car. CarPlay
    /// offers no route to the player from a list of its own; and the system's
    /// Now Playing screen stays empty until the app owns the audio session,
    /// which an episode restored at launch has never done — so it is invisible
    /// there. A restored episode may also be older than the twenty newest and
    /// have no row in Latest at all.
    static func sections(
        current: Episode?,
        at position: TimeInterval,
        latest: [Episode]
    ) -> [CarPlaySection] {
        guard let current else {
            // Still titled with nothing playing: the template above carries no
            // title, so this is the only thing naming the list.
            return [CarPlaySection(title: latestTitle, rows: rows(for: latest, current: nil))]
        }

        let id = current.persistentModelID
        return [
            CarPlaySection(
                title: continueTitle,
                rows: [
                    CarPlayRow(
                        id: id,
                        title: current.title,
                        subtitle: detail(for: current, at: position),
                        isPlaying: true,
                        artworkURL: artwork(for: current),
                        // The player's reading rather than the stored one, for
                        // the reason the phone's ring uses it: positions are
                        // written to the store every ten seconds, so the bar
                        // would otherwise sit behind the clock printed beside
                        // it in this very row.
                        progress: PlaybackProgress.fraction(
                            stored: position,
                            duration: current.duration,
                            isPlayed: current.isPlayed
                        )
                    )
                ]
            ),
            // One episode, one row: the same one in both sections would be two
            // things to read and two places to tap for one outcome.
            CarPlaySection(
                title: latestTitle,
                rows: rows(for: latest.filter { $0.persistentModelID != id }, current: nil)
            ),
        ]
    }

    static func rows(
        for episodes: [Episode],
        current: PersistentIdentifier?
    ) -> [CarPlayRow] {
        episodes.map { episode in
            CarPlayRow(
                id: episode.persistentModelID,
                title: episode.title,
                subtitle: detail(for: episode, at: nil),
                isPlaying: episode.persistentModelID == current,
                artworkURL: artwork(for: episode),
                progress: progress(for: episode)
            )
        }
    }

    /// One place, like `artwork`, so the Continue row and the Latest ones
    /// cannot drift apart.
    private static func progress(for episode: Episode) -> Double? {
        PlaybackProgress.fraction(
            stored: episode.playbackPosition,
            duration: episode.duration,
            isPlayed: episode.isPlayed
        )
    }

    /// One place, so the Continue row cannot drift from the Latest ones.
    private static func artwork(for episode: Episode) -> String? {
        episode.artworkURL ?? episode.podcast?.artworkURL
    }

    /// Tapping a row means "play this". For the episode already playing that
    /// would be a pause, which is not what a row means — `toggle` is wrong
    /// here. For the one loaded but paused, which is what the Continue row
    /// usually holds, it means carry on from where it was left.
    static func selection(isCurrent: Bool, isPlaying: Bool) -> CarPlaySelection {
        guard isCurrent else { return .playThenShowPlayer }
        return isPlaying ? .showPlayer : .resumeThenShowPlayer
    }

    /// A `CPListItem` has two lines where the phone's row has three, so the
    /// show shares the second one with the date and duration. Without it the
    /// car lists a column of episode titles and no sign of which show any of
    /// them came from.
    private static func detail(for episode: Episode, at position: TimeInterval?) -> String {
        var parts = [
            episode.podcast?.title,
            EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration),
        ]
        // `nearStart` rather than a second constant saying 3: "0:00" is
        // noise for the same reason resuming there would just replay the
        // intro, and this row's bar is already drawn by that rule.
        if let position, position >= PlaybackProgress.nearStart {
            parts.append(PlaybackTime.clock(position))
        }
        // Same separator `EpisodeSubtitle` uses internally, and the same
        // reason for dropping empties: an orphan or an undated episode must
        // not be given a stray one.
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
