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
    /// The "3 days ago · 42 min" line, from `EpisodeSubtitle`, so the car says
    /// the same thing about an episode as the phone does.
    let subtitle: String
    /// Marks the episode the player is holding, so it is visibly the one the
    /// car is on.
    let isPlaying: Bool
}

/// What selecting a row should do.
enum CarPlaySelection: Equatable {
    case playThenShowPlayer
    case showPlayer
}

/// The rules behind the car's Latest list. Pure, so they can be checked
/// without a car, a template or an interface controller.
enum CarPlayLatestList {
    static func rows(
        for episodes: [Episode],
        current: PersistentIdentifier?
    ) -> [CarPlayRow] {
        episodes.map { episode in
            CarPlayRow(
                id: episode.persistentModelID,
                title: episode.title,
                subtitle: EpisodeSubtitle.text(
                    published: episode.publishedAt,
                    duration: episode.duration
                ),
                isPlaying: episode.persistentModelID == current
            )
        }
    }

    /// Selecting the episode already loaded must not disturb it. On connect it
    /// sits in the list part-listened, and a tap there means "take me to the
    /// player" — not "start again", and not `toggle(_:)`, which would pause an
    /// episode that is playing.
    static func selection(isCurrent: Bool) -> CarPlaySelection {
        isCurrent ? .showPlayer : .playThenShowPlayer
    }
}
