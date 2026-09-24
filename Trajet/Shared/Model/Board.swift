import Foundation

// El tablero tal cual lo sirve GET /api/v1/board (`BoardV1` del contrato,
// docs/openapi.yaml). Los nombres siguen al servidor para que no haya que
// traducir dos veces; la estrategia snake_case del decodificador hace el
// resto. Todo se decodifica de forma tolerante (R21): un campo que falta o
// llega con otro tipo toma su valor de reserva, nunca tumba la pantalla.

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

    init(platform: String, share: Double, samples: Int, basis: String, why: String) {
        self.platform = platform
        self.share = share
        self.samples = samples
        self.basis = basis
        self.why = why
    }

    var percent: Int { Int((share * 100).rounded()) }
}

/// Longitud del tren. Sustituye a la ocupación, que la API NO da (R5).
enum TrainLength: String, Codable, Sendable {
    case short, long

    var label: String { self == .short ? "Tren corto" : "Tren largo" }
    var symbol: String { self == .short ? "rectangle" : "rectangle.split.2x1" }
}

/// Un paso por la parada (`Departure` del contrato).
struct Departure: Codable, Identifiable, Hashable, Sendable {
    var jid: String
    var minutes: Int
    var at: String            // "HH:MM" prevista (París)
    var aimedAt: String       // "HH:MM" teórica, vacía en metro y bus
    var destination: String
    var platform: String?     // vía real; nil el 83 % de las veces
    var platformNew: Bool     // acaba de aparecer: hay que cantarlo
    var guess: PlatformGuess?
    var delay: Int?           // con signo; nil cuando no hay hora teórica
    var status: String        // onTime, delayed, cancelled… o ""
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
        // R22: el número de misión llega como cadena o como número.
        train       = c.text(.train)
        length      = c.opt(.length)
    }

    init(jid: String = "", minutes: Int, at: String = "", aimedAt: String = "",
         destination: String = "", platform: String? = nil, platformNew: Bool = false,
         guess: PlatformGuess? = nil, delay: Int? = nil, status: String = "onTime",
         atStop: Bool = false, train: String? = nil, length: TrainLength? = nil) {
        self.jid = jid
        self.minutes = minutes
        self.at = at
        self.aimedAt = aimedAt
        self.destination = destination
        self.platform = platform
        self.platformNew = platformNew
        self.guess = guess
        self.delay = delay
        self.status = status
        self.atStop = atStop
        self.train = train
        self.length = length
    }

    /// Identidad estable entre refrescos (R23): es lo que permite que una
    /// salida se desplace por la tira en vez de que parpadee la lista entera.
    var id: String {
        jid.isEmpty ? "\(at)|\(destination)|\(minutes)" : jid
    }

    /// Un retraso de cero no es un retraso: no se pinta (R14). Sin hora
    /// teórica tampoco hay retraso que enseñar (R4).
    var realDelay: Int? {
        guard let delay, delay != 0 else { return nil }
        return delay
    }

    /// La vía de verdad manda; la probable solo existe si no hay real.
    var hasRealPlatform: Bool {
        guard let platform else { return false }
        return !platform.isEmpty
    }

    /// El tren se ha suprimido (`status: "cancelled"` de SIRI).
    var isCancelled: Bool { status.lowercased() == "cancelled" }

    /// La hora prevista («HH:MM» de París) como fecha, la más cercana a
    /// `reference`. Sirve para las cuentas atrás de los widgets y de la Live
    /// Activity, que el sistema mueve solo.
    func date(near reference: Date) -> Date? {
        Self.parisDate(at, near: reference)
    }

    /// «HH:MM» en hora de París → la fecha más cercana a `reference` (±12 h):
    /// un «00:10» pedido a las 23:55 es de mañana, no de esta madrugada.
    static func parisDate(_ hhmm: String, near reference: Date) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute),
              let paris = TimeZone(identifier: "Europe/Paris")
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        var comps = calendar.dateComponents([.year, .month, .day], from: reference)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard var date = calendar.date(from: comps) else { return nil }
        let diff = date.timeIntervalSince(reference)
        if diff < -12 * 3600 {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if diff > 12 * 3600 {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }
}

/// Estado de la línea en este tramo (`LineStatus` del contrato).
struct LegStatus: Codable, Hashable, Sendable {
    var level: Int            // 0 normal · 1 perturbada · 2 interrumpida
    var label: String
    var messages: [String]        // en francés, hasta tres
    var messagesEs: [String?]     // los mismos en español, o null si aún no
    var translating: Bool
    var planned: Int              // obras con fecha futura: no encienden nada (R28)

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
    /// Nunca se espera al traductor; la pantalla es lo primero (R8).
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

/// Un tramo de la ruta (`BoardLegV1` del contrato).
struct Leg: Codable, Identifiable, Hashable, Sendable {
    var seq: Int
    var lineId: String
    var lineCode: String
    var lineName: String
    var lineMode: String
    var lineColor: String     // hexadecimal SIN almohadilla (tolerante: R57)
    var fromId: String        // zona de parada de subida (mapa y geocercas)
    var fromName: String
    var toId: String
    var toName: String
    var directions: [String]
    var status: LegStatus
    var departures: [Departure]
    /// Segundos de antigüedad del dato de la estación; nil si falló sin caché.
    var age: Double?
    /// Lo dice el servidor (v1). Si falta (caché vieja), se deduce del modo.
    var platformExpected: Bool?

