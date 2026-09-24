import Foundation
import Observation

/// Las rutas guardadas. Las comparten el selector del título del tablero, la
/// pantalla de rutas y el planificador: una sola copia y una sola carga (R41).
@MainActor
@Observable
final class RoutesStore {

    private(set) var routes: [SavedRoute] = []
    /// Cuál toca ahora según el servidor (día de la semana y franja).
    private(set) var activeID: Int?
    private(set) var isLoading = false
    /// El último error al cargar (se enseña; no se confunde con «no hay rutas»).
    private(set) var lastError: APIError?
    /// Ya se ha cargado bien al menos una vez. Si la carga falla, sigue en
    /// false y la siguiente `loadIfNeeded()` vuelve a probar.
    private(set) var hasLoaded = false

    /// Avisa de cada cambio (lo conecta `AppServices` con el tablero, R39).
    @ObservationIgnored var onChange: (@MainActor (RoutesChange) -> Void)?

    private let api: TrajetAPI
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(api: TrajetAPI) {
        self.api = api
    }

    /// Recarga. Si ya hay una carga en marcha, espera a esa (una sola llamada).
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Solo carga si no hay nada: evita una llamada por cada vez que se abre
    /// una pantalla (R41).
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let reply = try await api.routes()
            routes = reply.routes
            activeID = reply.activeId
            lastError = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch let error as APIError {
            lastError = error
        } catch {
            lastError = .network(error.localizedDescription)
        }
    }

    func route(id: Int?) -> SavedRoute? {
        guard let id else { return nil }
        return routes.first { $0.id == id }
    }

    var activeRoute: SavedRoute? { route(id: activeID) }

    /// Crea una ruta a mano. Devuelve la ruta guardada.
    @discardableResult
    func create(_ draft: RouteDraft) async throws -> SavedRoute? {
        let saved = try await api.createRoute(draft)
        await load()
        onChange?(.created(saved.id))
        return saved.route ?? route(id: saved.id)
    }

    /// Reemplaza una ruta (cabecera y tramos).
    @discardableResult
    func update(id: Int, _ draft: RouteDraft) async throws -> SavedRoute? {
        let saved = try await api.updateRoute(id: id, draft)
        await load()
        onChange?(.updated(id))
        return saved.route ?? route(id: id)
    }

    /// Borra una ruta. Si era la fijada en el tablero, este vuelve a la
    /// automática (R44).
    func delete(id: Int) async throws {
        do {
            try await api.deleteRoute(id: id)
        } catch APIError.notFound {
            // Ya no estaba: para la lista es lo mismo.
        }
        routes.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
        onChange?(.deleted(id))
        await load()
    }

    /// Guarda una opción del planificador. Si hay tramos sin sentido
    /// (`withoutDirection`), quien llama tiene que decirlo (R33).
    func saveFromPlan(_ request: PlanSaveRequest) async throws -> PlanSaveResponse {
        let saved = try await api.routeFromPlan(request)
        await load()
        onChange?(.created(saved.id))
        return saved
    }

    /// Al desemparejar.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        routes = []
        activeID = nil
        lastError = nil
        hasLoaded = false
    }
}
