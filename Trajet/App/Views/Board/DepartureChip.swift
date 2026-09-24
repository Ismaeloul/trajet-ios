import SwiftUI

/// Una ficha de las salidas 2.ª–4.ª (sistema.md §7.3): contexto, no lo que
/// se mira. La primera salida es el billete (R48).
///
/// - Fila 1: cifra (`chip`) + «min».
/// - Fila 2: el destino si el tramo mezcla destinos (R24; también en
///   compacto) o, si no, la hora prevista.
/// - Fila 3: vía (sin porcentaje), longitud (R5) y retraso con signo (R14).
/// - En compacto (5–6 tramos, R47) se van la hora, la longitud y el retraso;
///   la vía y el destino obligatorio se quedan.
/// - Sin ritmo: solo el billete lo lleva (R16).
/// - VoiceOver: la misma frase completa que el billete (R50).
struct DepartureChip: View {
    let departure: Departure
    let leg: Leg
    var density: BoardDensity = .roomy

    private var moment: DepartureMoment { DepartureMoment(departure) }

    var body: some View {
        let content = BoardChipContent(departure: departure, leg: leg, density: density)
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            number
            if let destination = content.destination {
                ChipDestinationText(destination: destination)
            } else if let time = content.time {
                Text(time)
                    .textLevel(.chipCaption)
                    .foregroundStyle(Palette.ink3)
            }
            details(content)
        }
        .padding(.vertical, Metrics.Space.sm)
        .padding(.horizontal, Metrics.Space.ml)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: Metrics.Size.chipMinWidth)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardSpeech.sentence(departure, leg: leg))
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(moment.text)
                .numberFont(.chip, scale: chipScale)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(moment.isWord ? 0.7 : 1)
                .minutesTransition(value: moment.text)
            if let unit = moment.unit {
                Text(unit)
                    .textLevel(.label)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    /// «En andén» en una ficha a 0,6 (a 0,5 de 24 pt no se lee); el resto
    /// como en el billete.
    private var chipScale: CGFloat {
        switch moment {
        case .atStop: 0.6
        case .now, .inMinutes: moment.numberScale
        }
    }

    @ViewBuilder
    private func details(_ content: BoardChipContent) -> some View {
        let hasDetails = !content.platform.isNone || content.length != nil || content.delay != nil
        if hasDetails {
            HStack(alignment: .center, spacing: Metrics.Space.s) {
                PlatformBadge(state: content.platform, context: .chip, showsPercent: false)
                if let length = content.length {
                    Text(BoardText.length(length))
                        .textLevel(.chipCaption)
                        .foregroundStyle(Palette.ink3)
                }
                if let delay = content.delay {
                    Text(Fmt.delay(delay))
                        .fontWeight(delay > 0 ? .bold : .regular)
                        .textLevel(.chipCaption)
                        .foregroundStyle(delay > 0 ? Palette.warnText : Palette.ink2)
                }
            }
            .lineLimit(1)
        }
    }
}

/// El destino de una ficha cuando el tramo mezcla destinos (R24): la
/// variante más larga que quepa, sin cortar nunca a mitad de palabra
/// (`DestinationAbbreviator`). Si no cabe ni la más corta, dos líneas.
struct ChipDestinationText: View {
    let destination: String

    var body: some View {
        let variants = DestinationAbbreviator.variants(destination)
        let options = variants.isEmpty ? [destination] : variants
        let n = options.count
        ViewThatFits(in: .horizontal) {
            line(options[0])
            line(options[min(1, n - 1)])
            line(options[min(2, n - 1)])
            Text(options[n - 1])
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textLevel(.chipCaption)
        .foregroundStyle(Palette.ink2)
        .accessibilityLabel(destination)
    }

    private func line(_ text: String) -> some View {
        Text(text).lineLimit(1)
    }
}

/// La tira de fichas: tres a la vista (dos con letra enorme), con
/// desplazamiento que encaja en cada ficha y sin indicadores (F17). Cuando
/// una salida pasa, las demás se desplazan (identidad por `jid`, R23).
struct DepartureChipStrip: View {
    let departures: [Departure]
    let leg: Leg
    var density: BoardDensity = .roomy

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 3 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Metrics.Space.sm) {
                ForEach(departures) { departure in
                    DepartureChip(departure: departure, leg: leg, density: density)
                        .containerRelativeFrame(.horizontal, count: columns, span: 1, spacing: Metrics.Space.sm)
                        .transition(.push(from: .trailing))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
            .animation(Motion.animation(.morph, reduceMotion: reduceMotion), value: departures.map(\.id))
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}

#if DEBUG
#Preview("Fichas: densidades y mezcla") {
    let mezcla = PreviewData.board(.destinosMezclados).legs[0]
    let tranquilo = PreviewData.board(.tranquilo).legs[1]
    let seis = PreviewData.board(.seisTramos).legs[2]
    let limite = PreviewData.board(.casosLimite).legs[0]
    ScrollView {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            Text("Destinos mezclados (R24)").textLevel(.kicker)
            DepartureChipStrip(departures: Array(mezcla.departures.dropFirst()), leg: mezcla)
            Text("Holgado, vía probable y longitud").textLevel(.kicker)
            DepartureChipStrip(departures: Array(tranquilo.departures.dropFirst()), leg: tranquilo)
            Text("Compacto (R47)").textLevel(.kicker)
            DepartureChipStrip(departures: Array(seis.departures.dropFirst()), leg: seis, density: .compact)
            Text("1 hora justa").textLevel(.kicker)
            DepartureChipStrip(departures: Array(limite.departures.dropFirst()), leg: limite, density: .regular)
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.surface)
}
#endif
