import Foundation
import Observation

// Lógica de Ajustes que NO es vista (F50–F52, sistema.md §7.15): qué se dice
// de las direcciones (R61, ATS), de la clave de PRIM (sin enseñarla nunca),
// de la cuota por endpoint (R46), del recolector, del traductor, de los
// permisos, de los widgets y la Live Activity (R60) y de la versión.
// Funciones puras para probarlas sin pintar nada (TrajetTests/
// StatsLogicTests.swift, clase `SettingsLogicTests`).

/// El color con que se dice un estado. La vista lo pasa a `okText`,
/// `warnText`, `badText` o `ink2` (nunca el relleno como texto).
enum SettingsTone: Equatable, Sendable {
    case ok
    case warn
    case bad
    case neutral
}

/// Un estado dicho con palabras y su tono.
struct SettingsStatus: Equatable, Sendable {
    var text: String
    var tone: SettingsTone
}

// MARK: - Direcciones del servidor (R61, ATS)

/// Qué tipo de dirección es, para saber si iOS dejará usarla por HTTP.
///
/// ATS (docs/decisiones.md, «Notas que la FASE 3 tiene que respetar»): la app
/// lleva `NSAllowsLocalNetworking` (RFC 1918, link-local, `.local` y nombres
/// sin dominio) y excepciones para `100.64.0.0/10` (Tailscale por IP) y
/// `ts.net` (nombres MagicDNS). Nada de `NSAllowsArbitraryLoads`: cualquier
/// otra dirección por HTTP la corta iOS.
enum ServerAddressKind: Equatable, Sendable {
    case empty
    case invalid
    case https
    case localNetwork
    case tailscaleIP
    case magicDNS
    case needsHTTPS
    /// IPv6 u otras que no se pueden juzgar desde aquí.
    case other
}

enum ServerAddressRules {

    static func classify(_ raw: String) -> ServerAddressKind {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let normalized = ServerConfig.normalize(trimmed),
              let comps = URLComponents(string: normalized),
              let rawHost = comps.host, !rawHost.isEmpty
        else { return .invalid }
        if comps.scheme?.lowercased() == "https" { return .https }
        let host = rawHost.lowercased()
        if host.contains(":") { return .other }
        if let octets = ipv4(host) {
            let (a, b) = (octets[0], octets[1])
            if a == 10 || a == 127 { return .localNetwork }
            if a == 172, (16...31).contains(b) { return .localNetwork }
            if a == 192, b == 168 { return .localNetwork }
            if a == 169, b == 254 { return .localNetwork }
            if a == 100, (64...127).contains(b) { return .tailscaleIP }
            return .needsHTTPS
        }
        if host == "ts.net" || host.hasSuffix(".ts.net") { return .magicDNS }
        if host.hasSuffix(".local") || !host.contains(".") { return .localNetwork }
        return .needsHTTPS
    }

    /// Los cuatro números de una IPv4, o nil si no lo es.
    static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(part), (0...255).contains(n)
            else { return nil }
            out.append(n)
        }
        return out
    }

    /// Lo que se dice debajo de una dirección (nil si no hay nada que decir).
    static func note(_ kind: ServerAddressKind) -> String? {
        switch kind {
        case .tailscaleIP:
            "Tailscale por IP (100.x): la app ya lleva la excepción de iOS para hablarle por HTTP."
        case .magicDNS:
            "Nombre MagicDNS de Tailscale (*.ts.net): también vale por HTTP."
        case .needsHTTPS:
            "iOS no deja hablar por HTTP con esta dirección. Usa la IP de casa, la de Tailscale (100.x), un nombre *.ts.net o HTTPS."
        case .invalid:
            "No parece una dirección: escribe algo como 192.168.1.10:7796."
        case .empty, .https, .localNetwork, .other:
            nil
        }
    }

    static func tone(_ kind: ServerAddressKind) -> SettingsTone {
        switch kind {
        case .needsHTTPS, .invalid: .warn
        case .empty, .https, .localNetwork, .tailscaleIP, .magicDNS, .other: .neutral
        }
    }

    /// El pie de la sección del servidor.
    static let footer = "Se guardan según escribes. La app prueba las dos, en este orden, y se queda con la que responde. Con Tailscale por IP (100.x.x.x) la app usa la excepción de seguridad de red que ya lleva; con el nombre MagicDNS (*.ts.net) también vale."
}

