#if canImport(ActivityKit)
import Foundation

/// Lo que enseña la Live Activity, sacado del tablero y de nada más
/// (docs/diseno/sistema.md §12.4, decisiones-la-widgets.md §5.3).
///
/// Es una función pura: el modo trayecto la llama al refrescar y en cada
/// cambio de minuto (sin red, con el último tablero) y escribe el resultado
/// con `activity.update(ActivityContent(state:staleDate:))`. Aquí se decide
/// el tramo, las salidas (≤ 3, en orden, las que ya se fueron fuera), los
/// minutos al momento de escribir, la vía real o probable, el cambio de vía,
/// el transbordo y las variantes del destino. Nada inventado: lo derivado
/// (fechas, variantes, cambio de vía, conexión) sale de campos del tablero.
enum ActivityContentBuilder {

    typealias State = TrajetActivityAttributes.ContentState
    typealias Connection = TrajetActivityAttributes.Connection
    typealias EndReason = TrajetActivityAttributes.EndReason

    /// Salidas que caben en el estado (tope de 4 KB de ActivityKit).
    static let maxDepartures = 3
    /// Un «ya» se sigue enseñando hasta 45 s después de su hora
    /// (`Motion.Timing.nowGrace`, igual que el tablero).
    static let departedGrace: TimeInterval = 45

    /// Lo que la app sabe y el tablero no.
    struct Options: Sendable {
        /// El tramo en el que va la persona (lo dicen las geocercas). Sin él,
        /// el primero de la ruta.
        var legSeq: Int?
        /// El último estado escrito: sirve para ver el cambio de vía (misma
        /// salida, otra vía).
        var previous: State?
        /// Cómo fue el último refresco. Sin él se deduce del tablero: clave
        /// que falta → `.noKey`; tablero de hace más de 90 s → `.offline`.
        var connection: Connection?
        /// Solo en el estado final (llegada o duración máxima).
        var ended: EndReason?

        init(legSeq: Int? = nil, previous: State? = nil,
             connection: Connection? = nil, ended: EndReason? = nil) {
            self.legSeq = legSeq
            self.previous = previous
            self.connection = connection
            self.ended = ended
        }
    }

    /// El estado de la Live Activity para `board`, tal como está a `now`.
    ///
    /// - Parameters:
    ///   - board: el último tablero bueno.
    ///   - receivedAt: cuándo llegó al teléfono (R17; el de `CachedBoard`).
    ///   - routeID: la ruta del trayecto (la de los atributos de la actividad).
    ///   - now: el momento en que se escribe.
    static func make(board: Board, receivedAt: Date, routeID: Int, now: Date) -> State {
        make(board: board, receivedAt: receivedAt, routeID: routeID, now: now, options: Options())
    }

    /// Igual, con lo que sabe el modo trayecto (tramo actual, estado anterior,
    /// conexión, fin).
    static func make(board: Board, receivedAt: Date, routeID: Int, now: Date, options: Options) -> State {
        let legs = board.legs
        let index = legIndex(in: legs, preferredSeq: options.legSeq)
        let previousDeps = previousDepartures(options.previous)

        let leg: TrajetActivityAttributes.Leg
        var next: TrajetActivityAttributes.Link?
        if let index {
            let boardLeg = legs[index]
            let nextLeg = index + 1 < legs.count ? legs[index + 1] : nil
            leg = activityLeg(boardLeg, nextLeg: nextLeg, receivedAt: receivedAt, now: now, previous: previousDeps)
            if let nextLeg {
                next = link(nextLeg, receivedAt: receivedAt, now: now, previous: previousDeps)
            }
        } else {
            // Un tablero sin tramos: la actividad dice «sin salidas» en vez de
            // romperse.
            leg = TrajetActivityAttributes.Leg(
                seq: 0, lineCode: "", lineColor: "", platformExpected: false, toName: "",
                direction: DestinationAbbreviator.variants(board.route?.destName ?? ""),
                mixed: false, statusLevel: 0, departures: [])
        }

        return State(
            leg: leg,
            next: next,
            legIndex: index ?? 0,
            legCount: legs.count,
            receivedAt: receivedAt,
            dataAge: board.dataAge,
            refreshHint: board.server?.refreshHintS ?? Int(Board.minimumRefresh),
            connection: connection(board: board, receivedAt: receivedAt, now: now, explicit: options.connection),
            ended: options.ended)
    }

    /// El mismo estado, ya terminado (llegada o duración máxima): lo escribe
    /// el modo trayecto con `end(…, dismissalPolicy: .after(.now + 15 min))`.
    /// Parado a mano no tiene estado final (`.immediate`).
    static func ended(_ state: State, reason: EndReason) -> State {
        var s = state
        s.ended = reason
        return s
    }

    // MARK: - staleDate y alertas

