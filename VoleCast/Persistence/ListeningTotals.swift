import Foundation
import SwiftData

/// How many episodes of each show have been played.
///
/// Sibling of `ListeningHistory`, and deliberately not the same query. That
/// one answers "what have I been listening to" for a screen, newest first and
/// capped at a hundred rows. This one answers "how much of each show" and
/// takes no limit: a seed ranking drawn from the last hundred episodes would
/// forget a show you listened to heavily a year ago.
enum ListeningTotals {

    /// Keyed by the show's identifier. A show with nothing played is absent
    /// rather than zero, which is the distinction the ranking rests on.
    static func playCounts(in context: ModelContext) -> [PersistentIdentifier: Int] {
        // The same marker `ListeningHistory` uses: `lastPlayedAt` is the only
        // thing that says an episode was ever played.
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.lastPlayedAt != nil && $0.podcast != nil }
        )
        let played = (try? context.fetch(descriptor)) ?? []

        return played.reduce(into: [:]) { counts, episode in
            guard let show = episode.podcast?.persistentModelID else { return }
            counts[show, default: 0] += 1
        }
    }
}
