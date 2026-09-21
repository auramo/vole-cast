import Foundation

/// Parsing `itunes:duration`, which the spec allows in three shapes —
/// `3600`, `56:12` and `01:02:03` — and which feeds also write with stray
/// whitespace or fractional seconds.
enum EpisodeDuration {

    /// Past this, a value is a feed bug or an attack rather than an episode.
    /// Generous on purpose — 24-hour charity streams and unabridged audiobook
    /// chapters are real — but far below the point where `Duration.seconds`
    /// overflows its internal Int128 and traps.
    static let maxSeconds: TimeInterval = 7 * 24 * 60 * 60

    static func seconds(from raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }

        var total: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            // `Double` accepts "inf", "infinity" and "1e400", and infinity
            // passes a bare `>= 0`. Reject it here rather than let it reach a
            // formatter that traps on it.
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            // Only the last component may be fractional, and only the first may
            // exceed its usual range (a 90-minute show can say "90:00").
            if index < parts.count - 1, value != value.rounded(.down) { return nil }
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        // The accumulation can reach infinity even from finite parts, so the
        // ceiling is checked on the total rather than on each component.
        return total > 0 && total <= maxSeconds ? total : nil
    }
}
