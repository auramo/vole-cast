import Foundation
import SwiftData

/// What the player screens bind to, and the only place that knows both an
/// `Episode` and the engine.
///
/// `Playback/` deliberately can't see SwiftData, so translating a stored
/// episode into a `PlayableEpisode` happens here. The live model is held only
/// as a `PersistentIdentifier` alongside a snapshot: unsubscribing cascades
/// episodes away, and reading a deleted `@Model` traps.
@MainActor
@Observable
final class PlayerModel {
    private let playback: any AudioPlayback

    /// The snapshot being played. Safe to read after the store has deleted the
    /// episode it came from.
    private(set) var current: PlayableEpisode?
    private(set) var phase: PlaybackPhase = .idle
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var error: PlaybackError?

    /// Whether the full player is showing. Owned here so any screen can raise
    /// it and it survives a tab change.
    var isExpanded = false

    private var currentID: PersistentIdentifier?

    var isPlaying: Bool { phase == .playing }
    var isBuffering: Bool { phase.isBusy }

    /// How far through, 0...1, for the mini-bar's hairline.
    var fraction: Double {
        guard let duration, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    init(playback: any AudioPlayback) {
        self.playback = playback
        self.playback.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - Intent

    func isCurrent(_ episode: Episode) -> Bool {
        currentID == episode.persistentModelID
    }

    /// What the row and bar buttons call: start this episode, or pause and
    /// resume it if it is the one already loaded.
    func toggle(_ episode: Episode) {
        guard isCurrent(episode) else {
            play(episode)
            return
        }
        if isPlaying { playback.pause() } else { playback.play() }
    }

    func play(_ episode: Episode) {
        guard let playable = snapshot(of: episode) else { return }
        error = nil
        currentID = episode.persistentModelID
        current = playable
        position = playable.startAt
        duration = playable.feedDuration
        playback.load(playable)
    }

    /// Acts on whatever is loaded. The bar has only the snapshot, not an
    /// `Episode`, so its controls come through here.
    func resume() {
        guard current != nil else { return }
        playback.play()
    }

    func pause() {
        guard current != nil else { return }
        playback.pause()
    }

    func seek(to time: TimeInterval) {
        guard current != nil else { return }
        playback.seek(to: min(max(time, 0), duration ?? time))
    }

    func skip(by delta: TimeInterval) {
        guard current != nil else { return }
        playback.skip(by: delta)
    }

    /// Called before a show is unsubscribed, because the cascade delete is
    /// about to destroy the episode being played.
    func stopIfPlaying(from podcast: Podcast) {
        guard let currentID,
              let episodes = podcast.episodes,
              episodes.contains(where: { $0.persistentModelID == currentID })
        else { return }
        stop()
    }

    func stop() {
        playback.stop()
        current = nil
        currentID = nil
        position = 0
        duration = nil
        phase = .idle
    }

    // MARK: - Engine events

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case let .phase(phase):
            self.phase = phase
            if case let .failed(error) = phase { self.error = error }
        case let .time(seconds):
            position = seconds
        case let .duration(seconds):
            // The asset's answer beats the feed's claim.
            duration = seconds
        case .reachedEnd:
            phase = .paused
            position = duration ?? position
        case .interrupted:
            phase = .paused
        case .routeLost:
            phase = .paused
        }
    }

    // MARK: - Translation

    private func snapshot(of episode: Episode) -> PlayableEpisode? {
        guard let url = URL(string: episode.audioURL), url.host() != nil else { return nil }
        return PlayableEpisode(
            id: "\(episode.podcast?.feedIdentity ?? "")|\(episode.guid)",
            audioURL: url,
            mimeType: episode.audioMIMEType,
            title: episode.title,
            showTitle: episode.podcast?.title ?? "",
            artworkURL: (episode.artworkURL ?? episode.podcast?.artworkURL)
                .flatMap(URL.init(string:)),
            feedDuration: episode.duration,
            startAt: 0
        )
    }
}
