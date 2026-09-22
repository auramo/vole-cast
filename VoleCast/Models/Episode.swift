import Foundation
import SwiftData

/// One episode of a subscribed show.
///
/// `guid` is the feed's own identity for the episode and is never empty — the
/// parser falls back through enclosure URL, page link and title+date. Refreshes
/// merge on it, which is what the playback state below hangs off: an episode
/// that falls out of the feed keeps its position rather than being discarded.
@Model
final class Episode {
    var guid: String = ""
    var title: String = ""
    var summary: String = ""
    var publishedAt: Date?
    /// The enclosure URL. An item without one is not an episode and is dropped
    /// at parse time, so this is always populated in practice.
    var audioURL: String = ""
    var audioMIMEType: String?
    var audioByteCount: Int?
    /// Seconds. `Double` so it maps straight onto `TimeInterval` for playback.
    var duration: Double?
    /// Episode-specific artwork, when the feed provides it; else the show's.
    var artworkURL: String?
    var pageURL: String?

    // Playback state. Defaulted and optional like everything else here, so this
    // was a schema addition rather than a migration. `PlaybackProgress` is the
    // only thing that writes these.

    /// Seconds in. 0 means "not started", which is also where a finished
    /// episode is reset to, so the two can never disagree.
    var playbackPosition: Double = 0
    var isPlayed: Bool = false
    var lastPlayedAt: Date?

    var podcast: Podcast?

    init(
        guid: String = "",
        title: String = "",
        audioURL: String = "",
        publishedAt: Date? = nil
    ) {
        self.guid = guid
        self.title = title
        self.audioURL = audioURL
        self.publishedAt = publishedAt
    }
}
