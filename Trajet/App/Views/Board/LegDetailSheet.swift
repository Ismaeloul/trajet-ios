import SwiftUI

/// El detalle de un tramo (sistema.md §7.13, F24): hoja media/grande que se
/// abre al tocar la tarjeta. Lee el tramo vivo del tablero, así que se
/// actualiza con cada refresco.
///
/// - Los avisos, en español Y en francés, para comprobar la traducción (R27).
/// - Las obras con fecha futura, aunque la línea esté normal (R28).
/// - Cada salida: momento, ritmo con palabras, vía y, si es probable, POR QUÉ
///   («Sale por la 21 el 90 % de las veces (20 observaciones, por el número
///   de tren).», R49), y sus etiquetas (destino, hora, retraso, longitud,
///   tren, en el andén).
/// - Sin salidas: «La línea no está circulando.» / «No quedan más salidas
///   hoy.» (R25).
struct LegDetailSheet: View {
    let legSeq: Int

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                ScrollView {
                    content(now: timeline.date)
                        .padding(.horizontal, Metrics.Space.gutter)
                        .padding(.vertical, Metrics.Space.l)
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var leg: Leg? {
        services.board.board?.legs.first { $0.seq == legSeq }
    }

    private var navigationTitle: String {
        guard let leg else { return "Tramo" }
        return leg.lineName.isEmpty ? "Línea \(leg.lineCode)" : "Línea \(leg.lineName)"
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let leg, let board = services.board.board {
            let store = services.board
            let live = !store.isStale(now: now)
            VStack(alignment: .leading, spacing: Metrics.Space.gutter) {
                header(leg)
                if store.isRetained(seq: leg.seq) {
                    Label(BoardText.retained(age: store.legAge(seq: leg.seq, now: now) ?? 0),
                          systemImage: "clock.arrow.circlepath")
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                notices(leg, disruptionsOK: board.disruptionsOK)
                departures(leg, board: board, live: live, now: now)
            }
        } else {
            MessageStateView(symbol: "questionmark.circle", title: "Este tramo ya no está en el tablero",
                             message: "Puede que la ruta haya cambiado. Cierra y vuelve a mirar.")
        }
    }

    // MARK: - Cabecera

    private func header(_ leg: Leg) -> some View {
        let title = BoardText.legTitle(leg)
        let direction = BoardText.legSubtitle(leg)
        let modeLine = [leg.lineMode, direction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: Metrics.Space.ml) {
            LineBadge(code: leg.lineCode, color: leg.lineColor, size: 50)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(BoardTitleText.arrow(from: title.from, to: title.to))
                    .textLevel(.routeTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !modeLine.isEmpty {
                    Text(modeLine)
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Avisos (R8, R27, R28)

    @ViewBuilder
    private func notices(_ leg: Leg, disruptionsOK: Bool) -> some View {
        let status = leg.status
        let bilingual = BoardNotice.bilingual(status)
        let planned = BoardText.plannedWorks(status.planned, alongsideNotice: status.level > 0 || !bilingual.isEmpty)
        if status.level > 0 || !bilingual.isEmpty || planned != nil || !disruptionsOK {
            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                if status.level > 0 || !bilingual.isEmpty {
                    noticeHeader(status)
                    ForEach(Array(bilingual.enumerated()), id: \.offset) { _, message in
                        BilingualMessage(message: message)
                    }
                }
                if let planned {
                    Label(planned, systemImage: "calendar.badge.clock")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                }
                if !disruptionsOK {
                    DisruptionsUnreadNotice()
                }
            }
            .padding(Metrics.Size.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private func noticeHeader(_ status: LegStatus) -> some View {
        let interrupted = status.level >= 2
        let color = status.level == 0 ? Palette.ink2 : (interrupted ? Palette.badText : Palette.warnText)
        return HStack(spacing: Metrics.Space.s) {
            Image(systemName: interrupted ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.level == 0 ? Palette.ink3 : (interrupted ? Palette.badText : Palette.warn))
                .accessibilityHidden(true)
            Text(BoardNotice.title(level: status.level))
                .textLevel(.noticeTitle)
                .foregroundStyle(color)
            Spacer(minLength: Metrics.Space.sm)
            if status.awaitingTranslation {
                TranslatingLabel()
            }
        }
    }

    // MARK: - Salidas (R49, R50)

    @ViewBuilder
    private func departures(_ leg: Leg, board: Board, live: Bool, now: Date) -> some View {
        if leg.departures.isEmpty {
            if let empty = BoardLegEmpty(leg: leg) {
                MessageStateView(symbol: empty.symbol,
                                 tint: empty == .suspended ? Palette.badText : Palette.ink3,
                                 title: empty.detail,
                                 message: BoardText.stationError(for: leg, in: board))
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(leg.departures.enumerated()), id: \.element.id) { index, departure in
                    if index > 0 {
                        Divider()
                    }
                    let isNew = index == 0 && BoardPlatformState.isNew(
                        departure: departure, leg: leg, event: services.board.lastPlatformEvent,
                        receivedAt: board.receivedAt, now: now, live: live)
                    DetailDepartureRow(departure: departure, leg: leg, isNewPlatform: isNew)
                }
            }
            .padding(.horizontal, Metrics.Size.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }
}

/// Un mensaje en los dos idiomas (R27): el español arriba (si ya está) y el
/// francés original debajo, en cursiva y con voz francesa.
private struct BilingualMessage: View {
    let message: BoardNotice.Bilingual

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            if let spanish = message.spanish {
                NoticeMessageText(text: spanish, isFrench: false)
            } else {
                Text("Aún sin traducir")
                    .textLevel(.label)
                    .foregroundStyle(Palette.ink3)
            }
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text("Original en francés")
                    .textLevel(.label)
                    .foregroundStyle(Palette.ink3)
                NoticeMessageText(text: message.french, isFrench: true)
            }
        }
        .padding(.vertical, Metrics.Space.xs)
    }
}

/// Una salida en el detalle.
private struct DetailDepartureRow: View {
    let departure: Departure
    let leg: Leg
    var isNewPlatform: Bool = false

    private var moment: DepartureMoment { DepartureMoment(departure) }
    private var platform: BoardPlatformState { BoardPlatformState(departure: departure, leg: leg) }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Space.ml) {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(moment.text)
                        .numberFont(.chip, scale: moment.isWord ? 0.7 : moment.numberScale)
                        .foregroundStyle(departure.atStop ? Palette.okText : Palette.ink)
                        .lineLimit(1)
                        .minutesTransition(value: moment.text)
                    if let unit = moment.unit {
                        Text(unit)
                            .textLevel(.label)
                            .foregroundStyle(Palette.ink3)
                    }
                }
                if let pace = moment.pace {
                    Label(pace.spoken, systemImage: pace.symbol)
                        .textLevel(.footnote)
                        .foregroundStyle(pace.color)
                }
            }
            .frame(minWidth: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: Metrics.Space.s) {
                PlatformBadge(state: platform, context: .detail, isNew: isNewPlatform)
                if let guess = platform.guess {
                    Text(BoardText.probableExplanation(guess))
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BoardTagFlow(spacing: Metrics.Space.s, lineSpacing: Metrics.Space.xs) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        DetailTag(text: tag.text, style: tag.style)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.Space.ml)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var text = BoardSpeech.sentence(departure, leg: leg, isNewPlatform: isNewPlatform)
        if let guess = platform.guess {
            text += " " + BoardText.probableExplanation(guess)
        }
        if let train = departure.train, !train.isEmpty {
            text += " Tren \(train)."
        }
        return text
    }

    private var tags: [DetailTagModel] {
        var out: [DetailTagModel] = []
        if !departure.destination.isEmpty { out.append(DetailTagModel(text: departure.destination, style: .strong)) }
        if !departure.at.isEmpty { out.append(DetailTagModel(text: "sale \(departure.at)", style: .plain)) }
        if let delay = BoardText.delay(departure) {
            out.append(DetailTagModel(text: delay, style: (BoardText.visibleDelay(departure) ?? 0) > 0 ? .warn : .plain))
        }
        if departure.isCancelled { out.append(DetailTagModel(text: "suprimido", style: .bad)) }
        if let length = departure.length { out.append(DetailTagModel(text: length.label, style: .plain)) }
        if let train = departure.train, !train.isEmpty { out.append(DetailTagModel(text: "tren \(train)", style: .plain)) }
        if departure.atStop { out.append(DetailTagModel(text: "parado en el andén", style: .ok)) }
        return out
    }
}

private struct DetailTagModel: Equatable {
    enum Style: Equatable { case plain, strong, warn, bad, ok }
    let text: String
    let style: Style
}

private struct DetailTag: View {
    let text: String
    let style: DetailTagModel.Style

    var body: some View {
        Text(text)
            .textLevel(style == .strong ? .bodyStrong : .footnote)
            .foregroundStyle(color)
            .lineLimit(2)
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 3)
            .background(Palette.surfaceHi, in: Capsule())
    }

    private var color: Color {
        switch style {
        case .plain: Palette.ink2
        case .strong: Palette.ink
        case .warn: Palette.warnText
        case .bad: Palette.badText
        case .ok: Palette.okText
        }
    }
}

/// Etiquetas que saltan de línea cuando no caben (iOS 16 `Layout`).
struct BoardTagFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width.isFinite ? width : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if x > bounds.minX, x + width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Detalle: metro cortado, aviso sin traducir") {
    DemoServicesPreview("cincoTramos") {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                LegDetailSheet(legSeq: 3)
            }
    }
}

#Preview("Detalle: vía probable explicada") {
    DemoServicesPreview("viaProbable") {
        LegDetailSheet(legSeq: 0)
    }
}

#Preview("Detalle: obras futuras y avisos sin leer") {
    DemoServicesPreview("casosLimite") {
        LegDetailSheet(legSeq: 2)
    }
}
#endif
