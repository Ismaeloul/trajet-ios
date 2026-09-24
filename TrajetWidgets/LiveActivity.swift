import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// La Live Activity del modo trayecto, variante A «Billete» corregida
// (docs/diseno/decisiones-la-widgets.md, sistema.md §12.5–12.6).
//
// Pinta SOLO la foto que escribió la app (`ContentState`) y el `isStale` del
// sistema (`ActivityPresentation`): viva, la cifra es la que escribió la app
// (dos tallas, «ya», «1h46»); caducada (`staleDate` vencida), horas fijas y
// apagada, sin cambiar de tren ni «publicar» vías. La antigüedad corre sola
// (texto de fecha del sistema). «Parar» (App Intent) nunca se apaga.

struct TrajetLiveActivity: Widget {
    // TODO-COMPILAR: todo se construye DENTRO de los cierres (como la
    // plantilla de Xcode) y sin llamar a funciones estáticas del Widget, que
    // estarían aisladas en el MainActor si WidgetKit declarase los cierres
    // como @Sendable.
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrajetActivityAttributes.self) { context in
            // Lo que se pinta: la foto de la app y si el sistema la da por
            // caducada (`staleDate` vencida).
            ActivityLockScreenView(presentation: ActivityPresentation(state: context.state,
                                                                      isStale: context.isStale,
                                                                      routeID: context.attributes.routeID),
                                   routeName: context.attributes.routeName)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            // La isla: compacta (distintivo · cifra + vía), mínima (aro con
            // la cifra) y expandida (las cuatro regiones).
            let p = ActivityPresentation(state: context.state, isStale: context.isStale,
                                         routeID: context.attributes.routeID)
            let routeName = context.attributes.routeName
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(presentation: p)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(presentation: p)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCenter(presentation: p)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(presentation: p, routeName: routeName)
                }
            } compactLeading: {
                IslandCompactLeading(presentation: p)
            } compactTrailing: {
                IslandCompactTrailing(presentation: p)
            } minimal: {
                IslandMinimal(presentation: p)
            }
            .keylineTint(LineColor.parse(p.state.leg.lineColor))
            .widgetURL(p.url)
        }
    }
}

// MARK: - Pantalla de bloqueo (371 × 150)

/// Cabecera · billete · pie con «luego» / transbordo / cancelado y «Parar».
struct ActivityLockScreenView: View {
    let presentation: ActivityPresentation
    let routeName: String

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isLuminanceReduced) var luminanceReduced

    var body: some View {
        Group {
            if presentation.isEnded {
                ActivityEndedView(presentation: presentation, routeName: routeName, surface: .lock)
            } else {
                live
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        // La ruta y el tramo que toca; con la línea cortada, las
        // alternativas; sin clave, los ajustes del servidor (decisiones §6).
        .widgetURL(presentation.url)
    }

    private var live: some View {
        let p = presentation
        let tone: GlanceTone = p.isOff ? .off : .live
        return VStack(alignment: .leading, spacing: 8) {
            ActivityHeaderRow(presentation: p, surface: .lock)
            ActivityTicket(presentation: p, tone: tone)
            HStack(spacing: 8) {
                ActivityFootRow(presentation: p, surface: .lock, tone: tone)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                StopTripButton(surface: .lock)
            }
        }
        // Se apaga con un fundido (R19); sin animación en «siempre activa» o
        // con «Reducir movimiento».
        .animation(luminanceReduced || reduceMotion ? nil : .easeInOut(duration: 0.45), value: p.isOff)
    }
}

/// El billete de la Live Activity (56 pt): la vía entra con muelle al
/// aparecer o cambiar (≤ 2 s, solo al actualizarse).
struct ActivityTicket: View {
    let presentation: ActivityPresentation
    var tone: GlanceTone = .live

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isLuminanceReduced) var luminanceReduced

    var body: some View {
        let p = presentation
        if let hero = p.hero {
            let via = p.via(hero)
            GlanceTicket(moment: p.moment(hero), meta: p.meta(hero), via: via, size: .large, tone: tone,
                         timer: p.timerRange(hero))
                .animation(viaAnimation, value: via)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(p.spoken(hero))
        } else {
            GlanceEmptyTicket(kind: p.empty ?? .finished)
        }
    }

    private var viaAnimation: Animation? {
        if luminanceReduced { return nil }
        return reduceMotion ? .easeInOut(duration: Motion.Timing.reduced)
                            : .spring(response: Motion.Timing.viaAppear, dampingFraction: Motion.dampingFraction)
    }
}

/// Distintivo · destino (abreviado sin cortar) · estado de la línea ·
/// antigüedad. Cae por escalones: la palabra «perturbada», el destino a sus
/// variantes, el prefijo de la antigüedad y, lo último, el destino entero.
/// La antigüedad no cae nunca (R17).
struct ActivityHeaderRow: View {
    let presentation: ActivityPresentation
    var surface: GlanceSurface = .lock

    var body: some View {
        let p = presentation
        let tone: GlanceTone = p.isOff ? .off : .live
        let kind = ActivityAgeKind(p)
        let steps = GlanceHeaderStep.ladder(destinations: p.destinations, hasStatusWord: p.statusLevel > 0,
                                            agePrefixCount: kind.prefixes.count)
        ViewThatFits(in: .horizontal) {
            ForEach(steps, id: \.self) { step in
                HStack(spacing: 8) {
                    GlanceBadge(code: p.state.leg.lineCode, color: p.state.leg.lineColor, size: 22, tone: tone)
                    if let destination = step.destination {
                        Text(verbatim: destination)
                            .glanceText(16, .bold, relativeTo: .headline)
                            .foregroundStyle(surface.ink)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if p.statusLevel > 0 {
                        LineStatusChip(level: p.statusLevel, showsWord: step.statusWord, surface: surface, tone: tone)
                    }
                    Spacer(minLength: 6)
                    ActivityAgeLabel(presentation: p, prefixIndex: step.agePrefix, surface: surface)
                }
            }
        }
    }
}

/// Debajo del billete, UNA línea: el tren cancelado, el transbordo (con la
/// vía del tren de enlace) o «luego 21 min [prob. 21]».
struct ActivityFootRow: View {
    let presentation: ActivityPresentation
    var surface: GlanceSurface = .lock
    var tone: GlanceTone = .live

