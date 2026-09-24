import SwiftUI

// Movimiento del sistema «Cristal»: muelles y morph.
//
// B anima con dos curvas CSS:
// - «spring»  cubic-bezier(.34, 1.45, .64, 1): sobrepasa un 6,6 %. Un muelle
//   con ese sobrepaso tiene un amortiguamiento ζ = 0,65 (cálculo en
//   design-lab/tools/tokens.mjs). La duración CSS se usa como `response`.
// - «ease»    cubic-bezier(.2, .8, .2, 1): se traduce tal cual con
//   `Animation.timingCurve`.
//
// Todo pasa por aquí para que «Reducir movimiento» se respete en un solo
// sitio (R51): cada animación tiene su alternativa, que casi siempre es un
// fundido corto o nada. Las hápticas NO se quitan con «Reducir movimiento».
// Catálogo completo: docs/diseno/sistema.md §9.

enum Motion {

    /// Amortiguamiento del muelle de B (ζ). 1 = sin rebote.
    static let dampingFraction: Double = 0.65

    /// Tiempos (segundos).
    enum Timing {
        /// Pulsar un botón de cristal (escala 0,88).
        static let press: Double = 0.35
        /// Pulsar un botón normal (escala 0,95).
        static let pressButton: Double = 0.4
        /// Cambio de cifra.
        static let numberSwap: Double = 0.5
        /// Morph y cambios de maqueta.
        static let morph: Double = 0.5
        /// Encontrar el QR al emparejar.
        static let pairFound: Double = 0.6
        /// La vía aparece (escala 0,3 → 1).
        static let viaAppear: Double = 0.7
        /// Barras de estadísticas al aparecer.
        static let barGrow: Double = 0.8
        /// Media vuelta del latido de la vía nueva (B: 1,6 s ida y vuelta).
        static let viaPulseHalf: Double = 0.8
        /// Latidos de la vía nueva.
        static let viaPulseCount = 5
        /// Retraso antes del primer latido (deja terminar la aparición).
        static let viaPulseDelay: Double = 0.5
        /// Cuánto tiempo se considera «nueva» una vía recién publicada.
        static let viaNewWindow: Double = 25
        /// Onda del punto «en directo».
        static let live: Double = 2.0
        /// Respiración del marco del escáner.
        static let breathe: Double = 1.2
        /// El tablero se apaga cuando el dato es viejo (R19).
        static let staleDim: Double = 0.45
        /// El trazado de la línea se dibuja al abrir el mapa.
        static let routeDraw: Double = 1.5
        /// Aviso efímero (R55).
        static let toast: Double = 2.4
        /// Fundido que sustituye a las animaciones con «Reducir movimiento».
        static let reduced: Double = 0.2
        /// Un «ya» sigue en pantalla hasta 45 s después de su hora.
        static let nowGrace: Double = 45
    }

    /// Qué se anima. Cada caso tiene su curva y su alternativa.
    enum Kind: Sendable, CaseIterable {
        case press
        case pressButton
        case numberSwap
        case morph
        case pairFound
        case viaAppear
        case barGrow
        case staleDim
        case routeDraw
        /// Transiciones suaves sin rebote (aparecer una hoja propia, un aviso).
        case ease
    }

    /// Muelle con el amortiguamiento de B y la respuesta dada.
    static func spring(_ response: Double) -> Animation {
        .spring(response: response, dampingFraction: dampingFraction, blendDuration: 0)
    }

    /// La curva «ease» de B, exacta.
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
    }

    static func animation(_ kind: Kind) -> Animation {
        switch kind {
        case .press: spring(Timing.press)
        case .pressButton: spring(Timing.pressButton)
        case .numberSwap: spring(Timing.numberSwap)
        case .morph: spring(Timing.morph)
        case .pairFound: spring(Timing.pairFound)
        case .viaAppear: spring(Timing.viaAppear)
        case .barGrow: spring(Timing.barGrow)
        case .staleDim: Animation.easeInOut(duration: Timing.staleDim)
        // easeOutCubic, como el dibujo de la línea en design-lab/shared/map.js.
        case .routeDraw: Animation.timingCurve(0.33, 1, 0.68, 1, duration: Timing.routeDraw)
        case .ease: ease(0.45)
        }
    }

    /// La alternativa con «Reducir movimiento». `nil` = sin animación.
    static func reduced(_ kind: Kind) -> Animation? {
        switch kind {
        case .press, .pressButton: Animation.easeOut(duration: 0.15)
        case .numberSwap, .morph, .pairFound, .viaAppear, .ease: Animation.easeInOut(duration: Timing.reduced)
        case .barGrow, .staleDim, .routeDraw: nil
        }
    }

    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        reduceMotion ? reduced(kind) : animation(kind)
    }
}

