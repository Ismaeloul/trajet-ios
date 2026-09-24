import SwiftUI
import UIKit

/// La tarjeta del modo trayecto, abajo del mapa (docs/diseno/sistema.md
/// §7.14): panel de cristal con
///  - «4 min a pie hasta Saint-Lazare» (minutos de MKDirections, no de la API),
///  - el billete opaco del próximo tren del tramo que toca,
///  - «Empezar trayecto» ↔ «Parar trayecto» (morph y háptica),
///  - el pie: qué hace el trayecto y cuándo se apaga.
///
/// El permiso de ubicación se explica ANTES de que iOS lo pida: al tocar
/// «Empezar trayecto» sin haberlo contestado nunca. Si se deniega, el
/// trayecto sigue sin GPS (sin llegada automática, solo el tiempo máximo).
struct TripCard: View {
    let routeID: Int
    let walking: WalkingGuide
    /// El mapa trae su licencia (IDFM, OpenStreetMap): se enlaza en el pie.
    let hasLicense: Bool
    let onShowLicense: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph
    @State private var explainingLocation = false
    @State private var starts = 0
    @State private var stops = 0

    var body: some View {
        let trip = services.trip
        CristalGroup(spacing: Metrics.Space.sm) {
            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                // Si terminó solo (quizá con la app en segundo plano, cuando
                // el aviso efímero no se vio), se dice aquí un rato.
                if let reason = trip.endReason, reason != .manual, let endedAt = trip.endedAt,
                   Date().timeIntervalSince(endedAt) < TripCardText.endedNoteWindow {
                    endedNote(reason, at: endedAt)
                }
                walkingLine
                trainSection
                tripButton
                footer
            }
            .padding(Metrics.Size.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cristal(.panel, cornerRadius: Metrics.Radius.bar)
        }
        .padding(.horizontal, Metrics.Space.gutter)
        .padding(.bottom, Metrics.Space.sm)
        .animation(Motion.animation(.morph, reduceMotion: reduceMotion), value: trip.state)
        .haptic(.tripStart, trigger: starts)
        .haptic(.tripStop, trigger: stops)
        .alert("Ubicación durante el trayecto", isPresented: $explainingLocation) {
            Button("Continuar") { start(askLocation: true) }
            Button("Sin ubicación") { start(askLocation: false) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(TripCardText.locationExplanation(maxMinutes: services.tripSettings.maxMinutes))
        }
    }

    // MARK: - Terminado

    private func endedNote(_ reason: TripEndReason, at endedAt: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.sm) {
            Image(systemName: reason == .arrived ? "checkmark.circle.fill" : "stop.circle")
                .foregroundStyle(reason == .arrived ? Palette.okText : Palette.ink2)
                .accessibilityHidden(true)
            Text(TripCardText.ended(reason, at: endedAt))
                .textLevel(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                services.trip.acknowledgeEnd()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.ink3)
            }
            .hitTarget()
            .accessibilityLabel("Cerrar aviso")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - A pie

    @ViewBuilder
    private var walkingLine: some View {
        let authorization = services.trip.location.authorization
        if let minutes = walking.minutes, let target = walking.target {
            Label {
                Text(TripCardText.walking(minutes: minutes, target: target, insideMinutes: walking.insideMinutes))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "figure.walk")
            }
            .textLevel(.callout)
            .foregroundStyle(Palette.ink2)
        } else if authorization == .notDetermined {
            Button {
                let location = services.trip.location
                Task {
                    let answer = await location.requestWhenInUse()
                    if answer.allowsTrip { location.requestCurrentLocation() }
                }
            } label: {
                Label("Ver el camino a pie hasta la estación", systemImage: "figure.walk")
                    .textLevel(.callout)
            }
            .tint(Palette.accent)
            .hitTarget()
            .accessibilityHint("Pide permiso de ubicación para calcular el camino andando")
        }
    }

    // MARK: - El tren que toca

