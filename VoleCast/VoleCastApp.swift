import SwiftUI

@main
struct VoleCastApp: App {
    let container = VoleCastModelContainer.makeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
