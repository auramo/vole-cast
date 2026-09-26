import Foundation
import SwiftData

/// Opening a show's episode list, optionally landing on one episode.
///
/// A show used to be pushed as a bare `Podcast`. Arriving at a particular
/// episode needs one more thing than the show itself, and a navigation value
/// can only carry what it is.
///
/// The episode travels as its `PersistentIdentifier` rather than the model:
/// nothing on the far side needs to read it — the list's rows are already
/// keyed by it — and an identifier cannot be left dangling by a delete the way
/// a second model reference could.
struct ShowDestination: Hashable {
    let podcast: Podcast
    /// Scroll here on arrival. Nil when the show was opened for its own sake.
    let focus: PersistentIdentifier?

    init(podcast: Podcast, focus: PersistentIdentifier? = nil) {
        self.podcast = podcast
        self.focus = focus
    }
}
