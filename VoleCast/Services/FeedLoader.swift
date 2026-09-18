import Foundation

/// The result of fetching a feed: what was parsed, and the URL it really lives
/// at once redirects and `itunes:new-feed-url` have had their say.
struct LoadedFeed: Equatable, Sendable {
    var feed: ParsedFeed
    var resolvedURL: URL

    var identityKey: String { FeedURL.identityKey(resolvedURL) }
}

protocol FeedLoading: Sendable {
    func load(_ url: URL, revalidating: Bool) async throws -> LoadedFeed
}

extension FeedLoading {
    func load(_ url: URL) async throws -> LoadedFeed {
        try await load(url, revalidating: false)
    }
}

/// Fetches a feed and parses it, off the main actor.
struct FeedLoader: FeedLoading {
    let http: any HTTPClient
    var maxEpisodes: Int = 300

    init(http: any HTTPClient = URLSessionHTTPClient(), maxEpisodes: Int = 300) {
        self.http = http
        self.maxEpisodes = maxEpisodes
    }

    func load(_ url: URL, revalidating: Bool = false) async throws -> LoadedFeed {
        do {
            return try await fetchAndParse(url, revalidating: revalidating)
        } catch NetworkError.insecureConnection {
            // ATS blocks plain http. Plenty of feeds are listed as http but
            // serve https perfectly well, so try that before giving up.
            guard let secure = httpsVariant(of: url) else { throw NetworkError.insecureConnection }
            return try await fetchAndParse(secure, revalidating: revalidating)
        }
    }

    private func fetchAndParse(_ url: URL, revalidating: Bool) async throws -> LoadedFeed {
        var request = URLRequest(url: url)
        if revalidating { request.cachePolicy = .reloadRevalidatingCacheData }

        let (data, response) = try await http.data(
            for: request,
            maxBytes: AppURLSession.feedByteLimit
        )

        // Parsing is synchronous and CPU-bound; only Sendable values cross.
        let parsed = try await Task.detached(priority: .userInitiated) {
            try FeedParser.parse(data, maxEpisodes: maxEpisodes)
        }.value

        // Identity follows the feed: a redirect or a declared move means this
        // is the same show at a new address, not a second subscription.
        let redirected = response.url ?? url
        let resolved = parsed.newFeedURL.flatMap(FeedURL.normalize) ?? redirected
        return LoadedFeed(feed: parsed, resolvedURL: resolved)
    }

    private func httpsVariant(of url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "https"
        return components.url
    }
}
