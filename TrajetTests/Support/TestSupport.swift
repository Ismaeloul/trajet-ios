import Foundation
import XCTest
@testable import Trajet

// Piezas comunes de los tests: un URLProtocol falso para TrajetAPI, un
// servidor de tableros de mentira para BoardStore y un reloj que se mueve a
// mano.

/// Servidor HTTP falso. Cada test pone su `handler` con `reset(_:)`; las
/// peticiones que llegan quedan apuntadas (con el cuerpo ya leído).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// (estado, cuerpo, cabeceras) o un error de transporte (URLError).
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data, [String: String])

    static let registry = MockRegistry()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            req.httpBody = Self.readAll(stream)
        }
        Self.registry.record(req)
        do {
            guard let handler = Self.registry.handler else { throw URLError(.cannotConnectToHost) }
            let (status, data, headers) = try handler(req)
            guard let url = req.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                 headerFields: headers)
            else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class MockRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: MockURLProtocol.Handler?
    private var storedRequests: [URLRequest] = []

    var handler: MockURLProtocol.Handler? {
        lock.lock(); defer { lock.unlock() }
        return storedHandler
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return storedRequests
    }

    /// Hosts de las peticiones, en orden.
    var hosts: [String] { requests.compactMap { $0.url?.host } }

    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        storedRequests.append(request)
    }

    func reset(_ handler: MockURLProtocol.Handler?) {
        lock.lock(); defer { lock.unlock() }
        storedHandler = handler
        storedRequests = []
    }
}

/// Respuestas de conveniencia para el handler.
enum MockReply {
    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> (Int, Data, [String: String]) {
        var h = headers
        h["Content-Type"] = "application/json"
        return (status, Data(body.utf8), h)
    }

    static func error(_ c: PreviewData.ErrorCase) -> (Int, Data, [String: String]) {
        json(PreviewData.errorJSON(c), status: c.status)
    }

    static func notModified(etag: String) -> (Int, Data, [String: String]) {
        (304, Data(), ["ETag": etag])
    }
}

/// Un reloj que solo avanza cuando se le dice.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 780_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// Servidor de tableros de mentira para BoardStore.
actor FakeBoardSource: BoardFetching {
    struct Call: Equatable, Sendable {
        let routeID: Int?
        let logHistory: Bool
    }

    private(set) var calls: [Call] = []
    private var replies: [Result<BoardPayload, APIError>] = []
    private var fallback: Result<BoardPayload, APIError>?

    init(fallback: Result<BoardPayload, APIError>? = nil) {
        self.fallback = fallback
    }

    func enqueue(_ reply: Result<BoardPayload, APIError>) {
        replies.append(reply)
    }

    func board(routeID: Int?, logHistory: Bool) async throws -> BoardPayload {
        calls.append(Call(routeID: routeID, logHistory: logHistory))
        let reply = replies.isEmpty ? (fallback ?? .failure(.network("sin respuesta preparada"))) : replies.removeFirst()
        return try reply.get()
    }
}

/// UserDefaults de usar y tirar.
func makeTestDefaults() -> UserDefaults {
    let name = "trajet.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Un cliente que habla con `MockURLProtocol`.
@MainActor
func makeMockAPI(token: String? = "trj_test",
                 lan: String = "http://casa.test:7796",
                 tailscale: String = "http://ts.test:7796") -> (TrajetAPI, ServerConfig) {
    let config = ServerConfig(defaults: makeTestDefaults())
    config.lanURL = lan
    config.tailscaleURL = tailscale
    let api = TrajetAPI(config: config, tokens: .memory(token),
                        session: TrajetAPI.makeSession(protocolClasses: [MockURLProtocol.self]))
    return (api, config)
}

/// El error que lanza `body`, o nil.
@MainActor
func captureError(_ body: () async throws -> Void) async -> Error? {
    do {
        try await body()
        return nil
    } catch {
        return error
    }
}

/// Espera (sin bloquear) a que se cumpla una condición, hasta `timeout` s.
@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

extension URLRequest {
    /// Valor de un parámetro de la query.
    func queryValue(_ name: String) -> String? {
        guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == name })?.value
    }
}
