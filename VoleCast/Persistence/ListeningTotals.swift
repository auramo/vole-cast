import Foundation
import OSLog
import SwiftData

/// How many episodes of each show have been played.
///
/// Sibling of `ListeningHistory`, and deliberately not the same query. That
/// one answers "what have I been listening to" for a screen, newest first and
/// capped at a hundred rows. This one answers "how much of each show" and
/// takes no limit: a seed ranking drawn from the last hundred episodes would
/// forget a show you listened to heavily a year ago.
enum ListeningTotals {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "listeningTotals"
    )

    /// Keyed by the show's identifier. A show with nothing played is absent
    /// rather than zero, which is the distinction the ranking rests on.
    static func playCounts(in context: ModelContext) -> [PersistentIdentifier: Int] {
        // `ListeningHistory.playedPredicate`: the same definition of
        // "played", not a second copy of it — see its doc comment for why.
        let descriptor = FetchDescriptor<Episode>(
            predicate: ListeningHistory.playedPredicate
        )

        // A fetch failure here must not be able to pass for "nothing has ever
        // been played": that's the same absent-rather-than-zero shape the
        // doc comment above describes as meaningful, so silently swallowing
        // the error would make a store problem look like a ranking answer.
        // Still, this is a ranking input, not the screen itself — it should
        // cost you suggestions, not take anything down, so we log and
        // degrade to empty rather than throw.
        let played: [Episode]
        do {
            played = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch played episodes: \(error)")
            played = []
        }

        return played.reduce(into: [:]) { counts, episode in
            guard let show = episode.podcast?.persistentModelID else { return }
            counts[show, default: 0] += 1
        }
    }
}
