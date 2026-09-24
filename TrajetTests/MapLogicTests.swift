import XCTest
@testable import Trajet

/// Las reglas del mapa y del modo trayecto que no necesitan vista: polilínea
/// según el zoom, llegada por distancia, estaciones vigiladas por defecto,
/// geometría del mapa (trazado, rectas, paradas, transbordos), camino a pie,
/// aviso discreto, vía en el mapa, la tarjeta del trayecto y el `staleDate`
/// de la Live Activity.
final class MapLogicTests: XCTestCase {

    // MARK: - Polilínea según el zoom

    /// De cerca la fina (2 m), de lejos la gruesa (20 m), con un margen para
    /// no parpadear en el umbral.
    func testPolilineaSegunDistanciaDeLaCamara() {
        let threshold = RouteMapDetail.fineBelowDistance
        XCTAssertTrue(RouteMapDetail.useFine(cameraDistance: 1_500, current: false))
        XCTAssertFalse(RouteMapDetail.useFine(cameraDistance: 40_000, current: true))
        // En el margen se queda como estaba.
        XCTAssertTrue(RouteMapDetail.useFine(cameraDistance: threshold * 1.05, current: true))
        XCTAssertFalse(RouteMapDetail.useFine(cameraDistance: threshold * 0.95, current: false))
        // Distancias sin sentido no cambian nada.
        XCTAssertTrue(RouteMapDetail.useFine(cameraDistance: .nan, current: true))
        XCTAssertFalse(RouteMapDetail.useFine(cameraDistance: -1, current: false))
    }

    // MARK: - Llegada por distancia

    func testLlegadaPorDistancia() {
        let destination = TripFixtures.argenteuil
        let now = Date()
        let near = TripLocation(point: TripFixtures.nearArgenteuil, horizontalAccuracy: 40, timestamp: now)
        let outside = TripLocation(point: TripFixtures.outsideArgenteuil, horizontalAccuracy: 40, timestamp: now)
        let vague = TripLocation(point: TripFixtures.nearArgenteuil, horizontalAccuracy: 800, timestamp: now)
        XCTAssertTrue(TripGeometry.hasArrived(near, destination: destination))
        XCTAssertFalse(TripGeometry.hasArrived(outside, destination: destination))
        XCTAssertFalse(TripGeometry.hasArrived(vague, destination: destination))
        XCTAssertEqual(TripFixtures.nearArgenteuil.distance(to: destination), 99, accuracy: 15)
        XCTAssertEqual(TripFixtures.outsideArgenteuil.distance(to: destination), 300, accuracy: 15)
    }

    /// El destino es la estación con papel «destino»; sin estaciones (mapa
    /// calculándose), la bajada del último tramo.
    func testDestinoDelMapa() throws {
        let destination = try XCTUnwrap(TripGeometry.destination(in: TripFixtures.map4))
        XCTAssertEqual(destination, TripFixtures.argenteuil)

        let pending: RouteMap = PreviewData.decode(PreviewData.routeMapPendingJSON)
        let fallback = try XCTUnwrap(TripGeometry.destination(in: pending))
        XCTAssertEqual(fallback.latitude, 48.946797, accuracy: 0.000001)
        XCTAssertNil(TripGeometry.destination(in: nil))
    }

    func testPosicionUtil() {
        let now = Date()
        XCTAssertTrue(TripGeometry.isUsable(TripLocation(point: TripFixtures.saintLazare, horizontalAccuracy: 65,
                                                         timestamp: now), now: now))
        XCTAssertFalse(TripGeometry.isUsable(TripLocation(point: TripFixtures.saintLazare, horizontalAccuracy: -1,
                                                          timestamp: now), now: now))
        XCTAssertFalse(TripGeometry.isUsable(TripLocation(point: TripFixtures.saintLazare, horizontalAccuracy: 65,
                                                          timestamp: now.addingTimeInterval(-300)), now: now))
        XCTAssertFalse(TripGeometry.isUsable(TripLocation(point: GeoPoint(latitude: 0, longitude: 0),
                                                          horizontalAccuracy: 10, timestamp: now), now: now))
    }

    // MARK: - Estaciones vigiladas por defecto

