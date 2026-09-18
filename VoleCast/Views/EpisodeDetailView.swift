import SwiftUI

/// One episode's show notes. Playback will land here first.
struct EpisodeDetailView: View {
    let episode: Episode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !episode.summary.isEmpty {
                    Text(HTMLText.plain(from: episode.summary))
                        .font(.callout)
                }
                if let page = episode.pageURL, let url = URL(string: page) {
                    Link("Open Episode Page", destination: url)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}
