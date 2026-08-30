import Foundation

// Planificador puerta a puerta: GET /api/plan y POST /api/routes/from-plan.
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

struct PlanResponse: Decodable, Sendable {
    var options: [PlanOption]
    var age: Double

    enum CodingKeys: String, CodingKey { case options, age }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options = c.get(.options, [])
        age     = c.get(.age, 0)
    }
}

/// Cuerpo de POST /api/routes/from-plan.
struct PlanSaveRequest: Encodable, Sendable {
    var option: PlanOption
    var meta: Meta

    struct Meta: Encodable, Sendable {
        var name: String
        var originId: String
        var originName: String
        var destId: String
        var destName: String
        var days: [Int]
        var timeMode: String
        var timeAt: String
        var timeFrom: String
        var timeTo: String
    }
}

struct PlanSaveResponse: Decodable, Sendable {
    var id: Int
    /// Tramos que se han guardado sin sentido porque el texto de Navitia no
    /// casaba con el del tiempo real. Hay que decirlo, no callarlo.
    var withoutDirection: [String]

    enum CodingKeys: String, CodingKey { case id, withoutDirection }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = c.get(.id, 0)
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

struct AlternativesResponse: Decodable, Sendable {
    var needed: Bool
    var affected: [AffectedLine]
    var options: [AlternativeOption]
    var baselineMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case needed, affected, options, baselineMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        needed          = c.get(.needed, false)
        affected        = c.get(.affected, [])
        options         = c.get(.options, [])
        baselineMinutes = c.opt(.baselineMinutes)
    }
}
