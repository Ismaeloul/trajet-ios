import Foundation

// Lógica del tablero que NO es vista: qué se dice, qué se enseña y cuándo.
// Son funciones puras sobre los modelos de la API (docs/openapi.yaml, nada
// inventado), para poder probarlas sin pintar nada
// (TrajetTests/BoardViewLogicTests.swift). Las vistas de Views/Board/ solo
// pintan lo que sale de aquí.

// MARK: - Preferencias

/// Preferencias que usa el tablero. Las enseña Ajustes.
enum BoardPreferences {
    /// «Vibrar cuando aparece la vía» (ajustes-b.md A34). Por defecto, sí.
    static let platformHapticKey = "board.platformHaptic"
}

// MARK: - Qué ocupa la pantalla (R9, R53)

/// Qué se enseña debajo de la cabecera. El orden importa: si hay un tablero
/// guardado se enseña ESE, pase lo que pase (R9); la pantalla sin tablero
/// solo dice por qué cuando no hay nada que enseñar.
enum BoardContentState: Equatable, Sendable {
    /// Primera vez y nada en disco: esqueleto.
    case loading
    /// El servidor dice que no hay rutas (`BoardEmptyV1`).
    case noRoutes(String)
    /// Falla y no hay nada guardado: el estado diseñado de ese fallo.
    case issue(BoardIssue)
    /// Hay ruta pero sin tramos (rareza F23 de la v1).
    case noLegs
    /// El tablero.
    case board

    static func make(board: Board?, emptyMessage: String?, issue: BoardIssue?) -> BoardContentState {
        if let board { return board.hasContent ? .board : .noLegs }
        if let emptyMessage { return .noRoutes(emptyMessage) }
        if let issue { return .issue(issue) }
        return .loading
    }
}

/// Textos de los estados de error a pantalla completa (sin tablero guardado).
enum BoardIssueCopy {
    static func title(_ issue: BoardIssue) -> String {
        switch issue {
        case .offline: "No se llega al servidor"
        case .noKey: "El servidor no tiene clave de PRIM"
        case .keyRejected: "PRIM no acepta la clave"
        case .quotaExhausted: "Se acabó la cuota de hoy"
        case .upstream: "PRIM no responde"
        case .notPaired: "Este iPhone no está emparejado"
        case .other: "El servidor ha dado un error"
        }
    }

    static func message(_ issue: BoardIssue) -> String {
        switch issue {
        case .offline(let detail):
            detail.isEmpty ? "Ni por la red de casa ni por Tailscale." : detail
        case .noKey:
            "Ponla en el panel de Trajet del Umbrel y vuelve a probar."
        case .keyRejected, .quotaExhausted, .upstream, .notPaired, .other:
            issue.message
        }
    }

    static func symbol(_ issue: BoardIssue) -> String {
        switch issue {
        case .noKey, .keyRejected: "key.fill"
        case .offline, .quotaExhausted, .upstream, .notPaired, .other: issue.symbol
        }
    }

    /// «Reintentar» tiene sentido salvo si hay que volver a emparejar.
    static func allowsRetry(_ issue: BoardIssue) -> Bool {
        issue != .notPaired
    }

    /// Se ofrece abrir los ajustes del servidor.
    static func offersServerSettings(_ issue: BoardIssue) -> Bool {
        switch issue {
        case .noKey, .keyRejected: true
        case .offline, .quotaExhausted, .upstream, .notPaired, .other: false
        }
    }

    /// Se ofrece volver a emparejar.
    static func offersRepair(_ issue: BoardIssue) -> Bool {
        issue == .notPaired
    }
}

// MARK: - La vía (R2, R3, R10)

/// Qué vía se enseña para una salida. Solo hay hueco si el tramo publica vía
/// (`platform_expected`, R3); la real manda sobre la probable; sin ninguna de
/// las dos, NADA, ni hueco (R2).
enum BoardPlatformState: Hashable, Sendable {
    case none
    case real(String)
    case probable(PlatformGuess)

    init(departure: Departure, leg: Leg) {
        guard leg.showsPlatform else {
            self = .none
            return
        }
        if departure.hasRealPlatform, let platform = departure.platform {
            self = .real(platform)
        } else if let guess = departure.guess, !guess.platform.isEmpty {
            self = .probable(guess)
        } else {
            self = .none
        }
    }

