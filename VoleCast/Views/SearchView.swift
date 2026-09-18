import SwiftUI

/// Finding a show by name, or by pasting a feed URL.
struct SearchView: View {
    @Binding var path: NavigationPath

    @Environment(\.podcastDirectory) private var directory
    @State private var model: SearchModel?
    @State private var showingAddByURL = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
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
            .navigationTitle("Search")
            .toolbar {
                Button("Add by RSS URL…", systemImage: "link.badge.plus") {
                    showingAddByURL = true
                }
            }
            .sheet(isPresented: $showingAddByURL) {
                AddFeedURLSheet { url in
                    path.append(ShowPreviewSource.feedURL(url))
                }
            }
            .navigationDestination(for: ShowPreviewSource.self) { source in
                ShowPreviewView(source: source)
            }
        }
        .onAppear {
            // Built here rather than in an initialiser so it picks up the
            // environment's directory, which previews and tests replace.
            if model == nil { model = SearchModel(directory: directory) }
        }
    }

    @ViewBuilder
    private func content(_ model: SearchModel) -> some View {
        switch model.state {
        case .idle where model.typedFeedURL == nil:
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
        case .idle, .results:
            resultsList(model)
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
                            SearchResultRow(result: result)
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

private struct SearchResultRow: View {
    let result: PodcastSearchResult

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: result.artworkURL?.absoluteString, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let count = result.episodeCount {
                    Text("^[\(count) episode](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
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