    /// Cuándo deja de valer lo escrito si la app no vuelve a escribir
    /// (decisiones §5.3): el primero de
    /// - llegada del tablero + max(90 s, 2 × `refresh_hint_s`) (solo con la
    ///   conexión bien: sin conexión, el dato ya se sabe viejo y ya se dice),
    /// - salida del tren enseñado + 60 s,
    /// - siguiente cambio de minuto de la cifra + 30 s.
    static func staleDate(for state: State, writtenAt: Date) -> Date {
        var candidates: [Date] = []
        if state.connection == .ok {
            let window = max(Board.staleAfter, 2 * TimeInterval(state.refreshHint))
            candidates.append(state.receivedAt.addingTimeInterval(window))
        }
        if let hero = state.leg.departures.first(where: { !$0.cancelled }), !hero.atStop {
            candidates.append(hero.at.addingTimeInterval(60))
        }
        // La cifra baja un minuto cada 60 s contados desde la llegada del
        // tablero (ver `minutes(_:receivedAt:now:)`).
        let elapsed = max(0, writtenAt.timeIntervalSince(state.receivedAt))
        let nextChange = state.receivedAt.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
        candidates.append(nextChange.addingTimeInterval(30))
        return candidates.min() ?? writtenAt.addingTimeInterval(Board.staleAfter)
    }

    /// Por qué merece la pena avisar (alerta que abre la isla). Solo por la
    /// vía publicada, el cambio de vía, el tren cancelado y la línea cortada;
    /// nunca por un cambio de minuto (decisiones §5.4).
    enum AlertReason: Hashable, Sendable {
        case platformPublished(platform: String)
        case platformChanged(platform: String, before: String)
        case cancelled(time: String)
        case lineCut(line: String)

        var title: String {
            switch self {
            case .platformPublished(let p): "Vía \(p)"
            case .platformChanged(let p, _): "Cambio de vía: \(p)"
            case .cancelled: "Tren cancelado"
            case .lineCut(let line): "Línea \(line) cortada"
            }
        }

        var body: String {
            switch self {
            case .platformPublished: "Se acaba de anunciar la vía."
            case .platformChanged(let p, let before): "Ahora sale por la \(p), antes \(before)."
            case .cancelled(let time): "El de las \(time) no sale."
            case .lineCut: "Sin circulación. Toca para ver alternativas."
            }
        }
    }

    /// La alerta que toca al pasar de `previous` a `current`, o nil.
    static func alert(previous: State?, current: State) -> AlertReason? {
        guard current.ended == nil else { return nil }
        let oldLevel = previous?.leg.statusLevel ?? 0
        if current.leg.statusLevel >= 2, oldLevel < 2, !current.leg.lineCode.isEmpty {
            return .lineCut(line: current.leg.lineCode)
        }
        let oldDeps = previousDepartures(previous)
        if let first = current.leg.departures.first, first.cancelled,
           let old = oldDeps[first.jid], !old.cancelled {
            return .cancelled(time: GlanceClock.hhmm(first.at))
        }
        guard current.leg.platformExpected,
              let hero = current.leg.departures.first(where: { !$0.cancelled }),
              let platform = hero.platform, !platform.isEmpty
        else { return nil }
        let old = oldDeps[hero.jid]
        if let before = hero.platformBefore, old?.platform != platform {
            return .platformChanged(platform: platform, before: before)
        }
        if hero.platformNew, old?.platform != platform {
            return .platformPublished(platform: platform)
        }
        return nil
    }

    // MARK: - Piezas

    /// El tramo que toca: el que diga el modo trayecto; si no, el primero.
    static func legIndex(in legs: [Leg], preferredSeq: Int?) -> Int? {
        guard !legs.isEmpty else { return nil }
        if let preferredSeq, let i = legs.firstIndex(where: { $0.seq == preferredSeq }) { return i }
        return 0
    }

    /// Los minutos de una salida en el momento de escribir: los del servidor
    /// (que sabe redondear con los segundos) menos los minutos enteros que
    /// han pasado desde que llegó el tablero. Nunca negativos.
    static func minutes(_ departure: Departure, receivedAt: Date, now: Date) -> Int {
        let elapsed = Int(max(0, now.timeIntervalSince(receivedAt)) / 60)
        return max(0, departure.minutes - elapsed)
    }

    /// La hora de salida como fecha («HH:MM» de París, la más cercana a la
    /// llegada del tablero); si no se entiende, la llegada + los minutos.
    static func departureDate(_ departure: Departure, receivedAt: Date) -> Date {
        departure.date(near: receivedAt)
            ?? receivedAt.addingTimeInterval(TimeInterval(departure.minutes) * 60)
    }

    /// ¿Ya se fue? A los 45 s de su hora. El tren parado en el andén se
    /// queda mientras el tablero sea reciente (≤ 90 s).
    static func isGone(_ departure: Departure, receivedAt: Date, now: Date) -> Bool {
        let at = departureDate(departure, receivedAt: receivedAt)
        if departure.atStop, now.timeIntervalSince(receivedAt) <= Board.staleAfter { return false }
        return at.addingTimeInterval(departedGrace) <= now
    }

