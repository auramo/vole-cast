import Foundation

/// Parsing the `pubDate` of a feed item.
///
/// RSS specifies RFC 822 dates, and real feeds interpret that generously: some
/// omit the weekday, some use a numeric offset, some append `(GMT)`, some give
/// ISO 8601 instead. So this tries a list rather than trusting one format. A
/// date that defeats the whole list yields nil and the episode still imports —
/// losing an episode over a typo in its timestamp would be worse.
enum RSSDate {

    static func parse(_ raw: String) -> Date? {
        let cleaned = clean(raw)
        guard !cleaned.isEmpty else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: cleaned) { return date }
        }
        for formatter in isoFormatters {
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    /// Collapse runs of whitespace and drop a trailing zone comment such as
    /// `Mon, 1 Sep 2025 07:00:00 +0300 (EEST)`.
    private static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.lastIndex(of: "("), text.hasSuffix(")") {
            text = String(text[text.startIndex..<open])
        }
        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.joined(separator: " ")
    }

    // Shared rather than built per call: `DateFormatter` is documented as
    // thread-safe for parsing once configured, and these are configured here
    // and never mutated again. Building nine of them per episode would be real
    // cost across a few hundred episodes.
    private static let formatters: [DateFormatter] = [
        // Single `d`/`H` patterns accept zero-padded input too.
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm zzz",
        "EEE, d MMM yyyy HH:mm:ss",
        "EEE, d MMM yyyy HH:mm",
        "d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Feeds that omit the zone mean UTC far more often than device-local.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    // Unlike `DateFormatter`, `ISO8601DateFormatter` isn't marked `Sendable`,
    // though it is equally safe to share for parsing once configured.
    nonisolated(unsafe) private static let isoFormatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()
}
