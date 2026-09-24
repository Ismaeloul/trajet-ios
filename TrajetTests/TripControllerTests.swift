import XCTest
@testable import Trajet

/// El modo trayecto (docs/app-v2.md «Modo trayecto», arquitectura.md §6):
/// máquina de estados con una ubicación falsa. Inicio y permiso, refresco
/// solo en trayecto (R7), llegada por distancia, tiempo máximo, parada a
/// mano (app y Live Activity), permiso denegado (sigue sin GPS), avance de
/// tramo y geocercas.
final class TripControllerTests: XCTestCase {

    // MARK: - Montaje

    private struct Rig {
        let trip: TripController
        let board: BoardStore
        let source: FakeBoardSource
        let location: FakeLocationService
        let maps: FakeRouteMaps
        let geofences: FakeGeofences
        let activity: FakeTripActivity
        let settings: TripSettings
        let records: TripRecordStore
        let clock: TestClock
    }

    @MainActor
    private func makeRig(authorization: LocationAuthorization = .whenInUse,
                         answer: LocationAuthorization = .whenInUse,
                         geofencesEnabled: Bool = false,
                         maxMinutes: Int? = nil) -> Rig {
        let clock = TestClock()
        let defaults = makeTestDefaults()
        let source = FakeBoardSource(fallback: .success(PreviewData.payload(.tranquilo)))
        let cached = CachedBoard(board: PreviewData.board(.tranquilo), receivedAt: clock.now, routeID: nil)
        let board = BoardStore(api: source, persistence: .memory(cached), now: { clock.now })
        let location = FakeLocationService(authorization: authorization, answer: answer)
        let maps = FakeRouteMaps()
        maps.maps[4] = TripFixtures.map4
        let geofences = FakeGeofences()
        let activity = FakeTripActivity()
        let settings = TripSettings(defaults: defaults)
        settings.geofencesEnabled = geofencesEnabled
        if let maxMinutes { settings.maxMinutes = maxMinutes }
        let records = TripRecordStore(defaults: defaults)
        let trip = TripController(board: board, maps: maps, routes: { PreviewData.routes },
                                  settings: settings, location: location, geofences: geofences,
                                  activity: activity, records: records, now: { clock.now })
        return Rig(trip: trip, board: board, source: source, location: location, maps: maps,
                   geofences: geofences, activity: activity, settings: settings, records: records, clock: clock)
    }

    // MARK: - Inicio

    /// «Empezar trayecto» sin permiso contestado: se pide (una vez) y el
    /// trayecto arranca con GPS, tablero en modo trayecto y registro en disco.
    @MainActor
    func testEmpezarPidePermisoYActiva() async throws {
        let rig = makeRig(authorization: .notDetermined, answer: .whenInUse)
        XCTAssertEqual(rig.trip.state, .off)
        XCTAssertFalse(rig.trip.isActive)

        await rig.trip.start(routeID: 4)

        XCTAssertTrue(rig.trip.isActive)
        XCTAssertEqual(rig.trip.activeRouteID, 4)
        XCTAssertEqual(rig.location.whenInUseRequests, 1)
        let session = try XCTUnwrap(rig.trip.session)
        XCTAssertTrue(session.usesLocation)
        XCTAssertEqual(session.deadline, rig.clock.now.addingTimeInterval(90 * 60))
        XCTAssertEqual(session.currentLegSeq, 0)
        XCTAssertTrue(rig.location.isTracking)
        XCTAssertTrue(rig.board.isTripMode)
        XCTAssertEqual(rig.board.pinnedRouteID, 4)          // fijada todo el trayecto
        XCTAssertEqual(rig.records.load()?.routeID, 4)
        XCTAssertNotNil(TripStopHandler.stop)

        // Empezar otra vez no hace nada.
        await rig.trip.start(routeID: 5)
        XCTAssertEqual(rig.trip.activeRouteID, 4)

        await rig.trip.stop(reason: .manual)
    }

