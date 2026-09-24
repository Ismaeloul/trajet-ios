import SwiftUI

/// La raíz: sin emparejar, el flujo de emparejamiento; emparejado, las
/// pestañas. También avisa al tablero de si la app está activa: el bucle de
/// refresco solo corre con la app delante (R7).
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if services.pairing.isPaired {
                MainTabView()
            } else {
                PairingFlowView()
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .onChange(of: scenePhase, initial: true) { _, phase in
            services.board.setSceneActive(phase == .active)
        }
    }
}
