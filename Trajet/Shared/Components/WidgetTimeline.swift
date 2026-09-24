import Foundation

// Los widgets son «una foto con fecha» (decisiones-la-widgets.md §5.5): cada
// entrada del timeline enseña las salidas que quedan TAL COMO LLEGARON en la
// última recarga (una vía probable sigue probable) y, al acabarse las
// salidas conocidas, una entrada final «Sin datos recientes · abre Trajet».
//
// La cifra no la mueve el sistema: hay una entrada por minuto (alineada con
// la llegada del tablero) durante la primera hora, así se pinta como la de la
// app (dos tallas, «ya», R6) y sigue siendo cierta aunque el widget no se
// recargue. Más allá, entradas cada 5 min con horas fijas, que no mienten.
// Aquí está la lógica, sin vistas, para poder probarla (WidgetTimelineTests).

/// Una salida tal como llegó en el tablero.
struct WidgetDeparture: Hashable, Sendable, Identifiable {
    /// `jid`, o su sustituto estable (R23).
    let id: String
    /// Hora de salida («HH:MM» de París como fecha).
    let at: Date
    /// «12:56», tal cual la manda la API.
    let atText: String
    /// Los minutos que dijo el servidor al llegar el tablero.
    let serverMinutes: Int
    let destination: String
    let destinationVariants: [String]
    let via: GlanceVia?
    /// Solo si hay hora teórica y no es 0 (R4, R14).
    let delay: Int?
    let atStop: Bool
    let length: TrainLength?
    let cancelled: Bool
}

/// Un tramo de la ruta, con todas sus salidas.
struct WidgetLeg: Hashable, Sendable, Identifiable {
    let seq: Int
    let lineCode: String
    let lineColor: String
    let fromName: String
    let toName: String
    /// El sentido: `directions` si es uno solo; si no, el destino del primero.
    let direction: String
    let statusLevel: Int
    /// Sin sentido elegido y con destinos distintos (R24).
    let mixed: Bool
    let departures: [WidgetDeparture]

    var id: Int { seq }
}

/// El tablero que ven los widgets (hasta tres tramos).
struct WidgetBoard: Hashable, Sendable {
    let routeID: Int?
    let routeName: String
    let receivedAt: Date
    let dataAge: Double
    let legs: [WidgetLeg]
}

/// Lo que se ve de un tramo en una entrada.
struct WidgetLegView: Hashable, Sendable {
    let leg: WidgetLeg
    /// Las que quedan (también canceladas), en orden.
    let remaining: [WidgetDeparture]
    let hero: WidgetDeparture?
    let second: WidgetDeparture?
    /// La primera que queda está cancelada.
    let cancelled: WidgetDeparture?
    /// Había salidas y ya pasaron todas: «Sin datos recientes».
    let isFinal: Bool

    /// Las que van detrás de la del billete (fichas y filas).
    var following: [WidgetDeparture] {
        remaining.filter { !$0.cancelled && $0.id != hero?.id }
    }

    /// Sin salida que enseñar.
    var empty: GlanceEmpty? {
        guard hero == nil else { return nil }
        if isFinal { return .noRecentData }
        if leg.statusLevel >= 2 { return .cut }
        return .finished
    }

    /// El estado de la línea solo cuenta si hay tren (con «Sin circulación»
    /// sobra decirlo dos veces).
    var statusLevel: Int { hero == nil ? 0 : leg.statusLevel }

    /// El destino de la cabecera: el del tren del billete o el sentido.
    var destinationVariants: [String] {
        if let hero, !hero.destinationVariants.isEmpty { return hero.destinationVariants }
        return DestinationAbbreviator.variants(leg.direction)
    }
}

/// Una entrada del timeline.
struct WidgetSnapshot: Hashable, Sendable {

    enum Content: Hashable, Sendable {
        /// IPA full firmada sin App Group: los widgets no pueden leer nada.
        case noAppGroup
        /// Aún no ha llegado ningún tablero (o se desemparejó).
        case noBoard
        case board(WidgetBoard)
    }