    /// Con el permiso ya dado no se vuelve a preguntar.
    @MainActor
    func testConPermisoNoPregunta() async {
        let rig = makeRig(authorization: .whenInUse)
        await rig.trip.start(routeID: 4)
        XCTAssertEqual(rig.location.whenInUseRequests, 0)
        XCTAssertTrue(rig.trip.usesLocation)
        await rig.trip.stop(reason: .manual)
    }

    // MARK: - R7: refresco en segundo plano solo en trayecto

    /// Sin mirar el tablero y con la app en segundo plano el bucle está
    /// parado; en trayecto corre, cada tablero nuevo llega a la Live Activity
    /// y al parar se vuelve a apagar.
    @MainActor
    func testRefrescoEnSegundoPlanoSoloEnTrayecto() async {
        let rig = makeRig()
        rig.board.setVisible(false)
        rig.board.setSceneActive(false)
        XCTAssertFalse(rig.board.isLoopRunning)

        await rig.trip.start(routeID: 4)
        XCTAssertTrue(rig.board.isLoopRunning)

        // La Live Activity empieza con el tablero de la ruta del trayecto.
        let started = await waitUntil { !rig.activity.started.isEmpty }
        XCTAssertTrue(started)
        XCTAssertEqual(rig.activity.started.first?.routeID, 4)
        XCTAssertEqual(rig.activity.started.first?.routeName, "Trabajo → Casa")
        XCTAssertEqual(rig.activity.started.first?.legCount, 2)

        // Un refresco del bucle (sin historial, R40) se escribe en la actividad.
        let updatesBefore = rig.activity.updates.count
        rig.clock.advance(30)
        await rig.board.autoRefresh()
        let updated = await waitUntil { rig.activity.updates.count > updatesBefore }
        XCTAssertTrue(updated)
        let calls = await rig.source.calls
        XCTAssertTrue(calls.contains(FakeBoardSource.Call(routeID: 4, logHistory: false)))

        await rig.trip.stop(reason: .manual)
        XCTAssertFalse(rig.board.isTripMode)
        XCTAssertFalse(rig.board.isLoopRunning)
        XCTAssertFalse(rig.location.isTracking)
        XCTAssertNil(rig.board.pinnedRouteID)               // vuelve a la que toca
    }

    // MARK: - Llegada

    /// Lejos del destino y luego a ~100 m de la estación de destino: se
    /// apaga solo y la Live Activity queda en «has llegado».
    @MainActor
    func testLlegadaApagaElTrayecto() async {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)

        rig.location.send(TripFixtures.olympiades, at: rig.clock.now)
        XCTAssertTrue(rig.trip.isActive)
        XCTAssertEqual(rig.trip.session?.armed, true)
        XCTAssertGreaterThan(rig.trip.session?.distanceToDestination ?? 0, 10_000)

        rig.location.send(TripFixtures.outsideArgenteuil, at: rig.clock.now)
        XCTAssertTrue(rig.trip.isActive)                     // a 300 m no es llegar

        rig.location.send(TripFixtures.nearArgenteuil, at: rig.clock.now)
        let ended = await waitUntil { rig.trip.state == .ended(.arrived) }
        XCTAssertTrue(ended)
        XCTAssertEqual(rig.activity.ended, [.arrived])
        XCTAssertFalse(rig.location.isTracking)
        XCTAssertFalse(rig.board.isTripMode)
        XCTAssertNil(rig.records.load())
        XCTAssertNotNil(rig.trip.endedAt)