    @ViewBuilder
    private var trainSection: some View {
        let trip = services.trip
        let legSeq = trip.activeRouteID == routeID ? trip.currentLegSeq : nil
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let model = TripCardModel.make(board: services.board.board, routeID: routeID,
                                              legSeq: legSeq, now: context.date) {
                VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                    TripCardLegHeader(model: model)
                    if let cancelled = model.cancelledBefore {
                        Label("El de las \(cancelled.at), cancelado", systemImage: "xmark.circle")
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.badText)
                    }
                    if let departure = model.departure {
                        TripCardTicket(leg: model.leg, departure: departure)
                            .opacity(model.isStale ? Metrics.Opacity.stale : 1)
                            .saturation(model.isStale ? Metrics.Opacity.staleSaturation : 1)
                            .motion(.staleDim, value: model.isStale)
                    } else {
                        Text("Sin salidas de este tramo ahora mismo")
                            .textLevel(.callout)
                            .foregroundStyle(Palette.ink2)
                    }
                    if model.isStale, let age = services.board.ageSeconds(now: context.date) {
                        Label("Dato sin actualizar · \(Fmt.age(age))", systemImage: "clock.badge.exclamationmark")
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.warnText)
                    }
                }
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        let board = services.board
        if board.isLoading || board.isShowingOtherRoute {
            HStack(spacing: Metrics.Space.sm) {
                ProgressView()
                Text("Cargando los trenes de esta ruta…")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            }
        } else {
            Text("Todavía no hay trenes de esta ruta: se piden al empezar el trayecto o al abrir el tablero.")
                .textLevel(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Empezar / parar

    @ViewBuilder
    private var tripButton: some View {
        let trip = services.trip
        if trip.isActive {
            Button {
                stop()
            } label: {
                Label("Parar trayecto", systemImage: "stop.fill")
            }
            .filledButton(.danger)
            .cristalID("trip-button", in: morph)
        } else if trip.isAskingPermission {
            Button {} label: {
                HStack(spacing: Metrics.Space.sm) {
                    ProgressView()
                        .tint(Palette.onAccent)
                    Text("Esperando el permiso de ubicación…")
                }
            }
            .filledButton(.primary)
            .disabled(true)
            .cristalID("trip-button", in: morph)
        } else {
            Button {
                startTapped()
            } label: {
                Label("Empezar trayecto", systemImage: "play.fill")
            }
            .filledButton(.primary)
            .cristalID("trip-button", in: morph)
            .accessibilityHint("Sigue la ruta en segundo plano hasta que llegues")
        }
    }

    private func startTapped() {
        if services.trip.location.authorization == .notDetermined {
            explainingLocation = true
        } else {
            start(askLocation: true)
        }
    }

    private func start(askLocation: Bool) {
        starts += 1
        let trip = services.trip
        let id = routeID
        Task { await trip.start(routeID: id, askLocation: askLocation) }
    }

    private func stop() {
        stops += 1
        let trip = services.trip
        Task { await trip.stop(reason: .manual) }
    }

    // MARK: - Pie

    @ViewBuilder
    private var footer: some View {
        let trip = services.trip
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            if trip.isActive {
                if trip.usesLocation {
                    Text(TripCardText.activeFooter(distance: trip.session?.distanceToDestination))
                } else {
                    Text(TripCardText.noLocationFooter(deadline: trip.deadline))
                    if trip.location.authorization == .denied {
                        Button("Dar permiso de ubicación en Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .tint(Palette.accent)
                    }
                }
            } else {
                Text(TripCardText.idleFooter(maxMinutes: services.tripSettings.maxMinutes))
            }
            if hasLicense {
                Button("Datos del mapa: IDFM · OpenStreetMap") {
                    onShowLicense()
                }
                .tint(Palette.ink3)
            }
        }
        .textLevel(.footnote)
        .foregroundStyle(Palette.ink3)
    }
}

// MARK: - Cabecera del tramo

/// [J] Gare Saint-Lazare → Argenteuil · tramo 2 de 3 · estado de la línea.
private struct TripCardLegHeader: View {
    let model: TripCardModel

    var body: some View {
        let leg = model.leg
        HStack(alignment: .center, spacing: Metrics.Space.sm) {
            LineBadge(code: leg.lineCode, color: leg.lineColor, size: Metrics.Size.badge)
            VStack(alignment: .leading, spacing: 0) {
                Text(TripCardText.legTitle(leg))
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if model.legCount > 1 {
                    Text("tramo \(model.legIndex + 1) de \(model.legCount)")
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
            if leg.status.level > 0 {
                let word: String = leg.status.level >= 2 ? "Interrumpida" : "Perturbada"
                Label(word, systemImage: "exclamationmark.triangle.fill")
                    .textLevel(.label)
                    .foregroundStyle(leg.status.level >= 2 ? Palette.badText : Palette.warnText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - El billete (sistema.md §7.2, versión de la tarjeta)

/// El billete opaco del próximo tren: cifra, destino y hora, vía (real o
/// probable) y ritmo. Los minutos ya vienen descontados (`TripCardModel`).
private struct TripCardTicket: View {
    let leg: Leg
    let departure: Departure

    var body: some View {
        let moment = DepartureMoment(departure)
        let atStop = departure.atStop
        let ink = atStop ? Palette.atStopInk : Palette.ticketInk
        let ink2 = atStop ? Palette.atStopInk : Palette.ticketInk2
        HStack(alignment: .center, spacing: Metrics.Space.ml) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.hair) {
                Text(moment.text)
                    .numberFont(.ticketCompact, scale: moment.numberScale)
                    .minutesTransition(value: departure.minutes)
                    .lineLimit(1)
                if let unit = moment.unit {
                    Text(unit)
                        .textLevel(.unit)
                        .foregroundStyle(ink2)
                }
            }
            .foregroundStyle(ink)
            .fixedSize()

            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(departure.destination.isEmpty ? leg.directionLabel : departure.destination)
                    .textLevel(.destination)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                meta(ink2: ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Metrics.Space.xs) {
                platform(ink: ink)
                if let pace = moment.pace {
                    paceTag(pace)
                }
            }
        }
        .padding(.vertical, Metrics.Space.ml)
        .padding(.horizontal, Metrics.Size.ticketPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous)
                .fill(atStop ? Palette.ok : Palette.ticket)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripCardText.spoken(leg: leg, departure: departure))
    }

    private func meta(ink2: Color) -> some View {
        HStack(spacing: Metrics.Space.s) {
            if !departure.at.isEmpty {
                Text(departure.at)
            }
            // R4 y R14: sin hora teórica no hay retraso; un 0 no se enseña.
            if !departure.aimedAt.isEmpty, let delay = departure.realDelay, delay != 0 {
                Text(Fmt.delay(delay))
                    .fontWeight(delay > 0 ? .bold : .regular)
                    .foregroundStyle(delay > 0 ? Palette.ticketWarn : ink2)
            }
            if let length = departure.length {
                let word: String = length == .short ? "corto" : "largo"
                Label(word, systemImage: length.symbol)
            }
        }
        .textLevel(.meta)
        .foregroundStyle(ink2)
        .lineLimit(1)
    }

    /// Vía real: caja sólida amarilla. Probable: recuadro punteado, sin
    /// «Vía» ni relleno (R10). Sin vía esperada (R3) o sin nada: nada.
    @ViewBuilder
    private func platform(ink: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.via, style: .continuous)
        if leg.showsPlatform {
            if departure.hasRealPlatform, let number = departure.platform, !number.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.xs) {
                    Text("Vía").textLevel(.label)
                    Text(number).numberFont(.via)
                }
                .foregroundStyle(Palette.viaInk)
                .padding(.vertical, Metrics.Space.xs)
                .padding(.horizontal, 9)
                .background(shape.fill(Palette.via))
                .overlay(shape.strokeBorder(Palette.viaEdge, lineWidth: Metrics.Size.hairline))
                .viaPulse(isActive: departure.platformNew)
                .fixedSize()
            } else if let guess = departure.guess, !guess.platform.isEmpty {
                ViewThatFits(in: .horizontal) {
                    probable(guess, percent: true)
                    probable(guess, percent: false)
                }
                .foregroundStyle(ink)
                .padding(.vertical, Metrics.Space.xs)
                .padding(.horizontal, Metrics.Space.sm)
                .overlay(shape.strokeBorder(ink, style: StrokeStyle(lineWidth: Metrics.Size.dashWidth,
                                                                    dash: Metrics.Size.dash)))
            }
        }
    }

    private func probable(_ guess: PlatformGuess, percent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.xs) {
            Text("probable").textLevel(.label)
            Text(guess.platform).numberFont(.via)
            if percent {
                Text("\(guess.percent) %").textLevel(.label)
            }
        }
        .fixedSize()
    }

    /// «Corre» / «Anda» / «Con calma» (sistema.md §7.6).
    private func paceTag(_ pace: Pace) -> some View {
        let running = pace == .run
        return Text(TripCardText.paceWord(pace))
            .textLevel(.label)
            .foregroundStyle(running ? Palette.onAccent : Palette.ticketInk)
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, Metrics.Space.hair)
            .background(Capsule().fill(running ? Palette.bad : Palette.pace))
            .fixedSize()
    }
}

