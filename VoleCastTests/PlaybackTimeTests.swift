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

    // MARK: - Percentage

    /// The separator is the whole reason this takes a locale: Finnish puts a
    /// space before the sign and English does not, and building the string by
    /// hand would get one of them wrong.
    @Test func aPercentageFollowsTheLanguage() {
        let en = PlaybackTime.percent(0.25, locale: Locale(identifier: "en_US"))
        let fi = PlaybackTime.percent(0.25, locale: Locale(identifier: "fi_FI"))

        #expect(en == "25%")
        // Finnish separates the number from the sign, and does it with a
        // non-breaking space — which is why that is not written out as a
        // literal here. A first attempt asserted against a plain space and
        // failed against output that printed identically.
        #expect(fi != en)
        #expect(fi?.hasPrefix("25") == true)
        #expect(fi?.hasSuffix("%") == true)
    }

    /// "0 %" beside an episode reads as a fault rather than as information.
    @Test func somethingTooSmallToRoundUpSaysNothing() {
        #expect(PlaybackTime.percent(0) == nil)
        #expect(PlaybackTime.percent(0.004) == nil)
        // Half a percent rounds up, so it has something to say.
        #expect(PlaybackTime.percent(0.005, locale: Locale(identifier: "en_US")) == "1%")
    }

    @Test func refusesAFractionThatCannotBeReal() {
        #expect(PlaybackTime.percent(.nan) == nil)
        #expect(PlaybackTime.percent(.infinity) == nil)
        #expect(PlaybackTime.percent(-0.5) == nil)
        #expect(PlaybackTime.percent(1.5) == nil)
    }
}
