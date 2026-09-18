import Foundation

/// The session every request goes through.
///
/// Caching is left to `URLCache`: feeds send `ETag`/`Last-Modified` and iTunes
/// sends cache headers, so conditional revalidation comes for free and a
/// hand-rolled cache would only reimplement it worse. Pull-to-refresh asks for
/// revalidation explicitly with `.reloadRevalidatingCacheData`.
enum AppURLSession {
    /// Feeds are polite in the low hundreds of kilobytes; a few are tens of
    /// megabytes. Past this we refuse rather than choke a phone.
    static let feedByteLimit = 15 << 20
    static let jsonByteLimit = 2 << 20

    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 << 20,
            diskCapacity: 64 << 20,
            directory: nil
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        // Some feed hosts block unidentified clients, and it is good manners.
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.8",
        ]
        return URLSession(configuration: configuration)
    }()

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "VoleCast/\(version ?? "1.0") (+https://github.com/auramo/vole-cast)"
    }
}
