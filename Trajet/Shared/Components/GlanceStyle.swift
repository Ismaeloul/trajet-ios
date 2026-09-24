import SwiftUI
import WidgetKit

// Tokens y ayudas de las piezas «de reojo» (Live Activity y widgets):
// docs/diseno/sistema.md §12.2 (apagado, isla) y §12.8 (modos de pintado).
// Los colores de siempre están en `Palette`; aquí solo lo propio.

/// Tono de una pieza: viva o apagada (R19: dato viejo, sin conexión, sin clave).
enum GlanceTone: Hashable, Sendable {
    case live
    case off
}

/// Cómo pinta el sistema lo que dibujamos (sistema.md §12.8).
enum GlanceInk: Hashable, Sendable {
    /// Color: la app, la Live Activity, los widgets de inicio normales.
    case color
    /// Inicio tintado o transparente: todo de un color, cuenta el alfa.
    case accented
    /// Pantalla de bloqueo y StandBy de noche: grises, cuenta la luminancia.
    case vibrant

    init(_ mode: WidgetRenderingMode) {
        if mode == .accented {
            self = .accented
        } else if mode == .vibrant {
            self = .vibrant
        } else {
            self = .color
        }
    }

    var isMono: Bool { self != .color }

    /// En el modo acentuado, la cifra CALADA en una forma blanca
    /// (`compositingGroup` + `blendMode(.destinationOut)`) o el CONTORNO (trazo).
    /// El calado está por probar en la extensión (decisiones §10.2); mientras
    /// tanto, el contorno, que no puede fallar.
    /// TODO-PROBAR: poner a `true` si el calado se pinta bien en el simulador.
    static let accentedKnockout = false
}

/// Colores propios de la extensión (sistema.md §12.2). El apagado no es
/// opacidad: el billete pasa a un gris OPACO para que cifra y vía conserven
/// el contraste (cifra ≥ 8:1).
enum GlancePalette {
    /// Billete apagado. Claro #4B4D50 · oscuro #A3A5A7 (con «Aumentar
    /// contraste», oklch 36 % y 78 %).
    static let ticketOffToken = DynamicColor(
        light: RGBA(0.2957, 0.3024, 0.3130),
        dark: RGBA(0.6393, 0.6453, 0.6551),
        lightHC: RGBA(0.2335, 0.2398, 0.2501),
        darkHC: RGBA(0.7128, 0.7190, 0.7289))
    /// Cifra apagada: blanco (8,5:1) · #060606 (8,2:1).
    static let ticketOffInkToken = DynamicColor(
        light: RGBA(1, 1, 1),
        dark: RGBA(0.0223, 0.0223, 0.0223),
        lightHC: RGBA(1, 1, 1),
        darkHC: RGBA(0, 0, 0))
    /// «min», hora y longitud apagadas: #DCDEE1 · #232426 (6,3:1).
    static let ticketOffInk2Token = DynamicColor(
        light: RGBA(0.8641, 0.8705, 0.8808),
        dark: RGBA(0.1356, 0.1414, 0.1509),
        lightHC: RGBA(0.9300, 0.9300, 0.9300),
        darkHC: RGBA(0.0800, 0.0800, 0.0800))
    /// Caja de la vía real apagada: #C9CACD · #3C3D40 (sigue llena, R10).
    static let viaOffToken = DynamicColor(
        light: RGBA(0.7877, 0.7940, 0.8042),
        dark: RGBA(0.2335, 0.2398, 0.2501),
        lightHC: RGBA(0.7877, 0.7940, 0.8042),
        darkHC: RGBA(0.2335, 0.2398, 0.2501))
    /// Número de la vía apagada: #090B0F (12:1) · blanco (10,9:1).
    static let viaOffInkToken = DynamicColor(
        light: RGBA(0.0343, 0.0442, 0.0605),
        dark: RGBA(1, 1, 1),
        lightHC: RGBA(0, 0, 0),
        darkHC: RGBA(1, 1, 1))

    static let ticketOff: Color = ticketOffToken.color
    static let ticketOffInk: Color = ticketOffInkToken.color
    static let ticketOffInk2: Color = ticketOffInk2Token.color
    static let viaOff: Color = viaOffToken.color
    static let viaOffInk: Color = viaOffInkToken.color

    // MARK: Isla (siempre negra: colores fijos, los del tema oscuro)

    static let islandInk = Color.white
    static let islandInk2: Color = Tokens.ink2.color(for: .dark)
    static let islandInk3: Color = Tokens.ink3.color(for: .dark)
    /// Cifra apagada en la isla, sin billete: #B0B1B3 (9,8:1 sobre negro).
    static let islandOff = Color(.sRGB, red: 0.6895, green: 0.6941, blue: 0.7015, opacity: 1)
    static let islandOffInk = Color(.sRGB, red: 0.0223, green: 0.0223, blue: 0.0223, opacity: 1)
    /// Aro de la mínima apagada: #7A7A7A.
    static let islandRingOff = Color(.sRGB, red: 0.4790, green: 0.4790, blue: 0.4790, opacity: 1)
    static let islandWarn: Color = Tokens.warnText.color(for: .dark)
    static let islandBad: Color = Tokens.badText.color(for: .dark)
    static let islandStopFill = Color.white.opacity(0.18)
}

// MARK: - Texto

extension View {
    /// Texto de la Live Activity y los widgets: la talla del diseño (en pt con
    /// Dynamic Type «Grande») que escala con Dynamic Type; el tope lo pone la
    /// raíz (`.xLarge` en la actividad y la isla, `.xxLarge` en los widgets).
    func glanceText(_ size: CGFloat, _ weight: Font.Weight = .semibold,
                    relativeTo style: Font.TextStyle = .footnote,
                    design: Font.Design = .default, tabular: Bool = false) -> some View {
        modifier(GlanceTextModifier(size: size, weight: weight, style: style, design: design, tabular: tabular))
    }
}

private struct GlanceTextModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let tabular: Bool

    init(size: CGFloat, weight: Font.Weight, style: Font.TextStyle, design: Font.Design, tabular: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.tabular = tabular
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        return content.font(tabular ? font.monospacedDigit() : font)
    }
}

/// Fuentes fijas de las cifras (la actividad y los widgets tienen alto fijo:
/// las cifras no crecen con Dynamic Type, sistema.md §12.3).
enum GlanceFont {
    /// SF Pro Rounded heavy con dígitos tabulares (R48).
    static func number(_ size: CGFloat) -> Font {
        NumberLevel.font(size: size)
    }

    /// SF Pro Rounded black (número de la vía, código del distintivo).
    static func black(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }

    /// Palabras fijas junto a las cifras («Vía», «probable», «min»).
    static func word(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight)
    }
}
