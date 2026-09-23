import SwiftUI

/// One episode in a list that spans several shows — Latest and History.
///
/// Named for the job rather than the screen, because both use it. A single
/// show's own list has a different, smaller row: under that show's header,
/// repeating its artwork and name in every line would just be noise.
///
/// Expects to sit beside an `EpisodePlayButton` in an `HStack`, which is why
/// the trailing `Spacer` and `contentShape` below are not decoration.
struct EpisodeListRow: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The show's artwork unless the episode has its own.
            ArtworkView(url: episode.artworkURL ?? episode.podcast?.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                if let show = episode.podcast?.title, !show.isEmpty {
                    Text(show)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(episode.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(episode.isPlayed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                HStack(spacing: 4) {
                    if episode.isPlayed {
                        // Labelled explicitly: a bare symbol is decorative, and
                        // VoiceOver would skip it — leaving finished and
                        // unfinished indistinguishable to a screen reader while
                        // they differ plainly on screen.
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityLabel("Played")
                    }
                    Text(EpisodeSubtitle.text(published: episode.publishedAt, duration: episode.duration))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            // Without this the gap between the text and the play button belongs
            // to neither control and swallows taps.
            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
