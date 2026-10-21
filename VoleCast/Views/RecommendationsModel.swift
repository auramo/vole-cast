import Foundation
import SwiftData

/// One suggested show, with where tapping it should go.
///
/// Flattened on purpose: a publisher row comes from a search result and a
/// genre row from a chart entry, and the list has no business knowing which.
struct RecommendationRow: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let artworkURL: URL?
    let source: ShowPreviewSource
}

/// A group of suggestions and the reason for them.
struct RecommendationSection: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [RecommendationRow]
}

/// What the suggestions segment of the Search tab binds to.
///
/// Holds nothing the search half holds. Suggestions lean on three separate
/// Apple endpoints, and the half of this screen that finds a show by name or
/// by pasted URL must not be able to go down with any of them.
@MainActor
@Observable
final class RecommendationsModel {
    enum EmptyReason: Equatable {
        /// Nothing subscribed yet. The remedy is to find a show.
        case noSubscriptions
        /// Everything subscribed to was added by pasting a feed, so Apple has
        /// nothing to go on — and must not be asked.
        case noAppleShows
        /// Suggestions were found and you already have all of them.
        case nothingNew
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded([RecommendationSection])
        case empty(EmptyReason)
        case failed(NetworkError)
    }

    private(set) var state: State = .idle

    /// At most three sections and five rows each: about four requests on a
    /// cold open, and a screen that can be read at a glance.
    static let maximumSections = 3
    static let rowsPerSection = 5

    private let directory: any PodcastDirectory
    private let lookup: any PodcastLookup
    private let charts: any PodcastCharts
    private let context: ModelContext
    private let storefront: String
    /// Built once per session. Suggestions move at the speed of a chart, and
    /// rebuilding on every visit would blink through a spinner to redraw the
    /// same screen.
    private var built = false

    init(
        directory: any PodcastDirectory,
        lookup: any PodcastLookup,
        charts: any PodcastCharts,
        context: ModelContext,
        storefront: String = Storefront.device
    ) {
        self.directory = directory
        self.lookup = lookup
        self.charts = charts
        self.context = context
        self.storefront = storefront
    }

    func load() async {
        guard !built else { return }
        await rebuild()
    }

    /// Pull-to-refresh. Goes past the memo.
    func refresh() async {
        await rebuild()
    }

    private func rebuild() async {
        state = .loading

        // `built` is NOT set on either early return below: it means "the
        // network work was done", not "a question was answered once". Both
        // of these are a local store query, not a request, so re-checking
        // them is free — and memoizing the answer here is exactly what would
        // strand someone who opens this with nothing subscribed, subscribes
        // from the Find Shows button, and comes back expecting suggestions.
        let subscriptions = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []
        guard !subscriptions.isEmpty else {
            state = .empty(.noSubscriptions)
            return
        }

        let seeds = Recommendations.seeds(
            from: subscriptions,
            playCounts: ListeningTotals.playCounts(in: context),
            limit: Self.maximumSections
        )
        guard !seeds.isEmpty else {
            state = .empty(.noAppleShows)
            return
        }

        // Everything already owned, in both the shapes a candidate can be
        // matched by.
        let ownedIDs = Set(subscriptions.compactMap(\.itunesCollectionID))
        let ownedIdentities = Set(subscriptions.map(\.feedIdentity))

        var sections: [RecommendationSection] = []
        var shown: Set<Int> = []
        // Remembered rather than swallowed. A section failing is a section
        // missing, but *everything* failing is a broken screen, and saying
        // "you already follow all of these" when the network is down would be
        // a confident lie with no way back.
        var failure: NetworkError?

        do {
            if let publisher = try await publisherSection(
                for: seeds[0], ownedIDs: ownedIDs, ownedIdentities: ownedIdentities
            ) {
                shown.formUnion(publisher.rows.compactMap(\.collectionID))
                sections.append(publisher)
            }
        } catch {
            failure = failure ?? NetworkError(from: error)
        }

        var genres: [Int: [PodcastGenre]] = [:]
        do {
            // Sorted rather than left in play-count order: the unsorted order
            // would put your most-played show's id first on the wire, which
            // leaks a ranking this request has no business revealing.
            genres = try await lookup.genres(
                for: seeds.compactMap(\.itunesCollectionID).sorted(), storefront: storefront
            )
        } catch {
            failure = failure ?? NetworkError(from: error)
        }

        // Two seeds can share a subgenre — two news shows is entirely
        // ordinary — and charting it twice would both waste a request and
        // hand `ForEach(sections)` two sections with the same "genre:\(id)"
        // id, which is a SwiftUI diffing hazard. One chart per genre.
        var chartedGenres: Set<Int> = []
        for seed in seeds where sections.count < Self.maximumSections {
            guard let collectionID = seed.itunesCollectionID,
                  let genre = Recommendations.subgenre(from: genres[collectionID] ?? []),
                  !chartedGenres.contains(genre.id)
            else { continue }
            chartedGenres.insert(genre.id)

            do {
                if let section = try await genreSection(
                    for: seed, genre: genre, excluding: ownedIDs.union(shown)
                ) {
                    shown.formUnion(section.rows.compactMap(\.collectionID))
                    sections.append(section)
                }
            } catch {
                failure = failure ?? NetworkError(from: error)
            }
        }

        if !sections.isEmpty {
            state = .loaded(sections)
        } else if let failure {
            // Nothing survived and something broke. Try Again is honest here.
            state = .failed(failure)
        } else {
            // Everything that would be suggested is already followed. Not an
            // error: Try Again would promise something that cannot change.
            state = .empty(.nothingNew)
        }
        built = true
    }

