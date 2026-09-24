import XCTest
@testable import Trajet

/// El tablero: nunca se borra la pantalla (R9), bucle solo mirando o en
/// trayecto (R7), refrescos automáticos sin historial (R40), 404 de ruta
/// borrada (R44), antigüedad y dato viejo (R17, R19), cambiar de ruta (R39).
final class BoardStoreTests: XCTestCase {

    @MainActor
    private func makeStore(_ fake: FakeBoardSource, clock: TestClock = TestClock(),
                           persistence: BoardPersistence = .memory()) -> BoardStore {
        BoardStore(api: fake, persistence: persistence, now: { clock.now })
    }

    // MARK: - R9

    /// Un fallo de red deja el último tablero bueno y dice por qué.
    @MainActor
    func testErrorConservaTablero() async {
        let fake = FakeBoardSource()
        await fake.enqueue(.success(PreviewData.payload(.tranquilo)))
        await fake.enqueue(.failure(.network("sin red")))
        await fake.enqueue(.failure(.server(code: "prim_key_missing", message: "", status: 503, retryAfter: nil)))
        let store = makeStore(fake)

        await store.refresh()
        XCTAssertEqual(store.board?.route?.id, 4)
        XCTAssertNil(store.issue)

        await store.refresh()
        XCTAssertEqual(store.board?.route?.id, 4)
        XCTAssertEqual(store.board?.legs.count, 2)
        XCTAssertEqual(store.issue, .offline("sin red"))

        await store.refresh()
        XCTAssertEqual(store.board?.legs.count, 2)
        XCTAssertEqual(store.issue, .noKey)
        XCTAssertTrue(store.hasLoadedOnce)
    }

    /// Al arrancar se pinta la caché con su hora real (R9, R20).
    @MainActor
    func testPrimeraAperturaEnsenaCache() {
        let clock = TestClock()
        let cached = CachedBoard(board: PreviewData.board(.tranquilo),
                                 receivedAt: clock.now.addingTimeInterval(-600), routeID: nil)
        let store = makeStore(FakeBoardSource(), clock: clock, persistence: .memory(cached))
        XCTAssertEqual(store.board?.route?.id, 4)
        XCTAssertEqual(store.receivedAt, clock.now.addingTimeInterval(-600))
        XCTAssertTrue(store.isStale())
        XCTAssertEqual(store.ageSeconds() ?? 0, 606, accuracy: 0.001)
    }

    /// Un tramo con la estación caída y sin salidas conserva sus últimas
    /// salidas buenas, con su antigüedad de verdad; el estado es el nuevo.
    @MainActor
    func testTramoCaidoConservaSusSalidas() async throws {
        let clock = TestClock()
        let fake = FakeBoardSource()
        let good = PreviewData.board(.tranquilo)
        var bad = good
        bad.legs[1].departures = []
        bad.legs[1].age = nil
        bad.legs[1].status = LegStatus(level: 1, label: "perturbada", messages: ["Trafic perturbé."],
                                       messagesEs: [nil], translating: true)
        bad.stale = true
        bad.errors = ["Gare Saint-Lazare: tiempo de espera agotado"]
        await fake.enqueue(.success(.board(good)))
        await fake.enqueue(.success(.board(bad)))
        let store = makeStore(fake, clock: clock)

        await store.refresh()
        clock.advance(30)
        await store.refresh()

        let leg = try XCTUnwrap(store.board?.legs[1])
        XCTAssertEqual(leg.departures.map(\.id), good.legs[1].departures.map(\.id))
        XCTAssertEqual(leg.status.level, 1)                          // el estado, el nuevo
        XCTAssertTrue(store.isRetained(seq: 1))
        XCTAssertFalse(store.isRetained(seq: 0))
        XCTAssertEqual(leg.age ?? 0, 3.2 + 30, accuracy: 0.001)
        XCTAssertEqual(store.legAge(seq: 1, now: clock.now.addingTimeInterval(10)) ?? 0, 3.2 + 30 + 10, accuracy: 0.001)
        XCTAssertTrue(store.isStale())                               // stale del servidor

        // Si vuelve, se sueltan.
        await fake.enqueue(.success(.board(good)))
        await store.refresh()
        XCTAssertFalse(store.isRetained(seq: 1))
    }

