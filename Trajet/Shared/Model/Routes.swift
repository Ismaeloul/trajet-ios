import Foundation

// Rutas guardadas: GET/POST/PUT/DELETE /api/v1/routes (`RouteList`,
// `Route`, `RouteLeg`, `RouteInput`, `RouteSaved`, `RouteDeleted` del
// contrato) y el buscador del editor manual (`StopSearch`, `StopLines`,
// `Directions`, `PlaceSearch`).

/// Cómo se define el horario de una ruta. Las tres formas acaban siendo una
/// franja en el servidor, pero se guarda cuál se eligió para poder enseñarla
/// tal como se pensó (R35): "llego a las 09:00" no es "de 07:30 a 09:15".
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

/// Un tramo guardado (`RouteLeg`).
struct SavedLeg: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var routeId: Int
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
    /// Destinos (texto SIRI) que cuentan como mi sentido. Vacío = todos (R32).
    var directions: [String]

    enum CodingKeys: String, CodingKey {
        case id, routeId, seq, lineId, lineCode, lineName, lineMode, lineColor
        case fromId, fromName, toId, toName, directions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = c.get(.id, 0)
        routeId    = c.get(.routeId, 0)
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

    /// Sin sentido elegido se enseñan todos los pasos de la línea (R32).
    var hasDirection: Bool { !directions.isEmpty }
}

/// Una ruta guardada (`Route`).
struct SavedRoute: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var originId: String
    var originName: String
    var destId: String
    var destName: String
    var days: [Int]           // 0 = lunes (R36)
    var timeFrom: String
    var timeTo: String
    var timeMode: TimeMode
    var timeAt: String
    var durationMin: Int
    var position: Int
    var createdAt: String
    var legs: [SavedLeg]

    enum CodingKeys: String, CodingKey {
        case id, name, originId, originName, destId, destName, days
        case timeFrom, timeTo, timeMode, timeAt, durationMin, position, createdAt, legs
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
        createdAt   = c.get(.createdAt, "")
        let rawLegs: [SavedLeg] = c.get(.legs, [])
        legs        = rawLegs.sorted { $0.seq < $1.seq }
    }

    /// El horario dicho como se definió (R35): «llego 09:00», «salgo 08:00»
    /// o «07:00–10:00».
    var scheduleLabel: String {
        switch timeMode {
        case .arrival where !timeAt.isEmpty: "llego \(timeAt)"
        case .departure where !timeAt.isEmpty: "salgo \(timeAt)"
        default: "\(timeFrom)–\(timeTo)"
        }
    }

    /// Los días en español (R36): «todos los días», «entre semana», «fin de
    /// semana» o las letras «L M X J V S D» de los marcados.
    var daysLabel: String {
        let letters = ["L", "M", "X", "J", "V", "S", "D"]
        let picked = Set(days).sorted().compactMap { letters.indices.contains($0) ? letters[$0] : nil }
        if picked.count == 7 { return "todos los días" }
        if Set(days) == Set(0...4) { return "entre semana" }
        if Set(days) == Set([5, 6]) { return "fin de semana" }
        return picked.joined(separator: " ")
    }

    /// Tramos que se ven en los dos sentidos porque no tienen ninguno elegido.
    var legsWithoutDirection: [SavedLeg] { legs.filter { !$0.hasDirection } }
}

/// `RouteList`: las rutas y la que elegiría el tablero ahora.
struct RoutesResponse: Decodable, Hashable, Sendable {
    var routes: [SavedRoute]
    var activeId: Int?

    enum CodingKeys: String, CodingKey { case routes, activeId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes   = c.get(.routes, [])
        activeId = c.opt(.activeId)
    }

    init(routes: [SavedRoute], activeId: Int?) {
        self.routes = routes
        self.activeId = activeId
    }
}

/// `RouteSaved`: respuesta de POST (201) y PUT (200).
struct RouteSaved: Decodable, Hashable, Sendable {
    var id: Int
    var route: SavedRoute?

    enum CodingKeys: String, CodingKey { case id, route }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = c.get(.id, 0)
        route = c.opt(.route)
    }
}

/// `RouteDeleted`: `{"deleted": <id>}`.
struct RouteDeleted: Decodable, Hashable, Sendable {
    var deleted: Int

    enum CodingKeys: String, CodingKey { case deleted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deleted = c.get(.deleted, 0)
    }
}

// ---------------- lo que se manda al crear o editar ----------------

