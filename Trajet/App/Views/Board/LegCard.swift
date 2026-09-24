import SwiftUI

/// La tarjeta de un tramo (sistema.md §7.8): OPACA (el cristal es solo para
/// los controles, ajustes-b.md A1). Cabecera con el distintivo y «parada →
/// parada», el aviso de su línea (R27), el billete de la primera salida y las
/// fichas 2.ª–4.ª. Tocarla abre el detalle.
///
/// - Sin salidas: «Sin circulación» si la línea está cortada, «Servicio
///   finalizado» si no (R25); sin punteado (el punteado es de «probable»).
/// - Estación caída con salidas guardadas: se conservan, atenuadas, con su
///   antigüedad («salidas de hace 3 min»); el estado de la línea es el nuevo.
/// - Estación caída sin nada: «No llega el dato de esta estación» y su error;
///   los demás tramos siguen (R26).
struct LegCard: View {
    let leg: Leg
    var density: BoardDensity = .roomy
    /// Tinta oficial del distintivo (`text_color` del mapa), si se tiene.
    var officialTextColor: String?
    /// Segundos de antigüedad de las salidas conservadas; nil si son de ahora.
    var retainedAge: Double?
    /// El error de la estación de este tramo, si el servidor lo dice.
    var stationError: String?
    /// La vía de la primera salida se acaba de publicar (R2).
    var isNewPlatform: Bool = false
    /// Abre el detalle del tramo.
    var onOpen: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            header
            if let retainedAge {
                retainedNote(retainedAge)
            }
            LineStatusNotice(status: leg.status)
            departures
        }
        .padding(Metrics.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .contentShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .contain)
        // Para los tests de interfaz: «tablero.tramo.0», «tablero.tramo.1»…
        .accessibilityIdentifier("tablero.tramo.\(leg.seq)")
    }

    // MARK: - Cabecera

    private var header: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: Metrics.Space.ml) {
                LineBadge(code: leg.lineCode, color: leg.lineColor, textColor: officialTextColor,
                          size: Metrics.Size.badgeLarge)
                VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                    // Con letra de accesibilidad, una línea más antes de
                    // cortar («Gare d'Argenteui…» no).
                    Text(BoardTitleText.arrow(from: BoardText.legTitle(leg).from, to: BoardText.legTitle(leg).to))
                        .textLevel(.legTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = BoardText.legSubtitle(leg) {
                        Text(subtitle)
                            .textLevel(.legSubtitle)
                            .foregroundStyle(Palette.ink3)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.Size.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre el detalle del tramo")
    }

    private func retainedNote(_ age: Double) -> some View {
        Label {
            Text(BoardText.retained(age: age))
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .textLevel(.footnote)
        .foregroundStyle(Palette.ink3)
    }

    // MARK: - Salidas

    @ViewBuilder
    private var departures: some View {
        if let first = leg.departures.first {
            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                DepartureTicket(departure: first, leg: leg, density: density, isNewPlatform: isNewPlatform)
                    .id(first.id)
                    .transition(ticketTransition)
                let rest = Array(leg.departures.dropFirst().prefix(3))
                if !rest.isEmpty {
                    DepartureChipStrip(departures: rest, leg: leg, density: density)
                }
            }
            .animation(Motion.animation(.morph, reduceMotion: reduceMotion), value: first.id)
            // Salidas conservadas de una estación caída: atenuadas.
            .opacity(retainedAge == nil ? 1 : 0.6)
        } else if let empty = BoardLegEmpty(leg: leg) {
            LegEmptyBox(state: empty, error: stationError)
        }
    }

    /// Cuando la primera salida pasa, el billete de la siguiente sube a su
    /// sitio (identidad por `jid`, R23).
    private var ticketTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.push(from: .trailing)
    }
}

/// Tramo sin salidas (R25) o con la estación caída sin nada guardado (R26).
struct LegEmptyBox: View {
    let state: BoardLegEmpty
    var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Space.ml) {
            Image(systemName: state.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(state == .suspended ? Palette.badText : Palette.ink3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(state.title)
                    .textLevel(.bodyStrong)
                    .foregroundStyle(state == .suspended ? Palette.badText : Palette.ink)
                Text(state.subtitle)
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
                if let error, !error.isEmpty {
                    Text(error)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.Space.ml)
        .padding(.horizontal, Metrics.Size.ticketPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// «Gare Saint-Lazare → Argenteuil» con la flecha en `ink3` (F8).
enum BoardTitleText {
    static func arrow(from: String, to: String) -> AttributedString {
        guard !to.isEmpty else { return AttributedString(from) }
        guard !from.isEmpty else { return AttributedString(to) }
        var arrow = AttributedString(" → ")
        arrow.foregroundColor = Palette.ink3
        return AttributedString(from) + arrow + AttributedString(to)
    }

    /// Un nombre de ruta con «→» dentro («Casa → Trabajo»): la flecha, gris.
    static func route(_ name: String) -> AttributedString {
        var value = AttributedString(name)
        if let range = value.range(of: "→") {
            value[range].foregroundColor = Palette.ink3
        }
        return value
    }
}

#if DEBUG
#Preview("Tarjetas de tramo") {
    let cinco = PreviewData.board(.cincoTramos)
    let limite = PreviewData.board(.casosLimite)
    let cortada = PreviewData.board(.lineaCortada)
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            LegCard(leg: cinco.legs[2], density: .compact, isNewPlatform: true)
            LegCard(leg: cinco.legs[3], density: .compact)
            LegCard(leg: cinco.legs[1], density: .compact)
            LegCard(leg: cortada.legs[0], density: .roomy)
            LegCard(leg: limite.legs[3], density: .regular,
                    stationError: BoardText.stationError(for: limite.legs[3], in: limite))
            LegCard(leg: PreviewData.board(.tranquilo).legs[1], density: .roomy, retainedAge: 184)
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
