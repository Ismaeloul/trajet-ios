import SwiftUI

/// Cuánto sitio le toca a cada salida.
///
/// Es lo que permite que quepan de uno a seis tramos sin que se pisen: con dos
/// tramos las salidas van holgadas, con seis se aprietan. Lo que nunca se
/// encoge por debajo de lo legible es la cifra de minutos.
enum ChipDensity {
    case roomy      // 1–2 tramos
    case normal     // 3–4 tramos
    case compact    // 5–6 tramos

    init(legCount: Int) {
        switch legCount {
        case ...2: self = .roomy
        case 3...4: self = .normal
        default: self = .compact
        }
    }

    var minuteSize: CGFloat {
        switch self {
        case .roomy: 34
        case .normal: 30
        case .compact: 26
        }
    }

    /// Las palabras («En andén», «ya») necesitan menos cuerpo que las cifras.
    var wordSize: CGFloat { minuteSize * 0.52 }

    /// Con seis tramos la segunda línea del chip estorba más que informa.
    var showsSecondLine: Bool { self != .compact }

    var isCompact: Bool { self == .compact }

    var padding: CGFloat {
        switch self {
        case .roomy: 11
        case .normal: 10
        case .compact: 8
        }
    }
}

/// Una salida dentro de la tira horizontal.
///
/// La jerarquía está decidida por el momento de uso: de pie, dos segundos, una
/// mano. Lo primero y lo más grande son los minutos; todo lo demás se lee solo
/// si sobra tiempo.
struct DepartureChip: View {
    let departure: Departure
    let leg: Leg
    let density: ChipDensity
    /// La primera salida es la que se mira; las demás son contexto.
    let isFirst: Bool

    private var moment: DepartureMoment { DepartureMoment(departure) }

    var body: some View {
        HStack(spacing: density.isCompact ? 7 : 9) {
            timeBlock

            if let platform = platformBadge {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: 34)
                platform
            }
        }
        .padding(.horizontal, density.padding)
        .padding(.vertical, density.isCompact ? 7 : 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.surfaceHi.opacity(isFirst ? 1 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isFirst ? Palette.hairlineHi : Palette.hairline, lineWidth: 1)
        )
        .opacity(isFirst ? 1 : 0.82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    // ---------------- los minutos ----------------

    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(moment.text)
                    .font(moment.isWord
                          ? .system(size: density.wordSize, weight: .heavy, design: .rounded)
                          : TypeScale.minutes(density.minuteSize))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                if let unit = moment.unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }

                if let pace = moment.pace, isFirst || !density.isCompact {
                    Image(systemName: pace.symbol)
                        .font(.system(size: density.isCompact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(pace.color)
                        .accessibilityHidden(true)
                }
            }

            if density.showsSecondLine, let secondary = secondaryText {
                Text(secondary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// La segunda línea del chip dice lo que aún aporta algo:
    ///  · el destino, pero solo si el tramo mezcla varios (línea sin sentido)
    ///  · el retraso, que en metro y bus no existe porque no hay hora teórica
    ///  · si el tren es corto o largo, que es lo único real que hay sobre
    ///    cuánta gente vas a encontrarte (ocupación NO la da la API)
    private var secondaryText: String? {
        var bits: [String] = []
        if leg.mixesDestinations, !departure.destination.isEmpty {
            bits.append(departure.destination)
        }
        if let delay = departure.realDelay {
            bits.append(Fmt.delay(delay))
        }
        if bits.isEmpty, let length = departure.length {
            bits.append(length.label)
        }
        if bits.isEmpty, !departure.at.isEmpty {
            bits.append(departure.at)
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    // ---------------- la vía ----------------

    /// En metro, bus y tranvía no hay hueco de vía: no lo publican jamás
    /// (0 de ~600 pasos medidos). Reservarlo sería un vacío permanente en la
    /// fila más importante de la pantalla.
    @ViewBuilder
    private var platformBadge: some View {
        if leg.showsPlatform {
            if let number = departure.platform, !number.isEmpty {
                PlatformBadge(kind: .real(number, isNew: departure.platformNew),
                              compact: density.isCompact)
            } else if let guess = departure.guess {
                PlatformBadge(kind: .guessed(guess), compact: density.isCompact)
            }
        }
    }

    // ---------------- lo que oye VoiceOver ----------------

    private var spokenLabel: String {
        var parts: [String] = [moment.spoken]
        if leg.mixesDestinations, !departure.destination.isEmpty {
            parts.append("hacia \(departure.destination)")
        }
        if let delay = departure.realDelay {
            parts.append(delay > 0 ? "\(delay) minutos de retraso"
                                   : "\(-delay) minutos de adelanto")
        }
        if leg.showsPlatform {
            if let number = departure.platform, !number.isEmpty {
                parts.append(departure.platformNew
                             ? "acaba de salir la vía \(number)" : "vía \(number)")
            } else if let guess = departure.guess {
                parts.append("vía \(guess.platform) probable, \(guess.percent) por ciento")
            }
        }
        if let length = departure.length { parts.append(length.label) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Salidas") {
    let board = PreviewData.fiveLegBoard
    let rer = board.legs[2]
    let metro = board.legs[3]
    let bus = board.legs[0]

    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ForEach([ChipDensity.roomy, .normal, .compact], id: \.minuteSize) { density in
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(describing: density)).overlineStyle()
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(rer.departures.enumerated()),
                                    id: \.element.id) { index, dep in
                                DepartureChip(departure: dep, leg: rer,
                                              density: density, isFirst: index == 0)
                            }
                            ForEach(metro.departures) { dep in
                                DepartureChip(departure: dep, leg: metro,
                                              density: density, isFirst: false)
                            }
                            ForEach(bus.departures) { dep in
                                DepartureChip(departure: dep, leg: bus,
                                              density: density, isFirst: false)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding()
    }
    .background(Palette.background)
}
#endif