// MARK: - Probar la conexión

/// Lo que ha dicho una dirección al probarla con `ping`.
enum ConnectionProbeResult: Equatable, Sendable {
    case notTried
    case trying
    case answered(version: String, paired: Bool)
    case notTrajet
    case failed(String)

    var status: SettingsStatus? {
        switch self {
        case .notTried:
            return nil
        case .trying:
            return SettingsStatus(text: "probando…", tone: .neutral)
        case .answered(let version, let paired):
            let name = version.isEmpty ? "Trajet" : "Trajet \(version)"
            return paired
                ? SettingsStatus(text: "responde · \(name)", tone: .ok)
                : SettingsStatus(text: "responde, pero no reconoce este iPhone", tone: .warn)
        case .notTrajet:
            return SettingsStatus(text: "responde algo que no es Trajet", tone: .bad)
        case .failed(let reason):
            return SettingsStatus(text: reason.isEmpty ? "no responde" : "no responde: \(reason)", tone: .bad)
        }
    }

    var answers: Bool {
        if case .answered = self { return true }
        return false
    }
}

/// «Probar conexión»: un `ping` a cada dirección (no gasta cuota ni pide
/// token), a la vez, y dice cuál responde.
@MainActor
@Observable
final class ConnectionProbeModel {
    private(set) var lan: ConnectionProbeResult = .notTried
    private(set) var tailscale: ConnectionProbeResult = .notTried
    private(set) var isRunning = false

    init() {}

    typealias Ping = @Sendable (String) async throws -> PingResponse