// MARK: - Lo que enseña la tarjeta (sin vista: se prueba solo)

/// El tramo que toca y su próximo tren, con los minutos al momento.
struct TripCardModel: Equatable {
    var leg: Leg
    /// Posición del tramo en la ruta (0…).
    var legIndex: Int
    var legCount: Int
    /// El próximo tren que no está cancelado, con `minutes` ya descontado
    /// desde la llegada del tablero. nil si no queda ninguno.
    var departure: Departure?
    /// Un tren anterior a ese, cancelado («el de las 12:56, cancelado»).
    var cancelledBefore: Departure?
    /// Dato viejo (R19): la tarjeta se apaga como el tablero.
    var isStale: Bool

    /// Un «ya» se sigue enseñando hasta 45 s después de su hora (como el
    /// tablero y la Live Activity).
    static let departedGrace: TimeInterval = 45

    /// nil si el tablero no es de esta ruta o no tiene tramos.
    static func make(board: Board?, routeID: Int, legSeq: Int?, now: Date) -> TripCardModel? {
        guard let board, board.route?.id == routeID, !board.legs.isEmpty else { return nil }
        let index = legSeq.flatMap { seq in board.legs.firstIndex { $0.seq == seq } } ?? 0
        let leg = board.legs[index]
        let receivedAt = board.receivedAt
        let elapsedMinutes = Int(max(0, now.timeIntervalSince(receivedAt)) / 60)
        let fresh = now.timeIntervalSince(receivedAt) <= Board.staleAfter

        var shown: Departure?
        var cancelled: Departure?
        for departure in leg.departures {
            let at = departure.date(near: receivedAt)
                ?? receivedAt.addingTimeInterval(TimeInterval(departure.minutes) * 60)
            let gone = !(departure.atStop && fresh) && at.addingTimeInterval(departedGrace) <= now
            if gone { continue }
            if departure.isCancelled {
                if cancelled == nil { cancelled = departure }
                continue
            }
            var current = departure
            current.minutes = max(0, departure.minutes - elapsedMinutes)
            shown = current
            break
        }
        return TripCardModel(leg: leg, legIndex: index, legCount: board.legs.count,
                             departure: shown, cancelledBefore: cancelled,
                             isStale: board.isStale(now: now))
    }
}

