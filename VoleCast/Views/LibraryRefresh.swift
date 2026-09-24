import Foundation
import OSLog
import SwiftData

/// Re-fetches every subscription, which is what the Latest list needs and what
/// nothing else in the app did.
///
/// `PodcastDetailView` refreshes one show, on its own screen. Latest is a view
/// of everything, so it needs something that refreshes everything — otherwise
/// the only way to see a new episode is to visit each show in turn, which is
/// exactly how it used to behave.
///
/// Lives in `Views/` for the same reason `PlayerModel` does: it is the layer
/// allowed to see both `Catalog/` and the store.
@MainActor
@Observable
final class LibraryRefresh {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "refresh"
    )

    /// Long enough not to hammer every feed each time the tab is opened, short
    /// enough that a show checked this morning shows this afternoon's episode.
    /// The same policy a single show's screen already uses.
    static let staleAfter: TimeInterval = 30 * 60

    private let feedLoader: any FeedLoading
    private let context: ModelContext

    private(set) var isRefreshing = false
    /// How many shows failed last time. Reported quietly: the stored episodes
    /// are all still there, so a dead feed is a note rather than a blocked
    /// screen.
    private(set) var failureCount = 0

    init(feedLoader: any FeedLoading, context: ModelContext) {
        self.feedLoader = feedLoader
        self.context = context
    }

    /// Refreshes subscriptions that are due, or all of them when `force` is set
    /// — which is what the button and pull-to-refresh ask for.
    func refreshAll(force: Bool) async {
        guard !isRefreshing else { return }

        let due = due(force: force)
        guard !due.isEmpty else {
            // Notice rather than debug: debug messages are not persisted, and
            // "did it even try?" is the first question worth answering when
            // the list looks stale.
            Self.logger.notice("Refresh: nothing due (force: \(force)).")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        // Feeds are fetched concurrently — with a dozen subscriptions, doing
        // them in turn is a dozen round trips of waiting. Only the URL crosses
        // into the group; the models stay here, on the main actor.
        var fetched: [Int: LoadedFeed] = [:]
        var failures = 0

        await withTaskGroup(of: (Int, LoadedFeed?).self) { group in
            for (index, item) in due.enumerated() {
                let url = item.url
                group.addTask { [feedLoader] in
                    // Always revalidating: everything here has been fetched at
                    // least once, so an unchanged feed costs a 304.
                    (index, try? await feedLoader.load(url, revalidating: true))
                }
            }
            for await (index, feed) in group {
                if let feed {
                    fetched[index] = feed
                } else {
                    failures += 1
                }
            }
        }

        // Applied in one pass afterwards: the store is main-actor work, and
        // doing it together lets the queries settle once rather than per show.
        //
        // The podcasts are held directly rather than re-resolved from a
        // `PersistentIdentifier`. `registeredModel(for:)` returned nil for all
        // of them after the awaits above, so every fetched feed was silently
        // dropped — the refresh reported success and changed nothing.
        var applied = 0
        for (index, feed) in fetched {
            let podcast = due[index].podcast
            guard !podcast.isDeleted else { continue }
            Subscriptions.refresh(feed, into: podcast, in: context)
            applied += 1
        }

        failureCount = failures
        Self.logger.notice(
            "Refresh: \(due.count) due, \(fetched.count) fetched, \(applied) applied, \(failures) failed."
        )
    }

    /// The subscriptions worth fetching, paired with the address to fetch.
    private func due(force: Bool) -> [(podcast: Podcast, url: URL)] {
        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []
        return podcasts.compactMap { podcast in
            guard force || isStale(podcast) else { return nil }
            guard let url = FeedURL.normalize(podcast.feedURL) else { return nil }
            return (podcast, url)
        }
    }

    private func isStale(_ podcast: Podcast) -> Bool {
        guard let last = podcast.lastRefreshedAt else { return true }
        return Date.now.timeIntervalSince(last) > Self.staleAfter
    }
}
