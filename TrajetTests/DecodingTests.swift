import CoreLocation
import XCTest
@testable import Trajet

/// Decodificación de los bancos de prueba y de JSON raros (R13, R21, R22) y
/// reglas que viven en los modelos (R3, R17, R19, R24).
final class DecodingTests: XCTestCase {

    // MARK: - R13: todos los PreviewData decodifican

    func testTodosLosPreviewData() {
        let catalog = PreviewData.catalog
        XCTAssertGreaterThan(catalog.count, 50)
        for sample in catalog {
            XCTAssertNoThrow(try sample.check(Data(sample.json.utf8)), sample.name)
        }
    }

    func testPreviewDataCubreLosCasos() {
        XCTAssertEqual(PreviewData.board(.cincoTramos).legs.count, 5)
        XCTAssertEqual(PreviewData.board(.seisTramos).legs.count, 6)
        XCTAssertEqual(PreviewData.board(.unTramo).legs.count, 1)

        // Bus a 106 y 165 min (R6).
        let bus = PreviewData.board(.bus106).legs[0].departures.map(\.minutes)
        XCTAssertTrue(bus.contains(106))
        XCTAssertTrue(bus.contains(165))
        XCTAssertTrue(bus.contains(60))

        // Vía que aparece (R2) y solo probable (R10).
        let appears = PreviewData.board(.viaAparece).legs[0].departures[0]
        XCTAssertTrue(appears.platformNew)
        XCTAssertEqual(appears.platform, "21")
        let probable = PreviewData.board(.viaProbable).legs[0].departures
        XCTAssertTrue(probable.allSatisfy { $0.platform == nil && $0.guess != nil })
        XCTAssertEqual(Set(probable.compactMap { $0.guess?.basis }), ["mision", "hora", "linea"])

        // En el andén ≠ ya (R15).
        let atStop = PreviewData.board(.enAnden).legs[0].departures[0]
        XCTAssertTrue(atStop.atStop)
        XCTAssertEqual(atStop.minutes, 0)

        // Destinos mezclados (R24).
        XCTAssertTrue(PreviewData.board(.destinosMezclados).legs[0].mixesDestinations)

        // Tramo vacío con la línea normal (R25) y línea cortada sin salidas.
        let empty = PreviewData.board(.tramoVacio).legs[0]
        XCTAssertTrue(empty.departures.isEmpty)
        XCTAssertEqual(empty.status.level, 0)
        let cut = PreviewData.board(.lineaCortada)
        XCTAssertTrue(cut.legs[0].status.isInterrupted)
        XCTAssertTrue(cut.legs[0].departures.isEmpty)
        XCTAssertFalse(cut.legs[0].status.awaitingTranslation)

        // Cuota justa: el servidor pide 120 s.
        let quota = PreviewData.board(.cuotaJusta)
        XCTAssertEqual(quota.server?.refreshHintS, 120)
        XCTAssertEqual(quota.server?.quotaLevel, .critical)
        XCTAssertEqual(quota.refreshInterval, 120)

        // Viejo.
        XCTAssertTrue(PreviewData.board(.viejo).stale)
        XCTAssertEqual(PreviewData.board(.viejo).server?.degraded, true)

        // Colores raros (R57): llegan tal cual; LineColor decide.
        XCTAssertEqual(PreviewData.board(.coloresRaros).legs.map(\.lineColor), ["", "F90", "#82C8E6", "ZZZZZZ"])

        // Transbordo.
        let transfer = PreviewData.board(.transbordo)
        XCTAssertEqual(transfer.legs.count, 2)
        XCTAssertNotEqual(transfer.legs[0].toId, transfer.legs[1].fromId)

        // Casos límite.
        let edge = PreviewData.board(.casosLimite)
        XCTAssertFalse(edge.disruptionsOK)
        XCTAssertEqual(edge.errors.count, 5)
        XCTAssertEqual(edge.legs[0].departures[0].delay, -1)
        XCTAssertEqual(edge.legs[0].departures[0].realDelay, -1)
        XCTAssertNil(edge.legs[0].departures[1].realDelay)          // 0 no se pinta (R14)
        XCTAssertTrue(edge.legs[1].status.awaitingTranslation)       // uno sin traducir (R8)
        XCTAssertEqual(edge.legs[1].status.visibleMessages[0], "Tráfico perturbado entre Invalides y Montparnasse.")
        XCTAssertEqual(edge.legs[1].status.visibleMessages[1], "Station Liège fermée jusqu'à nouvel ordre.")
        XCTAssertEqual(edge.legs[2].status.planned, 2)
        XCTAssertFalse(edge.legs[2].status.isDisrupted)               // obras futuras (R28)
        XCTAssertFalse(edge.legs[2].mixesDestinations)                // un solo destino (R24)
        XCTAssertTrue(edge.legs[3].stationFailed)
    }

