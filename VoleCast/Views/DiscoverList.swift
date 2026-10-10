import SwiftUI

/// The chart half of the Search tab.
///
/// Everything it can go wrong with stays inside it. A dead endpoint, a country
/// with no store, no network at all — each draws here and nowhere else, so the
/// search field and the pasted-URL path above it keep working regardless.
struct DiscoverList: View {
    let model: DiscoverModel
    let onUseDeviceCountry: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .failed(let error):
                ErrorView(error: error) { await model.refresh() }
            case .unavailableCountry(let code):
                unavailable(code)
            case .empty:
                ContentUnavailableView {
                    Label("No Chart", systemImage: "list.number")
                } description: {
                    Text("Apple published nothing for this selection.")
                }
            case .loaded(let page):
                chart(page)
            }
        }
        // Keyed on both, so changing either asks for the right chart — and the
        // model answers from memory when it already has one.
        .task(id: "\(model.storefront)|\(model.genre?.id ?? 0)") { await model.load() }
    }

    private func chart(_ page: ChartPage) -> some View {
        List {
            Section {
                ForEach(page.entries) { entry in
                    NavigationLink(value: ShowPreviewSource.chart(entry)) {
                        ShowRow(
                            artworkURL: entry.artworkURL?.absoluteString,
                            title: entry.title,
                            author: entry.author,
                            rank: entry.rank
                        )
                    }
                }
            } header: {
                Text(model.genre?.name ?? String(localized: "Top Podcasts"))
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
    }

    /// Worded as a possibility rather than a diagnosis, because it is one: the
    /// two chart endpoints refuse an unknown country differently and neither
    /// says why, so a real outage reaches here too. Both ways out are offered.
    private func unavailable(_ code: String) -> some View {
        ContentUnavailableView {
            Label("No Charts for This Country", systemImage: "globe")
        } description: {
            Text("Apple may not have a podcast store in \(countryName(code)).")
        } actions: {
            Button("Use My Country") { onUseDeviceCountry() }
            Button("Try Again") { Task { await model.refresh() } }
        }
    }

    private func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code.uppercased()
    }
}
