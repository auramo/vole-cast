import SwiftUI

/// The round play control at the right edge of an episode row.
///
/// Shared by every list that shows episodes, so they can't drift apart, as is
/// the row beside it in the cross-show lists (`EpisodeListRow`). A single
/// show's own list keeps a smaller row of its own: under that show's header,
/// repeating its artwork and name would only be repeating itself.
struct EpisodePlayButton: View {
    let episode: Episode

    @Environment(PlayerModel.self) private var player

    private var isCurrent: Bool { player.isCurrent(episode) }
    private var isPlayingThis: Bool { isCurrent && player.isPlaying }
    private var isBufferingThis: Bool { isCurrent && player.isBuffering }
    /// Tapping starts from the beginning, so the icon says that rather than
    /// "play". It goes as soon as a replay is under way.
    private var offersReplay: Bool { episode.isPlayed && !isPlayingThis && !isBufferingThis }

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
            Image(systemName: iconName)
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPlayable ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
    }

    private var iconName: String {
        if isPlayingThis { return "pause.circle.fill" }
        return offersReplay ? "arrow.counterclockwise.circle.fill" : "play.circle.fill"
    }

    /// How far in you already were, without costing a row of its own.
    @ViewBuilder
    private var progressRing: some View {
        if let fraction = ringFraction {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    /// Shown for anything part-listened, including the episode in the player
    /// once it is paused — a stopped episode with no sign of how far in it is
    /// looks like one you never started. It goes only while this episode is
    /// actually running, where the icon is already a pause button and a ring
    /// creeping around it is noise.
    private var ringFraction: Double? {
        guard !offersReplay else { return nil }
        guard isCurrent else { return storedFraction }
        guard !isPlayingThis, !isBufferingThis else { return nil }
        // The player's own reading rather than the stored one: it is live, so
        // the ring is right the moment you pause, and the engine knows the
        // real duration even for a feed that never declared one.
        return meaningful(player.fraction)
    }

    private var storedFraction: Double? {
        guard let duration = episode.duration, duration > 0 else { return nil }
        return meaningful(episode.playbackPosition / duration)
    }

    /// Nothing for barely-started or finished: a ring too short to see reads
    /// as a rendering fault, and a full one as a progress bar that stuck.
    private func meaningful(_ fraction: Double) -> Double? {
        guard fraction > 0.01, fraction < 1 else { return nil }
        return fraction
    }

    /// Spelled out through `String(localized:)` for the reason the header in
    /// `PodcastDetailView` is: this is a `String`, so a literal here would be
    /// read aloud in English whatever language the phone is in.
    private var label: String {
        if isPlayingThis { return String(localized: "Pause") }
        if offersReplay { return String(localized: "Replay \(episode.title)") }
        if episode.playbackPosition > 0 {
            return String(localized: "Resume \(episode.title)")
        }
        return String(localized: "Play \(episode.title)")
    }
}
