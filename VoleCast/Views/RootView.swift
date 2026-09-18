import SwiftUI

/// Three top-level tabs: what's new, the shows you follow, and finding more.
///
/// Each tab owns its navigation path so switching tabs doesn't unwind where you
/// were. When playback arrives, the mini-player becomes a bottom overlay here
/// and this structure stays as it is.
struct RootView: View {
    enum TabSelection {
        case latest, subscriptions, search
    }

    @State private var selection: TabSelection = .latest
    @State private var latestPath = NavigationPath()
    @State private var subscriptionsPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    var body: some View {
        TabView(selection: $selection) {
            LatestEpisodesView(path: $latestPath, onFindShows: showSearch)
                .tabItem { Label("Latest", systemImage: "waveform") }
                .tag(TabSelection.latest)
            SubscriptionsView(path: $subscriptionsPath, onFindShows: showSearch)
                .tabItem { Label("Subscriptions", systemImage: "square.stack.fill") }
                .tag(TabSelection.subscriptions)
            SearchView(path: $searchPath)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TabSelection.search)
        }
    }

    private func showSearch() {
        selection = .search
    }
}

#Preview {
    RootView()
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
