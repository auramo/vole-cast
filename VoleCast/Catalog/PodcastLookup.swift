import Foundation

/// Turning an iTunes collection id into something that can actually be
/// subscribed to.
///
/// Separate from `PodcastDirectory` rather than another method on it: a
/// directory that is not Apple's — Podcast Index, say — has no notion of a
/// collection id and would have nothing to implement. This exists because
/// charts identify shows by id and by nothing else.
protocol PodcastLookup: Sendable {
    /// `nil` when Apple has no public feed for that id: a show exclusive to
    /// Apple Podcasts, or an id that no longer exists.
    ///
    /// Deliberately not an error. Nothing has gone wrong, there is simply
    /// nothing to subscribe to, and the difference matters at the other end —
    /// an error gets a "Try Again" button, and retrying a show that will never
    /// have a feed is a promise the app cannot keep.
    func podcast(collectionID: Int) async throws -> PodcastSearchResult?
}
