#if canImport(ActivityKit)
import Foundation

/// Qué pinta la Live Activity con un `ContentState` (la «foto» que escribió
/// la app) y el `isStale` del sistema. Puro, para poder probarlo; las vistas
/// de TrajetWidgets solo lo dibujan.
///
/// La vista no sabe qué hora es (decisiones §5.3):
/// - viva: la cifra es la que escribió la app (`Dep.minutes`);
/// - caducada (`isStale`): horas fijas, y el tren lo decide la foto: el
///   primero que sale más de 60 s después de que caducó. Nunca «publica» una
///   vía ni pasa sola al tren siguiente con datos que no tiene.
struct ActivityPresentation: Hashable, Sendable {

    typealias State = TrajetActivityAttributes.ContentState
    typealias Dep = TrajetActivityAttributes.Dep

    let state: State
    let isStale: Bool
    let routeID: Int

    /// La salida del billete (la primera que no está cancelada).
    let hero: Dep?
    /// La siguiente («luego 21 min»).
    let second: Dep?
    /// La primera salida está cancelada: el pie lo dice.
    let cancelled: Dep?
    /// La primera salida del tramo siguiente (transbordo).
    let link: Dep?

    init(state: State, isStale: Bool, routeID: Int) {
        self.state = state
        self.isStale = isStale
        self.routeID = routeID

        let deps = state.leg.departures
        let pool: [Dep]
        if isStale {
            let limit = Self.staleReference(for: state)
            pool = deps.filter { $0.at.addingTimeInterval(-60) > limit }
        } else {
            pool = deps
        }
        cancelled = pool.first.flatMap { $0.cancelled ? $0 : nil }
        let valid = pool.filter { !$0.cancelled }
        hero = valid.first
        second = valid.count > 1 ? valid[1] : nil
        link = state.next?.first
    }

    /// Cuándo caducó, visto desde la foto: el primero de «tablero viejo» y
    /// «el tren enseñado ya salió» (el tercer término de `staleDate`, el
    /// cambio de minuto, depende de cuándo se escribió y la foto no lo sabe;
    /// sin él la hora que se enseña es la misma o una más prudente).
    static func staleReference(for state: State) -> Date {
        var candidates: [Date] = [
            state.receivedAt.addingTimeInterval(max(Board.staleAfter, 2 * TimeInterval(state.refreshHint))),
        ]
        if let first = state.leg.departures.first(where: { !$0.cancelled }), !first.atStop {
            candidates.append(first.at.addingTimeInterval(60))
        }
        return candidates.min() ?? state.receivedAt
    }

    // MARK: - Estado general

    /// Apagada (R19): sin conexión, servidor sin clave o caducada. Todo en
    /// gris menos «Parar» y el aviso que explica por qué.
    var isOff: Bool { isStale || state.connection != .ok }

    var isEnded: Bool { state.ended != nil }

    /// Qué se dice cuando no hay salida que enseñar.
    var empty: GlanceEmpty? {
        guard hero == nil else { return nil }
        if state.leg.statusLevel >= 2 { return .cut }
        // Había salidas pero ya pasaron todas las de la foto.
        if state.leg.departures.contains(where: { !$0.cancelled }) { return .noRecentData }
        // A la app, sin red, se le acabó su último tablero: nunca «Servicio
        // finalizado» (no lo sabe).
        if state.connection != .ok { return .noRecentData }
        return .finished
    }

    /// «tramo 1 de 2» (solo con más de un tramo).
    var legText: String? {
        state.legCount > 1 ? "tramo \(state.legIndex + 1) de \(state.legCount)" : nil
    }

    /// El destino de la cabecera: el del tren enseñado o el sentido del tramo.
    var destinations: [String] {
        if let hero, !hero.destination.isEmpty { return hero.destination }
        return state.leg.direction
    }

    /// La línea está perturbada o cortada y hay tren que enseñar (con el
    /// billete de «Sin circulación» sobra decirlo dos veces, P2-17).
    var statusLevel: Int {
        hero == nil ? 0 : state.leg.statusLevel
    }

    // MARK: - La cifra

    /// El momento de una salida: horas fijas si está caducada.
    func moment(_ dep: Dep) -> GlanceMoment {
        if isStale { return .time(GlanceClock.hhmm(dep.at)) }
        return GlanceMoment.from(minutes: dep.minutes, atStop: dep.atStop)
    }

    /// La vía de una salida, con su forma (R10). Caducada, tal como llegó y
    /// sin «nueva» (no se anima ni se canta nada con el dato viejo).
    func via(_ dep: Dep) -> GlanceVia? {
        GlanceVia.make(expected: state.leg.platformExpected, platform: dep.platform,
                       guess: dep.guessPlatform, share: dep.guessShare,
                       isNew: dep.platformNew && !isOff, before: dep.platformBefore)
    }

    /// La vía del tren de enlace (transbordo).
    func linkVia(_ dep: Dep) -> GlanceVia? {
        // El tramo siguiente no trae `platform_expected` en el estado: basta
        // con que haya vía o previsión (el constructor ya las quita en
        // metro, bus y tranvía, R3).
        GlanceVia.make(expected: true, platform: dep.platform, guess: dep.guessPlatform,
                       share: dep.guessShare, isNew: false, before: nil)
    }

    /// Texto secundario del billete, con su prioridad.
    func meta(_ dep: Dep) -> [GlanceMeta] {
        var items: [GlanceMeta] = []
        if let before = dep.platformBefore, dep.platform != nil { items.append(.platformChange(before: before)) }
        if !moment(dep).isTime, !dep.atStop { items.append(.time(GlanceClock.hhmm(dep.at))) }
        if let delay = dep.delay, delay != 0 { items.append(.delay(delay)) }
        if let raw = dep.length, let length = TrainLength(rawValue: raw) { items.append(.length(length)) }
        if let legText { items.append(.leg(legText)) }
        return items
    }

    /// La franja de vía de la expandida: solo cuando la vía se acaba de
    /// anunciar o ha cambiado, y nunca con el dato viejo.
    var showsPlatformBand: Bool {
        guard let hero, !isOff, let v = via(hero), v.isReal else { return false }
        return v.isNew || v.before != nil
    }

    // MARK: - Enlaces (decisiones §6)

    var url: URL {
        if state.connection == .noKey { return AppLink.serverSettings.url }
        if isEnded { return AppLink.route(id: routeID, legSeq: nil, departureJID: nil).url }
        if hero == nil, state.leg.statusLevel >= 2 { return AppLink.alternatives(routeID: routeID).url }
        return AppLink.route(id: routeID, legSeq: state.leg.seq, departureJID: nil).url
    }

    // MARK: - VoiceOver (R50)

    /// Una frase por salida: línea, destino, momento, vía, retraso y, si toca,
    /// «dato sin actualizar».
    func spoken(_ dep: Dep) -> String {
        var parts: [String] = []
        let line = state.leg.lineCode.isEmpty ? "Trayecto" : "Línea \(state.leg.lineCode)"
        if let d = dep.destination.first { parts.append("\(line) a \(d)") } else { parts.append(line) }
        let m = moment(dep)
        if case .long = m { parts.append(GlanceMoment.spokenLong(minutes: dep.minutes)) } else { parts.append(m.spoken) }
        if let v = via(dep) { parts.append(v.spoken) }
        if let delay = dep.delay, delay != 0 {
            parts.append(delay > 0 ? "\(delay) minutos de retraso" : "\(-delay) minutos de adelanto")
        }
        if isOff { parts.append("dato sin actualizar") }
        return parts.joined(separator: ", ")
    }
}
#endif
