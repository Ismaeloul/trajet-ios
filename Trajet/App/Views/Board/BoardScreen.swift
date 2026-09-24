import SwiftUI
import UIKit

/// El tablero (docs/diseno/sistema.md §7.1): lo que se mira de reojo, de pie
/// y con una mano (R1). De arriba abajo:
///
/// 1. El mapa de la ruta en el 46 % de arriba, quieto y fundido con el fondo
///    (`RouteMapView(style: .header)`); tocarlo abre el mapa entero con el
///    zoom de iOS 18 (push normal en iOS 17). Sin ruta, no hay mapa.
/// 2. La cabecera de cristal con la ruta que toca y el selector (R37, R39) y
///    el botón de Ajustes.
/// 3. La píldora de estado con la antigüedad SIEMPRE (R17, R18) y la barra
///    del próximo refresco (R54). No se apaga con el dato viejo: lo explica.
/// 4. Las tarjetas de tramo, OPACAS (billete + fichas, R47), que se apagan
///    enteras con el dato viejo (R19).
/// 5. «Empezar trayecto» / «Parar», «Buscar alternativa» (R29) y el pie con
///    los errores de estación (R26) y la cuota (R46).
///
/// Nunca pantalla en blanco (R9, R53): con cualquier error, si hay tablero
/// guardado se enseña ese; sin nada, esqueleto, vacío que dice qué hacer o el
/// error diseñado. El bucle de refresco corre solo con la pantalla delante
/// (`setVisible`, R7).
struct BoardScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// «Vibrar cuando aparece la vía» (Ajustes, ajustes-b.md A34).
    @AppStorage(BoardPreferences.platformHapticKey) private var platformHapticOn = true

    @Namespace private var zoom
    @State private var path: [BoardDestination] = []
    @State private var sheet: BoardSheet?
    @State private var throttle = BoardRefreshThrottle()
    /// La persona ha pedido volver a «La que toca ahora»: que la fijada pase
    /// a nil no es una ruta borrada (R44).
    @State private var expectingAutoRoute = false
    @State private var platformHaptic = HapticTrigger()
    @State private var trainSoonHaptic = HapticTrigger()
    @State private var disruptionHaptic = HapticTrigger()
    @State private var interruptionHaptic = HapticTrigger()
    @State private var selectionHaptic = HapticTrigger()

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                ScrollViewReader { reader in
                    screen(size: proxy.size, topInset: proxy.safeAreaInsets.top)
                        .onChange(of: navigator?.focusLegSeq) { _, _ in
                            focusIfRequested(reader)
                        }
                        .onChange(of: services.board.board?.legs.map(\.seq)) { _, _ in
                            focusIfRequested(reader)
                        }
                        .onAppear { focusIfRequested(reader) }
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BoardDestination.self) { destination in
                switch destination {
                case .map(let routeID, let title):
                    BoardFullMap(routeID: routeID, title: title)
                        .trajetZoomTransition(sourceID: BoardZoomID.map, in: zoom)
                }
            }
            // R7: el bucle solo corre con el tablero delante. Al irse a otra
            // pestaña manda la pestaña (Trayecto también lo mantiene); al
            // abrir el mapa entero dentro del tablero, se para.
            .onAppear {
                services.board.setVisible(true)
                openAlternativesIfRequested()
            }
            .onDisappear {
                services.board.setVisible(navigator?.tab == .trip)
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .haptic(.platformPublished, trigger: platformHaptic)
        .haptic(.trainSoon, trigger: trainSoonHaptic)
        .haptic(.disruption, trigger: disruptionHaptic)
        .haptic(.interruption, trigger: interruptionHaptic)
        .haptic(.selection, trigger: selectionHaptic)
        .onChange(of: services.board.lastPlatformEvent) { _, event in
            platformAppeared(event)
        }
        .onChange(of: BoardHapticRules.watch(board: services.board.board)) { old, new in
            guard !services.board.isStale(), BoardHapticRules.trainSoon(from: old, to: new) else { return }
            trainSoonHaptic.fire()
        }
        .onChange(of: BoardHapticRules.levelWatch(board: services.board.board)) { old, new in
            guard !services.board.isStale(),
                  let haptic = BoardHapticRules.levelHaptic(from: old, to: new) else { return }
            if haptic == .interruption {
                interruptionHaptic.fire()
            } else {
                disruptionHaptic.fire()
            }
        }
        .onChange(of: services.board.pinnedRouteID) { old, new in
            pinnedRouteChanged(from: old, to: new)
        }
        .onChange(of: navigator?.alternativesRouteID) { _, _ in
            openAlternativesIfRequested()
        }
        .task {
            // El selector de ruta de la cabecera (una sola carga, R41).
            await services.routes.loadIfNeeded()
        }
    }

    // MARK: - Maqueta

    private func screen(size: CGSize, topInset: CGFloat) -> some View {
        let mapRoute = services.board.board?.route
        return ZStack(alignment: .top) {
            if let mapRoute {
                BoardHeaderMap(routeID: mapRoute.id, height: size.height * 0.46 + topInset, zoom: zoom)
            }
            ScrollView {
                TimelineView(.periodic(from: .now, by: 5)) { timeline in
                    content(now: timeline.date, route: mapRoute,
                            window: mapRoute == nil ? nil : mapWindowHeight(size))
                }
            }
            .refreshable {
                await pullToRefresh()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// El hueco transparente por el que se ve el mapa (B: 34 % de la
    /// pantalla, 26 % con letra grande), descontada la cabecera.
    private func mapWindowHeight(_ size: CGSize) -> CGFloat {
        let share: CGFloat = dynamicTypeSize >= .xxLarge ? 0.26 : 0.34
        return max(64, size.height * share - 76)
    }

    private var header: some View {
        let store = services.board
        return BoardHeader(board: store.board,
                           pinnedRouteID: store.pinnedRouteID,
                           isSwitching: store.isShowingOtherRoute && store.isLoading,
                           routes: services.routes.routes,
                           onSelect: { selectRoute($0) },
                           onSettings: { openSettings() })
            .padding(.horizontal, Metrics.Space.gutter)
            .padding(.top, Metrics.Space.xs)
            .padding(.bottom, Metrics.Space.sm)
    }

    // MARK: - Contenido

    @ViewBuilder
    private func content(now: Date, route: BoardRoute?, window: CGFloat?) -> some View {
        let store = services.board
        let state = BoardContentState.make(board: store.board, emptyMessage: store.emptyMessage,
                                           issue: store.issue)
        VStack(spacing: Metrics.Space.gutter) {
            if let route, let window {
                mapWindow(route: route, height: window)
            }
            switch state {
            case .loading:
                BoardSkeleton()
            case .noRoutes:
                EmptyBoardView(kind: .noRoutes, onCreateRoute: { goToRoutes() })
            case .issue(let issue):
                BoardIssueView(issue: issue,
                               isRetrying: store.isLoading,
                               onRetry: { retry() },
                               onOpenSettings: { openSettings() },
                               onRepair: { repair() })
            case .noLegs:
                if let board = store.board {
                    pill(board: board, now: now)
                }
                EmptyBoardView(kind: .noLegs, onCreateRoute: { goToRoutes() })
            case .board:
                if let board = store.board {
                    boardBody(board, now: now)
                }
            }
        }
        .padding(.horizontal, Metrics.Space.gutter)
        .padding(.top, Metrics.Space.xs)
        .padding(.bottom, Metrics.Space.xxl)
    }

    /// El tablero con datos.
    @ViewBuilder
    private func boardBody(_ board: Board, now: Date) -> some View {
        let dimmed = BoardDimming.isDimmed(board: board, now: now)
        let density = BoardDensity(legCount: board.legs.count)
        pill(board: board, now: now)
        VStack(spacing: Metrics.Space.gutter) {
            ForEach(board.legs) { leg in
                legCard(leg, board: board, density: density, live: !dimmed, now: now)
                    .id(leg.seq)
            }
            if !board.disruptionsOK {
                DisruptionsUnreadNotice()
            }
        }
        .opacity(BoardDimming.opacity(dimmed: dimmed))
        .saturation(BoardDimming.saturation(dimmed: dimmed))
        .animation(Motion.animation(.staleDim, reduceMotion: reduceMotion), value: dimmed)
        actions(board)
        BoardFooter(board: board)
            .opacity(BoardDimming.opacity(dimmed: dimmed))
            .saturation(BoardDimming.saturation(dimmed: dimmed))
            .animation(Motion.animation(.staleDim, reduceMotion: reduceMotion), value: dimmed)
    }

    private func legCard(_ leg: Leg, board: Board, density: BoardDensity, live: Bool, now: Date) -> some View {
        let store = services.board
        let retained = store.isRetained(seq: leg.seq)
        let isNew: Bool = leg.departures.first.map {
            BoardPlatformState.isNew(departure: $0, leg: leg, event: store.lastPlatformEvent,
                                     receivedAt: board.receivedAt, now: now, live: live)
        } ?? false
        let seq = leg.seq
        return LegCard(leg: leg,
                       density: density,
                       officialTextColor: officialTextColor(leg: leg, routeID: board.route?.id),
                       retainedAge: retained ? (store.legAge(seq: seq, now: now) ?? 0) : nil,
                       stationError: BoardText.stationError(for: leg, in: board),
                       isNewPlatform: isNew,
                       onOpen: { sheet = .leg(seq) })
    }

    /// La tinta oficial del distintivo (`text_color` del mapa), si el mapa
    /// ya está; si no, `LineBadge` la calcula con contraste garantizado (R12).
    private func officialTextColor(leg: Leg, routeID: Int?) -> String? {
        guard let routeID,
              let text = services.maps.map(for: routeID)?.line(seq: leg.seq)?.textColor,
              !text.isEmpty
        else { return nil }
        return text
    }

    /// La píldora (con la barra del próximo refresco mientras el bucle corre).
    /// Con un problema que se arregla en Ajustes (sin clave, clave rechazada,
    /// sin emparejar), tocarla los abre.
    @ViewBuilder
    private func pill(board: Board, now: Date) -> some View {
        let store = services.board
        if let model = BoardPill.make(board: board, issue: store.issue, server: store.server, now: now) {
            let running = store.isLoopRunning
            let statusPill = StatusPill(pill: model,
                                        refreshFrom: running ? store.lastAttemptAt : nil,
                                        refreshTo: running ? store.nextRefreshAt : nil,
                                        now: now)
            Group {
                if pillOpensSettings(store.issue, server: store.server) {
                    Button {
                        openSettings()
                    } label: {
                        statusPill
                            .frame(minHeight: Metrics.Size.hit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre los ajustes del servidor")
                } else {
                    statusPill
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pillOpensSettings(_ issue: BoardIssue?, server: ServerState?) -> Bool {
        switch issue {
        case .noKey?, .keyRejected?, .notPaired?:
            return true
        case .offline?, .quotaExhausted?, .upstream?, .other?:
            return false
        case nil:
            switch server?.primKey {
            case .missing?, .invalid?, .forbidden?: return true
            case .valid?, .quotaExhausted?, .unreachable?, .unknown?, nil: return false
            }
        }
    }

    /// «Empezar trayecto» / «Parar» y «Buscar alternativa». Sin ruta no hay
    /// nada que empezar ni alternativa que buscar.
    @ViewBuilder
    private func actions(_ board: Board) -> some View {
        if let routeID = board.route?.id {
            VStack(spacing: Metrics.Space.m) {
                BoardTripControls(routeID: routeID)
                if BoardText.alternativesIsUrgent(board) {
                    Button {
                        sheet = .alternatives(routeID)
                    } label: {
                        Label(BoardText.alternativesTitle(board), systemImage: "arrow.triangle.swap")
                    }
                    .filledButton(.danger)
                } else {
                    Button {
                        sheet = .alternatives(routeID)
                    } label: {
                        Label(BoardText.alternativesTitle(board), systemImage: "arrow.triangle.swap")
                            .frame(maxWidth: .infinity)
                    }
                    .cristalButton()
                    // iOS 26: el botón de cristal del sistema en grande (≥ 44 pt, R52).
                    .controlSize(.large)
                }
            }
            .padding(.top, Metrics.Space.xs)
        }
    }

    /// El trozo de pantalla por el que se ve el mapa: tocarlo lo abre entero.
    /// Para VoiceOver y para quien no sepa que se toca, el botón redondo.
    private func mapWindow(route: BoardRoute, height: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                openMap(route)
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            Button {
                openMap(route)
            } label: {
                Image(systemName: "map")
                    .font(.title3.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .cristalButton(circle: true)
            .accessibilityLabel("Abrir el mapa de la ruta")
            .padding(.bottom, Metrics.Space.xs)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func sheetContent(_ item: BoardSheet) -> some View {
        Group {
            switch item {
            case .leg(let seq):
                LegDetailSheet(legSeq: seq)
            case .alternatives(let routeID):
                AlternativesSheet(routeID: routeID)
            }
        }
        .environment(services)
    }

    // MARK: - Acciones

    /// Tirar para refrescar, con un mínimo de 3 s entre tirones (R7: la cuota
    /// es de mil llamadas al día).
    private func pullToRefresh() async {
        guard throttle.allow(at: .now) else {
            // Un tirón nervioso: no se gasta otra llamada; el indicador se va.
            try? await Task.sleep(for: .milliseconds(350))
            return
        }
        await services.board.refresh()
    }

    private func retry() {
        let store = services.board
        Task { await store.refresh() }
    }

    private func selectRoute(_ routeID: Int?) {
        let store = services.board
        if routeID == nil, store.pinnedRouteID != nil {
            expectingAutoRoute = true
        }
        selectionHaptic.fire()
        store.selectRoute(routeID)
    }

    private func openSettings() {
        navigator?.showingSettings = true
    }

    private func goToRoutes() {
        navigator?.show(.routes)
    }

    /// «Emparejar de nuevo» (401): se olvida el emparejamiento de aquí y la
    /// raíz enseña el emparejamiento.
    private func repair() {
        services.pairing.forgetLocally()
    }

    private func openMap(_ route: BoardRoute) {
        let title = route.name.isEmpty ? "Mapa" : route.name
        path.append(.map(routeID: route.id, title: title))
    }

    /// Un enlace `trajet://ruta/{id}/alternativas` (widget, Live Activity)
    /// abre la hoja. Pedirlas sigue siendo cosa de abrirla (R29).
    private func openAlternativesIfRequested() {
        guard let routeID = navigator?.alternativesRouteID else { return }
        navigator?.alternativesRouteID = nil
        sheet = .alternatives(routeID)
    }

    /// Un enlace a un tramo concreto: se baja hasta él cuando esté.
    private func focusIfRequested(_ reader: ScrollViewProxy) {
        guard let seq = navigator?.focusLegSeq,
              services.board.board?.legs.contains(where: { $0.seq == seq }) == true
        else { return }
        navigator?.focusLegSeq = nil
        withMotion(.morph, reduceMotion: reduceMotion) {
            reader.scrollTo(seq, anchor: .top)
        }
    }

    /// La vía del tren que se mira acaba de salir (R2): háptica (si está
    /// activada en Ajustes) y aviso a VoiceOver. Nunca con el dato viejo.
    private func platformAppeared(_ event: PlatformEvent?) {
        guard let event, !services.board.isStale() else { return }
        if platformHapticOn {
            platformHaptic.fire()
        }
        let text: String
        if let previous = event.previous {
            text = "Cambio de vía: ahora sale por la \(event.platform), antes la \(previous)"
        } else {
            text = "Acaba de salir la vía \(event.platform)"
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// La ruta fijada vuelve a nil sin que nadie lo pida: se ha borrado o el
    /// servidor dice 404 (R44). Aviso efímero, nunca un diálogo (R55); desde
    /// Rutas ya lo dice quien la borró.
    private func pinnedRouteChanged(from old: Int?, to new: Int?) {
        guard old != nil, new == nil else { return }
        if expectingAutoRoute {
            expectingAutoRoute = false
            return
        }
        // Al desemparejar también se suelta la fijada: eso no es una ruta
        // borrada.
        guard services.pairing.isPaired, (navigator?.tab ?? .board) == .board else { return }
        toasts?.show("Esa ruta ya no existe", symbol: "exclamationmark.triangle")
    }
}

// MARK: - Piezas

/// Qué hoja tiene abierta el tablero.
enum BoardSheet: Identifiable, Hashable {
    /// El detalle de un tramo (`Leg.seq`).
    case leg(Int)
    /// Las alternativas de una ruta (R29: solo al pedirlas).
    case alternatives(Int)

    var id: String {
        switch self {
        case .leg(let seq): "tramo-\(seq)"
        case .alternatives(let routeID): "alternativas-\(routeID)"
        }
    }
}

/// Lo que se empuja dentro del tablero.
enum BoardDestination: Hashable {
    /// El mapa entero de la ruta.
    case map(routeID: Int, title: String)
}

/// Identidad del zoom tablero → mapa (iOS 18, sistema.md §9.3).
enum BoardZoomID: Hashable {
    case map
}

/// El mapa de cabecera: quieto (sin gestos), sin etiquetas y fundido con el
/// fondo entre el 30 % y el 50 % de la pantalla (B). Decorado: para
/// VoiceOver lo dice el botón «Abrir el mapa de la ruta».
private struct BoardHeaderMap: View {
    let routeID: Int
    let height: CGFloat
    let zoom: Namespace.ID

    var body: some View {
        RouteMapView(routeID: routeID, style: .header)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                LinearGradient(stops: [
                    .init(color: Palette.bg.opacity(0), location: 0.62),
                    .init(color: Palette.bg, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .trajetZoomSource(id: BoardZoomID.map, in: zoom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(edges: .top)
    }
}

/// El mapa entero, empujado desde el tablero. El de la pestaña Trayecto
/// (con el modo trayecto y el camino a pie) está a un toque.
private struct BoardFullMap: View {
    let routeID: Int
    let title: String

    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    var body: some View {
        RouteMapView(routeID: routeID, style: .full)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigator?.show(.trip)
                    } label: {
                        Label("Trayecto", systemImage: "location")
                    }
                    .accessibilityHint("Abre la pestaña Trayecto")
                }
            }
    }
}

/// El pie del tablero: los errores de estación (hasta 3, R26) y la cuota con
/// el ritmo de refresco (R46, R7).
struct BoardFooter: View {
    let board: Board

    var body: some View {
        let errors = BoardText.stationErrors(board.errors)
        VStack(spacing: Metrics.Space.sm) {
            if !errors.shown.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                    ForEach(Array(errors.shown.enumerated()), id: \.offset) { _, error in
                        Label {
                            Text(error)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Palette.warnText)
                        }
                    }
                    if let more = BoardText.moreErrors(errors.hidden) {
                        Text(more)
                    }
                }
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            Text(BoardText.footer(board: board))
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.Space.xs)
    }
}

#if DEBUG
#Preview("Tablero: cinco tramos") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        BoardScreen()
    }
}

#Preview("Tablero: vía que aparece") {
    DemoServicesPreview("viaAparece", loadsBoard: false) {
        BoardScreen()
    }
}

#Preview("Tablero: sin conexión con caché") {
    DemoServicesPreview("sinConexion", loadsBoard: false) {
        BoardScreen()
    }
}

#Preview("Tablero: sin rutas") {
    DemoServicesPreview("vacio", loadsBoard: false) {
        BoardScreen()
    }
}

#Preview("Tablero: servidor sin clave") {
    DemoServicesPreview("sinClave", loadsBoard: false) {
        BoardScreen()
    }
}

#Preview("Pie del tablero") {
    VStack(spacing: Metrics.Space.l) {
        BoardFooter(board: PreviewData.board(.casosLimite))
        BoardFooter(board: PreviewData.board(.cuotaJusta))
    }
    .padding(Metrics.Space.gutter)
    .background(Palette.bg)
}
#endif
