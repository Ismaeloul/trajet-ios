import Foundation
import Observation

/// El modo trayecto (docs/app-v2.md «Modo trayecto», docs/arquitectura.md §6).
///
/// Máquina de estados: `off → askingPermission → active → ended`.
///
/// - Se enciende A MANO («Empezar trayecto») y nunca está encendido siempre:
///   se apaga al llegar (a menos de ~150 m de la estación de destino), al
///   pasar `TripSettings.maxMinutes` (90 por defecto) o a mano, desde la app
///   o desde la Live Activity (`TripStopHandler.stop`).
/// - Mientras dura: ubicación con precisión de 100 m también en segundo plano
///   (solo entonces), el tablero sigue refrescando cada `max(30, hint)` s
///   aunque no se mire (`board.setTripMode(true)`, R7) y la Live Activity se
///   reescribe con cada tablero y cada cambio de minuto.
/// - El permiso de ubicación se pide al empezar. Si se deniega, el trayecto
///   sigue igual pero sin GPS: sin llegada automática, solo el tiempo máximo.
///   El resto de la app no cambia.
/// - Geocercas en las estaciones habituales (con «Siempre» y activadas en
///   Ajustes): al entrar, un refresco del tablero y la Live Activity al día.
@MainActor
@Observable
final class TripController {

    private(set) var state: TripState = .off
    /// La ruta que se va a empezar mientras se espera el permiso.
    private(set) var pendingRouteID: Int? = nil
    /// Cuándo terminó el último trayecto.
    private(set) var endedAt: Date? = nil
    /// Las geocercas que se vigilan ahora mismo.
    private(set) var monitoredStationIDs: Set<String> = []

    let settings: TripSettings
    let location: any LocationService

    private let board: BoardStore
    private let maps: any RouteMapProviding
    /// Las rutas guardadas; nil mientras no se han cargado.
    private let routesProvider: @MainActor () -> [SavedRoute]?
    private let geofences: any GeofenceMonitoring
    private let activity: any TripActivityControlling
    private let records: TripRecordStore
    private let clock: @Sendable () -> Date

    @ObservationIgnored private var tickTask: Task<Void, Never>? = nil
    @ObservationIgnored private var boardToken = 0
    @ObservationIgnored private var lastPushedLeg: Leg? = nil
    @ObservationIgnored private var activityStartAttempts = 0
    @ObservationIgnored private var activityStarted = false
    @ObservationIgnored private var pinnedByTrip = false
    @ObservationIgnored private var pinBeforeTrip: Int? = nil
    @ObservationIgnored private var geofenceTask: Task<Void, Never>? = nil
    @ObservationIgnored private var lastGeofenceRefresh: Date? = nil
    @ObservationIgnored private var requestedMaps: Set<Int> = []

    /// Tope de intentos de empezar la Live Activity en un trayecto.
    nonisolated static let maxActivityStarts = 3
    /// Una geocerca no refresca el tablero más de una vez en este rato.
    nonisolated static let geofenceCooldown: TimeInterval = 5 * 60

    init(board: BoardStore,
         maps: any RouteMapProviding,
         routes: @escaping @MainActor () -> [SavedRoute]?,
         settings: TripSettings,
         location: any LocationService,
         geofences: any GeofenceMonitoring,
         activity: any TripActivityControlling,
         records: TripRecordStore,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.board = board
        self.maps = maps
        self.routesProvider = routes
        self.settings = settings
        self.location = location
        self.geofences = geofences
        self.activity = activity
        self.records = records
        self.clock = now

        location.onLocation = { [weak self] fix in self?.handle(fix) }
        location.onAuthorizationChange = { [weak self] auth in self?.authorizationChanged(auth) }
        geofences.onEnter = { [weak self] id in self?.enteredStation(id) }
        // «Parar» de la Live Activity (StopTripIntent). Se registra ya, no al
        // empezar: si la app se cerró, el botón tiene que poder quitarla.
        TripStopHandler.stop = { [weak self] in
            await self?.stop(reason: .manual)
        }

        restore()
        observeInputs()
        scheduleGeofenceSync()
    }

