import SwiftUI

/// «Empezar trayecto» en el tablero y, si ya hay uno en marcha, su estado y
/// «Parar». El modo trayecto (TripController, del mapa) mantiene vivo el
/// refresco en segundo plano (R7), sigue la Live Activity y se apaga al
/// llegar o al pasar el tope.
struct BoardTripControls: View {
    let routeID: Int

    @Environment(AppServices.self) private var services
    @State private var started = HapticTrigger()
    @State private var stopped = HapticTrigger()

    private var isAskingPermission: Bool {
        if case .askingPermission = services.trip.state { return true }
        return false
    }

    var body: some View {
        let trip = services.trip
        VStack(spacing: Metrics.Space.sm) {
            if trip.isActive {
                activeNote(sameRoute: trip.activeRouteID == nil || trip.activeRouteID == routeID)
                Button {
                    stop()
                } label: {
                    Label("Parar trayecto", systemImage: "stop.fill")
                }
                .filledButton(.danger)
                .accessibilityIdentifier("tablero.parar")
            } else if isAskingPermission {
                Button {} label: {
                    HStack(spacing: Metrics.Space.sm) {
                        ProgressView()
                            .tint(Palette.onAccent)
                        Text("Pidiendo permiso de ubicación…")
                    }
                }
                .filledButton(.primary)
                .disabled(true)
            } else {
                Button {
                    start()
                } label: {
                    Label("Empezar trayecto", systemImage: "play.fill")
                }
                .filledButton(.primary)
                .accessibilityHint("Sigue la ruta en segundo plano hasta que llegues")
                .accessibilityIdentifier("tablero.empezar")
            }
        }
        .haptic(.tripStart, trigger: started)
        .haptic(.tripStop, trigger: stopped)
    }

    private func activeNote(sameRoute: Bool) -> some View {
        let title: String = sameRoute ? "Trayecto en marcha" : "Trayecto en marcha en otra ruta"
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.sm) {
            Image(systemName: "location.fill")
                .foregroundStyle(Palette.okText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(title)
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                Text("sigue en segundo plano · se apaga al llegar")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private func start() {
        started.fire()
        let trip = services.trip
        let id = routeID
        Task { await trip.start(routeID: id) }
    }

    private func stop() {
        stopped.fire()
        let trip = services.trip
        Task { await trip.stop(reason: .manual) }
    }

    /// Lo que se dice (aviso efímero) cuando el trayecto termina solo. Parar a
    /// mano no necesita aviso: ya se ve.
    static func endedText(_ reason: TripEndReason) -> String? {
        switch reason {
        case .arrived: "Has llegado: trayecto terminado"
        case .timeLimit: "Trayecto parado: se ha pasado el tiempo máximo"
        case .manual: nil
        case .permissionDenied: "Sin permiso de ubicación: el trayecto no puede seguir"
        case .failed(let detail): detail.isEmpty ? "El trayecto se ha parado" : "El trayecto se ha parado: \(detail)"
        }
    }
}

#if DEBUG
#Preview("Empezar y parar trayecto") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        BoardTripControls(routeID: 3)
            .padding(Metrics.Space.gutter)
            .frame(maxHeight: .infinity)
            .background(Palette.bg)
    }
}
#endif