/// Cuerpo de POST/PUT /api/v1/routes (`RouteInput`). Se codifica a snake_case
/// con `JSONEncoder.trajet`.
struct RouteDraft: Encodable, Hashable, Sendable {
    var name: String
    var originId: String
    var originName: String
    var destId: String
    var destName: String
    var days: [Int]
    var timeFrom: String
    var timeTo: String
    var timeMode: TimeMode
    var timeAt: String
    var durationMin: Int
    var position: Int
    var legs: [LegDraft]

    /// `RouteLegInput`.
    struct LegDraft: Encodable, Hashable, Sendable {
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

        init(lineId: String, lineCode: String, lineName: String, lineMode: String,
             lineColor: String, fromId: String, fromName: String, toId: String = "",
             toName: String = "", directions: [String] = []) {
            self.lineId = lineId
            self.lineCode = lineCode
            self.lineName = lineName
            self.lineMode = lineMode
            self.lineColor = lineColor
            self.fromId = fromId
            self.fromName = fromName
            self.toId = toId
            self.toName = toName
            self.directions = directions
        }

        /// El tramo tal como está guardado, para editarlo.
        init(_ leg: SavedLeg) {
            self.init(lineId: leg.lineId, lineCode: leg.lineCode, lineName: leg.lineName,
                      lineMode: leg.lineMode, lineColor: leg.lineColor, fromId: leg.fromId,
                      fromName: leg.fromName, toId: leg.toId, toName: leg.toName,
                      directions: leg.directions)
        }
    }

    /// Ruta nueva: lunes a viernes, «llego a las 09:00» (R36).
    init(name: String = "", originId: String = "", originName: String = "",
         destId: String = "", destName: String = "", days: [Int] = [0, 1, 2, 3, 4],
         timeFrom: String = "07:00", timeTo: String = "10:00",
         timeMode: TimeMode = .arrival, timeAt: String = "09:00",
         durationMin: Int = 0, position: Int = 0, legs: [LegDraft] = []) {
        self.name = name
        self.originId = originId
        self.originName = originName
        self.destId = destId
        self.destName = destName
        self.days = days
        self.timeFrom = timeFrom
        self.timeTo = timeTo
        self.timeMode = timeMode
        self.timeAt = timeAt
        self.durationMin = durationMin
        self.position = position
        self.legs = legs
    }

    /// Una ruta guardada, para editarla y mandarla entera con PUT.
    init(_ route: SavedRoute) {
        self.init(name: route.name, originId: route.originId, originName: route.originName,
                  destId: route.destId, destName: route.destName, days: route.days,
                  timeFrom: route.timeFrom, timeTo: route.timeTo, timeMode: route.timeMode,
                  timeAt: route.timeAt, durationMin: route.durationMin,
                  position: route.position, legs: route.legs.map { LegDraft($0) })
    }
}

// ---------------- buscador de paradas y líneas (editor manual) ----------------

/// Una línea de una parada (`Line` de /stops/{id}/lines y `StopSearchLine` del
/// buscador; los nulos quedan en "").
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

    /// Lo que se escribe en el distintivo: el código, o el nombre si no hay.
    var displayCode: String { code.isEmpty ? name : code }
}

/// Una zona de parada (`Stop` de /search/stops).
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

/// Una parada, una dirección postal o un sitio (`Place` de /search/places).
/// Sirve de origen o destino del planificador.
struct PlaceResult: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var city: String
    var kind: String          // "parada" | "dirección" | "sitio" | otro

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

/// `StopSearch`.
struct StopSearchResponse: Decodable, Sendable {
    var stops: [StopResult]
    var age: Double

    enum CodingKeys: String, CodingKey { case stops, age }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stops = c.get(.stops, [])
        age   = c.get(.age, 0)
    }
}

/// `PlaceSearch`.
struct PlaceSearchResponse: Decodable, Sendable {
    var places: [PlaceResult]

    enum CodingKeys: String, CodingKey { case places }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        places = c.get(.places, [])
    }
}

/// `StopLines`: ya ordenadas por el servidor (metro, RER, Transilien, TER,
/// tranvía y los buses al final). La app no reordena (R62).
struct StopLinesResponse: Decodable, Sendable {
    var lines: [StopLine]

    enum CodingKeys: String, CodingKey { case lines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = c.get(.lines, [])
    }
}

/// `Directions`: los destinos que circulan AHORA por esa línea en esa parada.
/// El sentido se elige de aquí, no se escribe (R32).
struct DirectionsResponse: Decodable, Sendable {
    var directions: [String]
    var age: Double

    enum CodingKeys: String, CodingKey { case directions, age }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        directions = c.get(.directions, [])
        age        = c.get(.age, 0)
    }
}
