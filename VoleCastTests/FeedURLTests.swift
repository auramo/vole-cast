import Testing
import Foundation
@testable import VoleCast

struct FeedURLTests {

    @Test(arguments: [
        ("https://example.com/feed", "https://example.com/feed"),
        // No scheme: assume https rather than refusing.
        ("example.com/feed", "https://example.com/feed"),
        ("  https://example.com/feed  ", "https://example.com/feed"),
        ("<https://example.com/feed>", "https://example.com/feed"),
        ("\"https://example.com/feed\"", "https://example.com/feed"),
        // Podcast-client schemes are HTTP underneath.
        ("feed://example.com/rss", "https://example.com/rss"),
        ("feed:https://example.com/rss", "https://example.com/rss"),
        ("itpc://example.com/rss", "https://example.com/rss"),
        ("pcast://example.com/rss", "https://example.com/rss"),
        // Case-insensitive parts get folded; the path does not.
        ("HTTPS://Example.COM/Feed", "https://example.com/Feed"),
        ("https://example.com./feed", "https://example.com/feed"),
        ("https://example.com:443/feed", "https://example.com/feed"),
        ("http://example.com:80/feed", "http://example.com/feed"),
        ("https://example.com/feed#latest", "https://example.com/feed"),
        ("https://example.com", "https://example.com/"),
        // Query strings carry private-feed tokens and must survive intact.
        ("https://example.com/feed?token=A1b2&format=rss", "https://example.com/feed?token=A1b2&format=rss"),
    ])
    func normalizeRewrites(_ input: String, _ expected: String) {
        #expect(FeedURL.normalize(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "",
        "   ",
        "not a url",
        "ftp://example.com/feed",
        "mailto:someone@example.com",
        // A bare word is a search term, not a host.
        "podcast",
    ])
    func normalizeRejects(_ input: String) {
        #expect(FeedURL.normalize(input) == nil)
    }

    @Test func identityCollapsesInterchangeableForms() throws {
        let variants = [
            "https://example.com/feed",
            "http://example.com/feed",
            "https://www.example.com/feed",
            "https://example.com/feed/",
            "HTTPS://EXAMPLE.COM/feed",
            "feed://www.example.com/feed/",
        ]
        let keys = try variants.map { raw in
            let url = try #require(FeedURL.normalize(raw))
            return FeedURL.identityKey(url)
        }
        #expect(Set(keys).count == 1)
        #expect(keys[0] == "example.com/feed")
    }

    @Test func identityIgnoresQueryOrderButNotQueryContent() throws {
        func key(_ raw: String) throws -> String {
            FeedURL.identityKey(try #require(FeedURL.normalize(raw)))
        }
        #expect(try key("https://example.com/f?a=1&b=2") == key("https://example.com/f?b=2&a=1"))
        // Two people's private feeds differ only by token; they are not one show.
        #expect(try key("https://example.com/f?token=aaa") != key("https://example.com/f?token=bbb"))
        #expect(try key("https://example.com/f") != key("https://example.com/f?token=aaa"))
    }

    @Test func identityKeepsDistinctShowsApart() throws {
        func key(_ raw: String) throws -> String {
            FeedURL.identityKey(try #require(FeedURL.normalize(raw)))
        }
        #expect(try key("https://example.com/a") != key("https://example.com/b"))
        #expect(try key("https://a.example.com/feed") != key("https://b.example.com/feed"))
        // Paths are case-sensitive on the wire, so they must be here too.
        #expect(try key("https://example.com/Feed") != key("https://example.com/feed"))
    }
}
