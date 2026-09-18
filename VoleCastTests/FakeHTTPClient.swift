import Foundation
@testable import VoleCast

/// A stand-in for the network. The handler is `@Sendable` because `HTTPClient`
/// is, and Swift 6 holds us to it.
struct FakeHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try handler(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // The real client maps transport errors before they escape, and a
            // fake that skips that step would let tests pass against a contract
            // the app never sees.
            throw error is CancellationError ? error : NetworkError(from: error)
        }
        guard data.count <= maxBytes else { throw NetworkError.tooLarge }
        if let error = NetworkError.forStatus(response.statusCode) { throw error }
        return (data, response)
    }

    static func ok(_ data: Data, url: URL = URL(string: "https://example.com/feed")!) -> FakeHTTPClient {
        FakeHTTPClient { _ in (data, response(url: url, status: 200)) }
    }

    /// Answers as if the request had been redirected to `finalURL`, which is
    /// what `URLSession` reports: the response's URL is the last one followed.
    static func redirecting(
        to finalURL: URL,
        data: Data
    ) -> FakeHTTPClient {
        FakeHTTPClient { _ in (data, response(url: finalURL, status: 200)) }
    }

    static func status(
        _ code: Int,
        url: URL = URL(string: "https://example.com/feed")!
    ) -> FakeHTTPClient {
        FakeHTTPClient { _ in (Data(), response(url: url, status: code)) }
    }

    static func failing(_ error: Error) -> FakeHTTPClient {
        FakeHTTPClient { _ in throw error }
    }

    /// Fails the first request and serves `data` for every one after it, for
    /// exercising the http→https retry.
    static func failingOnce(
        with error: Error,
        thenServing data: Data,
        from url: URL
    ) -> FakeHTTPClient {
        let served = Mutex(false)
        return FakeHTTPClient { _ in
            if served.exchange(true) {
                return (data, response(url: url, status: 200))
            }
            throw error
        }
    }

    private static func response(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
}

/// Minimal thread-safe box, so a `@Sendable` handler can carry state.
final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func exchange(_ newValue: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
