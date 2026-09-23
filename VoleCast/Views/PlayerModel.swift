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
    private let context: ModelContext

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
    /// The position last written to the store, so ticks can be thinned against
    /// it rather than writing on every one.
    private var lastWritten: TimeInterval = 0

    var isPlaying: Bool { phase == .playing }
    var isBuffering: Bool { phase.isBusy }

    /// How far through, 0...1, for the mini-bar's hairline.
    var fraction: Double {
        guard let duration, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    init(playback: any AudioPlayback, context: ModelContext) {
        self.playback = playback
        self.context = context
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
        // Whatever was playing keeps where it got to before being replaced.
        writePosition()
        error = nil
        currentID = episode.persistentModelID
        current = playable
        position = playable.startAt
        duration = playable.feedDuration
        lastWritten = playable.startAt
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
        writePosition(force: true)
    }

    func seek(to time: TimeInterval) {
        guard current != nil else { return }
        playback.seek(to: min(max(time, 0), duration ?? time))
        writePosition(force: true)
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
        writePosition(force: true)
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
            writePosition()
        case let .duration(seconds):
            // The asset's answer beats the feed's claim.
            duration = seconds
        case .reachedEnd:
            phase = .paused
            position = duration ?? position
            if let episode = liveEpisode() {
                PlaybackProgress.markPlayed(episode, in: context)
            }
            lastWritten = 0
        case .interrupted:
            phase = .paused
            writePosition(force: true)
            PlaybackProgress.flush(in: context)
        case .routeLost:
            phase = .paused
            writePosition(force: true)
        }
    }

    // MARK: - Persistence

    /// Called on every tick, but only writes when the position has actually
    /// moved far enough — or when the moment itself matters.
    private func writePosition(force: Bool = false) {
        guard current != nil else { return }
        guard force || PlaybackProgress.shouldWrite(position: position, lastWritten: lastWritten)
        else { return }
        guard let episode = liveEpisode() else { return }

        PlaybackProgress.record(position: position, for: episode, in: context)
        lastWritten = position
    }

    /// Writes whatever is pending and saves. For the scene leaving `.active`,
    /// where autosave can no longer be relied on.
    func flush() {
        writePosition(force: true)
        PlaybackProgress.flush(in: context)
    }

    /// Re-resolves the stored episode only when something must be written.
    /// Returns nil once it has been deleted, so nothing reads a dead model.
    private func liveEpisode() -> Episode? {
        guard let currentID else { return nil }
        guard let episode = context.registeredModel(for: currentID) as Episode?,
              !episode.isDeleted
        else { return nil }
        return episode
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
            startAt: PlaybackProgress.resumePosition(
                stored: episode.playbackPosition,
                duration: episode.duration,
                isPlayed: episode.isPlayed
            )
        )
    }
}