    func testCamposV1DelTablero() {
        let board = PreviewData.board(.tranquilo)
        XCTAssertEqual(board.route?.id, 4)
        XCTAssertFalse(board.autoSelected)
        XCTAssertTrue(board.disruptionsOK)
        XCTAssertEqual(board.server, ServerState.normal)
        let metro = board.legs[0]
        let train = board.legs[1]
        XCTAssertEqual(train.fromId, "stop_area:IDFM:71370")
        XCTAssertEqual(train.toId, "stop_area:IDFM:65063")
        XCTAssertEqual(train.platformExpected, true)
        XCTAssertTrue(train.showsPlatform)
        XCTAssertEqual(metro.platformExpected, false)
        XCTAssertFalse(metro.showsPlatform)
        XCTAssertEqual(train.departures[0].train, "137412")
        XCTAssertEqual(train.departures[0].length, .long)
        XCTAssertEqual(train.departures[1].guess?.percent, 90)
    }

    func testTableroVacio() {
        guard case .empty(let message, let server) = PreviewData.emptyPayload else {
            return XCTFail("tenía que ser el tablero vacío")
        }
        XCTAssertEqual(message, "todavía no hay rutas guardadas")
        XCTAssertEqual(server?.refreshHintS, 30)
        XCTAssertNil(PreviewData.emptyPayload.board)
        XCTAssertNotNil(PreviewData.payload(.cincoTramos).board)
    }

    // MARK: - R21: un JSON raro degrada, no revienta

    func testCamposAusentesNulosOTipoErroneo() throws {
        let empty = try decode(Board.self, PreviewData.oddJSON(.objetoVacio))
        XCTAssertTrue(empty.legs.isEmpty)
        XCTAssertNil(empty.route)
        XCTAssertTrue(empty.disruptionsOK)
        XCTAssertNil(empty.server)

        let odd = try decode(Board.self, PreviewData.oddJSON(.tiposCambiados))
        XCTAssertEqual(odd.legs.count, 1)
        XCTAssertEqual(odd.route?.id, 0)
        XCTAssertEqual(odd.legs[0].seq, 0)
        XCTAssertEqual(odd.legs[0].lineCode, "")
        XCTAssertEqual(odd.legs[0].directions, [])
        XCTAssertEqual(odd.legs[0].status.level, 0)
        XCTAssertNil(odd.legs[0].age)
        XCTAssertNil(odd.legs[0].platformExpected)
        let dep = odd.legs[0].departures[0]
        XCTAssertEqual(dep.minutes, 0)            // "6" no es un número: reserva
        XCTAssertNil(dep.platform)
        XCTAssertFalse(dep.platformNew)
        XCTAssertNil(dep.delay)
        XCTAssertNil(dep.length)
        XCTAssertFalse(odd.stale)
        XCTAssertEqual(odd.dataAge, 0)
        XCTAssertEqual(odd.quota, [:])
        XCTAssertNil(odd.server)
        XCTAssertTrue(odd.disruptionsOK)

        // Un tablero que no es un objeto sí falla (no hay nada que enseñar).
        XCTAssertThrowsError(try decode(BoardPayload.self, "[1, 2]"))
    }

