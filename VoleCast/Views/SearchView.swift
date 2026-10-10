import SwiftUI

/// Finding a show: by name, by pasting a feed URL, or by browsing a chart.
///
/// The two halves share this stack and its destinations but nothing else. The
/// search half talks only to the directory and the charts half only to the
/// charts, so an endpoint Apple might retire cannot take down the two ways of
/// finding a show that people actually depend on. Search is also what the tab
/// opens on, so a broken Discover is never the first thing anyone meets.
struct SearchView: View {
    @Binding var path: NavigationPath

    private enum Half: Hashable { case search, discover }

    @Environment(\.podcastDirectory) private var directory
    @Environment(\.podcastCharts) private var charts
    @State private var model: SearchModel?
    @State private var discover: DiscoverModel?
    @State private var half: Half = .search
    @State private var showingAddByURL = false
    /// Remembered across launches, because someone who browses another
    /// country's charts generally means it.
    @AppStorage("discoverStorefront") private var storefront = Storefront.device

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Find shows by", selection: $half) {
                    Text("Search").tag(Half.search)
                    Text("Discover").tag(Half.discover)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Pushed to fill what is left, so the picker above stays
                // pinned under the title. Without it the stack centres itself
                // and the control floats down the screen whenever the half
                // below it draws something small, like a spinner.
                Group {
                    switch half {
                    case .search:
                        searchHalf
                    case .discover:
                        discoverHalf
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Search")
            .toolbar {
                if half == .discover, let discover {
                    ToolbarItem(placement: .topBarLeading) {
                        chartPickers(discover)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add by RSS URL…", systemImage: "link.badge.plus") {
                        showingAddByURL = true
                    }
                }
            }
            .sheet(isPresented: $showingAddByURL) {
                AddFeedURLSheet { url in
                    path.append(ShowPreviewSource.feedURL(url))
                }
            }
            // Registered here too, because the player can open an episode
            // onto whichever tab happens to be in front.
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0, path: $path) }
            .navigationDestination(for: ShowDestination.self) {
                PodcastDetailView(show: $0, path: $path)
            }
            .navigationDestination(for: ShowPreviewSource.self) { source in
                ShowPreviewView(source: source)
            }
        }
        .onAppear {
            // Built here rather than in an initialiser so they pick up the
            // environment's services, which previews and tests replace. Owned
            // by this shell rather than by each half, so switching between
            // them does not throw away a chart already fetched.
            if model == nil { model = SearchModel(directory: directory) }
            if discover == nil {
                discover = DiscoverModel(charts: charts, storefront: storefront)
            }
        }
    }

    // MARK: - The two halves

    @ViewBuilder
    private var searchHalf: some View {
        if let model {
            content(model)
                .searchable(
                    text: Binding(get: { model.query }, set: { model.query = $0 }),
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Shows or RSS URL")
                )
                .task(id: model.query) { await model.search(model.query) }
        }
    }

    @ViewBuilder
    private var discoverHalf: some View {
        if let discover {
            DiscoverList(model: discover) {
                storefront = Storefront.device
                discover.storefront = Storefront.device
            }
        }
    }

    /// Both chart choices in one menu. A row of genre chips would cost
    /// permanent vertical space under an already-pinned segmented control, and
    /// put a sideways scroll directly above a list that scrolls the other way.
    private func chartPickers(_ discover: DiscoverModel) -> some View {
        Menu {
            Picker("Genre", selection: Binding(
                get: { discover.genre?.id ?? 0 },
                set: { id in discover.genre = PodcastGenre.all.first { $0.id == id } }
            )) {
                Text("Top Podcasts").tag(0)
                ForEach(PodcastGenre.all) { genre in
                    Text(genre.name).tag(genre.id)
                }
            }
            Picker("Country", selection: Binding(
                get: { storefront },
                set: { storefront = $0; discover.storefront = $0 }
            )) {
                ForEach(Self.countries, id: \.code) { country in
                    Text(country.name).tag(country.code)
                }
            }
        } label: {
            Label("Chart", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    /// Every region the device can name, rather than Apple's own list of
    /// stores. Apple has about 175 and publishes them nowhere stable, so a
    /// hardcoded table would be both long and quietly wrong over time; picking
    /// one Apple does not serve is recoverable in a way that a missing country
    /// is not.
    private static let countries: [(code: String, name: String)] = {
        Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty }
            .compactMap { region in
                guard let name = Locale.current.localizedString(forRegionCode: region.identifier)
                else { return nil }
                return (region.identifier.lowercased(), name)
            }
            .sorted { $0.name < $1.name }
    }()

    @ViewBuilder
    private func content(_ model: SearchModel) -> some View {
        // Anything that parses as a feed URL keeps its Open feed row, whatever
        // the directory is doing. A term can be both — "ev.news" is a show
        // name and a host — and for those the directory is still asked, but
        // its answer must not take the row away: "no matches" and a throttled
        // 403 are both reasons to want the URL more, not less.
        if model.typedFeedURL != nil {
            resultsList(model)
        } else {
            switch model.state {
            case .idle:
                ContentUnavailableView {
                    Label("Find a Show", systemImage: "magnifyingglass")
                } description: {
                    Text("Search by name, or paste an RSS feed URL.")
                }
            case .searching:
                ProgressView().controlSize(.large)
            case .failed(let error):
                ErrorView(error: error) { await model.search(model.query) }
            case .empty:
                ContentUnavailableView.search(text: model.query)
            case .results:
                resultsList(model)
            }
        }
    }

    private func resultsList(_ model: SearchModel) -> some View {
        List {
            // Apple's directory answers an unrecognised name with loosely
            // related shows rather than nothing, so a pasted URL needs a way
            // past it — hence this row, and the toolbar button.
            if let url = model.typedFeedURL {
                Section {
                    NavigationLink(value: ShowPreviewSource.feedURL(url)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Open feed")
                                Text(url.host() ?? url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "dot.radiowaves.up.forward")
                        }
                    }
                }
            }
            if case .results(let results) = model.state {
                Section {
                    ForEach(results) { result in
                        NavigationLink(value: ShowPreviewSource.directory(result)) {
                            ShowRow(
                                artworkURL: result.artworkURL?.absoluteString,
                                title: result.title,
                                author: result.author,
                                detail: result.episodeCount.map {
                                    String(localized: "^[\($0) episode](inflect: true)")
                                }
                            )
                        }
                    }
                } header: {
                    Text("Shows")
                }
            }
        }
        .listStyle(.plain)
    }
}

/// One way of showing a failed load, so every screen fails the same way.
struct ErrorView: View {
    let error: NetworkError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                error.errorDescription ?? "Something Went Wrong",
                systemImage: error.symbolName
            )
        } description: {
            Text(error.recoverySuggestion ?? "")
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
        }
    }
}

#Preview {
    SearchView(path: .constant(NavigationPath()))
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
