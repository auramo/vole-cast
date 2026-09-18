import Foundation

/// Every way fetching something can fail, in terms the UI can act on.
///
/// Deliberately small: the screens only distinguish between "you're offline",
/// "slow down", "that isn't there" and "something went wrong", plus a retry.
enum NetworkError: Error, Equatable, LocalizedError {
    case offline
    case timedOut
    /// iTunes answers a throttled search with 403 rather than 429, so both land
    /// here. A 403 can in principle mean something else, which is why the copy
    /// stays vague and the response is logged.
    case rateLimited
    case notFound
    case serverError(Int)
    /// App Transport Security refused a plain-http URL.
    case insecureConnection
    case invalidURL
    case invalidResponse
    case decodingFailed
    case notAFeed
    case tooLarge

    /// Maps whatever came back into one of the cases above.
    ///
    /// `CancellationError` must never reach here — callers rethrow it, so a
    /// superseded search doesn't flash an error at the user.
    init(from error: Error) {
        switch error {
        case let error as NetworkError:
            self = error
        case let error as FeedParseError:
            self = error == .notAFeed ? .notAFeed : .invalidResponse
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .cannotFindHost, .cannotConnectToHost, .internationalRoamingOff:
                self = .offline
            case .timedOut:
                self = .timedOut
            case .appTransportSecurityRequiresSecureConnection:
                self = .insecureConnection
            case .unsupportedURL, .badURL:
                self = .invalidURL
            case .dataLengthExceedsMaximum:
                self = .tooLarge
            default:
                self = .invalidResponse
            }
        case is DecodingError:
            self = .decodingFailed
        default:
            self = .invalidResponse
        }
    }

    static func forStatus(_ code: Int) -> NetworkError? {
        switch code {
        case 200...299: nil
        case 403, 429: .rateLimited
        case 404, 410: .notFound
        case 500...599: .serverError(code)
        default: .invalidResponse
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "No Internet Connection")
        case .timedOut: String(localized: "The Connection Timed Out")
        case .rateLimited: String(localized: "Too Many Searches Right Now")
        case .notFound: String(localized: "Not Found")
        case .serverError: String(localized: "The Server Had a Problem")
        case .insecureConnection: String(localized: "Insecure Connection")
        case .invalidURL: String(localized: "That Isn't a Web Address")
        case .invalidResponse, .decodingFailed: String(localized: "Unexpected Response")
        case .notAFeed: String(localized: "Not a Podcast Feed")
        case .tooLarge: String(localized: "That Feed Is Too Big")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .offline: String(localized: "Check your connection and try again.")
        case .timedOut, .serverError: String(localized: "Try again in a moment.")
        case .rateLimited: String(localized: "Wait a few seconds and try again.")
        case .notFound: String(localized: "The feed may have moved or been taken down.")
        case .insecureConnection: String(localized: "This feed is served over an unencrypted connection, which iOS blocks.")
        case .invalidURL: String(localized: "Check the address and try again.")
        case .invalidResponse, .decodingFailed: String(localized: "Try again in a moment.")
        case .notAFeed: String(localized: "That address is a web page, not a feed. Look for an RSS link on the site.")
        case .tooLarge: String(localized: "It's too large to load on a phone.")
        }
    }

    /// The symbol shown alongside the message.
    var symbolName: String {
        switch self {
        case .offline: "wifi.slash"
        case .timedOut: "clock.arrow.circlepath"
        case .rateLimited: "clock.badge.exclamationmark"
        case .notFound, .notAFeed: "questionmark.circle"
        case .insecureConnection: "lock.slash"
        default: "exclamationmark.triangle"
        }
    }
}