    let date: Date
    let content: Content
    /// La última recarga falló (sin red, servidor sin clave).
    let failure: WidgetFailure?
    /// La cifra en cuenta atrás vale en esta entrada (entradas por minuto).
    /// Si no, horas fijas.
    let countdownValid: Bool

    var board: WidgetBoard? {
        if case .board(let b) = content { return b }
        return nil
    }

    /// Antigüedad del dato en esta entrada (R17): desde la llegada al
    /// teléfono más `data_age`.
    var ageSeconds: Double {
        guard let board else { return 0 }
        return max(0, date.timeIntervalSince(board.receivedAt)) + board.dataAge
    }

    /// «hace 5 min» (R18).
    var ageText: String { Fmt.age(ageSeconds) }

    /// El tramo `index` tal como se ve en esta entrada.
    func legView(_ index: Int = 0) -> WidgetLegView? {
        guard let board, index < board.legs.count else { return nil }
        let leg = board.legs[index]
        let remaining = leg.departures.filter { isVisible($0, board: board) }
        let valid = remaining.filter { !$0.cancelled }
        let cancelled = remaining.first.flatMap { $0.cancelled ? $0 : nil }
        let had = leg.departures.contains { !$0.cancelled }
        return WidgetLegView(leg: leg, remaining: remaining, hero: valid.first,
                             second: valid.count > 1 ? valid[1] : nil,
                             cancelled: cancelled, isFinal: had && valid.isEmpty)
    }

    /// Los tramos de la ruta (hasta tres), tal como se ven en esta entrada.
    var legViews: [WidgetLegView] {
        guard let board else { return [] }
        return board.legs.indices.compactMap { legView($0) }
    }

    /// Apagado (R19): la recarga falló o ya no quedan salidas del tramo
    /// principal.
    var isOff: Bool {
        failure != nil || (legView(0)?.isFinal ?? false)
    }

    /// Los minutos de una salida en esta entrada: los del servidor menos los
    /// minutos enteros que han pasado desde que llegó el tablero.
    func minutes(_ dep: WidgetDeparture) -> Int {
        guard let board else { return dep.serverMinutes }
        let elapsed = Int(max(0, date.timeIntervalSince(board.receivedAt)) / 60)
        return max(0, dep.serverMinutes - elapsed)
    }

    /// Cómo se dice la salida en esta entrada. «En andén» solo con el tablero
    /// recién llegado; con 60 min o más, o fuera de las entradas por minuto,
    /// la hora fija (el sistema no la mueve y «1h46» no se puede dejar quieto).
    func moment(_ dep: WidgetDeparture) -> GlanceMoment {
        if dep.atStop, let board, date.timeIntervalSince(board.receivedAt) <= Board.staleAfter {
            return .atStop
        }
        let m = minutes(dep)
        if !countdownValid || m >= 60 { return .time(dep.atText) }
        if m <= 0 { return .now }
        return .minutes(m)
    }

    /// A dónde lleva tocar el widget entero (decisiones §6).
    var url: URL {
        guard let board, let routeID = board.routeID else { return AppLink.board.url }
        if failure == .noKey { return AppLink.serverSettings.url }
        guard let main = legView(0) else { return AppLink.board.url }
        if main.isFinal { return AppLink.board.url }
        if main.hero == nil, main.leg.statusLevel >= 2 { return AppLink.alternatives(routeID: routeID).url }
        return AppLink.route(id: routeID, legSeq: main.leg.seq, departureJID: nil).url
    }

    /// Enlace de una fila (mediano) o de un tramo (grande).
    func url(leg: WidgetLeg, departure: WidgetDeparture? = nil) -> URL {
        guard let routeID = board?.routeID else { return AppLink.board.url }
        return AppLink.route(id: routeID, legSeq: leg.seq, departureJID: departure?.id).url
    }

