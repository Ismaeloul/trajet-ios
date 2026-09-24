import Foundation

// Lo que enseñan la Live Activity y los widgets («mirar de reojo», R1), en
// valores puros: sin vistas, para que se pueda probar. Las piezas SwiftUI
// (GlanceNumber, GlancePlatformMark, GlanceTicket) los pintan.
// Diseño: variante A «Billete» (docs/diseno/decisiones-la-widgets.md,
// docs/diseno/sistema.md §12).

/// Cómo se dice el momento de una salida en la cifra del billete.
///
/// «En andén» (confirmado por el tren) y «ya» (contador a cero) no se mezclan
/// nunca (R15). Con una hora o más, «1h46» (R6). La hora fija es lo que se
/// enseña cuando la cuenta atrás ya no es de fiar (Live Activity caducada,
/// widgets con ≥ 60 min o entradas espaciadas).
enum GlanceMoment: Hashable, Sendable {
    case minutes(Int)       // 1…59, con «min»
    case now                // «ya»
    case long(String)       // «1h46»
    case atStop             // «En andén»
    case time(String)       // «12:56», hora fija

    /// El momento de una salida a partir de sus minutos (ya descontado lo que
    /// ha pasado desde que llegó el tablero).
    static func from(minutes: Int, atStop: Bool) -> GlanceMoment {
        if atStop { return .atStop }
        if minutes <= 0 { return .now }
        if minutes >= 60 { return .long(Fmt.minutes(minutes)) }
        return .minutes(minutes)
    }

    /// El texto de la cifra, sin unidad.
    var text: String {
        switch self {
        case .minutes(let m): "\(m)"
        case .now: "ya"
        case .long(let s): s
        case .atStop: "En andén"
        case .time(let t): t
        }
    }

    /// «min» solo acompaña a los minutos sueltos.
    var unit: String? {
        if case .minutes = self { return "min" }
        return nil
    }

    var isTime: Bool {
        if case .time = self { return true }
        return false
    }

    /// Texto de una sola línea («6 min», «ya», «1h46», «en andén», «sale 14:36»),
    /// para el widget en línea y los rótulos compactos.
    var inline: String {
        switch self {
        case .minutes(let m): "\(m) min"
        case .now: "ya"
        case .long(let s): s
        case .atStop: "en andén"
        case .time(let t): "sale \(t)"
        }
    }

    /// Lo que oye VoiceOver (R50), con la concordancia bien («1 hora»).
    var spoken: String {
        switch self {
        case .minutes(let m):
            return m == 1 ? "en 1 minuto" : "en \(m) minutos"
        case .now:
            return "sale ya"
        case .long:
            return "en más de una hora"
        case .atStop:
            return "parado en el andén"
        case .time(let t):
            return "sale a las \(t)"
        }
    }

    /// VoiceOver con los minutos exactos cuando se saben (1 h 46 min).
    static func spokenLong(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let hours = h == 1 ? "1 hora" : "\(h) horas"
        if m == 0 { return "en \(hours)" }
        return m == 1 ? "en \(hours) y 1 minuto" : "en \(hours) y \(m) minutos"
    }
}

/// La vía de una salida: real o probable, que se distinguen por FORMA y
/// PALABRA, nunca por color (R10). Sin vía no hay valor (ni hueco, R2).
enum GlanceVia: Hashable, Sendable {
    /// Caja llena con «Vía». `isNew`: se acaba de publicar (R2);
    /// `before`: la vía que tenía antes el mismo tren (cambio de vía).
    case real(String, isNew: Bool, before: String?)
    /// Recuadro punteado con «probable» / «prob.»; `share` de 0 a 1.
    case probable(String, share: Double?)

    /// La vía que se enseña, si la hay. Metro, bus y tranvía no publican vía
    /// (`expected` = `platform_expected`, R3): nada, ni la probable.
    static func make(expected: Bool, platform: String?, guess: String?, share: Double?,
                     isNew: Bool = false, before: String? = nil) -> GlanceVia? {
        guard expected else { return nil }
        if let platform, !platform.isEmpty {
            let previous = (before?.isEmpty == false && before != platform) ? before : nil
            return .real(platform, isNew: isNew, before: previous)
        }
        if let guess, !guess.isEmpty {
            return .probable(guess, share: share)
        }
        return nil
    }

