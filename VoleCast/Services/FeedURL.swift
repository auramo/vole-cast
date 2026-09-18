import Foundation

/// Turning whatever the user (or a directory) hands us into a feed URL, and
/// into a stable identity for deciding whether we already have that show.
enum FeedURL {

    /// The URL we will actually fetch, or nil when the input cannot be one.
    ///
    /// Normalisation stays conservative: everything it changes is defined to be
    /// case-insensitive or redundant in HTTP. In particular the query string is
    /// kept verbatim, because private feeds (Patreon, Supercast, Apple
    /// subscriptions) carry a per-user token there and rewriting it breaks them.
    static func normalize(_ raw: String) -> URL? {
        var text = unwrap(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return nil }

        text = rewritingPodcastScheme(text)
        guard !hasForeignScheme(text) else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        // A trailing dot is the DNS root and is legal, but nobody means it.
        if host.hasSuffix(".") { host.removeLast() }
        guard host.contains(".") else { return nil }

        components.scheme = scheme
        components.host = host
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.fragment = nil
        if components.path.isEmpty { components.path = "/" }

        return components.url
    }

    /// The deduplication key for a normalised URL — deliberately lossier than
    /// the URL itself, so `http://www.example.com/feed/` and
    /// `https://example.com/feed` are recognised as the same show.
    static func identityKey(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        var host = components.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }

        var key = host + path
        if let items = components.queryItems, !items.isEmpty {
            // Order is not meaningful to a server, so it must not be to us.
            let sorted = items
                .map { ($0.name, $0.value ?? "") }
                .sorted { $0 < $1 }
                .map { $0.1.isEmpty ? $0.0 : "\($0.0)=\($0.1)" }
            key += "?" + sorted.joined(separator: "&")
        }
        return key
    }

    /// Convenience for the common "normalise, then key it" pair.
    static func identityKey(for raw: String) -> String? {
        normalize(raw).map(identityKey)
    }

    /// True for a scheme we can't fetch, such as `mailto:`.
    ///
    /// Worth catching before the missing-scheme branch below, because prepending
    /// `https://` to `mailto:someone@example.com` yields a URL that parses
    /// perfectly well — as userinfo on the host `example.com`.
    private static func hasForeignScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let candidate = text[text.startIndex..<colon]
        guard let first = candidate.first, first.isLetter,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) })
        else { return false }
        // `example.com:8080/feed` is a host and port, not a scheme.
        if text[text.index(after: colon)...].first?.isNumber == true { return false }
        let scheme = candidate.lowercased()
        return scheme != "http" && scheme != "https"
    }

    /// People paste feed URLs out of HTML source and chat apps, which wrap them.
    private static func unwrap(_ text: String) -> String {
        var text = text
        while text.count >= 2, let first = text.first, let last = text.last,
              (first == "<" && last == ">")
                || (first == "\"" && last == "\"")
                || (first == "'" && last == "'") {
            text = String(text.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// `feed://`, `itpc://` and `pcast://` are podcast-client conventions for
    /// "this is a feed"; underneath they are ordinary HTTP URLs. `feed:` can
    /// also prefix a complete URL, as in `feed:https://example.com/rss`.
    private static func rewritingPodcastScheme(_ text: String) -> String {
        let lowercased = text.lowercased()
        for scheme in ["feed", "itpc", "pcast", "podcast"] {
            if lowercased.hasPrefix(scheme + "://") {
                return "https://" + String(text.dropFirst(scheme.count + 3))
            }
            if lowercased.hasPrefix(scheme + ":") {
                let rest = String(text.dropFirst(scheme.count + 1))
                return rest.lowercased().hasPrefix("http") ? rest : "https://" + rest
            }
        }
        return text
    }
}
