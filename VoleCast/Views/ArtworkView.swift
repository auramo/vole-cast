import SwiftUI

/// Square show or episode artwork, with a placeholder of the same size so rows
/// don't reflow as images arrive.
struct ArtworkView: View {
    let url: String?
    let size: CGFloat

    private var resolved: URL? { url.flatMap(URL.init(string:)) }

    var body: some View {
        AsyncImage(url: resolved) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .font(.system(size: size * 0.32))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .accessibilityHidden(true)
    }
}
