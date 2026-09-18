import Foundation
import SwiftData

enum SubscriptionError: Error, Equatable {
    case alreadySubscribed
}

/// Everything that writes subscriptions to the store lives here, so the views
/// stay free of persistence logic and the rules have one home.
@MainActor
enum Subscriptions {

    /// The subscription for a feed identity, if there is one.
    ///
    /// Identity rather than the raw URL: the same show reached over `http`,
    /// with `www.`, or after a redirect must count as one subscription. See
    /// `FeedURL.identityKey`.
    static func existing(identity: String, in context: ModelContext) -> Podcast? {
        var descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate { $0.feedIdentity == identity }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Subscribes to a freshly loaded feed.
    ///
    /// Throws `SubscriptionError.alreadySubscribed` rather than inserting a
    /// duplicate — uniqueness is enforced here because `@Attribute(.unique)` is
    /// unsupported under CloudKit mirroring, which the model stays ready for.
    @discardableResult
    static func subscribe(
        to loaded: LoadedFeed,
        directoryResult: PodcastSearchResult? = nil,
        in context: ModelContext
    ) throws -> Podcast {
        let identity = loaded.identityKey
        guard existing(identity: identity, in: context) == nil else {
            throw SubscriptionError.alreadySubscribed
        }

        let podcast = Podcast(
            feedURL: loaded.resolvedURL.absoluteString,
            feedIdentity: identity,
            title: loaded.feed.title
        )
        podcast.itunesCollectionID = directoryResult?.itunesCollectionID
        context.insert(podcast)
        apply(loaded.feed, to: podcast, fallback: directoryResult)
        merge(loaded.feed.episodes, into: podcast, in: context)
        return podcast
    }

    static func unsubscribe(_ podcast: Podcast, in context: ModelContext) {
        // Episodes go with it by cascade. Downloaded audio will need deleting
        // here too, once downloads exist.
        context.delete(podcast)
    }

    /// Folds a re-fetched feed into an existing subscription.
    static func refresh(_ loaded: LoadedFeed, into podcast: Podcast, in context: ModelContext) {
        // A feed that has moved keeps its subscription, at its new address.
        podcast.feedURL = loaded.resolvedURL.absoluteString
        podcast.feedIdentity = loaded.identityKey
        apply(loaded.feed, to: podcast, fallback: nil)
        merge(loaded.feed.episodes, into: podcast, in: context)
        podcast.lastRefreshedAt = .now
    }

    /// Copies show metadata over, preferring what the feed says. A directory
    /// result fills gaps only — the feed is the authority on its own show.
    private static func apply(
        _ feed: ParsedFeed,
        to podcast: Podcast,
        fallback: PodcastSearchResult?
    ) {
        podcast.title = feed.title.isEmpty ? (fallback?.title ?? podcast.title) : feed.title
        podcast.author = feed.author.isEmpty ? (fallback?.author ?? podcast.author) : feed.author
        podcast.summary = feed.summary
        podcast.artworkURL = feed.artworkURL ?? fallback?.artworkURL?.absoluteString
        podcast.websiteURL = feed.websiteURL
        podcast.language = feed.language
    }

    /// Matches on `guid`, so an edited episode is updated in place rather than
    /// duplicated. Episodes that have fallen off the end of the feed are kept:
    /// dropping them would one day discard playback state and downloads.
    private static func merge(
        _ parsed: [ParsedEpisode],
        into podcast: Podcast,
        in context: ModelContext
    ) {
        var byGUID = Dictionary(
            (podcast.episodes ?? []).map { ($0.guid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for incoming in parsed {
            let episode = byGUID[incoming.guid] ?? {
                let new = Episode(guid: incoming.guid)
                new.podcast = podcast
                context.insert(new)
                byGUID[incoming.guid] = new
                return new
            }()

            episode.title = incoming.title
            episode.summary = incoming.summary
            episode.publishedAt = incoming.publishedAt
            episode.audioURL = incoming.audioURL
            episode.audioMIMEType = incoming.audioMIMEType
            episode.audioByteCount = incoming.audioByteCount
            episode.duration = incoming.duration
            episode.artworkURL = incoming.artworkURL
            episode.pageURL = incoming.pageURL
        }

        podcast.lastEpisodeAt = (podcast.episodes ?? [])
            .compactMap(\.publishedAt)
            .max()
        podcast.lastRefreshedAt = .now
    }
}
