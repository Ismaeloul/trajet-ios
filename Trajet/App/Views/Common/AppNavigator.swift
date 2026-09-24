import Foundation
import Observation

/// Las pestañas de la app (docs/diseno/sistema.md §7.11). El planificador
/// vive dentro de Rutas y los ajustes son una hoja que se abre desde la
/// cabecera del tablero.
enum AppTab: Hashable, Sendable, CaseIterable {
    case board
    case trip
    case routes
    case history

    var title: String {
        switch self {
        case .board: "Tablero"
        case .trip: "Trayecto"
        case .routes: "Rutas"
        case .history: "Historial"
        }
    }

    var symbol: String {
        switch self {
        case .board: "clock"
        case .trip: "map"
        case .routes: "point.topleft.down.to.point.bottomright.curvepath"
        case .history: "chart.bar"
        }
    }
}

/// La navegación de la app: qué pestaña se ve, qué hoja está abierta y los
/// avisos efímeros. Lo crea `MainTabView` y lo pasa por el entorno (junto
/// con su `ToastCenter`):
///
/// ```swift
/// @Environment(AppNavigator.self) private var navigator: AppNavigator?
/// navigator?.show(.board)
/// @Environment(ToastCenter.self) private var toasts: ToastCenter?
/// toasts?.show("Ruta guardada", symbol: "checkmark")
/// ```
///
/// Se declara opcional en las vistas para que una vista previa sin él no
/// se caiga.
@MainActor
@Observable
final class AppNavigator {
    /// La pestaña que se ve.
    var tab: AppTab
    /// La hoja de Ajustes (desde la cabecera del tablero o un enlace).
    var showingSettings = false
    /// Un enlace pide abrir las alternativas de esta ruta: el tablero abre la
    /// hoja y lo vuelve a poner a nil.
    var alternativesRouteID: Int?
    /// Un enlace pide enseñar este tramo: el tablero se desplaza hasta él y
    /// lo vuelve a poner a nil.
    var focusLegSeq: Int?
    /// Avisos efímeros de toda la app (R55).
    let toasts: ToastCenter

    init() {
        tab = .board
        toasts = ToastCenter()
    }

    init(tab: AppTab, toasts: ToastCenter) {
        self.tab = tab
        self.toasts = toasts
    }

    /// Cambia de pestaña.
    func show(_ tab: AppTab) {
        self.tab = tab
    }

    /// Atiende un enlace `trajet://` que ya ha pasado por
    /// `AppServices.handle(url:)` (que ya ha fijado la ruta si hacía falta).
    func open(_ link: AppLink) {
        switch link {
        case .pair:
            // Lo atiende el emparejamiento; aquí no hay nada que abrir.
            break
        case .route(_, let legSeq, _):
            tab = .board
            focusLegSeq = legSeq
        case .alternatives(let routeID):
            tab = .board
            alternativesRouteID = routeID
        case .board:
            tab = .board
        case .settings, .serverSettings:
            showingSettings = true
        }
    }
}