    /// Las salidas que quedan, en el orden del tablero (también las
    /// canceladas: la vista dice «el de las 12:56, cancelado»).
    static func remaining(_ leg: Leg, receivedAt: Date, now: Date) -> [Departure] {
        leg.departures.filter { !isGone($0, receivedAt: receivedAt, now: now) }
    }

    private static func activityLeg(_ leg: Leg, nextLeg: Leg?, receivedAt: Date, now: Date,
                                    previous: [String: TrajetActivityAttributes.Dep]) -> TrajetActivityAttributes.Leg {
        let shown = Array(remaining(leg, receivedAt: receivedAt, now: now).prefix(maxDepartures))
        let deps = shown.map { dep($0, in: leg, receivedAt: receivedAt, now: now, previous: previous) }
        // «Transbordo en …»: la parada de bajada o, si falta, la de subida
        // del tramo siguiente.
        var toName = leg.toName
        if toName.isEmpty, let nextLeg { toName = nextLeg.fromName }
        return TrajetActivityAttributes.Leg(
            seq: leg.seq,
            lineCode: leg.lineCode,
            lineColor: leg.lineColor,
            platformExpected: leg.showsPlatform,
            toName: toName,
            direction: DestinationAbbreviator.variants(directionName(leg, shown: shown)),
            mixed: leg.mixesDestinations,
            statusLevel: leg.status.level,
            departures: deps)
    }

    private static func link(_ leg: Leg, receivedAt: Date, now: Date,
                             previous: [String: TrajetActivityAttributes.Dep]) -> TrajetActivityAttributes.Link {
        let first = remaining(leg, receivedAt: receivedAt, now: now).first(where: { !$0.isCancelled })
        return TrajetActivityAttributes.Link(
            lineCode: leg.lineCode,
            lineColor: leg.lineColor,
            statusLevel: leg.status.level,
            first: first.map { dep($0, in: leg, receivedAt: receivedAt, now: now, previous: previous) })
    }

    private static func dep(_ d: Departure, in leg: Leg, receivedAt: Date, now: Date,
                            previous: [String: TrajetActivityAttributes.Dep]) -> TrajetActivityAttributes.Dep {
        // R3: sin vía esperada no hay vía ni previsión que enseñar.
        let expected = leg.showsPlatform
        let platform: String? = expected && d.hasRealPlatform ? d.platform : nil
        let guess: PlatformGuess? = expected && platform == nil ? d.guess : nil
        let guessPlatform: String? = (guess?.platform.isEmpty == false) ? guess?.platform : nil

        // Cambio de vía: la misma salida tenía otra vía en lo último escrito.
        // Se conserva mientras la vía no vuelva a cambiar.
        var before: String?
        if let platform, let old = previous[d.id] {
            if let oldPlatform = old.platform, !oldPlatform.isEmpty, oldPlatform != platform {
                before = oldPlatform
            } else if old.platform == platform {
                before = old.platformBefore
            }
        }

        return TrajetActivityAttributes.Dep(
            jid: d.id,
            at: departureDate(d, receivedAt: receivedAt),
            minutes: minutes(d, receivedAt: receivedAt, now: now),
            destination: DestinationAbbreviator.variants(d.destination),
            platform: platform,
            platformNew: platform != nil && d.platformNew,
            platformBefore: before,
            guessPlatform: guessPlatform,
            guessShare: guessPlatform == nil ? nil : guess?.share,
            // R4 y R14: sin hora teórica no hay retraso; un 0 no se enseña.
            delay: d.aimedAt.isEmpty ? nil : d.realDelay,
            atStop: d.atStop,
            length: d.length?.rawValue,
            cancelled: d.isCancelled)
    }

    /// El sentido del tramo: el único `directions` si solo hay uno; si no, el
    /// destino del primer tren; si no, el primer sentido o la parada final.
    private static func directionName(_ leg: Leg, shown: [Departure]) -> String {
        if leg.directions.count == 1 { return leg.directions[0] }
        if let first = shown.first(where: { !$0.isCancelled }) ?? leg.departures.first {
            return first.destination
        }
        return leg.directions.first ?? leg.toName
    }

    private static func connection(board: Board, receivedAt: Date, now: Date, explicit: Connection?) -> Connection {
        if let explicit { return explicit }
        if board.server?.primKey == .missing { return .noKey }
        if now.timeIntervalSince(receivedAt) > Board.staleAfter { return .offline }
        return .ok
    }

    private static func previousDepartures(_ state: State?) -> [String: TrajetActivityAttributes.Dep] {
        guard let state else { return [:] }
        var all = state.leg.departures
        if let first = state.next?.first { all.append(first) }
        var map: [String: TrajetActivityAttributes.Dep] = [:]
        for d in all where map[d.jid] == nil { map[d.jid] = d }
        return map
    }
}
#endif