        rig.trip.acknowledgeEnd()
        XCTAssertEqual(rig.trip.state, .off)
    }

    /// Empezar al lado del destino no es llegar: hay que haberse alejado.
    @MainActor
    func testEmpezarAlLadoDelDestinoNoEsLlegar() async {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)
        rig.location.send(TripFixtures.nearArgenteuil, at: rig.clock.now)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(rig.trip.isActive)
        XCTAssertEqual(rig.trip.session?.armed, false)
        await rig.trip.stop(reason: .manual)
    }

    /// Una posición vieja o muy imprecisa no decide nada.
    @MainActor
    func testPosicionMalaNoDecide() async {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)
        rig.location.send(TripFixtures.olympiades, at: rig.clock.now)
        rig.location.send(TripFixtures.nearArgenteuil, accuracy: 900, at: rig.clock.now)
        rig.location.send(TripFixtures.nearArgenteuil, at: rig.clock.now.addingTimeInterval(-600))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(rig.trip.isActive)
        await rig.trip.stop(reason: .manual)
    }

    // MARK: - Tiempo máximo

    @MainActor
    func testTiempoMaximoApagaElTrayecto() async {
        let rig = makeRig(maxMinutes: 30)
        await rig.trip.start(routeID: 4)
        XCTAssertEqual(rig.trip.deadline, rig.clock.now.addingTimeInterval(30 * 60))

        rig.clock.advance(29 * 60)
        await rig.trip.tick()
        XCTAssertTrue(rig.trip.isActive)

        rig.clock.advance(61)
        await rig.trip.tick()
        let ended = await waitUntil { rig.trip.state == .ended(.timeLimit) }
        XCTAssertTrue(ended)
        XCTAssertEqual(rig.activity.ended, [.timeLimit])
        XCTAssertFalse(rig.board.isTripMode)
        XCTAssertFalse(rig.location.isTracking)
    }

    // MARK: - Parada a mano

    /// «Parar» desde la Live Activity (StopTripIntent → TripStopHandler) y
    /// desde la app.
    @MainActor
    func testParadaManualDesdeLaAppYLaLiveActivity() async {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)
        await TripStopHandler.run()
        XCTAssertEqual(rig.trip.state, .ended(.manual))
        XCTAssertEqual(rig.activity.ended, [.manual])
        XCTAssertFalse(rig.location.isTracking)

        await rig.trip.start(routeID: 4)
        XCTAssertTrue(rig.trip.isActive)
        await rig.trip.stop(reason: .manual)
        XCTAssertEqual(rig.trip.state, .ended(.manual))
        XCTAssertEqual(rig.activity.ended, [.manual, .manual])
        XCTAssertFalse(rig.board.isTripMode)
    }

    /// «Parar» sin trayecto (la app se cerró) quita la Live Activity que
    /// hubiera quedado.
    @MainActor
    func testPararSinTrayectoQuitaLaLiveActivity() async {
        let rig = makeRig()
        let before = rig.activity.endAllCalls
        await rig.trip.stop(reason: .manual)
        XCTAssertEqual(rig.trip.state, .off)
        XCTAssertGreaterThan(rig.activity.endAllCalls, before)
    }

    // MARK: - Permiso denegado

    /// Sin permiso el trayecto sigue igual (tablero y Live Activity), pero
    /// sin GPS: no hay llegada automática, solo el tiempo máximo.
    @MainActor
    func testPermisoDenegadoSigueSinGPS() async {
        let rig = makeRig(authorization: .notDetermined, answer: .denied, maxMinutes: 15)
        await rig.trip.start(routeID: 4)

        XCTAssertTrue(rig.trip.isActive)
        XCTAssertFalse(rig.trip.usesLocation)
        XCTAssertFalse(rig.location.isTracking)
        XCTAssertTrue(rig.board.isTripMode)

        rig.location.send(TripFixtures.olympiades, at: rig.clock.now)
        rig.location.send(TripFixtures.nearArgenteuil, at: rig.clock.now)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(rig.trip.isActive)                     // sin llegada automática

        rig.clock.advance(15 * 60 + 1)
        await rig.trip.tick()
        let ended = await waitUntil { rig.trip.state == .ended(.timeLimit) }
        XCTAssertTrue(ended)
    }

    /// Quitar el permiso en mitad del trayecto: sigue sin GPS.
    @MainActor
    func testQuitarElPermisoEnMitadSigueSinGPS() async {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)
        XCTAssertTrue(rig.location.isTracking)
        rig.location.change(to: .denied)
        XCTAssertTrue(rig.trip.isActive)
        XCTAssertFalse(rig.trip.usesLocation)
        XCTAssertFalse(rig.location.isTracking)
        await rig.trip.stop(reason: .manual)
    }

    // MARK: - Tramo en el que se va

    /// Cerca de la subida del tramo siguiente, el trayecto pasa a ese tramo y
    /// la Live Activity se escribe desde él.
    @MainActor
    func testAvanzaDeTramoEnElTransbordo() async throws {
        let rig = makeRig()
        await rig.trip.start(routeID: 4)
        XCTAssertEqual(rig.trip.currentLegSeq, 0)

        rig.location.send(TripFixtures.olympiades, at: rig.clock.now)
        XCTAssertEqual(rig.trip.currentLegSeq, 0)
        rig.location.send(TripFixtures.saintLazare, at: rig.clock.now)
        XCTAssertEqual(rig.trip.currentLegSeq, 1)
        XCTAssertEqual(rig.records.load()?.currentLegSeq, 1)

        let session = try XCTUnwrap(rig.trip.session)
        let snapshot = try XCTUnwrap(rig.trip.makeSnapshot(for: session))
        XCTAssertEqual(snapshot.legOffset, 1)
        XCTAssertEqual(snapshot.legCount, 2)
        XCTAssertEqual(snapshot.board.legs.map(\.seq), [1])

        // Nunca vuelve atrás.
        rig.location.send(TripFixtures.olympiades, at: rig.clock.now)
        XCTAssertEqual(rig.trip.currentLegSeq, 1)
        await rig.trip.stop(reason: .manual)
    }

    // MARK: - Geocercas

    /// Con las geocercas activadas y «Siempre», se vigilan las estaciones de
    /// origen que tienen coordenadas en algún mapa.
    @MainActor
    func testGeocercasConSiempre() async {
        let rig = makeRig(authorization: .always, geofencesEnabled: true)
        let watching = await waitUntil {
            rig.trip.monitoredStationIDs == ["stop_area:IDFM:70604", "stop_area:IDFM:71370"]
        }
        XCTAssertTrue(watching)
        XCTAssertEqual(rig.geofences.lastKeeping, ["stop_area:IDFM:420512", "stop_area:IDFM:474151"])
    }

    /// Sin «Siempre», nada de geocercas aunque estén activadas.
    @MainActor
    func testSinSiempreNoHayGeocercas() async {
        let rig = makeRig(authorization: .whenInUse, geofencesEnabled: true)
        let stopped = await waitUntil { rig.geofences.stopCalls > 0 }
        XCTAssertTrue(stopped)
        XCTAssertEqual(rig.geofences.monitorCalls, 0)
        XCTAssertTrue(rig.trip.monitoredStationIDs.isEmpty)
        XCTAssertFalse(rig.trip.canUseGeofences)
    }

    /// Pedir «Siempre» desde Ajustes: si se concede, quedan activadas; si no,
    /// apagadas.
    @MainActor
    func testPedirSiempreParaGeocercas() async {
        let yes = makeRig(authorization: .whenInUse)
        yes.location.alwaysAnswer = .always
        await yes.trip.requestAlwaysForGeofences()
        XCTAssertEqual(yes.location.alwaysRequests, 1)
        XCTAssertTrue(yes.settings.geofencesEnabled)

        let no = makeRig(authorization: .whenInUse)
        no.location.alwaysAnswer = .whenInUse
        await no.trip.requestAlwaysForGeofences()
        XCTAssertFalse(no.settings.geofencesEnabled)
    }

    /// Entrar en una estación vigilada refresca el tablero UNA vez (sin
    /// historial) y no vuelve a hacerlo en unos minutos.
    @MainActor
    func testEntrarEnGeocercaRefrescaUnaVez() async {
        let rig = makeRig(authorization: .always, geofencesEnabled: true)
        let before = await rig.source.calls.count
        rig.geofences.onEnter?("stop_area:IDFM:71370")
        let refreshed = await waitUntil { await rig.source.calls.count == before + 1 }
        XCTAssertTrue(refreshed)
        let last = await rig.source.calls.last
        XCTAssertEqual(last?.logHistory, false)

        rig.geofences.onEnter?("stop_area:IDFM:71370")
        try? await Task.sleep(for: .milliseconds(150))
        let after = await rig.source.calls.count
        XCTAssertEqual(after, before + 1)
    }

    // MARK: - Alertas de la Live Activity

    /// Solo avisan la vía publicada, el cambio de vía, el tren cancelado y
    /// la línea cortada; un cambio de minuto no.
    func testAlertasSoloLoQueImporta() {
        let board = PreviewData.board(.tranquilo)
        let current = board.legs[1]                          // J con vía 21 publicada
        var withoutPlatform = current
        withoutPlatform.departures[0].platform = nil
        XCTAssertEqual(TripAlert.detect(previous: withoutPlatform, current: current)?.kind, .platformPublished)

        var otherPlatform = current
        otherPlatform.departures[0].platform = "19"
        XCTAssertEqual(TripAlert.detect(previous: otherPlatform, current: current)?.kind, .platformChanged)

        var minuteLater = current
        minuteLater.departures[0].minutes -= 1
        XCTAssertNil(TripAlert.detect(previous: current, current: minuteLater))

        var cut = current
        cut.status.level = 2
        XCTAssertEqual(TripAlert.detect(previous: current, current: cut)?.kind, .lineCut)
    }
}

