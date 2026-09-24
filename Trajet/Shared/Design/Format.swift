import SwiftUI

/// Cómo se dice cada cosa. Casi todas estas reglas salen de un dato medido
/// contra la API real, no de una preferencia.
enum Fmt {

    /// Los minutos, que son lo primero que se lee.
    ///
    /// Se miden buses a 106 y a 165 minutos, así que a partir de una hora hay
    /// que decirlo en horas o el número se sale de la tira.
    static func minutes(_ m: Int) -> String {
        if m >= 60 {
            let h = m / 60
            let rest = m % 60
            return rest == 0 ? "\(h)h" : String(format: "%dh%02d", h, rest)
        }
        return "\(max(0, m))"
    }

    /// La unidad que acompaña al número, o nada si ya lleva la hora dentro.
    static func minutesUnit(_ m: Int) -> String? {
        m >= 60 ? nil : "min"
    }

    /// Retraso con signo. Un +0 no se enseña nunca.
    static func delay(_ minutes: Int) -> String {
        minutes > 0 ? "+\(minutes) min" : "\(minutes) min"
    }

    /// Antigüedad del dato, redondeada como se dice en voz alta.
    static func age(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "hace \(max(0, s)) s" }
        let m = s / 60
        if m < 60 { return "hace \(m) min" }
        let h = m / 60
        return "hace \(h) h"
    }

    /// Cuota que queda hoy en el endpoint del tablero.
    static func quota(_ remaining: Int) -> String {
        "\(remaining) llamadas hoy"
    }
}

/// El ritmo al que hay que ir, según los minutos que quedan.
///
/// Es la respuesta a la única pregunta que se hace de pie en un vestíbulo:
/// ¿corro o no corro?
enum Pace {
    case run        // <= 3 min
    case walk       // <= 8 min
    case easy       // > 8 min

    init(minutes: Int) {
        if minutes <= 3 { self = .run }
        else if minutes <= 8 { self = .walk }
        else { self = .easy }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .easy: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .run: Palette.badText   // el relleno rojo no pasa AA como texto
        case .walk: Palette.ink2
        case .easy: Palette.ink3
        }
    }

    var spoken: String {
        switch self {
        case .run: "corriendo"
        case .walk: "andando"
        case .easy: "con calma"
        }
    }
}

/// Cómo se dice el momento de una salida.
///
/// «En andén» y «ya» son cosas distintas y no se pueden mezclar: la primera
/// está confirmada por el tren (`at_stop`), la segunda solo quiere decir que
/// el contador ha llegado a cero.
enum DepartureMoment {
    case atStop
    case now
    case inMinutes(Int)

    init(_ departure: Departure) {
        if departure.atStop { self = .atStop }
        else if departure.minutes <= 0 { self = .now }
        else { self = .inMinutes(departure.minutes) }
    }

    var text: String {
        switch self {
        case .atStop: "En andén"
        case .now: "ya"
        case .inMinutes(let m): Fmt.minutes(m)
        }
    }

    var unit: String? {
        if case .inMinutes(let m) = self { return Fmt.minutesUnit(m) }
        return nil
    }

    /// «En andén» y «ya» son palabras, no cifras: piden un cuerpo menor para
    /// que quepan sin empujar al resto de la tira.
    var isWord: Bool {
        switch self {
        case .atStop, .now: true
        case .inMinutes: false
        }
    }

    var pace: Pace? {
        switch self {
        case .atStop: nil
        case .now: .run
        case .inMinutes(let m): Pace(minutes: m)
        }
    }

    /// Lo que oye VoiceOver.
    var spoken: String {
        switch self {
        case .atStop: "parado en el andén"
        case .now: "sale ya"
        case .inMinutes(let m):
            m >= 60 ? "en \(m / 60) horas y \(m % 60) minutos" : "en \(m) minutos"
        }
    }
}
