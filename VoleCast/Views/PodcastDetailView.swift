import SwiftData
import SwiftUI

/// A subscribed show and its episodes.
struct PodcastDetailView: View {
    let podcast: Podcast
    /// Needed because the rows navigate by appending rather than wrapping
    /// themselves in a `NavigationLink` — see the episode section below.
    @Binding var path: NavigationPath

    @Environment(\.feedLoader) private var feedLoader
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerModel.self) private var player

    @State private var refreshError: NetworkError?
    @State private var confirmingUnsubscribe = false

    /// Long enough not to hammer a feed on every visit, short enough that a
    /// show checked this morning shows this afternoon's episode.
    private static let staleAfter: TimeInterval = 30 * 60

    var body: some View {
        List {
            Section { header }

            if let error = refreshError {
                Section {
                    Label(error.errorDescription ?? "", systemImage: error.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !podcast.summary.isEmpty {
                Section("About") {
                    Text(HTMLText.plain(from: podcast.summary))
                        .font(.callout)
                }
            }

            Section("Episodes") {
                if podcast.episodeCount == 0 {
                    Text("No episodes yet.")
                        .foregroundStyle(.secondary)
                }
                // The same two sibling buttons as Latest and History, for the
                // same reason: a button inside a `NavigationLink`'s label does
                // not get its own taps in a list, so the play control would be
                // dead. `path.append` pushes exactly what the link pushed.
                ForEach(podcast.orderedEpisodes) { episode in
                    HStack(spacing: 8) {
                        Button {
                            path.append(episode)
                        } label: {
                            EpisodeListRow(episode: episode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows episode details")

                        EpisodePlayButton(episode: episode)
                    }
                }
            }
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
        .refreshable { await refresh(revalidating: true) }
        .task { await refreshIfStale() }
        .toolbar {
            Menu("Show Options", systemImage: "ellipsis.circle") {
                Button("Copy Feed URL", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = podcast.feedURL
                }
                if let website = podcast.websiteURL, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Open Website", systemImage: "safari")
                    }
                }
                Button("Unsubscribe", systemImage: "trash", role: .destructive) {
                    confirmingUnsubscribe = true
                }
            }
        }
        .confirmationDialog(
            "Unsubscribe from \(podcast.title)?",
            isPresented: $confirmingUnsubscribe,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) {
                player.stopIfPlaying(from: podcast)
                Subscriptions.unsubscribe(podcast, in: context)
                dismiss()
            }
        } message: {
            Text("Its episodes will be removed from your library.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: podcast.artworkURL, size: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title).font(.headline)
                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("^[\(podcast.episodeCount) episode](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func refreshIfStale() async {
        guard let last = podcast.lastRefreshedAt else {
            await refresh(revalidating: false)
            return
        }
        if Date.now.timeIntervalSince(last) > Self.staleAfter {
            await refresh(revalidating: true)
        }
    }

    private func refresh(revalidating: Bool) async {
        guard let url = FeedURL.normalize(podcast.feedURL) else { return }
        do {
            let loaded = try await feedLoader.load(url, revalidating: revalidating)
            Subscriptions.refresh(loaded, into: podcast, in: context)
            refreshError = nil
        } catch is CancellationError {
        } catch {
            // The stored episodes are still there, so this is a note, not a
            // blocking failure.
            refreshError = NetworkError(from: error)
        }
    }
}