    private func publisherSection(
        for seed: Podcast, ownedIDs: Set<Int>, ownedIdentities: Set<String>
    ) async throws -> RecommendationSection? {
        guard !seed.author.isEmpty else { return nil }
        // Exclusion happens after this request comes back, so the request has
        // to ask for more than a full section's worth: sized off every
        // subscription rather than just this publisher's, since there is no
        // way to know in advance how many of them this publisher made.
        // Clamped to 200: Apple's search endpoint rejects a larger limit, and
        // without the clamp someone with ~195 Apple-sourced subscriptions
        // would silently lose the whole publisher section to a rejected
        // request rather than just an oversized one.
        let found = try await directory.shows(
            byAuthor: seed.author, limit: min(Self.rowsPerSection + ownedIDs.count, 200)
        )

        let rows = Recommendations.surviving(
            found, excludingCollectionIDs: ownedIDs, excludingIdentities: ownedIdentities
        )
        .prefix(Self.rowsPerSection)
        .map {
            RecommendationRow(
                id: $0.id, title: $0.title, author: $0.author,
                artworkURL: $0.artworkURL, source: .directory($0)
            )
        }

        guard !rows.isEmpty else { return nil }
        return RecommendationSection(
            id: "author:\(seed.author)",
            title: String(localized: "More from \(seed.author)"),
            rows: Array(rows)
        )
    }

    private func genreSection(
        for seed: Podcast, genre: PodcastGenre, excluding: Set<Int>
    ) async throws -> RecommendationSection? {
        // Sized off every excluded show, not just this genre's, for the same
        // reason `publisherSection` is: there is no way to know in advance how
        // many of them chart here. Clamped to 200, the most Apple's chart
        // endpoint will return for one request.
        let page = try await charts.top(
            limit: min(Self.rowsPerSection + excluding.count, 200),
            genre: genre,
            storefront: storefront,
            revalidating: false
        )

        let rows = Recommendations.surviving(
            page.entries, excludingCollectionIDs: excluding
        )
        .prefix(Self.rowsPerSection)
        .map {
            RecommendationRow(
                id: $0.id, title: $0.title, author: $0.author,
                artworkURL: $0.artworkURL, source: .chart($0)
            )
        }

        guard !rows.isEmpty else { return nil }
        return RecommendationSection(
            id: "genre:\(genre.id)",
            // "Like", not "because you listen to": a seed can come from
            // subscriptions alone, and the warmer wording would be false.
            title: String(localized: "Like \(seed.title)"),
            rows: Array(rows)
        )
    }
}

private extension RecommendationRow {
    /// The collection id behind a row, for excluding it from later sections.
    var collectionID: Int? {
        switch source {
        case .directory(let result): result.itunesCollectionID
        case .chart(let entry): entry.collectionID
        case .feedURL: nil
        }
    }
}
