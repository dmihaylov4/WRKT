import Foundation
import Supabase
import Testing
@testable import WRKT

@MainActor
@Suite(.serialized)
struct PostCaptionUpdateTests {
    @Test func clearingCaptionSendsExplicitNull() async throws {
        let body = try await update(caption: nil)
        #expect(body.keys.contains("caption"))
        #expect(body["caption"] is NSNull)
        #expect(body["visibility"] as? String == "friends")
        #expect(body["updated_at"] is String)
    }

    @Test func editingCaptionSendsTheText() async throws {
        let body = try await update(caption: "A fresh description")
        #expect(body["caption"] as? String == "A fresh description")
    }

    private func update(caption: String?) async throws -> [String: Any] {
        CaptionRequestProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptionRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = PostRepository(client: SupabaseClient(
            supabaseURL: URL(string: "https://caption-fixture.invalid")!,
            supabaseKey: "fixture-key",
            options: .init(global: .init(session: session))
        ))
        try await repository.updatePost(UUID(), caption: caption, visibility: .friends)
        let data = try #require(CaptionRequestProtocol.recordedBody())
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class CaptionRequestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var body: Data?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        body = nil
    }

    static func recordedBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var buffer = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                buffer.append(contentsOf: bytes.prefix(count))
            }
            data = buffer
        }
        Self.lock.lock()
        Self.body = data
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
