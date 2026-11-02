import SwiftData
import SwiftUI

/// The newest episodes across every subscription, newest first.
struct LatestEpisodesView: View {
    @Binding var path: NavigationPath
    let onFindShows: () -> Void

    @Environment(\.feedLoader) private var feedLoader
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// Built in `onAppear` rather than an initialiser so it picks up the
    /// environment's loader, which previews and tests replace.
    @State private var refresher: LibraryRefresh?

    @Query(LatestEpisodes.descriptor())
    private var episodes: [Episode]

    /// Only to tell "nothing subscribed yet" apart from "subscribed, but no
    /// episodes have dates" — the list itself comes from the query above.
    @Query private var podcasts: [Podcast]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if episodes.isEmpty {
                    emptyState
                } else {
                    List {
                        if let refresher, refresher.failureCount > 0 {
                            failureNote(refresher.failureCount)
                        }
                        episodeRows
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Latest")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { refreshButton }
            }
            .refreshable { await existingRefresher().refreshAll(force: true) }
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0, path: $path) }
            .navigationDestination(for: ShowDestination.self) {
                PodcastDetailView(show: $0, path: $path)
            }
        }
        // On the stack rather than the `Group` inside it: the Group swaps
        // between the empty state and the list, and that change of identity
        // re-ran this, refetching every feed two or three times on launch.
        //
        // Built here rather than in `onAppear` too, because the order of those
        // two is not guaranteed and a refresher that does not exist yet
        // refreshes nothing — which is why the first version of this silently
        // did nothing at all.
        //
        // Stale-gated, so opening the tab doesn't hammer every feed.
        //
        // Only with the window in front. A sync push launches the app in the
        // background, and on a Mac that builds this screen too: the 1.0 copy
        // on a laptop refreshed every feed on every push, and each of those
        // refreshes could put a second copy of a new episode into sync. Coming
        // to the front afterwards is a phase change, so nothing is skipped for
        // good — and a return after the stale window now refreshes as well.
        //
        // A `Task` of its own rather than `.task(id:)`, which would cancel a
        // refresh halfway through the moment the phase flickers to inactive.
        // CarPlay refreshes through its own scene and is untouched by this.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await existingRefresher().refreshAll(force: false) }
        }
    }

    /// Two sibling buttons rather than a `NavigationLink` wrapping the row: a
    /// button inside a link's label doesn't get its own taps in a list, the
    /// link's gesture takes them. `path.append` pushes exactly what
    /// `NavigationLink(value:)` did, and the destinations are unchanged.
    private var episodeRows: some View {
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
        }
    }

    private func existingRefresher() -> LibraryRefresh {
        if let refresher { return refresher }
        let made = LibraryRefresh(feedLoader: feedLoader, context: modelContext)
        refresher = made
        return made
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let refresher, refresher.isRefreshing {
            ProgressView()
        } else {
            Button {
                Task { await existingRefresher().refreshAll(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    /// Quiet on purpose: every stored episode is still here, so a show that
    /// couldn't be reached is a note rather than a blocked screen.
    private func failureNote(_ count: Int) -> some View {
        Label(
            count == 1 ? "1 show couldn't be refreshed" : "\(count) shows couldn't be refreshed",
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var emptyState: some View {
        if podcasts.isEmpty {
            ContentUnavailableView {
                Label("Nothing Yet", systemImage: "waveform")
            } description: {
                Text("Episodes from shows you subscribe to appear here.")
            } actions: {
                Button("Find Shows", action: onFindShows)
            }
        } else {
            ContentUnavailableView(
                "No Dated Episodes",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Your shows haven't published anything with a date on it.")
            )
        }
    }
}

#Preview {
    let container = VoleCastModelContainer.makeInMemory()
    LatestEpisodesView(path: .constant(NavigationPath()), onFindShows: {})
        .modelContainer(container)
        .environment(PlayerModel(playback: AVPlayerAudioEngine(), context: ModelContext(container)))
}
