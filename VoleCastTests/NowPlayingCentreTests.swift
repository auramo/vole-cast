import Testing
import MediaPlayer
import UIKit
@testable import VoleCast

struct NowPlayingCentreTests {

    /// MediaRemote builds and asks for the artwork on its own queue, whenever
    /// it likes. A request handler that carries main-actor isolation — which it
    /// does by default, being written inside a `@MainActor` type — aborts the
    /// process there with "BUG IN CLIENT OF LIBDISPATCH: Assertion failed:
    /// Block was expected to execute on queue".
    ///
    /// Nothing crosses the boundary here but a `CGSize`, because
    /// `MPMediaItemArtwork` is not `Sendable`: it has to be made and used on
    /// the same side, exactly as MediaRemote does it.
    @Test func artworkIsUsableEntirelyOffTheMainActor() async {
        let size = await Task.detached {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            let artwork = NowPlayingCentre.artwork(for: image)
            return artwork.image(at: CGSize(width: 64, height: 64))?.size
        }.value

        #expect(size != nil)
    }

    /// A steering wheel's skip buttons send track-skip, not skip-by-interval:
    /// they were built for music, where the next thing is a track. Disabled —
    /// which they were, since a podcast has no queue — they do nothing in the
    /// car, and there is no other way to jump from the wheel.
    ///
    /// Only that they answer at all. What they do with the press is a closure
    /// `MPRemoteCommand` gives no public way to fire.
    @MainActor
    @Test func theWheelsTrackButtonsAreAnswered() {
        let centre = NowPlayingCentre()
        defer { centre.tearDown() }

        #expect(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
        #expect(MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled)
    }
}
