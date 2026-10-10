import Testing
import Foundation
@testable import VoleCast

@MainActor
struct DiscoverModelTests {

    /// Counts what it was asked for, so "did we go to the network?" is
    /// testable — the same trick `SearchModelTests` uses for the directory.
    private struct StubCharts: PodcastCharts {
        var entries: [ChartEntry] = []
        var error: Error?
        let calls = Mutex(0)
        let lastGenre = Mutex<Int?>(nil)
        let lastRevalidating = Mutex(false)

        func top(
            limit: Int,
            genre: PodcastGenre?,
            storefront: String,
            revalidating: Bool
        ) async throws -> ChartPage {
            calls.withLock { $0 += 1 }
            _ = lastGenre.exchange(genre?.id)
            _ = lastRevalidating.exchange(revalidating)
            if let error { throw error }
            return ChartPage(entries: entries, storefront: storefront)
        }
    }

    private func entry(_ title: String, rank: Int = 1) -> ChartEntry {
        ChartEntry(
            id: "itunes:\(rank)",
            collectionID: rank,
            rank: rank,
            title: title,
            author: "Someone",
            artworkURL: nil,
            storefront: "fi"
        )
    }

    @Test func showsTheChartItLoaded() async {
        let charts = StubCharts(entries: [entry("Top Show")])
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()

        #expect(model.state == .loaded(ChartPage(entries: [entry("Top Show")], storefront: "fi")))
    }

    @Test func anEmptyChartIsItsOwnState() async {
        let model = DiscoverModel(charts: StubCharts(), storefront: "fi")

        await model.load()

        #expect(model.state == .empty)
    }

    @Test func asksForTheChosenGenre() async {
        let charts = StubCharts(entries: [entry("Funny")])
        let model = DiscoverModel(charts: charts, storefront: "fi")
        model.genre = PodcastGenre.all.first { $0.id == 1303 }

        await model.load()

        #expect(charts.lastGenre.current == 1303)
    }

    /// Flicking between genres must not blink through a spinner to redraw a
    /// list that was on screen a moment ago.
    @Test func doesNotRefetchAChartItAlreadyHas() async {
        let charts = StubCharts(entries: [entry("Top Show")])
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()
        await model.load()

        #expect(charts.calls.current == 1)
    }

    /// The memo is per country and genre, not one slot.
    @Test func remembersEachChartSeparately() async {
        let charts = StubCharts(entries: [entry("Top Show")])
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()
        model.genre = PodcastGenre.all.first { $0.id == 1303 }
        await model.load()
        model.genre = nil
        await model.load()

        #expect(charts.calls.current == 2)
    }

    @Test func refreshingGoesPastTheMemoAndRevalidates() async {
        let charts = StubCharts(entries: [entry("Top Show")])
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()
        await model.refresh()

        #expect(charts.calls.current == 2)
        #expect(charts.lastRevalidating.current)
    }

    @Test func reportsBeingOfflineAsAFailure() async {
        let charts = StubCharts(error: URLError(.notConnectedToInternet))
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()

        #expect(model.state == .failed(.offline))
    }

    /// A country Apple has no store for is not a fault to retry.
    @Test(arguments: [NetworkError.invalidResponse, .notFound])
    func treatsARefusedStoreAsAChoiceToChange(_ error: NetworkError) async {
        let charts = StubCharts(error: error)
        let model = DiscoverModel(charts: charts, storefront: "ax")

        await model.load()

        #expect(model.state == .unavailableCountry("ax"))
    }

    /// A server error must not be read as a missing storefront, however
    /// tempting — an unknown country does provoke one from the newer endpoint,
    /// but so does Apple having a bad minute, and that host has been seen
    /// erring on a country that plainly has a store. Saying "Finland has no
    /// Apple podcast store" to someone in Helsinki is wrong and unarguable;
    /// offering Try Again is neither.
    @Test(arguments: [NetworkError.serverError(500), .timedOut, .offline, .rateLimited])
    func keepsATryAgainForEverythingThatMightPass(_ error: NetworkError) async {
        let charts = StubCharts(error: error)
        let model = DiscoverModel(charts: charts, storefront: "fi")

        await model.load()

        #expect(model.state == .failed(error))
    }

    /// The guarantee the whole feature is arranged around: browsing charts is
    /// an extra, and when it fails the two ways of finding a show that people
    /// actually rely on must be untouched.
    @Test func chartsFailingLeavesSearchWorking() async {
        let directory = StubDirectory(results: [
            PodcastSearchResult(
                id: "itunes:1",
                title: "Found By Name",
                author: "Someone",
                feedURL: URL(string: "https://example.com/feed.xml")!,
                artworkURL: nil,
                episodeCount: 3,
                genres: [],
                itunesCollectionID: 1
            )
        ])
        let search = SearchModel(directory: directory, debounce: .zero)
        let discover = DiscoverModel(
            charts: StubCharts(error: URLError(.notConnectedToInternet)),
            storefront: "fi"
        )

        await discover.load()
        await search.search("anything")

        #expect(discover.state == .failed(.offline))
        #expect(search.state == .results(directory.results))
        // And the pasted-URL path, which never asks anyone anything.
        search.query = "https://feeds.example.com/show.xml"
        #expect(search.typedFeedURL != nil)
    }

    /// Mirrors `SearchModelTests`' stub, kept here so the isolation test above
    /// needs nothing from that file.
    private struct StubDirectory: PodcastDirectory {
        var results: [PodcastSearchResult] = []
        func search(term: String, limit: Int) async throws -> [PodcastSearchResult] { results }
    }
}
