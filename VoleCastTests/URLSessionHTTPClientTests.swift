import Testing
import Foundation
@testable import VoleCast

/// Serialized because `StubURLProtocol` is installed process-wide: these tests
/// would otherwise race each other for it.
@Suite(.serialized)
struct URLSessionHTTPClientTests {

    private let url = URL(string: "https://feed.example.com/rss")!

    private func client() -> URLSessionHTTPClient {
        URLSessionHTTPClient(session: StubURLProtocol.session())
    }

    @Test func returnsABodyWithinTheCap() async throws {
        StubURLProtocol.install(.init(declaredLength: 11, chunks: [Data("hello world".utf8)]))

        let (data, response) = try await client().data(for: URLRequest(url: url), maxBytes: 1024)

        #expect(String(decoding: data, as: UTF8.self) == "hello world")
        #expect(response.statusCode == 200)
    }

    /// A server that announces more than the cap is refused on its headers,
    /// before its body is transferred at all.
    @Test func refusesADeclaredLengthOverTheCap() async throws {
        StubURLProtocol.install(
            .init(declaredLength: 100 << 20, chunks: [Data(repeating: 0x41, count: 4096)])
        )

        await #expect(throws: NetworkError.tooLarge) {
            try await client().data(for: URLRequest(url: url), maxBytes: 8192)
        }
    }

    /// The dangerous case: no `Content-Length` at all, so the only defence is
    /// counting bytes as they arrive and giving up once they pass the cap.
    ///
    /// Asserting the refusal is not enough — buffering the whole body and then
    /// measuring it would pass that too. What makes the cap worth having is
    /// that the transfer stops, so the body here never ends on its own: the
    /// only thing that can end it is the client cancelling.
    @Test func stopsReadingAnUndeclaredBodyOnceItPassesTheCap() async throws {
        StubURLProtocol.install(
            .init(declaredLength: nil, endless: Data(repeating: 0x41, count: 1024))
        )

        await #expect(throws: NetworkError.tooLarge) {
            try await client().data(for: URLRequest(url: url), maxBytes: 8192)
        }
        #expect(await StubURLProtocol.waitForStop())
        #expect(!StubURLProtocol.wasExhausted)
    }

    /// An over-sized declared length is refused on the headers, before the body
    /// matters at all — so this one is stopped too, and sooner.
    @Test func doesNotReadTheBodyOfAnOversizedDeclaredLength() async throws {
        StubURLProtocol.install(
            .init(declaredLength: 100 << 20, endless: Data(repeating: 0x41, count: 1024))
        )

        await #expect(throws: NetworkError.tooLarge) {
            try await client().data(for: URLRequest(url: url), maxBytes: 8192)
        }
        #expect(await StubURLProtocol.waitForStop())
        #expect(!StubURLProtocol.wasExhausted)
    }

    @Test func stillReportsHTTPErrorStatuses() async throws {
        StubURLProtocol.install(.init(statusCode: 404, declaredLength: 0, chunks: []))

        await #expect(throws: NetworkError.notFound) {
            try await client().data(for: URLRequest(url: url), maxBytes: 1024)
        }
    }
}