// MARK: - Datos del trayecto

enum TripFixtures {
    static let olympiades = GeoPoint(latitude: 48.827123, longitude: 2.366990)
    static let saintLazare = GeoPoint(latitude: 48.876837, longitude: 2.324738)
    static let argenteuil = GeoPoint(latitude: 48.946797, longitude: 2.257897)
    /// A unos 100 m de la estación de Argenteuil.
    static let nearArgenteuil = GeoPoint(latitude: 48.9460, longitude: 2.2585)
    /// A unos 300 m.
    static let outsideArgenteuil = GeoPoint(latitude: 48.9441, longitude: 2.2579)

    /// El mapa de la ruta 4 (14 de Olympiades a Saint-Lazare, J hasta
    /// Argenteuil), sin trazado (rectas).
    static let map4JSON = """
    {"route_id": 4, "generated_at": "2026-09-24T05:30:12+00:00", "pending": false, "stale": false,
     "lines": [
      {"seq": 0, "line_id": "line:IDFM:C01384", "code": "14", "mode": "metro", "color": "#640082", "text_color": "#FFFFFF",
       "from": {"zdc": "70604", "name": "Olympiades", "lat": 48.827123, "lon": 2.366990},
       "to": {"zdc": "71370", "name": "Saint-Lazare", "lat": 48.875190, "lon": 2.325520},
       "path": null, "via": [], "source": "recta"},
      {"seq": 1, "line_id": "line:IDFM:C01739", "code": "J", "mode": "rail", "color": "#CEC73D", "text_color": "#000000",
       "from": {"zdc": "71370", "name": "Gare Saint-Lazare", "lat": 48.876837, "lon": 2.324738},
       "to": {"zdc": "65063", "name": "Argenteuil", "lat": 48.946797, "lon": 2.257897},
       "path": null, "via": [], "source": "recta"}],
     "stations": [
      {"zdc": "70604", "name": "Olympiades", "lat": 48.827123, "lon": 2.366990, "role": "origin",
       "platforms": [], "tracks": []},
      {"zdc": "71370", "name": "Gare Saint-Lazare", "lat": 48.876837, "lon": 2.324738, "role": "transfer",
       "platforms": [], "tracks": [{"voie": "21", "lat": 48.877602, "lon": 2.324921}]},
      {"zdc": "65063", "name": "Argenteuil", "lat": 48.946797, "lon": 2.257897, "role": "destination",
       "platforms": [], "tracks": []}],
     "accesses": [],
     "transfers": [{"zdc": "71370", "from_seq": 0, "to_seq": 1, "min_transfer_s": 240}],
     "sources": {}, "license": "Datos: Île-de-France Mobilités (ODbL)"}
    """

