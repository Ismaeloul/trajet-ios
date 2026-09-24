import SwiftUI

/// Las pestañas de la app (docs/diseno/sistema.md §7.11), con la barra del
/// sistema: en iOS 26 flota en cristal sola; las etiquetas se ven siempre.
///
/// - Tablero, Trayecto (mapa y modo trayecto), Rutas (con el planificador
///   dentro) e Historial.
/// - Ajustes es una hoja que se abre desde la cabecera del tablero o con un
///   enlace `trajet://ajustes`. `SettingsScreen` trae su propio
///   `NavigationStack` y su «Cerrar».
/// - Atiende los enlaces `trajet://` que deja `AppServices.pendingLink`
///   (widgets, Live Activity): la ruta en el Tablero, la hoja de alternativas,
///   Ajustes.
/// - El bucle de 30 s del tablero solo corre con Tablero o Trayecto delante
///   (R7); en Rutas e Historial se para (el modo trayecto lo mantiene vivo por
///   su cuenta).
/// - Pone en el entorno la navegación (`AppNavigator`) y los avisos efímeros
///   (`ToastCenter`, R55) y los pinta encima de la barra de pestañas.
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @State private var navigator = AppNavigator()

    var body: some View {
        TabView(selection: $navigator.tab) {
            BoardScreen()
                .tabItem { tabLabel(.board) }
                .tag(AppTab.board)
            MapScreen()
                .tabItem { tabLabel(.trip) }
                .tag(AppTab.trip)
            RoutesScreen()
                .tabItem { tabLabel(.routes) }
                .tag(AppTab.routes)
            StatsScreen()
                .tabItem { tabLabel(.history) }
                .tag(AppTab.history)
        }
        .haptic(.selection, trigger: navigator.tab)
        .sheet(isPresented: $navigator.showingSettings) {
            SettingsScreen()
                .environment(services)
                .environment(navigator)
                .environment(navigator.toasts)
        }
        .toastHost(navigator.toasts)
        .environment(navigator)
        .environment(navigator.toasts)
        .onAppear {
            consumePendingLink()
        }
        .onChange(of: services.pendingLink) { _, link in
            if link != nil {
                consumePendingLink()
            }
        }
        .onChange(of: navigator.tab) { _, tab in
            services.board.setVisible(tab.refreshesBoard)
        }
        .onChange(of: services.trip.state) { _, state in
            tripStateChanged(state)
        }
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.symbol)
    }

    /// Recoge el enlace pendiente (y lo borra) y abre lo que pide.
    private func consumePendingLink() {
        guard let link = services.consumePendingLink() else { return }
        navigator.open(link)
    }

    /// Cuando el trayecto termina solo (al llegar, por tiempo, sin permiso o
    /// por un fallo) se dice con un aviso efímero; parar a mano ya se ve.
    private func tripStateChanged(_ state: TripState) {
        guard case .ended(let reason) = state,
              let text = BoardTripControls.endedText(reason)
        else { return }
        navigator.toasts.show(text, symbol: reason == .arrived ? "checkmark.circle" : "stop.circle")
    }
}

#if DEBUG
#Preview("Pestañas (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        MainTabView()
    }
}
#endif
