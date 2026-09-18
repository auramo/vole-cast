import Foundation
import Testing

/// Loads the canned feeds and API responses in `VoleCastTests/Fixtures/`.
///
/// `Bundle.main` is the *host app* in a unit-test bundle, so resources have to
/// be looked up relative to a type in this bundle instead. Xcode's synchronized
/// folder groups flatten the folder away, so files are found by bare name.
enum Fixtures {
    private final class BundleToken {}

    static func data(_ name: String, _ extension: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: `extension`),
            "Missing fixture \(name).\(`extension`) in \(bundle.bundleURL.lastPathComponent)"
        )
        return try Data(contentsOf: url)
    }

    static func feed(_ name: String) throws -> Data {
        try data(name, "xml")
    }

    static func json(_ name: String) throws -> Data {
        try data(name, "json")
    }
}
