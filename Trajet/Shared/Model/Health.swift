import Foundation

// Salud del servidor: GET /api/v1/health (`HealthV1` del contrato). No gasta
// cuota. Lo usan Ajustes (clave, cuota por endpoint, traductor, recolector) y
// el pie del tablero (R46). Tolerante como todo lo demás (R21).

/// De dónde sale la clave de PRIM que usa el servidor.
enum PrimKeySource: String, Codable, Sendable, CaseIterable {
    case panel, env, none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PrimKeySource(rawValue: raw) ?? PrimKeySource.none
    }

    var label: String {
        switch self {
        case .panel: "guardada en el panel"
        case .env: "del entorno del servidor"
        case .none: "ninguna"
        }
    }
}

/// `PrimState`: estado de la clave para la app.
struct PrimState: Codable, Hashable, Sendable {
    var keyState: PrimKeyState
    var keySource: PrimKeySource
    var checkedAt: String?        // ISO 8601 (UTC) o nil
    var lastError: String?        // último fallo con PRIM, sin secretos

    enum CodingKeys: String, CodingKey { case keyState, keySource, checkedAt, lastError }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyState  = c.get(.keyState, PrimKeyState.unknown)
        keySource = c.get(.keySource, PrimKeySource.none)
        checkedAt = c.opt(.checkedAt)
        lastError = c.opt(.lastError)
    }

    init(keyState: PrimKeyState = .unknown, keySource: PrimKeySource = PrimKeySource.none,
         checkedAt: String? = nil, lastError: String? = nil) {
        self.keyState = keyState
        self.keySource = keySource
        self.checkedAt = checkedAt
        self.lastError = lastError
    }

    var hasKey: Bool { keyState != .missing && keySource != PrimKeySource.none }
}

/// `QuotaEndpoint`: lo gastado hoy en un endpoint de PRIM.
struct QuotaEndpoint: Codable, Hashable, Identifiable, Sendable {
    var endpoint: String          // stop-monitoring | general-message | navitia
    var used: Int
    var cap: Int
    var remainingReported: Int?
    var level: QuotaLevel

    enum CodingKeys: String, CodingKey { case endpoint, used, cap, remainingReported, level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint          = c.get(.endpoint, "")
        used              = c.get(.used, 0)
        cap               = c.get(.cap, 1000)
        remainingReported = c.opt(.remainingReported)
        level             = c.get(.level, QuotaLevel.ok)
    }

    init(endpoint: String, used: Int, cap: Int = 1000, remainingReported: Int? = nil,
         level: QuotaLevel = .ok) {
        self.endpoint = endpoint
        self.used = used
        self.cap = cap
        self.remainingReported = remainingReported
        self.level = level
    }

    var id: String { endpoint }

    /// Nombre para personas (R46): «Tablero», «Avisos», «Buscador».
    var label: String {
        switch endpoint {
        case "stop-monitoring": "Tablero"
        case "general-message": "Avisos"
        case "navitia": "Buscador"
        default: endpoint
        }
    }

    /// Lo que queda: el peor dato entre el contador propio y el de PRIM.
    var remaining: Int {
        let own = max(0, cap - used)
        guard let remainingReported else { return own }
        return min(own, max(0, remainingReported))
    }

    /// 0…1, para la barra.
    var usedShare: Double { cap > 0 ? min(1, Double(used) / Double(cap)) : 0 }
}

/// `QuotaV1`: la cuota del día UTC. Se reinicia a medianoche UTC (R46).
struct QuotaSnapshot: Codable, Hashable, Sendable {
    var dayUtc: String            // "2026-09-24"
    var resetsAt: String          // ISO 8601
    var level: QuotaLevel
    var refreshHintS: Int
    var endpoints: [QuotaEndpoint]

