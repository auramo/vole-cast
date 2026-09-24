import Testing
import Foundation
import UIKit
@testable import VoleCast

struct ArtworkCacheTests {

    /// Scale pinned to 1 so `side` means pixels. A renderer left to its own
    /// devices uses the display scale, which would quietly make a "64pt"
    /// fixture 192 pixels wide and every number here a third of what it says.
    private func jpeg(_ side: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        ).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    /// The whole point. Feeds serve 3000×3000 artwork for a 56pt thumbnail, and
    /// decoding one to full size costs 34 MB of bitmap — per row, per scroll,
    /// because `AsyncImage` keeps no decoded image.
    @Test func decodesAtTheSizeItWillBeDrawnRatherThanFullSize() throws {
        let data = try jpeg(1200)

        let thumbnail = try #require(ArtworkCache.downsample(data, maxPixels: 168))

        let cgImage = try #require(thumbnail.cgImage)
        #expect(cgImage.width <= 168)
        #expect(cgImage.height <= 168)
    }

    @Test func keepsTheImageSquare() throws {
        let data = try jpeg(900)

        let thumbnail = try #require(ArtworkCache.downsample(data, maxPixels: 100))
        let cgImage = try #require(thumbnail.cgImage)

        #expect(cgImage.width == cgImage.height)
    }

    /// An image already smaller than the target is not blown up.
    @Test func leavesASmallImageAlone() throws {
        let data = try jpeg(64)

        let thumbnail = try #require(ArtworkCache.downsample(data, maxPixels: 512))
        let cgImage = try #require(thumbnail.cgImage)

        #expect(cgImage.width == 64)
    }

    @Test func refusesSomethingThatIsNotAnImage() {
        #expect(ArtworkCache.downsample(Data("not an image".utf8), maxPixels: 100) == nil)
    }

    /// Without this a recycled row decodes all over again, which is the other
    /// half of the cost.
    @Test @MainActor func remembersWhatItHasAlreadyDecoded() throws {
        let cache = ArtworkCache()
        let url = try #require(URL(string: "https://art.example.com/a.jpg"))
        let image = try #require(ArtworkCache.downsample(try jpeg(300), maxPixels: 100))

        #expect(cache.cached(url, maxPixels: 100) == nil)
        cache.store(image, for: url, maxPixels: 100)

        #expect(cache.cached(url, maxPixels: 100) === image)
    }

    /// The same artwork is drawn at 40pt in the bar and 260pt in the full
    /// player, and those must not be confused for one another.
    @Test @MainActor func keepsSizesApart() throws {
        let cache = ArtworkCache()
        let url = try #require(URL(string: "https://art.example.com/b.jpg"))
        let small = try #require(ArtworkCache.downsample(try jpeg(300), maxPixels: 100))

        cache.store(small, for: url, maxPixels: 100)

        #expect(cache.cached(url, maxPixels: 100) != nil)
        #expect(cache.cached(url, maxPixels: 800) == nil)
    }
}
