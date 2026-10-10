import SwiftUI

/// One show in a list: what it's called, who makes it, and one line of
/// whatever that list knows about it.
///
/// Shared by search results and chart rows so the two cannot drift apart —
/// they sit behind the same segmented control, and a reader switching between
/// them should see one kind of list, not two that nearly match.
struct ShowRow: View {
    let artworkURL: String?
    let title: String
    let author: String
    /// What this particular list has to add: an episode count from search, or
    /// nothing from a chart.
    var detail: String?
    /// Chart position. Shown only where the order is the point — a search
    /// result being third says nothing worth printing.
    var rank: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    // Fixed width so the artwork beside it lines up down the
                    // list rather than stepping right at number 10.
                    .frame(minWidth: 22, alignment: .trailing)
            }
            ArtworkView(url: artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
