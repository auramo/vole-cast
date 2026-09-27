import SwiftUI

@main
struct VoleCastApp: App {
    /// The store and the player both come from here, so that a second scene —
    /// the car — can be handed the same ones.
    private let host = PlaybackHost.shared

    var body: some Scene {
        WindowGroup {
            RootView(player: host.player)
        }
        .modelContainer(host.container)
    }
}
