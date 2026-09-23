import Foundation
import MediaPlayer
import OSLog
import UIKit

/// The lock screen, Control Centre, CarPlay and the AirPods stem: everything
/// that drives playback from outside the app, and everything that displays it.
///
/// Owned by the engine rather than the view layer, because the engine is the
/// one thing that knows position, rate, duration *and* the episode's metadata.
/// Routing the remote commands through the same methods the UI calls also means
/// a squeeze on a headphone stem emits the same events as an on-screen tap, so
/// position gets persisted with no extra code.
@MainActor
final class NowPlayingCentre {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "now-playing"
    )

    nonisolated static let skipForward: TimeInterval = 30
    nonisolated static let skipBackward: TimeInterval = 15

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSkip: ((TimeInterval) -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    /// Which episode the current info dictionary describes, so a slow artwork
    /// fetch can't overwrite metadata that has since moved on.
    private var describing: String?
    /// What we last told the system. `MPNowPlayingInfoCenter.playbackState` is
    /// ignored on iOS without a MediaRemote entitlement, so it cannot be read
    /// back as the source of truth.
    private var isPlaying = false
    private var artworkTask: Task<Void, Never>?

    init() {
        wireCommands()
    }

    // MARK: - Commands

    /// Every handler is `@Sendable` and hops to the main actor itself.
    /// MediaRemote does not promise to call these on the main thread, and a
    /// closure that inherited this type's isolation would abort the process
    /// the first time it didn't.
    private nonisolated func wireCommands() {
        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }
        centre.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Our own record, not `MPNowPlayingInfoCenter.playbackState`:
                // iOS ignores writes to that without a MediaRemote entitlement,
                // so reading it back is not a reliable answer.
                if self.isPlaying { self.onPause?() } else { self.onPlay?() }
            }
            return .success
        }

        centre.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward)]
        centre.skipForwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onSkip?(Self.skipForward) }
            return .success
        }

        centre.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackward)]
        centre.skipBackwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onSkip?(-Self.skipBackward) }
            return .success
        }

        // What makes the lock screen's scrubber draggable rather than inert.
        centre.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = event.positionTime
            Task { @MainActor in self?.onSeek?(target) }
            return .success
        }

        // There is no queue. Left enabled, Control Centre shows track-skip
        // arrows that do nothing when pressed.
        centre.nextTrackCommand.isEnabled = false
        centre.previousTrackCommand.isEnabled = false
    }

    // MARK: - Metadata

    /// Full metadata for a newly loaded episode. Call this *before* activating
    /// the session and starting playback, or the lock screen comes up blank for
    /// the first few seconds.
    func describe(
        _ episode: PlayableEpisode,
        position: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool
    ) {
        describing = episode.id
        artworkTask?.cancel()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.showTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        self.isPlaying = isPlaying

        if let artworkURL = episode.artworkURL {
            loadArtwork(from: artworkURL, for: episode.id)
        }
    }

    /// Position and rate only.
    ///
    /// Deliberately *not* called on every tick: the lock screen extrapolates
    /// elapsed time from the playback rate, so refreshing it once a second
    /// makes its scrubber stutter and jump. Only moments that actually break
    /// the extrapolation — play, pause, seek, a rate change — need this.
    func updatePlayback(position: TimeInterval, duration: TimeInterval?, isPlaying: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        self.isPlaying = isPlaying
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        describing = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isPlaying = false
    }

    // MARK: - Artwork

    /// Wraps an image for the lock screen.
    ///
    /// `nonisolated` is load-bearing, not tidiness. MediaRemote calls the
    /// request handler on its own queue whenever it wants the image at some
    /// size, so a handler that inherited this type's main-actor isolation —
    /// which it does by default — aborts the process with "BUG IN CLIENT OF
    /// LIBDISPATCH: Block was expected to execute on queue" the moment the
    /// lock screen draws.
    nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// `URLSession.shared`, not `AppURLSession`: that one sends an RSS `Accept`
    /// header and a feed-sized cache, neither of which suits an image.
    private func loadArtwork(from url: URL, for episodeID: String) {
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled
            else { return }

            guard let self, describing == episodeID else { return }

            let artwork = Self.artwork(for: image)
            // Merge rather than replace: a newer episode may have landed while
            // this was in flight, and its title must survive.
            guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    func tearDown() {
        artworkTask?.cancel()
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.removeTarget(nil)
        centre.pauseCommand.removeTarget(nil)
        centre.togglePlayPauseCommand.removeTarget(nil)
        centre.skipForwardCommand.removeTarget(nil)
        centre.skipBackwardCommand.removeTarget(nil)
        centre.changePlaybackPositionCommand.removeTarget(nil)
        clear()
    }
}
