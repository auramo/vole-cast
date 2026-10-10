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
    let storefront: String

    init(http: any HTTPClient = URLSessionHTTPClient(), storefront: String = Storefront.device) {
        self.http = http
        self.storefront = storefront
    }

    func podcast(collectionID: Int) async throws -> PodcastSearchResult? {
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
