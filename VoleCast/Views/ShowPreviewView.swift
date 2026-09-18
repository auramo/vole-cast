import SwiftData
import SwiftUI

/// Where a show comes from before you subscribe: a directory hit, or a feed URL.
enum ShowPreviewSource: Hashable {
    case directory(PodcastSearchResult)
    case feedURL(URL)

    var url: URL {
        switch self {
        case .directory(let result): result.feedURL
        case .feedURL(let url): url
        }
    }

    var directoryResult: PodcastSearchResult? {
        switch self {
        case .directory(let result): result
        case .feedURL: nil
        }
    }
}

/// A show as it is before subscribing: what it's called, what it's about, and
/// what's in it lately.
struct ShowPreviewView: View {
    let source: ShowPreviewSource

    @Environment(\.feedLoader) private var feedLoader
    @Environment(\.modelContext) private var context

    @State private var phase: Phase = .loading
    @State private var subscribed = false
    @State private var subscribeError: NetworkError?

    private enum Phase {
        case loading
        case loaded(LoadedFeed)
        case failed(NetworkError)
    }

    var body: some View {
        List {
            Section {
                header
            }
            switch phase {
            case .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
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
        return source.directoryResult?.title ?? "Show"
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
        return source.directoryResult?.artworkURL?.absoluteString
    }

    private var author: String? {
        if case .loaded(let loaded) = phase, !loaded.feed.author.isEmpty { return loaded.feed.author }
        return source.directoryResult?.author
    }

    private func load() async {
        phase = .loading
        do {
            let loaded = try await feedLoader.load(source.url)
            phase = .loaded(loaded)
            subscribed = Subscriptions.existing(identity: loaded.identityKey, in: context) != nil
        } catch is CancellationError {
        } catch {
            phase = .failed(NetworkError(from: error))
        }
    }

    private func subscribe(_ loaded: LoadedFeed) {
        do {
            try Subscriptions.subscribe(
                to: loaded,
                directoryResult: source.directoryResult,
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
