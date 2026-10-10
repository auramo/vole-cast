import SwiftData
import SwiftUI

/// Where a show comes from before you subscribe: a directory hit, a feed URL,
/// or a row in a chart.
///
/// The chart case is the odd one. A chart names a show by an iTunes collection
/// id and nothing else, so unlike the other two it arrives without the feed
/// URL this screen exists to load — that has to be looked up first.
enum ShowPreviewSource: Hashable {
    case directory(PodcastSearchResult)
    case feedURL(URL)
    case chart(ChartEntry)

    /// nil for a chart entry, whose URL is not known until it is resolved.
    var url: URL? {
        switch self {
        case .directory(let result): result.feedURL
        case .feedURL(let url): url
        case .chart: nil
        }
    }

    var directoryResult: PodcastSearchResult? {
        switch self {
        case .directory(let result): result
        case .feedURL, .chart: nil
        }
    }

    /// What to draw before anything has loaded. A chart row already knows the
    /// title, author and artwork, so arriving from Discover shows the show
    /// rather than a placeholder — same as arriving from search.
    var placeholder: (title: String, author: String, artworkURL: String?)? {
        switch self {
        case .directory(let result):
            (result.title, result.author, result.artworkURL?.absoluteString)
        case .chart(let entry):
            (entry.title, entry.author, entry.artworkURL?.absoluteString)
        case .feedURL:
            nil
        }
    }
}

/// A show as it is before subscribing: what it's called, what it's about, and
/// what's in it lately.
struct ShowPreviewView: View {
    let source: ShowPreviewSource

    @Environment(\.feedLoader) private var feedLoader
    @Environment(\.modelContext) private var context

    @Environment(\.podcastLookup) private var lookup

    @State private var phase: Phase = .loading
    @State private var subscribed = false
    @State private var subscribeError: NetworkError?
    /// Set once a chart entry has been resolved, so subscribing records the
    /// collection id exactly as it would arriving from search.
    @State private var resolved: PodcastSearchResult?

    private enum Phase {
        /// Looking a chart entry's feed up. Draws the same spinner as
        /// `loading`; separate so the state machine does not lie about which
        /// request is in flight.
        case resolving
        case loading
        case loaded(LoadedFeed)
        /// The show has no feed anyone else can play. Not a failure, and
        /// deliberately not `failed`: there is no Try Again, because trying
        /// again would never produce a different answer.
        case unavailable
        case failed(NetworkError)
    }

    var body: some View {
        List {
            Section {
                header
            }
            switch phase {
            case .resolving, .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            case .unavailable:
                Section {
                    ContentUnavailableView(
                        "Not Available as a Podcast Feed",
                        systemImage: "lock.circle",
                        description: Text(
                            "This show is exclusive to Apple Podcasts, so no other app can play it."
                        )
                    )
                }
            case .failed(let error):
                Section {
                    ErrorView(error: error) { await load() }
                }
            case .loaded(let loaded):
                if !loaded.feed.summary.isEmpty {
                    Section("About") {
                        Text(HTMLText.plain(from: loaded.feed.summary))
                            .font(.callout)
                    }
                }
                Section("Latest Episodes") {
                    ForEach(loaded.feed.episodes.prefix(20), id: \.guid) { episode in
                        EpisodePreviewRow(episode: episode)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(
            "Couldn't Subscribe",
            isPresented: Binding(get: { subscribeError != nil }, set: { if !$0 { subscribeError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscribeError?.recoverySuggestion ?? "")
        }
    }

    private var title: String {
        if case .loaded(let loaded) = phase, !loaded.feed.title.isEmpty {
            return loaded.feed.title
        }
        return source.placeholder?.title ?? "Show"
    }

    /// Drawn from the directory result while the feed loads, so arriving here
    /// from search never shows a blank screen.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: artworkURL, size: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                if let author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                subscribeButton
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subscribeButton: some View {
        if subscribed {
            Label("Subscribed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        } else if case .loaded(let loaded) = phase {
            Button("Subscribe") { subscribe(loaded) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var artworkURL: String? {
        if case .loaded(let loaded) = phase, let art = loaded.feed.artworkURL { return art }
        return resolved?.artworkURL?.absoluteString ?? source.placeholder?.artworkURL
    }

    private var author: String? {
        if case .loaded(let loaded) = phase, !loaded.feed.author.isEmpty { return loaded.feed.author }
        return resolved?.author ?? source.placeholder?.author
    }

    private func load() async {
        do {
            guard let url = try await feedURL() else { return }
            phase = .loading
            let loaded = try await feedLoader.load(url)
            phase = .loaded(loaded)
            subscribed = Subscriptions.existing(identity: loaded.identityKey, in: context) != nil
        } catch is CancellationError {
        } catch {
            phase = .failed(NetworkError(from: error))
        }
    }

    /// The feed to load, looking it up first when all we have is a chart
    /// entry's collection id.
    ///
    /// Returns nil having already set the phase, for the one case that is not
    /// an error: a show with no public feed, which cannot be loaded now or
    /// ever.
    private func feedURL() async throws -> URL? {
        if let known = source.url { return known }
        guard case .chart(let entry) = source else { return nil }

        phase = .resolving
        // Asked of the store the show charted in, not the device's. A show is
        // only in the stores that carry it, and asking the wrong one comes
        // back empty — indistinguishable here from having no feed at all.
        guard let result = try await lookup.podcast(
            collectionID: entry.collectionID,
            storefront: entry.storefront
        ) else {
            phase = .unavailable
            return nil
        }
        resolved = result
        return result.feedURL
    }

    private func subscribe(_ loaded: LoadedFeed) {
        do {
            try Subscriptions.subscribe(
                to: loaded,
                // A chart entry resolves into the same kind of result a search
                // hit is, so a show subscribed to from Discover records its
                // collection id just as one found by name does.
                directoryResult: resolved ?? source.directoryResult,
                in: context
            )
            subscribed = true
        } catch SubscriptionError.alreadySubscribed {
            // Nothing went wrong — it's in the library, which is what the
            // button was for.
            subscribed = true
        } catch {
            subscribeError = NetworkError(from: error)
        }
    }
}

private struct EpisodePreviewRow: View {
    let episode: ParsedEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(episode.title)
                .font(.subheadline)
                .lineLimit(2)
            Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
