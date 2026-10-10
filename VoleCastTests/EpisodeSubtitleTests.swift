import Testing
import Foundation
@testable import VoleCast

struct EpisodeSubtitleTests {

    /// These assert on English wording, so they say so rather than depending on
    /// wherever they happen to run. Finnish answers "42 min" where English
    /// answers "42m", and the suite should not start failing in Helsinki.
    private let english = Locale(identifier: "en_US")

    @Test func formatsADuration() {
        #expect(EpisodeSubtitle.text(published: nil, duration: 3600, locale: english) == "1h")
        #expect(EpisodeSubtitle.text(published: nil, duration: 2520, locale: english) == "42m")
    }

    @Test func omitsADurationItHasNothingToSayAbout() {
        #expect(EpisodeSubtitle.text(published: nil, duration: nil, locale: english) == "")
        #expect(EpisodeSubtitle.text(published: nil, duration: 0, locale: english) == "")
    }

    /// `EpisodeDuration` refuses these now, but the subtitle is also reached
    /// with values read back from the store, so it must not trap on one that
    /// was persisted before the parser learned to reject it.
    @Test(arguments: [Double.infinity, -Double.infinity, .nan, 1e21, .greatestFiniteMagnitude])
    func survivesADurationThatCouldNotBeReal(_ duration: TimeInterval) {
        #expect(EpisodeSubtitle.text(published: nil, duration: duration, locale: english) == "")
    }
}
