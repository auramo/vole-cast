import Testing
import Foundation
@testable import VoleCast

struct FeedLoaderTests {
    private let requested = URL(string: "https://example.com/feed")!

    @Test func loadsAndParses() async throws {
        let loader = FeedLoader(http: FakeHTTPClient.ok(try Fixtures.feed("feed-minimal"), url: requested))
        let loaded = try await loader.load(requested)

        #expect(loaded.feed.title == "Minimal Show")
        #expect(loaded.resolvedURL == requested)
        #expect(loaded.identityKey == "example.com/feed")
    }

    @Test func identityFollowsARedirect() async throws {
        let moved = URL(string: "https://cdn.example.net/shows/1/rss")!
        let loader = FeedLoader(
            http: FakeHTTPClient.redirecting(to: moved, data: try Fixtures.feed("feed-minimal"))
        )
        let loaded = try await loader.load(requested)
        #expect(loaded.resolvedURL == moved)
    }

    @Test func aDeclaredMoveWinsOverTheRequestedURL() async throws {
        let loader = FeedLoader(http: FakeHTTPClient.ok(try Fixtures.feed("feed-itunes-full"), url: requested))
        let loaded = try await loader.load(requested)
        // itunes:new-feed-url in the fixture.
        #expect(loaded.resolvedURL.absoluteString == "https://example.com/moved/feed.xml")
    }

    @Test func retriesOverHTTPSWhenATSBlocksPlainHTTP() async throws {
        let insecure = URL(string: "http://example.com/feed")!
        let loader = FeedLoader(
            http: FakeHTTPClient.failingOnce(
                with: URLError(.appTransportSecurityRequiresSecureConnection),
                thenServing: try Fixtures.feed("feed-minimal"),
                from: URL(string: "https://example.com/feed")!
            )
        )
        let loaded = try await loader.load(insecure)
        #expect(loaded.resolvedURL.scheme == "https")
    }

    @Test func givesUpWhenHTTPSAlsoFails() async throws {
        let loader = FeedLoader(
            http: FakeHTTPClient.failing(URLError(.appTransportSecurityRequiresSecureConnection))
        )
        await #expect(throws: NetworkError.insecureConnection) {
            try await loader.load(URL(string: "http://example.com/feed")!)
        }
    }

    @Test func reportsAWebPageAsNotAFeed() async throws {
        let loader = FeedLoader(http: FakeHTTPClient.ok(try Fixtures.data("not-a-feed", "html"), url: requested))
        await #expect(throws: FeedParseError.notAFeed) {
            try await loader.load(requested)
        }
    }

    @Test func refusesAnOversizedFeed() async throws {
        let big = Data(repeating: 0x20, count: AppURLSession.feedByteLimit + 1)
        let loader = FeedLoader(http: FakeHTTPClient.ok(big, url: requested))
        await #expect(throws: NetworkError.tooLarge) {
            try await loader.load(requested)
        }
    }

    @Test func surfacesThrottlingAsRateLimited() async throws {
        let loader = FeedLoader(http: FakeHTTPClient.status(403, url: requested))
        await #expect(throws: NetworkError.rateLimited) {
            try await loader.load(requested)
        }
    }

    @Test func honoursTheEpisodeCap() async throws {
        let loader = FeedLoader(
            http: FakeHTTPClient.ok(try Fixtures.feed("feed-messy-dates"), url: requested),
            maxEpisodes: 3
        )
        let loaded = try await loader.load(requested)
        #expect(loaded.feed.episodes.count == 3)
    }
}
