import SwiftUI

/// El tablero sin nada que enseñar porque no hay rutas (o la ruta no tiene
/// tramos). Dice qué hacer, no solo que está vacío (R53, sistema.md §7.18).
struct EmptyBoardView: View {
    enum Kind: Equatable, Sendable {
        /// El servidor aún no tiene rutas (`BoardEmptyV1`).
        case noRoutes
        /// Hay ruta, pero sin tramos.
        case noLegs
    }

    let kind: Kind
    /// Lleva a Rutas (donde está el planificador).
    var onCreateRoute: () -> Void = {}

    var body: some View {
        MessageStateView(symbol: symbol, title: title, message: message) {
            Button(action: onCreateRoute) {
                Label(buttonTitle, systemImage: kind == .noRoutes ? "plus" : "pencil")
            }
            .filledButton(.primary)
        }
    }

    private var symbol: String {
        switch kind {
        case .noRoutes: "point.topleft.down.to.point.bottomright.curvepath"
        case .noLegs: "square.dashed"
        }
    }

    private var title: String {
        switch kind {
        case .noRoutes: "Todavía no hay ninguna ruta"
        case .noLegs: "Esta ruta no tiene tramos"
        }
    }

    private var message: String {
        switch kind {
        case .noRoutes:
            "Ve a Rutas, di de dónde a dónde vas y guarda el trayecto que uses de verdad. El tablero enseñará la que toque según el día y la hora."
        case .noLegs:
            "Edítala en Rutas y añádele al menos un tramo."
        }
    }

    private var buttonTitle: String {
        switch kind {
        case .noRoutes: "Crear una ruta"
        case .noLegs: "Ir a Rutas"
        }
    }
}

/// Cargando por primera vez sin nada en disco: la forma de dos tarjetas, para
/// que se vea dónde va a estar cada cosa antes de que llegue (R53). Quieta:
/// sin parpadeo (la v1 parpadeaba siempre, también con «Reducir
/// movimiento»).
struct BoardSkeleton: View {
    var body: some View {
        VStack(spacing: Metrics.Space.gutter) {
            ForEach(0..<2, id: \.self) { _ in
                card
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando el tablero")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(spacing: Metrics.Space.ml) {
                RoundedRectangle(cornerRadius: Metrics.Size.badgeLarge * Metrics.Radius.badgeRatio, style: .continuous)
                    .fill(Palette.surfaceHi)
                    .frame(width: Metrics.Size.badgeLarge, height: Metrics.Size.badgeLarge)
                VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                    Text("Gare Saint-Lazare → Argenteuil")
                        .textLevel(.legTitle)
                    Text("dirección Ermont - Eaubonne")
                        .textLevel(.legSubtitle)
                }
                .foregroundStyle(Palette.ink3)
            }
            RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous)
                .fill(Palette.surfaceHi)
                .frame(height: 84)
            HStack(spacing: Metrics.Space.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous)
                        .fill(Palette.surfaceHi)
                        .frame(height: 58)
                }
            }
        }
        .padding(Metrics.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

#if DEBUG
#Preview("Vacío, sin tramos y cargando") {
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            EmptyBoardView(kind: .noRoutes)
            EmptyBoardView(kind: .noLegs)
            BoardSkeleton()
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