    enum CodingKeys: String, CodingKey {
        case seq, lineId, lineCode, lineName, lineMode, lineColor
        case fromId, fromName, toId, toName, directions, status, departures, age
        case platformExpected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq              = c.get(.seq, 0)
        lineId           = c.get(.lineId, "")
        lineCode         = c.get(.lineCode, "")
        lineName         = c.get(.lineName, "")
        lineMode         = c.get(.lineMode, "")
        lineColor        = c.get(.lineColor, "")
        fromId           = c.get(.fromId, "")
        fromName         = c.get(.fromName, "")
        toId             = c.get(.toId, "")
        toName           = c.get(.toName, "")
        directions       = c.get(.directions, [])
        status           = c.get(.status, LegStatus())
        departures       = c.get(.departures, [])
        age              = c.opt(.age)
        platformExpected = c.opt(.platformExpected)
    }

    init(seq: Int, lineId: String = "", lineCode: String, lineName: String = "",
         lineMode: String, lineColor: String = "", fromId: String = "",
         fromName: String = "", toId: String = "", toName: String = "",
         directions: [String] = [], status: LegStatus = LegStatus(),
         departures: [Departure] = [], age: Double? = 0, platformExpected: Bool? = nil) {
        self.seq = seq
        self.lineId = lineId
        self.lineCode = lineCode
        self.lineName = lineName.isEmpty ? lineCode : lineName
        self.lineMode = lineMode
        self.lineColor = lineColor
        self.fromId = fromId
        self.fromName = fromName
        self.toId = toId
        self.toName = toName
        self.directions = directions
        self.status = status
        self.departures = departures
        self.age = age
        self.platformExpected = platformExpected
    }

    var id: Int { seq }

    /// Modo de transporte, normalizado.
    var mode: TransportMode { TransportMode(rawMode: lineMode) }

    /// ¿Se reserva hueco para la vía? (R3). Manda `platform_expected` del
    /// servidor; sin él, el modo: solo tren, RER y TER publican vía.
    var showsPlatform: Bool { platformExpected ?? mode.publishesPlatform }

    /// La estación falló y no había caché: `age` llega null.
    var stationFailed: Bool { age == nil }

    /// El sentido de la marcha, tal como se enseña bajo el nombre de la parada.
    var directionLabel: String {
        if !directions.isEmpty { return directions.joined(separator: " · ") }
        if !toName.isEmpty { return toName }
        return ""
    }

    /// Cuando el tramo no filtra sentido, en la misma parada se mezclan
    /// destinos distintos y hay que decir a dónde va cada paso (R24).
    var mixesDestinations: Bool {
        directions.isEmpty && Set(departures.map(\.destination)).count > 1
    }
}

/// Los modos que devuelve `line_mode`, ya agrupados por lo que nos importa.
enum TransportMode: Sendable {
    case metro, rer, transilien, ter, tram, bus, other

    init(rawMode: String) {
        let m = rawMode.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                locale: Locale(identifier: "es")).lowercased()
        let words = m.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if m.contains("metro") { self = .metro }
        else if words.contains("rer") { self = .rer }
        else if m.contains("transilien") { self = .transilien }
        else if words.contains("ter") { self = .ter }
        else if m.contains("tram") { self = .tram }      // también «Tram-train»
        else if m.contains("bus") || words.contains("autocar") { self = .bus }
        else if words.contains("train") { self = .transilien }   // «Train» a secas (R3)
        else { self = .other }
    }

    /// Medido el 30/08: metro, bus y tranvía no publican vía jamás. Solo es
    /// la reserva: el servidor manda `platform_expected` en cada tramo.
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

    init(id: Int, name: String, originName: String = "", destName: String = "") {
        self.id = id
        self.name = name
        self.originName = originName
        self.destName = destName
    }
}

/// El tablero (`BoardV1`).
struct Board: Codable, Hashable, Sendable {
    /// Sin recibir un tablero nuevo durante más de esto, el dato es viejo y
    /// se apaga el tablero entero (R19). Nunca por `data_age`.
    static let staleAfter: TimeInterval = 90
    /// El refresco nunca baja de aquí, diga lo que diga el servidor (R7).
    static let minimumRefresh: TimeInterval = 30

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
    /// Estado del servidor (clave PRIM, cuota, cada cuánto refrescar).
    var server: ServerState?
    /// false si no se pudieron leer los avisos: el «normal» no es de fiar.
    var disruptionsOK: Bool

