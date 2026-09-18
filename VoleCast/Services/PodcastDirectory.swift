import Foundation

/// One show as a directory describes it — enough to list it and to fetch it.
struct PodcastSearchResult: Identifiable, Hashable, Sendable {
    /// Namespaced so results stay distinct if a second directory is added.
    let id: String
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
    let episodeCount: Int?
    let genres: [String]
    let itunesCollectionID: Int?
}

/// Where "search for a show by name" is answered.
///
/// A protocol because Apple's directory is not the only possible answer:
/// Podcast Index could be added later without the UI knowing. It also lets
/// tests and previews avoid the network entirely.
protocol PodcastDirectory: Sendable {
    func search(term: String, limit: Int) async throws -> [PodcastSearchResult]
}

extension PodcastDirectory {
    func search(term: String) async throws -> [PodcastSearchResult] {
        try await search(term: term, limit: 25)
    }
}
