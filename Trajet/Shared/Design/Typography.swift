import SwiftUI

// Tipografía del sistema «Cristal».
//
// - El texto es SF Pro con los estilos de Dynamic Type: nada de tamaños fijos
//   (la v1 no tenía Dynamic Type; ver R1 en docs/reglas.md).
// - Las cifras (minutos, vía, estadísticas, distintivo) son SF Pro Rounded
//   heavy con dígitos tabulares, para que no bailen al pasar de 9 a 10 (R48).
//   Escalan con Dynamic Type mediante `@ScaledMetric` y tienen un TOPE: si no,
//   con los tamaños de accesibilidad los minutos rompen el billete.
// - Correspondencia con el laboratorio y tamaños en docs/diseno/sistema.md §4.

/// Nivel de texto. Cada uno es un estilo de Dynamic Type con su peso.
enum TextLevel: Sendable, CaseIterable {
    /// Título grande de pantalla (Rutas, Historial). Lo pone la barra nativa.
    case screenTitle
    /// Título de barra de navegación y de hoja.
    case navTitle
    /// Nombre de la ruta en la cabecera de cristal del tablero.
    case routeTitle
    /// «Gare Saint-Lazare → Argenteuil» en la tarjeta del tramo.
    case legTitle
    /// «dirección Ermont - Eaubonne».
    case legSubtitle
    /// Rótulo de sección («La que toca ahora», «Cuota PRIM»).
    case kicker
    /// Texto de lista y de párrafo.
    case body
    /// Valor editable de un campo.
    case bodyStrong
    /// Texto del aviso, subtítulo de tarjeta de ruta.
    case callout
    /// Hora «12:56», longitud, retraso dentro del billete.
    case meta
    /// «en directo · hace 10 s».
    case status
    /// «Perturbada», «Interrumpida».
    case noticeTitle
    /// Destino en el billete: lo segundo que se lee.
    case destination
    /// «min» junto a la cifra.
    case unit
    /// Hora y datos de las fichas 2.ª–4.ª.
    case chipCaption
    /// Etiquetas pequeñas: ritmo, «ahora», «Vía», «probable».
    case label
    /// Botón normal.
    case button
    /// Botón pequeño («Guardar ruta», «Cambiar»).
    case buttonSmall
    /// Pie del tablero, notas.
    case footnote

    var style: Font.TextStyle {
        switch self {
        case .screenTitle: .largeTitle
        case .navTitle, .legTitle, .destination: .headline
        case .routeTitle: .title3
        case .legSubtitle, .meta, .status, .noticeTitle, .unit: .footnote
        case .kicker, .chipCaption, .footnote: .caption
        case .body, .bodyStrong, .button: .body
        case .callout, .buttonSmall: .subheadline
        case .label: .caption2
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenTitle, .legTitle, .noticeTitle, .destination, .unit, .label: .bold
        case .navTitle, .kicker, .bodyStrong, .status, .button, .buttonSmall: .semibold
        case .routeTitle: .heavy
        case .legSubtitle, .body, .callout, .meta, .chipCaption, .footnote: .regular
        }
    }

    var design: Font.Design {
        self == .unit ? .rounded : .default
    }

    /// Horas y cuentas: con dígitos tabulares.
    var tabularDigits: Bool {
        switch self {
        case .meta, .status, .chipCaption, .footnote, .unit: true
        default: false
        }
    }

    /// Tope de Dynamic Type para piezas que viven dentro del billete o de las
    /// fichas; el resto del texto escala sin límite y la maqueta se adapta.
    var maxDynamicType: DynamicTypeSize? {
        switch self {
        case .routeTitle, .unit: .accessibility2
        case .destination: .accessibility3
        case .chipCaption, .label: .accessibility1
        default: nil
        }
    }

    var font: Font {
        let base = Font.system(style, design: design, weight: weight)
        return tabularDigits ? base.monospacedDigit() : base
    }
}

/// Cifras grandes en SF Pro Rounded heavy. `base` es el tamaño con Dynamic
/// Type «Grande» (el de fábrica); escala con el estilo `relativeTo` y se topa
/// en `maxSize`.
enum NumberLevel: Sendable, CaseIterable {
    /// Minutos del billete con 1–2 tramos (holgado, R47).
    case ticket
    /// Minutos del billete con 3–4 tramos.
    case ticketNormal
    /// Minutos del billete con 5–6 tramos. Nunca más pequeño que esto.
    case ticketCompact
    /// Minutos de las fichas 2.ª–4.ª.
    case chip
    /// Número de la vía (real o probable).
    case via
    /// Cifra de las fichas de estadísticas.
    case stat
    /// Porcentaje de acierto de la vía.
    case statBig
    /// Código de línea dentro del distintivo (el distintivo lo escala él).
    case badge

