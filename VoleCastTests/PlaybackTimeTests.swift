import Testing
import Foundation
@testable import VoleCast

struct PlaybackTimeTests {

    @Test(arguments: [
        (0.0, "0:00"),
        (7.0, "0:07"),
        (63.0, "1:03"),
        (423.0, "7:03"),
        (599.0, "9:59"),
        (3599.0, "59:59"),
        (3600.0, "1:00:00"),
        (4364.0, "1:12:44"),
        // Seconds are truncated, not rounded: a scrubber that reads 1:03 while
        // the player is at 1:03.9 is right, one that reads 1:04 is ahead.
        (63.9, "1:03"),
    ])
    func formatsAClock(_ seconds: TimeInterval, _ expected: String) {
        #expect(PlaybackTime.clock(seconds) == expected)
    }

    /// A duration reaches this straight from the store, where a feed put it, so
    /// it has to be total in the same way `EpisodeSubtitle` is.
    @Test(arguments: [-1.0, -0.5, .infinity, -.infinity, .nan, 1e12, .greatestFiniteMagnitude])
    func refusesWhatCannotBeAPosition(_ seconds: TimeInterval) {
        #expect(PlaybackTime.clock(seconds) == PlaybackTime.placeholder)
        #expect(PlaybackTime.remaining(seconds) == PlaybackTime.placeholder)
    }

    @Test func formatsWhatIsLeft() {
        #expect(PlaybackTime.remaining(2712) == "-45:12")
        #expect(PlaybackTime.remaining(0) == "-0:00")
    }

    @Test func placeholderIsTheSameWidthAsAShortClock() {
        #expect(PlaybackTime.placeholder == "--:--")
    }
}