    func testEnumeradosDesconocidos() throws {
        let state = try decode(ServerState.self, PreviewData.oddJSON(.enumsDesconocidos))
        XCTAssertEqual(state.primKey, .unknown)
        XCTAssertEqual(state.quotaLevel, .ok)
        XCTAssertEqual(state.refreshHintS, 30)
        XCTAssertFalse(state.degraded)
        XCTAssertEqual(state.refreshInterval, 30)
    }

    func testRutaRara() throws {
        let route = try decode(SavedRoute.self, PreviewData.oddJSON(.rutaRara))
        XCTAssertEqual(route.timeMode, .window)
        XCTAssertEqual(route.timeFrom, "07:00")
        XCTAssertEqual(route.legs.map(\.lineCode), ["B", "A"])     // ordenados por seq
        XCTAssertEqual(route.daysLabel, "todos los días")
    }

    func testTableroSinServidorNiRuta() throws {
        let board = try decode(Board.self, PreviewData.oddJSON(.tableroSinRuta))
        XCTAssertNil(board.route)
        XCTAssertNil(board.server)
        XCTAssertTrue(board.disruptionsOK)
        XCTAssertEqual(board.refreshInterval, 30)
    }

    func testPlanVacioYMapaMinimo() throws {
        XCTAssertTrue(try decode(PlanResponse.self, PreviewData.oddJSON(.planVacio)).options.isEmpty)
        let map = try decode(RouteMap.self, PreviewData.oddJSON(.mapaMinimo))
        XCTAssertEqual(map.routeId, 1)
        XCTAssertEqual(map.lines.first?.mode, .other)
        XCTAssertNil(map.lines.first?.path)
        XCTAssertTrue(map.lines.first?.isStraightLine ?? false)
    }

    // MARK: - R22: formatos cambiantes

    func testTrenNumeroOCadena() throws {
        let board = try decode(Board.self, PreviewData.oddJSON(.trenNumero))
        XCTAssertEqual(board.legs[0].departures.map(\.train), ["135711", "135713"])
    }

    func testAgeLegadoComoDataAge() throws {
        let board = try decode(Board.self, PreviewData.oddJSON(.ageAntiguo))
        XCTAssertEqual(board.dataAge, 12)
    }

    // MARK: - Errores

    func testErrorV1YLegado() throws {
        let quota = PreviewData.error(.cuotaAgotada)
        XCTAssertEqual(quota.code, "prim_quota_exhausted")
        XCTAssertEqual(quota.retryAfter, 3600)
        XCTAssertEqual(quota.knownCode, .primQuotaExhausted)
        XCTAssertEqual(PreviewData.error(.sinClave).knownCode, .primKeyMissing)

        let legacy = try XCTUnwrap(APIErrorBody.parse(Data(PreviewData.oddJSON(.errorLegado).utf8)))
        XCTAssertEqual(legacy.code, "")
        XCTAssertEqual(legacy.message, "ruta no encontrada")
        XCTAssertNil(APIErrorBody.parse(Data("<html>Bad Gateway</html>".utf8)))
    }

    // MARK: - Salud, emparejamiento, rutas, estadísticas

    func testSalud() {
        let ok = PreviewData.health(.conClave)
        XCTAssertTrue(ok.hasWorkingKey)
        XCTAssertEqual(ok.prim.keySource, .panel)
        XCTAssertEqual(ok.quota.endpoints.map(\.label), ["Tablero", "Avisos", "Buscador"])
        XCTAssertEqual(ok.quota.endpoint("stop-monitoring")?.remaining, 682)
        XCTAssertNotNil(ok.quota.resetsAtDate)
        XCTAssertTrue(ok.translator.ok)
        XCTAssertEqual(ok.platformModel.percentLabel, "84 %")

        let noKey = PreviewData.health(.sinClave)
        XCTAssertEqual(noKey.prim.keyState, .missing)
        XCTAssertFalse(noKey.prim.hasKey)
        XCTAssertFalse(noKey.translator.ok)
        XCTAssertEqual(noKey.platformModel.percentLabel, "—")      // R11

        XCTAssertEqual(PreviewData.health(.cuotaJusta).quota.refreshHintS, 120)
        XCTAssertFalse(PreviewData.health(.traductorCaido).translator.ok)
    }

