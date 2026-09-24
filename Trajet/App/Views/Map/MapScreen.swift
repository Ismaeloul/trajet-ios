import MapKit
import SwiftUI

/// La pestaña «Trayecto»: el mapa entero de la ruta y, abajo, la tarjeta del
/// modo trayecto (docs/diseno/sistema.md §6, §7.10 y §7.14).
///
/// - La ruta es la del trayecto en marcha o, sin trayecto, la que se ve en el
///   tablero (`board.currentRouteID`: la que toca o la elegida). La píldora
///   de arriba cambia la ruta del tablero (una sola «ruta de ahora» en toda
///   la app); con un trayecto en marcha no se puede cambiar.
/// - Controles flotantes de cristal: píldora de ruta, encuadrar la ruta y
///   `MapUserLocationButton` (del sistema).
/// - Aviso discreto si el trazado aún se calcula (`pending`), si el portal de
///   IDFM ha fallado (`stale`) o si alguna línea va en recta.
/// - El camino a pie (MKDirections) solo con permiso de ubicación; el
///   permiso se pide al tocar «Ver el camino a pie», nunca al abrir.
/// - Mientras se mira, el tablero se refresca a su ritmo aunque no se vea la
///   pestaña Tablero (sistema.md §7.11), sin montar un segundo bucle: solo
///   refresca si el del tablero está parado (R7, R40).
struct MapScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapScope
    @State private var walking = WalkingGuide()
    @State private var recenter = 0
    @State private var showingLicense = false

    var body: some View {
        Group {
            if let routeID = MapScreenLogic.routeID(tripRoute: services.trip.activeRouteID,
                                                    boardRoute: services.board.currentRouteID) {
                screen(routeID: routeID)
            } else {
                emptyState
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .task {
            await services.routes.loadIfNeeded()
        }
    }

    // MARK: - Con ruta

    private func screen(routeID: Int) -> some View {
        let map = services.maps.map(for: routeID)
        let legSeq = services.trip.activeRouteID == routeID ? services.trip.currentLegSeq : nil
        let platform = MapScreenLogic.platformHint(board: services.board.board, routeID: routeID,
                                                   legSeq: legSeq, map: map)
        let user = services.trip.location.lastLocation
        let target = map.flatMap { WalkingTarget.resolve(map: $0, legSeq: legSeq, user: user?.point) }

        return RouteMapView(routeID: routeID, style: .full,
                            walkingPath: walking.route?.path ?? [],
                            scope: mapScope, platform: platform, recenter: recenter)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                    topBar(routeID: routeID, map: map)
                    if let notice = MapScreenLogic.notice(map: map,
                                                          isLoading: services.maps.isLoading(routeID),
                                                          failed: services.maps.error(for: routeID) != nil) {
                        noticeView(notice, routeID: routeID)
                    }
                }
                .padding(.horizontal, Metrics.Space.gutter)
                .padding(.top, Metrics.Space.xs)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TripCard(routeID: routeID, walking: walking,
                         hasLicense: !(map?.license ?? "").isEmpty,
                         onShowLicense: { showingLicense = true })
            }
            .mapScope(mapScope)
            .alert("Datos del mapa", isPresented: $showingLicense) {
                Button("Vale", role: .cancel) {}
            } message: {
                Text(map?.license ?? "")
            }
            // El camino a pie: se recalcula cuando cambia la posición o el
            // destino (WalkingGuide ya limita las peticiones a Apple).
            .task(id: WalkKey(target: target, user: user?.point)) {
                await walking.update(user: user, target: target)
            }
            // Una posición suelta de vez en cuando, si ya hay permiso (con
            // trayecto ya la da el propio trayecto).
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    services.trip.location.requestCurrentLocation()
                    try? await Task.sleep(for: .seconds(MapScreenLogic.locationEvery))
                }
            }
            // El tablero al día mientras se mira el mapa (sin segundo bucle).
            .task(id: RefreshKey(routeID: routeID, active: scenePhase == .active)) {
                guard scenePhase == .active else { return }
                await MapScreenLogic.refreshWhileLooking(board: services.board)
            }
    }

    private struct WalkKey: Hashable {
        var target: WalkingTarget?
        var user: GeoPoint?
    }

    private struct RefreshKey: Hashable {
        var routeID: Int
        var active: Bool
    }

    // MARK: - Barra de arriba (cristal)

    private func topBar(routeID: Int, map: RouteMap?) -> some View {
        CristalGroup(spacing: Metrics.Space.sm) {
            HStack(spacing: Metrics.Space.sm) {
                routeMenu(routeID: routeID, map: map)
                Spacer(minLength: 0)
                Button {
                    recenter += 1
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .semibold))
                }
                .cristalButton(circle: true)
                .accessibilityLabel("Encuadrar la ruta")
                // El botón del sistema va desnudo: se le pone el mismo
                // círculo de cristal que a «Encuadrar».
                MapUserLocationButton(scope: mapScope)
                    .frame(width: Metrics.Size.glassButton, height: Metrics.Size.glassButton)
                    .cristal(.control, in: Circle())
                    .accessibilityLabel("Mi posición")
            }
        }
    }

    /// Píldora de ruta: distintivos + nombre. Es un menú para elegir la ruta
    /// del tablero (la que toca o una guardada), salvo en trayecto.
    private func routeMenu(routeID: Int, map: RouteMap?) -> some View {
        let tripOn = services.trip.isActive
        let pill = MapRoutePill(badges: MapScreenLogic.badges(map: map, board: services.board.board,
                                                              routes: services.routes.routes, routeID: routeID),
                                name: MapScreenLogic.routeName(board: services.board.board,
                                                               routes: services.routes.routes, routeID: routeID),
                                showsChevron: !tripOn)
        let spokenRoute: String = "Ruta: " + pill.name
        let hint: String = tripOn ? "Para cambiar de ruta, para antes el trayecto" : "Elige otra ruta"
        return Menu {
            Button {
                services.board.selectRoute(nil)
            } label: {
                if services.board.pinnedRouteID == nil {
                    Label("La que toca ahora", systemImage: "checkmark")
                } else {
                    Label("La que toca ahora", systemImage: "clock")
                }
            }
            if !services.routes.routes.isEmpty {
                Divider()
                ForEach(services.routes.routes, id: \.id) { route in
                    Button {
                        services.board.selectRoute(route.id)
                    } label: {
                        if services.board.pinnedRouteID == route.id {
                            Label(route.name, systemImage: "checkmark")
                        } else {
                            Text(route.name)
                        }
                    }
                }
            }
        } label: {
            pill
        }
        .disabled(tripOn)
        .accessibilityLabel(spokenRoute)
        .accessibilityHint(hint)
    }

    private func noticeView(_ notice: MapScreenLogic.Notice, routeID: Int) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: notice.symbol)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
            if notice.canRetry {
                Button("Reintentar") {
                    let maps = services.maps
                    Task { await maps.load(routeID: routeID, force: true) }
                }
                .font(TextLevel.footnote.font.weight(.semibold))
                .tint(Palette.accent)
                .hitTarget()
            }
        }
        .textLevel(.footnote)
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, Metrics.Space.ml)
        .padding(.vertical, Metrics.Space.s)
        .cristal(.bar, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sin ruta

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Metrics.Space.ml) {
            if !services.board.hasLoadedOnce && services.board.isLoading {
                ProgressView()
                Text("Cargando…")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            } else {
                Image(systemName: "map")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
                Text("Sin ruta que enseñar")
                    .textLevel(.navTitle)
                    .foregroundStyle(Palette.ink)
                Text("Guarda un trayecto en Rutas y aquí verás su mapa, el camino a pie hasta la estación y el modo trayecto.")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Metrics.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Píldora de ruta

/// «[J] Saint-Lazare → Argenteuil ⌄» en una cápsula de cristal de 44 pt.
private struct MapRoutePill: View {
    let badges: [MapScreenLogic.Badge]
    let name: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: Metrics.Space.s) {
            ForEach(badges) { badge in
                LineBadge(code: badge.code, color: badge.color, textColor: badge.textColor,
                          size: Metrics.Size.badgeSmall)
            }
            Text(name)
                .textLevel(.bodyStrong)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Metrics.Space.ml)
        .frame(minHeight: Metrics.Size.glassButton)
        .cristal(.control, in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Reglas de la pantalla (sin vista: se prueban solas)

enum MapScreenLogic {

    /// Cada cuánto se pide una posición suelta sin trayecto (camino a pie).
    static let locationEvery: Double = 60

    /// La ruta del mapa: la del trayecto en marcha; si no, la del tablero.
    static func routeID(tripRoute: Int?, boardRoute: Int?) -> Int? {
        tripRoute ?? boardRoute
    }

    /// Un distintivo de la píldora.
    struct Badge: Hashable, Identifiable, Sendable {
        var id: String
        var code: String
        var color: String
        var textColor: String?
    }

    /// Hasta tres distintivos: los del mapa (con su `text_color` oficial), los
    /// del tablero o los de la ruta guardada, lo primero que haya.
    static func badges(map: RouteMap?, board: Board?, routes: [SavedRoute], routeID: Int) -> [Badge] {
        var result: [Badge] = []
        if let map, !map.lines.isEmpty {
            for line in map.lines.sorted(by: { $0.seq < $1.seq }) {
                result.append(Badge(id: "\(line.seq)", code: line.code, color: line.color,
                                    textColor: line.textColor.isEmpty ? nil : line.textColor))
            }
        } else if let board, board.route?.id == routeID {
            for leg in board.legs {
                result.append(Badge(id: "\(leg.seq)", code: leg.lineCode, color: leg.lineColor, textColor: nil))
            }
        } else if let route = routes.first(where: { $0.id == routeID }) {
            for leg in route.legs.sorted(by: { $0.seq < $1.seq }) {
                result.append(Badge(id: "\(leg.seq)", code: leg.lineCode, color: leg.lineColor, textColor: nil))
            }
        }
        return Array(result.prefix(3))
    }

    /// El nombre de la ruta.
    static func routeName(board: Board?, routes: [SavedRoute], routeID: Int) -> String {
        if let route = board?.route, route.id == routeID, !route.name.isEmpty { return route.name }
        if let saved = routes.first(where: { $0.id == routeID }), !saved.name.isEmpty { return saved.name }
        return "Ruta \(routeID)"
    }

    /// El aviso discreto de arriba.
    struct Notice: Equatable, Sendable {
        var text: String
        var symbol: String
        var canRetry: Bool
    }

    static func notice(map: RouteMap?, isLoading: Bool, failed: Bool) -> Notice? {
        guard let map else {
            if isLoading {
                return Notice(text: "Cargando el mapa…", symbol: "map", canRetry: false)
            }
            if failed {
                return Notice(text: "No se ha podido cargar el mapa", symbol: "wifi.slash", canRetry: true)
            }
            return nil
        }
        if map.lines.isEmpty {
            return Notice(text: "Esta ruta aún no tiene mapa", symbol: "map", canRetry: false)
        }
        if map.pending {
            return Notice(text: "Calculando el trazado · de momento, rectas entre paradas",
                          symbol: "hourglass", canRetry: false)
        }
        if map.stale {
            return Notice(text: "Trazado guardado: el portal de IDFM no responde ahora",
                          symbol: "clock.arrow.circlepath", canRetry: false)
        }
        if map.lines.contains(where: \.isStraightLine) {
            return Notice(text: "Alguna línea va en recta: no hay trazado abierto",
                          symbol: "line.diagonal", canRetry: false)
        }
        return nil
    }

    /// Dónde señalar la vía del tren que toca: la vía con coordenadas de la
    /// estación de subida (solo las SNCF las tienen). Real si está
    /// publicada; probable si solo hay previsión (R10). Sin vía esperada
    /// (R3) o sin coordenadas, nada.
    static func platformHint(board: Board?, routeID: Int, legSeq: Int?, map: RouteMap?) -> MapPlatformHint? {
        guard let board, board.route?.id == routeID, let map else { return nil }
        let leg = legSeq.flatMap { seq in board.legs.first { $0.seq == seq } } ?? board.legs.first
        guard let leg, leg.showsPlatform,
              let departure = leg.departures.first(where: { !$0.isCancelled })
        else { return nil }
        let zdc = map.line(seq: leg.seq)?.from.zdc ?? TripSettings.zdc(of: leg.fromId)
        guard let station = map.station(zdc: zdc) else { return nil }
        if departure.hasRealPlatform, let platform = departure.platform, !platform.isEmpty {
            guard let track = station.track(platform), track.geoPoint.isValid else { return nil }
            return MapPlatformHint(point: track.geoPoint, platform: platform, isReal: true)
        }
        if let guess = departure.guess, !guess.platform.isEmpty,
           let track = station.track(guess.platform), track.geoPoint.isValid {
            return MapPlatformHint(point: track.geoPoint, platform: guess.platform, isReal: false)
        }
        return nil
    }

    /// Refresca el tablero a su ritmo mientras se mira el mapa, pero solo si
    /// su propio bucle está parado (fuera de la pestaña Tablero y sin
    /// trayecto): nunca dos refrescos a la vez. Se para al cancelarse (la
    /// pestaña se va o la app pasa a segundo plano). Sin historial (R40).
    @MainActor
    static func refreshWhileLooking(board: BoardStore) async {
        while !Task.isCancelled {
            let wait = board.nextRefreshAt.map { $0.timeIntervalSinceNow } ?? 0
            if wait > 0.5 {
                try? await Task.sleep(for: .seconds(min(wait, 30)))
                continue
            }
            if !board.isLoopRunning {
                await board.autoRefresh()
            }
            // Nunca en bucle apretado (un refresco descartado no mueve
            // `nextRefreshAt`).
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

#if DEBUG
#Preview("Mapa · J a Argenteuil") {
    MapScreen()
        .environment(AppServices.demo(escenario: "tranquilo"))
}
#endif