    var number: String {
        switch self {
        case .real(let n, _, _): n
        case .probable(let n, _): n
        }
    }

    var isReal: Bool {
        if case .real = self { return true }
        return false
    }

    var isNew: Bool {
        if case .real(_, let isNew, _) = self { return isNew }
        return false
    }

    /// La vía anterior si ha cambiado.
    var before: String? {
        if case .real(_, _, let before) = self { return before }
        return nil
    }

    /// «90 %», con espacio (R56).
    var sharePercent: String? {
        guard case .probable(_, let share) = self, let share else { return nil }
        return "\(Int((share * 100).rounded())) %"
    }

    /// Texto de una línea: «Vía 21» o «prob. 21» (nunca «vía 21 prob.», P2-13).
    var inline: String {
        isReal ? "Vía \(number)" : "prob. \(number)"
    }

    /// VoiceOver.
    var spoken: String {
        switch self {
        case .real(let n, let isNew, let before):
            if let before { return "vía \(n), cambio de vía, antes \(before)" }
            return isNew ? "acaba de salir la vía \(n)" : "vía \(n)"
        case .probable(let n, let share):
            guard let share else { return "vía \(n) probable" }
            return "vía \(n) probable, \(Int((share * 100).rounded())) por ciento"
        }
    }
}

/// Sin salida que enseñar: qué se dice en su lugar.
enum GlanceEmpty: Hashable, Sendable {
    /// Línea normal y sin más salidas (R25): «Servicio finalizado».
    case finished
    /// Línea interrumpida (nivel 2) y sin salidas: «Sin circulación».
    case cut
    /// Había salidas pero ya pasaron todas las de la foto: «Sin datos
    /// recientes · abre Trajet». Nunca «Servicio finalizado».
    case noRecentData

    var title: String {
        switch self {
        case .finished: "Servicio finalizado"
        case .cut: "Sin circulación"
        case .noRecentData: "Sin datos recientes"
        }
    }

    var subtitle: String {
        switch self {
        case .finished: "no hay más salidas"
        case .cut: "toca para ver alternativas"
        case .noRecentData: "abre Trajet para actualizar"
        }
    }

    /// Para el widget en línea y el de bloqueo.
    var lowercased: String {
        switch self {
        case .finished: "servicio finalizado"
        case .cut: "sin circulación"
        case .noRecentData: "sin datos recientes"
        }
    }

    var symbol: String {
        switch self {
        case .finished: "moon.zzz.fill"
        case .cut: "xmark.octagon.fill"
        case .noRecentData: "clock"
        }
    }
}

