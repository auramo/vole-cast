import Testing
import Foundation
@testable import VoleCast

struct EpisodeDurationTests {

    @Test(arguments: [
        ("3600", 3600.0),
        ("56:12", 3372.0),
        ("01:02:03", 3723.0),
        ("1:02:03", 3723.0),
        (" 1:02:03 ", 3723.0),
        ("0:30", 30.0),
        // Feeds do write minute counts past an hour.
        ("90:00", 5400.0),
        ("3600.5", 3600.5),
        ("00:00:45.250", 45.25),
    ])
    func parsesTheThreeShapes(_ input: String, _ expected: TimeInterval) {
        #expect(EpisodeDuration.seconds(from: input) == expected)
    }

    @Test(arguments: ["", "  ", "abc", "1:2:3:4", "12:99", "-30", "0", "00:00"])
    func rejectsNonsense(_ input: String) {
        #expect(EpisodeDuration.seconds(from: input) == nil)
    }

    /// `Double("inf")` and `Double("1e400")` both succeed, and infinity passes a
    /// bare `>= 0` check. Left in, the value reaches `Duration.seconds` and
    /// traps — and because it is persisted, it traps on every later launch.
    @Test(arguments: ["inf", "-inf", "infinity", "Inf", "1e400", "nan", "NaN"])
    func rejectsValuesThatAreNotRealDurations(_ input: String) {
        #expect(EpisodeDuration.seconds(from: input) == nil)
    }

    /// Finite but absurd values trap the same way: anything past roughly 1.7e20
    /// seconds overflows `Duration`'s internal Int128.
    @Test(arguments: ["1e21", "999999999999999999999", "86400000", "3:1e20"])
    func rejectsDurationsLongerThanAnyEpisode(_ input: String) {
        #expect(EpisodeDuration.seconds(from: input) == nil)
    }

    /// The ceiling has to stay clear of genuinely long shows — unabridged
    /// audiobook chapters and 24-hour charity streams are real.
    @Test func acceptsGenuinelyLongEpisodes() {
        #expect(EpisodeDuration.seconds(from: "86400") == 86400.0)
        #expect(EpisodeDuration.seconds(from: "24:00:00") == 86400.0)
    }
}
