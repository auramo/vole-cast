import Foundation

/// Apple's podcast charts, from two different endpoints.
///
/// Two, because no single one does both jobs. The history is worth recording,
/// since all of it was established by trying them rather than by reading docs
/// that do not exist:
///
///  - `rss.itunes.apple.com/api/v1/…`, the URL most often suggested, is dead.
///    It answers 503 with a DNS failure.
///  - `rss.marketingtools.apple.com/api/v2/…` is its live replacement and is
///    the one Apple documents. It serves the overall chart well, and it
///    *silently ignores* any genre you ask for — request Comedy and it returns
///    the same Business and News shows as the unfiltered chart. So it cannot
///    do genres at all, and the failure is invisible rather than an error.
///  - The legacy `itunes.apple.com/{cc}/rss/toppodcasts/…` endpoint genuinely
///    filters by genre. It is undocumented and its sibling host has already
///    been retired, so it is the fragile half.
///
/// Hence the split: the overall chart comes from the supported endpoint and
/// genre charts from the fragile one. If the legacy endpoint goes the way of
/// its sibling, genre browsing fails and the overall chart, the search and the
/// rest of the app carry on.
///
/// Neither endpoint returns a feed URL — see `ChartEntry`.
struct ApplePodcastCharts: PodcastCharts {
    let http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func top(
        limit: Int,
        genre: PodcastGenre?,
        storefront: String,
        revalidating: Bool
    ) async throws -> ChartPage {
        guard let url = Self.chartURL(storefront: storefront, limit: limit, genre: genre) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        // Same expression of "refresh" as `FeedLoader`: let the shared
        // URLCache answer, but make it revalidate first.
        if revalidating { request.cachePolicy = .reloadRevalidatingCacheData }

        // 100 entries is ~200 KB from the legacy endpoint and ~50 KB from the
        // newer one, so this cap is roughly ten times what either sends. It is
        // here to bound a surprise, not to trim a known payload.
        let (data, _) = try await http.data(for: request, maxBytes: AppURLSession.jsonByteLimit)

        let entries = genre == nil
            ? try Self.decodeTop(data, storefront: storefront)
            : try Self.decodeGenreChart(data, storefront: storefront)
        return ChartPage(entries: entries, storefront: storefront)
    }

    // MARK: - URLs

    /// Built by interpolation rather than `URLComponents` because the legacy
    /// endpoint takes its parameters as *path segments* in a fixed order —
    /// `limit` then `genre` — not as a query. Everything interpolated is a
    /// number or a lowercase ISO code, so there is nothing to escape.
    static func chartURL(storefront: String, limit: Int, genre: PodcastGenre?) -> URL? {
        guard let genre else {
            return URL(
                string: "https://rss.marketingtools.apple.com/api/v2/"
                    + "\(storefront)/podcasts/top/\(limit)/podcasts.json"
            )
        }
        return URL(
            string: "https://itunes.apple.com/"
                + "\(storefront)/rss/toppodcasts/limit=\(limit)/genre=\(genre.id)/json"
        )
    }

    // MARK: - Decoding

    /// The documented endpoint's shape. Pure, so the payload can be checked
    /// without a network or a fake.
    static func decodeTop(_ data: Data, storefront: String) throws -> [ChartEntry] {
        do {
            let decoded = try JSONDecoder().decode(TopResponse.self, from: data)
            return entries(from: decoded.feed.results.map {
                RawEntry(
                    collectionID: $0.id,
                    title: $0.name,
                    author: $0.artistName,
                    artwork: $0.artworkUrl100
                )
            }, storefront: storefront)
        } catch {
            throw NetworkError.decodingFailed
        }
    }

