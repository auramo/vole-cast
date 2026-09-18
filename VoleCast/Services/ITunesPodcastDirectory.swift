import Foundation

/// Search backed by Apple's iTunes Search API.
///
/// Chosen because it needs no API key — a clone of this repo builds and
/// searches with nothing to configure — and because its rate limit applies per
/// device rather than per app.
///
/// Two behaviours worth knowing when reading the UI code:
///  - It never reports "no matches". A term it doesn't recognise comes back as
///    a handful of loosely related shows, so results are presented as
///    suggestions, and pasting a feed URL stays a first-class path.
///  - Throttling arrives as HTTP 403, mapped to `.rateLimited` in `HTTPClient`.
struct ITunesPodcastDirectory: PodcastDirectory {
    let http: any HTTPClient
    /// Storefront to search. Shows absent from it are invisible here.
    let storefront: String

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        storefront: String = Locale.current.region?.identifier.lowercased() ?? "us"
    ) {
        self.http = http
        self.storefront = storefront
    }

    func search(term: String, limit: Int) async throws -> [PodcastSearchResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: storefront),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "term", value: term),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }

        let (data, _) = try await http.data(
            for: URLRequest(url: url),
            maxBytes: AppURLSession.jsonByteLimit
        )
        return try Self.decodeResults(data)
    }

    /// Pure, so the response shape is testable without a network or a fake.
    static func decodeResults(_ data: Data) throws -> [PodcastSearchResult] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }

        return response.results.compactMap { entry in
            // Some entries are video-only or malformed; without a usable feed
            // there is nothing to subscribe to, so they are dropped here.
            guard let rawFeed = entry.feedUrl,
                  let feedURL = FeedURL.normalize(rawFeed)
            else { return nil }

            let title = entry.collectionName ?? entry.trackName ?? ""
            guard !title.isEmpty else { return nil }

            return PodcastSearchResult(
                id: entry.collectionId.map { "itunes:\($0)" } ?? "itunes:\(feedURL.absoluteString)",
                title: title,
                author: entry.artistName ?? "",
                feedURL: feedURL,
                artworkURL: (entry.artworkUrl600 ?? entry.artworkUrl100)
                    .flatMap(URL.init(string:)),
                episodeCount: entry.trackCount,
                genres: entry.genres ?? [],
                itunesCollectionID: entry.collectionId
            )
        }
    }

    private struct SearchResponse: Decodable {
        let results: [Entry]
    }

    private struct Entry: Decodable {
        let collectionId: Int?
        let collectionName: String?
        let trackName: String?
        let artistName: String?
        let feedUrl: String?
        let artworkUrl100: String?
        let artworkUrl600: String?
        let trackCount: Int?
        let genres: [String]?
    }
}
