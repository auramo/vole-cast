import Foundation
import SwiftData

/// One show's episodes, newest first, optionally narrowed by a title search.
///
/// A descriptor rather than sorting the relationship in the view, for the same
/// reason as `LatestEpisodes`: the store does the work once, instead of the
/// view re-sorting every episode each time it draws. That mattered little at a
/// few dozen episodes and matters a lot now a show can hold two thousand — the
/// old `orderedEpisodes` sorted the lot on every render, including the ones
/// caused by a playback position being written mid-episode.
///
/// Searching belongs here too, for the same reason: SQLite narrows two
/// thousand rows more happily than an array comprehension in a view body.
enum ShowEpisodes {

    /// Scoped by `feedIdentity` rather than the relationship: a predicate that
    /// walks to the related object and compares a value of it is something the
    /// store can run, where comparing model references is not.
    static func descriptor(
        feedIdentity: String,
        matching search: String = ""
    ) -> FetchDescriptor<Episode> {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = [SortDescriptor(\Episode.publishedAt, order: .reverse)]

        // An empty field is not a filter. Folding it into one predicate with a
        // `term.isEmpty ||` would make the store test it per row for nothing.
        guard !term.isEmpty else {
            return FetchDescriptor<Episode>(
                predicate: #Predicate { $0.podcast?.feedIdentity == feedIdentity },
                sortBy: sort
            )
        }

        return FetchDescriptor<Episode>(
            predicate: #Predicate {
                $0.podcast?.feedIdentity == feedIdentity
                    && $0.title.localizedStandardContains(term)
            },
            sortBy: sort
        )
    }
}