    func testEmparejamiento() {
        XCTAssertTrue(PreviewData.ping.isTrajet)
        XCTAssertFalse(PreviewData.ping.paired)
        let result = PreviewData.pairResult
        XCTAssertTrue(result.token.hasPrefix("trj_"))
        XCTAssertEqual(result.token.count, 4 + 43)
        XCTAssertEqual(result.server.url(.lan), "http://192.168.1.10:7796")
        XCTAssertEqual(result.server.url(.tailscale), "http://100.64.0.10:7796")
        XCTAssertEqual(result.device.name, "iPhone de Isma")
    }

    func testPairRequestSnakeCase() throws {
        let body = PairRequest(code: "ABCD-EFGH", deviceName: "iPhone", deviceModel: "iPhone17,1", appVersion: "")
        let json = try XCTUnwrap(String(data: JSONEncoder.trajet.encode(body), encoding: .utf8))
        XCTAssertTrue(json.contains("\"device_name\""))
        XCTAssertTrue(json.contains("\"device_model\""))
        XCTAssertFalse(json.contains("app_version"))                 // vacío: no se manda
    }

    func testRutasYEtiquetas() {
        let routes = PreviewData.routes
        XCTAssertEqual(routes.map(\.id), [3, 4, 5, 6])
        XCTAssertEqual(PreviewData.routesResponse.activeId, 3)
        XCTAssertEqual(routes[0].legs.count, 5)
        XCTAssertEqual(routes[0].scheduleLabel, "llego 09:00")     // R35
        XCTAssertEqual(routes[0].daysLabel, "entre semana")        // R36
        XCTAssertEqual(routes[1].daysLabel, "todos los días")
        XCTAssertEqual(routes[1].scheduleLabel, "17:00–20:00")
        XCTAssertEqual(routes[2].daysLabel, "fin de semana")
        XCTAssertEqual(routes[2].scheduleLabel, "salgo 10:30")
        XCTAssertEqual(routes[3].daysLabel, "M J")
        XCTAssertEqual(routes[0].legsWithoutDirection.map(\.lineCode), ["13"])
    }

    func testRouteDraftSnakeCase() throws {
        let draft = RouteDraft(PreviewData.routes[0])
        let json = try XCTUnwrap(String(data: JSONEncoder.trajet.encode(draft), encoding: .utf8))
        XCTAssertTrue(json.contains("\"time_mode\":\"arrival\""))
        XCTAssertTrue(json.contains("\"origin_id\""))
        XCTAssertTrue(json.contains("\"from_id\""))
        XCTAssertEqual(draft.legs.count, 5)
    }

    func testAlternativasYPlan() {
        let alt = PreviewData.alternatives
        XCTAssertTrue(alt.needed)
        XCTAssertFalse(alt.options[1].usable)
        XCTAssertEqual(alt.options[0].deltaLabel, "+12 min")
        XCTAssertEqual(alt.options[0].departureTime, "12:55")
        XCTAssertEqual(alt.options[0].arrivalTime, "13:54")
        let deltas: AlternativesResponse = PreviewData.decode(PreviewData.alternativesDeltasJSON)
        XCTAssertEqual(deltas.options.map { $0.deltaLabel ?? "nil" }, ["igual de rápido", "-3 min"])
        let short: AlternativesResponse = PreviewData.decode(PreviewData.alternativesNotNeededJSON)
        XCTAssertFalse(short.needed)
        XCTAssertTrue(short.options.isEmpty)
        XCTAssertEqual(PreviewData.planOptions.map(\.transfersLabel), ["1 transbordo", "directo", "2 transbordos"])
        let saved: PlanSaveResponse = PreviewData.decode(PreviewData.planSavedWithoutDirectionJSON)
        XCTAssertEqual(saved.withoutDirection, ["13"])                // R33
        XCTAssertEqual(saved.route?.id, 5)
    }

