import SwiftData
import SwiftUI

/// Four top-level tabs: what's new, what you have been listening to, the shows
/// you follow, and finding more.
///
/// Each tab owns its navigation path so switching tabs doesn't unwind where you
/// were. The mini-player is the tab view's bottom accessory, which is why it
/// survives navigating and changing tabs.
struct RootView: View {
    enum TabSelection {
        case latest, history, subscriptions, search
    }

    /// Handed in rather than built here. It outlives this screen — the car is
    /// a second scene driving the same player — so the process owns it.
    let player: PlayerModel

    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: TabSelection = .latest
    @State private var latestPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var subscriptionsPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    var body: some View {
        TabView(selection: $selection) {
            LatestEpisodesView(path: $latestPath, onFindShows: showSearch)
                .environment(player)
                .tabItem { Label("Latest", systemImage: "waveform") }
                .tag(TabSelection.latest)
            HistoryView(path: $historyPath)
                .environment(player)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(TabSelection.history)
            SubscriptionsView(path: $subscriptionsPath, onFindShows: showSearch)
                .environment(player)
                .tabItem { Label("Subscriptions", systemImage: "square.stack.fill") }
                .tag(TabSelection.subscriptions)
            SearchView(path: $searchPath)
                .environment(player)
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
        .tabViewBottomAccessory(isEnabled: player.current != nil) {
            MiniPlayerBar()
                .environment(player)
        }
        // Autosave cannot be relied on once the app is suspended while still
        // playing: it can be killed without another pass of the main runloop,
        // taking the last few seconds of position with it.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.flush() }
        }
        // Presented once, from here, so it covers the tab bar and survives a
        // tab change underneath it.
        .sheet(
            isPresented: Binding(
                get: { player.isExpanded },
                set: { player.isExpanded = $0 }
            )
        ) {
            FullPlayerView(onOpenEpisode: openFromPlayer)
                .environment(player)
        }
    }

    private func showSearch() {
        selection = .search
    }

    /// Opens the playing episode's own screen, and closes the player to do it.
    ///
    /// Pushed onto whichever tab is in front rather than shown inside the
    /// player's sheet: from the episode you can go on to its place in the
    /// show, and a show's episode list stacked inside a modal is a dead end.
    /// The player is a tap away on the bar the whole time.
    private func openFromPlayer(_ episode: Episode) {
        player.isExpanded = false
        activePath.wrappedValue.append(episode)
    }

    private var activePath: Binding<NavigationPath> {
        switch selection {
        case .latest: $latestPath
        case .history: $historyPath
        case .subscriptions: $subscriptionsPath
        case .search: $searchPath
        }
    }
}

#Preview {
    let container = VoleCastModelContainer.makeInMemory()
    RootView(
        player: PlayerModel(playback: AVPlayerAudioEngine(), context: ModelContext(container))
    )
    .modelContainer(container)
}
