import Foundation
#if canImport(ActivityKit) && !TRAJET_LITE
import ActivityKit
#endif

/// La Live Activity del modo trayecto, detrás de un protocolo (en la IPA lite
/// no existe y en los tests se usa una falsa).
///
/// Sin push: se empieza con la app delante («Empezar trayecto»), la app la
/// reescribe en cada refresco del tablero y en cada cambio de minuto mientras
/// dura el trayecto, y se termina con él (docs/diseno/decisiones-la-widgets.md
/// §5.3–5.4). Al tocarla se abre `trajet://ruta/<id>` (lo pone la extensión
/// con `AppLink.route(id:legSeq:departureJID:)`).
@MainActor
protocol TripActivityControlling: AnyObject {
    /// Hay una Live Activity de este trayecto en pantalla.
    var isRunning: Bool { get }
    /// La empieza (con la app delante). false si no se puede (lite, sin App
    /// Group, apagadas en Ajustes, app en segundo plano…).
    func start(_ snapshot: TripActivitySnapshot) async -> Bool
    /// La reescribe (tablero nuevo o cambio de minuto), con alerta si toca.
    func update(_ snapshot: TripActivitySnapshot, alert: TripAlert?) async
    /// La termina: llegada o tiempo máximo dejan «Trayecto terminado» 15 min;
    /// «Parar» la quita al momento.
    func end(_ snapshot: TripActivitySnapshot?, reason: TripEndReason) async
    /// Retoma la que siga viva de esa ruta (la app se cerró en mitad del
    /// trayecto). true si la hay.
    func adopt(routeID: Int) -> Bool
    /// Quita todas las que queden vivas (huérfanas de un cierre).
    func endAll() async
}

/// Sin Live Activity (IPA lite).
@MainActor
final class NoActivityController: TripActivityControlling {
    var isRunning: Bool { false }

    init() {}

    func start(_ snapshot: TripActivitySnapshot) async -> Bool { false }
    func update(_ snapshot: TripActivitySnapshot, alert: TripAlert?) async {}
    func end(_ snapshot: TripActivitySnapshot?, reason: TripEndReason) async {}
    func adopt(routeID: Int) -> Bool { false }
    func endAll() async {}
}

enum TripActivities {
    /// La de verdad en la IPA full; ninguna en la lite (R60).
    @MainActor
    static func system() -> any TripActivityControlling {
#if canImport(ActivityKit) && !TRAJET_LITE
        return ActivityController()
#else
        return NoActivityController()
#endif
    }
}

/// Cuándo se da por caducada una foto de la Live Activity (`staleDate`,
/// docs/diseno/sistema.md §12.4 y decisiones §5.3): el primero de
///  · llegada del tablero + max(90 s, 2 × refresh_hint_s) (el dato es viejo, R19),
///  · salida del tren enseñado + 60 s (el tren ya salió),
///  · siguiente cambio de minuto + 30 s (la cifra la escribe la app).
/// Con «sin conexión» o «servidor sin clave» el primero no cuenta: ya se sabe
/// y ya se dice.
enum ActivityTiming {
    static func staleDate(receivedAt: Date, refreshHint: Int, connectionOK: Bool,
                          shownDeparture: Date?, now: Date) -> Date {
        var candidates: [Date] = []
        if connectionOK {
            let freshness = max(Board.staleAfter, 2 * TimeInterval(max(0, refreshHint)))
            candidates.append(receivedAt.addingTimeInterval(freshness))
        }
        if let shownDeparture {
            candidates.append(shownDeparture.addingTimeInterval(60))
        }
        candidates.append(nextMinute(after: now).addingTimeInterval(30))
        return candidates.min() ?? now.addingTimeInterval(Board.staleAfter)
    }

    /// El siguiente cambio de minuto del reloj (las salidas son a minuto
    /// justo: «HH:MM»).
    static func nextMinute(after date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60 + 60)
    }
}

#if canImport(ActivityKit) && !TRAJET_LITE

/// La de verdad (ActivityKit). Solo si `Capabilities.liveActivitiesAvailable`:
/// no es la lite, hay App Group y el usuario no las ha apagado.
///
/// El `Activity` no se guarda: se guarda su `id` y se busca cada vez en
/// `Activity.activities` desde una función no aislada. Así el objeto nunca
/// cruza de actor (Swift 6 estricto).
@MainActor
final class ActivityController: TripActivityControlling {
    typealias State = TrajetActivityAttributes.ContentState

    /// «Trayecto terminado» se queda este rato y se quita solo.
    nonisolated static let endedLinger: TimeInterval = 15 * 60
    /// Una foto igual que la anterior no se vuelve a escribir antes de esto
    /// (sí para correr `staleDate`).
    nonisolated static let sameStateInterval: TimeInterval = 45

    private(set) var activityID: String?
    private var lastState: State?
    private var lastPushAt: Date?

    var isRunning: Bool { activityID != nil }

    init() {}

