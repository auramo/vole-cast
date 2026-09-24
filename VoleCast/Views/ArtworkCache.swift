import Foundation
import ImageIO
import UIKit

/// Decodes artwork at the size it will actually be drawn, and remembers it.
///
/// Feeds serve enormous art — 3000×3000 is routine, and the URL usually says so
/// — while a list row draws it at 56pt. `AsyncImage` decodes at full size and
/// keeps no decoded image, so a 3000×3000 JPEG becomes a 34 MB bitmap, thrown
/// away and rebuilt every time a row is recycled. That is around 319 times more
/// pixels than the row can show, and it is what makes scrolling stutter.
///
/// `CGImageSourceCreateThumbnailAtIndex` decodes *at* the requested size rather
/// than decoding everything and scaling afterwards, so the full bitmap is never
/// built. The cache then makes a row that comes back into view free.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let images = NSCache<NSString, UIImage>()

    init() {
        // Small thumbnails: a hundred of them is a few megabytes, and the cost
        // of a miss is another decode.
        images.countLimit = 200
    }

    // MARK: - Cache

    func cached(_ url: URL, maxPixels: Int) -> UIImage? {
        images.object(forKey: Self.key(url, maxPixels))
    }

    func store(_ image: UIImage, for url: URL, maxPixels: Int) {
        images.setObject(image, forKey: Self.key(url, maxPixels))
    }

    /// The cached image, or one fetched and decoded to size.
    func image(for url: URL, maxPixels: Int) async -> UIImage? {
        if let hit = cached(url, maxPixels: maxPixels) { return hit }

        // `URLSession.shared` rather than `AppURLSession`, whose RSS `Accept`
        // header and feed-sized cache suit a feed and not an image.
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

        // Off the main actor: decoding is the expensive part, and the whole
        // point is to keep it away from the scroll.
        let decoded = await Task.detached(priority: .utility) {
            Self.downsample(data, maxPixels: maxPixels)
        }.value
        guard let image = decoded else { return nil }

        store(image, for: url, maxPixels: maxPixels)
        return image
    }

    // MARK: - Decoding

    /// Nonisolated: this runs off the main actor, and touches nothing shared.
    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Respects EXIF orientation, which some feed artwork carries.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, on this thread, rather than lazily on the main one
            // the first time the image is drawn.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private static func key(_ url: URL, _ maxPixels: Int) -> NSString {
        // Size is part of the key: the same art is drawn at 40pt in the bar and
        // 260pt in the full player.
        "\(maxPixels)|\(url.absoluteString)" as NSString
    }
}
