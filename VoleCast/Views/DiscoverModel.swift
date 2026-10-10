import Foundation

/// What the Discover half of the Search tab binds to.
///
/// Holds nothing the search half holds and talks to nothing the search half
/// talks to. That separation is the point rather than tidiness: charts come
/// from an endpoint Apple does not document and has retired the sibling of, so
/// the half of this screen that finds shows by name or by pasted URL must not
/// be able to go down with it.
@MainActor
@Observable
final class DiscoverModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(ChartPage)
        case empty
        /// The chosen country has no Apple podcast store, or Apple will not
        /// serve its chart. Kept apart from `failed` because the remedy is to
        /// pick somewhere else, not to try again.
        case unavailableCountry(String)
        case failed(NetworkError)
    }

    /// nil is the overall chart.
    var genre: PodcastGenre?
    var storefront: String
    private(set) var state: State = .idle

    private let charts: any PodcastCharts
    private let limit: Int
    /// Charts already fetched this session, by country and genre.
    ///
    /// Above `URLCache` on purpose. The cache makes a second fetch cheap but
    /// still asynchronous, so without this every flick between genres would
    /// blink through a spinner to redraw a list it had a moment ago.
    private var pages: [String: ChartPage] = [:]

    init(
        charts: any PodcastCharts,
        storefront: String = Storefront.device,
        limit: Int = 100
    ) {
        self.charts = charts
        self.storefront = storefront
        self.limit = limit
    }

    /// Driven by `.task(id:)`, which restarts it whenever the genre or the
    /// country changes.
    func load() async {
        if let remembered = pages[key] {
            state = .loaded(remembered)
            return
        }
        await fetch(revalidating: false)
    }

    /// Pull-to-refresh. Goes past the memo and asks the network to revalidate,
    /// which is the same thing a feed refresh does.
    func refresh() async {
        await fetch(revalidating: true)
    }

    private var key: String { "\(storefront)|\(genre?.id ?? 0)" }

    private func fetch(revalidating: Bool) async {
        // Both captured before the await: either can change while it is in
        // flight, and the page must be filed under what was asked for rather
        // than under whatever is selected when the answer arrives.
        let requested = key
        let country = storefront
        state = .loading
        do {
            let page = try await charts.top(
                limit: limit,
                genre: genre,
                storefront: storefront,
                revalidating: revalidating
            )
            try Task.checkCancellation()
            pages[requested] = page
            state = page.entries.isEmpty ? .empty : .loaded(page)
        } catch is CancellationError {
            // A newer genre or country is already loading; leave its state alone.
        } catch {
            state = Self.state(for: NetworkError(from: error), storefront: country)
        }
    }

    /// Only a refusal counts as "no store here".
    ///
    /// A 5xx deliberately does not, though an unknown country does provoke one
    /// from the newer endpoint. Apple's chart host has been seen timing out
    /// and erring on a country that plainly does have a store — read as a
    /// missing storefront, that becomes the app telling someone in Helsinki
    /// that Finland has no Apple podcast store, which is both wrong and
    /// unarguable. A server error is far more often a bad minute than a bad
    /// country, so it keeps its Try Again and says nothing it cannot support.
    ///
    /// The cost is that choosing a country Apple really does not serve reads
    /// as a plain failure on the overall chart, and only the genre charts —
    /// whose endpoint answers 400 — name the actual problem. Being vague
    /// sometimes beats being confidently wrong.
    private static func state(for error: NetworkError, storefront: String) -> State {
        switch error {
        case .invalidResponse, .notFound:
            .unavailableCountry(storefront)
        default:
            .failed(error)
        }
    }
}
