import Foundation

/// The "3 days ago · 42 min" line under an episode title, shared by the
/// preview, detail and episode screens so they can't drift apart.
enum EpisodeSubtitle {
    /// `locale` is a parameter only so tests can pin one. Both formats below
    /// follow the device otherwise, and both answer differently per language —
    /// "42m" in English, "42 min" in Finnish — so a test asserting on the
    /// English wording passes or fails according to where it is run.
    static func text(
        published: Date?,
        duration: TimeInterval?,
        locale: Locale = .current
    ) -> String {
        var parts: [String] = []
        if let published {
            parts.append(published.formatted(.relative(presentation: .named).locale(locale)))
        }
        if let duration, isFormattable(duration) {
            parts.append(
                Duration.seconds(duration)
                    .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
            )
        }
        return parts.joined(separator: " · ")
    }

    /// `Duration.seconds` traps rather than throws on a value it cannot fit in
    /// an Int128, so nothing implausible may reach it. `EpisodeDuration` already
    /// refuses these, but a duration also arrives here straight from the store,
    /// where one may have been written before the parser learned to.
    ///
    /// The bound is deliberately looser than the parser's — the formatter's job
    /// is only to be total, not to judge what counts as an episode.
    private static func isFormattable(_ duration: TimeInterval) -> Bool {
        duration > 0 && duration.isFinite && duration < 1e9
    }
}