    var guess: PlatformGuess? {
        if case .probable(let guess) = self { return guess }
        return nil
    }

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    /// Identidad para animar el cambio (probable → real, aparece la vía).
    var key: String {
        switch self {
        case .none: "none"
        case .real(let platform): "real|\(platform)"
        case .probable(let guess): "probable|\(guess.platform)"
        }
    }

    /// ¿Se destaca como vía NUEVA (latido, háptica)? Solo con el dato vivo
    /// (nada de latidos con el tablero apagado, ajustes-b.md A3) y durante
    /// `Motion.Timing.viaNewWindow` (25 s) desde que apareció: lo que dice
    /// `BoardStore.lastPlatformEvent` o, si no, `platform_new` del servidor
    /// contado desde que llegó el tablero.
    static func isNew(departure: Departure, leg: Leg, event: PlatformEvent?,
                      receivedAt: Date, now: Date, live: Bool) -> Bool {
        guard live, case .real(let platform) = BoardPlatformState(departure: departure, leg: leg) else {
            return false
        }
        let window = Motion.Timing.viaNewWindow
        if let event, event.legSeq == leg.seq, event.departureID == departure.id, event.platform == platform {
            return now.timeIntervalSince(event.at) < window
        }
        return departure.platformNew && now.timeIntervalSince(receivedAt) < window
    }
}

// MARK: - Lo que dice VoiceOver (R50)

/// Cada salida se lee como UNA frase completa (R50): «Tren a Ermont -
/// Eaubonne, en 6 minutos, a las 12:56, vía 21, tren largo.». Con la
/// concordancia bien (la v1 decía «en 1 horas»).
enum BoardSpeech {

