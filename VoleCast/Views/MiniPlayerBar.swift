import SwiftUI

/// The bar that sits above the tab bar whenever something is loaded.
///
/// Inset into each tab's content rather than overlaid, so the last row of a
/// list scrolls clear of it instead of hiding underneath.
struct MiniPlayerBar: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if let episode = player.current {
            VStack(spacing: 0) {
                progress
                content(for: episode)
            }
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// A hairline rather than a control: scrubbing belongs to the full player.
    private var progress: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.tint)
                .frame(width: proxy.size.width * player.fraction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .background(.quaternary)
        .accessibilityHidden(true)
    }

    private func content(for episode: PlayableEpisode) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: episode.artworkURL?.absoluteString, size: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(episode.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                if !episode.showTitle.isEmpty {
                    Text(episode.showTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                player.skip(by: -NowPlayingCentre.skipBackward)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Skip back 15 seconds")

            playPause
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var playPause: some View {
        if player.isBuffering {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        } else {
            Button {
                if player.isPlaying {
                    player.pause()
                } else {
                    player.resume()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }
}
