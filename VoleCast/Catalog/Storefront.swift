import Foundation

/// Which of Apple's country stores to ask.
///
/// Every iTunes endpoint the app talks to is scoped to one, and they do not
/// agree on how they refuse an unknown one — the search and charts endpoints
/// answer 400, the newer charts host answers 500 — so the one thing worth
/// centralising is which code we ask for in the first place.
enum Storefront {
    /// Where to land when the device's region has no store of its own, or has
    /// no region set at all. Apple's largest catalogue, and the one most
    /// likely to recognise a show someone is looking for.
    static let fallback = "us"

    /// The device's own region, lowercased into the form the URLs want.
    static var device: String {
        Locale.current.region?.identifier.lowercased() ?? fallback
    }
}
