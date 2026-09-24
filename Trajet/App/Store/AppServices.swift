import Foundation
import Observation

/// El contenedor de la app: una sola configuración, un solo cliente y los
/// stores, que se pasan por el entorno:
///
/// ```swift
/// @Environment(AppServices.self) private var services
/// services.board.board …
/// ```
@MainActor
@Observable
final class AppServices {

    let config: ServerConfig
    let api: TrajetAPI
    let board: BoardStore
    let routes: RoutesStore
    let health: HealthStore
    let maps: MapStore
    let pairing: PairingStore
    /// Ajustes del modo trayecto y de las geocercas (UserDefaults).
    let tripSettings: TripSettings
    /// El modo trayecto (Trajet/App/Trip): empezar, parar, Live Activity y
    /// geocercas. Registra ya el «Parar» de la Live Activity.
    let trip: TripController
    /// Arrancada con `-demo` (servidor falso en proceso).
    let isDemo: Bool

    /// El último enlace `trajet://` recibido que la interfaz tiene que
    /// atender (abrir una pestaña, una hoja…). `MainTabView` lo consume con
    /// `consumePendingLink()`.
    private(set) var pendingLink: AppLink?

    init(config: ServerConfig, api: TrajetAPI, tokens: TokenStore,
         persistence: BoardPersistence, mapDirectory: URL?, isDemo: Bool = false) {
        self.config = config
        self.api = api
        self.board = BoardStore(api: api, persistence: persistence)
        self.routes = RoutesStore(api: api)
        self.health = HealthStore(api: api)
        self.maps = MapStore(api: api, directory: mapDirectory)
        self.pairing = PairingStore(api: api, config: config, tokens: tokens)
        self.isDemo = isDemo
        let tripSettings = TripSettings(defaults: isDemo ? TripSettings.demoDefaults() : .standard)
        self.tripSettings = tripSettings
        self.trip = TripController.make(board: self.board, maps: self.maps, routes: self.routes,
                                        settings: tripSettings, isDemo: isDemo)
        wire()
    }

    /// La app de verdad: Llavero, UserDefaults y disco.
    static func live() -> AppServices {
        let config = ServerConfig()
        let tokens = TokenStore.keychain
        let api = TrajetAPI(config: config, tokens: tokens)
        return AppServices(config: config, api: api, tokens: tokens,
                           persistence: .disk, mapDirectory: MapStore.defaultDirectory)
    }

    private func wire() {
        // Tocar rutas refresca el tablero (R39) y suelta la fijada si se
        // borró (R44); el mapa de una ruta tocada se vuelve a pedir.
        routes.onChange = { [weak self] change in
            guard let self else { return }
            self.board.routesChanged(change)
            switch change {
            case .updated(let id), .deleted(let id): self.maps.forget(routeID: id)
            case .created: break
            }
        }
        pairing.onPaired = { [weak self] in
            guard let self else { return }
            Task {
                await self.board.refresh()
                await self.routes.load()
            }
        }
        pairing.onUnpaired = { [weak self] in
            guard let self else { return }
            self.board.reset()
            self.routes.reset()
            self.health.reset()
            self.maps.clear()
            Task { await self.api.clearETags() }
        }
    }

    // MARK: - Enlaces trajet://

    /// `onOpenURL`: el QR de emparejamiento, los widgets y la Live Activity.
    func handle(url: URL) async {
        guard let link = AppLink(url: url) else { return }
        switch link {
        case .pair:
            await pairing.handle(url: url)
            return
        case .route(let id, _, _), .alternatives(let id):
            board.selectRoute(id)
        case .board:
            Task { await board.refresh() }
        case .settings, .serverSettings:
            break
        }
        pendingLink = link
    }

    /// La interfaz recoge el enlace pendiente (y se borra).
    func consumePendingLink() -> AppLink? {
        defer { pendingLink = nil }
        return pendingLink
    }
}
