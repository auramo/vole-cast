import SwiftUI

/// One episode's show notes. Playback will land here first.
struct EpisodeDetailView: View {
    let episode: Episode

    /// Step 1 scaffolding: wired straight to the engine so that audio can be
    /// heard before any of the player UI exists. `PlayerModel` replaces this.
    @State private var engine: AVPlayerAudioEngine?
    @State private var isPlaying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                playButton
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
        .onAppear { if engine == nil { engine = AVPlayerAudioEngine() } }
        .onDisappear {
            engine?.tearDown()
            engine = nil
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if let url = URL(string: episode.audioURL), !episode.audioURL.isEmpty {
            Button {
                guard let engine else { return }
                if isPlaying {
                    engine.pause()
                } else {
                    engine.load(playable(url))
                }
                isPlaying.toggle()
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func playable(_ url: URL) -> PlayableEpisode {
        PlayableEpisode(
            id: "\(episode.podcast?.feedIdentity ?? "")|\(episode.guid)",
            audioURL: url,
            mimeType: episode.audioMIMEType,
            title: episode.title,
            showTitle: episode.podcast?.title ?? "",
            artworkURL: (episode.artworkURL ?? episode.podcast?.artworkURL).flatMap(URL.init(string:)),
            feedDuration: episode.duration,
            startAt: 0
        )
    }
}
