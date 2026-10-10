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

    /// The two chart endpoints disagree about how they refuse a country they
    /// do not have — the legacy one answers 400, the newer one 500 — and
    /// neither says why. A genuine Apple outage looks the same as asking for
    /// Åland, so this cannot be certain, and the screen it leads to is worded
    /// as a possibility with a way out rather than as a diagnosis.
    private static func state(for error: NetworkError, storefront: String) -> State {
        switch error {
        case .invalidResponse, .serverError, .notFound:
            .unavailableCountry(storefront)
        default:
            .failed(error)
        }
    }
}
