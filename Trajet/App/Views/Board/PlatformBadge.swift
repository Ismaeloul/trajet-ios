import SwiftUI

/// La vía de una salida (sistema.md §7.4).
///
/// - **Real**: caja SÓLIDA amarilla con «Vía» y el número (R10). Si es
///   nueva (R2), late 5 veces con el halo; con «Reducir movimiento», anillo
///   fijo (R51).
/// - **Probable**: recuadro PUNTEADO, sin relleno, con «probable» + número
///   (+ «90 %» en el billete). Nunca lleva «Vía» ni caja rellena, y la real
///   nunca va punteada: se distinguen en gris y en monocromo (R10). El
///   punteado queda reservado para esto.
/// - **Ninguna**: nada, ni hueco (R2, R3). Lo decide `BoardPlatformState`.
struct PlatformBadge: View {
    /// Sobre qué fondo va: decide el color del texto de la probable.
    enum Context: Sendable {
        /// Dentro del billete (fondo invertido).
        case ticket
        /// Dentro del billete verde «En andén».
        case ticketAtStop
        /// En una ficha 2.ª–4.ª.
        case chip
        /// En el detalle del tramo.
        case detail
    }

    let state: BoardPlatformState
    var context: Context = .chip
    /// Vía recién publicada: latido (o anillo fijo con «Reducir movimiento»).
    var isNew: Bool = false
    /// El porcentaje de la probable. Si el ancho no da, se quita antes que la
    /// palabra (`ViewThatFits`); en las fichas no va nunca (ajustes-b.md A5).
    var showsPercent: Bool = true

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .real(let platform):
            real(platform)
        case .probable(let guess):
            probable(guess)
        }
    }

    // MARK: - Real

    private func real(_ platform: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.via, style: .continuous)
        let spoken: String = isNew ? "Acaba de salir la vía \(platform)" : "Vía \(platform)"
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.xs) {
            Text("Vía")
                .textLevel(.label)
            Text(platform)
                .numberFont(.via)
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(Palette.viaInk)
        .padding(.vertical, Metrics.Space.xs)
        .padding(.horizontal, 9)
        .background(Palette.via, in: shape)
        .overlay { shape.strokeBorder(Palette.viaEdge, lineWidth: Metrics.Size.hairline) }
        .viaPulse(isActive: isNew)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: - Probable

    @ViewBuilder
    private func probable(_ guess: PlatformGuess) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.via, style: .continuous)
        let spoken = BoardSpeech.platform(.probable(guess), isNew: false) ?? ""
        Group {
            if showsPercent {
                ViewThatFits(in: .horizontal) {
                    probableContent(guess, withPercent: true)
                    probableContent(guess, withPercent: false)
                }
            } else {
                probableContent(guess, withPercent: false)
            }
        }
        .foregroundStyle(ink)
        .padding(.vertical, Metrics.Space.xs)
        .padding(.horizontal, 9)
        .overlay {
            shape.strokeBorder(ink, style: StrokeStyle(lineWidth: Metrics.Size.dashWidth,
                                                       dash: Metrics.Size.dash))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.capitalizedFirst(spoken))
    }

    private func probableContent(_ guess: PlatformGuess, withPercent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.xs) {
            Text("probable")
                .textLevel(.label)
            Text(guess.platform)
                .numberFont(.via)
                .lineLimit(1)
            if withPercent {
                Text(BoardText.percent(guess.percent))
                    .textLevel(.label)
            }
        }
        .fixedSize()
    }

    /// El color del texto (y del punteado) de la probable: el del sitio.
    private var ink: Color {
        switch context {
        case .ticket: Palette.ticketInk
        case .ticketAtStop: Palette.atStopInk
        case .chip, .detail: Palette.ink2
        }
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + String(text.dropFirst())
    }
}

#if DEBUG
#Preview("Vía: real, nueva, probable") {
    let guess = PlatformGuess(platform: "21", share: 0.9, samples: 20, basis: "mision",
                              why: "por el número de tren")
    VStack(alignment: .leading, spacing: Metrics.Space.l) {
        HStack(spacing: Metrics.Space.ml) {
            PlatformBadge(state: .real("21"), context: .ticket)
            PlatformBadge(state: .real("11"), context: .ticket, isNew: true)
            PlatformBadge(state: .probable(guess), context: .ticket)
        }
        .padding(Metrics.Size.ticketPadding)
        .background(Palette.ticket, in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        HStack(spacing: Metrics.Space.ml) {
            PlatformBadge(state: .real("9"), context: .chip)
            PlatformBadge(state: .probable(guess), context: .chip, showsPercent: false)
            PlatformBadge(state: .none, context: .chip)
            Text("← sin vía: nada").textLevel(.footnote).foregroundStyle(Palette.ink3)
        }
        .padding(Metrics.Space.ml)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
    }
    .padding(Metrics.Space.gutter)
    .background(Palette.bg)
}
#endif
