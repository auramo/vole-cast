import SwiftData
import SwiftUI

/// A subscribed show and its episodes.
struct PodcastDetailView: View {
    let show: ShowDestination
    /// Needed because the rows navigate by appending rather than wrapping
    /// themselves in a `NavigationLink` — see the episode section below.
    @Binding var path: NavigationPath

    private var podcast: Podcast { show.podcast }

    /// Briefly marks the episode arrived at, so it can be picked out of a list
    /// that may have scrolled a long way to reach it.
    @State private var highlighted: PersistentIdentifier?
    @State private var search = ""

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
        ScrollViewReader { proxy in
            list.onAppear { landOnFocus(proxy) }
        }
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search \(podcast.title)"
        )
    }

    /// Searching is a question about the episodes, so everything that is not
    /// an episode gets out of the way — otherwise the answer starts below a
    /// screenful of artwork and show notes.
    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var list: some View {
        List {
            if !isSearching {
                Section { header }
            }

            if let error = refreshError, !isSearching {
                Section {
                    Label(error.errorDescription ?? "", systemImage: error.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !podcast.summary.isEmpty, !isSearching {
                Section("About") {
                    Text(HTMLText.plain(from: podcast.summary))
                        .font(.callout)
                }
            }

            EpisodeSection(
                feedIdentity: podcast.feedIdentity,
                search: search,
                highlighted: highlighted,
                path: $path
            )
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0, path: $path) }
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

    /// Jumps to the episode this show was opened from.
    ///
    /// The point of the whole thing: a series episode from years ago is buried
    /// hundreds of rows down, and finding its sequel by scrolling is the
    /// problem being solved.
    private func landOnFocus(_ proxy: ScrollViewProxy) {
        guard let focus = show.focus else { return }
        // After the first layout pass: scrolling to a row the list has not
        // built yet does nothing.
        Task { @MainActor in
            proxy.scrollTo(focus, anchor: .center)
            withAnimation(.easeIn(duration: 0.2)) { highlighted = focus }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
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

/// The show's episodes, fetched and filtered by the store.
///
/// Its own view because `@Query` takes its descriptor at initialisation: the
/// search text arrives as a parameter, so typing rebuilds this view with a new
/// query rather than filtering an array that was fetched in full.
private struct EpisodeSection: View {
    let highlighted: PersistentIdentifier?
    @Binding var path: NavigationPath

    @Query private var episodes: [Episode]
    private let isSearching: Bool

    init(
        feedIdentity: String,
        search: String,
        highlighted: PersistentIdentifier?,
        path: Binding<NavigationPath>
    ) {
        self.highlighted = highlighted
        self._path = path
        self.isSearching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self._episodes = Query(
            ShowEpisodes.descriptor(feedIdentity: feedIdentity, matching: search)
        )
    }

    var body: some View {
        Section(header) {
            if episodes.isEmpty {
                Text(isSearching ? "No episodes match." : "No episodes yet.")
                    .foregroundStyle(.secondary)
            }
            // The same two sibling buttons as Latest and History, for the same
            // reason: a button inside a `NavigationLink`'s label does not get
            // its own taps in a list, so the play control would be dead.
            // `path.append` pushes exactly what the link pushed.
            ForEach(episodes) { episode in
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
                .listRowBackground(background(for: episode))
            }
        }
    }

    private var header: String {
        isSearching ? "\(episodes.count) Found" : "Episodes"
    }

    @ViewBuilder
    private func background(for episode: Episode) -> some View {
        if episode.persistentModelID == highlighted {
            Color.accentColor.opacity(0.18)
        } else {
            Color.clear
        }
    }
}
