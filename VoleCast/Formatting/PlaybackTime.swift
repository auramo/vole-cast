import Foundation

/// Clock readings for the player: `7:03`, `1:12:44`, `-45:12`.
///
/// Separate from `EpisodeSubtitle`, which says "42 min" — that answers "how
/// long is this?", where these answer "where am I?". Different jobs, different
/// shapes.
enum PlaybackTime {

    /// Shown wherever there is no answer yet — an unresolved duration, or a
    /// value a feed made up. Same width as a short clock so nothing jumps.
    static let placeholder = "--:--"

    /// Beyond this a value is a feed bug rather than a position, and formatting
    /// it would print an absurd hour count.
    private static let maxSeconds: TimeInterval = 359_999  // 99:59:59

    static func clock(_ seconds: TimeInterval) -> String {
        guard let whole = wholeSeconds(seconds) else { return placeholder }

        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// How much is left, as the player shows it on the right of a scrubber.
    static func remaining(_ seconds: TimeInterval) -> String {
        guard wholeSeconds(seconds) != nil else { return placeholder }
        return "-" + clock(seconds)
    }

    /// Truncates rather than rounds: reading 1:03 while the player sits at
    /// 1:03.9 is behind by less than a second, where 1:04 is ahead of it.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds >= 0, seconds <= maxSeconds else { return nil }
        return Int(seconds)
    }
}
