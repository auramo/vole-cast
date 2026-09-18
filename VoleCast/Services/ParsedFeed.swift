import Foundation

/// A feed as read off the wire, before anything is stored.
///
/// Value types on purpose: previewing a show parses a feed and shows it without
/// touching SwiftData, and only subscribing turns one of these into a `Podcast`.
struct ParsedFeed: Equatable, Sendable {
    var title: String = ""
    var author: String = ""
    var summary: String = ""
    var artworkURL: String?
    var websiteURL: String?
    var language: String?
    /// `itunes:new-feed-url` — the feed telling us it has moved. Used for
    /// identity, so a move doesn't read as a second subscription.
    var newFeedURL: String?
    var episodes: [ParsedEpisode] = []
}

struct ParsedEpisode: Equatable, Sendable {
    var guid: String = ""
    var title: String = ""
    var summary: String = ""
    var publishedAt: Date?
    var audioURL: String = ""
    var audioMIMEType: String?
    var audioByteCount: Int?
    var duration: TimeInterval?
    var artworkURL: String?
    var pageURL: String?
}
