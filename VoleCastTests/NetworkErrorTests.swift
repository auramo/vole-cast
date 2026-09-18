import Testing
import Foundation
@testable import VoleCast

struct NetworkErrorTests {

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, NetworkError.offline),
        (.networkConnectionLost, .offline),
        (.cannotFindHost, .offline),
        (.timedOut, .timedOut),
        (.appTransportSecurityRequiresSecureConnection, .insecureConnection),
        (.badURL, .invalidURL),
        (.badServerResponse, .invalidResponse),
    ])
    func mapsURLErrors(_ code: URLError.Code, _ expected: NetworkError) {
        #expect(NetworkError(from: URLError(code)) == expected)
    }

    @Test(arguments: [
        (200, NetworkError?.none),
        (204, nil),
        // iTunes signals throttling with 403, not 429.
        (403, .rateLimited),
        (429, .rateLimited),
        (404, .notFound),
        (410, .notFound),
        (500, .serverError(500)),
        (503, .serverError(503)),
        (302, .invalidResponse),
    ])
    func mapsStatusCodes(_ code: Int, _ expected: NetworkError?) {
        #expect(NetworkError.forStatus(code) == expected)
    }

    @Test func passesThroughItsOwnCases() {
        #expect(NetworkError(from: NetworkError.tooLarge) == .tooLarge)
        #expect(NetworkError(from: FeedParseError.notAFeed) == .notAFeed)
        #expect(NetworkError(from: FeedParseError.malformedXML(line: 3, column: 1)) == .invalidResponse)
    }

    @Test func everyCaseExplainsItself() {
        let cases: [NetworkError] = [
            .offline, .timedOut, .rateLimited, .notFound, .serverError(500),
            .insecureConnection, .invalidURL, .invalidResponse, .decodingFailed,
            .notAFeed, .tooLarge,
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
            #expect(!error.symbolName.isEmpty)
        }
    }
}
