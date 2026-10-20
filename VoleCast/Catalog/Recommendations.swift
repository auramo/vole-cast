import Foundation
import SwiftData

/// The rules behind the suggestions. Pure, so every one of them can be checked
/// without a network, a store or a screen.
///
/// What is *not* here is the fetching: a section is assembled in
/// `RecommendationsModel`, which asks these questions and makes the requests
/// the answers imply.
enum Recommendations {

    /// Apple's root podcast genre. Every show carries it and it means nothing.
    static let rootGenreID = 26

    /// Which of your shows a suggestion should be drawn from, best first.
    ///
    /// Ranked by how many episodes you have played, falling back to how
    /// recently you subscribed — which is what orders the list before anything
    /// has been played at all. The fallback is the reason a section is titled
    /// "Like X" rather than "Because you listen to X": the second would be a
    /// lie on a fresh install.
    ///
    /// A show without an `itunesCollectionID` seeds nothing. It was added by
    /// pasting a feed URL, so Apple has no name for it — and a private feed
    /// must never be handed to Apple anyway, which is why pasted URLs are kept
    /// out of search too.
    static func seeds(
        from podcasts: [Podcast],
        playCounts: [PersistentIdentifier: Int],
        limit: Int
    ) -> [Podcast] {
        podcasts
            .filter { $0.itunesCollectionID != nil }
            .sorted { first, second in
                let firstPlays = playCounts[first.persistentModelID] ?? 0
                let secondPlays = playCounts[second.persistentModelID] ?? 0
                guard firstPlays == secondPlays else { return firstPlays > secondPlays }
                return first.subscribedAt > second.subscribedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The narrowest genre a show is filed under.
    ///
    /// Specificity is the whole value of this feature. Apple files The Daily
    /// under both News and Daily News; charting the first suggests whatever is
    /// most popular in the country, and charting the second suggests other
    /// daily news shows.
    ///
    /// "Narrowest" is read as "not one of the nineteen `PodcastGenre.all`
    /// shows in the picker, and not the root" — Apple does not mark which is
    /// which, and that negative is the only signal in the payload.
    static func subgenre(from genres: [PodcastGenre]) -> PodcastGenre? {
        let topLevel = Set(PodcastGenre.all.map(\.id))
        let usable = genres.filter { $0.id != rootGenreID }
        return usable.first { !topLevel.contains($0.id) } ?? usable.first
    }

    /// Chart entries worth showing. A chart gives a collection id and nothing
    /// else, so that is all there is to match on.
    static func surviving(
        _ entries: [ChartEntry],
        excludingCollectionIDs excluded: Set<Int>
    ) -> [ChartEntry] {
        entries.filter { !excluded.contains($0.collectionID) }
    }

    /// Search results worth showing.
    ///
    /// Two keys rather than one, because a show subscribed to by a pasted URL
    /// has no collection id on record: the feed identity is the only thing the
    /// store and the directory both know about it.
    static func surviving(
        _ results: [PodcastSearchResult],
        excludingCollectionIDs excludedIDs: Set<Int>,
        excludingIdentities excludedIdentities: Set<String>
    ) -> [PodcastSearchResult] {
        results.filter { result in
            if let id = result.itunesCollectionID, excludedIDs.contains(id) { return false }
            return !excludedIdentities.contains(FeedURL.identityKey(result.feedURL))
        }
    }
}
