import Testing
import Foundation
@testable import VoleCast

/// Nothing here touches itunes.apple.com or Apple's RSS hosts. Their rate
/// limit is per device and arrives as a 403, so a suite that called them would
/// eventually fail CI for reasons that have nothing to do with the code —
/// which is exactly the failure the decoders are split out to avoid.
struct ApplePodcastChartsTests {

    // MARK: - URLs

    /// The documented endpoint, used for the overall chart.
    @Test func buildsTheSupportedURLForTheOverallChart() throws {
        let url = try #require(
            ApplePodcastCharts.chartURL(storefront: "fi", limit: 100, genre: nil)
        )
        #expect(
            url.absoluteString
                == "https://rss.marketingtools.apple.com/api/v2/fi/podcasts/top/100/podcasts.json"
        )
    }

    /// The legacy endpoint takes its parameters as path segments in a fixed
    /// order, which is the whole reason the URL is interpolated rather than
    /// assembled from query items.
    @Test func buildsTheLegacyURLForAGenreChart() throws {
        let comedy = try #require(PodcastGenre.all.first { $0.id == 1303 })
        let url = try #require(
            ApplePodcastCharts.chartURL(storefront: "fi", limit: 50, genre: comedy)
        )
        #expect(
            url.absoluteString
                == "https://itunes.apple.com/fi/rss/toppodcasts/limit=50/genre=1303/json"
        )
    }

    // MARK: - The supported endpoint's shape

    @Test func readsTheOverallChart() throws {
        let entries = try ApplePodcastCharts.decodeTop(
            Fixtures.json("apple-top-podcasts"),
            storefront: "fi"
        )

        #expect(entries.count == 3)
        let first = try #require(entries.first)
        #expect(first.rank == 1)
        #expect(first.title == "Sijoituskästi")
        #expect(first.author == "Teemu Liila ja Kevin van Dessel")
        #expect(first.collectionID == 1521917708)
        #expect(first.id == "itunes:1521917708")
        #expect(first.artworkURL != nil)
        #expect(entries.map(\.rank) == [1, 2, 3])
    }

    // MARK: - The legacy endpoint's shape

    @Test func readsAGenreChart() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"),
            storefront: "fi"
        )

        let first = try #require(entries.first)
        #expect(first.title == "Conan O’Brien Needs A Friend")
        #expect(first.collectionID == 1438054347)
        #expect(first.rank == 1)
    }

    /// The legacy feed offers 55, 60 and 170 pixel artwork. A 56pt row at 3×
    /// wants 168, so anything smaller is visibly soft.
    @Test func takesTheLargestArtworkOffered() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"),
            storefront: "fi"
        )
        let artwork = try #require(entries.first?.artworkURL?.absoluteString)

        #expect(artwork.contains("170x170"))
    }

    /// An entry whose id will not parse can never be resolved to a feed, and
    /// one with no title has nothing to draw — both are dead ends, so neither
    /// earns a row.
    @Test func dropsEntriesItCouldNeverOpen() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"),
            storefront: "fi"
        )

        #expect(!entries.contains { $0.title == "Unresolvable Show" })
        #expect(!entries.contains { $0.title.isEmpty })
    }

    /// Dropping an entry must not leave a hole in the numbering: a jump from 3
    /// to 5 reads as a bug in the app rather than as Apple having listed
    /// something unusable.
    @Test func numbersTheRowsItKeptWithoutGaps() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"),
            storefront: "fi"
        )

        #expect(entries.map(\.rank) == Array(1...entries.count))
    }

    /// A show with no `im:artist` still belongs on the chart.
    @Test func keepsAShowWithNoNamedAuthor() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"),
            storefront: "fi"
        )
        let anonymous = try #require(entries.first { $0.title == "No Artist Show" })

        #expect(anonymous.author.isEmpty)
    }

    /// An empty chart omits the `entry` key altogether rather than sending an
    /// empty array.
    @Test func readsAChartWithNothingInIt() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-empty"),
            storefront: "fi"
        )

        #expect(entries.isEmpty)
    }

    /// And a chart with one show has been seen to serve it as a bare object
    /// where an array was expected.
    @Test func readsAChartServedAsASingleObject() throws {
        let entries = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-single"),
            storefront: "fi"
        )

        #expect(entries.count == 1)
        #expect(entries.first?.rank == 1)
    }

    /// Each row has to remember whose chart it came from. A show is only in
    /// the stores that carry it, and the lookup that turns a row into a feed
    /// happens long after the page is gone — asked of the wrong store it finds
    /// nothing, which this app reports as the show having no feed at all.
    @Test func everyRowRemembersWhichStoreItCameFrom() throws {
        let top = try ApplePodcastCharts.decodeTop(
            Fixtures.json("apple-top-podcasts"), storefront: "us"
        )
        let genre = try ApplePodcastCharts.decodeGenreChart(
            Fixtures.json("itunes-top-podcasts-comedy"), storefront: "gb"
        )

        #expect(top.allSatisfy { $0.storefront == "us" })
        #expect(genre.allSatisfy { $0.storefront == "gb" })
    }

    @Test func refusesAPayloadItCannotRead() {
        #expect(throws: NetworkError.decodingFailed) {
            try ApplePodcastCharts.decodeGenreChart(Data("not json".utf8), storefront: "fi")
        }
        #expect(throws: NetworkError.decodingFailed) {
            try ApplePodcastCharts.decodeTop(Data("not json".utf8), storefront: "fi")
        }
    }

    // MARK: - Fetching

    @Test func reportsWhichStoreAnswered() async throws {
        let charts = ApplePodcastCharts(
            http: FakeHTTPClient.ok(try Fixtures.json("apple-top-podcasts"))
        )

        let page = try await charts.top(limit: 10, genre: nil, storefront: "fi", revalidating: false)

        #expect(page.storefront == "fi")
        #expect(page.entries.count == 3)
    }

    /// Charts share one per-device budget with search and lookup, and that
    /// budget is enforced as a 403.
    @Test func surfacesThrottlingAsRateLimited() async {
        let charts = ApplePodcastCharts(http: FakeHTTPClient.status(403))

        await #expect(throws: NetworkError.rateLimited) {
            try await charts.top(limit: 10, genre: nil, storefront: "fi", revalidating: false)
        }
    }
}
