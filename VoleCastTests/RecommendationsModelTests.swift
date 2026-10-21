import Testing
import Foundation
import SwiftData
@testable import VoleCast

@Suite(.serialized)
@MainActor
struct RecommendationsModelTests {

    private struct StubDirectory: PodcastDirectory {
        var byAuthor: [PodcastSearchResult] = []
        var failure: (any Error)?
        /// A class property on a value-type stub, so every copy of the stub
        /// — including the one `RecommendationsModel` holds — shares one
        /// counter with whatever copy the test kept to read it back from.
        let authorCalls = Mutex<Int>(0)

        func search(term: String, limit: Int) async throws -> [PodcastSearchResult] { [] }
        func shows(byAuthor author: String, limit: Int) async throws -> [PodcastSearchResult] {
            authorCalls.withLock { $0 += 1 }
            if let failure { throw failure }
            return byAuthor
        }
    }

    private struct StubLookup: PodcastLookup {
        var genresByID: [Int: [PodcastGenre]] = [:]

        func podcast(collectionID: Int, storefront: String) async throws -> PodcastSearchResult? { nil }
        func genres(for collectionIDs: [Int], storefront: String) async throws -> [Int: [PodcastGenre]] {
            genresByID
        }
    }

    private struct StubCharts: PodcastCharts {
        var page = ChartPage(entries: [], storefront: "fi")
        var failure: (any Error)?

        func top(
            limit: Int, genre: PodcastGenre?, storefront: String, revalidating: Bool
        ) async throws -> ChartPage {
            if let failure { throw failure }
            return page
        }
    }

    /// The author matters: `Podcast.author` defaults to "" and the publisher
    /// section refuses to ask Apple about a show with no publisher, so a
    /// fixture without one would make three of these tests pass while
    /// exercising nothing.
    private func subscribed(
        _ context: ModelContext, _ name: String,
        collectionID: Int, author: String = "Goalhanger"
    ) -> Podcast {
        let podcast = Podcast(
            feedURL: "https://\(name).example.com/feed",
            feedIdentity: "\(name).example.com/feed",
            title: name
        )
        podcast.author = author
        podcast.itunesCollectionID = collectionID
        context.insert(podcast)
        return podcast
    }

    private func entry(_ collectionID: Int, _ title: String) -> ChartEntry {
        ChartEntry(
            id: "itunes:\(collectionID)", collectionID: collectionID, rank: 1,
            title: title, author: "a", artworkURL: nil, storefront: "fi"
        )
    }

    private func model(
        _ context: ModelContext,
        directory: StubDirectory = StubDirectory(),
        lookup: StubLookup = StubLookup(),
        charts: StubCharts = StubCharts()
    ) -> RecommendationsModel {
        RecommendationsModel(
            directory: directory, lookup: lookup, charts: charts,
            context: context, storefront: "fi"
        )
    }

    /// Nothing subscribed is not a failure, and the remedy is not Try Again.
    @Test func withNoSubscriptionsItSaysSo() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let model = model(context)

        await model.load()

