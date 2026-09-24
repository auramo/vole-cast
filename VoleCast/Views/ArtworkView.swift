import SwiftUI

/// Square show or episode artwork, with a placeholder of the same size so rows
/// don't reflow as images arrive.
///
/// Backed by `ArtworkCache` rather than `AsyncImage`: feeds serve 3000×3000 art
/// for a 56pt row, and decoding that at full size on every row recycle is what
/// made the lists stutter.
struct ArtworkView: View {
    let url: String?
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var resolved: URL? { url.flatMap(URL.init(string:)) }

    /// Rounded up, so a 56pt row on a 3× screen decodes to 168 pixels.
    private var maxPixels: Int { Int((size * displayScale).rounded(.up)) }

    /// Checked during `body` rather than only in `task`, so a row scrolling
    /// back into view draws its artwork on the first frame instead of flashing
    /// the placeholder. An `NSCache` lookup is cheap enough to do here.
    private var image: UIImage? {
        if let loaded { return loaded }
        guard let resolved else { return nil }
        return ArtworkCache.shared.cached(resolved, maxPixels: maxPixels)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .accessibilityHidden(true)
        // Keyed, so a recycled row loads its own artwork rather than keeping
        // whatever the previous occupant had.
        .task(id: "\(maxPixels)|\(url ?? "")") {
            guard let resolved else {
                loaded = nil
                return
            }
            loaded = await ArtworkCache.shared.image(for: resolved, maxPixels: maxPixels)
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .font(.system(size: size * 0.32))
        }
    }
}
