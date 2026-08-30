import Foundation

// Historial y estado del aprendizaje de andenes: GET /api/stats,
// GET /api/platform-model y GET /api/health.

struct MonthStat: Decodable, Identifiable, Hashable, Sendable {
    var month: String         // "2026-08"
    var badDays: Int
    var totalDays: Int
    var avgDelay: Double

    enum CodingKeys: String, CodingKey { case month, badDays, totalDays, avgDelay }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month     = c.get(.month, "")
        badDays   = c.get(.badDays, 0)
        totalDays = c.get(.totalDays, 0)
        avgDelay  = c.get(.avgDelay, 0)
    }

    var id: String { month }

    /// Proporción de días con incidencia, para la barra.
    var badShare: Double {
        totalDays > 0 ? Double(badDays) / Double(totalDays) : 0
    }

    /// "agosto 2026" a partir de "2026-08".
    var monthLabel: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else {
            return month
        }
        let names = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                     "julio", "agosto", "septiembre", "octubre", "noviembre",
                     "diciembre"]
        return "\(names[m - 1]) \(parts[0])"
    }
}

struct LineStat: Decodable, Identifiable, Hashable, Sendable {
    var worstLine: String
    var n: Int
    var avgDelay: Double

    enum CodingKeys: String, CodingKey { case worstLine, n, avgDelay }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        worstLine = c.get(.worstLine, "")
        n         = c.get(.n, 0)
        avgDelay  = c.get(.avgDelay, 0)
    }

    var id: String { worstLine }
}

struct OverallStat: Decodable, Hashable, Sendable {
    var n: Int
    var avgDelay: Double
    var maxDelay: Double

    enum CodingKeys: String, CodingKey { case n, avgDelay, maxDelay }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n        = c.get(.n, 0)
        avgDelay = c.get(.avgDelay, 0)
        maxDelay = c.get(.maxDelay, 0)
    }

    init() { n = 0; avgDelay = 0; maxDelay = 0 }
}

struct StatsResponse: Decodable, Sendable {
    var byMonth: [MonthStat]
    var byLine: [LineStat]
    var overall: OverallStat

    enum CodingKeys: String, CodingKey { case byMonth, byLine, overall }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byMonth = c.get(.byMonth, [])
        byLine  = c.get(.byLine, [])
        overall = c.get(.overall, OverallStat())
    }
}

// ---------------- previsión del andén ----------------

struct PlatformAccuracy: Decodable, Hashable, Sendable {
    var predictions: Int
    var hits: Int
    var rate: Double?         // null mientras no haya con qué puntuar
    var observations: Int
    var days: Int

    enum CodingKeys: String, CodingKey {
        case predictions, hits, rate, observations, days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        predictions  = c.get(.predictions, 0)
        hits         = c.get(.hits, 0)
        rate         = c.opt(.rate)
        observations = c.get(.observations, 0)
        days         = c.get(.days, 0)
    }

    init() { predictions = 0; hits = 0; rate = nil; observations = 0; days = 0 }

    var percentLabel: String {
        guard let rate else { return "—" }
        return "\(Int((rate * 100).rounded())) %"
    }
}

struct PlatformCoverage: Decodable, Identifiable, Hashable, Sendable {
    var seq: Int
    var lineCode: String
    var observations: Int
    var days: Int
    var platforms: Int

    enum CodingKeys: String, CodingKey {
        case seq, lineCode, observations, days, platforms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq          = c.get(.seq, 0)
        lineCode     = c.get(.lineCode, "")
        observations = c.get(.observations, 0)
        days         = c.get(.days, 0)
        platforms    = c.get(.platforms, 0)
    }

    var id: Int { seq }
}

struct PlatformModelResponse: Decodable, Sendable {
    var accuracy: PlatformAccuracy
    var coverage: [PlatformCoverage]
    var routeName: String?

    enum CodingKeys: String, CodingKey { case accuracy, coverage, route }
    private enum RouteKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accuracy = c.get(.accuracy, PlatformAccuracy())
        coverage = c.get(.coverage, [])
        let route = try? c.nestedContainer(keyedBy: RouteKeys.self, forKey: .route)
        routeName = route?.get(.name, "")
    }
}

// ---------------- salud del servidor ----------------

struct TranslatorStatus: Decodable, Hashable, Sendable {
    var ok: Bool
    var reason: String
    var model: String

    enum CodingKeys: String, CodingKey { case ok, reason, model }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok     = c.get(.ok, false)
        reason = c.get(.reason, "")
        model  = c.get(.model, "")
    }

    init() { ok = false; reason = ""; model = "" }
}

struct HealthResponse: Decodable, Sendable {
    var ok: Bool
    var keyConfigured: Bool
    var quota: [String: Int]
    var lastError: String?
    var nowParis: String
    var translator: TranslatorStatus

    enum CodingKeys: String, CodingKey {
        case ok, keyConfigured, quota, lastError, nowParis, translator
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok            = c.get(.ok, false)
        keyConfigured = c.get(.keyConfigured, false)
        quota         = c.get(.quota, [:])
        lastError     = c.opt(.lastError)
        nowParis      = c.get(.nowParis, "")
        translator    = c.get(.translator, TranslatorStatus())
    }
}