/// Los textos de la tarjeta.
enum TripCardText {

    /// Lo que se sigue diciendo en la tarjeta que el trayecto terminó solo.
    static let endedNoteWindow: TimeInterval = 30 * 60

    /// «Trayecto terminado: has llegado. · 18:42».
    static func ended(_ reason: TripEndReason, at date: Date) -> String {
        reason.summary + " · " + date.formatted(date: .omitted, time: .shortened)
    }

    static func locationExplanation(maxMinutes: Int) -> String {
        "Para saber cuándo llegas y apagarse sola, Trajet mira tu ubicación con poca precisión "
            + "(unos 100 m) mientras dura el trayecto, también con la pantalla apagada. Al llegar deja de "
            + "mirarla. Sin ubicación, el trayecto funciona igual pero se para solo a los \(maxMinutes) min."
    }

    /// «4 min a pie hasta Gare Saint-Lazare · por r. Budapest · y 3 min dentro».
    static func walking(minutes: Int, target: WalkingTarget, insideMinutes: Int?) -> String {
        var text = "\(minutes) min a pie hasta \(target.stationName)"
        if let access = target.accessName, !access.isEmpty {
            text += " · por \(access)"
        }
        if let insideMinutes {
            text += " · y \(insideMinutes) min dentro"
        }
        return text
    }

