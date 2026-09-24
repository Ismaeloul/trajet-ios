import CoreLocation
import Foundation

// Tipos del modo trayecto y del mapa que cruzan de un sitio a otro: todos
// `Sendable` y sin nada de CoreLocation dentro (las coordenadas van como
// Double), para que pasen entre actores sin discusión.

// MARK: - Puntos y ubicación

/// Un punto del mapa en grados. Es lo que viaja entre el servicio de
/// ubicación, el modo trayecto, MKDirections y las vistas.
struct GeoPoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// El mapa manda 0,0 cuando le falta la coordenada: eso no es un sitio.
    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    /// Distancia en metros (semiverseno sobre una esfera de 6371 km). A las
    /// distancias del modo trayecto el error es de centímetros.
    func distance(to other: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

extension MapLegStop {
    var geoPoint: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
}

extension MapStation {
    var geoPoint: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
}

extension MapAccess {
    var geoPoint: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
}

extension MapPoint {
    var geoPoint: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
}

extension MapTrack {
    var geoPoint: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
}

/// Una posición del GPS, ya sin CLLocation.
struct TripLocation: Equatable, Sendable {
    var point: GeoPoint
    /// Radio de incertidumbre en metros; negativo = no vale.
    var horizontalAccuracy: Double
    var timestamp: Date

    init(point: GeoPoint, horizontalAccuracy: Double, timestamp: Date) {
        self.point = point
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        self.point = GeoPoint(location.coordinate)
        self.horizontalAccuracy = location.horizontalAccuracy
        self.timestamp = location.timestamp
    }
}

/// El permiso de ubicación, reducido a lo que le importa a Trajet.
enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    /// Denegado o restringido (control parental, MDM).
    case denied
    case whenInUse
    case always

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted, .denied: self = .denied
        case .authorizedWhenInUse: self = .whenInUse
        case .authorizedAlways: self = .always
        @unknown default: self = .denied
        }
    }

    /// Basta para el modo trayecto (con la sesión de segundo plano).
    var allowsTrip: Bool { self == .whenInUse || self == .always }
}

// MARK: - Máquina de estados

/// Por qué terminó un trayecto.
enum TripEndReason: Equatable, Sendable {
    /// A menos de ~150 m de la estación de destino.
    case arrived
    /// Pasó `TripSettings.maxMinutes`.
    case timeLimit
    /// «Parar trayecto», en la app o en la Live Activity.
    case manual
    /// Reservado. Hoy un permiso denegado NO termina el trayecto: sigue sin
    /// GPS (sin llegada automática) hasta el tiempo máximo.
    case permissionDenied
    /// Algo falló y no se puede seguir.
    case failed(String)

    /// Lo que se dice al terminar.
    var summary: String {
        switch self {
        case .arrived: "Trayecto terminado: has llegado."
        case .timeLimit: "Trayecto terminado: se pasó el tiempo máximo."
        case .manual: "Trayecto parado."
        case .permissionDenied: "Trayecto terminado: sin permiso de ubicación."
        case .failed(let detail): detail.isEmpty ? "El trayecto se ha parado." : "El trayecto se ha parado: \(detail)"
        }
    }
}

/// Un trayecto en marcha.
struct TripSession: Equatable, Sendable {
    var routeID: Int
    var startedAt: Date
    /// Se apaga solo aquí (inicio + `maxMinutes`).
    var deadline: Date
    /// Hay permiso de ubicación: se sigue el GPS y hay llegada automática.
    /// Sin él, el trayecto sigue igual pero solo termina por tiempo o a mano.
    var usesLocation: Bool
    /// El tramo en el que se va (`Leg.seq`). Avanza con las geocercas del
    /// propio trayecto: al llegar cerca de la subida de un tramo siguiente.
    var currentLegSeq: Int
    /// Ya ha estado lejos del destino: a partir de aquí, acercarse cuenta
    /// como llegar (no se «llega» por empezar al lado del destino).
    var armed: Bool
    var lastFix: TripLocation?
    /// Metros hasta el destino con la última posición.
    var distanceToDestination: Double?

    init(routeID: Int, startedAt: Date, deadline: Date, usesLocation: Bool,
         currentLegSeq: Int = 0, armed: Bool = false, lastFix: TripLocation? = nil,
         distanceToDestination: Double? = nil) {
        self.routeID = routeID
        self.startedAt = startedAt
        self.deadline = deadline
        self.usesLocation = usesLocation
        self.currentLegSeq = currentLegSeq
        self.armed = armed
        self.lastFix = lastFix
        self.distanceToDestination = distanceToDestination
    }
}

