import Foundation
import Observation

/// Por qué el último refresco no ha traído un tablero nuevo. El tablero
/// anterior se queda en pantalla (R9); esto dice qué pasa, con un estado
/// diseñado para cada caso.
enum BoardIssue: Equatable, Sendable {
    /// No se llega al servidor por ninguna dirección.
    case offline(String)
    /// El servidor no tiene clave de PRIM (`prim_key_missing`).
    case noKey
    /// PRIM rechaza la clave (`prim_key_invalid`).
    case keyRejected
    /// Se acabó la cuota del día (`prim_quota_exhausted`).
    case quotaExhausted(retryAfter: Int?)
    /// PRIM no responde y no hay caché (`prim_unreachable`, `upstream`).
    case upstream
    /// Este iPhone no está emparejado o el servidor ya no lo reconoce (401).
    case notPaired
    /// Cualquier otra cosa (error del servidor, respuesta ilegible).
    case other(String)

    var title: String {
        switch self {
        case .offline: "Sin conexión"
        case .noKey: "Servidor sin clave"
        case .keyRejected: "Clave de PRIM rechazada"
        case .quotaExhausted: "Cuota agotada"
        case .upstream: "PRIM no responde"
        case .notPaired: "iPhone sin emparejar"
        case .other: "Error del servidor"
        }
    }

    /// Qué pasa y qué hacer, en una o dos frases.
    var message: String {
        switch self {
        case .offline(let detail):
            return detail.isEmpty ? "No se llega al servidor. Se enseña lo último que llegó." : detail
        case .noKey:
            return "El servidor no tiene clave de PRIM. Pónsela en el panel de Trajet del Umbrel."
        case .keyRejected:
            return "PRIM no acepta la clave del servidor. Cámbiala en el panel de Trajet del Umbrel."
        case .quotaExhausted(let retry):
            if let retry, retry > 0 {
                return "Se han gastado las llamadas de hoy. Vuelve a probar en \(Self.wait(retry))."
            }
            return "Se han gastado las llamadas de hoy. La cuota vuelve a medianoche UTC."
        case .upstream:
            return "PRIM no responde ahora mismo. Se enseña lo último que llegó."
        case .notPaired:
            return "El servidor ya no reconoce este iPhone. Vuelve a emparejarlo desde el panel."
        case .other(let detail):
            return detail.isEmpty ? "El servidor ha dado un error." : detail
        }
    }

    /// Símbolo que acompaña a la palabra (nunca solo color).
    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .noKey, .keyRejected: "server.rack"
        case .quotaExhausted: "gauge.with.dots.needle.100percent"
        case .upstream: "exclamationmark.icloud"
        case .notPaired: "iphone.slash"
        case .other: "exclamationmark.triangle"
        }
    }

    private static func wait(_ seconds: Int) -> String {
        seconds < 90 ? "\(seconds) s" : "\((seconds + 59) / 60) min"
    }
}

/// La vía de un tren que se mira acaba de publicarse (o ha cambiado). Para la
/// háptica y el aviso (R2): `.haptic(.platformPublished, trigger: store.lastPlatformEvent)`.
struct PlatformEvent: Equatable, Sendable {
    let id: UUID
    let legSeq: Int
    let departureID: String
    let platform: String
    /// La vía que tenía antes el mismo tren, si era otra (cambio de vía).
    let previous: String?
    let at: Date
}

/// Dónde guarda el tablero el `BoardStore`. En la app, el disco
/// (`BoardCache`); en los tests y la demo, memoria.
struct BoardPersistence: Sendable {
    var load: @Sendable () -> CachedBoard?
    var save: @Sendable (CachedBoard) -> Void
    var clear: @Sendable () -> Void

    init(load: @escaping @Sendable () -> CachedBoard?,
         save: @escaping @Sendable (CachedBoard) -> Void,
         clear: @escaping @Sendable () -> Void) {
        self.load = load
        self.save = save
        self.clear = clear
    }

    static let disk = BoardPersistence(load: { BoardCache.load() },
                                       save: { BoardCache.save($0); WidgetRefresher.boardDidChange() },
                                       clear: { BoardCache.clear() })

    static let none = BoardPersistence(load: { nil }, save: { _ in }, clear: {})

    /// En memoria, empezando con `initial`.
    static func memory(_ initial: CachedBoard? = nil) -> BoardPersistence {
        let box = LockedBox<CachedBoard?>(initial)
        return BoardPersistence(load: { box.value },
                                save: { box.value = $0 },
                                clear: { box.value = nil })
    }
}

