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

    func genres(for collectionIDs: [Int], storefront: String) async throws -> [Int: [PodcastGenre]] {
        guard !collectionIDs.isEmpty else { return [:] }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: collectionIDs.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: storefront),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }

        let (data, _) = try await http.data(
            for: URLRequest(url: url),
            maxBytes: AppURLSession.jsonByteLimit
        )
        return try Self.decodeGenres(data)
    }

    /// Pure, so the payload shape is testable without a network or a fake.
    ///
    /// `genreIds` and `genres` arrive as parallel arrays. Zipping them is what
    /// keeps a subgenre's name attached to its id; the ids alone would need a
    /// table of roughly a hundred names this app does not have.
    static func decodeGenres(_ data: Data) throws -> [Int: [PodcastGenre]] {
        struct Response: Decodable { let results: [Entry] }
        struct Entry: Decodable {
            let collectionId: Int?
            let genreIds: [String]?
            let genres: [String]?
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }

        return decoded.results.reduce(into: [:]) { out, entry in
            guard let collectionID = entry.collectionId else { return }
            let ids = entry.genreIds ?? []
            let names = entry.genres ?? []
            out[collectionID] = zip(ids, names).compactMap { id, name in
                Int(id).map { PodcastGenre(id: $0, name: name) }
            }
        }
    }
}
