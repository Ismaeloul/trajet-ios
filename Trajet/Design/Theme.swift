import SwiftUI

// FACHADA TEMPORAL — SE BORRA EN LA FASE 3.
//
// Esto era la paleta oscura de la v1 (Palette, TypeScale, Metrics y tres
// modificadores). La capa nueva vive en Tokens.swift, Typography.swift,
// Metrics.swift, Motion.swift y Glass.swift (sistema «Cristal»,
// docs/diseno/sistema.md). Aquí solo quedan los nombres viejos que usan las
// vistas de la v1 y Format.swift, redirigidos a los tokens nuevos y marcados
// como obsoletos para que el compilador enseñe cada uso pendiente.
//
// Cuando la FASE 3 haya rehecho las vistas y movido `Pace.color` de
// Format.swift a `Palette.badText` / `Palette.ink2` / `Palette.ink3`, este
// fichero se borra entero.

// MARK: - Nombres viejos de la paleta
// `Palette.surface`, `.surfaceHi`, `.ink`, `.warn`, `.bad` y `.ok` existen con
// el mismo nombre en la paleta nueva y ya apuntan a ella.

extension Palette {
    @available(*, deprecated, renamed: "bg", message: "Fachada de la v1: usa Palette.bg")
    static var background: Color { bg }

    @available(*, deprecated, renamed: "rule", message: "Fachada de la v1: usa Palette.rule")
    static var hairline: Color { rule }

    @available(*, deprecated, message: "Fachada de la v1: usa Palette.rule (con «Aumentar contraste» ya se refuerza sola)")
    static var hairlineHi: Color { rule }

    @available(*, deprecated, renamed: "ink2", message: "Fachada de la v1: usa Palette.ink2")
    static var inkMuted: Color { ink2 }

    @available(*, deprecated, renamed: "ink3", message: "Fachada de la v1: usa Palette.ink3")
    static var inkFaint: Color { ink3 }
}

// MARK: - Tipografía vieja (ahora con Dynamic Type)

@available(*, deprecated, message: "Fachada de la v1: usa .textLevel(_:) y .numberFont(_:) (Typography.swift)")
enum TypeScale {
    /// Antes fijo; sigue fijo porque aquí no hay `@ScaledMetric`. Usa `.numberFont`.
    static func minutes(_ size: CGFloat) -> Font {
        NumberLevel.font(size: size)
    }

    static var title: Font { Font.system(.title, design: .default, weight: .heavy) }
    static var section: Font { TextLevel.legTitle.font }
    static var body: Font { TextLevel.callout.font }
    static var caption: Font { Font.system(.footnote, design: .default, weight: .semibold) }
    static var overline: Font { Font.system(.caption2, design: .default, weight: .bold) }
    static var badge: Font { Font.system(.subheadline, design: .rounded, weight: .heavy) }
}

extension View {
    /// Rótulo pequeño en versales de la v1. En «Cristal» los rótulos van en
    /// minúscula normal: `.textLevel(.kicker)` con `Palette.ink3`.
    @available(*, deprecated, message: "Fachada de la v1: usa .textLevel(.kicker).foregroundStyle(Palette.ink3)")
    func overlineStyle(_ color: Color = Palette.ink3) -> some View {
        self.font(Font.system(.caption2, design: .default, weight: .bold))
            .textCase(.uppercase)
            .kerning(1.3)
            .foregroundStyle(color)
    }

    /// Superficie de tarjeta de la v1, ya con los colores nuevos.
    @available(*, deprecated, message: "Fachada de la v1: usa .cardBackground() (Metrics.swift)")
    func cardSurface(_ radius: CGFloat = 22, fill: Color = Palette.surface) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: 1)
        )
    }

    /// Área táctil mínima de la v1.
    @available(*, deprecated, renamed: "hitTarget()", message: "Fachada de la v1: usa .hitTarget()")
    func minimumHitTarget() -> some View {
        hitTarget()
    }
}

// MARK: - Medidas viejas del tablero (el hilo vertical de la v1)

extension Metrics {
    @available(*, deprecated, message: "Fachada de la v1: el hilo vertical no existe en «Cristal»")
    static let railColumn: CGFloat = 46

    @available(*, deprecated, message: "Fachada de la v1: usa Metrics.Size.badgeLarge")
    static let badgeSize: CGFloat = 42

    @available(*, deprecated, message: "Fachada de la v1: el hilo vertical no existe en «Cristal»")
    static let railWidth: CGFloat = 5
}