/// apagado → pidiendo permiso → activo → terminado (docs/arquitectura.md §6).
enum TripState: Equatable, Sendable {
    case off
    case askingPermission
    case active(TripSession)
    case ended(TripEndReason)
}

// MARK: - Live Activity (lo que la app le pasa)

/// Cómo está la conexión con el servidor, para la Live Activity.
enum TripConnection: Equatable, Sendable {
    case ok
    /// Fallo de red.
    case offline
    /// El servidor no tiene clave de PRIM (`prim_key_missing`).
    case noKey

    init(issue: BoardIssue?) {
        switch issue {
        case .offline?: self = .offline
        case .noKey?: self = .noKey
        case .keyRejected?, .quotaExhausted?, .upstream?, .notPaired?, .other?, nil: self = .ok
        }
    }
}

/// Todo lo que hace falta para escribir la Live Activity. El tablero va
/// recortado desde el tramo en el que se va (`legOffset`).
struct TripActivitySnapshot: Equatable, Sendable {
    var routeID: Int
    var routeName: String
    var board: Board
    var receivedAt: Date
    /// Tramos que ya quedan atrás (se quitaron de `board.legs`).
    var legOffset: Int
    /// Tramos de la ruta entera.
    var legCount: Int
    var connection: TripConnection
    var now: Date
}

/// Lo único que merece una alerta de la Live Activity (decisiones §5.4):
/// vía publicada, cambio de vía, tren cancelado y línea cortada. Nunca un
/// cambio de minuto.
struct TripAlert: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case lineCut
        case cancelled
        case platformPublished
        case platformChanged
    }

    var kind: Kind
    var title: String
    var body: String

    /// Compara el tramo que se enseñaba con el nuevo (el mismo `seq`).
    static func detect(previous: Leg?, current: Leg) -> TripAlert? {
        guard let previous, previous.seq == current.seq else { return nil }
        let code = current.lineCode

        // 1. La línea se corta.
        if current.status.level >= 2, previous.status.level < 2 {
            return TripAlert(kind: .lineCut, title: "Línea \(code) cortada",
                             body: "Sin circulación. Toca para ver alternativas.")
        }

        // 2. Un tren que se esperaba, cancelado.
        for dep in current.departures where dep.isCancelled {
            let before = previous.departures.first { $0.id == dep.id }
            if let before, !before.isCancelled {
                return TripAlert(kind: .cancelled, title: "Tren cancelado",
                                 body: "El \(code) de las \(dep.at), cancelado.")
            }
        }

        // 3. La vía del tren que se enseña (el primero que no está cancelado).
        guard current.showsPlatform,
              let first = current.departures.first(where: { !$0.isCancelled }),
              first.hasRealPlatform, let platform = first.platform
        else { return nil }
        let before = previous.departures.first { $0.id == first.id }
        let oldPlatform = before?.platform ?? ""
        if before != nil, oldPlatform.isEmpty {
            return TripAlert(kind: .platformPublished, title: "Vía \(platform)",
                             body: "\(code) de las \(first.at) · anunciada ahora")
        }
        if !oldPlatform.isEmpty, oldPlatform != platform {
            return TripAlert(kind: .platformChanged, title: "Vía \(platform)",
                             body: "Cambio de vía · antes \(oldPlatform)")
        }
        return nil
    }
}

// MARK: - Estaciones vigiladas (geocercas)

/// Una estación con coordenadas, lista para una geocerca.
struct WatchedStation: Hashable, Sendable, Identifiable {
    /// `stop_area:IDFM:NNNNN` (el `from_id` de los tramos).
    var id: String
    var name: String
    var point: GeoPoint
}

/// Una estación que se puede vigilar (para la lista de Ajustes).
struct StationOption: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
}

// MARK: - El trayecto en disco

/// Lo mínimo para retomar un trayecto si el sistema cierra la app: al volver
/// a abrirla sigue (si no ha pasado el tiempo máximo) y su Live Activity
/// también.
struct TripRecord: Codable, Equatable, Sendable {
    var routeID: Int
    var startedAt: Date
    var deadline: Date
    var usesLocation: Bool
    var currentLegSeq: Int
    var armed: Bool

    init(_ session: TripSession) {
        routeID = session.routeID
        startedAt = session.startedAt
        deadline = session.deadline
        usesLocation = session.usesLocation
        currentLegSeq = session.currentLegSeq
        armed = session.armed
    }
}

/// Dónde se guarda el trayecto en marcha (UserDefaults).
struct TripRecordStore {
    static let key = "trip.running"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TripRecord? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(TripRecord.self, from: data)
    }

    func save(_ record: TripRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
