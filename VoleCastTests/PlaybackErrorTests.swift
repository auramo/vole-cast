import Testing
import Foundation
@testable import VoleCast

struct PlaybackErrorTests {

    /// Every case has to say something a listener can act on. A failure that
    /// renders as an empty string is indistinguishable from silence.
    @Test(arguments: [
        PlaybackError.unplayable,
        .offline,
        .failed("CDN returned 500"),
    ])
    func everyFailureExplainsItself(_ error: PlaybackError) {
        #expect(!(error.errorDescription ?? "").isEmpty)
        #expect(!(error.recoverySuggestion ?? "").isEmpty)
    }

    /// The underlying text is for the log, not the listener — it is where
    /// "Error Domain=NSURLErrorDomain Code=-1008" would otherwise surface.
    @Test func doesNotPutRawFrameworkTextInFrontOfAnyone() {
        let error = PlaybackError.failed("Error Domain=NSURLErrorDomain Code=-1008")
        #expect(error.errorDescription?.contains("NSURLErrorDomain") == false)
    }
}
