import CoreLocation
import Foundation

// Mapa de una ruta: GET /api/v1/routes/{id}/map (`RouteMap` del contrato).
// Datos abiertos de IDFM recortados al tramo de cada línea: trazado
// (polilínea codificada, precisión 5, dos niveles), paradas, andenes, vías de
// las estaciones SNCF, accesos con metros y segundos hasta cada andén y el
// tiempo mínimo de transbordo. No gasta cuota de PRIM.
//
// Las coordenadas se guardan como `lat`/`lon` (Double) para que todo sea
// Sendable y Hashable; `coordinate` las da como CLLocationCoordinate2D.

/// Un punto con nombre (paradas intermedias de una línea).
struct MapPoint: Codable, Hashable, Sendable {
    var name: String
    var lat: Double
    var lon: Double

    enum CodingKeys: String, CodingKey { case name, lat, lon }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.get(.name, "")
        lat  = c.get(.lat, 0)
        lon  = c.get(.lon, 0)
    }

    init(name: String, lat: Double, lon: Double) {
        self.name = name
        self.lat = lat
        self.lon = lon
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Parada de subida o de bajada de una línea (`MapLegStop`).
struct MapLegStop: Codable, Hashable, Sendable {
    var zdc: String               // zona de correspondencia (stop_area:IDFM:<zdc>)
    var stopId: String?
    var name: String
    var lat: Double
    var lon: Double

    enum CodingKeys: String, CodingKey { case zdc, stopId, name, lat, lon }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zdc    = c.text(.zdc) ?? ""
        stopId = c.opt(.stopId)
        name   = c.get(.name, "")
        lat    = c.get(.lat, 0)
        lon    = c.get(.lon, 0)
    }

    init(zdc: String, stopId: String? = nil, name: String, lat: Double, lon: Double) {
        self.zdc = zdc
        self.stopId = stopId
        self.name = name
        self.lat = lat
        self.lon = lon
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Trazado de una línea en dos niveles de detalle.
struct MapPath: Codable, Hashable, Sendable {
    struct Tolerance: Codable, Hashable, Sendable {
        var coarse: Double
        var fine: Double

        enum CodingKeys: String, CodingKey { case coarse, fine }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            coarse = c.get(.coarse, 20)
            fine   = c.get(.fine, 2)
        }

        init(coarse: Double = 20, fine: Double = 2) {
            self.coarse = coarse
            self.fine = fine
        }
    }

    var encoding: String          // "polyline5"
    var coarse: String            // simplificada a 20 m (zoom ≤ 13)
    var fine: String              // simplificada a 2 m (zoom 14–16)
    var toleranceM: Tolerance

    enum CodingKeys: String, CodingKey { case encoding, coarse, fine, toleranceM }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        encoding   = c.get(.encoding, "polyline5")
        coarse     = c.get(.coarse, "")
        fine       = c.get(.fine, "")
        toleranceM = c.get(.toleranceM, Tolerance())
    }

    init(coarse: String, fine: String, toleranceM: Tolerance = Tolerance()) {
        self.encoding = "polyline5"
        self.coarse = coarse
        self.fine = fine
        self.toleranceM = toleranceM
    }

    var coarseCoordinates: [CLLocationCoordinate2D] { Polyline.decode(coarse) }
    var fineCoordinates: [CLLocationCoordinate2D] { Polyline.decode(fine.isEmpty ? coarse : fine) }
}

/// Una línea de la ruta, recortada a su tramo (`MapLine`).
struct MapLine: Codable, Hashable, Identifiable, Sendable {
    enum Mode: String, Codable, Sendable {
        case rail, metro, tram, bus, other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Mode(rawValue: raw) ?? .other
        }
    }

    var seq: Int                  // el tramo del tablero (Leg.seq)
    var lineId: String
    var code: String
    var mode: Mode
    var color: String             // «#RRGGBB»
    var textColor: String         // «#RRGGBB»
    var from: MapLegStop
    var to: MapLegStop
    /// nil si aún no hay trazado: la app une las paradas con una recta discreta.
    var path: MapPath?
    var lengthM: Int?
    var via: [MapPoint]           // paradas intermedias, en orden
    var source: String            // gtfs | ferre | recta | none

    enum CodingKeys: String, CodingKey {
        case seq, lineId, code, mode, color, textColor, from, to, path, lengthM, via, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq       = c.get(.seq, 0)
        lineId    = c.get(.lineId, "")
        code      = c.get(.code, "")
        mode      = c.get(.mode, Mode.other)
        color     = c.get(.color, "")
        textColor = c.get(.textColor, "")
        from      = c.get(.from, MapLegStop(zdc: "", name: "", lat: 0, lon: 0))
        to        = c.get(.to, MapLegStop(zdc: "", name: "", lat: 0, lon: 0))
        path      = c.opt(.path)
        lengthM   = c.opt(.lengthM)
        via       = c.get(.via, [])
        source    = c.get(.source, "none")
    }

    var id: Int { seq }

    /// El trazado a pintar: el fino si lo hay; si no, la recta entre paradas
    /// pasando por las intermedias.
    func coordinates(fine: Bool = true) -> [CLLocationCoordinate2D] {
        if let path {
            let pts = fine ? path.fineCoordinates : path.coarseCoordinates
            if pts.count >= 2 { return pts }
        }
        return [from.coordinate] + via.map(\.coordinate) + [to.coordinate]
    }

    /// No hay trazado de verdad: se pinta la recta discreta.
    var isStraightLine: Bool { path == nil || source == "recta" || source == "none" }
}

