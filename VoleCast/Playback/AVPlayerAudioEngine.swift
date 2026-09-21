import AVFoundation
import OSLog

/// Plays episodes by streaming them, with one long-lived `AVPlayer` reused for
/// every episode.
///
/// Reuse is deliberate: building a fresh `AVPlayer` per episode tears the
/// output route down and back up, which is audible and churns the audio
/// session. `replaceCurrentItem(with:)` does not.
///
/// Nothing is written to disk. `AVURLAsset` uses CoreMedia's own HTTP stack,
/// which neither consults nor populates `AppURLSession`'s `URLCache`, and the
/// only API that stores audio durably — `AVAssetDownloadURLSession` — is not
/// used here.
@MainActor
final class AVPlayerAudioEngine: AudioPlayback {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "playback"
    )

    /// Read-ahead once audio is flowing. Asking for this up front would instead
    /// slow down time-to-first-sound, which is the delay people actually
    /// notice, so it is applied only after playback starts.
    private static let forwardBuffer: TimeInterval = 60

    var onEvent: ((PlaybackEvent) -> Void)?

    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval?

    private var player: AVPlayer?
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingCentre()
    private var loaded: PlayableEpisode?

    private var timeObserver: Any?
    /// Kept apart because they have different lifetimes: the player outlives
    /// every item, so swapping an item must not invalidate its observations.
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var itemTasks: [Task<Void, Never>] = []

    /// Whether we were playing when the system interrupted us.
    private var wasPlayingBeforeInterruption = false
    /// A drag can outrun the seeks it asks for, so only the newest survives.
    private var seekInFlight = false
    private var pendingSeek: TimeInterval?
    private var raisedBuffer = false

    init() {
        session.onInterruption = { [weak self] began, resumable in
            self?.handleInterruption(began: began, resumable: resumable)
        }
        session.onRouteLost = { [weak self] in
            guard let self else { return }
            pause()
            onEvent?(.routeLost)
        }
        session.onMediaServicesReset = { [weak self] in
            self?.rebuildAfterReset()
        }

        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onSkip = { [weak self] delta in self?.skip(by: delta) }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    // MARK: - AudioPlayback

    func load(_ episode: PlayableEpisode) {
        // Tapping the same episode twice must not restart it.
        guard loaded?.id != episode.id else {
            play()
            return
        }

        loaded = episode
        position = episode.startAt
        duration = episode.feedDuration
        onEvent?(.phase(.loading))

        var options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsCellularAccessKey: true,
            // Low Data Mode. Leaving this false makes playback mysteriously
            // refuse for anyone who has it switched on.
            AVURLAssetAllowsConstrainedNetworkAccessKey: true,
        ]
        if let mimeType = episode.mimeType, !mimeType.isEmpty {
            options["AVURLAssetOutOfBandMIMETypeKey"] = mimeType
        }

        let asset = AVURLAsset(url: episode.audioURL, options: options)
        let item = AVPlayerItem(asset: asset)
        // Automatic to begin with; raised once audio is actually flowing.
        item.preferredForwardBufferDuration = 0

        let player = existingPlayer()
        player.replaceCurrentItem(with: item)
        observe(item)
        raisedBuffer = false

        // Before `play()`, which activates the session: populating afterwards
        // leaves the lock screen blank for the first few seconds.
        nowPlaying.describe(episode, position: position, duration: duration, isPlaying: false)

        if episode.startAt > 0 {
            seek(to: episode.startAt)
        }
        play()
    }

    func play() {
        guard let player, player.currentItem != nil else { return }
        session.activate()
        player.play()
    }

    func pause() {
        player?.pause()
        nowPlaying.updatePlayback(position: position, duration: duration, isPlaying: false)
        onEvent?(.phase(.paused))
    }

    func seek(to time: TimeInterval) {
        guard let player, player.currentItem != nil else { return }
        let clamped = max(0, min(time, duration ?? time))

        guard !seekInFlight else {
            pendingSeek = clamped
            return
        }
        seekInFlight = true

        // Never zero tolerance: a sample-accurate seek into a VBR MP3 with no
        // index forces a byte-range hunt and can re-fetch large spans.
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        position = clamped
        onEvent?(.time(clamped))
        nowPlaying.updatePlayback(
            position: clamped,
            duration: duration,
            isPlaying: player.timeControlStatus == .playing
        )

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seekInFlight = false
                if let next = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(to: next)
                }
            }
        }
    }

    func skip(by delta: TimeInterval) {
        seek(to: position + delta)
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        clearItemObservations()
        loaded = nil
        position = 0
        duration = nil
        nowPlaying.clear()
        session.deactivate()
        onEvent?(.phase(.idle))
    }

    /// Must be called before the engine is released: a periodic time observer
    /// that outlives its player is a hard crash, and a `@MainActor deinit`
    /// cannot touch isolated state under Swift 6.
    func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        clearItemObservations()
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        player?.replaceCurrentItem(with: nil)
        player = nil
        nowPlaying.tearDown()
        session.tearDown()
    }

    // MARK: - Player

    private func existingPlayer() -> AVPlayer {
        if let player { return player }

        let player = AVPlayer()
        // Let AVFoundation decide when it has enough buffered to start.
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        self.player = player

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time.seconds)
            }
        }

        playerObservations.append(
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.emitPhase() }
            }
        )
        return player
    }

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0 else { return }
        position = seconds
        onEvent?(.time(seconds))
    }

    private func emitPhase() {
        guard let player else { return }
        switch player.timeControlStatus {
        case .playing:
            raiseBufferOnce()
            nowPlaying.updatePlayback(position: position, duration: duration, isPlaying: true)
            onEvent?(.phase(.playing))
        case .paused:
            nowPlaying.updatePlayback(position: position, duration: duration, isPlaying: false)
            onEvent?(.phase(loaded == nil ? .idle : .paused))
        case .waitingToPlayAtSpecifiedRate:
            onEvent?(.phase(player.reasonForWaitingToPlay == .noItemToPlay ? .idle : .buffering))
        @unknown default:
            break
        }
    }

    /// Raised only once audio is flowing, so it buys stall resistance without
    /// paying for it in startup latency.
    private func raiseBufferOnce() {
        guard !raisedBuffer, let item = player?.currentItem else { return }
        item.preferredForwardBufferDuration = Self.forwardBuffer
        raisedBuffer = true
    }

    // MARK: - Item observation

    private func observe(_ item: AVPlayerItem) {
        clearItemObservations()

        itemObservations.append(
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay: self.resolveDuration(of: item)
                    case .failed: self.emitFailure(item.error)
                    default: break
                    }
                }
            }
        )

        itemTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification, object: item
            ) {
                guard let self else { return }
                self.onEvent?(.reachedEnd)
            }
        })

        itemTasks.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(
                named: AVPlayerItem.failedToPlayToEndTimeNotification, object: item
            ) {
                guard let self else { return }
                self.emitFailure(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            }
        })
    }

    private func resolveDuration(of item: AVPlayerItem) {
        let resolved = item.duration
        guard resolved.isNumeric, !resolved.isIndefinite else { return }
        let seconds = resolved.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
        onEvent?(.duration(seconds))
        nowPlaying.updatePlayback(
            position: position,
            duration: seconds,
            isPlaying: player?.timeControlStatus == .playing
        )
    }

    private func emitFailure(_ error: Error?) {
        let mapped: PlaybackError
        switch error {
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            mapped = .offline
        case let error?:
            mapped = .failed(error.localizedDescription)
        case nil:
            mapped = .unplayable
        }
        Self.logger.error("Playback failed: \(String(describing: error))")
        onEvent?(.phase(.failed(mapped)))
    }

    private func clearItemObservations() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        itemTasks.forEach { $0.cancel() }
        itemTasks.removeAll()
    }

    // MARK: - Interruptions

    private func handleInterruption(began: Bool, resumable: Bool) {
        if began {
            wasPlayingBeforeInterruption = player?.timeControlStatus == .playing
            player?.pause()
            onEvent?(.interrupted(resumable: wasPlayingBeforeInterruption))
            onEvent?(.phase(.paused))
        } else if resumable, wasPlayingBeforeInterruption {
            session.activate()
            play()
        }
    }

    private func rebuildAfterReset() {
        guard let episode = loaded else { return }
        let resumeAt = position
        clearItemObservations()
        player = nil
        loaded = nil
        var restarted = episode
        restarted = PlayableEpisode(
            id: episode.id,
            audioURL: episode.audioURL,
            mimeType: episode.mimeType,
            title: episode.title,
            showTitle: episode.showTitle,
            artworkURL: episode.artworkURL,
            feedDuration: episode.feedDuration,
            startAt: resumeAt
        )
        load(restarted)
    }
}
