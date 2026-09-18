import SwiftUI

/// Two top-level tabs: the shows you subscribe to, and finding new ones.
///
/// Each tab owns its navigation path so switching tabs doesn't unwind where you
/// were. When playback arrives, the mini-player becomes a bottom overlay here
/// and this structure stays as it is.
struct RootView: View {
    enum TabSelection {
        case library, search
    }

    @State private var selection: TabSelection = .library
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    var body: some View {
        TabView(selection: $selection) {
            LibraryView(path: $libraryPath, onFindShows: { selection = .search })
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
                .tag(TabSelection.library)
            SearchView(path: $searchPath)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TabSelection.search)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