    func testEstadisticas() {
        let stats = PreviewData.stats
        XCTAssertEqual(stats.byMonth[1].monthLabel, "agosto 2026")
        XCTAssertNil(stats.byMonth[2].avgDelay)
        XCTAssertEqual(stats.overall.maxDelay, 27)
        let model = PreviewData.platformModel
        XCTAssertEqual(model.accuracy.percentLabel, "84 %")
        XCTAssertEqual(model.routeId, 3)
        XCTAssertEqual(model.routeName, "Casa → Trabajo")
        XCTAssertTrue(model.collector.enabled)
        let noData: PlatformModelResponse = PreviewData.decode(PreviewData.platformModelNoDataJSON)
        XCTAssertEqual(noData.accuracy.percentLabel, "—")
        XCTAssertNil(noData.routeId)
    }

    // MARK: - Mapa

    func testMapaDeLaJ() {
        let map = PreviewData.routeMap
        XCTAssertEqual(map.routeId, 5)
        XCTAssertFalse(map.pending)
        XCTAssertEqual(map.lines.count, 1)
        let line = map.lines[0]
        XCTAssertEqual(line.code, "J")
        XCTAssertEqual(line.mode, .rail)
        XCTAssertEqual(line.via.count, 4)
        XCTAssertEqual(line.coordinates(fine: false).count, 6)
        XCTAssertEqual(line.coordinates(fine: true).count, 18)
        XCTAssertFalse(line.isStraightLine)
        XCTAssertEqual(map.stations.map(\.role), [.origin, .destination])
        XCTAssertNotNil(map.station(zdc: "71370")?.track("21"))
        XCTAssertEqual(map.accesses(zdc: "71370").count, 2)
        XCTAssertEqual(map.accesses(zdc: "65063").first?.toStop.first?.s, 59)
        XCTAssertNil(map.accesses(zdc: "71370")[1].toStop[0].m)

        let pending: RouteMap = PreviewData.decode(PreviewData.routeMapPendingJSON)
        XCTAssertTrue(pending.pending)
        XCTAssertEqual(pending.lines[0].coordinates().count, 2)       // recta entre paradas
    }

    // MARK: - Reglas de los modelos

    /// R3: solo tren, RER y TER publican vía (reserva si falta platform_expected).
    func testModosConYSinVia() {
        XCTAssertFalse(TransportMode(rawMode: "Métro").publishesPlatform)
        XCTAssertFalse(TransportMode(rawMode: "Bus").publishesPlatform)
        XCTAssertFalse(TransportMode(rawMode: "Tramway").publishesPlatform)
        XCTAssertFalse(TransportMode(rawMode: "Funiculaire").publishesPlatform)
        XCTAssertTrue(TransportMode(rawMode: "RER").publishesPlatform)
        XCTAssertTrue(TransportMode(rawMode: "Train Transilien").publishesPlatform)
        XCTAssertTrue(TransportMode(rawMode: "TER").publishesPlatform)
        XCTAssertTrue(TransportMode(rawMode: "Train").publishesPlatform)
        XCTAssertEqual(TransportMode(rawMode: "Tram-train"), .tram)
        XCTAssertEqual(TransportMode(rawMode: "Autocar"), .bus)
        // «Interurbain» contiene «ter» pero no es un TER.
        XCTAssertFalse(TransportMode(rawMode: "Interurbain").publishesPlatform)

        // El servidor manda sobre el modo.
        var leg = PreviewData.board(.tranquilo).legs[0]
        leg.platformExpected = true
        XCTAssertTrue(leg.showsPlatform)
        leg.platformExpected = nil
        XCTAssertFalse(leg.showsPlatform)
    }

    /// R23: identidad estable.
    func testIdEstable() {
        var d = PreviewData.board(.unTramo).legs[0].departures[0]
        let id = d.id
        d.minutes = 3
        XCTAssertEqual(d.id, id)
        let anonymous = Departure(minutes: 4, at: "12:54", destination: "Ermont")
        XCTAssertEqual(anonymous.id, "12:54|Ermont|4")
    }