/// Horas de París («HH:MM»), que es como las da la API.
enum GlanceClock {
    static func hhmm(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Texto secundario de una salida, con la prioridad con la que se queda
/// cuando no cabe todo (sistema.md §12.5): cambio de vía 7 > retraso 5 >
/// hora 4 > longitud 3 > tramo 2. Lo que no cabe se cae ENTERO.
enum GlanceMeta: Hashable, Sendable {
    case platformChange(before: String)
    case time(String)
    case delay(Int)
    case length(TrainLength)
    case leg(String)

    var priority: Int {
        switch self {
        case .platformChange: 7
        case .delay: 5
        case .time: 4
        case .length: 3
        case .leg: 2
        }
    }

    /// Primera línea: cambio de vía, hora y retraso. Segunda: longitud y tramo.
    var isFirstLine: Bool {
        switch self {
        case .platformChange, .time, .delay: true
        case .length, .leg: false
        }
    }

    /// Texto completo.
    var text: String {
        switch self {
        case .platformChange(let before): "cambio de vía · antes \(before)"
        case .time(let t): "sale \(t)"
        case .delay(let d): Fmt.delay(d)
        case .length(let l): l == .long ? "tren largo" : "tren corto"
        case .leg(let t): t
        }
    }

    /// Texto corto, si lo tiene («antes vía 21»).
    var shortText: String? {
        if case .platformChange(let before) = self { return "antes vía \(before)" }
        return nil
    }

    /// Las líneas secundarias que caben, de la más completa a la más pobre:
    /// cae primero el tramo, luego la longitud y la hora; con cambio de vía,
    /// después se acorta a «antes vía 21»; al final no queda nada.
    static func ladder(_ items: [GlanceMeta]) -> [[GlanceMetaPiece]] {
        var current = items.sorted { $0.order < $1.order }.map { GlanceMetaPiece(meta: $0, short: false) }
        var steps: [[GlanceMetaPiece]] = [current]
        // Se quitan de menor a mayor prioridad, menos el cambio de vía y el
        // retraso, que se quedan hasta el final.
        for victim in items.filter({ $0.priority < 5 }).sorted(by: { $0.priority < $1.priority }) {
            current.removeAll { $0.meta == victim }
            steps.append(current)
        }
        if current.contains(where: { $0.meta.shortText != nil && !$0.short }) {
            current = current.map { GlanceMetaPiece(meta: $0.meta, short: $0.meta.shortText != nil) }
            steps.append(current)
        }
        // Después el retraso, y el cambio de vía el último.
        for victim in current.map(\.meta).sorted(by: { $0.priority < $1.priority }) {
            current.removeAll { $0.meta == victim }
            steps.append(current)
        }
        var unique: [[GlanceMetaPiece]] = []
        for step in steps where !unique.contains(step) { unique.append(step) }
        return unique
    }

    /// Orden de pintado dentro de cada línea (el del laboratorio).
    fileprivate var order: Int {
        switch self {
        case .platformChange: 0
        case .time: 1
        case .delay: 2
        case .length: 3
        case .leg: 4
        }
    }
}

/// Un trozo de texto secundario ya decidido (completo o corto).
struct GlanceMetaPiece: Hashable, Sendable {
    let meta: GlanceMeta
    let short: Bool

    var text: String { short ? (meta.shortText ?? meta.text) : meta.text }
}

/// Un escalón de la cabecera (Live Activity y widgets): qué variante del
/// destino, si va la palabra del estado de la línea y cuánto prefijo lleva la
/// antigüedad. Se prueban de arriba abajo con `ViewThatFits`.
///
/// Orden de caída (el `fitRows` del laboratorio): primero cae la palabra
/// «perturbada» (queda ⚠), luego el destino se abrevia, luego se acorta el
/// prefijo de la antigüedad («servidor sin clave ·» → «sin clave ·») y lo
/// último, el destino entero. La antigüedad no cae nunca (R17).
struct GlanceHeaderStep: Hashable, Sendable {
    let destination: String?
    let statusWord: Bool
    let agePrefix: Int

    static func ladder(destinations: [String], hasStatusWord: Bool, agePrefixCount: Int) -> [GlanceHeaderStep] {
        let prefixes = max(1, agePrefixCount)
        var steps: [GlanceHeaderStep] = []
        let first = destinations.first
        steps.append(GlanceHeaderStep(destination: first, statusWord: hasStatusWord, agePrefix: 0))
        steps.append(GlanceHeaderStep(destination: first, statusWord: false, agePrefix: 0))
        for d in destinations.dropFirst() {
            steps.append(GlanceHeaderStep(destination: d, statusWord: false, agePrefix: 0))
        }
        let shortest = destinations.last
        if prefixes > 1 {
            for p in 1..<prefixes {
                steps.append(GlanceHeaderStep(destination: shortest, statusWord: false, agePrefix: p))
            }
        }
        steps.append(GlanceHeaderStep(destination: nil, statusWord: false, agePrefix: prefixes - 1))
        var unique: [GlanceHeaderStep] = []
        for step in steps where !unique.contains(step) { unique.append(step) }
        return unique
    }
}
