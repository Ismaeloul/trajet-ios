import Foundation

// Lo que la app necesita saber del servidor en cada tablero (`ServerState`
// del contrato) y los dos enumerados que comparte con /api/v1/health.
// Tolerantes: un valor que no se conoce no revienta, cae en el de reserva.

/// Estado de la clave de PRIM. Nunca la clave ni un trozo de ella.
enum PrimKeyState: String, Codable, Sendable, CaseIterable {
    case missing
    case valid
    case invalid
    case forbidden
    case quotaExhausted = "quota_exhausted"
    case unreachable
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PrimKeyState(rawValue: raw) ?? .unknown
    }

    /// Cómo se dice en Ajustes.
    var label: String {
        switch self {
        case .missing: "sin clave"
        case .valid: "válida"
        case .invalid: "rechazada"
        case .forbidden: "sin permiso"
        case .quotaExhausted: "cuota agotada"
        case .unreachable: "PRIM no responde"
        case .unknown: "sin comprobar"
        }
    }

    /// La clave funciona (o al menos no se sabe que no).
    var isUsable: Bool {
        switch self {
        case .valid, .unknown: true
        case .missing, .invalid, .forbidden, .quotaExhausted, .unreachable: false
        }
    }
}

/// Nivel de la cuota del día: < 70 % ok, < 85 % warn, < 95 % critical; si no,
/// exhausted. Un valor desconocido se lee como `ok`.
enum QuotaLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case ok, warn, critical, exhausted

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = QuotaLevel(rawValue: raw) ?? .ok
    }

    var label: String {
        switch self {
        case .ok: "normal"
        case .warn: "justa"
        case .critical: "casi agotada"
        case .exhausted: "agotada"
        }
    }

    private var rank: Int {
        switch self {
        case .ok: 0
        case .warn: 1
        case .critical: 2
        case .exhausted: 3
        }
    }

    static func < (lhs: QuotaLevel, rhs: QuotaLevel) -> Bool { lhs.rank < rhs.rank }
}

/// `ServerState` del contrato: va en cada tablero (y en el vacío).
struct ServerState: Codable, Hashable, Sendable {
    var primKey: PrimKeyState
    var quotaLevel: QuotaLevel
    /// Cada cuánto conviene refrescar (30, 60, 120 o 300). La app nunca baja
    /// de 30 s.
    var refreshHintS: Int
    /// Se sirve caché más vieja de lo normal para ahorrar cuota o porque PRIM
    /// falla.
    var degraded: Bool

    enum CodingKeys: String, CodingKey { case primKey, quotaLevel, refreshHintS, degraded }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primKey      = c.get(.primKey, PrimKeyState.unknown)
        quotaLevel   = c.get(.quotaLevel, QuotaLevel.ok)
        refreshHintS = c.get(.refreshHintS, 30)
        degraded     = c.get(.degraded, false)
    }

    init(primKey: PrimKeyState = .valid, quotaLevel: QuotaLevel = .ok,
         refreshHintS: Int = 30, degraded: Bool = false) {
        self.primKey = primKey
        self.quotaLevel = quotaLevel
        self.refreshHintS = refreshHintS
        self.degraded = degraded
    }

    /// Lo corriente: clave buena, cuota holgada, cada 30 s.
    static let normal = ServerState()

    /// Segundos entre refrescos: el consejo del servidor, nunca menos de 30.
    var refreshInterval: TimeInterval { max(30, TimeInterval(refreshHintS)) }
}
