import SwiftUI

/// Un tramo: el distintivo de línea fuera, la tarjeta dentro y, cosiéndolos,
/// el hilo vertical que va degradando del color de esta línea al de la
/// siguiente. Ese hilo es lo que convierte una lista de tarjetas en un
/// trayecto que se lee de un vistazo.
struct LegRow: View {
    let leg: Leg
    let nextColor: String?
    let density: ChipDensity
    let onSearchAlternative: () -> Void
    let onTap: () -> Void

    /// Hueco hasta el tramo siguiente. El raíl se mete dentro de él para
    /// llegar al distintivo de abajo.
    private let gap: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            railColumn
            card.padding(.bottom, gap)
        }
    }

    // ---------------- el hilo y el distintivo ----------------

    private var railColumn: some View {
        VStack(spacing: 0) {
            LineBadge(code: leg.lineCode, color: leg.lineColor)

            if let nextColor {
                RoundedRectangle(cornerRadius: Metrics.railWidth / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LineColor.parse(leg.lineColor),
                                     LineColor.parse(nextColor)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: Metrics.railWidth)
                    .frame(maxHeight: .infinity)
                    .opacity(0.85)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: Metrics.railColumn)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    // ---------------- la tarjeta ----------------

    private var card: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            if leg.status.isDisrupted {
                DisruptionNotice(status: leg.status,
                                 onSearchAlternative: onSearchAlternative)
            }

            departures
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.fromName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                if !leg.directionLabel.isEmpty {
                    Text("dirección \(leg.directionLabel)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                } else if leg.mixesDestinations {
                    // Sin sentido guardado se mezclan destinos en la misma
                    // parada, y entonces cada salida dice a dónde va.
                    Text("todos los sentidos")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: leg.mode.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var departures: some View {
        if leg.departures.isEmpty {
            // Pasa de noche, y pasa cuando la línea está cortada de verdad.
            // Los demás tramos siguen funcionando.
            HStack(spacing: 9) {
                Image(systemName: leg.status.isInterrupted ? "nosign" : "moon.stars.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(leg.status.isInterrupted ? Palette.bad : Palette.inkFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.status.isInterrupted ? "Sin circulación" : "Servicio finalizado")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                    Text("no hay más salidas")
                        .overlineStyle()
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        } else {
            // Tira HORIZONTAL. Apiladas, cinco tramos no caben en una pantalla.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(leg.departures.enumerated()), id: \.element.id) { index, dep in
                        DepartureChip(departure: dep, leg: leg,
                                      density: density, isFirst: index == 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled(false)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

#if DEBUG
#Preview("Tramos") {
    let board = PreviewData.fiveLegBoard
    return ScrollView {
        VStack(spacing: 0) {
            ForEach(Array(board.legs.enumerated()), id: \.element.id) { index, leg in
                LegRow(leg: leg,
                       nextColor: index < board.legs.count - 1
                           ? board.legs[index + 1].lineColor : nil,
                       density: ChipDensity(legCount: board.legs.count),
                       onSearchAlternative: {}, onTap: {})
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    .background(Palette.background)
}
#endif