    var body: some View {
        let p = presentation
        if let cancelled = p.cancelled {
            cancelledView(cancelled)
        } else if let link = p.state.next {
            transferView(link)
        } else if let second = p.second {
            nextView(second)
        }
    }

    // «✕ el de las 12:56, cancelado»
    private func cancelledView(_ dep: TrajetActivityAttributes.Dep) -> some View {
        let time = GlanceClock.hhmm(dep.at)
        return HStack(spacing: 5) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy))
            ViewThatFits(in: .horizontal) {
                footText("el de las \(time), cancelado")
                footText("\(time) cancelado")
                footText("cancelado")
            }
        }
        .foregroundStyle(surface.badText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("El de las \(time), cancelado")
    }

    // «⇅ en St-Lazare [J] 12:56 [Vía 21]»: la vía se queda antes que la hora.
    private func transferView(_ link: TrajetActivityAttributes.Link) -> some View {
        let names = presentation.transferNames
        var labels: [String] = []
        if let first = names.first { labels.append("Transbordo en \(first)") }
        for name in names { labels.append("en \(name)") }
        labels.append("")
        var unique: [String] = []
        for label in labels where !unique.contains(label) { unique.append(label) }
        return ViewThatFits(in: .horizontal) {
            ForEach(unique, id: \.self) { label in
                transferLine(link, label: label, showsTime: true)
            }
            transferLine(link, label: "", showsTime: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(transferSpoken(link))
    }

    private func transferLine(_ link: TrajetActivityAttributes.Link, label: String, showsTime: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(surface.ink2)
            if !label.isEmpty {
                footText(label)
            }
            GlanceBadge(code: link.lineCode, color: link.lineColor, size: 18, tone: tone)
            if let first = link.first {
                if showsTime {
                    Text(verbatim: GlanceClock.hhmm(first.at))
                        .glanceText(14, .heavy, relativeTo: .subheadline, tabular: true)
                        .foregroundStyle(surface.number(off: tone == .off))
                        .lineLimit(1)
                        .fixedSize()
                }
                if let via = presentation.linkVia(first) {
                    GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone,
                                       onIsland: surface.onIsland, probableInk: surface.ink)
                }
            } else {
                footText(link.statusLevel >= 2 ? "sin circulación" : "—")
            }
        }
    }

    private func transferSpoken(_ link: TrajetActivityAttributes.Link) -> String {
        var parts = ["Transbordo"]
        if let name = presentation.transferNames.first { parts.append("en \(name)") }
        parts.append("a la línea \(link.lineCode)")
        if let first = link.first {
            parts.append("que sale a las \(GlanceClock.hhmm(first.at))")
            if let via = presentation.linkVia(first) { parts.append(via.spoken) }
        } else if link.statusLevel >= 2 {
            parts.append("sin circulación")
        }
        return parts.joined(separator: " ")
    }

    // «luego 21 min [prob. 21]» (con destinos mezclados, también a dónde va).
    private func nextView(_ dep: TrajetActivityAttributes.Dep) -> some View {
        ViewThatFits(in: .horizontal) {
            nextLine(dep, showsDestination: presentation.state.leg.mixed)
            nextLine(dep, showsDestination: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Luego: \(presentation.spoken(dep))")
    }

    private func nextLine(_ dep: TrajetActivityAttributes.Dep, showsDestination: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            footText("luego")
            GlanceNumber(moment: presentation.moment(dep), style: .next,
                         ink: surface.number(off: tone == .off), ink2: surface.ink2, showsTimeLabel: false)
                .fixedSize()
            if showsDestination, let short = dep.destination.last {
                footText(short)
            }
            if let via = presentation.via(dep) {
                GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone,
                                   onIsland: surface.onIsland, probableInk: surface.ink)
            }
        }
    }

    private func footText(_ text: String) -> some View {
        Text(verbatim: text)
            .glanceText(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(surface.ink2)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Trayecto terminado por llegada o por la duración máxima: el resumen que se
/// queda 15 min (parado a mano se quita al momento y no llega aquí).
struct ActivityEndedView: View {
    let presentation: ActivityPresentation
    let routeName: String
    var surface: GlanceSurface = .lock

    var body: some View {
        let p = presentation
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlanceBadge(code: p.state.leg.lineCode, color: p.state.leg.lineColor, size: 22)
                Text(verbatim: "Trayecto terminado")
                    .glanceText(16, .heavy, relativeTo: .headline)
                    .foregroundStyle(surface.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(surface.onIsland ? Tokens.okText.color(for: .dark) : Palette.okText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if !routeName.isEmpty {
                        Text(verbatim: routeName)
                            .glanceText(16, .heavy, relativeTo: .headline)
                            .foregroundStyle(surface.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(verbatim: detail)
                        .glanceText(12, .semibold, relativeTo: .caption)
                        .foregroundStyle(surface.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surface.onIsland ? Color.white.opacity(0.12) : Palette.surfaceHi))
        }
        .accessibilityElement(children: .combine)
    }

    /// «se quita sola a las 13:05» con la hora de fin del estado; sin ella,
    /// «en unos minutos» (`ActivityPresentation.endedDetail`).
    private var detail: String {
        presentation.endedDetail
    }
}