    var baseSize: CGFloat {
        switch self {
        case .ticket: 56
        case .ticketNormal: 48
        case .ticketCompact: 40
        case .chip: 24
        case .via: 20
        case .stat: 30
        case .statBig: 48
        case .badge: 15
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .ticket, .ticketNormal, .ticketCompact, .statBig: .largeTitle
        case .chip: .title2
        case .via: .title3
        case .stat: .title
        case .badge: .subheadline
        }
    }

    var maxSize: CGFloat {
        switch self {
        case .ticket: 80
        case .ticketNormal: 72
        case .ticketCompact: 60
        case .chip: 40
        case .via: 32
        case .stat: 48
        case .statBig: 72
        case .badge: 22
        }
    }

    /// Fuente a un tamaño ya calculado.
    static func font(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }
}

/// Densidad del tablero según el número de tramos (R47): lo que se encoge es
/// el aire y la segunda línea de las fichas, no la legibilidad de la cifra.
enum BoardDensity: Sendable {
    case roomy      // 1–2 tramos
    case regular    // 3–4 tramos
    case compact    // 5 o más

    init(legCount: Int) {
        switch legCount {
        case ...2: self = .roomy
        case 3...4: self = .regular
        default: self = .compact
        }
    }

    var ticketNumber: NumberLevel {
        switch self {
        case .roomy: .ticket
        case .regular: .ticketNormal
        case .compact: .ticketCompact
        }
    }

    /// En compacto las fichas solo llevan cifra y vía (sin hora ni longitud).
    var chipShowsSecondLine: Bool { self != .compact }
}

extension DepartureMoment {
    /// Escala de la cifra según lo que dice:
    /// - «ya» a tamaño completo: son dos letras y es lo más urgente.
    /// - «En andén» a la mitad, en una línea (en B salía a tamaño completo y
    ///   partía el billete en dos líneas enormes).
    /// - A partir de una hora («1h46») a 0,75: no es urgente y así cabe en un
    ///   iPhone SE sin empujar al destino.
    var numberScale: CGFloat {
        switch self {
        case .atStop: 0.5
        case .now: 1
        case .inMinutes(let m): m >= 60 ? 0.75 : 1
        }
    }
}

// MARK: - Modificadores

extension View {
    /// Aplica un nivel de texto (fuente de Dynamic Type y, si toca, su tope).
    func textLevel(_ level: TextLevel) -> some View {
        modifier(TextLevelModifier(level: level))
    }

    /// Cifra grande en SF Pro Rounded heavy, con dígitos tabulares, escalada
    /// con Dynamic Type hasta su tope. `scale` es para «En andén» y «1h46»
    /// (ver `DepartureMoment.numberScale`).
    func numberFont(_ level: NumberLevel, scale: CGFloat = 1) -> some View {
        modifier(NumberFontModifier(level: level, scale: scale))
    }
}

private struct TextLevelModifier: ViewModifier {
    let level: TextLevel

    @ViewBuilder
    func body(content: Content) -> some View {
        if let cap = level.maxDynamicType {
            content
                .font(level.font)
                .dynamicTypeSize(...cap)
        } else {
            content.font(level.font)
        }
    }
}

private struct NumberFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let level: NumberLevel
    private let scale: CGFloat

    init(level: NumberLevel, scale: CGFloat) {
        self.level = level
        self.scale = scale
        _size = ScaledMetric(wrappedValue: level.baseSize, relativeTo: level.relativeTo)
    }

    func body(content: Content) -> some View {
        let points = min(size, level.maxSize) * scale
        return content
            .font(NumberLevel.font(size: points))
            // B: letter-spacing −.02em en las cifras.
            .tracking(-0.02 * points)
    }
}

#if DEBUG
#Preview("Niveles de texto") {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(TextLevel.allCases, id: \.self) { level in
                Text(String(describing: level))
                    .textLevel(level)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("6").numberFont(.ticket)
                Text("min").textLevel(.unit)
                Text("1h46").numberFont(.ticket, scale: 0.75)
            }
        }
        .padding()
    }
}
#endif
