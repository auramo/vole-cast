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

    @Environment(\.makeAudioPlayback) private var makeAudioPlayback

    @State private var selection: TabSelection = .latest
    @State private var latestPath = NavigationPath()
    @State private var subscriptionsPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    /// Built in `onAppear` rather than an initialiser so it picks up the
    /// environment's engine, which previews and tests replace. One per app:
    /// every screen shares this instance.
    @State private var player: PlayerModel?

    var body: some View {
        TabView(selection: $selection) {
            LatestEpisodesView(path: $latestPath, onFindShows: showSearch)
                .modifier(MiniPlayerInset(player: player))
                .tabItem { Label("Latest", systemImage: "waveform") }
                .tag(TabSelection.latest)
            SubscriptionsView(path: $subscriptionsPath, onFindShows: showSearch)
                .modifier(MiniPlayerInset(player: player))
                .tabItem { Label("Subscriptions", systemImage: "square.stack.fill") }
                .tag(TabSelection.subscriptions)
            SearchView(path: $searchPath)
                .modifier(MiniPlayerInset(player: player))
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TabSelection.search)
        }
        .onAppear {
            if player == nil { player = PlayerModel(playback: makeAudioPlayback()) }
        }
    }

    private func showSearch() {
        selection = .search
    }
}

/// Puts the mini-player above the tab bar.
///
/// Applied to each tab's content rather than to the `TabView`, because an inset
/// on the `TabView` is laid out outside it and lands *below* the tab bar. Here
/// it also shrinks the tab's safe area, so the last row of a list scrolls clear
/// of the bar rather than hiding under it — which an overlay would not do
/// without hand-tuned padding. iOS 26's `.tabViewBottomAccessory` does this in
/// one line; the deployment target is 18.0.
private struct MiniPlayerInset: ViewModifier {
    let player: PlayerModel?

    func body(content: Content) -> some View {
        if let player {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MiniPlayerBar()
                        .environment(player)
                }
                .environment(player)
        } else {
            content
        }
    }
}

#Preview {
    RootView()
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
