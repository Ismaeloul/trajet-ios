import XCTest
@testable import Trajet

/// El QR del panel (`trajet://pair?…`) y el emparejamiento contra un
/// servidor falso.
final class PairingStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.registry.reset(nil)
    }

    override func tearDown() {
        MockURLProtocol.registry.reset(nil)
        super.tearDown()
    }

    // MARK: - Leer el QR

    func testQRBueno() throws {
        let link = try PairingLink.parse(try XCTUnwrap(URL(string: PreviewData.pairingLink)))
        XCTAssertEqual(link.code, "ABCD-EFGH")
        XCTAssertEqual(link.lanURL, "http://192.168.1.10:7796")
        XCTAssertEqual(link.tailscaleURL, "http://100.64.0.10:7796")
        XCTAssertEqual(link.serverName, "Trajet de casa")
        XCTAssertEqual(link.addresses, ["http://192.168.1.10:7796", "http://100.64.0.10:7796"])
    }

    func testQRSoloTailscaleYSinVersionNiNombre() throws {
        let url = try XCTUnwrap(URL(string: "trajet://pair?code=abcd%20efgh&ts=http%3A%2F%2Fmi-umbrel.tail1234.ts.net%3A7796%2F"))
        let link = try PairingLink.parse(url)
        XCTAssertEqual(link.code, "ABCDEFGH")
        XCTAssertNil(link.lanURL)
        XCTAssertEqual(link.tailscaleURL, "http://mi-umbrel.tail1234.ts.net:7796")
        XCTAssertNil(link.serverName)
    }

    func testQRMalo() throws {
        func parseError(_ text: String) -> PairingLinkError? {
            guard let url = URL(string: text) else { return .notAPairingLink }
            do {
                _ = try PairingLink.parse(url)
                return nil
            } catch let failure as PairingLinkError {
                return failure
            } catch {
                return nil
            }
        }
        XCTAssertEqual(parseError("https://pair?v=1&code=ABCD-EFGH&lan=http%3A%2F%2Fa%3A1"), .notAPairingLink)
        XCTAssertEqual(parseError("trajet://ruta/5"), .notAPairingLink)
        XCTAssertEqual(parseError("trajet://pair?v=2&code=ABCD-EFGH&lan=http%3A%2F%2Fa%3A1"), .unsupportedVersion("2"))
        XCTAssertEqual(parseError("trajet://pair?v=1&lan=http%3A%2F%2Fa%3A1"), .missingCode)
        XCTAssertEqual(parseError("trajet://pair?v=1&code=ABC&lan=http%3A%2F%2Fa%3A1"), .badCode)
        XCTAssertEqual(parseError("trajet://pair?v=1&code=ABCD-EFG%21&lan=http%3A%2F%2Fa%3A1"), .badCode)
        XCTAssertEqual(parseError("trajet://pair?v=1&code=ABCD-EFGH"), .noAddresses)
        XCTAssertEqual(parseError("trajet://pair?v=1&code=ABCD-EFGH&lan=ftp%3A%2F%2Fcasa"), .badAddress("ftp://casa"))
        XCTAssertNotNil(PairingLinkError.badCode.errorDescription)
    }

    func testCodigoAMano() throws {
        XCTAssertEqual(try PairingLink.normalizeCode("abcd efgh"), "ABCDEFGH")
        XCTAssertEqual(try PairingLink.normalizeCode(" ABCD-EFGH "), "ABCD-EFGH")
        XCTAssertEqual(try PairingLink.normalizeCode(PreviewData.demoCode), "DEMO-2026")
        XCTAssertThrowsError(try PairingLink.normalizeCode("ABCD-EF"))
        XCTAssertThrowsError(try PairingLink.normalizeCode("ÁBCD-EFGH"))
        XCTAssertThrowsError(try PairingLink.normalizeCode(String(repeating: "A", count: 17)))
    }

    // MARK: - Emparejar

    /// Casa no responde, Tailscale sí: se canjea el código allí, se guarda el
    /// token y las direcciones del servidor, y Tailscale queda preferida.
    @MainActor
    func testEmparejaPorLaDireccionQueResponde() async throws {
        let config = ServerConfig(defaults: makeTestDefaults())
        let tokens = TokenStore.memory()
        let api = TrajetAPI(config: config, tokens: tokens,
                            session: TrajetAPI.makeSession(protocolClasses: [MockURLProtocol.self]))
        let store = PairingStore(api: api, config: config, tokens: tokens)
        XCTAssertFalse(store.isPaired)
        let pairedCalls = LockedBox(0)
        store.onPaired = { pairedCalls.value += 1 }

        MockURLProtocol.registry.reset { request in
            if request.url?.host == "casa.test" { throw URLError(.cannotConnectToHost) }
            switch request.url?.path ?? "" {
            case "/api/v1/ping": return MockReply.json(PreviewData.pingJSON)
            case "/api/v1/pair":
                return MockReply.json(PreviewData.pairResultJSON(lan: "http://casa.test:7796",
                                                                 tailscale: "http://ts.test:7796",
                                                                 name: "Casa"))
            default: return MockReply.error(.rutaNoEncontrada)
            }
        }
        let url = try XCTUnwrap(URL(string: "trajet://pair?v=1&code=abcd-efgh&lan=http%3A%2F%2Fcasa.test%3A7796&ts=http%3A%2F%2Fts.test%3A7796&name=Casa"))
        let ok = await store.handle(url: url)

        XCTAssertTrue(ok)
        XCTAssertTrue(store.isPaired)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(pairedCalls.value, 1)
        XCTAssertEqual(tokens.read(), PreviewData.demoToken)
        XCTAssertEqual(store.device?.id, 3)
        XCTAssertEqual(config.lanURL, "http://casa.test:7796")
        XCTAssertEqual(config.tailscaleURL, "http://ts.test:7796")
        XCTAssertEqual(config.preferredURL, "http://ts.test:7796")
        XCTAssertEqual(config.serverName, "Casa")

        // El canje fue en Tailscale, con el código y en snake_case.
        let pair = try XCTUnwrap(MockURLProtocol.registry.requests.last)
        XCTAssertEqual(pair.url?.host, "ts.test")
        XCTAssertEqual(pair.httpMethod, "POST")
        let body = try XCTUnwrap(pair.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["code"] as? String, "ABCD-EFGH")
        XCTAssertNotNil(json["device_name"] as? String)
        XCTAssertNil(pair.value(forHTTPHeaderField: "Authorization"))

        // Desemparejar: se olvida todo.
        let unpairedCalls = LockedBox(0)
        store.onUnpaired = { unpairedCalls.value += 1 }
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.unpairJSON) }
        await store.unpair()
        XCTAssertFalse(store.isPaired)
        XCTAssertNil(tokens.read())
        XCTAssertEqual(config.lanURL, "")
        XCTAssertNil(config.preferredURL)
        XCTAssertEqual(unpairedCalls.value, 1)
    }

    /// Código caducado o usado: se dice, sin guardar nada.
    @MainActor
    func testCodigoRechazado() async throws {
        let config = ServerConfig(defaults: makeTestDefaults())
        let tokens = TokenStore.memory()
        let api = TrajetAPI(config: config, tokens: tokens,
                            session: TrajetAPI.makeSession(protocolClasses: [MockURLProtocol.self]))
        let store = PairingStore(api: api, config: config, tokens: tokens)
        MockURLProtocol.registry.reset { request in
            request.url?.path == "/api/v1/ping" ? MockReply.json(PreviewData.pingJSON) : MockReply.error(.codigoNoValido)
        }
        let ok = await store.pair(code: "ABCD-EFGH", lanURL: "casa.test:7796")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.failure, .codeRejected)
        XCTAssertFalse(store.isPaired)
        XCTAssertNil(tokens.read())
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test", "casa.test"])
    }

    /// Nadie responde: «no se llega», sin canjear nada.
    @MainActor
    func testNadieResponde() async {
        let config = ServerConfig(defaults: makeTestDefaults())
        let tokens = TokenStore.memory()
        let api = TrajetAPI(config: config, tokens: tokens,
                            session: TrajetAPI.makeSession(protocolClasses: [MockURLProtocol.self]))
        let store = PairingStore(api: api, config: config, tokens: tokens)
        MockURLProtocol.registry.reset { _ in throw URLError(.timedOut) }
        let ok = await store.pair(code: "ABCD-EFGH", lanURL: "http://casa.test:7796", tailscaleURL: "http://ts.test:7796")
        XCTAssertFalse(ok)
        guard case .unreachable? = store.failure else {
            return XCTFail("tenía que ser «no se llega»")
        }
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test", "ts.test"])
        XCTAssertEqual(PairingStore.failure(for: .server(code: "rate_limited", message: "", status: 429, retryAfter: 60)),
                       .rateLimited(retryAfter: 60))
    }
}
