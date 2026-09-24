#if DEBUG
import ActivityKit
import SwiftUI
import WidgetKit

// Vistas previas de la Live Activity y de los widgets con los bancos de
// `PreviewData` (R13): los mismos JSON de /api/v1 que usan los tests y la
// demo, a las 12:50 de París. Solo en DEBUG.

/// Estados de muestra (Live Activity) y entradas del timeline (widgets).
enum GlancePreview {

    /// Las 12:50 de hoy en París: la hora de los bancos de prueba.
    static var reference: Date {
        Departure.parisDate("12:50", near: Date()) ?? Date()
    }

    static let attributes = TrajetActivityAttributes(routeID: 5, routeName: "Saint-Lazare → Argenteuil")

    /// Un banco, retocado si hace falta (cancelado, cambio de vía…).
    static func board(_ c: PreviewData.BoardCase, edit: (inout Board) -> Void = { _ in }) -> Board {
        var b = PreviewData.board(c)
        edit(&b)
        return b
    }

    // MARK: Live Activity

    static func state(_ c: PreviewData.BoardCase, seconds: TimeInterval = 10,
                      options: ActivityContentBuilder.Options = ActivityContentBuilder.Options())
        -> TrajetActivityAttributes.ContentState {
        state(board: board(c), seconds: seconds, options: options)
    }

    static func state(board: Board, seconds: TimeInterval = 10,
                      options: ActivityContentBuilder.Options = ActivityContentBuilder.Options())
        -> TrajetActivityAttributes.ContentState {
        let ref = reference
        return ActivityContentBuilder.make(board: board, receivedAt: ref, routeID: board.route?.id ?? 0,
                                           now: ref.addingTimeInterval(seconds), options: options)
    }

    /// El primer tren cancelado (`status: "cancelled"`).
    static var cancelled: TrajetActivityAttributes.ContentState {
        state(board: board(.viaAparece) { $0.legs[0].departures[0].status = "cancelled" })
    }

    /// Misma salida, otra vía: «cambio de vía · antes 21».
    static var platformChange: TrajetActivityAttributes.ContentState {
        let before = state(.viaAparece)
        let after = board(.viaAparece) {
            $0.legs[0].departures[0].platform = "23"
            $0.legs[0].departures[0].platformNew = false
        }
        return state(board: after, seconds: 40, options: ActivityContentBuilder.Options(previous: before))
    }

    /// El bus a 1h46 (R6): sin los dos primeros.
    static var bus146: TrajetActivityAttributes.ContentState {
        state(board: board(.bus106) { $0.legs[0].departures.removeFirst(2) })
    }

    /// Nombres largos (auditoría de recortes del laboratorio).
    static var longNames: TrajetActivityAttributes.ContentState {
        state(board: board(.viaAparece) { b in
            b.legs[0].lineCode = "B"
            b.legs[0].lineColor = "5091CB"
            b.legs[0].lineMode = "RER"
            b.legs[0].directions = ["Aéroport Charles de Gaulle 2 TGV"]
            for i in b.legs[0].departures.indices {
                b.legs[0].departures[i].destination = "Aéroport Charles de Gaulle 2 TGV"
            }
        })
    }

    static var offline: TrajetActivityAttributes.ContentState {
        state(.viaAparece, seconds: 240, options: ActivityContentBuilder.Options(connection: .offline))
    }

    static var noKey: TrajetActivityAttributes.ContentState {
        state(.viaAparece, seconds: 240, options: ActivityContentBuilder.Options(connection: .noKey))
    }

    static var ended: TrajetActivityAttributes.ContentState {
        ActivityContentBuilder.ended(state(.unTramo), reason: .arrived, at: reference)
    }

    // MARK: Widgets

    /// La entrada del timeline que toca `seconds` después de la recarga.
    static func snapshot(board: Board, after seconds: TimeInterval = 300,
                         failure: WidgetFailure? = nil) -> WidgetSnapshot {
        let ref = reference
        let cached = CachedBoard(board: board, receivedAt: ref, routeID: board.route?.id)
        let plan = WidgetTimelinePlanner.plan(cached: cached, hasAppGroup: true, failure: failure, now: ref)
        let target = ref.addingTimeInterval(seconds)
        return plan.snapshots.last(where: { $0.date <= target }) ?? plan.snapshots[0]
    }

    static func entry(_ c: PreviewData.BoardCase, after seconds: TimeInterval = 300,
                      failure: WidgetFailure? = nil) -> TrajetEntry {
        TrajetEntry(snapshot: snapshot(board: board(c), after: seconds, failure: failure))
    }

    static func entry(board: Board, after seconds: TimeInterval = 300,
                      failure: WidgetFailure? = nil) -> TrajetEntry {
        TrajetEntry(snapshot: snapshot(board: board, after: seconds, failure: failure))
    }

    /// La entrada final: «Sin datos recientes · abre Trajet».
    static func finalEntry(_ c: PreviewData.BoardCase) -> TrajetEntry {
        let ref = reference
        let cached = CachedBoard(board: board(c), receivedAt: ref, routeID: nil)
        let plan = WidgetTimelinePlanner.plan(cached: cached, hasAppGroup: true, failure: nil, now: ref)
        return TrajetEntry(snapshot: plan.snapshots[plan.snapshots.count - 1])
    }

    /// IPA full firmada sin App Group.
    static var unavailableEntry: TrajetEntry {
        let plan = WidgetTimelinePlanner.plan(cached: nil, hasAppGroup: false, failure: nil, now: reference)
        return TrajetEntry(snapshot: plan.snapshots[0])
    }

    static var cancelledBoard: Board {
        board(.viaAparece) { $0.legs[0].departures[0].status = "cancelled" }
    }
}

// MARK: - Live Activity