    enum CodingKeys: String, CodingKey { case dayUtc, resetsAt, level, refreshHintS, endpoints }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayUtc       = c.get(.dayUtc, "")
        resetsAt     = c.get(.resetsAt, "")
        level        = c.get(.level, QuotaLevel.ok)
        refreshHintS = c.get(.refreshHintS, 30)
        endpoints    = c.get(.endpoints, [])
    }

    init(dayUtc: String = "", resetsAt: String = "", level: QuotaLevel = .ok,
         refreshHintS: Int = 30, endpoints: [QuotaEndpoint] = []) {
        self.dayUtc = dayUtc
        self.resetsAt = resetsAt
        self.level = level
        self.refreshHintS = refreshHintS
        self.endpoints = endpoints
    }

    /// La hora del reinicio como fecha, si se puede leer.
    var resetsAtDate: Date? { ISO8601Parsing.date(resetsAt) }

    func endpoint(_ name: String) -> QuotaEndpoint? {
        endpoints.first { $0.endpoint == name }
    }
}

/// `CollectorStatus`: el recolector de andenes que alimenta la vía probable.
struct CollectorStatus: Codable, Hashable, Sendable {
    var enabled: Bool
    var running: Bool
    var lastAt: String            // "HH:MM:SS" (París) o ""
    var sessionTotal: Int
    var stations: Int
    var recorded: Int
    var reason: String
    var interval: Int             // s hasta la siguiente pasada; 0 = no muestrea
    var remaining: Int?
    var priority: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, running, lastAt, sessionTotal, stations, recorded
        case reason, interval, remaining, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled      = c.get(.enabled, false)
        running      = c.get(.running, false)
        lastAt       = c.get(.lastAt, "")
        sessionTotal = c.get(.sessionTotal, 0)
        stations     = c.get(.stations, 0)
        recorded     = c.get(.recorded, 0)
        reason       = c.get(.reason, "")
        interval     = c.get(.interval, 0)
        remaining    = c.opt(.remaining)
        priority     = c.get(.priority, false)
    }

    init() {
        enabled = false; running = false; lastAt = ""; sessionTotal = 0; stations = 0
        recorded = 0; reason = ""; interval = 0; remaining = nil; priority = false
    }
}

/// `TranslatorStatus`: el traductor de avisos (Ollama). Tres formas en el
/// servidor; aquí una sola, con reservas.
struct TranslatorStatus: Codable, Hashable, Sendable {
    var ok: Bool
    var reason: String
    var model: String
    var models: [String]

    enum CodingKeys: String, CodingKey { case ok, reason, model, models }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok     = c.get(.ok, false)
        reason = c.get(.reason, "")
        model  = c.get(.model, "")
        models = c.get(.models, [])
    }

    init(ok: Bool = false, reason: String = "", model: String = "", models: [String] = []) {
        self.ok = ok
        self.reason = reason
        self.model = model
        self.models = models
    }
}

/// `HealthV1`: todo lo que Ajustes enseña del servidor.
struct ServerHealth: Codable, Hashable, Sendable {
    var ok: Bool                  // el esquema de la BD está al día
    var version: String
    var api: Int
    var nowParis: String          // "2026-09-24 12:50:03"
    var schemaVersion: Int
    var prim: PrimState
    var quota: QuotaSnapshot
    var collector: CollectorStatus
    var platformModel: PlatformAccuracy
    var translator: TranslatorStatus

    enum CodingKeys: String, CodingKey {
        case ok, version, api, nowParis, schemaVersion, prim, quota
        case collector, platformModel, translator
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok            = c.get(.ok, false)
        version       = c.get(.version, "")
        api           = c.get(.api, 1)
        nowParis      = c.get(.nowParis, "")
        schemaVersion = c.get(.schemaVersion, 0)
        prim          = c.get(.prim, PrimState())
        quota         = c.get(.quota, QuotaSnapshot())
        collector     = c.get(.collector, CollectorStatus())
        platformModel = c.get(.platformModel, PlatformAccuracy())
        translator    = c.get(.translator, TranslatorStatus())
    }

    /// El servidor tiene una clave de PRIM que funciona.
    var hasWorkingKey: Bool { prim.keyState == .valid }
}

/// Lectura de fechas ISO 8601 del servidor («2026-09-24T10:12:00+00:00»,
/// con o sin fracciones de segundo).
enum ISO8601Parsing {
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }
}