    /// «1 minuto», «6 minutos».
    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    /// «6 minutos», «1 hora», «1 hora y 46 minutos», «2 horas y 1 minuto».
    static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return count(m, "minuto", "minutos") }
        let hours = count(m / 60, "hora", "horas")
        let rest = m % 60
        return rest == 0 ? hours : "\(hours) y \(count(rest, "minuto", "minutos"))"
    }

    /// Antigüedad dicha en voz alta: «10 segundos», «4 minutos», «2 horas».
    static func age(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return count(s, "segundo", "segundos") }
        let m = s / 60
        if m < 60 { return count(m, "minuto", "minutos") }
        return count(m / 60, "hora", "horas")
    }

    /// «en 6 minutos», «sale ya», «parado en el andén» (R15).
    static func moment(_ departure: Departure) -> String {
        switch DepartureMoment(departure) {
        case .atStop: "parado en el andén"
        case .now: "sale ya"
        case .inMinutes(let m): "en \(duration(minutes: m))"
        }
    }

    /// El vehículo que se nombra al principio; nil si el modo no se conoce.
    static func vehicle(_ mode: TransportMode) -> String? {
        switch mode {
        case .metro: "Metro"
        case .rer, .transilien, .ter: "Tren"
        case .tram: "Tranvía"
        case .bus: "Bus"
        case .other: nil
        }
    }

    /// «2 minutos de retraso», «1 minuto de adelanto» (R14, R4).
    static func delay(_ departure: Departure) -> String? {
        guard let d = BoardText.visibleDelay(departure) else { return nil }
        return d > 0
            ? "\(count(d, "minuto", "minutos")) de retraso"
            : "\(count(-d, "minuto", "minutos")) de adelanto"
    }

    /// «vía 21», «acaba de salir la vía 21», «vía 21 probable, 90 por ciento
    /// sobre 20 observaciones, por el número de tren» (R10, R49).
    static func platform(_ state: BoardPlatformState, isNew: Bool) -> String? {
        switch state {
        case .none:
            return nil
        case .real(let platform):
            return isNew ? "acaba de salir la vía \(platform)" : "vía \(platform)"
        case .probable(let guess):
            var text = "vía \(guess.platform) probable, \(guess.percent) por ciento"
            text += " sobre \(count(guess.samples, "observación", "observaciones"))"
            let why = guess.why.trimmingCharacters(in: .whitespacesAndNewlines)
            if !why.isEmpty { text += ", \(why)" }
            return text
        }
    }

    /// La frase entera de una salida.
    static func sentence(_ departure: Departure, leg: Leg, isNewPlatform: Bool = false) -> String {
        var parts: [String] = []
        let destination = departure.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (vehicle(leg.mode), destination.isEmpty) {
        case (let name?, false): parts.append("\(name) a \(destination)")
        case (nil, false): parts.append("Hacia \(destination)")
        case (let name?, true): parts.append(name)
        case (nil, true): parts.append("Salida")
        }
        if departure.isCancelled { parts.append("suprimido") }
        parts.append(moment(departure))
        if case .inMinutes = DepartureMoment(departure), !departure.at.isEmpty {
            parts.append("a las \(departure.at)")
        }
        if let delay = delay(departure) { parts.append(delay) }
        let state = BoardPlatformState(departure: departure, leg: leg)
        if let platform = platform(state, isNew: isNewPlatform) { parts.append(platform) }
        if let length = departure.length { parts.append(length.label.lowercased()) }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Textos del tablero

enum BoardText {

    /// El retraso que se enseña: solo si hay hora teórica (R4) y no es cero
    /// (R14). Con signo.
    static func visibleDelay(_ departure: Departure) -> Int? {
        guard !departure.aimedAt.isEmpty else { return nil }
        return departure.realDelay
    }

    /// «+2 min», «-1 min», o nada.
    static func delay(_ departure: Departure) -> String? {
        visibleDelay(departure).map(Fmt.delay)
    }

    /// Ritmo «¿corro o no corro?» (R16): la etiqueta del billete.
    static func pace(_ pace: Pace) -> String {
        switch pace {
        case .run: "Corre"
        case .walk: "Anda"
        case .easy: "Con calma"
        }
    }

    /// La etiqueta de ritmo de una salida; nil «En andén» (R15, R16).
    static func paceLabel(for departure: Departure) -> String? {
        DepartureMoment(departure).pace.map { pace($0) }
    }

    /// «corto» / «largo» (R5).
    static func length(_ length: TrainLength) -> String {
        length == .short ? "corto" : "largo"
    }

    /// Porcentaje con espacio no separable («90 %», R56).
    static func percent(_ value: Int) -> String {
        "\(value)\u{00A0}%"
    }

    /// Título del tramo: parada de subida → bajada (o el primer sentido).
    static func legTitle(_ leg: Leg) -> (from: String, to: String) {
        let to = leg.toName.isEmpty ? (leg.directions.first ?? "") : leg.toName
        return (leg.fromName, to)
    }

    /// Debajo del título: «dirección X» o «todos los sentidos» si el tramo
    /// no filtra sentido y se mezclan destinos (R24).
    static func legSubtitle(_ leg: Leg) -> String? {
        if leg.mixesDestinations { return "todos los sentidos" }
        if !leg.directions.isEmpty { return "dirección " + leg.directions.joined(separator: " · ") }
        if let destination = leg.departures.first?.destination, !destination.isEmpty {
            return "dirección \(destination)"
        }
        return nil
    }

    /// Rótulo encima del nombre de la ruta (R37): quién la ha elegido.
    static func routeKicker(board: Board?, pinnedRouteID: Int?, isSwitching: Bool) -> String {
        if isSwitching { return "Cambiando de ruta…" }
        guard let board else { return pinnedRouteID == nil ? "Trajet" : "Ruta elegida" }
        if pinnedRouteID != nil || !board.autoSelected { return "Ruta elegida" }
        return "La que toca ahora"
    }

    /// «cada 30 s», «cada 2 min».
    static func every(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 60, s % 60 == 0 { return "cada \(s / 60) min" }
        return "cada \(s) s"
    }

    /// Pie (R46, R7): «640 llamadas hoy · se refresca cada 30 s mientras
    /// miras». El ritmo es el del servidor, nunca menos de 30 s.
    static func footer(board: Board) -> String {
        let rhythm = "se refresca \(every(board.refreshInterval)) mientras miras"
        guard let remaining = board.remainingCalls else { return rhythm }
        return "\(Fmt.quota(remaining)) · \(rhythm)"
    }

    /// Errores de estación del pie (R26): como mucho `limit`, y cuántos más.
    static func stationErrors(_ errors: [String], limit: Int = 3) -> (shown: [String], hidden: Int) {
        let clean = errors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let shown = Array(clean.prefix(max(0, limit)))
        return (shown, clean.count - shown.count)
    }

    /// El error de la estación de un tramo caído, si el servidor lo dice
    /// (`errors` va como «Parada: motivo»).
    static func stationError(for leg: Leg, in board: Board) -> String? {
        guard leg.stationFailed, !leg.fromName.isEmpty else { return nil }
        return board.errors.first { $0.hasPrefix(leg.fromName) }
    }

    /// «salidas de hace 3 min»: el tramo enseña sus últimas salidas buenas.
    static func retained(age seconds: Double) -> String {
        "salidas de \(Fmt.age(seconds)) · la estación no responde"
    }

    /// Obras con fecha futura (R28): no encienden el aviso, pero se dicen
    /// en el detalle aunque la línea esté normal.
    static func plannedWorks(_ count: Int, alongsideNotice: Bool) -> String? {
        guard count > 0 else { return nil }
        let lead = alongsideNotice ? "Además hay" : "Hay"
        return count == 1
            ? "\(lead) 1 aviso de obras con fecha futura, que no afecta a hoy."
            : "\(lead) \(count) avisos de obras con fecha futura, que no afectan a hoy."
    }

    /// Por qué la previsión dice esa vía (R49): «Sale por la 21 el 90 % de
    /// las veces (20 observaciones, por el número de tren).»
    static func probableExplanation(_ guess: PlatformGuess) -> String {
        var inside = BoardSpeech.count(guess.samples, "observación", "observaciones")
        let why = guess.why.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { inside += ", \(why)" }
        return "Sale por la \(guess.platform) el \(percent(guess.percent)) de las veces (\(inside))."
    }

    /// «próximo en 25 s» (la barra de refresco con «Reducir movimiento»,
    /// sistema.md §9.2 `refreshBar`), en pasos de 5 s.
    static func nextRefresh(in seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let s = Int((seconds / 5).rounded(.up)) * 5
        return s < 60 ? "próximo en \(s) s" : "próximo en \((s + 59) / 60) min"
    }

    /// A qué hora vuelve la cuota: `retry_after` si lo hay; si no, la
    /// medianoche UTC (R46), en la hora del teléfono.
    static func quotaReturn(now: Date, retryAfter: Int?, timeZone: TimeZone = .current) -> String {
        let target: Date
        if let retryAfter, retryAfter > 0 {
            target = now.addingTimeInterval(TimeInterval(retryAfter))
        } else {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            let today = utc.startOfDay(for: now)
            target = utc.date(byAdding: .day, value: 1, to: today) ?? now
        }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.hour, .minute], from: target)
        return String(format: "%02ld:%02ld", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Fichas 2.ª–4.ª (R24, R47, R14, R5)

/// Qué lleva una ficha. En compacto (5–6 tramos, R47) pierde la segunda
/// línea, pero el destino es obligatorio si el tramo mezcla destinos (R24)
/// y la vía nunca se quita.
struct BoardChipContent: Equatable, Sendable {
    /// Solo si el tramo mezcla destinos.
    let destination: String?
    /// La hora prevista, si no hay destino que decir.
    let time: String?
    let length: TrainLength?
    /// Con signo; solo si existe, es ≠ 0 y hay hora teórica.
    let delay: Int?
    let platform: BoardPlatformState

    init(departure: Departure, leg: Leg, density: BoardDensity) {
        let destination = departure.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        self.destination = leg.mixesDestinations && !destination.isEmpty ? destination : nil
        platform = BoardPlatformState(departure: departure, leg: leg)
        if density.chipShowsSecondLine {
            time = (self.destination == nil && !departure.at.isEmpty) ? departure.at : nil
            length = departure.length
            delay = BoardText.visibleDelay(departure)
        } else {
            time = nil
            length = nil
            delay = nil
        }
    }
}

// MARK: - Aviso de línea (R8, R27, R28)

/// El aviso de un tramo. En la tarjeta caben 2 mensajes (R27); el español si
/// ya está y, si no, el francés con «traduciendo» (R8). Las obras con fecha
/// futura NO encienden el aviso (R28): con nivel 0 no hay aviso.
struct BoardNotice: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        let text: String
        /// Sigue en francés (sin traducir): cursiva y voz francesa.
        let isFrench: Bool
    }

    /// Un mensaje en los dos idiomas, para el detalle (R27).
    struct Bilingual: Equatable, Sendable {
        let spanish: String?
        let french: String
    }

    let level: Int
    let title: String
    let lines: [Line]
    /// Mensajes que no caben en la tarjeta (van al detalle).
    let hiddenCount: Int
    let translating: Bool

    init?(status: LegStatus, limit: Int = 2) {
        guard status.level > 0 else { return nil }
        level = status.level
        title = Self.title(level: status.level)
        let all = Self.bilingual(status).map { pair -> Line in
            if let spanish = pair.spanish { return Line(text: spanish, isFrench: false) }
            return Line(text: pair.french, isFrench: true)
        }
        lines = Array(all.prefix(max(0, limit)))
        hiddenCount = max(0, all.count - lines.count)
        translating = status.awaitingTranslation
    }

    static func title(level: Int) -> String {
        switch level {
        case ...0: "Sin incidencias"
        case 1: "Perturbada"
        default: "Interrumpida"
        }
    }

    /// Todos los mensajes, en español (si ya está) y en francés.
    static func bilingual(_ status: LegStatus) -> [Bilingual] {
        status.messages.enumerated().map { index, french in
            let spanish: String? = index < status.messagesEs.count ? status.messagesEs[index] : nil
            let clean = spanish.flatMap { text -> String? in
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
            }
            return Bilingual(spanish: clean, french: french)
        }
    }
}