    /// Cambiar de ruta no vacía la pantalla aunque la petición falle.
    @MainActor
    func testCambioDeRutaNoVaciaPantalla() async {
        let fake = FakeBoardSource()
        await fake.enqueue(.success(PreviewData.payload(.tranquilo)))
        await fake.enqueue(.failure(.network("sin red")))
        let store = makeStore(fake)
        await store.refresh()
        store.selectRoute(9)
        XCTAssertEqual(store.pinnedRouteID, 9)
        XCTAssertEqual(store.board?.route?.id, 4)                    // sigue ahí
        let done = await waitUntil { await fake.calls.count >= 2 && store.issue != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(store.board?.route?.id, 4)
        XCTAssertTrue(store.isShowingOtherRoute)
    }

    /// Un tablero vacío del servidor no es un error.
    @MainActor
    func testSinRutasNoEsError() async {
        let fake = FakeBoardSource()
        await fake.enqueue(.success(PreviewData.emptyPayload))
        let store = makeStore(fake, persistence: .memory(PreviewData.cached(.tranquilo, receivedSecondsAgo: 60)))
        await store.refresh()
        XCTAssertNil(store.board)
        XCTAssertEqual(store.emptyMessage, "todavía no hay rutas guardadas")
        XCTAssertNil(store.issue)
    }

    // MARK: - R44

    /// 404 de la ruta fijada: no es «sin red»; se vuelve a la automática y se
    /// pide ya.
    @MainActor
    func test404RutaBorradaVuelveAAutomatica() async {
        let fake = FakeBoardSource()
        await fake.enqueue(.failure(.notFound))
        await fake.enqueue(.success(PreviewData.payload(.tranquilo)))
        let store = makeStore(fake)
        store.selectRoute(7)
        let done = await waitUntil { await fake.calls.count >= 2 && store.board != nil }
        XCTAssertTrue(done)
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.routeID), [7, nil])
        XCTAssertNil(store.pinnedRouteID)
        XCTAssertNil(store.issue)
        XCTAssertEqual(store.board?.route?.id, 4)
    }

    /// Borrar la ruta fijada suelta la fijación (R44) y refresca (R39).
    @MainActor
    func testBorrarLaRutaFijada() async {
        let fake = FakeBoardSource(fallback: .success(PreviewData.payload(.tranquilo)))
        let store = makeStore(fake)
        store.selectRoute(5)
        _ = await waitUntil { await fake.calls.count >= 1 }
        store.routesChanged(.deleted(5))
        XCTAssertNil(store.pinnedRouteID)
        let done = await waitUntil { await fake.calls.count >= 2 }
        XCTAssertTrue(done)
        let calls = await fake.calls
        XCTAssertEqual(calls.last?.routeID, nil)
    }

    // MARK: - R39

    /// Elegir ruta refresca al momento, con esa ruta.
    @MainActor
    func testSeleccionRefrescaYa() async {
        let fake = FakeBoardSource(fallback: .success(PreviewData.payload(.unTramo)))
        let store = makeStore(fake)
        store.selectRoute(5)
        let done = await waitUntil { await fake.calls.count >= 1 }
        XCTAssertTrue(done)
        let calls = await fake.calls
        XCTAssertEqual(calls.first, FakeBoardSource.Call(routeID: 5, logHistory: true))
        XCTAssertEqual(store.currentRouteID, 5)
    }

    // MARK: - R40

    @MainActor
    func testRefrescoAutomaticoSinHistorial() async {
        let fake = FakeBoardSource(fallback: .success(PreviewData.payload(.tranquilo)))
        let store = makeStore(fake)
        await store.autoRefresh()
        await store.refresh()
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.logHistory), [false, true])
    }

    // MARK: - R7

    /// El bucle solo corre con el tablero delante y la app activa, o en modo
    /// trayecto; su primer refresco es automático (sin historial).
    @MainActor
    func testBucleSoloVisibleOEnTrayecto() async {
        let fake = FakeBoardSource(fallback: .success(PreviewData.payload(.tranquilo)))
        let store = makeStore(fake)
        XCTAssertFalse(store.isLoopRunning)

        store.setVisible(true)
        XCTAssertTrue(store.isLoopRunning)
        let started = await waitUntil { await fake.calls.count >= 1 }
        XCTAssertTrue(started)
        let first = await fake.calls.first
        XCTAssertEqual(first?.logHistory, false)

        store.setVisible(false)
        XCTAssertFalse(store.isLoopRunning)

        store.setTripMode(true)                  // en trayecto, aunque no se mire
        XCTAssertTrue(store.isLoopRunning)
        store.setTripMode(false)
        XCTAssertFalse(store.isLoopRunning)

        store.setVisible(true)
        XCTAssertTrue(store.isLoopRunning)
        store.setSceneActive(false)              // segundo plano: se para
        XCTAssertFalse(store.isLoopRunning)
        store.setTripMode(true)
        XCTAssertTrue(store.isLoopRunning)
        store.setTripMode(false)
        store.setVisible(false)
        XCTAssertFalse(store.isLoopRunning)
    }

    /// El ritmo lo marca el servidor, nunca por debajo de 30 s.
    @MainActor
    func testRitmoDelServidor() async {
        let clock = TestClock()
        let fake = FakeBoardSource()
        await fake.enqueue(.success(PreviewData.payload(.cuotaJusta)))
        let store = makeStore(fake, clock: clock)
        XCTAssertEqual(store.refreshInterval, 30)
        await store.refresh()
        XCTAssertEqual(store.refreshInterval, 120)
        XCTAssertEqual(store.nextRefreshAt, clock.now.addingTimeInterval(120))
    }

    // MARK: - R17, R19

    @MainActor
    func testAntiguedadDesdeLlegadaAlTelefono() async {
        let clock = TestClock()
        let fake = FakeBoardSource(fallback: .success(PreviewData.payload(.tranquilo)))
        let store = makeStore(fake, clock: clock)
        await store.refresh()
        XCTAssertEqual(store.receivedAt, clock.now)
        // data_age 6.0 + 60 s en el teléfono.
        XCTAssertEqual(store.ageSeconds(now: clock.now.addingTimeInterval(60)) ?? 0, 66, accuracy: 0.001)
    }

    @MainActor
    func testViejoA90Segundos() async {
        let clock = TestClock()
        let fake = FakeBoardSource()
        var calm = PreviewData.board(.tranquilo)
        calm.dataAge = 300                              // data_age alto no apaga
        await fake.enqueue(.success(.board(calm)))
        await fake.enqueue(.success(PreviewData.payload(.viejo)))
        let store = makeStore(fake, clock: clock)
        await store.refresh()
        let t0 = clock.now
        XCTAssertFalse(store.isStale(now: t0))
        XCTAssertFalse(store.isStale(now: t0.addingTimeInterval(90)))
        XCTAssertTrue(store.isStale(now: t0.addingTimeInterval(91)))
        await store.refresh()                          // stale del servidor
        XCTAssertTrue(store.isStale(now: t0))
    }

    // MARK: - Vía que aparece (háptica, R2)

    @MainActor
    func testViaQueApareceAvisa() async throws {
        let fake = FakeBoardSource()
        await fake.enqueue(.success(PreviewData.payload(.viaProbable)))
        await fake.enqueue(.success(PreviewData.payload(.viaAparece)))
        await fake.enqueue(.success(PreviewData.payload(.viaAparece)))
        let store = makeStore(fake)
        await store.refresh()
        XCTAssertNil(store.lastPlatformEvent)
        await store.refresh()
        let event = try XCTUnwrap(store.lastPlatformEvent)
        XCTAssertEqual(event.platform, "21")
        XCTAssertEqual(event.legSeq, 0)
        XCTAssertEqual(event.departureID, "j1")
        await store.refresh()                          // la misma vía: no se repite
        XCTAssertEqual(store.lastPlatformEvent?.id, event.id)
    }

    // MARK: - Errores con código → estado diseñado

    func testCodigosAEstados() {
        func server(_ code: String, retry: Int? = nil) -> APIError {
            .server(code: code, message: "", status: 503, retryAfter: retry)
        }
        XCTAssertEqual(BoardStore.designedIssue(for: server("prim_key_missing")), .noKey)
        XCTAssertEqual(BoardStore.designedIssue(for: server("prim_key_invalid")), .keyRejected)
        XCTAssertEqual(BoardStore.designedIssue(for: server("prim_quota_exhausted", retry: 60)), .quotaExhausted(retryAfter: 60))
        XCTAssertEqual(BoardStore.designedIssue(for: server("prim_unreachable")), .upstream)
        XCTAssertEqual(BoardStore.designedIssue(for: server("upstream")), .upstream)
        XCTAssertEqual(BoardStore.designedIssue(for: .unauthorized), .notPaired)
        XCTAssertEqual(BoardStore.designedIssue(for: .notPaired), .notPaired)
        XCTAssertEqual(BoardStore.designedIssue(for: .network("x")), .offline("x"))
        XCTAssertFalse(BoardIssue.noKey.message.isEmpty)
        XCTAssertEqual(BoardIssue.offline("").title, "Sin conexión")
    }
}