    private func isVisible(_ dep: WidgetDeparture, board: WidgetBoard) -> Bool {
        if dep.atStop, date.timeIntervalSince(board.receivedAt) <= Board.staleAfter { return true }
        return dep.at.addingTimeInterval(WidgetTimelinePlanner.departedGrace) > date
    }
}

/// Lo que devuelve el planificador: las entradas y cuándo pedir otra recarga
/// (nil = nunca; la app avisará con `WidgetRefresher`).
struct WidgetTimelinePlan: Sendable {
    let snapshots: [WidgetSnapshot]
    let reloadDate: Date?
}

/// Construye el timeline de los widgets a partir de la caché del App Group.
enum WidgetTimelinePlanner {

    /// Tramos que caben en el widget grande.
    static let maxLegs = 3
    /// Salidas por tramo que se guardan en la foto.
    static let maxDepartures = 8
    /// Un «ya» sigue a la vista 45 s después de su hora (como el tablero).
    static let departedGrace: TimeInterval = 45
    /// Entradas de minuto en minuto durante la primera hora.
    static let minuteHorizon: TimeInterval = 60 * 60
    /// Después, una cada 5 min (WidgetKit no garantiza más).
    static let sparseStep: TimeInterval = 5 * 60
    /// Tope de entradas en un timeline.
    static let maxEntries = 100
    /// Política de recarga: como mucho a los 15 min (sistema.md §12.7).
    static let reloadAfter: TimeInterval = 15 * 60
    /// Sin nada que contar (sin tablero, o ya sin salidas): cada hora.
    static let idleReload: TimeInterval = 60 * 60

    // MARK: - Tablero → foto

    static func board(from cached: CachedBoard) -> WidgetBoard {
        let b = cached.board
        let receivedAt = cached.receivedAt
        let legs = b.legs.prefix(maxLegs).map { leg -> WidgetLeg in
            let deps = leg.departures.prefix(maxDepartures).map { departure(from: $0, leg: leg, receivedAt: receivedAt) }
            let direction: String
            if leg.directions.count == 1 {
                direction = leg.directions[0]
            } else if let first = leg.departures.first(where: { !$0.isCancelled }) ?? leg.departures.first {
                direction = first.destination
            } else {
                direction = leg.directions.first ?? leg.toName
            }
            return WidgetLeg(seq: leg.seq, lineCode: leg.lineCode, lineColor: leg.lineColor,
                             fromName: leg.fromName, toName: leg.toName, direction: direction,
                             statusLevel: leg.status.level, mixed: leg.mixesDestinations,
                             departures: Array(deps))
        }
        return WidgetBoard(routeID: b.route?.id ?? cached.routeID,
                           routeName: b.route?.name ?? "",
                           receivedAt: receivedAt,
                           dataAge: b.dataAge,
                           legs: Array(legs))
    }

    static func departure(from d: Departure, leg: Leg, receivedAt: Date) -> WidgetDeparture {
        let at = d.date(near: receivedAt) ?? receivedAt.addingTimeInterval(TimeInterval(d.minutes) * 60)
        return WidgetDeparture(
            id: d.id,
            at: at,
            atText: d.at.isEmpty ? GlanceClock.hhmm(at) : d.at,
            serverMinutes: d.minutes,
            destination: d.destination,
            destinationVariants: DestinationAbbreviator.variants(d.destination),
            // Tal como llegó: una probable sigue probable (R10); sin vía
            // esperada, nada (R3).
            via: GlanceVia.make(expected: leg.showsPlatform, platform: d.platform,
                                guess: d.guess?.platform, share: d.guess?.share),
            delay: d.aimedAt.isEmpty ? nil : d.realDelay,
            atStop: d.atStop,
            length: d.length,
            cancelled: d.isCancelled)
    }

    // MARK: - Timeline

