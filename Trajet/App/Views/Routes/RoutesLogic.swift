import Foundation
import Observation

// Lógica de Rutas, del editor, de «montar un tramo» y del planificador que NO
// es vista: las reglas de los buscadores (R31), las etiquetas de horario y
// días (R35, R36), la franja que calcula el servidor (R38), el cuerpo que se
// manda al guardar (`RouteInput`), el orden de las rutas (`position`) y el
// planificador (R33, R34). Funciones puras sobre los modelos de la API
// (docs/openapi.yaml, nada inventado), para probarlas sin pintar nada
// (TrajetTests/RoutesLogicTests.swift).

// MARK: - Buscadores (R31)

/// Los buscadores gastan cuota de PRIM (Navitia): no se busca por tecla.
/// Mínimo 2 caracteres (tras recortar espacios) y 350 ms sin escribir; cada
/// tecla cancela la búsqueda anterior.
enum SearchRules {
    static let minimumCharacters = 2
    /// El contrato no acepta más (`q`: maxLength 80).
    static let maximumCharacters = 80
    static let delay: Duration = .milliseconds(350)

    /// El texto que se manda, o nil si no llega al mínimo.
    static func query(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumCharacters else { return nil }
        return String(text.prefix(maximumCharacters))
    }
}

/// Espera 350 ms sin teclas antes de buscar y cancela la búsqueda anterior
/// en cada tecla (R31). El reloj se inyecta para probarlo sin esperar.
@MainActor
final class SearchDebouncer {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let sleep: Sleeper
    private var task: Task<Void, Never>?

    init(sleep: Sleeper? = nil) {
        if let sleep {
            self.sleep = sleep
        } else {
            self.sleep = { duration in try await Task.sleep(for: duration) }
        }
    }

