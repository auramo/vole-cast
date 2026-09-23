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
    /// Set when an episode plays out. The player still sits at the duration
    /// afterwards, so without this a later forced write — a backgrounding, a
    /// stop — would put that duration back on an episode whose position
    /// `markPlayed` had just zeroed, leaving it finished *and* part-played.
    private var reachedEnd = false
    /// Whether this load has already been recorded as started. `.playing` is
    /// re-emitted on every resume, and stamping again would shuffle the
    /// listening history every time someone paused.
    private var stampedStart = false
    /// True for an episode restored into the bar at launch: it is on screen,
    /// but the engine has never been given it. Playing has to hand it over
    /// rather than just asking for a rate change.
    private var needsLoad = false

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

    // MARK: - Restoring

    /// Puts the most recently played episode back in the player, paused.
    ///
    /// `PlayerModel` lives only as long as the process, and a paused app in the
    /// background gets suspended and then terminated — a couple of hours is
    /// plenty. Without this the mini-player simply vanishes overnight, taking
    /// the one obvious route back to a half-finished episode with it.
    ///
    /// Nothing is handed to the engine here: the app has just launched, quite
    /// possibly in someone's pocket, and restoring must not make a sound.
    func restoreLastPlayed() {
        guard current == nil else { return }
        guard let episode = try? context.fetch(ListeningHistory.descriptor(limit: 1)).first,
              let playable = snapshot(of: episode)
        else { return }

        currentID = episode.persistentModelID
        current = playable
        position = playable.startAt
        duration = playable.feedDuration
        lastWritten = playable.startAt
        phase = .paused
        needsLoad = true
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
        if isPlaying { playback.pause() } else { resume() }
    }

    func play(_ episode: Episode) {
        guard let playable = snapshot(of: episode) else { return }
        // Forced: whatever was playing keeps exactly where it got to, even if
        // that is less than `writeInterval` in. Switching away after a few
        // seconds used to discard those seconds entirely.
        writePosition(force: true)
        error = nil
        currentID = episode.persistentModelID
        current = playable
        position = playable.startAt
        duration = playable.feedDuration
        lastWritten = playable.startAt
        stampedStart = false
        reachedEnd = false
        needsLoad = false
        playback.load(playable)
    }

    /// Acts on whatever is loaded. The bar has only the snapshot, not an
    /// `Episode`, so its controls come through here.
    func resume() {
        guard let current else { return }
        guard !needsLoad else {
            // Restored but never loaded. Start it where the bar says it is,
            // which a scrub may have moved since launch.
            needsLoad = false
            playback.load(current.starting(at: position))
            return
        }
        playback.play()
    }

    func pause() {
        guard current != nil else { return }
        playback.pause()
        writePosition(force: true)
    }

    func seek(to time: TimeInterval) {
        guard current != nil else { return }
        let target = min(max(time, 0), duration ?? time)
        // Scrubbing away from the end is a deliberate "play me that again", so
        // recording resumes. Position is set here rather than waiting for the
        // engine's tick, so the write below records where we are going.
        reachedEnd = false
        position = target
        // Nothing to seek in the engine yet; `resume` will start here instead.
        if !needsLoad { playback.seek(to: target) }
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
            // `.playing` means audio is genuinely flowing, so an episode whose
            // enclosure is dead never enters the history.
            if phase == .playing { stampStart() }
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
            reachedEnd = true
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
        // Nothing left to record: the episode finished, and `markPlayed` has
        // already put both fields where they belong.
        guard !reachedEnd else { return }
        guard force || PlaybackProgress.shouldWrite(position: position, lastWritten: lastWritten)
        else { return }
        guard let episode = liveEpisode() else { return }

        PlaybackProgress.record(position: position, for: episode, in: context)
        lastWritten = position
    }

    /// Records this episode as listened to, once per load.
    private func stampStart() {
        guard !stampedStart, let episode = liveEpisode() else { return }
        PlaybackProgress.markStarted(episode, in: context)
        stampedStart = true
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
