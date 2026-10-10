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

    /// Spot-checks against the ids Apple's genre service actually returns, so
    /// a typo in the table is caught rather than silently fetching the wrong
    /// chart — a wrong id returns a perfectly valid chart of something else.
    @Test(arguments: [(1303, "Comedy"), (1488, "True Crime"), (1489, "News"), (1321, "Business")])
    func carriesApplesOwnIdentifiers(_ id: Int, _ name: String) {
        #expect(PodcastGenre.all.first { $0.id == id }?.name == name)
    }
}
