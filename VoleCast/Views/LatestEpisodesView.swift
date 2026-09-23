import SwiftData
import SwiftUI

/// The newest episodes across every subscription, newest first.
struct LatestEpisodesView: View {
    @Binding var path: NavigationPath
    let onFindShows: () -> Void

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
                    List(episodes) { episode in
                        // Two sibling buttons rather than a `NavigationLink`
                        // wrapping the row: a button inside a link's label
                        // doesn't get its own taps in a list, the link's
                        // gesture takes them. `path.append` pushes exactly what
                        // `NavigationLink(value:)` did, and the destinations
                        // below are unchanged.
                        HStack(spacing: 8) {
                            Button {
                                path.append(episode)
                            } label: {
                                LatestEpisodeRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows episode details")

                            EpisodePlayButton(episode: episode)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Latest")
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
        }
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

private struct LatestEpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The show's artwork unless the episode has its own.
            ArtworkView(url: episode.artworkURL ?? episode.podcast?.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                if let show = episode.podcast?.title, !show.isEmpty {
                    Text(show)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(episode.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            // Without this the gap between the text and the play button belongs
            // to neither control and swallows taps.
            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    let container = VoleCastModelContainer.makeInMemory()
    LatestEpisodesView(path: .constant(NavigationPath()), onFindShows: {})
        .modelContainer(container)
        .environment(PlayerModel(playback: AVPlayerAudioEngine(), context: ModelContext(container)))
}