    /// Por defecto, la estación de origen (subida del primer tramo) de cada
    /// ruta guardada.
    func testEstacionesVigiladasPorDefecto() {
        let ids = TripSettings.defaultStationIDs(for: PreviewData.routes)
        XCTAssertEqual(ids, ["stop_area:IDFM:420512", "stop_area:IDFM:70604",
                             "stop_area:IDFM:71370", "stop_area:IDFM:474151"])
        XCTAssertEqual(TripSettings.zdc(of: "stop_area:IDFM:71370"), "71370")
        XCTAssertEqual(TripSettings.zdc(of: "71370"), "71370")
    }

    /// Mientras no se toquen son las de por defecto; al tocarlas, las del
    /// usuario, guardadas.
    @MainActor
    func testAjustesDelTrayectoSeGuardan() {
        let defaults = makeTestDefaults()
        let settings = TripSettings(defaults: defaults)
        XCTAssertEqual(settings.maxMinutes, 90)
        XCTAssertFalse(settings.geofencesEnabled)
        XCTAssertTrue(settings.watchedStationIDs.isEmpty)

        settings.refreshDefaultStations(from: PreviewData.routes)
        XCTAssertTrue(settings.usesDefaultStations)
        XCTAssertEqual(settings.watchedStationIDs.count, 4)

        settings.watchedStationIDs = ["stop_area:IDFM:71370"]
        settings.maxMinutes = 1_000                          // se acota
        settings.geofencesEnabled = true

        let again = TripSettings(defaults: defaults)
        XCTAssertEqual(again.watchedStationIDs, ["stop_area:IDFM:71370"])
        XCTAssertFalse(again.usesDefaultStations)
        XCTAssertEqual(again.maxMinutes, TripSettings.maxMinutesRange.upperBound)
        XCTAssertTrue(again.geofencesEnabled)

        again.resetWatchedStations()
        XCTAssertTrue(again.usesDefaultStations)
        XCTAssertEqual(again.watchedStationIDs.count, 4)
    }

    // MARK: - Geometría del mapa

    /// El mapa de la J con trazado: una línea de verdad (gruesa y fina),
    /// subida y bajada, y las cuatro paradas de paso.
    func testGeometriaConTrazado() throws {
        let geometry = RouteMapGeometry(map: PreviewData.routeMap)
        XCTAssertEqual(geometry.tracedLines.count, 1)
        XCTAssertTrue(geometry.straightLines.isEmpty)
        let line = try XCTUnwrap(geometry.tracedLines.first)
        XCTAssertGreaterThanOrEqual(line.coarse.count, 2)
        XCTAssertGreaterThanOrEqual(line.fine.count, line.coarse.count)
        XCTAssertEqual(geometry.stops.map(\.role), [.origin, .destination])
        XCTAssertEqual(geometry.dots.count, 4)
        XCTAssertFalse(geometry.points.isEmpty)
        XCTAssertNotNil(RouteMapDetail.frame(points: geometry.points, style: .full))
    }

    /// Sin trazado todavía (`pending`): recta discreta entre paradas y las
    /// paradas de los tramos (no hay estaciones aún).
    func testGeometriaSinTrazadoEsRecta() {
        let pending: RouteMap = PreviewData.decode(PreviewData.routeMapPendingJSON)
        let geometry = RouteMapGeometry(map: pending)
        XCTAssertEqual(geometry.straightLines.count, 1)
        XCTAssertTrue(geometry.tracedLines.isEmpty)
        XCTAssertEqual(geometry.straightLines.first?.coarse.count, 2)
        XCTAssertEqual(geometry.stops.map(\.role), [.origin, .destination])
    }

    /// En los transbordos, solo el tiempo mínimo (no hay camino entre andenes
    /// en los datos abiertos).
    func testTransbordoConTiempoMinimo() throws {
        let geometry = RouteMapGeometry(map: TripFixtures.map4)
        XCTAssertEqual(geometry.transfers.count, 1)
        XCTAssertEqual(geometry.transfers.first?.label, "Transbordo · mín. 4 min")
        XCTAssertEqual(geometry.stops.map(\.role), [.origin, .transfer, .destination])
        XCTAssertEqual(TransferText.label(minTransferS: nil), "Transbordo")
        XCTAssertEqual(TransferText.label(minTransferS: 0), "Transbordo")
        XCTAssertEqual(TransferText.label(minTransferS: 61), "Transbordo · mín. 2 min")
    }

