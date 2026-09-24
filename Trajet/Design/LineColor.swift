import SwiftUI

/// Los colores de línea no son nuestros: vienen en `line_color` y son los que
/// están pintados en las paredes de la estación. El ojo ya los conoce (R12).
///
/// Dos reglas:
/// - **Parseo tolerante** (R57): con o sin «#», con «0x», 3, 4, 6 u 8 dígitos
///   (el alfa se ignora), espacios alrededor. Lo que no se entiende da el gris
///   de reserva, «un gris que no miente».
/// - **Contraste garantizado** en el distintivo (R12): la tinta es el texto
///   oficial de IDFM (`textcolourweb_hexa`, que el servidor manda como
///   `text_color` en el mapa) si da al menos 4,5:1; si no, negro o blanco, el
///   que MÁS contraste dé. Negro y blanco empatan a una luminancia de ~0,18
///   con 4,58:1, así que la tinta calculada nunca baja de ahí y la oficial,
///   cuando se usa, da al menos 4,5:1. La v1 usaba un umbral de 0,45 y dejaba
///   colores con texto blanco a 2,5:1. Consecuencia buscada: donde el texto
///   oficial de IDFM no llega (RER A, B y D, Transilien K, N y V, tranvías
///   T6, T9 y T14…) el código va en negro. Tabla de las 49 líneas de metro,
///   tren y tranvía de IDFM en docs/diseno/sistema.md (anexo A).
enum LineColor {

    /// Contraste mínimo del texto del distintivo (WCAG AA, texto normal).
    static let minimumContrast: Double = 4.5

    /// El gris de reserva (#6B7380), para cuando la API no manda color.
    static let fallbackHex = "6B7380"
    static let fallbackRGB = LineRGB(red: 0x6B, green: 0x73, blue: 0x80)
    static let fallback: Color = fallbackRGB.color

    /// "82C8E6" -> Color. Nunca falla: si no se entiende, el gris de reserva.
    static func parse(_ hex: String) -> Color {
        (rgb(hex) ?? fallbackRGB).color
    }

    /// El color ya parseado, o `nil` si el texto no es un color.
    static func rgb(_ hex: String?) -> LineRGB? {
        guard let hex else { return nil }
        return LineRGB(hex: hex)
    }

    /// Tinta (texto) encima del color de línea, con contraste garantizado.
    ///
    /// - Parameters:
    ///   - hex: `line_color`.
    ///   - official: el texto oficial (`text_color` del mapa), si se tiene.
    static func ink(on hex: String, official: String? = nil) -> Color {
        badge(line: hex, officialText: official).foreground
    }

    /// Fondo y tinta del distintivo, con el contraste que dan.
    static func badge(line hex: String, officialText: String? = nil) -> BadgeColors {
        let background = rgb(hex) ?? fallbackRGB
        if let official = rgb(officialText) {
            let ratio = background.contrast(with: official)
            if ratio >= minimumContrast {
                return BadgeColors(background: background, text: official, contrast: ratio, usesOfficialText: true)
            }
        }
        let onBlack = background.contrast(with: .black)
        let onWhite = background.contrast(with: .white)
        let text: LineRGB = onBlack >= onWhite ? .black : .white
        return BadgeColors(background: background, text: text, contrast: max(onBlack, onWhite), usesOfficialText: false)
    }

    /// Un tono del color de línea que sirva de fondo tenue sin gritar.
    static func wash(_ hex: String, opacity: Double = 0.14) -> Color {
        parse(hex).opacity(opacity)
    }
}