    /// Las entradas y la política de recarga.
    ///
    /// - Parameters:
    ///   - cached: la caché del App Group (nil si no hay).
    ///   - hasAppGroup: sin App Group no se puede leer nada: se dice.
    ///   - failure: el fallo que apuntó la app después de ese tablero.
    ///   - now: ahora.
    static func plan(cached: CachedBoard?, hasAppGroup: Bool, failure: WidgetFailure?, now: Date) -> WidgetTimelinePlan {
        guard hasAppGroup else {
            return WidgetTimelinePlan(
                snapshots: [WidgetSnapshot(date: now, content: .noAppGroup, failure: nil, countdownValid: true)],
                reloadDate: nil)
        }
        guard let cached else {
            return WidgetTimelinePlan(
                snapshots: [WidgetSnapshot(date: now, content: .noBoard, failure: nil, countdownValid: true)],
                reloadDate: now.addingTimeInterval(idleReload))
        }
        let photo = Self.board(from: cached)
        // Servidor sin clave: también se sabe por el propio tablero.
        let effectiveFailure = failure ?? (cached.board.server?.primKey == .missing ? .noKey : nil)
        let dates = entryDates(for: photo, now: now)
        let snapshots = dates.map { date in
            WidgetSnapshot(date: date, content: .board(photo), failure: effectiveFailure,
                           countdownValid: date.timeIntervalSince(now) < minuteHorizon)
        }
        return WidgetTimelinePlan(snapshots: snapshots, reloadDate: reloadDate(for: photo, now: now))
    }

    /// Cuándo se ha ido la última salida de los tramos que se enseñan, o nil
    /// si no hay ninguna.
    static func finalDate(for board: WidgetBoard) -> Date? {
        board.legs.flatMap(\.departures).map { $0.at.addingTimeInterval(departedGrace) }.max()
    }

    /// Fechas de las entradas: ahora; cada minuto (contado desde la llegada
    /// del tablero, que es cuando cambia la cifra) durante la primera hora;
    /// el momento en que se va cada salida; cada 5 min después; y la entrada
    /// final cuando se va la última. Ordenadas, sin repetir y con tope.
    static func entryDates(for board: WidgetBoard, now: Date) -> [Date] {
        guard let final = finalDate(for: board), final > now else { return [now] }
        let horizon = min(final, now.addingTimeInterval(minuteHorizon))
        var dates: [Date] = [now]

        // Cada minuto, alineado con la llegada del tablero.
        let elapsed = max(0, now.timeIntervalSince(board.receivedAt))
        var t = board.receivedAt.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
        if t <= now { t = now.addingTimeInterval(60) }
        while t < horizon {
            dates.append(t)
            t = t.addingTimeInterval(60)
        }
        // Cuando se va cada salida (desaparece del widget en su momento).
        for dep in board.legs.flatMap(\.departures) {
            let gone = dep.at.addingTimeInterval(departedGrace)
            if gone > now, gone < horizon { dates.append(gone) }
        }
        // Más allá de la hora, cada 5 min con horas fijas.
        var s = horizon
        while s < final {
            dates.append(s)
            s = s.addingTimeInterval(sparseStep)
        }
        dates.append(final)

        // Ordenadas, sin fechas a menos de 1 s y con tope (la final, siempre).
        let sorted = dates.sorted()
        var result: [Date] = []
        for d in sorted {
            if let last = result.last, d.timeIntervalSince(last) < 1 { continue }
            result.append(d)
        }
        if result.count > maxEntries {
            result = Array(result.prefix(maxEntries - 1)) + [final]
        }
        return result
    }

    /// La siguiente recarga: a los 15 min como mucho y no después de que se
    /// vaya la última salida; sin salidas, dentro de una hora.
    static func reloadDate(for board: WidgetBoard, now: Date) -> Date {
        guard let final = finalDate(for: board), final > now else {
            return now.addingTimeInterval(idleReload)
        }
        return min(final, now.addingTimeInterval(reloadAfter))
    }
}
