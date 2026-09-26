import SwiftData
import SwiftUI

/// What you have been listening to, most recent first.
struct HistoryView: View {
    @Binding var path: NavigationPath

    @Query(ListeningHistory.descriptor())
    private var episodes: [Episode]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if episodes.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Played Yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Episodes you play show up here, finished or not.")
                    }
                } else {
                    List(episodes) { episode in
                        HStack(spacing: 8) {
                            Button {
                                path.append(episode)
                            } label: {
                                EpisodeListRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows episode details")

                            EpisodePlayButton(episode: episode)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0, path: $path) }
        }
    }
}

#Preview {
    let container = VoleCastModelContainer.makeInMemory()
    HistoryView(path: .constant(NavigationPath()))
        .modelContainer(container)
        .environment(PlayerModel(playback: AVPlayerAudioEngine(), context: ModelContext(container)))
}