    /// Programa una búsqueda con lo escrito. Devuelve false si el texto no
    /// llega al mínimo: entonces no se busca nada (y lo que hubiera en
    /// marcha se cancela).
    @discardableResult
    func schedule(_ raw: String, perform: @escaping @MainActor @Sendable (String) async -> Void) -> Bool {
        task?.cancel()
        task = nil
        guard let query = SearchRules.query(raw) else { return false }
        let sleep = self.sleep
        task = Task { @MainActor in
            do {
                try await sleep(SearchRules.delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await perform(query)
        }
        return true
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Espera a que termine lo programado (para los tests).
    func waitForPending() async {
        await task?.value
    }
}

/// En qué punto está un buscador.
enum SearchPhase: Equatable, Sendable {
    /// Nada escrito, o menos de 2 caracteres.
    case idle
    case searching
    /// Terminado (con o sin resultados).
    case done
    case failed(String)
}

/// Buscador de paradas del editor manual (`/search/stops`).
@MainActor
@Observable
final class StopSearchModel {
    private(set) var phase: SearchPhase = .idle
    private(set) var results: [StopResult] = []
    private let debouncer: SearchDebouncer

    init(debouncer: SearchDebouncer? = nil) {
        self.debouncer = debouncer ?? SearchDebouncer()
    }

    /// Cada tecla. `fetch` es la llamada al servidor.
    func textChanged(_ raw: String, fetch: @escaping @Sendable (String) async throws -> [StopResult]) {
        let scheduled = debouncer.schedule(raw) { [weak self] query in
            await self?.run(query, fetch: fetch)
        }
        if !scheduled {
            results = []
            phase = .idle
        }
    }

    func waitForPending() async {
        await debouncer.waitForPending()
    }

    private func run(_ query: String, fetch: @Sendable (String) async throws -> [StopResult]) async {
        phase = .searching
        do {
            let found = try await fetch(query)
            guard !Task.isCancelled else { return }
            results = found
            phase = .done
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            phase = .failed(SearchText.failure(error))
        }
    }
}

/// Buscador de sitios del planificador (`/search/places`): paradas,
/// direcciones y sitios.
@MainActor
@Observable
final class PlaceSearchModel {
    private(set) var phase: SearchPhase = .idle
    private(set) var results: [PlaceResult] = []
    private let debouncer: SearchDebouncer

    init(debouncer: SearchDebouncer? = nil) {
        self.debouncer = debouncer ?? SearchDebouncer()
    }

    func textChanged(_ raw: String, fetch: @escaping @Sendable (String) async throws -> [PlaceResult]) {
        let scheduled = debouncer.schedule(raw) { [weak self] query in
            await self?.run(query, fetch: fetch)
        }
        if !scheduled {
            results = []
            phase = .idle
        }
    }

    func waitForPending() async {
        await debouncer.waitForPending()
    }

    private func run(_ query: String, fetch: @Sendable (String) async throws -> [PlaceResult]) async {
        phase = .searching
        do {
            let found = try await fetch(query)
            guard !Task.isCancelled else { return }
            results = found
            phase = .done
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            phase = .failed(SearchText.failure(error))
        }
    }
}

enum SearchText {
    static let typeMore = "Escribe al menos 2 letras."
    static let noStops = "Ninguna parada con ese nombre."
    static let noPlaces = "Nada con ese nombre."

    static func failure(_ error: Error) -> String {
        if let api = error as? APIError, let text = api.errorDescription { return text }
        return "No se ha podido buscar."
    }

    /// «parada · Paris», «dirección · Argenteuil».
    static func placeSubtitle(_ place: PlaceResult) -> String {
        [place.kind, place.city].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Horas «HH:MM»

/// Horas como las guarda el servidor: «HH:MM» (hora de París).
enum ClockTime {
    /// «09:00» → 540. nil si no es una hora.
    static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        return h * 60 + m
    }

    /// 433 → «07:13». Se recorta a 00:00–23:59: no hay franjas que crucen
    /// la medianoche.
    static func text(minutes: Int) -> String {
        let m = min(max(minutes, 0), 23 * 60 + 59)
        return String(format: "%02ld:%02ld", m / 60, m % 60)
    }

    /// La hora como `Date` de hoy, para el selector nativo.
    static func date(_ text: String, calendar: Calendar = .current, on day: Date = Date()) -> Date {
        let m = minutes(text) ?? 9 * 60
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: start) ?? start
    }

    /// Lo que marca el selector nativo, en «HH:MM».
    static func text(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return text(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

/// Una franja «de … a …».
struct TimeWindow: Equatable, Sendable {
    var from: String
    var to: String
}

// MARK: - Textos de las rutas (R32, R35, R36, R38)

enum RouteText {
    static let weekdayLetters = ["L", "M", "X", "J", "V", "S", "D"]
    static let weekdayNames = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    /// Los días como los dice `SavedRoute.daysLabel` (R36: 0 = lunes), para
    /// lo que aún no está guardado (el editor).
    static func daysLabel(_ days: Set<Int>) -> String {
        let picked = days.sorted().compactMap { weekdayLetters.indices.contains($0) ? weekdayLetters[$0] : nil }
        if picked.count == 7 { return "todos los días" }
        if days == Set(0...4) { return "entre semana" }
        if days == Set([5, 6]) { return "fin de semana" }
        return picked.joined(separator: " ")
    }

    /// Los días para VoiceOver: «entre semana», «lunes, miércoles y viernes».
    static func spokenDays(_ days: [Int]) -> String {
        let set = Set(days.filter { weekdayNames.indices.contains($0) })
        if set.isEmpty { return "ningún día" }
        if set.count == 7 { return "todos los días" }
        if set == Set(0...4) { return "entre semana" }
        if set == Set([5, 6]) { return "fin de semana" }
        return list(set.sorted().map { weekdayNames[$0] })
    }

    /// «a, b y c».
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " y " + (items.last ?? "")
        }
    }

    /// El horario como se definió (R35), igual que `SavedRoute.scheduleLabel`:
    /// «llego 09:00», «salgo 08:00» o «07:00–10:00».
    static func scheduleLabel(mode: TimeMode, at: String, from: String, to: String) -> String {
        switch mode {
        case .arrival where !at.isEmpty: "llego \(at)"
        case .departure where !at.isEmpty: "salgo \(at)"
        default: "\(from)–\(to)"
        }
    }

    /// El horario para VoiceOver: «llego a las 09:00», «de 07:00 a 10:00».
    static func spokenSchedule(mode: TimeMode, at: String, from: String, to: String) -> String {
        switch mode {
        case .arrival where !at.isEmpty: "llego a las \(at)"
        case .departure where !at.isEmpty: "salgo a las \(at)"
        default: "de \(from) a \(to)"
        }
    }

    /// «entre semana · llego 09:00» (las etiquetas de R35 y R36).
    static func summary(_ route: SavedRoute) -> String {
        let days = route.daysLabel
        return days.isEmpty ? route.scheduleLabel : "\(days) · \(route.scheduleLabel)"
    }

    /// «origen → destino», o nil si no hay ninguno de los dos.
    static func endpoints(_ route: SavedRoute) -> String? {
        let from = route.originName.trimmingCharacters(in: .whitespaces)
        let to = route.destName.trimmingCharacters(in: .whitespaces)
        switch (from.isEmpty, to.isEmpty) {
        case (true, true): return nil
        case (false, true): return from
        case (true, false): return "→ \(to)"
        case (false, false): return "\(from) → \(to)"
        }
    }

    /// El sentido de un tramo (R32): «dirección Ermont - Eaubonne» o, sin
    /// ninguno elegido, «todos los sentidos» (se pinta como aviso).
    static func direction(_ directions: [String]) -> String {
        let clean = directions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return clean.isEmpty ? allDirections : "dirección " + clean.joined(separator: " · ")
    }

    static let allDirections = "todos los sentidos"

    /// Lo que pasa con un tramo sin sentido (R32).
    static let allDirectionsWarning = "Sin sentido elegido, el tablero enseña todos los pasos de la línea, en los dos sentidos."

    /// «Gare Saint-Lazare → Argenteuil» o solo la parada de subida.
    static func legTitle(fromName: String, toName: String) -> String {
        let from = fromName.isEmpty ? "Parada sin nombre" : fromName
        return toName.isEmpty ? from : "\(from) → \(toName)"
    }

    /// «de origen a destino», para VoiceOver.
    static func spokenEndpoints(_ route: SavedRoute) -> String? {
        let from = route.originName.trimmingCharacters(in: .whitespaces)
        let to = route.destName.trimmingCharacters(in: .whitespaces)
        switch (from.isEmpty, to.isEmpty) {
        case (true, true): return nil
        case (false, true): return "desde \(from)"
        case (true, false): return "hasta \(to)"
        case (false, false): return "de \(from) a \(to)"
        }
    }

    /// La tarjeta entera para VoiceOver.
    static func spoken(_ route: SavedRoute, isActive: Bool) -> String {
        var parts = [route.name.isEmpty ? "Ruta sin nombre" : route.name]
        if isActive { parts.append("es la que toca ahora") }
        if let endpoints = spokenEndpoints(route) {
            parts.append(endpoints)
        }
        parts.append(spokenDays(route.days))
        parts.append(spokenSchedule(mode: route.timeMode, at: route.timeAt, from: route.timeFrom, to: route.timeTo))
        if route.legs.isEmpty {
            parts.append("sin tramos")
        } else {
            let codes = route.legs.map { $0.lineCode.isEmpty ? $0.lineName : $0.lineCode }
            parts.append((codes.count == 1 ? "línea " : "líneas ") + list(codes))
        }
        return parts.joined(separator: ". ") + "."
    }

    /// La franja que calcula el servidor con «Llego a» / «Salgo a» (R38):
    /// salida → [hora − 45, hora + duración + 30]; llegada → [hora − duración
    /// − 45, hora + 15]. Sin duración conocida se cuenta 60 min. Recortada a
    /// 00:00–23:59. nil en «Franja» o sin hora.
    static func derivedWindow(mode: TimeMode, at: String, durationMin: Int) -> TimeWindow? {
        guard let t = ClockTime.minutes(at) else { return nil }
        let duration = durationMin > 0 ? durationMin : 60
        switch mode {
        case .departure:
            return TimeWindow(from: ClockTime.text(minutes: t - 45), to: ClockTime.text(minutes: t + duration + 30))
        case .arrival:
            return TimeWindow(from: ClockTime.text(minutes: t - duration - 45), to: ClockTime.text(minutes: t + 15))
        case .window:
            return nil
        }
    }

    /// El texto de ayuda de «Cuándo toca» (R38; corrige el de la v1, que no
    /// contaba los 30 min que el servidor añade tras llegar).
    static func windowExplanation(mode: TimeMode, at: String, durationMin: Int) -> String {
        let duration = durationMin > 0
            ? "con los \(durationMin) min que dura"
            : "contando 1 h de trayecto, porque la ruta a mano no sabe cuánto dura"
        switch mode {
        case .window:
            return "El tablero enseña esta ruta entre esas dos horas los días marcados."
        case .arrival:
            var text = "La franja se calcula hacia atrás desde la llegada, \(duration): empieza 45 min antes de salir y acaba 15 min después de llegar."
            if let w = derivedWindow(mode: mode, at: at, durationMin: durationMin) {
                text += " Ahora: de \(w.from) a \(w.to)."
            }
            return text
        case .departure:
            var text = "La franja va desde 45 min antes de salir hasta 30 min después de llegar, \(duration)."
            if let w = derivedWindow(mode: mode, at: at, durationMin: durationMin) {
                text += " Ahora: de \(w.from) a \(w.to)."
            }
            return text
        }
    }
}

// MARK: - Editor de ruta a mano

/// Lo que falta para poder guardar.
enum RouteEditorProblem: Equatable, Sendable, CaseIterable {
    case name
    case days
    case legs
    case window

    var text: String {
        switch self {
        case .name: "el nombre"
        case .days: "al menos un día"
        case .legs: "al menos un tramo"
        case .window: "una franja que no cruce la medianoche («Desde» antes que «Hasta»)"
        }
    }
}

/// El formulario del editor, como valor: se rellena desde una ruta guardada
/// (o con lo de fábrica), se toca y da el `RouteDraft` que se manda.
///
/// Origen y destino: si se dejan vacíos, salen de los tramos (la parada del
/// primero; la bajada o el primer sentido del último). Si la ruta traía unos
/// propios (p. ej. una dirección del planificador), se conservan aunque se
/// cambien los tramos.
struct RouteEditorState: Equatable, Sendable {
    var name: String
    var originName: String
    var destName: String
    /// Vacío = el que sale de los tramos.
    var originID: String
    var destID: String
    var days: Set<Int>
    var timeMode: TimeMode
    var timeAt: String
    var timeFrom: String
    var timeTo: String
    var legs: [RouteDraft.LegDraft]
    var durationMin: Int
    var position: Int

    /// Ruta nueva: lunes a viernes, «llego a las 09:00» (R36, F33); o la
    /// ruta guardada, tal cual.
    init(route: SavedRoute?) {
        guard let route else {
            let fresh = RouteDraft()
            name = fresh.name
            originName = ""
            destName = ""
            originID = ""
            destID = ""
            days = Set(fresh.days)
            timeMode = fresh.timeMode
            timeAt = fresh.timeAt
            timeFrom = fresh.timeFrom
            timeTo = fresh.timeTo
            legs = []
            durationMin = 0
            position = 0
            return
        }
        let legDrafts = route.legs.map { RouteDraft.LegDraft($0) }
        name = route.name
        legs = legDrafts
        days = Set(route.days)
        timeMode = route.timeMode
        timeAt = route.timeAt.isEmpty ? "09:00" : route.timeAt
        timeFrom = route.timeFrom
        timeTo = route.timeTo
        durationMin = route.durationMin
        position = route.position
        // Lo que coincide con lo que saldría de los tramos se deja vacío: así
        // sigue a los tramos si se cambian.
        let derived = Self.derive(legDrafts)
        originID = route.originId == derived.originID ? "" : route.originId
        destID = route.destId == derived.destID ? "" : route.destId
        originName = route.originName == derived.originName ? "" : route.originName
        destName = route.destName == derived.destName ? "" : route.destName
    }

    // MARK: Lo que sale de los tramos

    struct Derived: Equatable, Sendable {
        var originID: String
        var originName: String
        var destID: String
        var destName: String
    }

    static func derive(_ legs: [RouteDraft.LegDraft]) -> Derived {
        guard let first = legs.first, let last = legs.last else {
            return Derived(originID: "", originName: "", destID: "", destName: "")
        }
        let destID = last.toId.isEmpty ? last.fromId : last.toId
        let destName: String
        if !last.toName.isEmpty {
            destName = last.toName
        } else if let direction = last.directions.first(where: { !$0.isEmpty }) {
            destName = direction
        } else {
            destName = last.fromName
        }
        return Derived(originID: first.fromId, originName: first.fromName, destID: destID, destName: destName)
    }

    var derived: Derived { Self.derive(legs) }

    // MARK: Cambios

    mutating func toggleDay(_ day: Int) {
        guard (0...6).contains(day) else { return }
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
    }

    mutating func addLeg(_ leg: RouteDraft.LegDraft) {
        legs.append(leg)
    }

    mutating func removeLeg(at index: Int) {
        guard legs.indices.contains(index) else { return }
        legs.remove(at: index)
    }

    // MARK: Guardar

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Lo que falta para guardar (vacío = se puede).
    var problems: [RouteEditorProblem] {
        var out: [RouteEditorProblem] = []
        if trimmedName.isEmpty { out.append(.name) }
        if days.isEmpty { out.append(.days) }
        if legs.isEmpty { out.append(.legs) }
        if timeMode == .window {
            let from = ClockTime.minutes(timeFrom)
            let to = ClockTime.minutes(timeTo)
            if from == nil || to == nil || (from ?? 0) >= (to ?? 0) { out.append(.window) }
        }
        return out
    }

    var canSave: Bool { problems.isEmpty }

    /// «Para guardar falta: el nombre y al menos un tramo.»
    var problemsText: String? {
        let list = problems.map(\.text)
        guard !list.isEmpty else { return nil }
        return "Para guardar falta \(RouteText.list(list))."
    }

    /// Tramos que se verán en los dos sentidos (R32).
    var legsWithoutDirection: [RouteDraft.LegDraft] {
        legs.filter { leg in !leg.directions.contains { !$0.isEmpty } }
    }

    /// El cuerpo de POST/PUT /api/v1/routes (`RouteInput`), o nil si falta
    /// algo. Días ordenados; en «Franja» `time_at` va vacío (F35).
    func draft() -> RouteDraft? {
        guard canSave else { return nil }
        let d = derived
        let origin = originName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = destName.trimmingCharacters(in: .whitespacesAndNewlines)
        return RouteDraft(
            name: trimmedName,
            originId: originID.isEmpty ? d.originID : originID,
            originName: origin.isEmpty ? d.originName : origin,
            destId: destID.isEmpty ? d.destID : destID,
            destName: dest.isEmpty ? d.destName : dest,
            days: days.sorted(),
            timeFrom: timeFrom,
            timeTo: timeTo,
            timeMode: timeMode,
            timeAt: timeMode == .window ? "" : timeAt,
            durationMin: durationMin,
            position: position,
            legs: legs)
    }
}

// MARK: - Montar un tramo (F36–F38)

enum LegBuilderLogic {
    /// Las líneas de la parada TAL COMO LLEGAN del servidor: metro, RER,
    /// Transilien, TER, tranvía y los buses al final (R62). La app no
    /// reordena. Si la llamada falla o viene vacía, las que trajo el
    /// buscador (F37). Fuera las que no tienen id (no se pueden guardar).
    static func lines(loaded: [StopLine]?, fallback: [StopLine]) -> [StopLine] {
        let source: [StopLine]
        if let loaded, !loaded.isEmpty { source = loaded } else { source = fallback }
        return source.filter { !$0.id.isEmpty }
    }

    /// «14 · Métro», «Transilien J · Train Transilien».
    static func lineSubtitle(_ line: StopLine) -> String {
        var parts: [String] = []
        if !line.name.isEmpty, line.name != line.code { parts.append(line.name) }
        if !line.mode.isEmpty { parts.append(line.mode) }
        return parts.joined(separator: " · ")
    }

    /// Cabecera de la lista de sentidos (F38).
    static func directionsHeader(_ directions: [String]) -> String {
        directions.isEmpty ? "Ahora mismo no circula nada por aquí" : "Sentidos que circulan ahora"
    }

    static let allDirectionsFooter = "Si no eliges ninguno se enseñan todos los pasos de la línea, en los dos sentidos."

    /// El tramo que se añade. Los sentidos, en el orden en que los dio el
    /// servidor (de más a menos pasos) y solo de los que circulan (R32: se
    /// eligen, no se escriben). Sin elegir ninguno = todos.
    static func leg(stop: StopResult, line: StopLine, chosen: Set<String>, available: [String]) -> RouteDraft.LegDraft {
        let directions = available.filter { chosen.contains($0) }
        return RouteDraft.LegDraft(
            lineId: line.id,
            lineCode: line.code.isEmpty ? line.name : line.code,
            lineName: line.name,
            lineMode: line.mode,
            lineColor: line.color,
            fromId: stop.id,
            fromName: stop.name,
            directions: directions)
    }
}

// MARK: - Orden de las rutas (`position`)

enum RouteOrdering {
    /// Una ruta que tiene que cambiar de sitio.
    struct Update: Equatable, Sendable {
        var id: Int
        var position: Int
    }

    /// Los ids tras mover `source` a `destination` (la semántica de
    /// `onMove` de SwiftUI).
    static func move(_ ids: [Int], from source: IndexSet, to destination: Int) -> [Int] {
        let picked = source.filter { ids.indices.contains($0) }.sorted()
        guard !picked.isEmpty else { return ids }
        var items = ids
        let moving = picked.map { ids[$0] }
        for index in picked.reversed() { items.remove(at: index) }
        let before = picked.filter { $0 < destination }.count
        let insertAt = min(max(0, destination - before), items.count)
        items.insert(contentsOf: moving, at: insertAt)
        return items
    }

    /// Las rutas cuya `position` no casa con su sitio nuevo (0…n-1). El
    /// servidor ordena por `position` y luego por `id`, y la usa para
    /// desempatar la que toca (R37).
    static func updates(routes: [SavedRoute], order: [Int]) -> [Update] {
        var out: [Update] = []
        for (index, id) in order.enumerated() {
            guard let route = routes.first(where: { $0.id == id }) else { continue }
            if route.position != index { out.append(Update(id: id, position: index)) }
        }
        return out
    }
}

// MARK: - Planificador (R33, R34)

/// Cuándo se busca. «Llegar a» y «salir a» no son el mismo resultado
/// reordenado (R34): la API resuelve hacia atrás y solo entiende `arrival` y
/// `departure`; «ahora» es salir ya (sin `when`).
enum PlannerTiming: String, CaseIterable, Identifiable, Sendable {
    case arrival
    case departure
    case now

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrival: "Llegar a"
        case .departure: "Salir a"
        case .now: "Ahora"
        }
    }
}

/// Una búsqueda hecha (con lo que había en el formulario al buscar).
struct PlannerSearch: Equatable, Sendable {
    var from: PlaceResult
    var to: PlaceResult
    var timing: PlannerTiming
    /// «HH:MM» (se ignora con «ahora»).
    var time: String

    /// `when` de /api/v1/plan: nil = ahora.
    var apiWhen: String? { timing == .now ? nil : time }

    /// `mode` de /api/v1/plan (R34).
    var apiMode: TimeMode { timing == .arrival ? .arrival : .departure }

    /// El rótulo de los resultados, con el criterio de ESTA búsqueda (la v1
    /// usaba el del formulario, que puede haber cambiado: F42).
    var heading: String {
        switch timing {
        case .arrival: "Para llegar a las \(time)"
        case .departure: "Saliendo a las \(time)"
        case .now: "Saliendo ahora"
        }
    }
}

enum PlannerText {
    static let noOptions = "No hay ningún trayecto en transporte público entre esos dos puntos a esa hora."
    static let tip = "Toca «Guardar ruta» en el itinerario que uses de verdad: el tablero lo vigilará los días y a la hora que digas."

    /// El `kind` de Navitia en palabras (nil si no dice nada útil).
    static func kind(_ raw: String) -> String? {
        let k = raw.lowercased()
        switch k {
        case "best": return "Recomendado"
        case "rapid", "fastest": return "Más rápido"
        case "comfort": return "Más cómodo"
        case "less_walk": return "Menos a pie"
        default:
            return k.hasPrefix("less_fallback") ? "Menos a pie" : nil
        }
    }

    /// «08:07 → 08:54».
    static func times(_ option: PlanOption) -> String? {
        switch (option.departure.isEmpty, option.arrival.isEmpty) {
        case (false, false): "\(option.departure) → \(option.arrival)"
        case (false, true): "sale \(option.departure)"
        case (true, false): "llega \(option.arrival)"
        case (true, true): nil
        }
    }

    /// «1 transbordo · 11 min a pie» (R56).
    static func summary(_ option: PlanOption) -> String {
        var parts = [transfers(option.transfers)]
        if option.walkMinutes > 0 { parts.append("\(option.walkMinutes) min a pie") }
        return parts.joined(separator: " · ")
    }

    /// «directo», «1 transbordo», «2 transbordos».
    static func transfers(_ n: Int) -> String {
        switch n {
        case ...0: "directo"
        case 1: "1 transbordo"
        default: "\(n) transbordos"
        }
    }

    /// «17 min · sale 08:12» (minutos con «1h46» si hace falta, R6).
    static func legDetail(_ leg: PlanLeg) -> String {
        var parts: [String] = []
        if leg.minutes > 0 {
            let unit = Fmt.minutesUnit(leg.minutes).map { " \($0)" } ?? ""
            parts.append(Fmt.minutes(leg.minutes) + unit)
        }
        if !leg.at.isEmpty { parts.append("sale \(leg.at)") }
        return parts.joined(separator: " · ")
    }

    /// El tramo de una opción: «dirección Châtillon - Montrouge» o la bajada.
    static func legTitle(_ leg: PlanLeg) -> String {
        if !leg.direction.isEmpty { return "dirección \(leg.direction)" }
        if !leg.toName.isEmpty { return "hasta \(leg.toName)" }
        return "Línea \(leg.lineCode)"
    }

    /// La opción entera para VoiceOver.
    static func spoken(_ option: PlanOption) -> String {
        var parts = [BoardSpeech.duration(minutes: option.minutes)]
        if let kind = kind(option.kind) { parts.append(kind.lowercased()) }
        if !option.departure.isEmpty { parts.append("sale a las \(option.departure)") }
        if !option.arrival.isEmpty { parts.append("llega a las \(option.arrival)") }
        parts.append(transfers(option.transfers))
        if option.walkMinutes > 0 {
            parts.append("\(BoardSpeech.count(option.walkMinutes, "minuto", "minutos")) a pie")
        }
        for leg in option.legs {
            var text = "línea \(leg.lineCode.isEmpty ? leg.lineName : leg.lineCode)"
            if !leg.fromName.isEmpty { text += " desde \(leg.fromName)" }
            if !leg.direction.isEmpty { text += " dirección \(leg.direction)" }
            parts.append(text)
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Nombre por defecto al guardar: «Argenteuil → Montparnasse».
    static func defaultName(_ search: PlannerSearch) -> String {
        "\(search.from.name) → \(search.to.name)"
    }

    /// `meta` de POST /api/v1/routes/from-plan. «Llegar a» se guarda como
    /// «llego a» y «salir a» como «salgo a», con la hora pedida (R34, R35);
    /// «ahora» se guarda como «salgo a» a la hora a la que sale la opción.
    static func saveMeta(search: PlannerSearch, option: PlanOption, name: String, days: Set<Int>,
                         now: Date = Date(), calendar: Calendar = .current) -> PlanSaveRequest.Meta {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: TimeMode
        let at: String
        switch search.timing {
        case .arrival:
            mode = .arrival
            at = search.time
        case .departure:
            mode = .departure
            at = search.time
        case .now:
            mode = .departure
            at = ClockTime.minutes(option.departure) != nil ? option.departure : ClockTime.text(from: now, calendar: calendar)
        }
        return PlanSaveRequest.Meta(
            name: trimmed.isEmpty ? defaultName(search) : trimmed,
            originId: search.from.id,
            originName: search.from.name,
            destId: search.to.id,
            destName: search.to.name,
            days: days.sorted(),
            timeMode: mode,
            timeAt: at)
    }

    /// «Se guardará como «llego 09:00», y la franja se calculará con los
    /// 47 min que dura: de 07:28 a 09:15.»
    static func saveExplanation(meta: PlanSaveRequest.Meta, option: PlanOption) -> String {
        let label = RouteText.scheduleLabel(mode: meta.timeMode, at: meta.timeAt, from: meta.timeFrom, to: meta.timeTo)
        var text = "Se guardará como «\(label)»"
        if option.minutes > 0 {
            text += ", y la franja se calculará con los \(option.minutes) min que dura"
            if let w = RouteText.derivedWindow(mode: meta.timeMode, at: meta.timeAt, durationMin: option.minutes) {
                text += ": de \(w.from) a \(w.to)"
            }
        }
        return text + "."
    }

    /// Tramos guardados sin sentido porque el texto de Navitia no casaba con
    /// el del tiempo real. Se dice, no se calla (R33). nil si no hay.
    static func withoutDirection(_ codes: [String]) -> String? {
        let clean = codes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return nil }
        if clean.count == 1 {
            return "La línea \(clean[0]) se ha guardado sin sentido: el tablero enseñará sus pasos en los dos sentidos. Puedes elegirlo editando la ruta."
        }
        return "Las líneas \(RouteText.list(clean)) se han guardado sin sentido: el tablero enseñará sus pasos en los dos sentidos. Puedes elegirlo editando la ruta."
    }
}

/// El planificador: lo que hay en el formulario y lo que ha contestado el
/// servidor. Nada se pide hasta «Buscar».
@MainActor
@Observable
final class PlannerModel {
    enum Phase: Equatable, Sendable {
        case idle
        case searching
        case loaded(PlanResponse, PlannerSearch)
        /// El servidor no encuentra nada (sin opciones o 404).
        case empty(PlannerSearch)
        case failed(String)
    }

    typealias Fetch = @Sendable (_ from: String, _ to: String, _ when: String?, _ mode: TimeMode) async throws -> PlanResponse

    var from: PlaceResult?
    var to: PlaceResult?
    /// Por defecto «Llegar a las 09:00» (F40, ajustes-b.md A17).
    var timing: PlannerTiming = .arrival
    var time: String = "09:00"
    private(set) var phase: Phase = .idle

    init() {}

    /// Lo que se buscaría ahora con el formulario.
    var currentSearch: PlannerSearch? {
        guard let from, let to else { return nil }
        return PlannerSearch(from: from, to: to, timing: timing, time: time)
    }

    var isSearching: Bool { phase == .searching }

    /// Hay origen y destino, y no son el mismo sitio.
    var canSearch: Bool {
        guard let from, let to else { return false }
        return from.id != to.id && !isSearching
    }

    /// Da la vuelta al trayecto.
    func swapEnds() {
        let old = from
        from = to
        to = old
    }

    func search(_ fetch: Fetch) async {
        guard canSearch, let search = currentSearch else { return }
        phase = .searching
        do {
            let reply = try await fetch(search.from.id, search.to.id, search.apiWhen, search.apiMode)
            phase = reply.options.isEmpty ? .empty(search) : .loaded(reply, search)
        } catch is CancellationError {
            phase = .idle
        } catch APIError.notFound {
            phase = .empty(search)
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "No se ha podido buscar.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