    func start(_ snapshot: TripActivitySnapshot) async -> Bool {
        if activityID != nil {
            await update(snapshot, alert: nil)
            return true
        }
        guard Capabilities.liveActivitiesAvailable else { return false }
        if adopt(routeID: snapshot.routeID) {
            await update(snapshot, alert: nil)
            return true
        }
        let state = Self.state(for: snapshot)
        let attributes = TrajetActivityAttributes(routeID: snapshot.routeID, routeName: snapshot.routeName)
        let content = ActivityContent(state: state, staleDate: Self.staleDate(state, now: snapshot.now))
        do {
            let activity = try Activity<TrajetActivityAttributes>.request(attributes: attributes,
                                                                         content: content,
                                                                         pushType: nil)
            activityID = activity.id
            lastState = state
            lastPushAt = snapshot.now
            return true
        } catch {
            // App en segundo plano, demasiadas actividades, apagadas… El
            // trayecto sigue sin ella.
            return false
        }
    }

    func update(_ snapshot: TripActivitySnapshot, alert: TripAlert?) async {
        guard let id = activityID else { return }
        let state = Self.state(for: snapshot)
        if alert == nil, state == lastState, let lastPushAt,
           snapshot.now.timeIntervalSince(lastPushAt) < Self.sameStateInterval {
            return
        }
        lastState = state
        lastPushAt = snapshot.now
        let alive = await Self.push(id: id, state: state,
                                    staleDate: Self.staleDate(state, now: snapshot.now),
                                    alertTitle: alert?.title, alertBody: alert?.body)
        if !alive {
            // La quitó el usuario (o iOS): no se vuelve a crear.
            activityID = nil
            lastState = nil
        }
    }

    func end(_ snapshot: TripActivitySnapshot?, reason: TripEndReason) async {
        let ids = activityID.map { [$0] }
        activityID = nil
        lastState = nil
        lastPushAt = nil
        let finalReason: TrajetActivityAttributes.EndReason? = switch reason {
        case .arrived: .arrived
        case .timeLimit: .maxDuration
        case .manual, .permissionDenied, .failed: nil
        }
        if let finalReason, let snapshot {
            var state = Self.state(for: snapshot)
            state.ended = finalReason
            await Self.finish(ids: ids, state: state,
                              dismissAt: snapshot.now.addingTimeInterval(Self.endedLinger))
        } else {
            await Self.finish(ids: ids, state: nil, dismissAt: nil)
        }
    }

    func adopt(routeID: Int) -> Bool {
        if activityID != nil { return true }
        guard let id = Self.liveID(routeID: routeID) else { return false }
        activityID = id
        return true
    }

    func endAll() async {
        activityID = nil
        lastState = nil
        lastPushAt = nil
        await Self.finish(ids: nil, state: nil, dismissAt: nil)
    }

    // MARK: - La foto

    /// El `ContentState` de B4 (`ActivityContentBuilder`) sobre el tablero
    /// recortado, con la posición del tramo en la ruta entera y el estado de
    /// la conexión, que el constructor no conoce.
    static func state(for snapshot: TripActivitySnapshot) -> State {
        var state = ActivityContentBuilder.make(board: snapshot.board, receivedAt: snapshot.receivedAt,
                                                routeID: snapshot.routeID, now: snapshot.now)
        state.legIndex += snapshot.legOffset
        state.legCount = max(snapshot.legCount, state.legCount)
        state.connection = switch snapshot.connection {
        case .ok: .ok
        case .offline: .offline
        case .noKey: .noKey
        }
        return state
    }

    static func staleDate(_ state: State, now: Date) -> Date {
        ActivityTiming.staleDate(receivedAt: state.receivedAt,
                                 refreshHint: state.refreshHint,
                                 connectionOK: state.connection == .ok,
                                 shownDeparture: state.leg.departures.first(where: { !$0.cancelled })?.at,
                                 now: now)
    }

    // MARK: - ActivityKit, fuera del MainActor

    nonisolated private static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    nonisolated private static func liveID(routeID: Int) -> String? {
        Activity<TrajetActivityAttributes>.activities.first {
            $0.attributes.routeID == routeID && isLive($0.activityState)
        }?.id
    }

    /// false si ya no está (la quitaron).
    nonisolated private static func push(id: String, state: State, staleDate: Date,
                                         alertTitle: String?, alertBody: String?) async -> Bool {
        guard let activity = Activity<TrajetActivityAttributes>.activities.first(where: { $0.id == id }),
              isLive(activity.activityState)
        else { return false }
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let alertTitle, let alertBody {
            // TODO-COMPILAR: `LocalizedStringResource(stringLiteral:)` con un
            // String de variable (es el init de ExpressibleByStringLiteral).
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: alertTitle),
                                           body: LocalizedStringResource(stringLiteral: alertBody),
                                           sound: .default)
            await activity.update(content, alertConfiguration: alert)
        } else {
            await activity.update(content)
        }
        return true
    }

    /// Termina las de `ids` (o todas las vivas con nil).
    nonisolated private static func finish(ids: [String]?, state: State?, dismissAt: Date?) async {
        for activity in Activity<TrajetActivityAttributes>.activities where isLive(activity.activityState) {
            if let ids, !ids.contains(activity.id) { continue }
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            let policy: ActivityUIDismissalPolicy = dismissAt.map { .after($0) } ?? .immediate
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}

#endif
