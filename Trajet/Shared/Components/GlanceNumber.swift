import SwiftUI

/// Tallas de la cifra en cada pieza (sistema.md §12.3 y el laboratorio).
struct GlanceNumberStyle: Hashable, Sendable {
    /// Minutos sueltos («6»).
    var number: CGFloat
    /// «ya».
    var now: CGFloat
    /// «1h46».
    var long: CGFloat
    /// «En andén».
    var atStop: CGFloat
    /// Hora fija «12:56».
    var time: CGFloat
    /// «min».
    var unit: CGFloat
    /// «sale a las» encima de la hora fija (0 = sin rótulo).
    var label: CGFloat

    /// Billete de la Live Activity y primer tramo del widget grande (56 pt).
    static let ticketLarge = GlanceNumberStyle(number: 44, now: 38, long: 34, atStop: 22, time: 28, unit: 15, label: 11)
    /// Billete mediano (50 pt).
    static let ticketMedium = GlanceNumberStyle(number: 38, now: 32, long: 26, atStop: 19, time: 24, unit: 14, label: 10)
    /// Billete pequeño (42 pt): la hora va sin rótulo.
    static let ticketSmall = GlanceNumberStyle(number: 30, now: 26, long: 21, atStop: 16, time: 21, unit: 13, label: 0)
    /// Widget pequeño: la cifra manda (54 pt).
    static let widgetSmall = GlanceNumberStyle(number: 54, now: 46, long: 40, atStop: 21, time: 32, unit: 16, label: 11)
    /// Columna del widget mediano (50 pt).
    static let widgetMedium = GlanceNumberStyle(number: 50, now: 42, long: 36, atStop: 19, time: 30, unit: 16, label: 11)
    /// Isla expandida (38 pt, blanca sobre negro).
    static let expanded = GlanceNumberStyle(number: 38, now: 32, long: 30, atStop: 20, time: 24, unit: 14, label: 10)
    /// Isla compacta.
    static let compact = GlanceNumberStyle(number: 17, now: 17, long: 15, atStop: 10, time: 15, unit: 10, label: 0)
    /// Isla mínima.
    static let minimal = GlanceNumberStyle(number: 15, now: 13, long: 11, atStop: 9, time: 11, unit: 9, label: 0)
    /// «luego 21 min» del pie.
    static let next = GlanceNumberStyle(number: 19, now: 17, long: 16, atStop: 13, time: 16, unit: 12, label: 0)
    /// Filas del widget mediano.
    static let row = GlanceNumberStyle(number: 21, now: 19, long: 17, atStop: 14, time: 17, unit: 11, label: 0)
    /// Fichas del widget grande.
    static let chip = GlanceNumberStyle(number: 20, now: 18, long: 16, atStop: 13, time: 15, unit: 10.5, label: 0)
    /// Widget circular de la pantalla de bloqueo.
    static let circular = GlanceNumberStyle(number: 24, now: 20, long: 15, atStop: 12, time: 15, unit: 10, label: 0)
    /// Widget rectangular de la pantalla de bloqueo.
    static let rectangular = GlanceNumberStyle(number: 27, now: 24, long: 22, atStop: 17, time: 20, unit: 13, label: 10)

    func size(for moment: GlanceMoment) -> CGFloat {
        switch moment {
        case .minutes: number
        case .now: now
        case .long: long
        case .atStop: atStop
        case .time: time
        }
    }
}

/// La cifra: lo primero que se lee (R48). SF Pro Rounded heavy con dígitos
/// tabulares, «min» más pequeño al lado (dos tallas), «ya», «1h46» (R6),
/// «En andén» (R15) o la hora fija con «sale a las».
///
/// Cambia con `numericText(countsDown: true)` (fundido con «Reducir
/// movimiento» y nada en «siempre activa»).
struct GlanceNumber: View {
    let moment: GlanceMoment
    var style: GlanceNumberStyle = .ticketLarge
    var ink: Color = Palette.ink
    var ink2: Color = Palette.ink2
    /// «6′» en vez de «6 min» (isla compacta).
    var prime: Bool = false
    /// Sin «min» (cuando no cabe o ya lo dice otra cosa).
    var showsUnit: Bool = true
    /// «sale a las» encima de la hora fija.
    var showsTimeLabel: Bool = true
    /// Encoger hasta este factor antes que desbordar (1 = nunca).
    var minimumScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        switch moment {
        case .minutes(let m):
            HStack(alignment: .firstTextBaseline, spacing: style.unit * 0.2) {
                numberText(prime ? "\(m)′" : "\(m)", size: style.number)
                if showsUnit, !prime {
                    Text(verbatim: "min")
                        .font(GlanceFont.number(style.unit))
                        .foregroundStyle(ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        case .time(let t):
            if showsTimeLabel, style.label > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "sale a las")
                        .font(GlanceFont.word(style.label, .bold))
                        .foregroundStyle(ink2)
                        .lineLimit(1)
                        .fixedSize()
                    numberText(t, size: style.time)
                }
            } else {
                numberText(t, size: style.time)
            }
        case .now, .long, .atStop:
            numberText(moment.text, size: style.size(for: moment))
        }
    }

    private func numberText(_ text: String, size: CGFloat) -> some View {
        Text(verbatim: text)
            .font(GlanceFont.number(size))
            .tracking(-0.02 * size)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .contentTransition(transition)
    }

    private var transition: ContentTransition {
        if luminanceReduced { return .identity }
        return reduceMotion ? .opacity : .numericText(countsDown: true)
    }
}