    /// The legacy endpoint's shape, which is the same chart wearing Atom's
    /// clothes: every value is wrapped in a `label`, and the useful ids hide
    /// in `attributes` under keys with colons in them.
    static func decodeGenreChart(_ data: Data, storefront: String) throws -> [ChartEntry] {
        do {
            let decoded = try JSONDecoder().decode(GenreResponse.self, from: data)
            return entries(from: (decoded.feed.entry?.values ?? []).map {
                RawEntry(
                    collectionID: $0.id.attributes.collectionID,
                    title: $0.name.label,
                    author: $0.artist?.label,
                    // Largest advertised, which tops out at 170 — enough for a
                    // 56pt row at 3×. Rewriting Apple's `170x170bb` path to
                    // ask for more is undocumented string surgery, and by the
                    // time anyone sees a bigger image the preview screen has
                    // better artwork from the feed itself.
                    artwork: $0.image.max { ($0.height ?? 0) < ($1.height ?? 0) }?.label
                )
            }, storefront: storefront)
        } catch {
            throw NetworkError.decodingFailed
        }
    }

    /// What both shapes reduce to before the shared rules are applied.
    private struct RawEntry {
        let collectionID: String?
        let title: String?
        let author: String?
        let artwork: String?
    }

    /// Entries without a usable id or title are dropped: with no id a row can
    /// never be resolved to a feed, and with no title there is nothing to
    /// show. Rank counts the rows that survive, so the numbers on screen are
    /// contiguous — a gap would read as a rendering fault rather than as
    /// Apple having listed something we could not use.
    private static func entries(from raw: [RawEntry], storefront: String) -> [ChartEntry] {
        raw.compactMap { entry -> (Int, String, String, URL?)? in
            guard let rawID = entry.collectionID, let collectionID = Int(rawID) else { return nil }
            guard let title = entry.title, !title.isEmpty else { return nil }
            return (collectionID, title, entry.author ?? "", entry.artwork.flatMap(URL.init(string:)))
        }
        .enumerated()
        .map { index, entry in
            ChartEntry(
                id: "itunes:\(entry.0)",
                collectionID: entry.0,
                rank: index + 1,
                title: entry.1,
                author: entry.2,
                artworkURL: entry.3,
                storefront: storefront
            )
        }
    }

    // MARK: - Wire shapes

    private struct TopResponse: Decodable {
        let feed: Feed
        struct Feed: Decodable { let results: [Result] }
        struct Result: Decodable {
            let id: String?
            let name: String?
            let artistName: String?
            let artworkUrl100: String?
        }
    }

    private struct GenreResponse: Decodable {
        let feed: Feed
        struct Feed: Decodable { let entry: EntryList? }
    }

    /// An empty chart omits `entry` entirely, and a chart with one show has
    /// been seen to serve it as a bare object rather than a one-element array.
    /// Five lines here removes a whole class of storefront-specific crash.
    private struct EntryList: Decodable {
        let values: [Entry]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let many = try? container.decode([Entry].self) {
                values = many
            } else {
                values = [try container.decode(Entry.self)]
            }
        }
    }

    private struct Entry: Decodable {
        let name: Labelled
        let artist: Labelled?
        let image: [Image]
        let id: IDField

        enum CodingKeys: String, CodingKey {
            case name = "im:name"
            case artist = "im:artist"
            case image = "im:image"
            case id
        }

        struct Image: Decodable {
            let label: String
            /// A string on the wire, like every legacy attribute.
            let height: Int?

            enum CodingKeys: String, CodingKey { case label, attributes }
            enum AttributeKeys: String, CodingKey { case height }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                label = try container.decode(String.self, forKey: .label)
                let attributes = try? container.nestedContainer(
                    keyedBy: AttributeKeys.self, forKey: .attributes
                )
                height = (try? attributes?.decode(String.self, forKey: .height)).flatMap { Int($0) }
            }
        }

        struct IDField: Decodable {
            let attributes: Attributes
            struct Attributes: Decodable {
                let collectionID: String?
                enum CodingKeys: String, CodingKey { case collectionID = "im:id" }
            }
        }
    }

    private struct Labelled: Decodable { let label: String }
}