    /// Prueba las dos. Devuelve la primera que responde (casa antes que
    /// Tailscale), para recordarla.
    @discardableResult
    func run(lanURL: String?, tailscaleURL: String?, ping: @escaping Ping) async -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        let lanTarget = lanURL.flatMap(ServerConfig.normalize)
        let tsTarget = tailscaleURL.flatMap(ServerConfig.normalize)
        lan = lanTarget == nil ? .notTried : .trying
        tailscale = tsTarget == nil ? .notTried : .trying
        async let lanResult = Self.probe(lanTarget, ping: ping)
        async let tsResult = Self.probe(tsTarget, ping: ping)
        let (a, b) = await (lanResult, tsResult)
        lan = a
        tailscale = b
        if a.answers { return lanTarget }
        if b.answers { return tsTarget }
        return nil
    }

    func reset() {
        lan = .notTried
        tailscale = .notTried
    }

    nonisolated static func probe(_ url: String?, ping: Ping) async -> ConnectionProbeResult {
        guard let url else { return .notTried }
        do {
            let reply = try await ping(url)
            return reply.isTrajet ? .answered(version: reply.version, paired: reply.paired) : .notTrajet
        } catch let error as APIError {
            switch error {
            case .network(let message):
                return .failed(message)
            case .notFound, .decoding, .server, .unauthorized:
                return .notTrajet
            case .notPaired:
                return .failed(error.errorDescription ?? "")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Clave de PRIM (nunca se enseña: estado y origen)

enum PrimKeyText {
    static func status(_ prim: PrimState) -> SettingsStatus {
        let tone: SettingsTone
        switch prim.keyState {
        case .valid: tone = .ok
        case .unknown: tone = .neutral
        case .quotaExhausted, .unreachable: tone = .warn
        case .missing, .invalid, .forbidden: tone = .bad
        }
        return SettingsStatus(text: prim.keyState.label, tone: tone)
    }

    /// «guardada en el panel» / «del entorno del servidor»; nil sin clave.
    static func source(_ prim: PrimState) -> String? {
        prim.keySource == PrimKeySource.none ? nil : prim.keySource.label
    }

    /// Qué hacer, si hay algo que hacer.
    static func advice(_ prim: PrimState) -> String? {
        switch prim.keyState {
        case .missing: "El servidor no tiene clave de PRIM: ponla en el panel del servidor (Trajet en tu Umbrel)."
        case .invalid: "PRIM rechaza la clave: cámbiala en el panel del servidor."
        case .forbidden: "La clave no tiene permiso para alguna API de PRIM: revísala en el portal de PRIM."
        case .quotaExhausted: "Se ha gastado la cuota de hoy: vuelve a medianoche UTC."
        case .unreachable: "PRIM no responde ahora mismo; el tablero enseña lo último que tiene."
        case .valid, .unknown: nil
        }
    }

    /// «comprobada a las 12:40» (hora de aquí).
    static func checked(_ prim: PrimState, timeZone: TimeZone = .current) -> String? {
        guard let date = ISO8601Parsing.date(prim.checkedAt) else { return nil }
        return "comprobada a las \(clock(date, timeZone: timeZone))"
    }

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ClockTime.text(from: date, calendar: calendar)
    }
}

// MARK: - Cuota por endpoint (R46)

enum QuotaText {
    /// Tablero, Avisos, Buscador y lo demás detrás.
    static func ordered(_ endpoints: [QuotaEndpoint]) -> [QuotaEndpoint] {
        let order = ["stop-monitoring", "general-message", "navitia"]
        return endpoints.sorted { a, b in
            let ia = order.firstIndex(of: a.endpoint) ?? order.count
            let ib = order.firstIndex(of: b.endpoint) ?? order.count
            return ia == ib ? a.endpoint < b.endpoint : ia < ib
        }
    }

    /// «318 de 1000».
    static func usage(_ e: QuotaEndpoint) -> String {
        "\(e.used) de \(e.cap)"
    }

    /// «quedan 682» (lo más pesimista entre el contador propio y el de PRIM).
    static func remaining(_ e: QuotaEndpoint) -> String {
        e.remaining == 0 ? "no queda nada" : "quedan \(e.remaining)"
    }

    static func tone(_ level: QuotaLevel) -> SettingsTone {
        switch level {
        case .ok: .ok
        case .warn: .warn
        case .critical, .exhausted: .bad
        }
    }

    static func level(_ e: QuotaEndpoint) -> SettingsStatus {
        SettingsStatus(text: e.level.label, tone: tone(e.level))
    }

    /// «Tablero: 318 de 1000 llamadas hoy, quedan 682, normal.»
    static func spoken(_ e: QuotaEndpoint) -> String {
        "\(e.label): \(e.used) de \(e.cap) llamadas hoy, \(remaining(e)), \(e.level.label)."
    }

    /// El pie (R46): tope, reinicio a medianoche UTC (con la hora de aquí) y
    /// el ritmo del tablero.
    static func footer(_ q: QuotaSnapshot, timeZone: TimeZone = .current) -> String {
        let caps = Set(q.endpoints.map(\.cap))
        let cap = caps.count == 1 ? "\(caps.first ?? 1000) llamadas" : "un tope de llamadas"
        var text = "La cuota es de \(cap) al día por endpoint y se reinicia a medianoche UTC"
        if let date = q.resetsAtDate {
            text += " (a las \(PrimKeyText.clock(date, timeZone: timeZone)) aquí)"
        }
        text += ". " + refresh(q)
        return text
    }

    /// El ritmo del tablero según la cuota: nunca menos de 30 s (R7).
    static func refresh(_ q: QuotaSnapshot) -> String {
        let seconds = max(30, q.refreshHintS)
        let every = seconds < 60 ? "\(seconds) s" : (seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s")
        let base = "El tablero se refresca cada \(every), y solo mientras lo miras o en modo trayecto"
        return seconds > 30 ? base + ", para ahorrar cuota." : base + "."
    }

    /// Aviso general si la cuota no va bien.
    static func overall(_ q: QuotaSnapshot) -> SettingsStatus? {
        switch q.level {
        case .ok: nil
        case .warn: SettingsStatus(text: "Cuota justa: el servidor refresca más despacio para no quedarse sin ella.", tone: .warn)
        case .critical: SettingsStatus(text: "Cuota casi agotada: el servidor tira de la caché todo lo que puede.", tone: .bad)
        case .exhausted: SettingsStatus(text: "Cuota agotada: hasta medianoche UTC se ve lo último guardado.", tone: .bad)
        }
    }
}

// MARK: - Recolector de andenes y traductor

enum CollectorText {
    static func status(_ c: CollectorStatus) -> SettingsStatus {
        if !c.enabled { return SettingsStatus(text: "apagado", tone: .neutral) }
        if c.running { return SettingsStatus(text: "aprendiendo", tone: .ok) }
        return SettingsStatus(text: "parado", tone: .warn)
    }

    /// «última pasada a las 12:48:10 · 4 estaciones · 1 andén nuevo · …».
    static func detail(_ c: CollectorStatus) -> String? {
        var parts: [String] = []
        if !c.lastAt.isEmpty { parts.append("última pasada a las \(c.lastAt)") }
        if c.stations > 0 { parts.append(StatsText.count(c.stations, "estación", "estaciones")) }
        if c.recorded > 0 { parts.append(StatsText.count(c.recorded, "andén nuevo", "andenes nuevos")) }
        if c.enabled, c.interval > 0 {
            parts.append(c.interval >= 60 ? "la siguiente en \(c.interval / 60) min" : "la siguiente en \(c.interval) s")
        }
        let reason = c.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { parts.append(reason) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum TranslatorText {
    static func status(_ t: TranslatorStatus) -> SettingsStatus {
        t.ok ? SettingsStatus(text: "listo", tone: .ok) : SettingsStatus(text: "no disponible", tone: .warn)
    }

    /// El modelo, o por qué no está; y qué pasa mientras (R8).
    static func detail(_ t: TranslatorStatus) -> String? {
        if t.ok { return t.model.isEmpty ? nil : t.model }
        let reason = t.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = reason.isEmpty ? "" : "\(reason). "
        return why + "Los avisos se ven en francés mientras tanto."
    }
}

// MARK: - Este dispositivo

enum DeviceText {
    static let spanish = Locale(identifier: "es_ES")

    /// «emparejado el 24 de septiembre de 2026».
    static func pairedOn(_ device: DeviceInfo, timeZone: TimeZone = .current) -> String? {
        guard let date = ISO8601Parsing.date(device.createdAt) else { return nil }
        let style = Date.FormatStyle(date: .long, time: .omitted, locale: spanish,
                                     calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
        return "emparejado el \(date.formatted(style))"
    }

    /// «último uso hace 2 min».
    static func lastUsed(_ device: DeviceInfo, now: Date = Date()) -> String? {
        guard let date = ISO8601Parsing.date(device.lastUsedAt) else { return nil }
        return "último uso \(Fmt.age(max(0, now.timeIntervalSince(date))))"
    }

    /// «iPhone17,1 · app 2.0 (1)».
    static func detail(_ device: DeviceInfo) -> String? {
        var parts: [String] = []
        if !device.model.isEmpty { parts.append(device.model) }
        if !device.appVersion.isEmpty { parts.append("app \(device.appVersion)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Permisos

enum PermissionText {
    static func location(_ authorization: LocationAuthorization) -> SettingsStatus {
        switch authorization {
        case .notDetermined: SettingsStatus(text: "sin preguntar", tone: .neutral)
        case .denied: SettingsStatus(text: "denegada", tone: .bad)
        case .whenInUse: SettingsStatus(text: "al usar la app", tone: .ok)
        case .always: SettingsStatus(text: "siempre", tone: .ok)
        }
    }

    /// Qué se puede hacer con el permiso que hay.
    static func locationNote(_ authorization: LocationAuthorization) -> String {
        switch authorization {
        case .notDetermined:
            "Se pide al empezar un trayecto, no antes."
        case .denied:
            "El modo trayecto funciona sin ubicación, pero no se apaga solo al llegar ni hay geocercas."
        case .whenInUse:
            "El modo trayecto funciona entero. Las geocercas necesitan «Siempre»."
        case .always:
            "El modo trayecto y las geocercas funcionan. Fuera de un trayecto solo lo vigila el sistema, sin GPS."
        }
    }

    static func camera(_ permission: CameraPermission) -> SettingsStatus {
        switch permission {
        case .notDetermined: SettingsStatus(text: "sin preguntar", tone: .neutral)
        case .authorized: SettingsStatus(text: "permitida", tone: .ok)
        case .denied: SettingsStatus(text: "denegada", tone: .bad)
        case .restricted: SettingsStatus(text: "restringida", tone: .bad)
        case .unavailable: SettingsStatus(text: "no hay cámara", tone: .neutral)
        }
    }

    static let cameraNote = "Solo para escanear el QR del panel al emparejar."

    /// R45: sin permiso de red local solo funciona Tailscale.
    static let localNetworkNote = "iOS la pide la primera vez que la app habla con la red de casa. Sin ella solo funciona Tailscale: si «Red de casa» no responde, mira Ajustes › Privacidad y seguridad › Red local › Trajet."
}

// MARK: - Widgets y Live Activity (R60)

/// Qué extras tiene esta instalación. La lite y la full sin App Group no los
/// tienen, y se dice con una frase en vez de romperse (R60).
enum ExtrasAvailability: Equatable, Sendable {
    case lite
    case noAppGroup
    case available(liveActivitiesEnabled: Bool)

    static func make(isLite: Bool, hasAppGroup: Bool, liveActivitiesEnabled: Bool) -> ExtrasAvailability {
        if isLite { return .lite }
        if !hasAppGroup { return .noAppGroup }
        return .available(liveActivitiesEnabled: liveActivitiesEnabled)
    }

    /// La de esta instalación.
    static func current() -> ExtrasAvailability {
        make(isLite: Capabilities.isLite, hasAppGroup: Capabilities.hasAppGroup,
             liveActivitiesEnabled: Capabilities.liveActivitiesAvailable)
    }

    var widgets: SettingsStatus {
        switch self {
        case .lite, .noAppGroup: SettingsStatus(text: "no disponibles", tone: .neutral)
        case .available: SettingsStatus(text: "disponibles", tone: .ok)
        }
    }

    var liveActivity: SettingsStatus {
        switch self {
        case .lite, .noAppGroup: SettingsStatus(text: "no disponible", tone: .neutral)
        case .available(let enabled):
            enabled ? SettingsStatus(text: "disponible", tone: .ok)
                : SettingsStatus(text: "apagada en Ajustes", tone: .warn)
        }
    }

    var explanation: String? {
        switch self {
        case .lite:
            "Esta es la versión «lite», para firmar con un Apple ID gratuito: no lleva widgets ni Live Activity porque necesitan un App Group, que esa firma no da. Todo lo demás funciona igual."
        case .noAppGroup:
            "Esta instalación no tiene App Group (la firma no lo ha incluido), así que no hay widgets ni Live Activity. Todo lo demás funciona igual."
        case .available(let enabled):
            enabled
                ? "Los widgets leen el último tablero guardado; la Live Activity sale al empezar un trayecto."
                : "Las Live Activities están apagadas para Trajet: actívalas en Ajustes › Trajet."
        }
    }
}

// MARK: - Versión

enum AppVersionText {
    /// «2.0 (1)» con `CFBundleShortVersionString` y `CFBundleVersion`.
    static func make(short: String?, build: String?) -> String {
        let s = (short ?? "").trimmingCharacters(in: .whitespaces)
        let b = (build ?? "").trimmingCharacters(in: .whitespaces)
        switch (s.isEmpty, b.isEmpty) {
        case (true, true): return "—"
        case (false, true): return s
        case (true, false): return "(\(b))"
        case (false, false): return "\(s) (\(b))"
        }
    }

    static var current: String {
        make(short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }
}

// MARK: - Modo trayecto

enum TripSettingsText {
    static let step = 15

    /// 90 → «1h30»; 45 → «45 min» (R6).
    static func maxMinutes(_ minutes: Int) -> String {
        let unit = Fmt.minutesUnit(minutes).map { " \($0)" } ?? ""
        return Fmt.minutes(minutes) + unit
    }

    static let maxMinutesFooter = "El trayecto se apaga solo al llegar o, como muy tarde, al pasar este tiempo. Nunca se queda encendido siempre."

    static let alwaysNeeded = "Las geocercas necesitan el permiso de ubicación «Siempre». Cámbialo en Ajustes › Trajet › Ubicación."

    static func stationsFooter(usesDefault: Bool) -> String {
        usesDefault
            ? "Ahora: las paradas donde empiezan tus rutas. Toca para elegir otras."
            : "Elegidas a mano."
    }
}
