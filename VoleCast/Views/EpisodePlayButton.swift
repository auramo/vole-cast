import SwiftUI

/// The round play control at the right edge of an episode row.
///
/// Shared by every list that shows episodes, so they can't drift apart. The
/// rows themselves are deliberately not shared — a cross-show list needs
/// artwork and the show's name, where a single show's list would only be
/// repeating itself.
struct EpisodePlayButton: View {
    let episode: Episode

    @Environment(PlayerModel.self) private var player

    private var isCurrent: Bool { player.isCurrent(episode) }
    private var isPlayingThis: Bool { isCurrent && player.isPlaying }
    private var isBufferingThis: Bool { isCurrent && player.isBuffering }

    /// `audioURL` is a `String` off a feed and can be empty or nonsense.
    private var isPlayable: Bool {
        URL(string: episode.audioURL)?.host() != nil
    }

    var body: some View {
        Button {
            player.toggle(episode)
        } label: {
            ZStack {
                progressRing
                icon
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.borderless)
        .disabled(!isPlayable)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var icon: some View {
        if isBufferingThis {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPlayable ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
    }

    /// How far in you already were, without costing a row of its own.
    @ViewBuilder
    private var progressRing: some View {
        if !isCurrent, let fraction = storedFraction {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var storedFraction: Double? {
        guard let duration = episode.duration, duration > 0 else { return nil }
        let fraction = episode.playbackPosition / duration
        guard fraction > 0.01, fraction < 1 else { return nil }
        return fraction
    }

    private var label: String {
        if isPlayingThis { return "Pause" }
        if episode.playbackPosition > 0 { return "Resume \(episode.title)" }
        return "Play \(episode.title)"
    }
}
