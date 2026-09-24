import XCTest
@testable import Trajet

/// El cliente con un servidor falso (URLProtocol): dos direcciones en orden,
/// un error HTTP no salta, un fallo de red sí (R42); tiempos cortos y sin
/// caché (R43); token, ETag/304 y errores con código.
final class TrajetAPITests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.registry.reset(nil)
    }

    override func tearDown() {
        MockURLProtocol.registry.reset(nil)
        super.tearDown()
    }

    /// R42: casa caída → Tailscale, y queda como preferida para la siguiente.
    @MainActor
    func testOrdenDeCandidatos() async throws {
        let (api, config) = makeMockAPI()
        MockURLProtocol.registry.reset { request in
            if request.url?.host == "casa.test" { throw URLError(.cannotConnectToHost) }
            return MockReply.json(PreviewData.boardJSON(.tranquilo))
        }
        let payload = try await api.board(routeID: nil, logHistory: false)
        XCTAssertEqual(payload.board?.route?.id, 4)
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test", "ts.test"])
        XCTAssertEqual(config.preferredURL, "http://ts.test:7796")
        XCTAssertEqual(config.candidates, ["http://ts.test:7796", "http://casa.test:7796"])

        // La siguiente empieza por la que respondió.
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.boardJSON(.tranquilo)) }
        _ = try await api.board(routeID: nil, logHistory: false)
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["ts.test"])
    }

    /// R42: un error HTTP (el servidor contestó) NO prueba la otra dirección.
    @MainActor
    func testErrorHTTPNoSaltaDeDireccion() async {
        let (api, config) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in MockReply.error(.errorInterno) }
        let error = await captureError { _ = try await api.board(routeID: nil, logHistory: false) }
        XCTAssertEqual(error as? APIError,
                       .server(code: "internal", message: "error interno del servidor", status: 500, retryAfter: nil))
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test"])
        XCTAssertEqual(config.preferredURL, "http://casa.test:7796")    // contestó: es la buena
    }

    /// R42: fallo de red en las dos → `.network`, habiendo probado las dos.
    @MainActor
    func testFalloDeRedSalta() async {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in throw URLError(.timedOut) }
        let error = await captureError { _ = try await api.health() }
        guard case .network(let message)? = error as? APIError else {
            return XCTFail("tenía que ser un fallo de red: \(String(describing: error))")
        }
        XCTAssertTrue(message.contains("Tailscale"))
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test", "ts.test"])
    }

    /// Una respuesta que no se entiende tampoco salta de dirección.
    @MainActor
    func testRespuestaIlegible() async {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in (200, Data("<html>hola</html>".utf8), [:]) }
        let error = await captureError { _ = try await api.routes() }
        guard case .decoding? = error as? APIError else {
            return XCTFail("tenía que ser un error de decodificación")
        }
        XCTAssertEqual(MockURLProtocol.registry.hosts, ["casa.test"])
    }

    /// R43: 6 s por petición, 12 s en total, sin esperar a tener red y sin
    /// caché.
    func testConfiguracionDeSesion() {
        let c = TrajetAPI.makeSessionConfiguration()
        XCTAssertEqual(c.timeoutIntervalForRequest, 6)
        XCTAssertEqual(c.timeoutIntervalForResource, 12)
        XCTAssertFalse(c.waitsForConnectivity)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(c.urlCache)
    }

    /// El token va en `Authorization: Bearer`; sin token no se llama.
    @MainActor
    func testTokenBearerYSinToken() async throws {
        let (api, _) = makeMockAPI(token: "trj_prueba")
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.healthJSON(.conClave)) }
        _ = try await api.health()
        let request = try XCTUnwrap(MockURLProtocol.registry.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer trj_prueba")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.url?.path, "/api/v1/health")

        let (unpaired, _) = makeMockAPI(token: nil)
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.healthJSON(.conClave)) }
        let error = await captureError { _ = try await unpaired.health() }
        XCTAssertEqual(error as? APIError, .notPaired)
        XCTAssertTrue(MockURLProtocol.registry.requests.isEmpty)

        // El ping no necesita token.
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.pingJSON) }
        let ping = try await unpaired.ping()
        XCTAssertTrue(ping.isTrajet)
        XCTAssertNil(MockURLProtocol.registry.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    /// ETag guardado por URL, If-None-Match en la siguiente y 304 → lo guardado.
    @MainActor
    func testETagY304() async throws {
        let (api, _) = makeMockAPI()
        let etag = #"W/"abc123""#
        MockURLProtocol.registry.reset { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == etag {
                return MockReply.notModified(etag: etag)
            }
            return MockReply.json(PreviewData.boardJSON(.unTramo), headers: ["ETag": etag])
        }
        let first = try await api.board(routeID: 5, logHistory: false)
        let second = try await api.board(routeID: 5, logHistory: false)
        let requests = MockURLProtocol.registry.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), etag)
        XCTAssertEqual(second.board?.legs, first.board?.legs)
        XCTAssertEqual(second.board?.route, first.board?.route)

        // Olvidar los ETag: la siguiente va sin If-None-Match.
        await api.clearETags()
        _ = try await api.board(routeID: 5, logHistory: false)
        XCTAssertNil(MockURLProtocol.registry.requests.last?.value(forHTTPHeaderField: "If-None-Match"))
    }

    /// El mapa con ETag de fuera (MapStore): 304 → `.notModified`.
    @MainActor
    func testMapaCondicional() async throws {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "W/\"m1\"" { return MockReply.notModified(etag: "W/\"m1\"") }
            return MockReply.json(PreviewData.routeMapJSON(), headers: ["ETag": "W/\"m1\""])
        }
        guard case .modified(let map, let etag, _) = try await api.routeMap(routeID: 5, etag: nil) else {
            return XCTFail("tenía que traer el mapa")
        }
        XCTAssertEqual(map.lines.count, 1)
        XCTAssertEqual(etag, "W/\"m1\"")
        guard case .notModified = try await api.routeMap(routeID: 5, etag: etag) else {
            return XCTFail("tenía que ser 304")
        }
        XCTAssertEqual(MockURLProtocol.registry.requests.last?.url?.path, "/api/v1/routes/5/map")
    }

    /// Errores con código del contrato → enumerado.
    @MainActor
    func testErroresConCodigo() async {
        let (api, _) = makeMockAPI()

        MockURLProtocol.registry.reset { _ in MockReply.error(.sinClave) }
        var error = await captureError { _ = try await api.board(routeID: nil, logHistory: true) } as? APIError
        XCTAssertEqual(error?.serverCode, .primKeyMissing)
        XCTAssertEqual(BoardStore.designedIssue(for: error ?? .notPaired), .noKey)

        MockURLProtocol.registry.reset { _ in MockReply.error(.cuotaAgotada) }
        error = await captureError { _ = try await api.board(routeID: nil, logHistory: true) } as? APIError
        XCTAssertEqual(error?.retryAfter, 3600)
        XCTAssertEqual(error?.serverCode, .primQuotaExhausted)

        MockURLProtocol.registry.reset { _ in MockReply.error(.primCaido) }
        error = await captureError { _ = try await api.board(routeID: nil, logHistory: true) } as? APIError
        XCTAssertEqual(error?.serverCode, .primUnreachable)

        MockURLProtocol.registry.reset { _ in MockReply.error(.noEmparejado) }
        error = await captureError { _ = try await api.routes() } as? APIError
        XCTAssertEqual(error, .unauthorized)
        XCTAssertTrue(error?.needsPairing ?? false)

        MockURLProtocol.registry.reset { _ in MockReply.error(.rutaNoEncontrada) }
        error = await captureError { _ = try await api.route(id: 99) } as? APIError
        XCTAssertEqual(error, .notFound)

        MockURLProtocol.registry.reset { _ in MockReply.error(.codigoNoValido) }
        error = await captureError {
            _ = try await api.pair(PairRequest(code: "ABCD-EFGH", deviceName: "iPhone"), baseURL: "http://casa.test:7796")
        } as? APIError
        XCTAssertEqual(error?.serverCode, .pairingInvalid)

        // Retry-After de la cabecera si el cuerpo no lo trae.
        MockURLProtocol.registry.reset { _ in
            MockReply.json(#"{"error": {"code": "rate_limited", "message": "espera"}}"#, status: 429,
                           headers: ["Retry-After": "42"])
        }
        error = await captureError {
            _ = try await api.pair(PairRequest(code: "ABCD-EFGH", deviceName: "iPhone"), baseURL: "http://casa.test:7796")
        } as? APIError
        XCTAssertEqual(error?.retryAfter, 42)

        // 502 sin sobre: código vacío y el texto de siempre.
        MockURLProtocol.registry.reset { _ in (502, Data("Bad Gateway".utf8), [:]) }
        error = await captureError { _ = try await api.stats() } as? APIError
        XCTAssertEqual(error, .server(code: "", message: "", status: 502, retryAfter: nil))
        XCTAssertEqual(error?.errorDescription, "El servidor ha respondido 502.")
    }

    /// R40 y R37: `route_id` solo si hay ruta fijada; `log_history=false` en
    /// los refrescos automáticos.
    @MainActor
    func testParametrosDelTablero() async throws {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.boardJSON(.tranquilo)) }
        _ = try await api.board(routeID: 7, logHistory: false)
        _ = try await api.board(routeID: nil, logHistory: true)
        let requests = MockURLProtocol.registry.requests
        XCTAssertEqual(requests[0].queryValue("route_id"), "7")
        XCTAssertEqual(requests[0].queryValue("log_history"), "false")
        XCTAssertNil(requests[1].queryValue("route_id"))
        XCTAssertNil(requests[1].queryValue("log_history"))
    }

    /// R34: la API solo entiende `arrival` y `departure`.
    @MainActor
    func testPlanModoArrivalDeparture() async throws {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.planJSON) }
        _ = try await api.plan(from: "stop_area:IDFM:65063", to: "2.3;48.8", when: "09:00", mode: .arrival)
        _ = try await api.plan(from: "a+b", to: "c", when: nil, mode: .window)
        let requests = MockURLProtocol.registry.requests
        XCTAssertEqual(requests[0].queryValue("mode"), "arrival")
        XCTAssertEqual(requests[0].queryValue("when"), "09:00")
        XCTAssertEqual(requests[1].queryValue("mode"), "departure")
        XCTAssertNil(requests[1].queryValue("when"))
        // El «+» viaja escapado: el servidor no lo lee como un espacio.
        XCTAssertTrue(requests[1].url?.absoluteString.contains("from=a%2Bb") ?? false)
    }

    /// Cuerpos en snake_case y métodos de cada operación.
    @MainActor
    func testOperacionesDeRutas() async throws {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v1/routes"): return MockReply.json(PreviewData.routeSavedJSON, status: 201)
            case ("PUT", "/api/v1/routes/5"): return MockReply.json(PreviewData.routeSavedJSON)
            case ("DELETE", "/api/v1/routes/5"): return MockReply.json(PreviewData.routeDeletedJSON)
            case ("POST", "/api/v1/routes/from-plan"): return MockReply.json(PreviewData.planSavedWithoutDirectionJSON, status: 201)
            case ("GET", "/api/v1/stops/stop_area:IDFM:71370/lines"): return MockReply.json(PreviewData.stopLinesJSON)
            case ("GET", "/api/v1/stops/stop_area:IDFM:71370/directions"): return MockReply.json(PreviewData.directionsJSON)
            case ("GET", "/api/v1/search/stops"): return MockReply.json(PreviewData.stopSearchJSON)
            case ("GET", "/api/v1/search/places"): return MockReply.json(PreviewData.placeSearchJSON)
            case ("DELETE", "/api/v1/devices/me"): return MockReply.json(PreviewData.unpairJSON)
            case ("GET", "/api/v1/devices/me"): return MockReply.json(PreviewData.deviceJSON)
            default: return MockReply.error(.rutaNoEncontrada)
            }
        }
        let draft = RouteDraft(PreviewData.routes[2])
        let created = try await api.createRoute(draft)
        XCTAssertEqual(created.id, 5)
        let body = try XCTUnwrap(MockURLProtocol.registry.requests.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["time_mode"] as? String, "departure")
        XCTAssertEqual(json["origin_id"] as? String, "stop_area:IDFM:71370")
        XCTAssertNotNil(json["legs"] as? [[String: Any]])

        _ = try await api.updateRoute(id: 5, draft)
        let deleted = try await api.deleteRoute(id: 5)
        XCTAssertEqual(deleted, 5)
        let option = try XCTUnwrap(PreviewData.planOptions.first)
        let saved = try await api.routeFromPlan(PlanSaveRequest(option: option, meta: .init(
            name: "Casa", originId: "a", originName: "A", destId: "b", destName: "B", timeAt: "09:00")))
        XCTAssertEqual(saved.withoutDirection, ["13"])
        let lines = try await api.stopLines(stopID: "stop_area:IDFM:71370")
        XCTAssertEqual(lines.first?.code, "14")
        let dirs = try await api.stopDirections(stopID: "stop_area:IDFM:71370", lineID: "line:IDFM:C01739")
        XCTAssertEqual(dirs.first, "Ermont - Eaubonne")
        let stops = try await api.searchStops("lazare")
        XCTAssertEqual(stops.count, 2)
        let places = try await api.searchPlaces("lazare")
        XCTAssertEqual(places.count, 3)
        let me = try await api.me()
        XCTAssertEqual(me.id, 3)
        let revoked = try await api.unpair()
        XCTAssertTrue(revoked)
    }
}
