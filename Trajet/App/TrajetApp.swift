import SwiftUI

/// Trajet: la app del tablero. Crea los servicios (los de verdad o, con
/// `-demo`, los del servidor falso en proceso), los pasa por el entorno y
/// recibe los enlaces `trajet://` (QR del panel, widgets, Live Activity).
@main
struct TrajetApp: App {
    @State private var services: AppServices

    init() {
#if DEBUG
        if let escenario = DemoServer.scenarioName(arguments: ProcessInfo.processInfo.arguments) {
            _services = State(initialValue: AppServices.demo(escenario: escenario))
        } else {
            _services = State(initialValue: AppServices.live())
        }
#else
        _services = State(initialValue: AppServices.live())
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .onOpenURL { url in
                    Task { await services.handle(url: url) }
                }
        }
    }
}
