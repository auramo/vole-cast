import Foundation

/// One show as a chart lists it.
///
/// Deliberately not a `PodcastSearchResult`: no chart Apple publishes carries a
/// feed URL, and a `PodcastSearchResult` whose `feedURL` had to be invented
/// would be a value that cannot do the one thing it exists for. What a chart
/// gives is enough to draw a row and enough to look the show up later — see
/// `PodcastLookup` — and the type says so.
struct ChartEntry: Identifiable, Hashable, Sendable {
    /// Namespaced the same way search results are, so the same show reached
    /// through either path is the same value.
    let id: String
    /// Apple's collection id. The only thread back to a feed URL.
    let collectionID: Int
    /// 1-based position, fixed when the chart is decoded rather than taken
    /// from a row's index, so a filtered-out entry cannot shift the numbers
    /// the reader sees against the chart Apple published.
    let rank: Int
    let title: String
    let author: String
    let artworkURL: URL?
    /// Which country's chart this came from.
    ///
    /// Carried by the entry rather than left on the page, because the entry is
    /// what outlives it: a row sits in a navigation stack long after the page
    /// is gone, and looking the show up in a different store than it charted
    /// in finds nothing — which this app would otherwise report as the show
    /// having no feed at all.
    let storefront: String
}

/// A chart, and which store actually answered.
///
/// The storefront is carried because it can differ from the one asked for: a
/// region Apple has no store for falls back, and someone being shown another
/// country's chart should be told rather than left to wonder why nothing is in
/// their language.
struct ChartPage: Equatable, Sendable {
    let entries: [ChartEntry]
    let storefront: String
}

protocol PodcastCharts: Sendable {
    /// `genre` nil means the overall chart.
    func top(
        limit: Int,
        genre: PodcastGenre?,
        storefront: String,
        revalidating: Bool
    ) async throws -> ChartPage
}

extension PodcastCharts {
    func top(
        limit: Int = 100,
        genre: PodcastGenre? = nil,
        storefront: String = Storefront.device
    ) async throws -> ChartPage {
        try await top(limit: limit, genre: genre, storefront: storefront, revalidating: false)
    }
}
