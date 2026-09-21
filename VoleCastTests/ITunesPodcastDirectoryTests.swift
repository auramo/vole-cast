import Testing
import Foundation
@testable import VoleCast

/// Nothing here touches itunes.apple.com: the live API is rate-limited, and
/// tripping its 403 is exactly the failure we don't want in CI.
struct ITunesPodcastDirectoryTests {

    @Test func decodesASearchResponse() throws {
        let results = try ITunesPodcastDirectory.decodeResults(try Fixtures.json("itunes-search"))

        let first = try #require(results.first)
        #expect(first.title == "Directory Show")
        #expect(first.feedURL.absoluteString == "https://feeds.example.com/directory-show.xml")
        #expect(first.itunesCollectionID != nil)
        #expect(first.id.hasPrefix("itunes:"))
        #expect(first.artworkURL != nil)
        #expect((first.episodeCount ?? 0) > 0)
    }

    @Test func dropsResultsWithNoFeedToSubscribeTo() throws {
        let results = try ITunesPodcastDirectory.decodeResults(try Fixtures.json("itunes-search"))
        #expect(!results.contains { $0.title == "Video Only Show" })
    }

    @Test func decodesAnEmptyResponse() throws {
        let results = try ITunesPodcastDirectory.decodeResults(
            try Fixtures.json("itunes-search-empty")
        )
        #expect(results.isEmpty)
    }

    @Test func reportsGarbageAsDecodingFailure() {
        #expect(throws: NetworkError.decodingFailed) {
            try ITunesPodcastDirectory.decodeResults(Data("<html></html>".utf8))
        }
    }

    @Test func buildsAStorefrontScopedQuery() async throws {
        let seen = Mutex<URL?>(nil)
        let json = try Fixtures.json("itunes-search-empty")
        let client = FakeHTTPClient { request in
            _ = seen.exchange(request.url)
            return (json, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        let directory = ITunesPodcastDirectory(http: client, storefront: "fi")

        _ = try await directory.search(term: "yle areena", limit: 10)

        let url = try #require(seen.current)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "itunes.apple.com")
        #expect(values["media"] == "podcast")
        #expect(values["entity"] == "podcast")
        #expect(values["country"] == "fi")
        #expect(values["limit"] == "10")
        #expect(values["term"] == "yle areena")
    }

    @Test func surfacesThrottlingAsRateLimited() async {
        let directory = ITunesPodcastDirectory(http: FakeHTTPClient.status(403), storefront: "fi")
        await #expect(throws: NetworkError.rateLimited) {
            try await directory.search(term: "anything", limit: 5)
        }
    }

    @Test func surfacesBeingOffline() async {
        let directory = ITunesPodcastDirectory(
            http: FakeHTTPClient.failing(URLError(.notConnectedToInternet)),
            storefront: "fi"
        )
        await #expect(throws: NetworkError.offline) {
            try await directory.search(term: "anything", limit: 5)
        }
    }

    @Test func surfacesServerTrouble() async {
        let directory = ITunesPodcastDirectory(http: FakeHTTPClient.status(500), storefront: "fi")
        await #expect(throws: NetworkError.serverError(500)) {
            try await directory.search(term: "anything", limit: 5)
        }
    }
}
