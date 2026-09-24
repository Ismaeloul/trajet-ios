import Foundation
import Observation

/// Ajustes del modo trayecto y de las geocercas, guardados en UserDefaults
/// según se cambian (sin botón de guardar).
///
/// - `maxMinutes`: el trayecto se apaga solo a los 90 min (por defecto),
///   aunque no haya llegado: nunca se queda encendido siempre.
/// - `geofencesEnabled`: geocercas en las estaciones habituales. Solo
///   funcionan con el permiso «Siempre»; se piden desde Ajustes con
///   `TripController.requestAlwaysForGeofences()`.
/// - `watchedStationIDs`: las estaciones vigiladas (`stop_area:IDFM:…`).
///   Mientras no se toquen, son las de origen de las rutas guardadas.
@MainActor
@Observable
final class TripSettings {

    enum Key {
        static let maxMinutes = "trip.maxMinutes"
        static let geofences = "trip.geofences"
        static let watched = "trip.watchedStations"
        static let defaultWatched = "trip.defaultWatchedStations"
    }

    nonisolated static let defaultMaxMinutes = 90
    /// Lo que se deja elegir en Ajustes.
    nonisolated static let maxMinutesRange = 15...240

    /// El texto que acompaña al interruptor de las geocercas en Ajustes
    /// (antes de pedir el permiso «Siempre»).
    nonisolated static let geofenceExplanation =
        "Al llegar a una de tus estaciones habituales, Trajet se despierta unos segundos, "
        + "pide el tablero una vez y pone al día la Live Activity. Para eso iOS pide el permiso "
        + "de ubicación «Siempre». Casi no gasta batería: lo vigila el sistema, sin GPS."

    // Almacenado aparte y expuesto con propiedades calculadas, como en
    // ServerConfig: cada escritura se persiste sin mezclar `didSet` con el
    // macro @Observable.
    private var storedMaxMinutes: Int
    private var storedGeofences: Bool
    private var customWatched: Set<String>? = nil

    /// Las estaciones de origen de las rutas guardadas (las vigiladas por
    /// defecto). Se guardan para tenerlas al arrancar en segundo plano.
    private(set) var defaultWatchedStationIDs: Set<String>

    /// Donde se guarda todo (también el trayecto en marcha).
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Key.maxMinutes)
        storedMaxMinutes = stored == 0 ? Self.defaultMaxMinutes : Self.clamp(stored)
        storedGeofences = defaults.bool(forKey: Key.geofences)
        if let list = defaults.stringArray(forKey: Key.watched) {
            customWatched = Set(list)
        }
        defaultWatchedStationIDs = Set(defaults.stringArray(forKey: Key.defaultWatched) ?? [])
    }

    /// Tiempo máximo de un trayecto, en minutos.
    var maxMinutes: Int {
        get { storedMaxMinutes }
        set {
            let value = Self.clamp(newValue)
            storedMaxMinutes = value
            defaults.set(value, forKey: Key.maxMinutes)
        }
    }

    /// Geocercas en las estaciones vigiladas.
    var geofencesEnabled: Bool {
        get { storedGeofences }
        set {
            storedGeofences = newValue
            defaults.set(newValue, forKey: Key.geofences)
        }
    }

    /// Estaciones vigiladas. Si nunca se han tocado, las de origen de las
    /// rutas guardadas; al escribir, pasan a ser la lista del usuario.
    var watchedStationIDs: Set<String> {
        get { customWatched ?? defaultWatchedStationIDs }
        set {
            customWatched = newValue
            defaults.set(newValue.sorted(), forKey: Key.watched)
        }
    }

    /// La lista es la de por defecto (no se ha tocado).
    var usesDefaultStations: Bool { customWatched == nil }

    /// Vuelve a las de por defecto.
    func resetWatchedStations() {
        customWatched = nil
        defaults.removeObject(forKey: Key.watched)
    }

    /// Recalcula las de por defecto con las rutas guardadas. Solo escribe si
    /// cambian (lo llama el modo trayecto cada vez que cambian las rutas).
    func refreshDefaultStations(from routes: [SavedRoute]) {
        let ids = Self.defaultStationIDs(for: routes)
        guard ids != defaultWatchedStationIDs else { return }
        defaultWatchedStationIDs = ids
        defaults.set(ids.sorted(), forKey: Key.defaultWatched)
    }

    // MARK: - Reglas

    /// La estación de subida del primer tramo de cada ruta.
    nonisolated static func defaultStationIDs(for routes: [SavedRoute]) -> Set<String> {
        Set(routes.compactMap { route -> String? in
            guard let first = route.legs.first, !first.fromId.isEmpty else { return nil }
            return first.fromId
        })
    }

    /// «stop_area:IDFM:71370» → «71370» (la `zdc` del mapa).
    nonisolated static func zdc(of stationID: String) -> String {
        stationID.split(separator: ":").last.map(String.init) ?? stationID
    }

    nonisolated static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, maxMinutesRange.lowerBound), maxMinutesRange.upperBound)
    }

    /// Preferencias de usar y tirar para la demo (`-demo`).
    static func demoDefaults() -> UserDefaults {
        let suite = "com.ismaeloul.trajet.demo.trip"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