/// Un andén (`MapPlatform`), con el id de SIRI «STIF:StopPoint:Q:<arrid>:».
struct MapPlatform: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var line: String?
    var name: String?
    var lat: Double
    var lon: Double

    enum CodingKeys: String, CodingKey { case id, line, name, lat, lon }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = c.get(.id, "")
        line = c.opt(.line)
        name = c.opt(.name)
        lat  = c.get(.lat, 0)
        lon  = c.get(.lon, 0)
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Una vía con coordenadas (solo estaciones SNCF).
struct MapTrack: Codable, Hashable, Identifiable, Sendable {
    var voie: String
    var lat: Double
    var lon: Double

    enum CodingKeys: String, CodingKey { case voie, lat, lon }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voie = c.text(.voie) ?? ""
        lat  = c.get(.lat, 0)
        lon  = c.get(.lon, 0)
    }

    var id: String { voie }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Estación de la ruta (`MapStation`): subida, transbordo o destino.
struct MapStation: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case origin, transfer, destination, other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Role(rawValue: raw) ?? .other
        }
    }

    var zdc: String
    var name: String
    var lat: Double
    var lon: Double
    var role: Role
    var platforms: [MapPlatform]
    var tracks: [MapTrack]

    enum CodingKeys: String, CodingKey { case zdc, name, lat, lon, role, platforms, tracks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zdc       = c.text(.zdc) ?? ""
        name      = c.get(.name, "")
        lat       = c.get(.lat, 0)
        lon       = c.get(.lon, 0)
        role      = c.get(.role, Role.other)
        platforms = c.get(.platforms, [])
        tracks    = c.get(.tracks, [])
    }

    var id: String { zdc }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// La vía con ese número, para señalarla en el mapa cuando se publica.
    func track(_ voie: String) -> MapTrack? { tracks.first { $0.voie == voie } }
}

/// Lo que se tarda andando de un acceso a un andén (pathways.txt).
struct MapAccessPath: Codable, Hashable, Sendable {
    var stopId: String
    var m: Double?                // metros
    var s: Int?                   // segundos

    enum CodingKeys: String, CodingKey { case stopId, m, s }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stopId = c.get(.stopId, "")
        m      = c.opt(.m)
        s      = c.opt(.s)
    }
}

/// Un acceso a la estación (`MapAccess`).
struct MapAccess: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var zdc: String
    var name: String
    var number: String?
    var entry: Bool
    var exit: Bool
    var lat: Double
    var lon: Double
    var toStop: [MapAccessPath]

    enum CodingKeys: String, CodingKey { case id, zdc, name, number, entry, exit, lat, lon, toStop }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = c.text(.id) ?? ""
        zdc    = c.text(.zdc) ?? ""
        name   = c.get(.name, "")
        number = c.text(.number)
        entry  = c.get(.entry, true)
        exit   = c.get(.exit, true)
        lat    = c.get(.lat, 0)
        lon    = c.get(.lon, 0)
        toStop = c.get(.toStop, [])
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Transbordo entre dos tramos (`MapTransfer`). No hay geometría abierta del
/// camino entre andenes: solo el tiempo mínimo.
struct MapTransfer: Codable, Hashable, Sendable {
    var zdc: String
    var fromSeq: Int
    var toSeq: Int
    var minTransferS: Int?

    enum CodingKeys: String, CodingKey { case zdc, fromSeq, toSeq, minTransferS }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zdc          = c.text(.zdc) ?? ""
        fromSeq      = c.get(.fromSeq, 0)
        toSeq        = c.get(.toSeq, 0)
        minTransferS = c.opt(.minTransferS)
    }
}

/// `RouteMap`: el mapa entero de una ruta.
struct RouteMap: Codable, Hashable, Sendable {
    var routeId: Int
    var generatedAt: String
    /// Se está calculando en segundo plano: volver a pedir en unos segundos.
    var pending: Bool
    /// El portal de IDFM falló: es lo último que se guardó.
    var stale: Bool
    var lines: [MapLine]
    var stations: [MapStation]
    var accesses: [MapAccess]
    var transfers: [MapTransfer]
    var sources: [String: String]
    var license: String

    enum CodingKeys: String, CodingKey {
        case routeId, generatedAt, pending, stale, lines, stations, accesses
        case transfers, sources, license
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routeId     = c.get(.routeId, 0)
        generatedAt = c.get(.generatedAt, "")
        pending     = c.get(.pending, false)
        stale       = c.get(.stale, false)
        lines       = c.get(.lines, [])
        stations    = c.get(.stations, [])
        accesses    = c.get(.accesses, [])
        transfers   = c.get(.transfers, [])
        sources     = c.get(.sources, [:])
        license     = c.get(.license, "")
    }

    func line(seq: Int) -> MapLine? { lines.first { $0.seq == seq } }
    func station(zdc: String) -> MapStation? { stations.first { $0.zdc == zdc } }

    /// Accesos de una estación.
    func accesses(zdc: String) -> [MapAccess] { accesses.filter { $0.zdc == zdc } }

    /// Todas las coordenadas que hay que encuadrar.
    var allCoordinates: [CLLocationCoordinate2D] {
        lines.flatMap { $0.coordinates(fine: false) } + stations.map(\.coordinate)
    }
}