// MARK: - Tramo sin salidas (R25, R26)

/// Un tramo sin salidas no es un error del tablero: pasa de noche y pasa
/// cuando la línea está cortada. Los demás tramos siguen (R25).
enum BoardLegEmpty: Equatable, Sendable {
    /// La línea está interrumpida: «Sin circulación».
    case suspended
    /// La estación no ha respondido y no hay nada guardado (R26).
    case stationDown
    /// No quedan más salidas: «Servicio finalizado».
    case finished

    init?(leg: Leg) {
        guard leg.departures.isEmpty else { return nil }
        if leg.status.level >= 2 { self = .suspended }
        else if leg.stationFailed { self = .stationDown }
        else { self = .finished }
    }

    var title: String {
        switch self {
        case .suspended: "Sin circulación"
        case .stationDown: "No llega el dato de esta estación"
        case .finished: "Servicio finalizado"
        }
    }

    var subtitle: String {
        switch self {
        case .suspended, .finished: "no hay más salidas"
        case .stationDown: "los demás tramos siguen"
        }
    }

    /// El texto del detalle del tramo.
    var detail: String {
        switch self {
        case .suspended: "La línea no está circulando."
        case .stationDown: "No llega el dato de esta estación."
        case .finished: "No quedan más salidas hoy."
        }
    }

