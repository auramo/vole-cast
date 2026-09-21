import Foundation

/// What the player needs to know about an episode, and nothing more.
///
/// A snapshot rather than the `Episode` itself, so `Playback/` stays free of
/// SwiftData and can be exercised without a store. It also survives the model
/// being deleted underneath it — unsubscribing cascades away a show's episodes,
/// and reading a deleted `@Model` traps.
struct PlayableEpisode: Equatable, Sendable, Identifiable {
    /// A show's `feedIdentity` and the episode's `guid`, joined. `guid` alone
    /// is only unique within one show, so two shows sharing one would make the
    /// wrong row look like it's playing. `Views/` matches on the store's own
    /// `PersistentIdentifier`; this is for the engine's own bookkeeping, and
    /// keeps SwiftData out of this layer.
    let id: String
    let audioURL: URL
    /// From the enclosure. Passed to AVFoundation out-of-band, because some
    /// hosts answer with a missing or wrong `Content-Type`.
    let mimeType: String?
    let title: String
    let showTitle: String
    let artworkURL: URL?
    /// What the feed claimed. The asset's own duration wins once it resolves.
    let feedDuration: TimeInterval?
    let startAt: TimeInterval
}

enum PlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case failed(PlaybackError)

    var isPlaying: Bool { self == .playing }
    var isBusy: Bool { self == .loading || self == .buffering }
}

enum PlaybackError: Error, Equatable, Sendable {
    case unplayable
    case offline
    case failed(String)
}

/// What the engine tells the world. Delivered on the main actor.
enum PlaybackEvent: Equatable, Sendable {
    case phase(PlaybackPhase)
    /// Roughly once a second while playing.
    case time(TimeInterval)
    /// Resolved from the asset; may contradict what the feed claimed.
    case duration(TimeInterval)
    case reachedEnd
    /// A phone call or similar. `resumable` is the system's opinion, not ours.
    case interrupted(resumable: Bool)
    /// Headphones or AirPods pulled out.
    case routeLost
}

/// The seam between the app and AVFoundation.
///
/// `@MainActor` because `AVPlayer` is not `Sendable` and every caller is on the
/// main actor anyway. Events arrive through a closure rather than an
/// `AsyncStream` so a fake can drive a model synchronously in tests — no
/// `Task`, no waiting on a clock.
@MainActor
protocol AudioPlayback: AnyObject, Sendable {
    /// Set by the owner. The engine holds this strongly, so assign `[weak self]`.
    var onEvent: ((PlaybackEvent) -> Void)? { get set }

    var position: TimeInterval { get }
    var duration: TimeInterval? { get }

    /// Loads and begins playing. Idempotent for the episode already loaded.
    func load(_ episode: PlayableEpisode)
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func skip(by delta: TimeInterval)
    /// Unloads and releases the audio session back to whatever else wants it.
    func stop()
}
