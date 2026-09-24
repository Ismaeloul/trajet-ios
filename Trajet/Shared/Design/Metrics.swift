import SwiftUI

// Medidas del sistema «Cristal»: espaciado, radios, tamaños, opacidades y
// sombras. Valores sacados de design-lab/b-cristal/style.css y ajustados
// donde B rompía una regla (explicado en docs/diseno/sistema.md §5 y en
// docs/diseno/ajustes-b.md). Copia en formato máquina: design-lab/tokens.json.
//
// Los valores son puntos de iOS con Dynamic Type «Grande». Los que acompañan
// al texto (rellenos del billete, alto de las fichas) conviene escalarlos con
// `@ScaledMetric` en la vista; los de la maqueta (márgenes, radios) no.

enum Metrics {

    /// Espaciado. Rejilla de 2 pt con los pasos que usa B.
    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let sm: CGFloat = 8
        static let m: CGFloat = 10
        static let ml: CGFloat = 12
        /// Margen lateral de la pantalla y separación entre tarjetas (B: 14 px).
        static let gutter: CGFloat = 14
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    /// Radios. Todos `RoundedRectangle(cornerRadius:style: .continuous)`.
    ///
    /// Concentricidad: lo que toca una esquina de su contenedor lleva
    /// radio = radio del contenedor − margen. Tarjeta 30 con 12 de relleno →
    /// billete, fichas y aviso a 18. En B no casaba (tarjeta 28, relleno 14,
    /// billete 22). En iOS 26 se puede delegar en el sistema con formas
    /// concéntricas; aquí se calcula para que sea igual desde iOS 17.
    enum Radius {
        /// Caja de la vía (real o probable).
        static let via: CGFloat = 10
        /// Billete, fichas, aviso y banner dentro de una tarjeta.
        static let inner: CGFloat = 18
        /// Fichas de estadísticas.
        static let tile: CGFloat = 22
        /// Tarjeta opaca (tramo, ruta, opción).
        static let card: CGFloat = 30
        /// Barras flotantes de cristal (cabecera del tablero, tarjeta del mapa).
        static let bar: CGFloat = 30
        /// Hojas propias (las del sistema ya traen el suyo).
        static let sheet: CGFloat = 36
        /// Distintivo de línea: 30 % del lado (B: .6em sobre 2em).
        static let badgeRatio: CGFloat = 0.3

        /// Radio concéntrico de un hijo que toca la esquina de su contenedor.
        static func concentric(outer: CGFloat, padding: CGFloat, minimum: CGFloat = 4) -> CGFloat {
            max(minimum, outer - padding)
        }
    }

    /// Tamaños.
    enum Size {
        /// Área táctil mínima (R52). Nada que se toque mide menos.
        static let hit: CGFloat = 44
        /// Botón redondo de cristal.
        static let glassButton: CGFloat = 44
        /// Alto del botón principal y del de peligro.
        static let primaryButton: CGFloat = 50
        /// Alto mínimo de una fila de lista.
        static let row: CGFloat = 48
        /// Distintivo de línea: pequeño (cadenas, estadísticas), normal y grande
        /// (cabecera del tramo).
        static let badgeSmall: CGFloat = 25
        static let badge: CGFloat = 30
        static let badgeLarge: CGFloat = 42
        /// Ancho mínimo de una ficha de salida (2.ª–4.ª).
        static let chipMinWidth: CGFloat = 92
        /// Grosor de la barra del próximo refresco (R54).
        static let refreshBar: CGFloat = 2
        /// Punto «en directo».
        static let liveDot: CGFloat = 9
        /// Filete.
        static let hairline: CGFloat = 1
        /// Recuadro punteado de la vía probable (R10): trazo y guion.
        static let dashWidth: CGFloat = 1.5
        static let dash: [CGFloat] = [4, 3]
        /// Anillo del latido de la vía nueva (B: box-shadow 0 0 0 6px).
        static let viaRing: CGFloat = 6
        /// Relleno de la tarjeta opaca y de las barras de cristal.
        static let cardPadding: CGFloat = 12
        /// Relleno del billete.
        static let ticketPadding: CGFloat = 14
    }

    /// Opacidades con significado.
    enum Opacity {
        /// Tablero con el dato viejo: se apaga entero (R19).
        static let stale: Double = 0.55
        /// …y pierde el color (saturación).
        static let staleSaturation: Double = 0.2
        /// Alternativa que no sirve (R30).
        static let unusable: Double = 0.55
        /// Pulsado con «Reducir movimiento» (en vez de encoger).
        static let pressed: Double = 0.7
    }

    /// Sombras. En CSS el desenfoque es ~2σ; en SwiftUI `radius` ≈ desenfoque / 2.
    /// En iOS 26 las piezas con `glassEffect` no llevan sombra propia: la pone
    /// el sistema.
    enum Shadow {
        struct Spec: Sendable, Hashable {
            let opacity: Double
            let radius: CGFloat
            let y: CGFloat
        }
        /// Barras de cristal (B: 0 10px 30px / .18).
        static let glass = Spec(opacity: 0.18, radius: 15, y: 10)
        /// Botón de cristal (B: 0 4px 14px / .15).
        static let glassButton = Spec(opacity: 0.15, radius: 7, y: 4)
        /// Tarjeta opaca (B: 0 6px 24px / .12).
        static let card = Spec(opacity: 0.12, radius: 12, y: 6)
        /// Botón principal y de peligro, del color del botón (B: 0 8px 20px / .35).
        static let filled = Spec(opacity: 0.35, radius: 10, y: 8)
        /// Halo de la vía nueva (B: 0 0 24px via/.8).
        static let viaGlow = Spec(opacity: 0.8, radius: 12, y: 0)
    }
}

extension View {
    /// Área táctil de al menos 44 × 44 pt sin cambiar lo que se ve (R52).
    func hitTarget(_ minimum: CGFloat = Metrics.Size.hit) -> some View {
        frame(minWidth: minimum, minHeight: minimum)
            .contentShape(Rectangle())
    }

    /// Sombra del sistema a partir de una `Metrics.Shadow.Spec`.
    func trajetShadow(_ spec: Metrics.Shadow.Spec, color: Color = Palette.shadow) -> some View {
        shadow(color: color.opacity(spec.opacity), radius: spec.radius, x: 0, y: spec.y)
    }

    /// Tarjeta opaca del sistema: `surface`, radio 30, filete y sombra suave.
    /// El relleno lo pone quien la usa (normalmente `Metrics.Size.cardPadding`).
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }
}

private struct CardBackgroundModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
        return content
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.rule, lineWidth: contrast == .increased ? 1.5 : Metrics.Size.hairline))
            .trajetShadow(Metrics.Shadow.card)
    }
}
