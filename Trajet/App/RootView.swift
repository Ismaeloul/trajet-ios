import SwiftUI

/// La raíz: sin emparejar, el flujo de emparejamiento; emparejado, las
/// pestañas. También avisa al tablero de si la app está activa: el bucle de
/// refresco solo corre con la app delante (R7).
///
/// Al emparejarse no salta a las pestañas en el acto: deja ver un momento el
/// «Listo» del emparejamiento y luego funde. Al abrir la app o al
/// desemparejar, lo que toca va sin esperas.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Las pestañas están a la vista. nil hasta la primera vez (entonces
    /// manda `pairing.isPaired`).
    @State private var showsTabs: Bool?

    /// Lo que se queda a la vista el «Listo» antes de pasar a las pestañas.
    static let pairedHold: Double = 1.2

    var body: some View {
        let paired = services.pairing.isPaired
        Group {
            if showsTabs ?? paired {
                MainTabView()
                    .transition(.opacity)
            } else {
                PairingFlowView()
                    .transition(.opacity)
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .task(id: paired) {
            await pairingChanged(paired)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            services.board.setSceneActive(phase == .active)
        }
    }

    private func pairingChanged(_ paired: Bool) async {
        // La primera vez (al abrir la app), lo que toca y ya.
        guard let shown = showsTabs else {
            showsTabs = paired
            return
        }
        guard paired != shown else { return }
        guard paired else {
            // Desemparejado (Ajustes o un 401): al emparejamiento ya.
            showsTabs = false
            return
        }
        try? await Task.sleep(for: .seconds(Self.pairedHold))
        // Se deshizo mientras tanto: `task(id:)` ya ha cancelado esta espera.
        guard !Task.isCancelled else { return }
        withMotion(.ease, reduceMotion: reduceMotion) {
            showsTabs = true
        }
    }
}