    var symbol: String {
        switch self {
        case .suspended: "nosign"
        case .stationDown: "antenna.radiowaves.left.and.right.slash"
        case .finished: "moon.zzz"
        }
    }
}

// MARK: - Píldora de estado (R9, R17, R18, R19)

/// La píldora de encima de los tramos: si el dato está vivo y de cuándo es.
/// La antigüedad se enseña SIEMPRE (R17, R18): desde la llegada al teléfono
/// más `data_age`. Con el dato viejo (R19) o un problema, la píldora es opaca
/// y dice por qué, sin apagarse con el resto del tablero.
struct BoardPill: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case live
        case degraded
        case stale
        case offline
        case noKey
        case serverError
    }

    let kind: Kind
    let text: String
    /// nil = el punto verde «en directo».
    let symbol: String?
    let spoken: String

    /// Cristal (dato vivo) u opaca (algo pasa).
    var isOpaque: Bool {
        switch kind {
        case .live, .degraded: false
        case .stale, .offline, .noKey, .serverError: true
        }
    }

    /// nil sin tablero: entonces la pantalla entera dice lo que pasa.
    static func make(board: Board?, issue: BoardIssue?, server: ServerState?,
                     now: Date, timeZone: TimeZone = .current) -> BoardPill? {
        guard let board else { return nil }
        let seconds = board.ageSeconds(now: now)
        let age = Fmt.age(seconds)
        let spokenAge = BoardSpeech.age(seconds)

        if let issue {
            switch issue {
            case .offline:
                return BoardPill(kind: .offline, text: "sin conexión · último tablero \(age)",
                                 symbol: "wifi.slash",
                                 spoken: "Sin conexión. Último tablero de hace \(spokenAge).")
            case .noKey:
                return noKey(age: age, spokenAge: spokenAge)
            case .keyRejected:
                return keyRejected(age: age, spokenAge: spokenAge)
            case .quotaExhausted(let retryAfter):
                return quota(now: now, retryAfter: retryAfter, timeZone: timeZone, age: age, spokenAge: spokenAge)
            case .upstream:
                return BoardPill(kind: .serverError, text: "PRIM no responde · \(age)",
                                 symbol: "exclamationmark.icloud",
                                 spoken: "PRIM no responde. Tablero de hace \(spokenAge).")
            case .notPaired:
                return BoardPill(kind: .serverError, text: "iPhone sin emparejar · \(age)",
                                 symbol: "iphone.slash",
                                 spoken: "Este iPhone ya no está emparejado. Tablero de hace \(spokenAge).")
            case .other:
                return BoardPill(kind: .serverError, text: "error del servidor · \(age)",
                                 symbol: "exclamationmark.icloud",
                                 spoken: "El servidor ha dado un error. Tablero de hace \(spokenAge).")
            }
        }

        switch server?.primKey {
        case .missing?:
            return noKey(age: age, spokenAge: spokenAge)
        case .invalid?, .forbidden?:
            return keyRejected(age: age, spokenAge: spokenAge)
        case .quotaExhausted?:
            return quota(now: now, retryAfter: nil, timeZone: timeZone, age: age, spokenAge: spokenAge)
        case .valid?, .unreachable?, .unknown?, nil:
            break
        }

        if board.isStale(now: now) {
            return BoardPill(kind: .stale, text: "dato viejo · \(age)",
                             symbol: "clock.badge.exclamationmark",
                             spoken: "Dato viejo, de hace \(spokenAge).")
        }
        if server?.degraded == true {
            let every = BoardText.every(server?.refreshInterval ?? board.refreshInterval)
            return BoardPill(kind: .degraded, text: "ahorrando cuota · \(every) · \(age)",
                             symbol: "tortoise",
                             spoken: "Dato de hace \(spokenAge). El servidor ahorra cuota y refresca \(every).")
        }
        return BoardPill(kind: .live, text: "en directo · \(age)", symbol: nil,
                         spoken: "Dato de hace \(spokenAge), en directo.")
    }

    private static func noKey(age: String, spokenAge: String) -> BoardPill {
        BoardPill(kind: .noKey, text: "servidor sin clave de PRIM · \(age)", symbol: "key.fill",
                  spoken: "El servidor no tiene clave de PRIM: ponla en el panel. Tablero de hace \(spokenAge).")
    }

    private static func keyRejected(age: String, spokenAge: String) -> BoardPill {
        BoardPill(kind: .serverError, text: "la clave de PRIM no vale · \(age)", symbol: "key.fill",
                  spoken: "PRIM no acepta la clave del servidor. Tablero de hace \(spokenAge).")
    }

    private static func quota(now: Date, retryAfter: Int?, timeZone: TimeZone,
                              age: String, spokenAge: String) -> BoardPill {
        let back = BoardText.quotaReturn(now: now, retryAfter: retryAfter, timeZone: timeZone)
        return BoardPill(kind: .serverError, text: "sin cuota hasta las \(back) · \(age)",
                         symbol: "gauge.with.dots.needle.100percent",
                         spoken: "Se acabó la cuota de hoy; vuelve a las \(back). Tablero de hace \(spokenAge).")
    }
}

