import Foundation
import Observation

/// La salud del servidor para Ajustes: clave de PRIM, cuota por endpoint
/// (R46), traductor, recolector y este dispositivo. No gasta cuota. Se pide
/// al abrir Ajustes y con «Comprobar ahora»; nunca en bucle.
@MainActor
@Observable
final class HealthStore {

    private(set) var health: ServerHealth?
    /// Este iPhone tal como lo ve el servidor.
    private(set) var device: DeviceInfo?
    private(set) var isLoading = false
    private(set) var lastError: APIError?
    private(set) var checkedAt: Date?

    private let api: TrajetAPI
    private let clock: @Sendable () -> Date

    init(api: TrajetAPI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.clock = now
    }

    /// Pide la salud (y el dispositivo, que tampoco gasta cuota).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            health = try await api.health()
            lastError = nil
            checkedAt = clock()
        } catch is CancellationError {
            return
        } catch let error as APIError {
            lastError = error
        } catch {
            lastError = .network(error.localizedDescription)
        }
        if let me = try? await api.me() { device = me }
    }

    /// Endpoint del tablero (el que se enseña en el pie, R46).
    var boardQuota: QuotaEndpoint? { health?.quota.endpoint("stop-monitoring") }

    func reset() {
        health = nil
        device = nil
        lastError = nil
        checkedAt = nil
    }
}
