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
    @FocusState private var typing: Bool
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
                // Large, and with no navigation title above it. These two are
                // the top level of this tab — a title saying "Search" over a
                // control whose left half also says Search was the same word
                // twice, once as a heading for something only half of which it
                // described.
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 4)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The chevron above the keyboard, which is what iOS uses
                // everywhere else for "put this away". Return does the same,
                // but only while you are still on the key — this stays reachable
                // once a thumb has moved on to the results.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") {
                        typing = false
                    }
                    .labelStyle(.iconOnly)
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
            VStack(spacing: 0) {
                field(model)
                content(model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task(id: model.query) { await model.search(model.query) }
        }
    }

    /// Hand-rolled rather than `.searchable`, which only offers navigation-bar
    /// placements — and the bar is where this field was before, above the
    /// control that decides whether searching is even what you are doing.
    ///
    /// What that costs: the system's Cancel button and its scroll-to-reveal.
    /// What it must therefore remember to do itself: refuse to capitalise or
    /// autocorrect, since half of what gets typed here is a URL and iOS is
    /// happy to turn one into prose.
    private func field(_ model: SearchModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Show name or RSS URL",
                text: Binding(get: { model.query }, set: { model.query = $0 })
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($typing)
            // The plain return arrow. Not "Search", which by the time the key
            // is reachable has already happened — results arrive as you type —
            // and not "Done", which iOS draws as a checkmark that reads like
            // confirming something rather than finishing typing. Pressing it
            // dismisses either way; the label is only what it looks like.
            .submitLabel(.return)
            .onSubmit { typing = false }
            if !model.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var discoverHalf: some View {
        if let discover {
            DiscoverList(model: discover, storefront: $storefront)
        }
    }


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
            // past it — which is this row, and now the only one: the toolbar
            // button that used to be the other way in is gone, since it led
            // to the same screen a pasted URL reaches from the field above.
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
