import SwiftUI

/// The expanded player: artwork, a draggable scrubber, and the transport.
///
/// Presented as a sheet, which brings drag-to-dismiss with it rather than
/// needing a hand-written gesture.
struct FullPlayerView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    /// Where the thumb is while a drag is in progress.
    ///
    /// The slider binds to this in preference to the player's own position,
    /// because position keeps ticking during a drag and would drag the thumb
    /// back out from under the finger.
    @State private var dragging: Double?

    var body: some View {
        NavigationStack {
            if let episode = player.current {
                content(for: episode)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "waveform")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func content(for episode: PlayableEpisode) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ArtworkView(url: episode.artworkURL?.absoluteString, size: 260)
                .shadow(color: .black.opacity(0.15), radius: 18, y: 8)

            VStack(spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if !episode.showTitle.isEmpty {
                    Text(episode.showTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)

            if let error = player.error {
                failure(error)
            }

            scrubber
            transport

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func failure(_ error: PlaybackError) -> some View {
        VStack(spacing: 2) {
            Label(error.errorDescription ?? "", systemImage: error.symbolName)
                .font(.subheadline.weight(.medium))
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.red)
        .padding(.horizontal)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { dragging ?? player.position },
                    set: { dragging = $0 }
                ),
                in: 0...sliderUpperBound,
                onEditingChanged: { editing in
                    guard !editing else { return }
                    // Seek on release only. Seeking live issues a burst of
                    // range requests against a stream with no cache behind it.
                    if let dragging { player.seek(to: dragging) }
                    dragging = nil
                }
            )
            .disabled(player.duration == nil)

            HStack {
                Text(PlaybackTime.clock(dragging ?? player.position))
                Spacer()
                Text(remaining)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    /// A slider needs a non-empty range even before the duration resolves.
    private var sliderUpperBound: Double {
        guard let duration = player.duration, duration > 0 else {
            return max(player.position, 1)
        }
        return duration
    }

    private var remaining: String {
        guard let duration = player.duration, duration > 0 else {
            return PlaybackTime.placeholder
        }
        return PlaybackTime.remaining(duration - (dragging ?? player.position))
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 44) {
            Button {
                player.skip(by: -NowPlayingCentre.skipBackward)
            } label: {
                Image(systemName: "gobackward.15").font(.title)
            }
            .accessibilityLabel("Skip back 15 seconds")

            playPause

            Button {
                player.skip(by: NowPlayingCentre.skipForward)
            } label: {
                Image(systemName: "goforward.30").font(.title)
            }
            .accessibilityLabel("Skip forward 30 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var playPause: some View {
        if player.isBuffering {
            ProgressView()
                .controlSize(.large)
                .frame(width: 64, height: 64)
        } else {
            Button {
                if player.isPlaying { player.pause() } else { player.resume() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }
}
