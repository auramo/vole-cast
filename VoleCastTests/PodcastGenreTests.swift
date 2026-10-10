import Testing
@testable import VoleCast

/// Nothing here touches itunes.apple.com. The list is hardcoded precisely so
/// that browsing by genre cannot fail at the network, and a test that fetched
/// it would undo that.
struct PodcastGenreTests {

    @Test func coversApplesNineteenPodcastGenres() {
        #expect(PodcastGenre.all.count == 19)
    }

    /// The id is the only thing the chart URL takes, so a duplicate would mean
    /// two rows in the picker that fetch the same chart.
    @Test func everyGenreHasItsOwnID() {
        let ids = PodcastGenre.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyGenreIsNamed() {
        #expect(PodcastGenre.all.allSatisfy { !$0.name.isEmpty })
    }

    /// The ids Apple's genre service actually returns. A typo here is not an
    /// error anywhere — a wrong id fetches a perfectly valid chart of
    /// something else — so the table is checked against the real list.
    ///
    /// Ids rather than names on purpose: the names are localized, so asserting
    /// on them would make this suite pass or fail according to the language of
    /// whoever runs it.
    @Test func carriesApplesOwnIdentifiers() {
        let apple: Set<Int> = [
            1301, 1303, 1304, 1305, 1309, 1310, 1314, 1318, 1321, 1324,
            1483, 1487, 1488, 1489, 1502, 1511, 1512, 1533, 1545,
        ]

        #expect(Set(PodcastGenre.all.map(\.id)) == apple)
    }
}
