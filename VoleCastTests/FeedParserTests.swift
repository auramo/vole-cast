import Testing
import Foundation
@testable import VoleCast

struct FeedParserTests {

    @Test func readsChannelAndEpisodes() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-minimal"))

        #expect(feed.title == "Minimal Show")
        #expect(feed.summary == "A show with nothing unusual about it.")
        #expect(feed.websiteURL == "https://example.com/show")
        #expect(feed.language == "en-us")
        #expect(feed.episodes.count == 2)

        let newest = try #require(feed.episodes.first)
        #expect(newest.title == "Episode Two")
        #expect(newest.guid == "episode-2")
        #expect(newest.audioURL == "https://cdn.example.com/2.mp3")
        #expect(newest.audioMIMEType == "audio/mpeg")
        #expect(newest.audioByteCount == 2048)
        #expect(newest.pageURL == "https://example.com/show/2")
        #expect(newest.publishedAt == Date(timeIntervalSince1970: 1_756_796_400))
    }

    @Test func newestEpisodeComesFirstRegardlessOfFeedOrder() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-messy-dates"))
        let dated = feed.episodes.compactMap(\.publishedAt)
        #expect(dated == dated.sorted(by: >))
        // The undated episode is kept, and sorts last rather than vanishing.
        #expect(feed.episodes.count == 6)
        #expect(feed.episodes.last?.title == "Unparseable")
        #expect(feed.episodes.last?.publishedAt == nil)
    }

    @Test func readsITunesTagsAndPrefersITunesArtwork() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-itunes-full"))

        #expect(feed.author == "Anna Aalto")
        #expect(feed.language == "fi")
        #expect(feed.newFeedURL == "https://example.com/moved/feed.xml")
        // itunes:image wins over the smaller RSS <image><url>.
        #expect(feed.artworkURL == "https://cdn.example.com/art-3000.jpg")
        // <description> wins over <itunes:summary>.
        #expect(feed.summary == "Channel description wins over the iTunes summary.")
        // The channel title, not the one repeated inside <image>.
        #expect(feed.title == "Full Show")

        #expect(feed.episodes.map(\.duration) == [3600, 3372, 3723])
        #expect(feed.episodes.first?.artworkURL == "https://cdn.example.com/ep3.jpg")
        #expect(feed.episodes.last?.artworkURL == nil)
    }

    @Test func fallsBackToRSSImageWhenThereIsNoITunesArtwork() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-rss-image"))
        #expect(feed.artworkURL == "https://cdn.example.com/old-144.png")
    }

    @Test func readsCDATAAndEntities() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-cdata"))

        #expect(feed.title == "CDATA & Entities")
        #expect(feed.summary == "<p>A show about <strong>markup</strong>.</p>")

        let first = try #require(feed.episodes.first)
        #expect(first.title == "Episode with & entity")
        #expect(first.summary.contains("Show notes with a"))
        // description wins; content:encoded is only a fallback.
        #expect(!first.summary.contains("Longer notes"))
        #expect(feed.episodes.last?.summary == "<p>The only notes there are.</p>")
    }

    @Test func decodesNonUTF8FeedsUsingTheDeclaredEncoding() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-latin1"))
        #expect(feed.title == "Jäljillä")
        #expect(feed.episodes.first?.title == "Ensimmäinen jakso")
    }

    @Test func dropsItemsThatCannotBePlayed() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-no-enclosure"))
        // The blog post and the media:content-only item are both dropped.
        #expect(feed.episodes.map(\.title) == ["A real episode"])
    }

    @Test func guidFallsBackWhenTheFeedOmitsIt() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-rss-image"))
        #expect(feed.episodes.first?.guid == "https://cdn.example.com/old-1.mp3")
    }

    @Test func keepsOnlyTheNewestEpisodesWhenCapped() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-messy-dates"), maxEpisodes: 2)
        #expect(feed.episodes.map(\.title) == ["Single digit day", "ISO 8601"])
    }

    @Test func rejectsAWebPage() throws {
        #expect(throws: FeedParseError.notAFeed) {
            try FeedParser.parse(try Fixtures.data("not-a-feed", "html"))
        }
    }

    @Test func reportsWhereTruncatedXMLBroke() throws {
        let error = #expect(throws: FeedParseError.self) {
            try FeedParser.parse(try Fixtures.feed("feed-truncated"))
        }
        guard case .malformedXML(let line, _) = try #require(error) else {
            Issue.record("Expected malformedXML, got \(String(describing: error))")
            return
        }
        #expect(line > 0)
    }

    @Test func rejectsEmptyData() {
        #expect(throws: FeedParseError.notAFeed) {
            try FeedParser.parse(Data())
        }
    }

    /// Descriptions are usually CDATA or escaped, but a feed may carry raw
    /// XHTML instead. Opening a child element must not discard the text
    /// already gathered for its parent.
    @Test func keepsDescriptionTextAroundRawInlineMarkup() throws {
        let feed = try FeedParser.parse(try Fixtures.feed("feed-inline-markup"))

        #expect(feed.summary == "A show whose notes carry raw XHTML rather than CDATA.")

        let first = try #require(feed.episodes.first { $0.guid == "inline-1" })
        #expect(first.summary == "Hello world and more.")

        let second = try #require(feed.episodes.first { $0.guid == "inline-2" })
        #expect(second.summary == "Leading text a link then trailing text.")
    }
}
