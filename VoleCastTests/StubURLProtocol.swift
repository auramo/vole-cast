import Foundation

/// A stand-in transport for exercising `URLSessionHTTPClient` itself, which the
/// `HTTPClient` fakes deliberately bypass.
///
/// Lets a test declare a `Content-Length` independently of the bytes it
/// actually sends, which is the whole point when the thing under test is a
/// size cap: a hostile server's declared length and its body need not agree.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Stub {
        var statusCode = 200
        /// `nil` sends no `Content-Length`, as a chunked response does.
        var declaredLength: Int?
        var chunks: [Data] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stub = Stub()
    nonisolated(unsafe) private static var delivered = 0

    static func install(_ stub: Stub) {
        lock.lock()
        defer { lock.unlock() }
        Self.stub = stub
        delivered = 0
    }

    private static var current: Stub {
        lock.lock()
        defer { lock.unlock() }
        return stub
    }

    /// How many chunks actually went out. A client that bounds its reads stops
    /// the transfer, so this stays below the number the stub was given.
    static var deliveredChunks: Int {
        lock.lock()
        defer { lock.unlock() }
        return delivered
    }

    private static func recordDelivery() {
        lock.lock()
        delivered += 1
        lock.unlock()
    }

    private let stopLock = NSLock()
    private var stopped = false

    private var isStopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopped
    }

    /// A session wired to this protocol and nothing else.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.current
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: stub.declaredLength.map { ["Content-Length": String($0)] }
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)

        // Delivered off the calling thread, with a breath between chunks, so a
        // client that gives up part-way actually gets the chance to.
        let chunks = stub.chunks
        DispatchQueue.global().async { [self] in
            for chunk in chunks {
                guard !isStopped else { return }
                client?.urlProtocol(self, didLoad: chunk)
                Self.recordDelivery()
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard !isStopped else { return }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
    }
}
