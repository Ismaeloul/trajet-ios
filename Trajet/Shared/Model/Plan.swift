import Foundation

// Planificador puerta a puerta: GET /api/v1/plan y POST
// /api/v1/routes/from-plan (`Plan`, `PlanOption`, `PlanLeg`,
// `RouteFromPlanInput`, `RouteFromPlanSaved` del contrato), y las
// alternativas de GET /api/v1/alternatives/{id} (`Alternatives`,
// `AlternativesNotNeeded`).
//
// La opción elegida se devuelve al servidor TAL CUAL vino, así que estos tipos
// son Codable en los dos sentidos y se codifican de vuelta a snake_case.

struct PlanLeg: Codable, Identifiable, Hashable, Sendable {
    var lineId: String
    var lineCode: String
    var lineName: String
    var lineMode: String
    var lineColor: String
    var fromId: String
    var fromName: String
    var toId: String
    var toName: String
    var direction: String
    var minutes: Int
    var at: String

    enum CodingKeys: String, CodingKey {
        case lineId, lineCode, lineName, lineMode, lineColor
        case fromId, fromName, toId, toName, direction, minutes, at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineId    = c.get(.lineId, "")
        lineCode  = c.get(.lineCode, "")
        lineName  = c.get(.lineName, "")
        lineMode  = c.get(.lineMode, "")
        lineColor = c.get(.lineColor, "")
        fromId    = c.get(.fromId, "")
        fromName  = c.get(.fromName, "")
        toId      = c.get(.toId, "")
        toName    = c.get(.toName, "")
        direction = c.get(.direction, "")
        minutes   = c.get(.minutes, 0)
        at        = c.get(.at, "")
    }

    var id: String { "\(lineId)|\(fromId)|\(at)" }
    var mode: TransportMode { TransportMode(rawMode: lineMode) }
}

struct PlanOption: Codable, Identifiable, Hashable, Sendable {
    var kind: String
    var minutes: Int
    var walkMinutes: Int
    var transfers: Int
    var departure: String
    var arrival: String
    var legs: [PlanLeg]

    enum CodingKeys: String, CodingKey {
        case kind, minutes, walkMinutes, transfers, departure, arrival, legs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind        = c.get(.kind, "")
        minutes     = c.get(.minutes, 0)
        walkMinutes = c.get(.walkMinutes, 0)
        transfers   = c.get(.transfers, 0)
        departure   = c.get(.departure, "")
        arrival     = c.get(.arrival, "")
        legs        = c.get(.legs, [])
    }

    var id: String { legs.map(\.lineId).joined(separator: ">") + "|" + departure }

    var transfersLabel: String {
        switch transfers {
        case 0: "directo"
        case 1: "1 transbordo"
        default: "\(transfers) transbordos"
        }
    }
}

struct PlanResponse: Decodable, Hashable, Sendable {
    var options: [PlanOption]
    var age: Double

    enum CodingKeys: String, CodingKey { case options, age }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options = c.get(.options, [])
        age     = c.get(.age, 0)
    }
}

/// Cuerpo de POST /api/v1/routes/from-plan (`RouteFromPlanInput`): la opción
/// tal cual vino y los datos de la ruta (`RouteMetaInput`).
struct PlanSaveRequest: Encodable, Hashable, Sendable {
    var option: PlanOption
    var meta: Meta

    struct Meta: Encodable, Hashable, Sendable {
        var name: String
        var originId: String
        var originName: String
        var destId: String
        var destName: String
        var days: [Int]
        var timeMode: TimeMode        // arrival | departure (R34)
        var timeAt: String
        var timeFrom: String
        var timeTo: String

        init(name: String, originId: String, originName: String, destId: String,
             destName: String, days: [Int] = [0, 1, 2, 3, 4], timeMode: TimeMode = .arrival,
             timeAt: String, timeFrom: String = "07:00", timeTo: String = "10:00") {
            self.name = name
            self.originId = originId
            self.originName = originName
            self.destId = destId
            self.destName = destName
            self.days = days
            self.timeMode = timeMode
            self.timeAt = timeAt
            self.timeFrom = timeFrom
            self.timeTo = timeTo
        }
    }

    init(option: PlanOption, meta: Meta) {
        self.option = option
        self.meta = meta
    }
}

