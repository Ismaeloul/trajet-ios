import SwiftUI

/// Las rutas guardadas (F26–F32, sistema.md §7.15).
///
/// - La lista es la MISMA que usa el selector del tablero: una sola copia y
///   una sola carga (`RoutesStore`, R41). Se carga al entrar si no hay nada y
///   al tirar para recargar.
/// - La que toca ahora la marca el servidor (`active_id`, R37); cada tarjeta
///   dice el horario tal como se definió (R35) y los días en español (R36).
/// - Tocar una ruta la abre en el editor (zoom de iOS 18). Pulsación larga:
///   «Ver en el tablero», «Editar» y «Borrar». Borrar pide confirmación.
/// - «Ordenar» cambia el orden (`position`): el servidor ordena así y lo usa
///   para desempatar la que toca.
/// - «+»: buscar un trayecto (el planificador) o montarla a mano.
/// - Tras crear, editar o borrar, el tablero se refresca solo (R39,
///   `RoutesStore.onChange`). Los avisos son efímeros (R55).
struct RoutesScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    @Namespace private var zoom
    @State private var path: [RoutesDestination] = []
    @State private var sheet: RoutesSheet?
    @State private var pendingDelete: SavedRoute?
    @State private var confirmingDelete = false
    @State private var editMode: EditMode = .inactive
    /// El orden nuevo mientras se guarda (para no ver saltos).
    @State private var localOrder: [Int]?
    @State private var isSavingOrder = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Palette.bg.ignoresSafeArea())
                .navigationTitle("Rutas")
                .toolbar { routesToolbar }
                .navigationDestination(for: RoutesDestination.self) { destination in
                    switch destination {
                    case .edit(let route):
                        RouteEditorView(route: route)
                            .trajetZoomTransition(sourceID: route.id, in: zoom)
                    }
                }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible,
                            presenting: pendingDelete) { route in
            Button("Borrar ruta", role: .destructive) {
                delete(route)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se borra también su historial. Los andenes aprendidos se quedan.")
        }
        .task {
            await services.routes.loadIfNeeded()
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        let store = services.routes
        if store.routes.isEmpty {
            ScrollView {
                Group {
                    if !store.hasLoaded, let error = store.lastError {
                        // R53: un error no se confunde con «no hay rutas» (rareza F27).
                        MessageStateView(symbol: error.isNetwork ? "wifi.slash" : "exclamationmark.triangle",
                                         tint: Palette.badText,
                                         title: "No se han podido cargar las rutas",
                                         message: error.errorDescription) {
                            Button {
                                Task { await services.routes.load() }
                            } label: {
                                Label("Reintentar", systemImage: "arrow.clockwise")
                            }
                            .filledButton(.primary)
                        }
                    } else if !store.hasLoaded {
                        loadingView
                    } else {
                        emptyView
                    }
                }
                .padding(.horizontal, Metrics.Space.gutter)
                .padding(.vertical, Metrics.Space.l)
            }
            .refreshable { await services.routes.load() }
        } else {
            list
        }
    }

    private var loadingView: some View {
        VStack(spacing: Metrics.Space.ml) {
            ProgressView()
            Text("Cargando las rutas…")
                .textLevel(.callout)
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.Space.xxl)
        .accessibilityElement(children: .combine)
    }

    /// Vacío que dice qué hacer (R53, F28).
    private var emptyView: some View {
        MessageStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                         title: "Aún no hay ninguna ruta",
                         message: "Empieza por «Buscar un trayecto»: di de dónde a dónde vas y guarda el que uses de verdad. Si ya sabes el camino exacto, móntala a mano.") {
            Button {
                sheet = .planner
            } label: {
                Label("Buscar un trayecto", systemImage: "magnifyingglass")
            }
            .filledButton(.primary)
            Button {
                sheet = .newRoute
            } label: {
                Label("Montar a mano", systemImage: "hand.point.up.left")
                    .frame(maxWidth: .infinity)
            }
            .cristalButton()
            .controlSize(.large)
        }
    }

    private var list: some View {
        let store = services.routes
        let routes = displayedRoutes
        return List {
            if let error = store.lastError {
                Label(error.errorDescription ?? "No se han podido actualizar las rutas.",
                      systemImage: "exclamationmark.triangle")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.warnText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(routes) { route in
                    row(route, isActive: route.id == store.activeID)
                }
                .onMove { source, destination in
                    move(from: source, to: destination)
                }
                .moveDisabled(isSavingOrder)
            } header: {
                Text("Se elige sola según el día y la hora")
                    .textLevel(.kicker)
                    .foregroundStyle(Palette.ink3)
                    .textCase(nil)
            }
            Section {
                Button {
                    sheet = .planner
                } label: {
                    Label("Buscar un trayecto", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .cristalButton()
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Metrics.Space.sm, leading: Metrics.Space.gutter,
                                          bottom: Metrics.Space.xl, trailing: Metrics.Space.gutter))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .refreshable { await services.routes.load() }
    }

    private func row(_ route: SavedRoute, isActive: Bool) -> some View {
        Button {
            path.append(.edit(route))
        } label: {
            RouteCard(route: route, isActive: isActive)
        }
        .buttonStyle(.plain)
        .disabled(editMode.isEditing)
        .trajetZoomSource(id: route.id, in: zoom)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: Metrics.Space.s, leading: Metrics.Space.gutter,
                                  bottom: Metrics.Space.s, trailing: Metrics.Space.gutter))
        .contextMenu {
            Button {
                showOnBoard(route)
            } label: {
                Label("Ver en el tablero", systemImage: "clock")
            }
            Button {
                path.append(.edit(route))
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                askDelete(route)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                showOnBoard(route)
            } label: {
                Label("Ver en el tablero", systemImage: "clock")
            }
            .tint(Palette.accentFill)
        }
        .swipeActions(edge: .trailing) {
            // Sin `role: .destructive`: la fila no se va hasta confirmar.
            Button {
                askDelete(route)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
            .tint(Palette.bad)
        }
        .accessibilityHint("Toca para editarla")
        .accessibilityAction(named: "Ver en el tablero") { showOnBoard(route) }
        .accessibilityAction(named: "Borrar") { askDelete(route) }
        .accessibilityAction(named: "Subir") { moveByOne(route, up: true) }
        .accessibilityAction(named: "Bajar") { moveByOne(route, up: false) }
    }

    // MARK: - Barra

    /// TODO-COMPILAR: `if` dentro de `@ToolbarContentBuilder` (iOS 16+). Si
    /// no casa, dejar siempre el botón «Ordenar» y desactivarlo con una sola
    /// ruta.
    @ToolbarContentBuilder
    private var routesToolbar: some ToolbarContent {
        if services.routes.routes.count > 1 {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Hecho" : "Ordenar") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .disabled(isSavingOrder)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Buscar va de una dirección a otra. A mano es para cuando ya sabes el camino exacto.") {
                    Button {
                        sheet = .planner
                    } label: {
                        Label("Buscar un trayecto", systemImage: "magnifyingglass")
                    }
                    Button {
                        sheet = .newRoute
                    } label: {
                        Label("Montar a mano", systemImage: "hand.point.up.left")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .hitTarget()
            }
            .accessibilityLabel("Nueva ruta")
        }
    }

    // MARK: - Hojas

    @ViewBuilder
    private func sheetContent(_ item: RoutesSheet) -> some View {
        switch item {
        case .planner:
            PlannerScreen()
                .environment(services)
                .environment(navigator)
                .environment(toasts)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .newRoute:
            NavigationStack {
                RouteEditorView(route: nil)
            }
            .environment(services)
            .environment(navigator)
            .environment(toasts)
            .presentationDetents([.large])
        }
    }

    // MARK: - Acciones

    private var deleteTitle: String {
        guard let route = pendingDelete else { return "Borrar la ruta" }
        return "¿Borrar «\(route.name)»?"
    }

    private func askDelete(_ route: SavedRoute) {
        pendingDelete = route
        confirmingDelete = true
    }

    /// Fija la ruta en el tablero (se refresca ya, R39) y lo enseña.
    private func showOnBoard(_ route: SavedRoute) {
        services.board.selectRoute(route.id)
        navigator?.show(.board)
    }

    private func delete(_ route: SavedRoute) {
        pendingDelete = nil
        let store = services.routes
        let toasts = self.toasts
        Task {
            do {
                try await store.delete(id: route.id)
                toasts?.show("Ruta borrada", symbol: "trash")
            } catch {
                toasts?.show("No se ha podido borrar", symbol: "exclamationmark.triangle")
            }
        }
    }

    /// Las rutas en el orden en que se ven (el nuevo, mientras se guarda).
    private var displayedRoutes: [SavedRoute] {
        let routes = services.routes.routes
        guard let order = localOrder else { return routes }
        let ordered = order.compactMap { id in routes.first { $0.id == id } }
        return ordered + routes.filter { !order.contains($0.id) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let ids = displayedRoutes.map(\.id)
        saveOrder(RouteOrdering.move(ids, from: source, to: destination))
    }

    /// «Subir» / «Bajar» con VoiceOver (arrastrar no es cómodo).
    private func moveByOne(_ route: SavedRoute, up: Bool) {
        let ids = displayedRoutes.map(\.id)
        guard let current = ids.firstIndex(of: route.id) else { return }
        let target = up ? current - 1 : current + 2
        guard target >= 0, target <= ids.count, !isSavingOrder else { return }
        saveOrder(RouteOrdering.move(ids, from: IndexSet(integer: current), to: target))
    }

    /// Guarda el orden nuevo: `PUT` de las rutas cuya `position` cambia,
    /// una recarga y un refresco del tablero (la que toca puede cambiar).
    private func saveOrder(_ order: [Int]) {
        let store = services.routes
        let updates = RouteOrdering.updates(routes: store.routes, order: order)
        guard !updates.isEmpty, !isSavingOrder else { return }
        localOrder = order
        isSavingOrder = true
        let api = services.api
        let board = services.board
        let toasts = self.toasts
        Task {
            var failed = false
            for update in updates {
                guard let route = store.route(id: update.id), !route.legs.isEmpty else { continue }
                var draft = RouteDraft(route)
                draft.position = update.position
                do {
                    _ = try await api.updateRoute(id: update.id, draft)
                } catch {
                    failed = true
                    break
                }
            }
            await store.load()
            localOrder = nil
            isSavingOrder = false
            if let first = updates.first {
                board.routesChanged(.updated(first.id))
            }
            if failed {
                toasts?.show("No se ha podido guardar el orden", symbol: "exclamationmark.triangle")
            }
        }
    }
}

/// Lo que se empuja en la pila de Rutas.
enum RoutesDestination: Hashable {
    case edit(SavedRoute)
}

/// Las hojas de Rutas.
enum RoutesSheet: String, Identifiable, Hashable {
    case planner
    case newRoute

    var id: String { rawValue }
}

#if DEBUG
#Preview("Rutas (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        RoutesScreen()
    }
}

#Preview("Rutas: vacío") {
    DemoServicesPreview("vacio", loadsBoard: false) {
        RoutesScreen()
    }
}
#endif
