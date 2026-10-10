import Testing
import Foundation
@testable import VoleCast

/// Nothing here touches itunes.apple.com, for the reason given in
/// `ITunesPodcastDirectoryTests`: its throttle is per device and arrives as a
/// 403, so a suite that called it would fail CI on someone else's traffic.
struct ITunesPodcastLookupTests {

    @Test func asksForOneShowInOneStore() async throws {
        let seen = Mutex<URL?>(nil)
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient { request in
                _ = seen.exchange(request.url)
                return (try Fixtures.json("itunes-search"), HTTPURLResponse())
            },
            storefront: "fi"
        )

        _ = try await lookup.podcast(collectionID: 1_000_000_001)

        let url = try #require(seen.current)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let items = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })
        #expect(url.path == "/lookup")
        #expect(items["id"] == "1000000001")
        #expect(items["entity"] == "podcast")
        #expect(items["country"] == "fi")
    }

    /// The payload is the same shape the search endpoint returns, which is the
    /// whole reason this shares that decoder.
    @Test func readsAShowTheSearchDecoderAlreadyUnderstands() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-search")),
            storefront: "fi"
        )

        let result = try #require(try await lookup.podcast(collectionID: 1_000_000_001))

        #expect(result.title == "Directory Show")
        #expect(result.feedURL.absoluteString == "https://feeds.example.com/directory-show.xml")
        #expect(result.itunesCollectionID == 1_000_000_001)
    }

    /// A show exclusive to Apple Podcasts has no feed anyone else can play.
    /// That is an answer, not a failure — so it comes back as nil rather than
    /// as a throw, because the two get different screens.
    @Test func answersNilForAShowWithNoPublicFeed() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-lookup-no-feed")),
            storefront: "fi"
        )

        #expect(try await lookup.podcast(collectionID: 1_147_969_773) == nil)
    }

    @Test func answersNilForAnIDAppleDoesNotKnow() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-search-empty")),
            storefront: "fi"
        )

        #expect(try await lookup.podcast(collectionID: 1) == nil)
    }

    /// Lookup shares the same per-device budget as search and the charts.
    @Test func surfacesThrottlingAsRateLimited() async {
        let lookup = ITunesPodcastLookup(http: FakeHTTPClient.status(403), storefront: "fi")

        await #expect(throws: NetworkError.rateLimited) {
            _ = try await lookup.podcast(collectionID: 1)
        }
    }

    @Test func surfacesBeingOfflineAsOffline() async {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.failing(URLError(.notConnectedToInternet)),
            storefront: "fi"
        )

        await #expect(throws: NetworkError.offline) {
            _ = try await lookup.podcast(collectionID: 1)
        }
    }
}
