import SwiftUI

/// Four top-level tabs: what's new, the shows you follow, what you have been
/// listening to, and finding more.
///
/// Each tab owns its navigation path so switching tabs doesn't unwind where you
/// were. The mini-player is the tab view's bottom accessory, which is why it
/// survives navigating and changing tabs.
struct RootView: View {
    enum TabSelection {
        case latest, subscriptions, history, search
    }

    @Environment(\.makeAudioPlayback) private var makeAudioPlayback
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: TabSelection = .latest
    @State private var latestPath = NavigationPath()
    @State private var subscriptionsPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    /// Built in `onAppear` rather than an initialiser so it picks up the
    /// environment's engine, which previews and tests replace. One per app:
    /// every screen shares this instance.
    @State private var player: PlayerModel?

    var body: some View {
        TabView(selection: $selection) {
            LatestEpisodesView(path: $latestPath, onFindShows: showSearch)
                .modifier(PlayerEnvironment(player: player))
                .tabItem { Label("Latest", systemImage: "waveform") }
                .tag(TabSelection.latest)
            SubscriptionsView(path: $subscriptionsPath, onFindShows: showSearch)
                .modifier(PlayerEnvironment(player: player))
                .tabItem { Label("Subscriptions", systemImage: "square.stack.fill") }
                .tag(TabSelection.subscriptions)
            HistoryView(path: $historyPath)
                .modifier(PlayerEnvironment(player: player))
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(TabSelection.history)
            SearchView(path: $searchPath)
                .modifier(PlayerEnvironment(player: player))
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TabSelection.search)
        }
        // The system owns this one: it places the bar above the tab bar, gives
        // it the tab bar's own material, and — the point of the change —
        // insets the scrollable content behind it, including inside pushed
        // views. Doing it by hand with `safeAreaInset` on each tab's root put
        // the inset outside the `NavigationStack`, where lists never saw it and
        // the bar simply covered the last rows.
        // `isEnabled` matters: the space is reserved whenever the accessory
        // exists, even if it renders nothing, which left a 56pt gap above the
        // tab bar with nothing playing.
        .tabViewBottomAccessory(isEnabled: player?.current != nil) {
            if let player {
                MiniPlayerBar()
                    .environment(player)
            }
        }
        .onAppear {
            if player == nil {
                let model = PlayerModel(playback: makeAudioPlayback(), context: modelContext)
                // The app is routinely killed while paused in the background,
                // so the bar has to be put back rather than assumed to survive.
                model.restoreLastPlayed()
                player = model
            }
        }
        // Autosave cannot be relied on once the app is suspended while still
        // playing: it can be killed without another pass of the main runloop,
        // taking the last few seconds of position with it.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.flush() }
        }
        // Presented once, from here, so it covers the tab bar and survives a
        // tab change underneath it.
        .sheet(
            isPresented: Binding(
                get: { player?.isExpanded ?? false },
                set: { player?.isExpanded = $0 }
            )
        ) {
            if let player {
                FullPlayerView()
                    .environment(player)
            }
        }
    }

    private func showSearch() {
        selection = .search
    }
}

/// Hands each tab the player.
///
/// Every episode row reads `PlayerModel` from the environment, so a tab without
/// it traps as soon as a row appears. Applied per tab rather than to the
/// `TabView`, which does not pass its environment down to tab content.
private struct PlayerEnvironment: ViewModifier {
    let player: PlayerModel?

    func body(content: Content) -> some View {
        if let player {
            content.environment(player)
        } else {
            content
        }
    }
}

#Preview {
    RootView()
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
