import SwiftUI

/// El «billete»: la primera salida de cada tramo (sistema.md §7.2). Es lo que
/// se mira de reojo, de pie, con una mano y a contraluz (R1), así que va en
/// una cápsula OPACA que invierte el tema y los minutos mandan (R48).
///
/// Tres columnas: cifra · destino y metadatos · vía y ritmo. Con los tamaños
/// de accesibilidad pasa a dos filas (sistema.md §4.4).
///
/// - «1h46» a partir de una hora, sin «min» (R6).
/// - «En andén» (confirmado por el tren) ≠ «ya» (el contador a cero): el
///   primero pone el billete en verde y quita el ritmo (R15, R16).
/// - Retraso solo si existe, es ≠ 0 y hay hora teórica, con signo (R4, R14).
/// - Longitud del tren si viene (R5). Nada de ocupación: no existe.
/// - Vía real sólida o probable punteada; sin vía, ni hueco (R2, R3, R10).
/// - VoiceOver: una sola frase (R50).
struct DepartureTicket: View {
    let departure: Departure
    let leg: Leg
    var density: BoardDensity = .roomy
    /// La vía se acaba de publicar (latido y «acaba de salir»).
    var isNewPlatform: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ancho mínimo de la cifra para que no baile de 9 a 10 (B: 3,4 em).
    @ScaledMetric(relativeTo: .largeTitle) private var numberMinWidth: CGFloat = 54

    private var moment: DepartureMoment { DepartureMoment(departure) }
    private var atStop: Bool { departure.atStop }
    private var platformState: BoardPlatformState { BoardPlatformState(departure: departure, leg: leg) }

    /// Tinta principal: AAA sobre el billete (o sobre el verde «En andén»).
    private var ink: Color { atStop ? Palette.atStopInk : Palette.ticketInk }
    /// Tinta secundaria («min», hora, longitud).
    private var ink2: Color { atStop ? Palette.atStopInk : Palette.ticketInk2 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                row
            }
        }
        .padding(.vertical, Metrics.Space.ml)
        .padding(.horizontal, Metrics.Size.ticketPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(atStop ? Palette.ok : Palette.ticket,
                    in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardSpeech.sentence(departure, leg: leg, isNewPlatform: isNewPlatform))
    }

    // MARK: - Maquetas

    /// Hasta XXXL: una fila.
    private var row: some View {
        HStack(alignment: .center, spacing: Metrics.Space.ml) {
            number
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                destination
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            side
        }
    }

    /// Tamaños de accesibilidad: arriba cifra y destino; debajo vía, ritmo y
    /// metadatos.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            number
            destination
            HStack(alignment: .center, spacing: Metrics.Space.s) {
                platform
                pace
            }
            .animation(Motion.animation(.viaAppear, reduceMotion: reduceMotion), value: platformState.key)
            meta
        }
    }

    // MARK: - Piezas

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.xs) {
            Text(moment.text)
                .numberFont(density.ticketNumber, scale: moment.numberScale)
                .lineLimit(1)
                .minimumScaleFactor(moment.isWord ? 0.7 : 1)
                .minutesTransition(value: moment.text)
            if let unit = moment.unit {
                Text(unit)
                    .textLevel(.unit)
                    .foregroundStyle(ink2)
            }
        }
        .foregroundStyle(ink)
        .frame(minWidth: numberMinWidth, alignment: .leading)
    }

    /// El destino: lo segundo que se lee. Dos líneas antes de encoger, y
    /// nunca cortado a mitad de palabra con puntos suspensivos (A7).
    private var destination: some View {
        Text(departure.destination.isEmpty ? leg.directionLabel : departure.destination)
            .textLevel(.destination)
            .foregroundStyle(ink)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var meta: some View {
        HStack(spacing: Metrics.Space.sm) {
            if !departure.at.isEmpty {
                Text(departure.at)
            }
            if let delay = BoardText.visibleDelay(departure) {
                Text(Fmt.delay(delay))
                    .fontWeight(delay > 0 ? .bold : .regular)
                    .foregroundStyle(delay > 0 && !atStop ? Palette.ticketWarn : ink2)
            }
            if departure.isCancelled {
                Text("suprimido")
                    .fontWeight(.bold)
                    .foregroundStyle(atStop ? ink : Palette.ticketWarn)
            }
            if let length = departure.length {
                HStack(spacing: 3) {
                    Image(systemName: length.symbol)
                    Text(BoardText.length(length))
                }
            }
        }
        .textLevel(.meta)
        .foregroundStyle(ink2)
        .lineLimit(1)
    }

    private var side: some View {
        VStack(alignment: .trailing, spacing: Metrics.Space.s) {
            platform
            pace
        }
        .animation(Motion.animation(.viaAppear, reduceMotion: reduceMotion), value: platformState.key)
    }

    /// La vía. Cambia de identidad al cambiar de estado para que la caja
    /// nueva ENTRE (escala 0,3 → 1 con muelle; fundido con «Reducir
    /// movimiento»).
    private var platform: some View {
        PlatformBadge(state: platformState,
                      context: atStop ? .ticketAtStop : .ticket,
                      isNew: isNewPlatform)
            .id(platformState.key)
            .transition(platformTransition)
    }

    @ViewBuilder
    private var pace: some View {
        if let pace = moment.pace {
            PaceTag(pace: pace)
        }
    }

    private var platformTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.scale(scale: 0.3).combined(with: .opacity)
    }
}

/// «Corre» / «Anda» / «Con calma» (R16): la respuesta a ¿corro o no corro?
/// Solo en el billete; «En andén» no lleva (R15).
struct PaceTag: View {
    let pace: Pace

    var body: some View {
        Text(BoardText.pace(pace))
            .textLevel(.label)
            .foregroundStyle(pace == .run ? Palette.onAccent : Palette.ticketInk)
            .lineLimit(1)
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 3)
            .background(pace == .run ? Palette.bad : Palette.pace, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Billete: estados") {
    let aparece = PreviewData.board(.viaAparece).legs[0]
    let probable = PreviewData.board(.viaProbable).legs[0]
    let anden = PreviewData.board(.enAnden).legs[0]
    let bus = PreviewData.board(.bus106).legs[0]
    let limite = PreviewData.board(.casosLimite).legs[0]
    let metro = PreviewData.board(.cincoTramos).legs[3]
    ScrollView {
        VStack(spacing: Metrics.Space.m) {
            DepartureTicket(departure: aparece.departures[0], leg: aparece, isNewPlatform: true)
            DepartureTicket(departure: probable.departures[0], leg: probable)
            DepartureTicket(departure: anden.departures[0], leg: anden)
            DepartureTicket(departure: bus.departures[2], leg: bus, density: .regular)
            DepartureTicket(departure: limite.departures[0], leg: limite, density: .compact)
            DepartureTicket(departure: metro.departures[1], leg: metro)
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.surface)
}

#Preview("Billete: letra enorme") {
    let leg = PreviewData.board(.viaProbable).legs[0]
    DepartureTicket(departure: leg.departures[0], leg: leg)
        .padding(Metrics.Space.gutter)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
