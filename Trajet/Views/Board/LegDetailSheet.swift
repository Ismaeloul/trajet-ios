import SwiftUI

/// El tramo entero, sentado.
///
/// En el tablero cada salida cabe en un chip porque allí solo hay dos
/// segundos. Aquí hay tiempo: se enseña todo lo que la API da de cada paso,
/// incluido por qué la previsión dice la vía que dice.
struct LegDetailSheet: View {
    let leg: Leg
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    head

                    if leg.status.isDisrupted {
                        messages
                    }

                    if leg.departures.isEmpty {
                        Text(leg.status.isInterrupted
                             ? "La línea no está circulando."
                             : "No quedan más salidas hoy.")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.inkMuted)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(leg.departures) { dep in
                                DepartureDetailRow(departure: dep, leg: leg)
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(Palette.background)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var head: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(code: leg.lineCode, color: leg.lineColor, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(leg.fromName)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(leg.directionLabel.isEmpty
                     ? leg.lineMode : "\(leg.lineMode) · dirección \(leg.directionLabel)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Los avisos, en español y en francés. Aquí sí caben los dos: sirve para
    /// comprobar la traducción cuando dice algo raro.
    private var messages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(leg.status.label).overlineStyle(
                leg.status.isInterrupted ? Palette.bad : Palette.warn)

            ForEach(Array(leg.status.messages.enumerated()), id: \.offset) { i, fr in
                VStack(alignment: .leading, spacing: 5) {
                    let es = i < leg.status.messagesEs.count ? leg.status.messagesEs[i] : nil
                    if let es, !es.isEmpty {
                        Text(es)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.9))
                    }
                    Text(fr)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                        .italic()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if leg.status.planned > 0 {
                Text("Además hay \(leg.status.planned) aviso(s) de obras con fecha futura, que no afectan a hoy.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(18)
    }
}

/// Una salida, con todo lo que se sabe de ella.
struct DepartureDetailRow: View {
    let departure: Departure
    let leg: Leg

    private var moment: DepartureMoment { DepartureMoment(departure) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(moment.text)
                    .font(moment.isWord ? .system(size: 20, weight: .heavy, design: .rounded)
                                        : TypeScale.minutes(32))
                    .foregroundStyle(Palette.ink)
                if let unit = moment.unit {
                    Text(unit).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
                if let pace = moment.pace {
                    Label(pace.spoken, systemImage: pace.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(pace.color)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if leg.showsPlatform {
                    if let number = departure.platform, !number.isEmpty {
                        PlatformBadge(kind: .real(number, isNew: departure.platformNew))
                    } else if let guess = departure.guess {
                        PlatformBadge(kind: .guessed(guess))
                    }
                }
            }

            // Por qué la previsión dice esa vía. Sin esto es un número mágico.
            if leg.showsPlatform, !departure.hasRealPlatform, let guess = departure.guess {
                Text("Sale por la \(guess.platform) el \(guess.percent) % de las veces (\(guess.samples) observaciones, \(guess.why)).")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowFacts(facts: facts)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(16)
    }

    private var facts: [String] {
        var out: [String] = []
        if !departure.destination.isEmpty { out.append(departure.destination) }
        if !departure.at.isEmpty { out.append("sale \(departure.at)") }
        if let delay = departure.realDelay { out.append(Fmt.delay(delay)) }
        if let length = departure.length { out.append(length.label) }
        if let train = departure.train, !train.isEmpty { out.append("tren \(train)") }
        if departure.atStop { out.append("parado en el andén") }
        return out
    }
}

/// Etiquetas sueltas que se reparten en las líneas que hagan falta.
struct FlowFacts: View {
    let facts: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) { chips }
        }
        .scrollIndicators(.hidden)
    }

    private var chips: some View {
        ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
            Text(fact)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.surfaceHi))
                .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview("Detalle del tramo") {
    LegDetailSheet(leg: PreviewData.fiveLegBoard.legs[2])
}
#endif