    // MARK: - Camino a pie

    /// Con posición, al acceso de entrada más cercano (y lo que queda dentro);
    /// sin ella, a la estación.
    func testCaminoAPieAlAccesoMasCercano() throws {
        let map = PreviewData.routeMap
        let nearBudapest = GeoPoint(latitude: 48.8772, longitude: 2.3272)
        let target = try XCTUnwrap(WalkingTarget.resolve(map: map, legSeq: nil, user: nearBudapest))
        XCTAssertEqual(target.accessName, "r. Budapest")
        XCTAssertEqual(target.insideSeconds, 150)
        XCTAssertEqual(target.stationName, "Gare Saint-Lazare")

        let nearRome = GeoPoint(latitude: 48.8752, longitude: 2.3240)
        let other = try XCTUnwrap(WalkingTarget.resolve(map: map, legSeq: 0, user: nearRome))
        XCTAssertEqual(other.accessName, "acceso 1 · cour de Rome")

        let station = try XCTUnwrap(WalkingTarget.resolve(map: map, legSeq: nil, user: nil))
        XCTAssertNil(station.accessName)
        XCTAssertEqual(station.point.latitude, 48.876837, accuracy: 0.000001)
    }

    // MARK: - Aviso discreto

    func testAvisoDelMapa() {
        XCTAssertEqual(MapScreenLogic.notice(map: nil, isLoading: true, failed: false)?.text, "Cargando el mapa…")
        XCTAssertEqual(MapScreenLogic.notice(map: nil, isLoading: false, failed: true)?.canRetry, true)
        XCTAssertNil(MapScreenLogic.notice(map: nil, isLoading: false, failed: false))
        XCTAssertNil(MapScreenLogic.notice(map: PreviewData.routeMap, isLoading: false, failed: false))

        let pending: RouteMap = PreviewData.decode(PreviewData.routeMapPendingJSON)
        XCTAssertEqual(MapScreenLogic.notice(map: pending, isLoading: false, failed: false)?.symbol, "hourglass")

        var stale = PreviewData.routeMap
        stale.stale = true
        XCTAssertEqual(MapScreenLogic.notice(map: stale, isLoading: false, failed: false)?.symbol,
                       "clock.arrow.circlepath")

        // Sin trazado de alguna línea (y sin estar calculándose): se dice.
        XCTAssertEqual(MapScreenLogic.notice(map: TripFixtures.map4, isLoading: false, failed: false)?.symbol,
                       "line.diagonal")
    }

    /// La ruta del mapa: la del trayecto manda sobre la del tablero.
    func testRutaDelMapa() {
        XCTAssertEqual(MapScreenLogic.routeID(tripRoute: 4, boardRoute: 5), 4)
        XCTAssertEqual(MapScreenLogic.routeID(tripRoute: nil, boardRoute: 5), 5)
        XCTAssertNil(MapScreenLogic.routeID(tripRoute: nil, boardRoute: nil))
    }

    // MARK: - Vía en el mapa

    /// La vía publicada del tren que toca, en su sitio de la estación; en un
    /// tramo sin vía esperada (metro, R3), nada.
    func testViaEnElMapa() throws {
        let board = PreviewData.board(.tranquilo)
        let hint = try XCTUnwrap(MapScreenLogic.platformHint(board: board, routeID: 4, legSeq: 1,
                                                              map: TripFixtures.map4))
        XCTAssertEqual(hint.platform, "21")
        XCTAssertTrue(hint.isReal)
        XCTAssertEqual(hint.point.latitude, 48.877602, accuracy: 0.000001)

        XCTAssertNil(MapScreenLogic.platformHint(board: board, routeID: 4, legSeq: 0, map: TripFixtures.map4))
        XCTAssertNil(MapScreenLogic.platformHint(board: board, routeID: 5, legSeq: 1, map: TripFixtures.map4))

        // Sin vía publicada pero con previsión: probable, nunca real (R10).
        var guessed = board
        guessed.legs[1].departures[0].platform = nil
        guessed.legs[1].departures[0].guess = PreviewData.decode(
            #"{"platform": "21", "share": 0.9, "samples": 20, "basis": "mision", "why": "por el número de tren"}"#,
            as: PlatformGuess.self)
        let probable = try XCTUnwrap(MapScreenLogic.platformHint(board: guessed, routeID: 4, legSeq: 1,
                                                                  map: TripFixtures.map4))
        XCTAssertFalse(probable.isReal)
        XCTAssertEqual(probable.platform, "21")
    }