    // MARK: - Lo que se lee

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var session: TripSession? {
        if case .active(let session) = state { return session }
        return nil
    }

    var activeRouteID: Int? { session?.routeID }

    /// El tramo por el que se va (nil sin trayecto).
    var currentLegSeq: Int? { session?.currentLegSeq }

    var isAskingPermission: Bool { state == .askingPermission }

    var endReason: TripEndReason? {
        if case .ended(let reason) = state { return reason }
        return nil
    }

    /// Hay permiso «Siempre»: las geocercas pueden funcionar.
    var canUseGeofences: Bool { location.authorization == .always }

    /// Las estaciones que se pueden vigilar (subidas de los tramos de las
    /// rutas guardadas), para la lista de Ajustes.
    func watchableStations() -> [StationOption] {
        var seen: Set<String> = []
        var options: [StationOption] = []
        for route in routesProvider() ?? [] {
            for leg in route.legs where !leg.fromId.isEmpty && seen.insert(leg.fromId).inserted {
                options.append(StationOption(id: leg.fromId, name: leg.fromName))
            }
        }
        return options
    }

    // MARK: - Empezar y parar

    /// «Empezar trayecto». Pide el permiso de ubicación si nunca se ha
    /// contestado.
    func start(routeID: Int) async {
        await start(routeID: routeID, askLocation: true)
    }

    /// Con `askLocation: false` empieza sin preguntar (el usuario ha dicho
    /// «Sin ubicación» en la explicación): sin GPS si no hay permiso ya.
    func start(routeID: Int, askLocation: Bool) async {
        switch state {
        case .active, .askingPermission:
            return
        case .off, .ended:
            break
        }
        pendingRouteID = routeID
        prepareBoard(for: routeID)

        var authorization = location.authorization
        if askLocation, authorization == .notDetermined {
            state = .askingPermission
            authorization = await location.requestWhenInUse()
            // Se paró mientras se esperaba la respuesta.
            guard state == .askingPermission else {
                pendingRouteID = nil
                return
            }
        }

        let now = clock()
        let session = TripSession(
            routeID: routeID,
            startedAt: now,
            deadline: now.addingTimeInterval(TimeInterval(settings.maxMinutes * 60)),
            usesLocation: authorization.allowsTrip,
            currentLegSeq: firstLegSeq(routeID: routeID))
        pendingRouteID = nil
        endedAt = nil
        state = .active(session)
        activate(session, restoring: false)
    }

    /// Termina el trayecto. Sin trayecto, «Parar» quita la Live Activity que
    /// hubiera quedado (p. ej. tras un cierre de la app).
    func stop(reason: TripEndReason) async {
        switch state {
        case .off, .ended:
            if reason == .manual { await activity.endAll() }
        case .askingPermission:
            pendingRouteID = nil
            restorePin(routeID: nil)
            endedAt = clock()
            state = .ended(reason)
        case .active(let session):
            let snapshot = makeSnapshot(for: session)
            endedAt = clock()
            state = .ended(reason)
            tearDown(session)
            await activity.end(snapshot, reason: reason)
        }
    }

    /// Vuelve de «terminado» a «apagado» (cierra el aviso).
    func acknowledgeEnd() {
        if case .ended = state { state = .off }
    }

    // MARK: - Ciclo del trayecto

    private func activate(_ session: TripSession, restoring: Bool) {
        records.save(TripRecord(session))
        board.setTripMode(true)
        if session.usesLocation { location.startTripUpdates() }
        lastPushedLeg = nil
        activityStartAttempts = 0
        activityStarted = false
        if restoring, activity.adopt(routeID: session.routeID) {
            activityStarted = true
        }
        let routeID = session.routeID
        Task { [weak self] in
            guard let self else { return }
            await self.maps.load(routeID: routeID, force: false)
            await self.pushActivity()
        }
        observeBoard()
        startTicking()
    }