/// `RouteFromPlanSaved`.
struct PlanSaveResponse: Decodable, Hashable, Sendable {
    var id: Int
    var route: SavedRoute?
    /// Tramos que se han guardado sin sentido porque el texto de Navitia no
    /// casaba con el del tiempo real (`line_code`). Hay que decirlo, no
    /// callarlo (R33).
    var withoutDirection: [String]

    enum CodingKeys: String, CodingKey { case id, route, withoutDirection }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = c.get(.id, 0)
        route            = c.opt(.route)
        withoutDirection = c.get(.withoutDirection, [])
    }
}

// ---------------- alternativas cuando algo está cortado ----------------

struct AlternativeLeg: Decodable, Identifiable, Hashable, Sendable {
    var code: String
    var mode: String
    var direction: String
    var color: String
    var minutes: Int
    var status: String

    enum CodingKeys: String, CodingKey {
        case code, mode, direction, color, minutes, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code      = c.get(.code, "")
        mode      = c.get(.mode, "")
        direction = c.get(.direction, "")
        color     = c.get(.color, "")
        minutes   = c.get(.minutes, 0)
        status    = c.get(.status, "normal")
    }

    var id: String { "\(code)|\(direction)|\(minutes)" }
}

struct AlternativeOption: Decodable, Identifiable, Hashable, Sendable {
    var totalMinutes: Int
    var transfers: Int
    var deltaMinutes: Int?
    var legs: [AlternativeLeg]
    /// false = esta alternativa también pasa por una línea caída.
    var usable: Bool
    var worstLevel: Int
    var departure: String
    var arrival: String

    enum CodingKeys: String, CodingKey {
        case totalMinutes, transfers, deltaMinutes, legs
        case usable, worstLevel, departure, arrival
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalMinutes = c.get(.totalMinutes, 0)
        transfers    = c.get(.transfers, 0)
        deltaMinutes = c.opt(.deltaMinutes)
        legs         = c.get(.legs, [])
        usable       = c.get(.usable, true)
        worstLevel   = c.get(.worstLevel, 0)
        departure    = c.get(.departure, "")
        arrival      = c.get(.arrival, "")
    }

    var id: String { legs.map(\.code).joined(separator: ">") + "|\(totalMinutes)" }

    /// Hora de Navitia «20260831T083100» → «08:31» (R56); "" si no se lee.
    static func navitiaTime(_ raw: String) -> String {
        guard let t = raw.firstIndex(of: "T") else { return "" }
        let digits = raw[raw.index(after: t)...].prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber) else { return "" }
        return "\(digits.prefix(2)):\(digits.suffix(2))"
    }

    var departureTime: String { Self.navitiaTime(departure) }
    var arrivalTime: String { Self.navitiaTime(arrival) }

    /// «+12 min» respecto de lo que dura normalmente la ruta.
    var deltaLabel: String? {
        guard let deltaMinutes else { return nil }
        if deltaMinutes == 0 { return "igual de rápido" }
        return deltaMinutes > 0 ? "+\(deltaMinutes) min" : "\(deltaMinutes) min"
    }
}

struct AffectedLine: Decodable, Identifiable, Hashable, Sendable {
    var lineId: String
    var lineCode: String
    var level: Int
    var label: String

    enum CodingKeys: String, CodingKey { case lineId, lineCode, level, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineId   = c.get(.lineId, "")
        lineCode = c.get(.lineCode, "")
        level    = c.get(.level, 0)
        label    = c.get(.label, "")
    }

    var id: String { lineId }
}

/// `Alternatives` o, si ninguna línea está tocada y no se forzó, la respuesta
/// corta `AlternativesNotNeeded` (`needed: false`, sin opciones).
struct AlternativesResponse: Decodable, Hashable, Sendable {
    var needed: Bool
    var affected: [AffectedLine]
    var options: [AlternativeOption]
    var baselineMinutes: Int?
    var age: Double
    var quota: [String: Int]

    enum CodingKeys: String, CodingKey {
        case needed, affected, options, baselineMinutes, age, quota
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        needed          = c.get(.needed, false)
        affected        = c.get(.affected, [])
        options         = c.get(.options, [])
        baselineMinutes = c.opt(.baselineMinutes)
        age             = c.get(.age, 0)
        quota           = c.get(.quota, [:])
    }

    /// Ninguna opción sirve (todas pasan por otra línea caída) o no hay.
    var hasUsableOption: Bool { options.contains { $0.usable } }
}
