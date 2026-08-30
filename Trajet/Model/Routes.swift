import Foundation

// Rutas guardadas: GET/POST/PUT/DELETE /api/routes

/// Cómo se define el horario de una ruta. Las tres formas acaban siendo una
/// franja en el servidor, pero se guarda cuál se eligió para poder enseñarla
/// tal como se pensó: "llego a las 09:00" no es "de 07:30 a 09:15".
enum TimeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrival, departure, window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrival: "Llego a"
        case .departure: "Salgo a"
        case .window: "Franja"
        }
    }
}

struct SavedLeg: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var seq: Int
    var lineId: String
    var lineCode: String
    var lineName: String
    var lineMode: String
    var lineColor: String
    var fromId: String
    var fromName: String
    var toId: String
    var toName: String
    var directions: [String]

    enum CodingKeys: String, CodingKey {
        case id, seq, lineId, lineCode, lineName, lineMode, lineColor
        case fromId, fromName, toId, toName, directions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = c.get(.id, 0)
        seq        = c.get(.seq, 0)
        lineId     = c.get(.lineId, "")
        lineCode   = c.get(.lineCode, "")
        lineName   = c.get(.lineName, "")
        lineMode   = c.get(.lineMode, "")
        lineColor  = c.get(.lineColor, "")
        fromId     = c.get(.fromId, "")
        fromName   = c.get(.fromName, "")
        toId       = c.get(.toId, "")
        toName     = c.get(.toName, "")
        directions = c.get(.directions, [])
    }

    var mode: TransportMode { TransportMode(rawMode: lineMode) }
}

struct SavedRoute: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var originId: String
    var originName: String
    var destId: String
    var destName: String
    var days: [Int]           // 0 = lunes
    var timeFrom: String
    var timeTo: String
    var timeMode: TimeMode
    var timeAt: String
    var durationMin: Int
    var position: Int
    var legs: [SavedLeg]

    enum CodingKeys: String, CodingKey {
        case id, name, originId, originName, destId, destName, days
        case timeFrom, timeTo, timeMode, timeAt, durationMin, position, legs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = c.get(.id, 0)
        name        = c.get(.name, "")
        originId    = c.get(.originId, "")
        originName  = c.get(.originName, "")
        destId      = c.get(.destId, "")
        destName    = c.get(.destName, "")
        days        = c.get(.days, [])
        timeFrom    = c.get(.timeFrom, "07:00")
        timeTo      = c.get(.timeTo, "10:00")
        timeMode    = c.get(.timeMode, TimeMode.window)
        timeAt      = c.get(.timeAt, "")
        durationMin = c.get(.durationMin, 0)
        position    = c.get(.position, 0)
        legs        = c.get(.legs, [])
    }

    /// El horario dicho como se definió: «llego 09:00», «salgo 08:00»
    /// o «07:00–10:00».
    var scheduleLabel: String {
        switch timeMode {
        case .arrival where !timeAt.isEmpty: "llego \(timeAt)"
        case .departure where !timeAt.isEmpty: "salgo \(timeAt)"
        default: "\(timeFrom)–\(timeTo)"
        }
    }

    /// «L M X J V» con los días marcados, en el orden de la semana española.
    var daysLabel: String {
        let letters = ["L", "M", "X", "J", "V", "S", "D"]
        let picked = days.sorted().compactMap { letters.indices.contains($0) ? letters[$0] : nil }
        if picked.count == 7 { return "todos los días" }
        if Set(days) == Set(0...4) { return "entre semana" }
        if Set(days) == Set([5, 6]) { return "fin de semana" }
        return picked.joined(separator: " ")
    }
}

struct RoutesResponse: Decodable, Sendable {
    var routes: [SavedRoute]
    var activeId: Int?

    enum CodingKeys: String, CodingKey { case routes, activeId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes   = c.get(.routes, [])
        activeId = c.opt(.activeId)
    }
}

// ---------------- lo que se manda al crear o editar ----------------

/// Cuerpo de POST/PUT /api/routes. Se codifica a snake_case.
struct RouteDraft: Encodable, Sendable {
    var name: String
    var originId: String
    var originName: String
    var destId: String
    var destName: String
    var days: [Int]
    var timeFrom: String
    var timeTo: String
    var timeMode: String
    var timeAt: String
    var durationMin: Int
    var legs: [LegDraft]

    struct LegDraft: Encodable, Sendable {
        var lineId: String
        var lineCode: String
        var lineName: String
        var lineMode: String
        var lineColor: String
        var fromId: String
        var fromName: String
        var toId: String
        var toName: String
        var directions: [String]
    }
}

// ---------------- buscador de paradas y líneas (editor manual) ----------------

struct StopLine: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var code: String
    var name: String
    var mode: String
    var color: String

    enum CodingKeys: String, CodingKey { case id, code, name, mode, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = c.get(.id, "")
        code  = c.get(.code, "")
        name  = c.get(.name, "")
        mode  = c.get(.mode, "")
        color = c.get(.color, "")
    }

    var transport: TransportMode { TransportMode(rawMode: mode) }
}

struct StopResult: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var city: String
    var lines: [StopLine]

    enum CodingKeys: String, CodingKey { case id, name, city, lines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = c.get(.id, "")
        name  = c.get(.name, "")
        city  = c.get(.city, "")
        lines = c.get(.lines, [])
    }
}

/// Una parada, una dirección postal o un sitio. Sirve de origen o destino.
struct PlaceResult: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var city: String
    var kind: String          // "parada" | "dirección" | "sitio"

    enum CodingKeys: String, CodingKey { case id, name, city, kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = c.get(.id, "")
        name = c.get(.name, "")
        city = c.get(.city, "")
        kind = c.get(.kind, "")
    }

    var symbol: String {
        switch kind {
        case "parada": "tram.fill"
        case "dirección": "house.fill"
        default: "mappin.circle.fill"
        }
    }
}
