#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// La Live Activity del modo trayecto, EXACTAMENTE según
/// docs/diseno/sistema.md §12.4: solo campos de /api/v1/board (`BoardV1`,
/// `BoardLegV1`, `Departure`, `PlatformGuess`, `LineStatus`, `ServerState`) y
/// lo que la app deriva de ellos sin inventar (marcado «derivado»).
/// ≈ 1,3 KB con 3 salidas; el tope de iOS es 4 KB.
///
/// Ojo con los nombres: dentro de este tipo, `Leg`, `Dep` y `Link` son los de
/// la actividad (los del tablero son `Leg` de fuera; desde una extensión de
/// este tipo, usa el alias `BoardLeg`).
struct TrajetActivityAttributes: ActivityAttributes, Hashable, Sendable {
    // Fijo durante todo el trayecto
    var routeID: Int                  // BoardRoute.id → widgetURL
    var routeName: String             // BoardRoute.name (estado final)

    struct ContentState: Codable, Hashable, Sendable {
        var leg: Leg                  // el tramo que toca (lo decide la app: hora y geocercas)
        var next: Link?               // el tramo siguiente, si hay transbordo
        var legIndex: Int             // posición de `leg` en BoardV1.legs (derivado)
        var legCount: Int             // BoardV1.legs.count (derivado)
        var receivedAt: Date          // llegada del tablero al teléfono (R17, derivado)
        var dataAge: Double           // BoardV1.data_age
        var refreshHint: Int          // BoardV1.server.refresh_hint_s
        var connection: Connection    // .ok · .offline (fallo de red) · .noKey (ErrorV1 prim_key_missing) — derivado
        var ended: EndReason?         // .arrived · .maxDuration (solo en el estado final; derivado del modo trayecto)
    }

    struct Leg: Codable, Hashable, Sendable {
        var seq: Int                  // BoardLegV1.seq
        var lineCode: String          // line_code
        var lineColor: String         // line_color (hex)
        var platformExpected: Bool    // platform_expected (R3)
        var toName: String            // to_name («Transbordo en …»)
        var direction: [String]       // abreviar(directions[0] o destination): variantes (derivado)
        var mixed: Bool               // directions vacío y destinos distintos (R24, derivado)
        var statusLevel: Int          // status.level
        var departures: [Dep]         // ≤ 3, en orden
    }

    struct Dep: Codable, Hashable, Sendable {
        var jid: String               // Departure.jid (identidad, R23)
        var at: Date                  // Departure.at «HH:MM» en Europe/Paris → fecha (derivado)
        var minutes: Int              // Departure.minutes (control del redondeo)
        var destination: [String]     // abreviar(Departure.destination) (derivado)
        var platform: String?         // Departure.platform
        var platformNew: Bool         // Departure.platform_new
        var platformBefore: String?   // vía de la misma jid en el tablero anterior: cambio de vía (derivado)
        var guessPlatform: String?    // Departure.guess.platform
        var guessShare: Double?       // Departure.guess.share
        var delay: Int?               // Departure.delay, solo si aimed_at ≠ "" (R4, R14)
        var atStop: Bool              // Departure.at_stop (R15)
        var length: String?           // Departure.length (R5)
        var cancelled: Bool           // Departure.status == "cancelled" (derivado)
    }

    struct Link: Codable, Hashable, Sendable {  // el tramo siguiente
        var lineCode: String
        var lineColor: String
        var statusLevel: Int
        var first: Dep?               // su primera salida (hora y vía del enlace)
    }

    /// Cómo está la conexión con el servidor (derivado).
    enum Connection: String, Codable, Hashable, Sendable {
        case ok
        case offline                  // fallo de red
        case noKey                    // ErrorV1 prim_key_missing
    }

    /// Por qué terminó el trayecto (solo en el estado final; «Parar» a mano
    /// quita la actividad al momento y no deja estado final).
    enum EndReason: String, Codable, Hashable, Sendable {
        case arrived
        case maxDuration
    }
}
#endif

/// El `Leg` del tablero con otro nombre, para poder nombrarlo desde dentro de
/// `TrajetActivityAttributes` (donde `Leg` es el de la actividad).
typealias BoardLeg = Leg