    private func tearDown(_ session: TripSession) {
        tickTask?.cancel()
        tickTask = nil
        boardToken += 1                 // deja de mirar el tablero
        location.stopTripUpdates()
        board.setTripMode(false)
        records.clear()
        restorePin(routeID: session.routeID)
        lastPushedLeg = nil
    }

    /// Si la app se cerró en mitad de un trayecto, al volver sigue (si no ha
    /// pasado el tiempo máximo). Si no, se quitan las Live Activity huérfanas.
    private func restore() {
        guard let record = records.load() else {
            Task { await self.activity.endAll() }
            return
        }
        guard clock() < record.deadline else {
            records.clear()
            Task { await self.activity.endAll() }
            return
        }
        let session = TripSession(routeID: record.routeID, startedAt: record.startedAt,
                                  deadline: record.deadline,
                                  usesLocation: location.authorization.allowsTrip,
                                  currentLegSeq: record.currentLegSeq, armed: record.armed)
        prepareBoard(for: record.routeID)
        state = .active(session)
        activate(session, restoring: true)
    }

    /// El tablero tiene que ser el de la ruta del trayecto: el bucle refresca
    /// la ruta fijada (o la automática).
    private func prepareBoard(for routeID: Int) {
        guard board.currentRouteID != routeID else {
            pinnedByTrip = false
            return
        }
        pinBeforeTrip = board.pinnedRouteID
        pinnedByTrip = true
        board.selectRoute(routeID)
    }

    /// Al terminar, si el trayecto fijó su ruta, se vuelve a lo de antes.
    private func restorePin(routeID: Int?) {
        guard pinnedByTrip else { return }
        pinnedByTrip = false
        if routeID == nil || board.pinnedRouteID == routeID {
            board.selectRoute(pinBeforeTrip)
        }
    }

    private func firstLegSeq(routeID: Int) -> Int {
        if let current = board.board, current.route?.id == routeID, let first = current.legs.first {
            return first.seq
        }
        if let map = maps.map(for: routeID), let first = map.lines.min(by: { $0.seq < $1.seq }) {
            return first.seq
        }
        return 0
    }

