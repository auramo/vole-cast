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
