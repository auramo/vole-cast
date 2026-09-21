import Testing
import Foundation
@testable import VoleCast

struct EpisodeSubtitleTests {

    @Test func formatsADuration() {
        #expect(EpisodeSubtitle.text(published: nil, duration: 3600) == "1h")
        #expect(EpisodeSubtitle.text(published: nil, duration: 2520) == "42m")
    }

    @Test func omitsADurationItHasNothingToSayAbout() {
        #expect(EpisodeSubtitle.text(published: nil, duration: nil) == "")
        #expect(EpisodeSubtitle.text(published: nil, duration: 0) == "")
    }

    /// `EpisodeDuration` refuses these now, but the subtitle is also reached
    /// with values read back from the store, so it must not trap on one that
    /// was persisted before the parser learned to reject it.
    @Test(arguments: [Double.infinity, -Double.infinity, .nan, 1e21, .greatestFiniteMagnitude])
    func survivesADurationThatCouldNotBeReal(_ duration: TimeInterval) {
        #expect(EpisodeSubtitle.text(published: nil, duration: duration) == "")
    }
}
