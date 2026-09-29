import Foundation
import SwiftData

/// The store and the player, owned by the process rather than by a screen.
///
/// The player used to be `@State` inside `RootView`, which was fine while the
/// window was the only scene. CarPlay is a second scene with its own delegate,
/// instantiated by UIKit, which cannot be handed anything — and it has to drive
/// the *same* `AVPlayer`. Two players would mean two claims on one audio
/// session, and a car that does not know what the phone is playing.
///
/// So this is a singleton, and deliberately a thin one. Everything worth
/// testing — `PlayerModel`, the engine behind it, the queries — still takes its
/// dependencies by hand and is exercised that way; this only decides who holds
/// the one instance the app runs with.
@MainActor
final class PlaybackHost {
    static let shared = PlaybackHost()

    let container: ModelContainer
    let player: PlayerModel

    /// The player the app runs with, built apart from `shared` so a test can
    /// build the same one against an in-memory store.
    ///
    /// It shares the store's `mainContext` with the views: the episodes it is
    /// asked to play come from their queries, and it has to be able to resolve
    /// them.
    static func makePlayer(
        for container: ModelContainer,
        playback: any AudioPlayback = AVPlayerAudioEngine()
    ) -> PlayerModel {
        PlayerModel(playback: playback, context: container.mainContext)
    }

    private init() {
        let container = VoleCastModelContainer.makeStore()
        self.container = container
        self.player = Self.makePlayer(for: container)
        // The app is routinely killed while paused in the background, so the
        // bar has to be put back rather than assumed to survive. Done here
        // rather than when a view appears: whichever scene comes up first —
        // the window or the car — should find the player already loaded.
        player.restoreLastPlayed()
    }
}
