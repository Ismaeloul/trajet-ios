import Foundation

// El tablero tal cual lo sirve GET /api/board. Los nombres siguen al servidor
// para que no haya que traducir dos veces; la estrategia snake_case del
// decodificador hace el resto.

/// Vía probable aprendida del histórico. Nunca se puede confundir con la real.
struct PlatformGuess: Codable, Hashable, Sendable {
    var platform: String
    var share: Double      // 0..1, cuota de la vía mayoritaria
    var samples: Int
    var basis: String      // "mision" | "hora" | "linea"
    var why: String        // ya viene redactado en español

    enum CodingKeys: String, CodingKey { case platform, share, samples, basis, why }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = c.get(.platform, "")
        share    = c.get(.share, 0)
        samples  = c.get(.samples, 0)
        basis    = c.get(.basis, "")
        why      = c.get(.why, "")
    }

    var percent: Int { Int((share * 100).rounded()) }
}

/// Longitud del tren. Sustituye a la ocupación, que la API NO da.
enum TrainLength: String, Codable, Sendable {
    case short, long

    var label: String { self == .short ? "Tren corto" : "Tren largo" }
    var symbol: String { self == .short ? "rectangle" : "rectangle.split.2x1" }
}

struct Departure: Codable, Identifiable, Hashable, Sendable {
    var jid: String
    var minutes: Int
    var at: String            // "HH:MM" prevista
    var aimedAt: String       // "HH:MM" teórica, vacía en metro y bus
    var destination: String
    var platform: String?     // vía real; nil el 83 % de las veces
    var platformNew: Bool     // acaba de aparecer: hay que cantarlo
    var guess: PlatformGuess?
    var delay: Int?           // con signo; nil cuando no hay hora teórica
    var status: String
    var atStop: Bool          // parado en el andén: distinto de minutes == 0
    var train: String?
    var length: TrainLength?

    enum CodingKeys: String, CodingKey {
        case jid, minutes, at, aimedAt, destination, platform, platformNew
        case guess, delay, status, atStop, train, length
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jid         = c.get(.jid, "")
        minutes     = c.get(.minutes, 0)
        at          = c.get(.at, "")
        aimedAt     = c.get(.aimedAt, "")
        destination = c.get(.destination, "")
        platform    = c.opt(.platform)
        platformNew = c.get(.platformNew, false)
        guess       = c.opt(.guess)
        delay       = c.opt(.delay)
        status      = c.get(.status, "")
        atStop      = c.get(.atStop, false)
        train       = c.text(.train)
        length      = c.opt(.length)
    }

    /// Identidad estable entre refrescos: es lo que permite que una salida se
    /// desplace por la tira en vez de que parpadee la lista entera.
    var id: String {
        jid.isEmpty ? "\(at)|\(destination)|\(minutes)" : jid
    }

    /// Un retraso de cero no es un retraso: no se pinta.
    var realDelay: Int? {
        guard let delay, delay != 0 else { return nil }
        return delay
    }

    /// La vía de verdad manda; la probable solo existe si no hay real.
    var hasRealPlatform: Bool {
        guard let platform else { return false }
        return !platform.isEmpty
    }
}

/// Estado de la línea en este tramo.
struct LegStatus: Codable, Hashable, Sendable {
    var level: Int            // 0 normal · 1 perturbada · 2 interrumpida
    var label: String
    var messages: [String]        // en francés, hasta tres
    var messagesEs: [String?]     // los mismos en español, o null si aún no
    var translating: Bool
    var planned: Int

    enum CodingKeys: String, CodingKey {
        case level, label, messages, messagesEs, translating, planned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level       = c.get(.level, 0)
        label       = c.get(.label, "normal")
        messages    = c.get(.messages, [])
        messagesEs  = c.get(.messagesEs, [])
        translating = c.get(.translating, false)
        planned     = c.get(.planned, 0)
    }

    init(level: Int = 0, label: String = "normal", messages: [String] = [],
         messagesEs: [String?] = [], translating: Bool = false, planned: Int = 0) {
        self.level = level
        self.label = label
        self.messages = messages
        self.messagesEs = messagesEs
        self.translating = translating
        self.planned = planned
    }

    /// El texto que se enseña: español si ya está, francés mientras tanto.
    /// Nunca se espera al traductor; la pantalla es lo primero.
    var visibleMessages: [String] {
        messages.enumerated().map { i, fr in
            if i < messagesEs.count, let es = messagesEs[i], !es.isEmpty { return es }
            return fr
        }
    }

    /// Sigue en francés: se dice, para que no parezca un fallo de la app.
    var awaitingTranslation: Bool {
        translating || messages.enumerated().contains { i, _ in
            i >= messagesEs.count || (messagesEs[i] ?? "").isEmpty
        }
    }

    var isDisrupted: Bool { level > 0 }
    var isInterrupted: Bool { level >= 2 }
}

struct Leg: Codable, Identifiable, Hashable, Sendable {
    var seq: Int
    var lineId: String
    var lineCode: String
    var lineName: String
    var lineMode: String
    var lineColor: String     // hexadecimal SIN almohadilla
    var fromName: String
    var toName: String
    var directions: [String]
    var status: LegStatus
    var departures: [Departure]
    var age: Double?

    enum CodingKeys: String, CodingKey {
        case seq, lineId, lineCode, lineName, lineMode, lineColor
        case fromName, toName, directions, status, departures, age
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq        = c.get(.seq, 0)
        lineId     = c.get(.lineId, "")
        lineCode   = c.get(.lineCode, "")
        lineName   = c.get(.lineName, "")
        lineMode   = c.get(.lineMode, "")
        lineColor  = c.get(.lineColor, "")
        fromName   = c.get(.fromName, "")
        toName     = c.get(.toName, "")
        directions = c.get(.directions, [])
        status     = c.get(.status, LegStatus())
        departures = c.get(.departures, [])
        age        = c.opt(.age)
    }

