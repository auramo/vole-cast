import SwiftUI

/// One episode's show notes, and where it can be played from.
struct EpisodeDetailView: View {
    let episode: Episode
    @Binding var path: NavigationPath

    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if episode.isPlayed {
                    Label("Played", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                }
                playButton
                showLink
                if !episode.summary.isEmpty {
                    Text(HTMLText.plain(from: episode.summary))
                        .font(.callout)
                }
                if let page = episode.pageURL, let url = URL(string: page) {
                    Link("Open Episode Page", destination: url)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Opens this episode's show, scrolled to this episode.
    ///
    /// The neighbours are the point: a multi-part series is only discoverable
    /// from the episode you are on, and hunting for part two of something
    /// published years ago means scrolling a very long list. It doubles as the
    /// only place this screen says which show you are listening to.
    @ViewBuilder
    private var showLink: some View {
        if let podcast = episode.podcast {
            Button {
                path.append(
                    ShowDestination(podcast: podcast, focus: episode.persistentModelID)
                )
            } label: {
                HStack(spacing: 8) {
                    ArtworkView(url: podcast.artworkURL, size: 28)
                    Text(podcast.title.isEmpty ? "Show" : podcast.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show all episodes of \(podcast.title)")
            .accessibilityHint("Opens the show at this episode")
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if URL(string: episode.audioURL) != nil, !episode.audioURL.isEmpty {
            Button {
                player.toggle(episode)
            } label: {
                playLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// Tapping a finished episode starts it over, as it does on the row's button.
    @ViewBuilder
    private var playLabel: some View {
        if isPlayingThis {
            Label("Pause", systemImage: "pause.fill")
        } else if episode.isPlayed {
            Label("Replay", systemImage: "arrow.counterclockwise")
        } else {
            Label("Play", systemImage: "play.fill")
        }
    }

    private var isPlayingThis: Bool {
        player.isCurrent(episode) && player.isPlaying
    }
}
