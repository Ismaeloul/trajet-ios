import SwiftUI

// El cristal de «Cristal»: la capa de CONTROLES que flota sobre el mapa.
//
// Dónde va: cabecera del tablero, píldora de ruta y botones del mapa, tarjeta
// del modo trayecto, hoja de emparejar y botones redondos. La barra de
// pestañas, las barras de navegación, las barras de herramientas y las hojas
// del sistema ya son de cristal en iOS 26 sin hacer nada: NO se reimplementan.
//
// Dónde NO va nunca: debajo de los minutos o de la vía (regla 1: se leen a
// contraluz). Las tarjetas de tramo son opacas (`cardBackground()`), y dentro
// de un cristal los minutos van en el billete opaco.
//
// Tres caminos, en este orden:
// 1. «Reducir transparencia» activado → relleno OPACO (`glassOpaque`) con
//    canto. Se comprueba primero, en todas las versiones.
// 2. iOS 26 → `glassEffect` del sistema (Liquid Glass de verdad).
// 3. iOS 17–25 → material (`.ultraThinMaterial` o `.regularMaterial`) con el
//    tinte, el brillo del canto superior y la sombra de B.
// Con «Aumentar contraste», además, canto visible (`glassEdge` en su variante
// de contraste alto).

/// Qué papel hace el cristal. Decide el material de la alternativa y si
/// reacciona al dedo en iOS 26.
enum CristalRole: Sendable {
    /// Barra flotante: cabecera del tablero, píldora de ruta. `.ultraThinMaterial`.
    case bar
    /// Botón o control que se toca. `.ultraThinMaterial` e interactivo en iOS 26.
    case control
    /// Panel con contenido: tarjeta del modo trayecto, hoja de emparejar.
    /// `.regularMaterial` (más opaco: lleva texto).
    case panel

    var isInteractive: Bool { self == .control }
}

extension View {
    /// Cristal con la forma dada.
    ///
    /// - Parameters:
    ///   - role: barra, control o panel.
    ///   - shape: la forma (capsula, círculo o `RoundedRectangle(…, style: .continuous)`).
    ///   - tint: tinte opcional (p. ej. rojo en «Parar trayecto»). Con cuentagotas.
    func cristal<S: InsettableShape>(_ role: CristalRole = .bar, in shape: S, tint: Color? = nil) -> some View {
        modifier(CristalModifier(role: role, shape: shape, tint: tint))
    }

    /// Cristal con esquinas redondeadas continuas (por defecto, las de las barras).
    func cristal(_ role: CristalRole = .bar, cornerRadius: CGFloat = Metrics.Radius.bar, tint: Color? = nil) -> some View {
        cristal(role, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }

    /// Identidad para el morph entre piezas de cristal del mismo `CristalGroup`
    /// (p. ej. «Iniciar trayecto» → tarjeta del modo trayecto). En iOS 17–25 es
    /// un `matchedGeometryEffect` con el mismo `id`.
    ///
    /// TODO-COMPILAR: firma supuesta `glassEffectID(_:in:)` de iOS 26
    /// (`(some Hashable & Sendable)?`, `Namespace.ID`). Si no casa, dejar solo
    /// la rama de `matchedGeometryEffect`, que también vale en iOS 26.
    @ViewBuilder
    func cristalID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }

    /// Botón de cristal del sistema (iOS 26) o su equivalente (iOS 17–25 y
    /// «Reducir transparencia»). `prominent` = relleno de acento; `circle` =
    /// botón redondo de 44 pt solo con icono (ajustes, atrás, centrar).
    func cristalButton(prominent: Bool = false, circle: Bool = false) -> some View {
        modifier(CristalButtonModifier(prominent: prominent, circle: circle))
    }

    /// Botón opaco con relleno: principal (acento) o de peligro (rojo).
    func filledButton(_ role: FilledButtonStyle.Role = .primary) -> some View {
        buttonStyle(FilledButtonStyle(role: role))
    }
}

/// Agrupa piezas de cristal para que se fundan y hagan morph entre ellas
/// (iOS 26: `GlassEffectContainer`). En iOS 17–25 no hace nada.
///
/// TODO-COMPILAR: firma supuesta `GlassEffectContainer(spacing:content:)`.
struct CristalGroup<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Cristal