        #expect(model.state == .empty(.noSubscriptions))
    }

    /// Only pasted feeds: Apple has nothing to go on, and must not be asked.
    @Test func withNothingFromApplesDirectoryItSaysSo() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let pasted = Podcast(
            feedURL: "https://p.example.com/feed",
            feedIdentity: "p.example.com/feed", title: "pasted"
        )
        context.insert(pasted)

        let model = model(context)
        await model.load()

        #expect(model.state == .empty(.noAppleShows))
    }

    @Test func buildsAPublisherSection() async throws {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)

        let model = model(context, directory: StubDirectory(byAuthor: [
            PodcastSearchResult(
                id: "itunes:99", title: "Sibling", author: "Goalhanger",
                feedURL: URL(string: "https://sib.example.com/feed")!,
                artworkURL: nil, episodeCount: nil, genres: [], itunesCollectionID: 99
            )
        ]))
        await model.load()

        guard case .loaded(let sections) = model.state else {
            Issue.record("expected sections, got \(model.state)")
            return
        }
        #expect(sections.contains { $0.rows.contains { $0.title == "Sibling" } })
    }

    /// The publisher section needs no play history at all, which is what keeps
    /// the dead window to "before the first subscription".
    @Test func aGenreSectionExcludesWhatIsAlreadySubscribedTo() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)
        _ = subscribed(context, "owned", collectionID: 2)

        let model = model(
            context,
            lookup: StubLookup(genresByID: [1: [PodcastGenre(id: 1526, name: "Daily News")]]),
            charts: StubCharts(page: ChartPage(
                entries: [entry(2, "Owned"), entry(3, "New")], storefront: "fi"
            ))
        )
        await model.load()

        guard case .loaded(let sections) = model.state else {
            Issue.record("expected sections, got \(model.state)")
            return
        }
        let titles = sections.flatMap { $0.rows.map(\.title) }
        #expect(titles.contains("New"))
        #expect(!titles.contains("Owned"))
    }

    /// One source failing must not empty the screen.
    @Test func aFailingPublisherSearchLeavesTheGenreSections() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)

        let model = model(
            context,
            directory: StubDirectory(failure: NetworkError.offline),
            lookup: StubLookup(genresByID: [1: [PodcastGenre(id: 1526, name: "Daily News")]]),
            charts: StubCharts(page: ChartPage(entries: [entry(3, "New")], storefront: "fi"))
        )
        await model.load()

        guard case .loaded(let sections) = model.state else {
            Issue.record("expected sections, got \(model.state)")
            return
        }
        #expect(sections.flatMap { $0.rows.map(\.title) } == ["New"])
    }

    /// Everything suggested already being subscribed to is an outcome, not an
    /// error — "Try Again" would promise something that cannot change.
    @Test func everythingAlreadyOwnedIsItsOwnState() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)
        _ = subscribed(context, "owned", collectionID: 2)

        let model = model(
            context,
            lookup: StubLookup(genresByID: [1: [PodcastGenre(id: 1526, name: "Daily News")]]),
            charts: StubCharts(page: ChartPage(entries: [entry(2, "Owned")], storefront: "fi"))
        )
        await model.load()

        #expect(model.state == .empty(.nothingNew))
    }

    /// Returning to the tab must not refetch. Asserted on a call count rather
    /// than on the resulting state: the stubs answer identically every time,
    /// so comparing states cannot tell a memo hit from a second fetch that
    /// happened to agree.
    @Test func doesNotRefetchWithinASession() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)

        let directory = StubDirectory(byAuthor: [
            PodcastSearchResult(
                id: "itunes:99", title: "Sibling", author: "a",
                feedURL: URL(string: "https://sib.example.com/feed")!,
                artworkURL: nil, episodeCount: nil, genres: [], itunesCollectionID: 99
            )
        ])
        let model = model(context, directory: directory)
        await model.load()
        let first = model.state

        await model.load()

        #expect(model.state == first)
        #expect(directory.authorCalls.current == 1)
    }

    // MARK: - Isolation

    /// The guarantee this screen is arranged around: a suggestions source
    /// failing must not break searching by name.
    ///
    /// The directory is deliberately ONE instance used by both models, because
    /// that is the production topology — `SearchView` hands the same
    /// environment directory to both. Two separate stubs would show only that
    /// two unrelated objects do not interact, which is true of any two objects
    /// and would keep passing if that shared instance ever gained state a
    /// failure could poison.
    @Test func aFailingSuggestionSourceLeavesSearchWorking() async {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        _ = subscribed(context, "seed", collectionID: 1)
        let shared = SharedDirectory()

        let suggestions = RecommendationsModel(
            directory: shared,
            // Genres resolve, so the chart request is genuinely attempted and
            // genuinely fails — without this the charts stub is never called.
            lookup: StubLookup(genresByID: [1: [PodcastGenre(id: 1526, name: "Daily News")]]),
            charts: StubCharts(failure: NetworkError.offline),
            context: context,
            storefront: "fi"
        )
        await suggestions.load()

        #expect(suggestions.state == .failed(.offline))

        // The same directory instance still answers a search.
        let search = SearchModel(directory: shared, debounce: .milliseconds(0))
        await search.search("something")

        guard case .results(let results) = search.state else {
            Issue.record("search should still work, got \(search.state)")
            return
        }
        #expect(results.count == 1)

        // Pasting survives for a different reason worth stating: it reaches no
        // service at all, so there is nothing for a failure to travel along.
        search.query = "https://example.com/feed.xml"
        #expect(search.typedFeedURL != nil)
    }

    /// One directory, failing the way the suggestions screen uses it and
    /// working the way the search field does.
    private struct SharedDirectory: PodcastDirectory {
        func search(term: String, limit: Int) async throws -> [PodcastSearchResult] {
            [PodcastSearchResult(
                id: "itunes:1", title: "Found", author: "a",
                feedURL: URL(string: "https://found.example.com/feed")!,
                artworkURL: nil, episodeCount: nil, genres: [], itunesCollectionID: 1
            )]
        }

        func shows(byAuthor author: String, limit: Int) async throws -> [PodcastSearchResult] {
            throw NetworkError.offline
        }
    }
}