// MARK: - Ayudas que respetan «Reducir movimiento»

extension View {
    /// `.animation(_:value:)` con la curva del sistema y su alternativa si
    /// «Reducir movimiento» está activado.
    func motion<V: Equatable>(_ kind: Motion.Kind, value: V) -> some View {
        modifier(MotionModifier(kind: kind, value: value))
    }

    /// Transición de los minutos (R48): cuenta numérica con muelle; con
    /// «Reducir movimiento», fundido.
    func minutesTransition<V: Equatable>(value: V, countsDown: Bool = true) -> some View {
        modifier(MinutesTransitionModifier(value: value, countsDown: countsDown))
    }

    /// Latido de la vía recién publicada (R2): halo amarillo que late 5 veces.
    /// Con «Reducir movimiento» no late: queda un anillo fijo mientras esté
    /// activo, para que siga viéndose que es nueva (forma, no movimiento).
    func viaPulse(isActive: Bool, cornerRadius: CGFloat = Metrics.Radius.via) -> some View {
        modifier(ViaPulseModifier(isActive: isActive, cornerRadius: cornerRadius))
    }

    /// Háptica de un momento clave. Se dispara cuando cambia `trigger`.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}

/// `withAnimation` con la curva del sistema y su alternativa.
@MainActor
func withMotion<Result>(_ kind: Motion.Kind, reduceMotion: Bool, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(kind, reduceMotion: reduceMotion), body)
}

/// Hápticas de los momentos clave (encargo 3.2).
enum Haptic: Sendable {
    /// Se publica la vía del tren que se mira (R2).
    case platformPublished
    /// El tren que se mira pasa a 2 minutos o menos.
    case trainSoon
    /// La línea pasa a perturbada.
    case disruption
    /// La línea pasa a interrumpida.
    case interruption
    /// Cambio de pestaña o de selección.
    case selection
    /// Empieza o termina el modo trayecto.
    case tripStart
    case tripStop
    /// Emparejado con el servidor.
    case paired

    var feedback: SensoryFeedback {
        switch self {
        case .platformPublished: .impact(weight: .heavy, intensity: 1)
        case .trainSoon: .warning
        case .disruption: .warning
        case .interruption: .error
        case .selection: .selection
        case .tripStart: .start
        case .tripStop: .stop
        case .paired: .success
        }
    }
}

// MARK: - Modificadores

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: Motion.Kind
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}

private struct MinutesTransitionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V
    let countsDown: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
            .animation(Motion.animation(.numberSwap, reduceMotion: reduceMotion), value: value)
    }
}

@MainActor
private struct ViaPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    let cornerRadius: CGFloat
    @State private var lit = false

    init(isActive: Bool, cornerRadius: CGFloat) {
        self.isActive = isActive
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        let ring = Metrics.Size.viaRing
        return content
            // Anillo exterior de 6 pt (B: box-shadow 0 0 0 6px via/.45).
            .background {
                RoundedRectangle(cornerRadius: cornerRadius + ring, style: .continuous)
                    .fill(Palette.via.opacity(lit ? 0.45 : 0))
                    .padding(-ring)
            }
            // Halo difuso (B: 0 0 24px via/.8).
            .shadow(color: Palette.via.opacity(lit ? Metrics.Shadow.viaGlow.opacity : 0),
                    radius: Metrics.Shadow.viaGlow.radius)
            // «Reducir movimiento»: anillo fijo de 2 pt mientras es nueva. En
            // `viaEdge` y no en amarillo: sobre el billete blanco el amarillo
            // no se distingue (1,4:1).
            .overlay {
                if isActive && reduceMotion {
                    RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                        .stroke(Palette.viaEdge, lineWidth: 2)
                        .padding(-3)
                }
            }
            .task(id: isActive) { await pulse() }
    }

    private func pulse() async {
        guard isActive, !reduceMotion else {
            lit = false
            return
        }
        let half = Motion.Timing.viaPulseHalf
        try? await Task.sleep(for: .seconds(Motion.Timing.viaPulseDelay))
        for _ in 0..<Motion.Timing.viaPulseCount {
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: half)) { lit = true }
            try? await Task.sleep(for: .seconds(half))
            withAnimation(.easeInOut(duration: half)) { lit = false }
            try? await Task.sleep(for: .seconds(half))
        }
        lit = false
    }
}
