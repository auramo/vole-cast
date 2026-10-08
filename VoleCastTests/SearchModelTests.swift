import Testing
import Foundation
@testable import VoleCast

@MainActor
struct SearchModelTests {

    /// Records how often it was asked, so "did we call the network?" is testable.
    private struct StubDirectory: PodcastDirectory {
        var results: [PodcastSearchResult] = []
        var error: Error?
        let calls = Mutex(0)

        func search(term: String, limit: Int) async throws -> [PodcastSearchResult] {
            calls.withLock { $0 += 1 }
            if let error { throw error }
            return results
        }
    }

    private func result(_ title: String) -> PodcastSearchResult {
        PodcastSearchResult(
            id: "itunes:\(title)",
            title: title,
            author: "Someone",
            feedURL: URL(string: "https://example.com/\(title).xml")!,
            artworkURL: nil,
            episodeCount: 3,
            genres: [],
            itunesCollectionID: nil
        )
    }

    private func model(_ directory: StubDirectory) -> SearchModel {
        SearchModel(directory: directory, debounce: .zero)
    }

    /// A pasted feed URL is not a show name, and asking Apple to find a show
    /// called "https://feeds.npr.org/510289/podcast.xml" can only come back
    /// empty — which then replaced the Open feed row with "No results".
    ///
    /// It must not be sent at all, either: a private feed from Patreon or
    /// Supercast carries a per-user token in its query string, and a search
    /// hands that straight to Apple.
    @Test func doesNotSearchForAPastedFeedURL() async {
        let directory = StubDirectory(results: [result("Something")])
        let model = model(directory)

        await model.search("https://feeds.npr.org/510289/podcast.xml")

        #expect(directory.calls.current == 0)
        // Idle, not empty: the view shows the Open feed row in this state.
        #expect(model.state == .idle)
    }

    @Test func doesNotSearchForAURLWithoutItsScheme() async {
        let directory = StubDirectory(results: [result("Something")])
        let model = model(directory)

        await model.search("feeds.npr.org/510289/podcast.xml")

        #expect(directory.calls.current == 0)
    }

    /// The other half: a bare dotted name is a plausible show name — "ev.news"
    /// is a real subscription — and must still be searched for, even though it
    /// also parses as a host.
    @Test func stillSearchesForANameThatHappensToHaveADot() async {
        let directory = StubDirectory(results: [result("ev.news Daily")])
        let model = model(directory)

        await model.search("ev.news")

        #expect(directory.calls.current == 1)
        #expect(model.state == .results([result("ev.news Daily")]))
    }

    @Test func showsResults() async {
        let directory = StubDirectory(results: [result("Directory Show")])
        let model = model(directory)

        await model.search("directory")

        #expect(model.state == .results([result("Directory Show")]))
        #expect(directory.calls.current == 1)
    }

    @Test func aTooShortQueryAsksNothing() async {
        let directory = StubDirectory(results: [result("Anything")])
        let model = model(directory)

        await model.search("r")

        #expect(model.state == .idle)
        #expect(directory.calls.current == 0)
    }

    @Test func blankQueryReturnsToIdle() async {
        let directory = StubDirectory()
        let model = model(directory)

        await model.search("   ")

        #expect(model.state == .idle)
        #expect(directory.calls.current == 0)
    }

    @Test func noMatchesIsItsOwnState() async {
        let model = model(StubDirectory(results: []))

        await model.search("zzzzz")

        #expect(model.state == .empty)
    }

    @Test func throttlingIsReported() async {
        let model = model(StubDirectory(error: NetworkError.rateLimited))

        await model.search("rikos")

        #expect(model.state == .failed(.rateLimited))
    }

    @Test func beingOfflineIsReported() async {
        let model = model(StubDirectory(error: URLError(.notConnectedToInternet)))

        await model.search("rikos")

        #expect(model.state == .failed(.offline))
    }

    @Test func aSupersededSearchLeavesStateAlone() async {
        let model = model(StubDirectory(error: CancellationError()))
        model.query = "rikos"

        await model.search("rikos")

        // Not `.failed`: the user is still typing.
        #expect(model.state == .searching)
    }

    @Test(arguments: [
        ("https://example.com/feed.xml", true),
        ("example.com/feed", true),
        ("feed://example.com/rss", true),
        ("Directory Show", false),
        // Accents and punctuation must not read as an address either.
        ("Mitä ihmettä, Esimerkki?", false),
        ("", false),
    ])
    func recognisesATypedFeedURL(_ query: String, _ isURL: Bool) {
        let model = model(StubDirectory())
        model.query = query
        #expect((model.typedFeedURL != nil) == isURL)
    }
}
