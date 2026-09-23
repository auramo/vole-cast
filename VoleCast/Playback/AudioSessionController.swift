import AVFoundation
import OSLog

/// Owns the app's `AVAudioSession`: what kind of audio we are, when to claim
/// the output, and what to do when something takes it away.
///
/// Split out from the engine so the "what should happen on an interruption"
/// rules stay one readable unit.
@MainActor
final class AudioSessionController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoleCast",
        category: "audio-session"
    )

    /// Raised when the system takes the output away. `resumable` is the
    /// system's opinion about whether we may start again afterwards.
    var onInterruption: ((_ began: Bool, _ resumable: Bool) -> Void)?
    /// Raised when the route disappeared under us — headphones unplugged.
    var onRouteLost: (() -> Void)?
    /// Raised when the media daemon restarted and everything must be rebuilt.
    var onMediaServicesReset: (() -> Void)?

    private var isActive = false
    private var observers: [Task<Void, Never>] = []

    init() {
        configure()
        observe()
    }

    /// `.spokenAudio` gets the right ducking against navigation prompts, and
    /// `.longFormAudio` is what makes AirPlay 2 route selection behave for
    /// podcasts. Set once; only activation is deferred.
    private func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .longFormAudio
            )
        } catch {
            Self.logger.error("Could not set the audio category: \(error.localizedDescription)")
        }
    }

    /// Claims the output. Deferred to the first `play()` rather than done at
    /// launch, because activating interrupts whatever else is playing.
    func activate() {
        guard !isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
        } catch {
            // Another app may hold the session; staying paused is correct.
            Self.logger.error("Could not activate the audio session: \(error.localizedDescription)")
        }
    }

    /// Only on stop, never on pause — the lock-screen controls disappear if the
    /// session goes inactive while an episode is still loaded.
    func deactivate() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        } catch {
            Self.logger.error("Could not deactivate the audio session: \(error.localizedDescription)")
        }
    }

    /// Re-asserts the category after the media daemon restarts.
    func reconfigureAfterReset() {
        isActive = false
        configure()
    }

    private func observe() {
        let center = NotificationCenter.default

        observers.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.interruptionNotification) {
                guard let self else { return }
                handleInterruption(note)
            }
        })

        observers.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self else { return }
                handleRouteChange(note)
            }
        })

        observers.append(Task { [weak self] in
            for await _ in center.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                guard let self else { return }
                Self.logger.notice("Media services were reset; rebuilding.")
                reconfigureAfterReset()
                onMediaServicesReset?()
            }
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // AVPlayer has already stopped. Don't fight it.
            isActive = false
            onInterruption?(true, false)
        case .ended:
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            onInterruption?(false, shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        // The headphones-yanked case. Not handling it is the single most
        // embarrassing bug a podcast app can ship.
        if reason == .oldDeviceUnavailable {
            onRouteLost?()
        }
    }

    func tearDown() {
        observers.forEach { $0.cancel() }
        observers.removeAll()
        deactivate()
    }
}
