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
        /// When set, the stub repeats this chunk and never finishes on its own.
        ///
        /// This is what makes a bound testable without a race: a finite body
        /// can be delivered in full before a cancellation lands, and then the
        /// test is measuring which thread won rather than whether the client
        /// stops. An endless body can only end one way.
        var endless: Data?
        /// So a client that fails to bound anything cannot hang the suite.
        var endlessCap = 4096
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stub = Stub()
    nonisolated(unsafe) private static var delivered = 0
    nonisolated(unsafe) private static var stopped = false

    static func install(_ stub: Stub) {
        lock.lock()
        defer { lock.unlock() }
        Self.stub = stub
        delivered = 0
        stopped = false
        exhausted = false
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

    /// Whether the client cancelled the transfer. With an endless body this is
    /// the whole assertion: nothing else can stop it.
    static var wasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Waits for the client to stop the transfer.
    ///
    /// Polled rather than sampled: cancelling a task and URLSession actually
    /// tearing the protocol down are not the same instant, and asserting on
    /// the second one immediately after the first is just a race in the other
    /// direction. This finishes as soon as the machine gets there, and only
    /// times out when the client genuinely never stopped.
    static func waitForStop(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if wasStopped { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private static func recordDelivery() {
        lock.lock()
        delivered += 1
        lock.unlock()
    }

    /// Set when an endless body ran to its safety cap, i.e. nobody stopped it.
    nonisolated(unsafe) private static var exhausted = false

    static var wasExhausted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exhausted
    }

    private static func recordExhausted() {
        lock.lock()
        exhausted = true
        lock.unlock()
    }

    private static func recordStop() {
        lock.lock()
        stopped = true
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
        let chunks = stub.endless.map { Array(repeating: $0, count: stub.endlessCap) } ?? stub.chunks
        let neverFinishes = stub.endless != nil
        DispatchQueue.global().async { [self] in
            for chunk in chunks {
                guard !isStopped else { return }
                client?.urlProtocol(self, didLoad: chunk)
                Self.recordDelivery()
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard !isStopped else { return }
            // Reaching here with an endless body means the client never
            // stopped reading — let it finish so the test fails on
            // `wasStopped` rather than hanging.
            if neverFinishes {
                Self.recordExhausted()
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
        Self.recordStop()
    }
}