/// Qué ha cambiado en las rutas (lo avisa `RoutesStore`).
enum RoutesChange: Equatable, Sendable {
    case created(Int)
    case updated(Int)
    case deleted(Int)
}

/// El estado del tablero.
///
/// Promesas que viven aquí:
///
///  1. **Nunca se borra la pantalla (R9).** Si la API falla, se conserva el
///     último tablero bueno con su antigüedad y `issue` dice por qué. Si un
///     tramo llega con su estación caída y sin salidas, se conservan sus
///     últimas salidas buenas. Al arrancar se pinta la caché de disco.
///  2. **Solo se refresca lo que se está mirando (R7).** El bucle corre cada
///     `max(30, server.refresh_hint_s)` s solo con el tablero delante y la
///     app activa, o en modo trayecto. Sus refrescos no engordan el
///     historial (R40).
///  3. **La antigüedad es la de verdad (R17, R19).** Se cuenta desde la
///     llegada al teléfono más `data_age`; el tablero se apaga con `stale`
///     del servidor o tras 90 s sin recibir uno nuevo.
@MainActor
@Observable
final class BoardStore {

    /// El último tablero bueno. Solo lo cambia otro tablero bueno (o el
    /// servidor diciendo que ya no hay rutas).
    private(set) var board: Board?
    /// El servidor ha dicho que no hay rutas (`BoardEmptyV1`).
    private(set) var emptyMessage: String?
    /// Lo último que se sabe del servidor (clave, cuota, ritmo).
    private(set) var server: ServerState?
    /// Por qué el último refresco no trajo tablero; nil si lo trajo.
    private(set) var issue: BoardIssue?
    private(set) var isLoading = false
    /// Ya ha habido al menos una respuesta (buena o mala) en esta sesión.
    private(set) var hasLoadedOnce = false
    /// Ruta elegida a mano. Con nil manda el servidor (R37).
    private(set) var pinnedRouteID: Int?
    /// Cuándo toca el siguiente refresco: la barra de progreso (R54) se dibuja
    /// a partir de esto, sin que el store tenga que latir a 60 fps.
    private(set) var nextRefreshAt: Date?
    /// Cuándo terminó el último intento (bueno o malo).
    private(set) var lastAttemptAt: Date?
    /// La vía que acaba de aparecer, para la háptica (R2).
    private(set) var lastPlatformEvent: PlatformEvent?
    /// Tramos cuyas salidas son las últimas buenas (su estación falló ahora).
    private(set) var retainedLegSeqs: Set<Int> = []
    private(set) var isVisible = false
    private(set) var isTripMode = false
    private(set) var isSceneActive = true
    private(set) var isLoopRunning = false

    private let api: any BoardFetching
    private let persistence: BoardPersistence
    private let clock: @Sendable () -> Date

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    /// Cambia al elegir ruta: una respuesta de antes se descarta.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var inFlight = 0
    /// «jid|vía» ya avisadas, para no repetir la háptica.
    @ObservationIgnored private var announcedPlatforms: Set<String> = []

    init(api: any BoardFetching, persistence: BoardPersistence = .disk,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.persistence = persistence
        self.clock = now
        // Se pinta la caché ya (< 1 s): la primera apertura del día no
        // enseña un hueco (R9, R20).
        if let cached = persistence.load() {
            board = cached.board
            server = cached.board.server
        }
    }

    // MARK: - Lo que se lee

    /// Cuándo llegó al teléfono lo que se ve.
    var receivedAt: Date? { board?.receivedAt }

    /// La ruta que se está viendo, elegida a mano o automática.
    var currentRouteID: Int? { pinnedRouteID ?? board?.route?.id }

    /// Cada cuánto se refresca: `server.refresh_hint_s`, nunca menos de 30 s.
    var refreshInterval: TimeInterval {
        max(Board.minimumRefresh, TimeInterval(server?.refreshHintS ?? 30))
    }

    /// El tablero en pantalla es de otra ruta que la elegida (se está
    /// cambiando): se enseña, pero se puede decir «cargando».
    var isShowingOtherRoute: Bool {
        guard let pinnedRouteID, let shown = board?.route?.id else { return false }
        return pinnedRouteID != shown
    }

    /// Segundos de antigüedad de lo que se ve (R17): desde la llegada al
    /// teléfono más `data_age`.
    func ageSeconds(now: Date? = nil) -> Double? {
        board?.ageSeconds(now: now ?? clock())
    }

    /// Dato viejo (R19): `stale` del servidor o > 90 s sin tablero nuevo.
    /// Sin tablero no hay nada que apagar.
    func isStale(now: Date? = nil) -> Bool {
        board?.isStale(now: now ?? clock()) ?? false
    }

