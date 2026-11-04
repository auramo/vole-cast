import Foundation
import SwiftData

/// The rules behind the car's History tab: what you have played, most
/// recently first, finished or not.
///
/// Its rows are Latest's rows, built from the same parts, with one difference.
/// Latest never holds a finished episode, and History mostly does, so where a
/// Latest row would say how far in you are, a finished one here says so.
enum CarPlayHistoryList {
    /// The phone draws a checkmark. A car row has no place for one of its own,
    /// so the word goes in the line that already carries the details — the
    /// same word the episode's own screen on the phone uses.
    static var playedLabel: String { String(localized: "Played") }

    /// One section with no heading: the tab already names the list.
    static func sections(
        history: [Episode],
        current: PersistentIdentifier?
    ) -> [CarPlaySection] {
        let rows = history.map { episode in
            CarPlayRow(
                id: episode.persistentModelID,
                title: episode.title,
                subtitle: CarPlayLatestList.detail(
                    for: episode,
                    at: nil,
                    percent: episode.isPlayed ? playedLabel : CarPlayLatestList.percent(for: episode)
                ),
                isPlaying: episode.persistentModelID == current,
                artworkURL: CarPlayLatestList.artwork(for: episode)
            )
        }
        return [CarPlaySection(title: nil, rows: rows)]
    }
}
