import AppIntents
import Foundation

/// Quién para el trayecto cuando se toca «Parar» en la Live Activity.
///
/// El modo trayecto (TripController, en la app) registra aquí su manejador al
/// arrancar: `TripStopHandler.stop = { await controller.stop(reason: .manual) }`.
/// Así este fichero, que también compila la extensión, no depende de nada de
/// la app.
@MainActor
enum TripStopHandler {
    static var stop: (@MainActor () async -> Void)?

    static func run() async {
        await stop?()
    }
}

/// «Parar» de la Live Activity (iOS 17+). Se ejecuta en el proceso de la app;
/// en la extensión no hace nada (allí no hay modo trayecto que parar).
struct StopTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Parar trayecto"

    init() {}

    func perform() async throws -> some IntentResult {
#if TRAJET_WIDGETS
        return .result()
#else
        await TripStopHandler.run()
        return .result()
#endif
    }
}
