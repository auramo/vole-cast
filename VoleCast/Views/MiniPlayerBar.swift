import SwiftUI

/// What's playing, shown as the tab view's bottom accessory.
///
/// The system supplies the shape, material and placement, so this draws only
/// its contents — no background, no divider, no transition of its own.
struct MiniPlayerBar: View {
    private enum Layout {
        /// Smaller than it was. The accessory's height follows the artwork, and
        /// at 40 the picture filled it corner to corner — no room above or
        /// below, and its edges running into the rounded ends of the bar.
        static let artwork: CGFloat = 32
        /// Clear of the rounded ends, which eat into the corners at 8.
        static let horizontalInset: CGFloat = 14
        /// Lifts the artwork off the top and bottom edges, and leaves the band
        /// the progress line sits in.
        static let verticalInset: CGFloat = 8
    }

    @Environment(PlayerModel.self) private var player

    var body: some View {
        if let episode = player.current {
            content(for: episode)
                .overlay(alignment: .bottom) { progress }
        }
    }

    /// A hairline rather than a control: scrubbing belongs to the full player.
    ///
    /// It lives in the band of padding below the contents, which is why that
    /// padding exists. Drawn against an unpadded row it lands across the
    /// bottom of the artwork and reads as part of the picture.
    private var progress: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * player.fraction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.bottom, 5)
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
                    ArtworkView(url: episode.artworkURL?.absoluteString, size: Layout.artwork)

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
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.vertical, Layout.verticalInset)
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