    var id: Int { seq }

    /// Modo de transporte, normalizado. Decide si hay hueco para la vía.
    var mode: TransportMode { TransportMode(rawMode: lineMode) }

    /// Solo tren, RER y TER publican vía: 0 de ~600 pasos de metro, bus y
    /// tranvía medidos traían andén. En esos modos no se reserva el hueco.
    var showsPlatform: Bool { mode.publishesPlatform }

    /// El sentido de la marcha, tal como se enseña bajo el nombre de la parada.
    var directionLabel: String {
        if !directions.isEmpty { return directions.joined(separator: " · ") }
        if !toName.isEmpty { return toName }
        return ""
    }

    /// Cuando el tramo no filtra sentido, en la misma parada se mezclan
    /// destinos distintos y hay que decir a dónde va cada paso.
    var mixesDestinations: Bool {
        directions.isEmpty && Set(departures.map(\.destination)).count > 1
    }
}

/// Los modos que devuelve `line_mode`, ya agrupados por lo que nos importa.
enum TransportMode: Sendable {
    case metro, rer, transilien, ter, tram, bus, other

    init(rawMode: String) {
        let m = rawMode.folding(options: .diacriticInsensitive,
                                locale: Locale(identifier: "es")).lowercased()
        if m.contains("metro") { self = .metro }
        else if m.contains("rer") { self = .rer }
        else if m.contains("transilien") { self = .transilien }
        else if m.contains("ter") { self = .ter }
        else if m.contains("tram") { self = .tram }
        else if m.contains("bus") { self = .bus }
        else { self = .other }
    }

    /// Medido el 30/08: metro, bus y tranvía no publican vía jamás.
    var publishesPlatform: Bool {
        switch self {
        case .rer, .transilien, .ter: true
        case .metro, .tram, .bus, .other: false
        }
    }

    var symbol: String {
        switch self {
        case .metro: "tram.fill.tunnel"
        case .rer, .transilien, .ter: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .other: "arrow.triangle.turn.up.right.diamond.fill"
        }
    }
}

struct BoardRoute: Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var originName: String
    var destName: String

    enum CodingKeys: String, CodingKey { case id, name, originName, destName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = c.get(.id, 0)
        name       = c.get(.name, "")
        originName = c.get(.originName, "")
        destName   = c.get(.destName, "")
    }
}

struct Board: Codable, Sendable {
    var route: BoardRoute?
    var legs: [Leg]
    var worstLevel: Int
    var worstLine: String
    var maxDelay: Double
    var updatedAt: String
    var dataAge: Double
    var stale: Bool
    var errors: [String]
    var quota: [String: Int]
    var lastError: String?
    var autoSelected: Bool

    /// Instalación limpia: no hay ni una ruta guardada todavía.
    var empty: Bool
    var message: String?

    /// Cuándo llegó al teléfono. La antigüedad que se enseña se cuenta desde
    /// aquí y no desde `updated_at`: si el móvil pierde la red, lo que
    /// envejece es lo que tenemos en la mano.
    var receivedAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case route, legs, worstLevel, worstLine, maxDelay, updatedAt
        case dataAge, stale, errors, quota, lastError, autoSelected
        case empty, message, age
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        route        = c.opt(.route)
        legs         = c.get(.legs, [])
        worstLevel   = c.get(.worstLevel, 0)
        worstLine    = c.get(.worstLine, "")
        maxDelay     = c.get(.maxDelay, 0)
        updatedAt    = c.get(.updatedAt, "")
        // Los ficheros de prueba antiguos traen "age" donde ahora va "data_age".
        dataAge      = c.get(.dataAge, c.get(.age, 0))
        stale        = c.get(.stale, false)
        errors       = c.get(.errors, [])
        quota        = c.get(.quota, [:])
        lastError    = c.opt(.lastError)
        autoSelected = c.get(.autoSelected, false)
        empty        = c.get(.empty, false)
        message      = c.opt(.message)
        receivedAt   = .now
    }

    /// Se escribe a mano porque `receivedAt` no es del servidor —se guarda
    /// aparte, junto a la caché— y porque `age` solo existe para leer los
    /// ficheros de prueba antiguos.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(route, forKey: .route)
        try c.encode(legs, forKey: .legs)
        try c.encode(worstLevel, forKey: .worstLevel)
        try c.encode(worstLine, forKey: .worstLine)
        try c.encode(maxDelay, forKey: .maxDelay)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(dataAge, forKey: .dataAge)
        try c.encode(stale, forKey: .stale)
        try c.encode(errors, forKey: .errors)
        try c.encode(quota, forKey: .quota)
        try c.encodeIfPresent(lastError, forKey: .lastError)
        try c.encode(autoSelected, forKey: .autoSelected)
        try c.encode(empty, forKey: .empty)
        try c.encodeIfPresent(message, forKey: .message)
    }

    /// Segundos de antigüedad de lo que se está viendo.
    func ageSeconds(now: Date = .now) -> Double {
        max(0, now.timeIntervalSince(receivedAt)) + dataAge
    }

    /// Con el dato viejo se apaga el tablero entero, no solo una etiqueta.
    func isStale(now: Date = .now) -> Bool {
        stale || ageSeconds(now: now) > 90
    }

    var hasContent: Bool { !legs.isEmpty }

    /// Llamadas que quedan hoy en el endpoint que consume el tablero.
    var remainingCalls: Int? { quota["stop-monitoring"] }
}