// TODO-COMPILAR: macros `#Preview(_:as:using:widget:contentStates:)` (iOS 17)
// y `#Preview(_:as:widget:timeline:)`, con la forma de las plantillas de
// Xcode. Si alguna diera guerra con Swift 6, se puede quitar sin tocar nada
// más: solo son vistas previas (DEBUG).
#Preview("Actividad · bloqueo", as: .content, using: GlancePreview.attributes) {
    TrajetLiveActivity()
} contentStates: {
    GlancePreview.state(.unTramo)
    GlancePreview.state(.viaAparece)
    GlancePreview.state(.viaProbable)
    GlancePreview.state(.destinosMezclados)
    GlancePreview.bus146
    GlancePreview.state(.lineaCortada)
    GlancePreview.state(.enAnden)
    GlancePreview.state(.tranquilo)
    GlancePreview.state(.transbordo)
    GlancePreview.platformChange
}

#Preview("Actividad · más estados", as: .content, using: GlancePreview.attributes) {
    TrajetLiveActivity()
} contentStates: {
    GlancePreview.cancelled
    GlancePreview.offline
    GlancePreview.noKey
    GlancePreview.longNames
    GlancePreview.state(.tramoVacio)
    GlancePreview.ended
}

/// Caducada (`staleDate` vencida): el sistema no deja elegirlo en las vistas
/// previas de actividades, así que se pinta la vista suelta.
#Preview("Actividad · caducada") {
    VStack(spacing: 16) {
        ActivityLockScreenView(
            presentation: ActivityPresentation(state: GlancePreview.state(.viaAparece), isStale: true, routeID: 5),
            routeName: "Saint-Lazare → Argenteuil")
        ActivityLockScreenView(
            presentation: ActivityPresentation(state: GlancePreview.state(.unTramo), isStale: true, routeID: 5),
            routeName: "Saint-Lazare → Argenteuil")
    }
    .background(Palette.surfaceHi)
}

#Preview("Isla · compacta", as: .dynamicIsland(.compact), using: GlancePreview.attributes) {
    TrajetLiveActivity()
} contentStates: {
    GlancePreview.state(.unTramo)
    GlancePreview.state(.viaProbable)
    GlancePreview.bus146
    GlancePreview.state(.enAnden)
    GlancePreview.state(.lineaCortada)
    GlancePreview.offline
}

#Preview("Isla · expandida", as: .dynamicIsland(.expanded), using: GlancePreview.attributes) {
    TrajetLiveActivity()
} contentStates: {
    GlancePreview.state(.viaAparece)
    GlancePreview.platformChange
    GlancePreview.state(.transbordo)
    GlancePreview.state(.lineaCortada)
    GlancePreview.noKey
    GlancePreview.ended
}

#Preview("Isla · mínima", as: .dynamicIsland(.minimal), using: GlancePreview.attributes) {
    TrajetLiveActivity()
} contentStates: {
    GlancePreview.state(.unTramo)
    GlancePreview.bus146
    GlancePreview.state(.enAnden)
    GlancePreview.offline
}

// MARK: - Widgets de inicio

#Preview("Pequeño", as: .systemSmall) {
    TrajetHomeWidget()
} timeline: {
    GlancePreview.entry(.unTramo)
    GlancePreview.entry(.viaProbable)
    GlancePreview.entry(.enAnden, after: 30)
    GlancePreview.entry(.cincoTramos)
    GlancePreview.entry(board: GlancePreview.cancelledBoard)
    GlancePreview.entry(.unTramo, failure: .offline)
    GlancePreview.finalEntry(.unTramo)
    GlancePreview.unavailableEntry
}

#Preview("Mediano", as: .systemMedium) {
    TrajetHomeWidget()
} timeline: {
    GlancePreview.entry(.unTramo)
    GlancePreview.entry(.destinosMezclados)
    GlancePreview.entry(.bus106)
    GlancePreview.entry(.lineaCortada)
    GlancePreview.entry(board: GlancePreview.cancelledBoard)
    GlancePreview.entry(.unTramo, failure: .noKey)
    GlancePreview.finalEntry(.viaProbable)
}

#Preview("Grande", as: .systemLarge) {
    TrajetHomeWidget()
} timeline: {
    GlancePreview.entry(.tranquilo)
    GlancePreview.entry(.cincoTramos)
    GlancePreview.entry(.transbordo)
    GlancePreview.entry(.destinosMezclados)
    GlancePreview.entry(.tranquilo, failure: .offline)
    GlancePreview.unavailableEntry
}

// MARK: - Widgets de la pantalla de bloqueo

#Preview("Bloqueo · circular", as: .accessoryCircular) {
    TrajetLockWidget()
} timeline: {
    GlancePreview.entry(.unTramo)
    GlancePreview.entry(.bus106)
    GlancePreview.entry(.enAnden, after: 30)
    GlancePreview.entry(.lineaCortada)
    GlancePreview.entry(.unTramo, failure: .offline)
    GlancePreview.finalEntry(.unTramo)
}

#Preview("Bloqueo · rectangular", as: .accessoryRectangular) {
    TrajetLockWidget()
} timeline: {
    GlancePreview.entry(.unTramo)
    GlancePreview.entry(.viaProbable)
    GlancePreview.entry(board: GlancePreview.cancelledBoard)
    GlancePreview.entry(.lineaCortada)
    GlancePreview.entry(.unTramo, failure: .noKey)
    GlancePreview.finalEntry(.unTramo)
}

#Preview("Bloqueo · en línea", as: .accessoryInline) {
    TrajetLockWidget()
} timeline: {
    GlancePreview.entry(.unTramo)
    GlancePreview.entry(.viaProbable)
    GlancePreview.entry(.bus106)
    GlancePreview.entry(.unTramo, failure: .offline)
}
#endif
