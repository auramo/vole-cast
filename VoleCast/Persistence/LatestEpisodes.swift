import Foundation
import SwiftData

/// The "what's new across everything I subscribe to" query.
///
/// A fetch descriptor rather than logic in the view: it can be tested against a
/// real store, and the limit is applied by the store instead of by fetching
/// every episode and throwing most of them away.
enum LatestEpisodes {
    static let defaultLimit = 20

    static func descriptor(limit: Int = defaultLimit) -> FetchDescriptor<Episode> {
        var descriptor = FetchDescriptor<Episode>(
            // Undated episodes can't be placed on a "newest first" list, and an
            // orphan with no show would have nothing to attribute it to.
            // Finished episodes have stopped being new — they live in
            // `ListeningHistory` now. Part-played ones stay: they're still
            // waiting for you.
            predicate: #Predicate {
                $0.publishedAt != nil && $0.podcast != nil && $0.isPlayed == false
            },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
