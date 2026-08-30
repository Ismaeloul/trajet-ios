import Foundation
import Observation
import SwiftUI

/// El estado del tablero.
///
/// Dos promesas de la app viven aquí:
///
///  1. **Nunca se borra la pantalla.** Si la API falla, se conserva el último
///     tablero bueno y lo que cambia es su antigüedad. Se guarda además en
///     disco, para que la primera apertura del día tampoco enseñe un hueco.
///  2. **Solo se refresca lo que se está mirando.** Son 1000 llamadas al día
///     por endpoint; en segundo plano el bucle se para en seco.
@MainActor
@Observable
final class BoardStore {

    /// Cada 30 s, que es lo que tarda el dato en moverse de verdad.
    static let refreshInterval: TimeInterval = 30

    private(set) var board: Board?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Ruta elegida a mano. Con nil manda el servidor, que sabe cuál toca
    /// según el día y la hora.
    private(set) var pinnedRouteId: Int?

    /// Cuándo toca el próximo refresco. La barra de progreso se dibuja a
    /// partir de esto, sin que el store tenga que latir a 60 fps.
    private(set) var nextRefreshAt: Date = .now.addingTimeInterval(refreshInterval)

    private let api: TrajetAPI
    private var loop: Task<Void, Never>?

    init(api: TrajetAPI) {
        self.api = api
        board = BoardCache.load()
    }

    // ---------------- ciclo de vida ----------------

    /// Arranca el refresco periódico. Idempotente: llamarlo dos veces no crea
    /// dos bucles.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let wait = self?.secondsUntilNextRefresh() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Para el bucle. Se llama al irse a segundo plano y al salir del tablero:
    /// refrescar lo que no se está mirando es tirar cuota.
    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func secondsUntilNextRefresh() -> TimeInterval {
        max(1, nextRefreshAt.timeIntervalSinceNow)
    }

    // ---------------- carga ----------------

    /// Trae el tablero. Un fallo deja en pantalla lo que hubiera y solo apunta
    /// el motivo: el tablero viejo con su edad es mejor que un hueco.
    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            nextRefreshAt = .now.addingTimeInterval(Self.refreshInterval)
        }
        do {
            let fresh = try await api.board(routeId: pinnedRouteId)
            board = fresh
            lastError = nil
            BoardCache.save(fresh)
        } catch {
            lastError = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Cambiar de ruta desde el título. Se refresca ya, sin esperar al ciclo.
    func select(routeId: Int?) {
        guard pinnedRouteId != routeId else { return }
        pinnedRouteId = routeId
        board = nil                  // el tablero anterior es de otra ruta
        Task { await refresh() }
    }

    /// La ruta que se está viendo, sea elegida a mano o automática.
    var currentRouteId: Int? { pinnedRouteId ?? board?.route?.id }

    /// Tras crear, editar o borrar una ruta el tablero puede haber cambiado.
    func invalidate() {
        if let pinnedRouteId, pinnedRouteId != board?.route?.id {
            self.pinnedRouteId = nil
        }
        Task { await refresh() }
    }
}

/// El último tablero bueno, en disco.
///
/// Se guarda el JSON y la hora de llegada por separado: si se recuperase sin
/// la hora, el tablero de anoche parecería recién hecho, que es justo la
/// mentira que la app promete no contar.
private enum BoardCache {

    private struct Entry: Codable {
        var board: Board
        var receivedAt: Date
    }

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("last-board.json")
    }

    static func save(_ board: Board) {
        guard let url else { return }
        let entry = Entry(board: board, receivedAt: board.receivedAt)
        guard let data = try? JSONEncoder.trajet.encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Board? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder.trajet.decode(Entry.self, from: data)
        else { return nil }
        var board = entry.board
        // Se restaura la hora real de llegada: lo que se enseña es viejo y la
        // pantalla tiene que decirlo.
        board.receivedAt = entry.receivedAt
        return board
    }
}