    // MARK: - Tarjeta del trayecto

    /// El próximo tren del tramo con los minutos descontados desde que llegó
    /// el tablero; el que ya salió (más de 45 s) no se enseña.
    func testTarjetaDescuentaMinutosYQuitaElQueSalio() throws {
        var board = PreviewData.board(.tranquilo)
        // 12:50 en París del 24/09/2026 (10:50 UTC), como las salidas.
        let receivedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T10:50:00Z"))
        board.receivedAt = receivedAt

        let model = try XCTUnwrap(TripCardModel.make(board: board, routeID: 4, legSeq: nil,
                                                      now: receivedAt.addingTimeInterval(125)))
        XCTAssertEqual(model.leg.seq, 0)
        XCTAssertEqual(model.legCount, 2)
        XCTAssertEqual(model.departure?.id, "q2")            // el de las 12:51 ya salió
        XCTAssertEqual(model.departure?.minutes, 1)          // 3 − 2 minutos pasados
        XCTAssertTrue(model.isStale)                         // > 90 s sin tablero (R19)

        let second = try XCTUnwrap(TripCardModel.make(board: board, routeID: 4, legSeq: 1,
                                                       now: receivedAt.addingTimeInterval(20)))
        XCTAssertEqual(second.legIndex, 1)
        XCTAssertEqual(second.departure?.id, "j1")
        XCTAssertFalse(second.isStale)

        XCTAssertNil(TripCardModel.make(board: board, routeID: 5, legSeq: nil, now: receivedAt))
        XCTAssertNil(TripCardModel.make(board: nil, routeID: 4, legSeq: nil, now: receivedAt))
    }

    func testTextosDeLaTarjeta() {
        XCTAssertEqual(TripCardText.distance(830), "850 m")
        XCTAssertEqual(TripCardText.distance(3_240), "3,2 km")
        XCTAssertEqual(TripCardText.distance(2_000), "2 km")
        let target = WalkingTarget(stationName: "Gare Saint-Lazare",
                                   point: TripFixtures.saintLazare, accessName: "r. Budapest", insideSeconds: 150)
        XCTAssertEqual(TripCardText.walking(minutes: 4, target: target, insideMinutes: 3),
                       "4 min a pie hasta Gare Saint-Lazare · por r. Budapest · y 3 min dentro")
        let leg = PreviewData.board(.tranquilo).legs[1]
        XCTAssertEqual(TripCardText.spoken(leg: leg, departure: leg.departures[0]),
                       "Línea J a Ermont - Eaubonne, en 16 minutos, a las 13:06, vía 21, tren largo.")
    }

    // MARK: - staleDate de la Live Activity

    /// El primero de: dato viejo (90 s o 2 × hint), salida + 60 s y el
    /// siguiente cambio de la cifra + 30 s (contado desde la llegada).
    func testStaleDateDeLaLiveActivity() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let now = receivedAt.addingTimeInterval(75)
        XCTAssertEqual(ActivityTiming.nextChange(receivedAt: receivedAt, now: now),
                       receivedAt.addingTimeInterval(120))
        XCTAssertEqual(ActivityTiming.staleDate(receivedAt: receivedAt, refreshHint: 30, connectionOK: true,
                                                shownDeparture: receivedAt.addingTimeInterval(600), now: now),
                       receivedAt.addingTimeInterval(90))
        // Sin conexión el primer término no cuenta: manda el cambio de cifra.
        XCTAssertEqual(ActivityTiming.staleDate(receivedAt: receivedAt, refreshHint: 30, connectionOK: false,
                                                shownDeparture: receivedAt.addingTimeInterval(600), now: now),
                       receivedAt.addingTimeInterval(150))
        // El tren que sale antes manda.
        XCTAssertEqual(ActivityTiming.staleDate(receivedAt: receivedAt, refreshHint: 120, connectionOK: true,
                                                shownDeparture: receivedAt.addingTimeInterval(20), now: receivedAt),
                       receivedAt.addingTimeInterval(80))
    }
}
