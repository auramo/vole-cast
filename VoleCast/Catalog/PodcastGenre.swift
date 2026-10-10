import Foundation

/// One of Apple's podcast categories, as the charts endpoint understands them.
///
/// Hardcoded rather than fetched. Apple publishes the list at
/// `MZStoreServices.woa/ws/genres?id=26`, but asking for it would put a second
/// network call — and a second way to fail — in front of a screen whose whole
/// job is to work when you have nothing in mind. The list has been these
/// nineteen for years; a new one appearing is a release, not an outage.
///
/// The ids are Apple's own and are the only thing the chart URL takes. A wrong
/// one does not error: it returns a perfectly valid chart of something else,
/// which is why `PodcastGenreTests` checks them against the real values.
///
/// One deliberate shortcoming: Apple returns category names localized to the
/// storefront, and these are English whatever store you are browsing. Fixing
/// that means either trusting the names in the chart payload — which arrive
/// too late to label a picker — or shipping translations the app does not yet
/// have anywhere else.
struct PodcastGenre: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    /// Alphabetical, because no other order means anything to someone reading
    /// a list of nineteen categories. Apple's numeric ids are historical.
    static let all: [PodcastGenre] = [
        PodcastGenre(id: 1301, name: String(localized: "Arts")),
        PodcastGenre(id: 1321, name: String(localized: "Business")),
        PodcastGenre(id: 1303, name: String(localized: "Comedy")),
        PodcastGenre(id: 1304, name: String(localized: "Education")),
        PodcastGenre(id: 1483, name: String(localized: "Fiction")),
        PodcastGenre(id: 1511, name: String(localized: "Government")),
        PodcastGenre(id: 1512, name: String(localized: "Health & Fitness")),
        PodcastGenre(id: 1487, name: String(localized: "History")),
        PodcastGenre(id: 1305, name: String(localized: "Kids & Family")),
        PodcastGenre(id: 1502, name: String(localized: "Leisure")),
        PodcastGenre(id: 1310, name: String(localized: "Music")),
        PodcastGenre(id: 1489, name: String(localized: "News")),
        PodcastGenre(id: 1314, name: String(localized: "Religion & Spirituality")),
        PodcastGenre(id: 1533, name: String(localized: "Science")),
        PodcastGenre(id: 1324, name: String(localized: "Society & Culture")),
        PodcastGenre(id: 1545, name: String(localized: "Sport")),
        PodcastGenre(id: 1318, name: String(localized: "Technology")),
        PodcastGenre(id: 1309, name: String(localized: "TV & Film")),
        PodcastGenre(id: 1488, name: String(localized: "True Crime")),
    ]
}
