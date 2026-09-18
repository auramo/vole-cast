import Foundation
import SwiftData

/// A show the user has subscribed to, plus the episodes known from its feed.
///
/// `feedIdentity` is the deduplication key: a lossier form of `feedURL` (see
/// `FeedURL.identityKey`) so the same show reached over `http`, `https` or with
/// a `www.` host counts as one subscription. It is enforced in
/// `Subscriptions.subscribe`, not by `@Attribute(.unique)`, because unique
/// constraints are unsupported under CloudKit mirroring — and the model is kept
/// CloudKit-shaped (every property defaulted, relationships optional with
/// inverses) in case sync is ever switched on. Enabling it would also mean a
/// dedupe pass at launch, since two devices could subscribe at the same time.
///
/// Playback state (position, played flag, downloads) is deliberately absent for
/// now. Those fields are additive and defaulted, so adding them later is a
/// schema addition rather than a migration.
@Model
final class Podcast {
    /// The URL actually fetched: normalised, and resolved through any redirect.
    var feedURL: String = ""
    /// Deduplication key derived from `feedURL`.
    var feedIdentity: String = ""
    var title: String = ""
    var author: String = ""
    /// Named `summary` rather than `description`: `@Model` types are
    /// NSObject-backed, where `description` is already taken.
    var summary: String = ""
    var artworkURL: String?
    var websiteURL: String?
    var language: String?
    /// Set when the show came from the iTunes directory; nil for a pasted URL.
    var itunesCollectionID: Int?
    var subscribedAt: Date = Date.now
    var lastRefreshedAt: Date?
    /// Newest episode date, denormalised so the library can sort and show
    /// recency without loading every episode.
    var lastEpisodeAt: Date?

    /// Cascade covers the episode rows. Once episodes can be downloaded, the
    /// audio files will need deleting separately — SwiftData won't do that.
    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodes: [Episode]? = []

    init(
        feedURL: String = "",
        feedIdentity: String = "",
        title: String = "",
        subscribedAt: Date = .now
    ) {
        self.feedURL = feedURL
        self.feedIdentity = feedIdentity
        self.title = title
        self.subscribedAt = subscribedAt
    }

    /// Newest first. Episodes with no date sort last rather than disappearing.
    var orderedEpisodes: [Episode] {
        (episodes ?? []).sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }

    var episodeCount: Int { (episodes ?? []).count }
}