    /// Antigüedad de un tramo: la suya, que en un tramo conservado incluye el
    /// tiempo que lleva conservado.
    func legAge(seq: Int, now: Date? = nil) -> Double? {
        guard let board, let leg = board.legs.first(where: { $0.seq == seq }) else { return nil }
        let since = max(0, (now ?? clock()).timeIntervalSince(board.receivedAt))
        return leg.age.map { $0 + since }
    }

    /// Las salidas de este tramo son las últimas buenas, no las de ahora.
    func isRetained(seq: Int) -> Bool { retainedLegSeqs.contains(seq) }

    // MARK: - Bucle (R7)

    /// El tablero está delante (lo llama la pantalla al aparecer y al irse).
    func setVisible(_ visible: Bool) {
        isVisible = visible
        syncLoop()
    }

    /// El modo trayecto mantiene el bucle vivo aunque no se mire.
    func setTripMode(_ on: Bool) {
        isTripMode = on
        syncLoop()
    }

    /// La app está activa (scenePhase). Lo llama RootView.
    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        syncLoop()
    }

    private var shouldLoop: Bool { (isVisible && isSceneActive) || isTripMode }

    private func syncLoop() {
        if shouldLoop {
            guard loopTask == nil else { return }
            isLoopRunning = true
            loopTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let wait = self?.secondsUntilNextRefresh() else { return }
                    if wait > 0.5 {
                        try? await Task.sleep(for: .seconds(wait))
                        continue
                    }
                    await self?.autoRefresh()
                }
            }
        } else if let task = loopTask {
            task.cancel()
            loopTask = nil
            isLoopRunning = false
        }
    }

    /// Lo que falta para el siguiente refresco. Volver a la pestaña no gasta
    /// una llamada si el último tablero es de hace nada.
    private func secondsUntilNextRefresh() -> TimeInterval {
        guard let nextRefreshAt else { return 0 }
        return max(0, nextRefreshAt.timeIntervalSince(clock()))
    }

    // MARK: - Refrescos

    /// Refresco pedido por la persona (tirar, «Reintentar»): cuenta como
    /// consulta en el historial.
    func refresh() async {
        await load(logHistory: true)
    }

    /// Refresco del bucle o del modo trayecto: no engorda el historial (R40).
    func autoRefresh() async {
        await load(logHistory: false)
    }

    /// Fija una ruta (o vuelve a la automática con nil) y refresca al momento
    /// (R39). El tablero anterior se queda hasta que llegue el nuevo (R9).
    func selectRoute(_ routeID: Int?) {
        guard pinnedRouteID != routeID else { return }
        pinnedRouteID = routeID
        epoch += 1
        Task { await self.load(logHistory: true) }
    }

    /// Tras crear, editar o borrar una ruta el tablero puede haber cambiado
    /// (R39). Si se borró la fijada, se vuelve a la automática (R44).
    func routesChanged(_ change: RoutesChange) {
        if case .deleted(let id) = change, pinnedRouteID == id {
            pinnedRouteID = nil
            epoch += 1
        }
        Task { await self.load(logHistory: false) }
    }

    /// Al desemparejar: fuera todo, también la caché.
    func reset() {
        epoch += 1
        board = nil
        emptyMessage = nil
        server = nil
        issue = nil
        pinnedRouteID = nil
        retainedLegSeqs = []
        announcedPlatforms = []
        lastPlatformEvent = nil
        hasLoadedOnce = false
        nextRefreshAt = nil
        persistence.clear()
    }

    private func load(logHistory: Bool) async {
        let myEpoch = epoch
        let routeID = pinnedRouteID
        inFlight += 1
        isLoading = true
        defer {
            inFlight -= 1
            isLoading = inFlight > 0
        }

        do {
            let payload = try await api.board(routeID: routeID, logHistory: logHistory)
            guard myEpoch == epoch else { return }     // se eligió otra ruta
            apply(payload)
            finishAttempt()
        } catch is CancellationError {
            // El bucle se ha parado: no es «sin conexión». Nada cambia.
            return
        } catch let error as APIError {
            guard myEpoch == epoch else { return }
            if error == .notFound, routeID != nil {
                // R44: la ruta fijada ya no existe. No es «sin red»: se vuelve
                // a la que toca y se pide ya.
                pinnedRouteID = nil
                epoch += 1
                await load(logHistory: logHistory)
                return
            }
            issue = Self.designedIssue(for: error)
            finishAttempt()
        } catch {
            guard myEpoch == epoch else { return }
            issue = .other(error.localizedDescription)
            finishAttempt()
        }
    }

    private func finishAttempt() {
        let t = clock()
        hasLoadedOnce = true
        lastAttemptAt = t
        nextRefreshAt = t.addingTimeInterval(refreshInterval)
    }

    private func apply(_ payload: BoardPayload) {
        switch payload {
        case .board(var fresh):
            let t = clock()
            fresh.receivedAt = t
            let (merged, retained) = Self.merge(fresh, previous: board, at: t)
            detectPlatformEvents(in: merged, previous: board, retained: retained, at: t)
            board = merged
            retainedLegSeqs = retained
            server = merged.server ?? server
            emptyMessage = nil
            issue = nil
            persistence.save(CachedBoard(board: merged, receivedAt: t, routeID: pinnedRouteID))
        case .empty(let message, let srv):
            // No es un error: el servidor dice que no hay rutas. Un tablero
            // de una ruta que ya no existe no se enseña.
            board = nil
            retainedLegSeqs = []
            emptyMessage = message
            server = srv ?? server
            issue = nil
            persistence.clear()
        }
    }

    /// R9 por tramo: si un tramo llega con su estación caída (`age` null) y
    /// sin salidas, se conservan las últimas salidas buenas de ese tramo,
    /// con su antigüedad de verdad (la que tenían + lo que llevan guardadas).
    /// El estado de la línea sí es el nuevo.
    nonisolated static func merge(_ fresh: Board, previous: Board?, at now: Date) -> (Board, Set<Int>) {
        guard let previous, previous.route?.id == fresh.route?.id else { return (fresh, []) }
        var merged = fresh
        var retained: Set<Int> = []
        let elapsed = max(0, now.timeIntervalSince(previous.receivedAt))
        for index in merged.legs.indices {
            let leg = merged.legs[index]
            guard leg.stationFailed, leg.departures.isEmpty,
                  let old = previous.legs.first(where: { Self.sameLeg($0, leg) }),
                  !old.departures.isEmpty
            else { continue }
            merged.legs[index].departures = old.departures.map {
                var d = $0
                d.platformNew = false       // ya se cantó en su día
                return d
            }
            merged.legs[index].age = (old.age ?? 0) + elapsed
            retained.insert(leg.seq)
        }
        return (merged, retained)
    }

    nonisolated private static func sameLeg(_ a: Leg, _ b: Leg) -> Bool {
        guard a.seq == b.seq, a.lineId == b.lineId else { return false }
        if !a.fromId.isEmpty, !b.fromId.isEmpty { return a.fromId == b.fromId }
        return true
    }

    /// La vía del tren que se mira (la primera salida de cada tramo) acaba de
    /// aparecer o ha cambiado.
    private func detectPlatformEvents(in fresh: Board, previous: Board?, retained: Set<Int>, at now: Date) {
        for leg in fresh.legs where leg.showsPlatform && !retained.contains(leg.seq) {
            guard let first = leg.departures.first, first.hasRealPlatform,
                  let platform = first.platform else { continue }
            let key = "\(first.id)|\(platform)"
            guard !announcedPlatforms.contains(key) else { continue }
            let previousLeg = previous?.legs.first(where: { $0.seq == leg.seq })
            let before = previousLeg?.departures.first(where: { $0.id == first.id })
            let previousPlatform = before?.platform
            let appeared = first.platformNew || (before != nil && previousPlatform != platform)
            guard appeared else {
                announcedPlatforms.insert(key)     // ya estaba: no se canta
                continue
            }
            announcedPlatforms.insert(key)
            lastPlatformEvent = PlatformEvent(
                id: UUID(), legSeq: leg.seq, departureID: first.id, platform: platform,
                previous: (previousPlatform?.isEmpty == false && previousPlatform != platform) ? previousPlatform : nil,
                at: now)
        }
    }

    /// Error del cliente → estado diseñado.
    nonisolated static func designedIssue(for error: APIError) -> BoardIssue {
        switch error {
        case .network(let message):
            return .offline(message)
        case .notPaired, .unauthorized:
            return .notPaired
        case .notFound:
            return .other("No se encuentra la ruta.")
        case .server(let code, let message, _, let retryAfter):
            switch ServerErrorCode(code: code) {
            case .primKeyMissing: return .noKey
            case .primKeyInvalid, .primKeyRejected: return .keyRejected
            case .primQuotaExhausted: return .quotaExhausted(retryAfter: retryAfter)
            case .primUnreachable, .upstream: return .upstream
            case .unauthorized: return .notPaired
            case .badRequest, .forbidden, .notFound, .pairingInvalid, .rateLimited,
                 .internal, .unknown:
                return .other(error.errorDescription ?? message)
            }
        case .decoding:
            return .other(error.errorDescription ?? "")
        }
    }
}
