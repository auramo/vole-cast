import Foundation

/// Looks a show up by its iTunes collection id.
///
/// The response is byte-identical in shape to the search endpoint's, so this
/// borrows `ITunesPodcastDirectory.decodeResults` rather than carrying a
/// second decoder that would have to be kept in step with the first. That
/// reuse also inherits its rule that an entry without a usable feed URL is
/// dropped — which is exactly what makes "no feed" readable here as an empty
/// result rather than something that needs its own detection.
struct ITunesPodcastLookup: PodcastLookup {
    let http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// The store is a parameter rather than a property: one lookup follows a
    /// chart row into whichever country's chart it came from, and the next may
    /// follow a different one.
    func podcast(collectionID: Int, storefront: String) async throws -> PodcastSearchResult? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(collectionID)),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: storefront),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }

        let (data, _) = try await http.data(
            for: URLRequest(url: url),
            maxBytes: AppURLSession.jsonByteLimit
        )
        return try ITunesPodcastDirectory.decodeResults(data).first
    }
}
