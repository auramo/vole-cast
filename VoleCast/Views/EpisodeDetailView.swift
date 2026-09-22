import SwiftUI

/// One episode's show notes, and where it can be played from.
struct EpisodeDetailView: View {
    let episode: Episode

    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                playButton
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

    @ViewBuilder
    private var playButton: some View {
        if URL(string: episode.audioURL) != nil, !episode.audioURL.isEmpty {
            Button {
                player.toggle(episode)
            } label: {
                Label(
                    isPlayingThis ? "Pause" : "Play",
                    systemImage: isPlayingThis ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var isPlayingThis: Bool {
        player.isCurrent(episode) && player.isPlaying
    }
}
