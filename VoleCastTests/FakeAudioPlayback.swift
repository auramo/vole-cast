import Foundation
@testable import VoleCast

/// A stand-in engine that records what it was asked to do and lets a test push
/// events back synchronously.
///
/// A class rather than a struct, unlike `FakeHTTPClient` and the stub
/// directories: the seam is a callback, so the fake has to be referenced by the
/// thing it reports to. It never leaves the main actor, so it needs no `Mutex`.
@MainActor
final class FakeAudioPlayback: AudioPlayback {

    enum Command: Equatable {
        case load(PlayableEpisode)
        case present(PlayableEpisode, TimeInterval)
        case play
        case pause
        case seek(TimeInterval)
        case skip(TimeInterval)
        case stop
    }

    var onEvent: ((PlaybackEvent) -> Void)?
    private(set) var commands: [Command] = []

    var position: TimeInterval = 0
    var duration: TimeInterval?

    /// The episode most recently handed to `load`.
    var loaded: PlayableEpisode? {
        commands.reversed().compactMap { if case let .load(episode) = $0 { episode } else { nil } }.first
    }

    /// The episode most recently announced through `present`, and where it was
    /// said to be. Metadata only — nothing here was given to an engine.
    var presented: PlayableEpisode? {
        commands.reversed().compactMap { if case let .present(episode, _) = $0 { episode } else { nil } }.first
    }

    var presentedAt: TimeInterval? {
        commands.reversed().compactMap { if case let .present(_, at) = $0 { at } else { nil } }.first
    }

    func load(_ episode: PlayableEpisode) {
        commands.append(.load(episode))
        position = episode.startAt
        duration = episode.feedDuration
    }

    /// Deliberately leaves `position` and `duration` alone: announcing an
    /// episode is not preparing it, and the fake must not look more loaded
    /// than the real engine would be.
    func present(_ episode: PlayableEpisode, at position: TimeInterval) {
        commands.append(.present(episode, position))
    }

    func play() { commands.append(.play) }
    func pause() { commands.append(.pause) }

    func seek(to time: TimeInterval) {
        commands.append(.seek(time))
        position = time
    }

    func skip(by delta: TimeInterval) {
        commands.append(.skip(delta))
        position += delta
    }

    func stop() {
        commands.append(.stop)
        position = 0
        duration = nil
    }

    /// Drives the model the way the real engine would, with no waiting.
    func emit(_ event: PlaybackEvent) {
        if case let .time(seconds) = event { position = seconds }
        if case let .duration(seconds) = event { duration = seconds }
        onEvent?(event)
    }

    func forget() { commands.removeAll() }
}
