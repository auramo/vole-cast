import Testing
import Foundation
@testable import VoleCast

struct RSSDateTests {
    /// 1 September 2025, 07:00:00 UTC, written the many ways feeds write it.
    private static let reference = Date(timeIntervalSince1970: 1_756_710_000)

    @Test(arguments: [
        "Mon, 01 Sep 2025 07:00:00 GMT",
        "Mon, 1 Sep 2025 07:00:00 GMT",
        "Mon, 01 Sep 2025 07:00:00 +0000",
        "Mon, 01 Sep 2025 10:00:00 +0300",
        "Mon, 01 Sep 2025 07:00:00 UT",
        "01 Sep 2025 07:00:00 GMT",
        "Mon, 01 Sep 2025 07:00:00 -0000",
        // A trailing zone comment is common and must not defeat parsing.
        "Mon, 01 Sep 2025 10:00:00 +0300 (EEST)",
        // Stray internal whitespace, seen in hand-rolled feeds.
        "Mon,  01  Sep  2025  07:00:00  GMT",
        "2025-09-01T07:00:00Z",
        "2025-09-01T10:00:00+03:00",
        "2025-09-01T07:00:00.000Z",
        "2025-09-01 07:00:00",
    ])
    func parsesTheRFC822Zoo(_ input: String) {
        #expect(RSSDate.parse(input) == Self.reference)
    }

    @Test func parsesDateOnly() {
        #expect(RSSDate.parse("2025-09-01") == Date(timeIntervalSince1970: 1_756_684_800))
    }

    @Test func missingZoneIsTreatedAsUTC() {
        #expect(RSSDate.parse("Mon, 01 Sep 2025 07:00:00") == Self.reference)
    }

    @Test(arguments: ["", "   ", "yesterday", "not a date", "0"])
    func returnsNilRatherThanGuessing(_ input: String) {
        #expect(RSSDate.parse(input) == nil)
    }
}
