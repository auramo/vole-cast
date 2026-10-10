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
            }
        )

        _ = try await lookup.podcast(collectionID: 1_000_000_001, storefront: "fi")

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
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-search"))
        )

        let result = try #require(
            try await lookup.podcast(collectionID: 1_000_000_001, storefront: "fi")
        )

        #expect(result.title == "Directory Show")
        #expect(result.feedURL.absoluteString == "https://feeds.example.com/directory-show.xml")
        #expect(result.itunesCollectionID == 1_000_000_001)
    }

    /// A show exclusive to Apple Podcasts has no feed anyone else can play.
    /// That is an answer, not a failure — so it comes back as nil rather than
    /// as a throw, because the two get different screens.
    @Test func answersNilForAShowWithNoPublicFeed() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-lookup-no-feed"))
        )

        #expect(try await lookup.podcast(collectionID: 1_147_969_773, storefront: "fi") == nil)
    }

    @Test func answersNilForAnIDAppleDoesNotKnow() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.ok(try Fixtures.json("itunes-search-empty"))
        )

        #expect(try await lookup.podcast(collectionID: 1, storefront: "fi") == nil)
    }

    /// The distinction the storefront parameter exists to keep.
    ///
    /// A show is only in the stores that carry it, so the same id answers in
    /// one country and not in another. Both answers are nil here, and nil
    /// means "no feed anywhere" — so asking the wrong store makes the app
    /// report a perfectly playable show as exclusive to Apple Podcasts. The
    /// only defence is asking the store the show charted in.
    @Test func findsAShowInTheStoreThatCarriesItAndNotInOneThatDoesNot() async throws {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient { request in
                let country = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "country" }?.value
                return (
                    try Fixtures.json(country == "us" ? "itunes-search" : "itunes-search-empty"),
                    HTTPURLResponse()
                )
            }
        )

        #expect(try await lookup.podcast(collectionID: 1_000_000_001, storefront: "us") != nil)
        #expect(try await lookup.podcast(collectionID: 1_000_000_001, storefront: "fi") == nil)
    }

    /// Lookup shares the same per-device budget as search and the charts.
    @Test func surfacesThrottlingAsRateLimited() async {
        let lookup = ITunesPodcastLookup(http: FakeHTTPClient.status(403))

        await #expect(throws: NetworkError.rateLimited) {
            _ = try await lookup.podcast(collectionID: 1, storefront: "fi")
        }
    }

    @Test func surfacesBeingOfflineAsOffline() async {
        let lookup = ITunesPodcastLookup(
            http: FakeHTTPClient.failing(URLError(.notConnectedToInternet))
        )

        await #expect(throws: NetworkError.offline) {
            _ = try await lookup.podcast(collectionID: 1, storefront: "fi")
        }
    }
}
