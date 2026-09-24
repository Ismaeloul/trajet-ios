import CoreLocation
import Foundation

/// Geocercas en las estaciones habituales, detrás de un protocolo (en los
/// tests y en la demo no hay).
///
/// Al entrar en una, iOS despierta la app unos segundos (aunque esté
/// cerrada): el modo trayecto pide el tablero UNA vez y pone al día la Live
/// Activity si hay una. Lo vigila el sistema con wifi y antenas, sin GPS:
/// casi no gasta. Solo con el permiso «Siempre».
@MainActor
protocol GeofenceMonitoring: AnyObject, Sendable {
    /// Se ha entrado en la geocerca de una estación (su id).
    var onEnter: (@MainActor (String) -> Void)? { get set }
    /// Las que se vigilan ahora.
    var monitoredIDs: Set<String> { get }
    /// Vigila exactamente estas. Las de `keeping` (aún sin coordenadas, p. ej.
    /// al arrancar sin el mapa) no se tocan si ya estaban.
    func monitor(_ stations: [WatchedStation], keeping: Set<String>) async
    /// Deja de vigilar todas.
    func stopAll() async
}

/// Sin geocercas (demo, tests, o mientras no se activen).
@MainActor
final class NoGeofences: GeofenceMonitoring {
    var onEnter: (@MainActor (String) -> Void)?
    private(set) var monitoredIDs: Set<String> = []

    init() {}

    func monitor(_ stations: [WatchedStation], keeping: Set<String>) async {
        monitoredIDs = Set(stations.map(\.id))
    }

    func stopAll() async {
        monitoredIDs = []
    }
}

/// Las de verdad, con `CLMonitor` (iOS 17).
///
/// El monitor se llama siempre igual («trajet.estaciones»): iOS guarda sus
/// condiciones entre arranques, y al despertar a la app por una geocerca
/// basta con volver a abrirlo y leer sus eventos. Por eso se abre al
/// arrancar si las geocercas están activas.
@MainActor
final class SystemGeofenceService: GeofenceMonitoring {

    nonisolated static let monitorName = "trajet.estaciones"
    /// Radio de cada geocerca. Con menos de ~150 m iOS avisa tarde o nunca
    /// (las antenas no dan para más); 200 m cubre la estación y sus accesos.
    nonisolated static let radius: CLLocationDistance = 200
    /// iOS no deja vigilar más de 20 condiciones por app.
    nonisolated static let maximum = 20
    /// Hay condiciones registradas de un arranque anterior (para no abrir el
    /// monitor sin necesidad cuando las geocercas están apagadas).
    nonisolated static let registeredKey = "trip.geofences.registered"

    var onEnter: (@MainActor (String) -> Void)?
    private(set) var monitoredIDs: Set<String> = []

    private var clMonitor: CLMonitor?
    private var opening: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    private var current: [String: WatchedStation] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Si iOS ha despertado a la app por una geocerca, el evento espera a
        // que se vuelva a abrir el monitor: se abre ya, sin esperar a las
        // rutas ni a los mapas (quien escucha, `onEnter`, se pone justo
        // después de crear esto, antes de que corra la tarea).
        if defaults.bool(forKey: Self.registeredKey) {
            Task { [weak self] in
                _ = await self?.openMonitor()
            }
        }
    }

    func monitor(_ stations: [WatchedStation], keeping: Set<String>) async {
        var wanted: [String: WatchedStation] = [:]
        for station in stations where station.point.isValid && wanted.count < Self.maximum {
            wanted[station.id] = station
        }
        let opened = await openMonitor()
        let existing = await opened.identifiers
        for id in existing where wanted[id] == nil && !keeping.contains(id) {
            await opened.remove(id)
        }
        for station in wanted.values where current[station.id] != station || !existing.contains(station.id) {
            // TODO-COMPILAR: firma de iOS 17 `add(_:identifier:assuming:)`
            // (la de la WWDC23). Si no casa, `add(_:identifier:)` a secas.
            let condition = CLMonitor.CircularGeographicCondition(center: station.point.coordinate,
                                                                   radius: Self.radius)
            await opened.add(condition, identifier: station.id, assuming: .unsatisfied)
        }
        current = wanted
        let now = await opened.identifiers
        monitoredIDs = Set(now)
        defaults.set(!now.isEmpty, forKey: Self.registeredKey)
    }

    func stopAll() async {
        // Sin monitor abierto y sin nada registrado de antes: nada que hacer
        // (no se abre el monitor para nada).
        guard clMonitor != nil || defaults.bool(forKey: Self.registeredKey) else { return }
        let opened = await openMonitor()
        for id in await opened.identifiers {
            await opened.remove(id)
        }
        current = [:]
        monitoredIDs = []
        defaults.set(false, forKey: Self.registeredKey)
    }

    /// Abre el monitor (una sola vez: iOS no admite dos abiertos con el mismo
    /// nombre) y se queda escuchando sus eventos.
    private func openMonitor() async -> CLMonitor {
        if let clMonitor { return clMonitor }
        if let opening { return await opening.value }
        let task = Task { await CLMonitor(Self.monitorName) }
        opening = task
        let opened = await task.value
        opening = nil
        if let clMonitor { return clMonitor }
        clMonitor = opened
        let handler: @Sendable (String) async -> Void = { [weak self] identifier in
            await self?.entered(identifier)
        }
        eventsTask = Task {
            await SystemGeofenceService.listen(to: opened, onEnter: handler)
        }
        return opened
    }

    private func entered(_ identifier: String) {
        onEnter?(identifier)
    }

    /// Los eventos se leen fuera del MainActor (el iterador del monitor no
    /// cruza de actor); solo el identificador (un String) vuelve a él.
    nonisolated private static func listen(to monitor: CLMonitor,
                                           onEnter: @escaping @Sendable (String) async -> Void) async {
        do {
            for try await event in await monitor.events where event.state == .satisfied {
                await onEnter(event.identifier)
            }
        } catch {
            // El flujo de eventos se ha cortado: se vuelve a abrir en el
            // próximo arranque.
        }
    }
}
