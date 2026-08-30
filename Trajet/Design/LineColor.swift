import SwiftUI

/// Los colores de línea no son nuestros: vienen en `line_color`, y son los que
/// están pintados en las paredes de la estación. El ojo ya los conoce.
enum LineColor {

    /// Si la API no manda color (pasa en algún bus), un gris que no miente.
    static let fallback = Color(red: 0.42, green: 0.45, blue: 0.50)

    /// "82C8E6" -> Color. Acepta con o sin almohadilla, y 3 o 6 dígitos.
    static func parse(_ hex: String) -> Color {
        guard let rgb = components(hex) else { return fallback }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Negro o blanco encima del color de línea, según el contraste real.
    ///
    /// El prototipo llevaba escrito a mano que la 13 y la J son claras. Con 36
    /// líneas eso no se sostiene, así que se calcula: luminancia relativa de
    /// la W3C y umbral en 0,45, que es donde el amarillo del Transilien J
    /// (#CEC73D) cae del lado del texto negro y el morado de la 14 (#640082)
    /// del lado del blanco.
    static func ink(on hex: String) -> Color {
        guard let rgb = components(hex) else { return .white }
        return luminance(rgb) > 0.45 ? .black : .white
    }

    /// Un tono del color de línea que sirva de fondo tenue sin gritar.
    static func wash(_ hex: String, opacity: Double = 0.14) -> Color {
        parse(hex).opacity(opacity)
    }

    // ---------------- cálculo ----------------

    private static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    /// Luminancia relativa, con la corrección de gamma de la W3C.
    private static func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
    }
}

/// El distintivo de la línea: J, 13, T2, 147.
///
/// Va FUERA de la tarjeta, montado sobre el hilo vertical que cose un tramo
/// con el siguiente. Es lo que convierte una lista de tarjetas en un trayecto.
struct LineBadge: View {
    let code: String
    let color: String
    var size: CGFloat = Metrics.badgeSize

    private var fontSize: CGFloat {
        switch code.count {
        case 0, 1, 2: size * 0.46
        case 3: size * 0.36
        default: size * 0.29
        }
    }

    var body: some View {
        Text(code.isEmpty ? "?" : code)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(LineColor.parse(color))
            )
            .foregroundStyle(LineColor.ink(on: color))
            .accessibilityLabel("Línea \(code)")
    }
}

#Preview("Distintivos") {
    HStack(spacing: 10) {
        LineBadge(code: "J", color: "CEC73D")
        LineBadge(code: "13", color: "82C8E6")
        LineBadge(code: "14", color: "640082")
        LineBadge(code: "T2", color: "C4318E")
        LineBadge(code: "147", color: "E4022D")
        LineBadge(code: "6424", color: "A50034")
    }
    .padding()
    .background(Palette.background)
}