/// Un color de línea en sRGB de 8 bits por canal.
struct LineRGB: Sendable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let black = LineRGB(red: 0, green: 0, blue: 0)
    static let white = LineRGB(red: 255, green: 255, blue: 255)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parseo tolerante (R57). Acepta «CEC73D», «#cec73d», «0xCEC73D»,
    /// « FC0 », «#FC0F» (4 dígitos, alfa ignorado) y «CEC73DFF» (8 dígitos).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
        } else if s.lowercased().hasPrefix("0x") {
            s.removeFirst(2)
        }
        // Solo dígitos hexadecimales: `UInt32(_:radix:)` aceptaría un «+».
        guard !s.isEmpty, s.allSatisfy(\.isHexDigit) else { return nil }
        switch s.count {
        case 3, 4:
            // «FC0» -> «FFCC00»; con 4, el cuarto es el alfa y se descarta.
            s = String(s.prefix(3)).map { "\($0)\($0)" }.joined()
        case 6:
            break
        case 8:
            s = String(s.prefix(6))
        default:
            return nil
        }
        guard let value = UInt32(s, radix: 16) else { return nil }
        self.init(red: UInt8((value >> 16) & 0xFF),
                  green: UInt8((value >> 8) & 0xFF),
                  blue: UInt8(value & 0xFF))
    }

    /// «CEC73D», sin almohadilla.
    var hex: String {
        String(format: "%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    var rgba: RGBA {
        RGBA(Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    }

    /// Luminancia relativa de WCAG 2.x.
    var relativeLuminance: Double { rgba.relativeLuminance }

    /// Relación de contraste WCAG (1…21).
    func contrast(with other: LineRGB) -> Double {
        rgba.contrast(with: other.rgba)
    }
}

/// Lo que necesita un distintivo para pintarse.
struct BadgeColors: Sendable, Hashable {
    let background: LineRGB
    let text: LineRGB
    /// Contraste real entre `text` y `background` (siempre ≥ 4,5).
    let contrast: Double
    /// `true` si la tinta es la oficial de IDFM; `false` si se ha calculado.
    let usesOfficialText: Bool

    var fill: Color { background.color }
    var foreground: Color { text.color }
}

/// El distintivo de la línea: J, 13, T2, 147, 6424.
///
/// Como en B: caja con esquinas al 30 % del lado, código en SF Pro Rounded
/// black a la mitad del lado y un filete oscuro abajo (B: `inset 0 -2px 0`).
/// Con códigos largos la caja crece a lo ancho en vez de encoger la letra.
/// Escala con Dynamic Type hasta 1,4× y, con «Aumentar contraste», lleva
/// canto para que se separe del fondo aunque el color de línea se le parezca.
struct LineBadge: View {
    let code: String
    let color: String
    /// Texto oficial (`text_color` del mapa), si se tiene.
    let textColor: String?
    /// Lado con Dynamic Type «Grande». 42 en la cabecera del tramo, 30 en
    /// listas y cadenas, 25 en lo pequeño (`Metrics.Size`).
    let size: CGFloat

    @ScaledMetric private var dynamicScale: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    /// Mismo orden que el de la v1 (`code:color:size:`), con `textColor` opcional.
    init(code: String, color: String, textColor: String? = nil, size: CGFloat = Metrics.Size.badgeLarge) {
        self.code = code
        self.color = color
        self.textColor = textColor
        self.size = size
        _dynamicScale = ScaledMetric(wrappedValue: 1, relativeTo: .headline)
    }

    private var side: CGFloat { size * min(dynamicScale, 1.4) }

    private var fontRatio: CGFloat {
        switch code.count {
        case 0...2: 0.5
        case 3: 0.44
        default: 0.38
        }
    }

    var body: some View {
        let colors = LineColor.badge(line: color, officialText: textColor)
        let shape = RoundedRectangle(cornerRadius: side * Metrics.Radius.badgeRatio, style: .continuous)
        Text(code.isEmpty ? "?" : code)
            .font(NumberLevel.font(size: side * fontRatio).weight(.black))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, side * 0.2)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .fixedSize(horizontal: true, vertical: false)
            .background(shape.fill(colors.fill))
            .overlay(alignment: .bottom) {
                // Filete inferior (B: inset 0 -2px 0 oklch(0% 0 0 / .15)).
                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(height: 2)
            }
            .clipShape(shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Palette.rule, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Línea \(code)")
    }
}

#if DEBUG
#Preview("Distintivos") {
    VStack(spacing: 12) {
        HStack(spacing: 10) {
            LineBadge(code: "J", color: "CEC73D", textColor: "#000000")
            LineBadge(code: "13", color: "82C8E6")
            LineBadge(code: "14", color: "640082", textColor: "#FFFFFF")
            LineBadge(code: "T2", color: "C4318E")
            LineBadge(code: "147", color: "E4022D")
            LineBadge(code: "6424", color: "A50034")
        }
        HStack(spacing: 8) {
            LineBadge(code: "B", color: "5091CB", textColor: "FFFFFF", size: Metrics.Size.badge)
            LineBadge(code: "3", color: "6E6E00", size: Metrics.Size.badge)
            LineBadge(code: "?", color: "no-es-un-color", size: Metrics.Size.badge)
            LineBadge(code: "U", color: "#b6134c", size: Metrics.Size.badgeSmall)
        }
    }
    .padding()
    .background(Palette.bg)
}
#endif
