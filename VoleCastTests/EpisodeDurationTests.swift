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
}