    /// Cuándo llegó al teléfono. La antigüedad que se enseña se cuenta desde
    /// aquí y no desde `updated_at` (R17): si el móvil pierde la red, lo que
    /// envejece es lo que tenemos en la mano. No viaja en el JSON: la caché lo
    /// guarda aparte (`CachedBoard`, R20).
    var receivedAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case route, legs, worstLevel, worstLine, maxDelay, updatedAt
        case dataAge, stale, errors, quota, lastError, autoSelected
        case server
        // `disruptions_ok` → «disruptionsOk» con convertFromSnakeCase.
        case disruptionsOK = "disruptionsOk"
        case age
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        route         = c.opt(.route)
        legs          = c.get(.legs, [])
        worstLevel    = c.get(.worstLevel, 0)
        worstLine     = c.get(.worstLine, "")
        maxDelay      = c.get(.maxDelay, 0)
        updatedAt     = c.get(.updatedAt, "")
        // R22: los ficheros antiguos traen "age" donde ahora va "data_age".
        dataAge       = c.get(.dataAge, c.get(.age, 0))
        stale         = c.get(.stale, false)
        errors        = c.get(.errors, [])
        quota         = c.get(.quota, [:])
        lastError     = c.opt(.lastError)
        autoSelected  = c.get(.autoSelected, false)
        server        = c.opt(.server)
        disruptionsOK = c.get(.disruptionsOK, true)
        receivedAt    = .now
    }

    init(route: BoardRoute?, legs: [Leg], worstLevel: Int = 0, worstLine: String = "",
         maxDelay: Double = 0, updatedAt: String = "", dataAge: Double = 0,
         stale: Bool = false, errors: [String] = [], quota: [String: Int] = [:],
         lastError: String? = nil, autoSelected: Bool = true,
         server: ServerState? = nil, disruptionsOK: Bool = true,
         receivedAt: Date = .now) {
        self.route = route
        self.legs = legs
        self.worstLevel = worstLevel
        self.worstLine = worstLine
        self.maxDelay = maxDelay
        self.updatedAt = updatedAt
        self.dataAge = dataAge
        self.stale = stale
        self.errors = errors
        self.quota = quota
        self.lastError = lastError
        self.autoSelected = autoSelected
        self.server = server
        self.disruptionsOK = disruptionsOK
        self.receivedAt = receivedAt
    }

    /// Se escribe a mano porque `receivedAt` no es del servidor —se guarda
    /// aparte, junto a la caché— y porque `age` solo existe para leer los
    /// ficheros de prueba antiguos. Sale con la forma de la API (snake_case
    /// con `JSONEncoder.trajet`).
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
        try c.encodeIfPresent(server, forKey: .server)
        try c.encode(disruptionsOK, forKey: .disruptionsOK)
    }

    /// Segundos de antigüedad de lo que se está viendo: desde la llegada al
    /// teléfono, más lo que ya traía el servidor (R17).
    func ageSeconds(now: Date = .now) -> Double {
        max(0, now.timeIntervalSince(receivedAt)) + dataAge
    }

    /// Con el dato viejo se apaga el tablero entero, no solo una etiqueta
    /// (R19): `stale` del servidor o más de 90 s sin recibir un tablero.
    /// Nunca por `data_age`: una estación con el tren a 40 min se pide cada
    /// 5 min y no por eso es un dato viejo.
    func isStale(now: Date = .now) -> Bool {
        stale || now.timeIntervalSince(receivedAt) > Self.staleAfter
    }

    var hasContent: Bool { !legs.isEmpty }

    /// Llamadas que quedan hoy en el endpoint que consume el tablero (R46).
    var remainingCalls: Int? { quota["stop-monitoring"] }

    /// Cada cuánto conviene volver a pedirlo: `server.refresh_hint_s`, nunca
    /// por debajo de 30 s.
    var refreshInterval: TimeInterval {
        max(Self.minimumRefresh, TimeInterval(server?.refreshHintS ?? 30))
    }
}

/// Lo que devuelve GET /api/v1/board: un tablero, o el aviso de que aún no
/// hay rutas (`BoardEmptyV1`). Un error nunca llega aquí: va como `APIError`.
enum BoardPayload: Sendable, Hashable {
    case board(Board)
    case empty(message: String, server: ServerState?)

    var board: Board? {
        if case .board(let b) = self { return b }
        return nil
    }

    var server: ServerState? {
        switch self {
        case .board(let b): b.server
        case .empty(_, let server): server
        }
    }
}

extension BoardPayload: Decodable {
    private enum Keys: String, CodingKey { case empty, message, server }

    init(from decoder: Decoder) throws {
        // Si no es un objeto JSON, esto sí lanza: no hay nada que enseñar.
        let c = try decoder.container(keyedBy: Keys.self)
        if c.get(.empty, false) {
            self = .empty(message: c.get(.message, "todavía no hay rutas guardadas"),
                          server: c.opt(.server))
        } else {
            self = .board(try Board(from: decoder))
        }
    }
}
