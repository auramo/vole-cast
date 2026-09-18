import Foundation

/// Parsing `itunes:duration`, which the spec allows in three shapes —
/// `3600`, `56:12` and `01:02:03` — and which feeds also write with stray
/// whitespace or fractional seconds.
enum EpisodeDuration {

    static func seconds(from raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }

        var total: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0 else { return nil }
            // Only the last component may be fractional, and only the first may
            // exceed its usual range (a 90-minute show can say "90:00").
            if index < parts.count - 1, value != value.rounded(.down) { return nil }
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total > 0 ? total : nil
    }
}