    static var map4: RouteMap { PreviewData.decode(map4JSON) }
}

// MARK: - Falsos

/// Ubicación de mentira: contesta al permiso lo que se le diga y manda las
/// posiciones a mano.
@MainActor
final class FakeLocationService: LocationService {
    var authorization: LocationAuthorization
    /// Lo que se contesta al pedir «Al usar la app».
    var answer: LocationAuthorization
    /// Lo que se contesta al pedir «Siempre».
    var alwaysAnswer: LocationAuthorization = .always
    private(set) var lastLocation: TripLocation? = nil
    private(set) var isTracking = false
    var onLocation: (@MainActor (TripLocation) -> Void)?
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    private(set) var whenInUseRequests = 0
    private(set) var alwaysRequests = 0

    init(authorization: LocationAuthorization, answer: LocationAuthorization) {
        self.authorization = authorization
        self.answer = answer
    }

    func requestWhenInUse() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        whenInUseRequests += 1
        authorization = answer
        return authorization
    }

    func requestAlways() async -> LocationAuthorization {
        alwaysRequests += 1
        authorization = alwaysAnswer
        return authorization
    }

    func startTripUpdates() { isTracking = true }
    func stopTripUpdates() { isTracking = false }
    func requestCurrentLocation() {}

    func send(_ point: GeoPoint, accuracy: Double = 50, at date: Date) {
        let fix = TripLocation(point: point, horizontalAccuracy: accuracy, timestamp: date)
        lastLocation = fix
        onLocation?(fix)
    }

    func change(to authorization: LocationAuthorization) {
        self.authorization = authorization
        onAuthorizationChange?(authorization)
    }
}