// MARK: - Tirar para refrescar

/// Tirar para refrescar, con un mínimo de 3 s entre tirones: la cuota es de
/// 1000 llamadas al día (R7) y un tirón nervioso no debería gastar tres.
struct BoardRefreshThrottle: Equatable, Sendable {
    static let minimumGap: TimeInterval = 3

    private(set) var lastPull: Date?

    init() {}

    /// ¿Se deja refrescar ahora? Si sí, apunta la hora.
    mutating func allow(at now: Date) -> Bool {
        if let lastPull, now.timeIntervalSince(lastPull) < Self.minimumGap { return false }
        lastPull = now
        return true
    }
}

// MARK: - Hápticas (sistema.md §9.5)

/// Cuándo vibra el tablero. Nunca con el dato viejo ni en cada refresco:
/// solo cuando el momento clave se cumple (eso lo comprueba quien llama).
enum BoardHapticRules {

    /// La primera salida del primer tramo (la que se mira).
    struct Watch: Equatable, Sendable {
        let routeID: Int?
        let departureID: String
        let minutes: Int
        let atStop: Bool
    }

    /// El nivel de la línea peor, por ruta.
    struct LevelWatch: Equatable, Sendable {
        let routeID: Int?
        let level: Int
    }

    static func watch(board: Board?) -> Watch? {
        guard let board, let first = board.legs.first?.departures.first else { return nil }
        return Watch(routeID: board.route?.id, departureID: first.id, minutes: first.minutes, atStop: first.atStop)
    }

