import SwiftUI

/// What's playing, shown as the tab view's bottom accessory.
///
/// The system supplies the shape, material and placement, so this draws only
/// its contents — no background, no divider, no transition of its own.
struct MiniPlayerBar: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if let episode = player.current {
            content(for: episode)
                .overlay(alignment: .bottom) { progress }
        }
    }

    /// A hairline rather than a control: scrubbing belongs to the full player.
    private var progress: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * player.fraction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }

    private func content(for episode: PlayableEpisode) -> some View {
        HStack(spacing: 12) {
            // The same two-sibling-buttons discipline as an episode row: the
            // artwork and text open the full player, the controls do not.
            Button {
                player.isExpanded = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: episode.artworkURL?.absoluteString, size: 40)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(episode.title)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        if let error = player.error {
                            Label(
                                error.errorDescription ?? "Playback Stopped",
                                systemImage: error.symbolName
                            )
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        } else if !episode.showTitle.isEmpty {
                            Text(episode.showTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")

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
        .padding(.horizontal, 8)
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
