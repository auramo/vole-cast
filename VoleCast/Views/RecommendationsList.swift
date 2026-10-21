import SwiftUI

/// Suggested shows, grouped by the reason for each group.
struct RecommendationsList: View {
    let model: RecommendationsModel
    let onFindShows: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .failed(let error):
                ErrorView(error: error) { await model.refresh() }
            case .empty(let reason):
                empty(reason)
            case .loaded(let sections):
                list(sections)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.load() }
    }

    private func list(_ sections: [RecommendationSection]) -> some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        NavigationLink(value: row.source) {
                            ShowRow(
                                artworkURL: row.artworkURL?.absoluteString,
                                title: row.title,
                                author: row.author
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refresh() }
    }

    /// Worded as what to do next rather than what is missing. The same shape
    /// `LatestEpisodesView` uses when nothing is subscribed, so the two read
    /// as one app rather than two screens with separate opinions.
    @ViewBuilder
    private func empty(_ reason: RecommendationsModel.EmptyReason) -> some View {
        switch reason {
        case .noSubscriptions:
            ContentUnavailableView {
                Label("No Suggestions Yet", systemImage: "sparkles")
            } description: {
                Text("Subscribe to a show and suggestions appear here.")
            } actions: {
                Button("Find Shows", action: onFindShows)
            }
        case .noAppleShows:
            ContentUnavailableView {
                Label("No Suggestions Yet", systemImage: "sparkles")
            } description: {
                Text("Suggestions come from shows found by name. The feeds you pasted are not sent anywhere, so they cannot be used for this.")
            } actions: {
                Button("Find Shows", action: onFindShows)
            }
        case .nothingNew:
            ContentUnavailableView {
                Label("Nothing New to Suggest", systemImage: "checkmark.circle")
            } description: {
                Text("Everything we would suggest, you already follow.")
            }
        }
    }
}