    // MARK: - Reloj (tiempo máximo y cifra de la Live Activity)

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.secondsUntilNextTick() else { return }
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                await self?.tick()
            }
        }
    }

    /// Hasta el siguiente cambio de minuto (la cifra de la Live Activity la
    /// escribe la app) o hasta el tiempo máximo, lo que llegue antes.
    private func secondsUntilNextTick() -> Double? {
        guard let session else { return nil }
        let now = clock()
        let minute = ActivityTiming.nextMinute(after: now).addingTimeInterval(1)
        let next = min(minute, session.deadline)
        return max(1, next.timeIntervalSince(now))
    }

    /// Un latido: comprueba el tiempo máximo y reescribe la Live Activity.
    func tick() async {
        guard let session else { return }
        if clock() >= session.deadline {
            // En otra tarea: parar cancela la del reloj, que es esta.
            Task { await self.stop(reason: .timeLimit) }
            return
        }
        await pushActivity()
    }

    // MARK: - Ubicación

    private func handle(_ fix: TripLocation) {
        guard case .active(var session) = state, session.usesLocation else { return }
        guard TripGeometry.isUsable(fix, now: clock()) else { return }
        session.lastFix = fix
        let map = maps.map(for: session.routeID)
        let wasArmed = session.armed

        if let destination = TripGeometry.destination(in: map) {
            let distance = fix.point.distance(to: destination)
            session.distanceToDestination = distance
            if distance >= TripGeometry.armDistance { session.armed = true }
            if session.armed, TripGeometry.hasArrived(fix, destination: destination) {
                state = .active(session)
                Task { await self.stop(reason: .arrived) }
                return
            }
        } else if requestedMaps.insert(session.routeID).inserted {
            // Sin mapa no hay destino: se pide (una vez) para la próxima.
            let routeID = session.routeID
            Task { await self.maps.load(routeID: routeID, force: false) }
        }

        var legChanged = false
        if let map {
            let next = TripGeometry.legSeq(current: session.currentLegSeq, fix: fix.point, lines: map.lines)
            if next != session.currentLegSeq {
                session.currentLegSeq = next
                legChanged = true
            }
        }
        state = .active(session)
        if legChanged || session.armed != wasArmed {
            records.save(TripRecord(session))
        }
        if legChanged {
            Task { await self.pushActivity() }
        }
    }

    private func authorizationChanged(_ authorization: LocationAuthorization) {
        if case .active(var session) = state {
            if session.usesLocation, !authorization.allowsTrip {
                // Lo quitaron en Ajustes: sigue sin GPS.
                session.usesLocation = false
                location.stopTripUpdates()
                state = .active(session)
                records.save(TripRecord(session))
            } else if !session.usesLocation, authorization.allowsTrip {
                session.usesLocation = true
                location.startTripUpdates()
                state = .active(session)
                records.save(TripRecord(session))
            }
        }
        scheduleGeofenceSync()
    }

    // MARK: - Tablero → Live Activity

    /// Mira el tablero mientras dura el trayecto: cada tablero nuevo (o
    /// cambio de estado de la conexión) se escribe en la Live Activity.
    private func observeBoard() {
        boardToken += 1
        trackBoard(token: boardToken)
    }

    private func trackBoard(token: Int) {
        guard token == boardToken, isActive else { return }
        withObservationTracking {
            _ = board.board
            _ = board.issue
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, token == self.boardToken else { return }
                self.trackBoard(token: token)
                await self.pushActivity()
            }
        }
    }

    /// Escribe la Live Activity con el tablero de ahora (o la empieza).
    func pushActivity() async {
        guard let session, let snapshot = makeSnapshot(for: session) else { return }
        let leg = snapshot.board.legs.first
        let alert = leg.flatMap { TripAlert.detect(previous: lastPushedLeg, current: $0) }
        lastPushedLeg = leg
        if activity.isRunning {
            await activity.update(snapshot, alert: alert)
        } else if !activityStarted, activityStartAttempts < Self.maxActivityStarts {
            activityStartAttempts += 1
            activityStarted = await activity.start(snapshot)
        }
        if alert != nil {
            // Con cuentagotas: solo con lo que merece alerta (§12.7).
            WidgetRefresher.boardDidChange()
        }
    }

    /// El tablero de la ruta del trayecto, recortado desde el tramo en el que
    /// se va. nil si el tablero es de otra ruta o aún no ha llegado.
    func makeSnapshot(for session: TripSession) -> TripActivitySnapshot? {
        guard let current = board.board, current.route?.id == session.routeID, !current.legs.isEmpty
        else { return nil }
        let index = current.legs.firstIndex { $0.seq == session.currentLegSeq } ?? 0
        var trimmed = current
        trimmed.legs = Array(current.legs[index...])
        let name = current.route?.name
            ?? routesProvider()?.first(where: { $0.id == session.routeID })?.name
            ?? ""
        return TripActivitySnapshot(routeID: session.routeID, routeName: name, board: trimmed,
                                    receivedAt: current.receivedAt, legOffset: index,
                                    legCount: current.legs.count,
                                    connection: TripConnection(issue: board.issue), now: clock())
    }

    // MARK: - Geocercas

    /// Pide «Siempre» para las geocercas (lo llama Ajustes al activarlas, con
    /// `TripSettings.geofenceExplanation` a la vista). Si se concede, quedan
    /// activadas; si no, apagadas.
    func requestAlwaysForGeofences() async {
        let authorization = await location.requestAlways()
        settings.geofencesEnabled = authorization == .always
        scheduleGeofenceSync()
    }

    /// Vuelve a mirar ajustes, rutas y permiso cuando cambian.
    private func observeInputs() {
        withObservationTracking {
            _ = settings.geofencesEnabled
            _ = settings.watchedStationIDs
            _ = routesProvider()
            _ = location.authorization
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeInputs()
                self.scheduleGeofenceSync()
            }
        }
    }

    /// Las sincronizaciones van en fila (cada una espera a la anterior).
    private func scheduleGeofenceSync() {
        let previous = geofenceTask
        geofenceTask = Task { [weak self] in
            await previous?.value
            await self?.syncGeofences()
        }
    }

    private func syncGeofences() async {
        if let routes = routesProvider() {
            settings.refreshDefaultStations(from: routes)
        }
        guard settings.geofencesEnabled, location.authorization == .always else {
            await geofences.stopAll()
            monitoredStationIDs = geofences.monitoredIDs
            return
        }
        let routes = routesProvider() ?? []
        let ids = settings.watchedStationIDs

        // Los mapas que hacen falta para las coordenadas (disco o 304).
        for routeID in Self.routesNeedingMaps(ids: ids, routes: routes) where maps.map(for: routeID) == nil {
            await maps.load(routeID: routeID, force: false)
        }

        var stations: [WatchedStation] = []
        var unresolved: Set<String> = []
        for id in ids.sorted() {
            if let station = resolveStation(id, routes: routes) {
                stations.append(station)
            } else {
                unresolved.insert(id)
            }
        }
        await geofences.monitor(stations, keeping: unresolved)
        monitoredStationIDs = geofences.monitoredIDs
    }

    /// Una ruta por estación vigilada (la primera que sube en ella).
    private static func routesNeedingMaps(ids: Set<String>, routes: [SavedRoute]) -> [Int] {
        var result: [Int] = []
        for id in ids.sorted() {
            if let route = routes.first(where: { $0.legs.contains { $0.fromId == id } }), !result.contains(route.id) {
                result.append(route.id)
            }
        }
        return result
    }

    /// Coordenadas de una estación, sacadas del mapa de una ruta que sube en ella.
    private func resolveStation(_ id: String, routes: [SavedRoute]) -> WatchedStation? {
        let zdc = TripSettings.zdc(of: id)
        for route in routes where route.legs.contains(where: { $0.fromId == id }) {
            guard let map = maps.map(for: route.id) else { continue }
            if let station = map.station(zdc: zdc), station.geoPoint.isValid {
                return WatchedStation(id: id, name: station.name, point: station.geoPoint)
            }
            if let line = map.lines.first(where: { $0.from.zdc == zdc }), line.from.geoPoint.isValid {
                return WatchedStation(id: id, name: line.from.name, point: line.from.geoPoint)
            }
        }
        return nil
    }

    /// Se ha entrado en una estación vigilada: un refresco del tablero (sin
    /// historial) y la Live Activity al día si hay trayecto.
    private func enteredStation(_ id: String) {
        let now = clock()
        if let last = lastGeofenceRefresh, now.timeIntervalSince(last) < Self.geofenceCooldown { return }
        lastGeofenceRefresh = now
        Task { [weak self] in
            guard let self else { return }
            await self.board.autoRefresh()
            if self.isActive { await self.pushActivity() }
            WidgetRefresher.boardDidChange()
        }
    }
}

// MARK: - La app de verdad

extension TripController {
    /// El modo trayecto con los servicios del sistema (o los de la demo).
    static func make(board: BoardStore, maps: MapStore, routes: RoutesStore,
                     settings: TripSettings, isDemo: Bool) -> TripController {
        let location: any LocationService
        let geofences: any GeofenceMonitoring
#if DEBUG
        if isDemo {
            location = DemoLocationService()
            geofences = NoGeofences()
        } else {
            location = SystemLocationService()
            geofences = SystemGeofenceService(defaults: settings.defaults)
        }
#else
        location = SystemLocationService()
        geofences = SystemGeofenceService(defaults: settings.defaults)
#endif
        return TripController(board: board, maps: maps,
                              routes: { routes.hasLoaded ? routes.routes : nil },
                              settings: settings, location: location, geofences: geofences,
                              activity: TripActivities.system(),
                              records: TripRecordStore(defaults: settings.defaults))
    }

    /// El enlace de la Live Activity y de la tarjeta: `trajet://ruta/<id>`.
    static func link(routeID: Int) -> URL {
        AppLink.route(id: routeID, legSeq: nil, departureJID: nil).url
    }
}
