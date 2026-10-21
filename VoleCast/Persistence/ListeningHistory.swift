import Foundation
import SwiftData

/// The "what have I been listening to" query.
///
/// Finished and part-played episodes both belong here — the list is what you
/// played, not what you completed. Unlike `LatestEpisodes` it does not require
/// a publish date: that list can't place an undated episode on a "newest first"
/// ordering, where this one sorts on when you played it and has a perfectly
/// good spot for it.
///
/// One limitation, by construction rather than by choice: unsubscribing from a
/// show cascades its episodes away, and they leave History with them. Outliving
/// that would need play events recorded separately from the episodes they point
/// at, which is a schema of its own.
enum ListeningHistory {
    static let defaultLimit = 100

    /// The definition of "played", shared with `ListeningTotals`. One
    /// predicate rather than two copies of it: this project has already
    /// shipped the same threshold under two names once, and a predicate is
    /// easier to fork by accident than a number is.
    ///
    /// `lastPlayedAt` is the only marker that anything was played, and an
    /// orphan with no show has neither a name nor artwork to show.
    static let playedPredicate = #Predicate<Episode> {
        $0.lastPlayedAt != nil && $0.podcast != nil
    }

    static func descriptor(limit: Int = defaultLimit) -> FetchDescriptor<Episode> {
        var descriptor = FetchDescriptor<Episode>(
            predicate: playedPredicate,
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
