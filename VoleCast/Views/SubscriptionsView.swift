import SwiftData
import SwiftUI

/// The shows you subscribe to, newest subscription first.
struct SubscriptionsView: View {
    @Binding var path: NavigationPath
    let onFindShows: () -> Void

    @Environment(\.modelContext) private var context

    @Query(sort: \Podcast.subscribedAt, order: .reverse)
    private var podcasts: [Podcast]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if podcasts.isEmpty {
                    ContentUnavailableView {
                        Label("No Subscriptions", systemImage: "square.stack")
                    } description: {
                        Text("Shows you subscribe to appear here.")
                    } actions: {
                        Button("Find Shows", action: onFindShows)
                    }
                } else {
                    List {
                        ForEach(podcasts) { podcast in
                            NavigationLink(value: podcast) {
                                PodcastRow(podcast: podcast)
                            }
                        }
                        .onDelete(perform: unsubscribe)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Subscriptions")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
        }
    }
}

extension SubscriptionsView {
    private func unsubscribe(at offsets: IndexSet) {
        for index in offsets {
            Subscriptions.unsubscribe(podcasts[index], in: context)
        }
    }
}

private struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: podcast.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SubscriptionsView(path: .constant(NavigationPath()), onFindShows: {})
        .modelContainer(VoleCastModelContainer.makeInMemory())
}