private struct CristalModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let role: CristalRole
    let shape: S
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            opaque(content)
        } else {
            glassy(content)
        }
    }

    /// 1. «Reducir transparencia»: el compuesto de B sobre el fondo, sin
    /// nada que se transparente detrás.
    private func opaque(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(Palette.glassOpaque)
                    if let tint { shape.fill(tint.opacity(0.18)) }
                }
            }
            .overlay { shape.strokeBorder(Palette.glassEdge, lineWidth: edgeWidth) }
    }

    @ViewBuilder
    private func glassy(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 2. Liquid Glass del sistema.
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(Palette.glassEdge, lineWidth: edgeWidth)
                    }
                }
        } else {
            // 3. Material + tinte + canto con brillo arriba + sombra (receta de B).
            content
                .background {
                    ZStack {
                        shape.fill(role == .panel ? Material.regular : Material.ultraThin)
                        shape.fill(Palette.glass)
                        if let tint { shape.fill(tint.opacity(0.22)) }
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Palette.glassHighlight, Palette.glassEdge],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: edgeWidth)
                }
                .trajetShadow(role == .control ? Metrics.Shadow.glassButton : Metrics.Shadow.glass)
        }
    }

    private var edgeWidth: CGFloat {
        contrast == .increased ? 1.5 : Metrics.Size.hairline
    }

    /// TODO-COMPILAR: API de iOS 26 supuesta: `Glass.regular`, `.tint(_:)`,
    /// `.interactive(_:)`. Si alguna no casa, quitar el modificador que falle:
    /// `Glass.regular` a secas ya es correcto.
    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if role.isInteractive { g = g.interactive() }
        return g
    }
}

// MARK: - Botones

private struct CristalButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    let circle: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(CristalFallbackButtonStyle(prominent: prominent, circle: circle))
        } else {
            system(content)
        }
    }

    @ViewBuilder
    private func system(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // TODO-COMPILAR: `.glass` y `.glassProminent` son los estilos de
            // botón de cristal de iOS 26. Si no casan, usar la rama de abajo.
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(circle ? .circle : .capsule)
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(circle ? .circle : .capsule)
            }
        } else {
            content.buttonStyle(CristalFallbackButtonStyle(prominent: prominent, circle: circle))
        }
    }
}

/// Botón de cristal en iOS 17–25 (y opaco con «Reducir transparencia»):
/// cápsula de cristal, 44 pt de alto mínimo, se encoge a 0,88 con muelle al
/// pulsar (B: `.glass-btn:active`). Con «Reducir movimiento», se atenúa en
/// vez de encogerse.
struct CristalFallbackButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var circle: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let side = Metrics.Size.glassButton
        return configuration.label
            .textLevel(.button)
            .foregroundStyle(prominent ? Palette.onAccent : Palette.ink)
            .padding(.horizontal, circle ? 0 : Metrics.Space.l)
            // Redondo: 44 × 44 (una cápsula de lados iguales es un círculo).
            .frame(minWidth: side, maxWidth: circle ? side : nil, minHeight: side, maxHeight: circle ? side : nil)
            .modifier(ProminentOrGlass(prominent: prominent))
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.88 : 1)
            .opacity(pressed && reduceMotion ? Metrics.Opacity.pressed : 1)
            .animation(Motion.animation(.press, reduceMotion: reduceMotion), value: pressed)
    }
}

private struct ProminentOrGlass: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.background(Capsule().fill(Palette.accentFill))
        } else {
            content.cristal(.control, in: Capsule())
        }
    }
}

/// Botón opaco con relleno (B: `.btn-primary`, `.btn-danger`): 50 pt de alto,
/// cápsula, texto blanco, sombra del color del botón; se encoge a 0,95.
struct FilledButtonStyle: ButtonStyle {
    enum Role: Sendable {
        /// «Iniciar trayecto», «Escanear», «Guardar ruta».
        case primary
        /// «Parar trayecto», «Buscar alternativa · línea cortada».
        case danger
    }

    var role: Role = .primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = role == .primary ? Palette.accentFill : Palette.bad
        return configuration.label
            .textLevel(.button)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, Metrics.Space.xl)
            .frame(maxWidth: .infinity, minHeight: Metrics.Size.primaryButton)
            .background(Capsule().fill(fill))
            .trajetShadow(Metrics.Shadow.filled, color: fill)
            .contentShape(Capsule())
            .opacity(isEnabled ? (pressed && reduceMotion ? Metrics.Opacity.pressed : 1) : 0.45)
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
            .animation(Motion.animation(.pressButton, reduceMotion: reduceMotion), value: pressed)
    }
}

#if DEBUG
#Preview("Cristal sobre el mapa") {
    ZStack {
        LinearGradient(colors: [.yellow, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        VStack(spacing: 16) {
            HStack {
                Text("Trabajo → Casa").textLevel(.routeTitle)
                Spacer()
                Button {} label: { Image(systemName: "gearshape") }
                    .cristalButton(circle: true)
                    .accessibilityLabel("Ajustes")
            }
            .padding(Metrics.Size.cardPadding)
            .cristal(.bar)
            Button("Iniciar trayecto") {}
                .filledButton()
            Button("Parar trayecto") {}
                .filledButton(.danger)
        }
        .padding(Metrics.Space.gutter)
    }
}
#endif