    /// R17 y R19 en el modelo.
    func testAntiguedadYDatoViejo() {
        let t0 = Date(timeIntervalSinceReferenceDate: 780_000_000)
        var board = PreviewData.board(.tranquilo)
        board.receivedAt = t0
        XCTAssertEqual(board.ageSeconds(now: t0.addingTimeInterval(60)), 66, accuracy: 0.001)
        XCTAssertFalse(board.isStale(now: t0.addingTimeInterval(90)))
        XCTAssertTrue(board.isStale(now: t0.addingTimeInterval(91)))
        board.dataAge = 300                                       // no apaga (R19)
        XCTAssertFalse(board.isStale(now: t0))
        board.stale = true
        XCTAssertTrue(board.isStale(now: t0))
    }

    func testHoraDeParisAFecha() throws {
        // 24/09/2026 10:50 UTC = 12:50 en París (CEST).
        let ref = try XCTUnwrap(ISO8601Parsing.date("2026-09-24T10:50:00+00:00"))
        let date = try XCTUnwrap(Departure.parisDate("12:56", near: ref))
        XCTAssertEqual(date.timeIntervalSince(ref), 6 * 60, accuracy: 0.5)
        // Un «00:10» visto a las 23:55 es de mañana.
        let late = try XCTUnwrap(ISO8601Parsing.date("2026-09-24T21:55:00+00:00"))
        let next = try XCTUnwrap(Departure.parisDate("00:10", near: late))
        XCTAssertEqual(next.timeIntervalSince(late), 15 * 60, accuracy: 0.5)
        XCTAssertNil(Departure.parisDate("25:99", near: ref))
    }

    func testCodificarYDecodificarConservaLoDeV1() throws {
        let original = PreviewData.board(.casosLimite)
        let data = try JSONEncoder.trajet.encode(original)
        let back = try JSONDecoder.trajet.decode(Board.self, from: data)
        XCTAssertEqual(back.legs, original.legs)
        XCTAssertEqual(back.server, original.server)
        XCTAssertEqual(back.disruptionsOK, false)
        XCTAssertEqual(back.errors, original.errors)
        XCTAssertEqual(back.route, original.route)
    }

    func testEnlacesTrajet() throws {
        let url = try XCTUnwrap(URL(string: "trajet://ruta/5?tramo=1&salida=j2"))
        XCTAssertEqual(AppLink(url: url), .route(id: 5, legSeq: 1, departureJID: "j2"))
        XCTAssertEqual(AppLink(url: try XCTUnwrap(URL(string: "trajet://route/7"))),
                       .route(id: 7, legSeq: nil, departureJID: nil))
        XCTAssertEqual(AppLink(url: try XCTUnwrap(URL(string: "trajet://ruta/5/alternativas"))), .alternatives(routeID: 5))
        XCTAssertEqual(AppLink(url: try XCTUnwrap(URL(string: "trajet://tablero"))), .board)
        XCTAssertEqual(AppLink(url: try XCTUnwrap(URL(string: "trajet://ajustes/servidor"))), .serverSettings)
        XCTAssertNil(AppLink(url: try XCTUnwrap(URL(string: "https://ruta/5"))))
        XCTAssertNil(AppLink(url: try XCTUnwrap(URL(string: "trajet://ruta/abc"))))
        let pair = try XCTUnwrap(URL(string: PreviewData.pairingLink))
        XCTAssertEqual(AppLink(url: pair), .pair(pair))
        // Ida y vuelta.
        for link in [AppLink.route(id: 5, legSeq: 2, departureJID: "a b"), .alternatives(routeID: 3),
                     .board, .settings, .serverSettings] {
            XCTAssertEqual(AppLink(url: link.url), link)
        }
    }

    // MARK: - Ayuda

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.trajet.decode(T.self, from: Data(json.utf8))
    }
}