    static func levelWatch(board: Board?) -> LevelWatch? {
        guard let board else { return nil }
        return LevelWatch(routeID: board.route?.id, level: board.worstLevel)
    }

    /// «Tren a 2 min»: el mismo tren cruza los 2 minutos hacia abajo.
    static func trainSoon(from old: Watch?, to new: Watch?) -> Bool {
        guard let old, let new, old.routeID == new.routeID, old.departureID == new.departureID,
              !new.atStop else { return false }
        return old.minutes > 2 && new.minutes <= 2
    }

    /// El nivel de la línea SUBE en la misma ruta: perturbación o interrupción.
    static func levelHaptic(from old: LevelWatch?, to new: LevelWatch?) -> Haptic? {
        guard let old, let new, old.routeID == new.routeID, new.level > old.level else { return nil }
        return new.level >= 2 ? .interruption : .disruption
    }
}

// MARK: - Alternativas (R29, R30, R6, R56)

enum BoardAlternativesText {
    /// R30: pasar por otra línea que también está caída no es alternativa.
    static let unusable = "No sirve: pasa por la línea cortada"

    static func isUnusable(_ option: AlternativeOption) -> Bool { !option.usable }

    /// «Línea 13 interrumpida» (una por línea tocada).
    static func banner(_ affected: [AffectedLine]) -> String? {
        let parts = affected.map { line -> String in
            let label = line.label.isEmpty ? BoardNotice.title(level: line.level).lowercased() : line.label
            return "Línea \(line.lineCode) \(label)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «tu ruta tarda 47 min cuando funciona».
    static func baseline(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let unit = Fmt.minutesUnit(minutes).map { " \($0)" } ?? ""
        return "tu ruta tarda \(Fmt.minutes(minutes))\(unit) cuando funciona"
    }

    /// Sin opciones: por qué.
    static func emptyTitle(needed: Bool) -> String {
        needed
            ? "El calculador no encuentra otro camino ahora mismo."
            : "Ninguna línea de esta ruta está tocada."
    }

    /// «12:55 → 13:54» desde la hora cruda de Navitia (R56).
    static func times(_ option: AlternativeOption) -> String? {
        let from = option.departureTime
        let to = option.arrivalTime
        switch (from.isEmpty, to.isEmpty) {
        case (false, false): return "\(from) → \(to)"
        case (false, true): return "sale \(from)"
        case (true, false): return "llega \(to)"
        case (true, true): return nil
        }
    }

    /// «directo», «1 transbordo», «2 transbordos».
    static func transfers(_ n: Int) -> String {
        switch n {
        case ...0: "directo"
        case 1: "1 transbordo"
        default: "\(n) transbordos"
        }
    }

    /// La frase de VoiceOver de una opción.
    static func spoken(_ option: AlternativeOption) -> String {
        var parts = [BoardSpeech.duration(minutes: option.totalMinutes)]
        if let delta = option.deltaMinutes {
            if delta == 0 { parts.append("igual de rápido") }
            else if delta > 0 { parts.append("\(BoardSpeech.count(delta, "minuto", "minutos")) más de lo normal") }
            else { parts.append("\(BoardSpeech.count(-delta, "minuto", "minutos")) menos de lo normal") }
        }
        if !option.departureTime.isEmpty { parts.append("sale a las \(option.departureTime)") }
        if !option.arrivalTime.isEmpty { parts.append("llega a las \(option.arrivalTime)") }
        parts.append(transfers(option.transfers))
        for leg in option.legs {
            var text = "línea \(leg.code)"
            if !leg.direction.isEmpty { text += " dirección \(leg.direction)" }
            text += ", \(BoardSpeech.count(leg.minutes, "minuto", "minutos"))"
            if !leg.status.isEmpty, leg.status != "normal" { text += ", \(leg.status)" }
            parts.append(text)
        }
        if !option.usable { parts.append(unusable) }
        return parts.joined(separator: "; ") + "."
    }
}
