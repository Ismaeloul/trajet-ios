import XCTest
@testable import Trajet

/// Rutas: una sola copia y una sola carga (R41); tocarlas avisa al tablero
/// (R39).
final class RoutesStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.registry.reset(nil)
    }

    override func tearDown() {
        MockURLProtocol.registry.reset(nil)
        super.tearDown()
    }

    @MainActor
    func testLoadIfNeededUnaVez() async {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.routesJSON) }
        let store = RoutesStore(api: api)

        // Dos pantallas a la vez: una sola llamada.
        let a = Task { await store.loadIfNeeded() }
        let b = Task { await store.loadIfNeeded() }
        await a.value
        await b.value
        await store.loadIfNeeded()

        XCTAssertEqual(MockURLProtocol.registry.requests.count, 1)
        XCTAssertEqual(store.routes.count, 4)
        XCTAssertEqual(store.activeID, 3)
        XCTAssertEqual(store.activeRoute?.name, "Casa → Trabajo")
        XCTAssertTrue(store.hasLoaded)
    }

    /// Si la carga falla no se da por cargada: la siguiente vuelve a probar, y
    /// el error se ve (no se confunde con «no hay rutas»).
    @MainActor
    func testFalloNoCuentaComoCargado() async {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { _ in throw URLError(.timedOut) }
        let store = RoutesStore(api: api)
        await store.loadIfNeeded()
        XCTAssertFalse(store.hasLoaded)
        XCTAssertTrue(store.lastError?.isNetwork ?? false)

        MockURLProtocol.registry.reset { _ in MockReply.json(PreviewData.routesJSON) }
        await store.loadIfNeeded()
        XCTAssertTrue(store.hasLoaded)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testBorrarAvisaAlTablero() async throws {
        let (api, _) = makeMockAPI()
        MockURLProtocol.registry.reset { request in
            request.httpMethod == "DELETE" ? MockReply.json(PreviewData.routeDeletedJSON) : MockReply.json(PreviewData.routesJSON)
        }
        let store = RoutesStore(api: api)
        let changes = LockedBox<[RoutesChange]>([])
        store.onChange = { change in changes.withValue { $0.append(change) } }
        await store.load()
        try await store.delete(id: 5)
        XCTAssertEqual(changes.value, [.deleted(5)])
    }
}
