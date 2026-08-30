import Foundation
import Observation

/// Las rutas guardadas. Las comparten el selector del título del tablero y la
/// pantalla de rutas, así que hay una sola copia y una sola recarga.
@MainActor
@Observable
final class RoutesStore {

    private(set) var routes: [SavedRoute] = []
    /// Cuál toca ahora según el servidor (día de la semana y franja horaria).
    private(set) var activeId: Int?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var hasLoadedOnce = false

    private let api: TrajetAPI

    init(api: TrajetAPI) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }
        do {
            let reply = try await api.routes()
            routes = reply.routes
            activeId = reply.activeId
            lastError = nil
        } catch {
            lastError = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Solo recarga si no hay nada: evita una llamada por cada vez que se
    /// abre la pestaña.
    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await load()
    }

    func delete(id: Int) async throws {
        try await api.deleteRoute(id: id)
        routes.removeAll { $0.id == id }
    }

    @discardableResult
    func create(_ draft: RouteDraft) async throws -> Int {
        let id = try await api.createRoute(draft)
        await load()
        return id
    }

    func update(id: Int, _ draft: RouteDraft) async throws {
        try await api.updateRoute(id: id, draft)
        await load()
    }

    func route(id: Int?) -> SavedRoute? {
        guard let id else { return nil }
        return routes.first { $0.id == id }
    }
}

/// El contenedor de la app: una sola configuración, un solo cliente, unos
/// stores que se pasan por el entorno.
@MainActor
@Observable
final class AppModel {
    let config: ServerConfig
    let api: TrajetAPI
    let board: BoardStore
    let routes: RoutesStore

    init() {
        let config = ServerConfig()
        let api = TrajetAPI(config: config)
        self.config = config
        self.api = api
        self.board = BoardStore(api: api)
        self.routes = RoutesStore(api: api)
    }
}