    static func activeFooter(distance: Double?) -> String {
        var text = "Sigue en segundo plano · se apaga al llegar"
        if let distance, distance > 0 {
            text += " · a \(Self.distance(distance)) del destino"
        }
        return text
    }

    static func noLocationFooter(deadline: Date?) -> String {
        guard let deadline else { return "Sin ubicación: se apagará solo" }
        return "Sin ubicación: no sabe cuándo llegas · se apaga solo a las "
            + deadline.formatted(date: .omitted, time: .shortened)
    }

    static func idleFooter(maxMinutes: Int) -> String {
        "Refresca los trenes y la Live Activity hasta que llegues · como mucho \(maxMinutes) min"
    }

    /// «850 m», «3,2 km».
    static func distance(_ meters: Double) -> String {
        if meters < 1_000 {
            let rounded = Int((meters / 50).rounded()) * 50
            return "\(max(50, rounded)) m"
        }
        let km = (meters / 100).rounded() / 10
        let text = km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km)
        return text.replacingOccurrences(of: ".", with: ",") + " km"
    }

    static func legTitle(_ leg: Leg) -> String {
        if leg.toName.isEmpty { return leg.fromName }
        if leg.fromName.isEmpty { return leg.toName }
        return "\(leg.fromName) → \(leg.toName)"
    }

    static func paceWord(_ pace: Pace) -> String {
        switch pace {
        case .run: "Corre"
        case .walk: "Anda"
        case .easy: "Con calma"
        }
    }

    /// Una frase entera para VoiceOver (R50).
    static func spoken(leg: Leg, departure: Departure) -> String {
        let moment = DepartureMoment(departure)
        let destination = departure.destination.isEmpty ? leg.directionLabel : departure.destination
        var parts = ["Línea \(leg.lineCode) a \(destination)", moment.spoken]
        if !departure.at.isEmpty {
            parts.append("a las \(departure.at)")
        }
        if !departure.aimedAt.isEmpty, let delay = departure.realDelay, delay != 0 {
            parts.append(delay > 0 ? "\(delay) minutos de retraso" : "\(-delay) minutos de adelanto")
        }
        if leg.showsPlatform {
            if departure.hasRealPlatform, let platform = departure.platform, !platform.isEmpty {
                parts.append("vía \(platform)")
            } else if let guess = departure.guess, !guess.platform.isEmpty {
                parts.append("vía \(guess.platform) probable, \(guess.percent) por ciento")
            }
        }
        if let length = departure.length {
            parts.append(length == .short ? "tren corto" : "tren largo")
        }
        return parts.joined(separator: ", ") + "."
    }
}
