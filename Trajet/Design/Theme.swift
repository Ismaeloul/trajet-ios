import SwiftUI

/// La paleta neutra.
///
/// Regla de fondo, heredada del manual: los colores oficiales de las líneas
/// son los ÚNICOS colores saturados de la pantalla. Todo lo de aquí es gris,
/// salvo los tres tonos de aviso, que se usan con cuentagotas.
enum Palette {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.047)   // #0a0a0c
    static let surface    = Color(red: 0.075, green: 0.075, blue: 0.086)   // #131316
    static let surfaceHi  = Color(red: 0.110, green: 0.110, blue: 0.125)   // #1c1c20
    static let hairline   = Color.white.opacity(0.09)
    static let hairlineHi = Color.white.opacity(0.16)

    static let ink        = Color.white
    static let inkMuted   = Color.white.opacity(0.62)
    static let inkFaint   = Color.white.opacity(0.38)

    /// Avisos. Deliberadamente apagados: compiten con los colores de línea.
    static let warn   = Color(red: 0.98, green: 0.72, blue: 0.20)
    static let bad    = Color(red: 1.00, green: 0.40, blue: 0.44)
    static let ok     = Color(red: 0.35, green: 0.85, blue: 0.58)
}

/// Tipografía. Los minutos van en cifras de ancho fijo para que no bailen
/// cuando pasan de 9 a 10 en mitad de un refresco.
enum TypeScale {
    static func minutes(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
            .monospacedDigit()
    }

    static let title    = Font.system(size: 30, weight: .heavy).width(.compressed)
    static let section  = Font.system(size: 20, weight: .bold)
    static let body     = Font.system(size: 15, weight: .medium)
    static let caption  = Font.system(size: 13, weight: .semibold)
    static let overline = Font.system(size: 10, weight: .bold)
    static let badge    = Font.system(size: 13, weight: .heavy, design: .rounded)
}

extension View {
    /// Rótulo pequeño en versales, el que rotula las secciones.
    func overlineStyle(_ color: Color = Palette.inkFaint) -> some View {
        self.font(TypeScale.overline)
            .textCase(.uppercase)
            .kerning(1.3)
            .foregroundStyle(color)
    }

    /// Superficie de tarjeta, con su filete.
    func cardSurface(_ radius: CGFloat = 22, fill: Color = Palette.surface) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    /// Área táctil mínima. El manual no la negocia: 44 pt, que es lo que
    /// Apple llama 48 px en la web.
    func minimumHitTarget() -> some View {
        self.contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
    }
}

/// Medidas compartidas del tablero.
enum Metrics {
    /// Ancho de la columna del distintivo de línea. El hilo vertical va
    /// centrado en ella, y por eso lo comparten la insignia y el raíl.
    static let railColumn: CGFloat = 46
    static let badgeSize: CGFloat = 42
    static let railWidth: CGFloat = 5
}