@MainActor
final class FakeRouteMaps: RouteMapProviding {
    var maps: [Int: RouteMap] = [:]
    private(set) var loads: [Int] = []

    func map(for routeID: Int) -> RouteMap? { maps[routeID] }

    func load(routeID: Int, force: Bool) async {
        loads.append(routeID)
    }
}

@MainActor
final class FakeGeofences: GeofenceMonitoring {
    var onEnter: (@MainActor (String) -> Void)?
    private(set) var monitoredIDs: Set<String> = []
    private(set) var monitorCalls = 0
    private(set) var stopCalls = 0
    private(set) var lastKeeping: Set<String> = []

    func monitor(_ stations: [WatchedStation], keeping: Set<String>) async {
        monitorCalls += 1
        lastKeeping = keeping
        monitoredIDs = Set(stations.map(\.id)).union(keeping.intersection(monitoredIDs))
    }

    func stopAll() async {
        stopCalls += 1
        monitoredIDs = []
    }
}

@MainActor
final class FakeTripActivity: TripActivityControlling {
    private(set) var isRunning = false
    var canStart = true
    private(set) var started: [TripActivitySnapshot] = []
    private(set) var updates: [TripActivitySnapshot] = []
    private(set) var alerts: [TripAlert] = []
    private(set) var ended: [TripEndReason] = []
    private(set) var endAllCalls = 0

    func start(_ snapshot: TripActivitySnapshot) async -> Bool {
        started.append(snapshot)
        isRunning = canStart
        return canStart
    }

    func update(_ snapshot: TripActivitySnapshot, alert: TripAlert?) async {
        updates.append(snapshot)
        if let alert { alerts.append(alert) }
    }

    func end(_ snapshot: TripActivitySnapshot?, reason: TripEndReason) async {
        ended.append(reason)
        isRunning = false
    }

    func adopt(routeID: Int) -> Bool { false }

    func endAll() async {
        endAllCalls += 1
        isRunning = false
    }
}
