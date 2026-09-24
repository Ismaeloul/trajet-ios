import AppIntents
import SwiftUI
import WidgetKit

// La Dynamic Island de la variante A (sistema.md §12.6, decisiones §2.2).
// La isla es siempre negra: colores fijos (`GlanceSurface.island`).
// - Compacta: leading = distintivo (+ símbolo si está apagada o la línea
//   tiene aviso); trailing = cifra + vía por FORMA (caja llena = real,
//   punteada = probable), nunca más de 52,33 pt por lado: primero cae el «′»
//   y luego la vía.
// - Mínima: aro del color de la línea con la cifra y «min»; ovalada para
//   «1h46» o la hora fija; verde en el andén; gris apagada.
// - Expandida: leading (distintivo y destino), trailing (cifra + vía),
//   center (estado, tramo u hora) y bottom (luego / transbordo / franja de
//   vía, antigüedad y «Parar»).

/// Ancho útil de cada lado de la compacta (52,33 pt menos el margen).
enum IslandLayout {
    static let compactTrailing: CGFloat = 44
    static let compactLeading: CGFloat = 45
}

extension ActivityPresentation {
    /// El símbolo de la compacta: por qué está apagada o, si no, el aviso de
    /// la línea (con tren que enseñar).
    var compactSymbol: String? {
        if let symbol = ActivityAgeKind(self).symbol { return symbol }
        if hero != nil, state.leg.statusLevel >= 2 { return "xmark.octagon.fill" }
        if hero != nil, state.leg.statusLevel == 1 { return "exclamationmark.triangle.fill" }
        return nil
    }

    /// El símbolo cuando no hay tren que enseñar.
    var emptySymbol: String {
        (empty ?? .finished).symbol
    }
}

// MARK: - Compacta

struct IslandCompactLeading: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        HStack(spacing: 3) {
            GlanceBadge(code: p.state.leg.lineCode, color: p.state.leg.lineColor, size: 22,
                        tone: p.isOff ? .off : .live)
            if p.isEnded {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Tokens.okText.color(for: .dark))
            } else if let symbol = p.compactSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
        }
        .frame(maxWidth: IslandLayout.compactLeading, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var symbolColor: Color {
        let kind = ActivityAgeKind(presentation)
        if kind.isBad { return GlancePalette.islandBad }
        if kind == .stale { return GlancePalette.islandWarn }
        return presentation.state.leg.statusLevel >= 2 ? GlancePalette.islandBad : GlancePalette.islandWarn
    }

    private var accessibilityText: String {
        var text = "Línea \(presentation.state.leg.lineCode)"
        switch ActivityAgeKind(presentation) {
        case .stale: text += ", dato sin actualizar"
        case .offline: text += ", sin conexión"
        case .noKey: text += ", servidor sin clave"
        case .live: break
        }
        return text
    }
}

struct IslandCompactTrailing: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        Group {
            if p.isEnded {
                Text(verbatim: "fin")
                    .font(GlanceFont.word(13, .heavy))
                    .foregroundStyle(GlancePalette.islandInk2)
            } else if let hero = p.hero {
                if hero.atStop {
                    atStop(hero)
                } else if p.isStale {
                    // Caducada: la hora fija, siempre cierta.
                    number(hero, prime: false, platform: false)
                } else {
                    // Con «59 min + vía» cae el «′» y luego la vía antes que
                    // ensanchar la isla.
                    ViewThatFits(in: .horizontal) {
                        number(hero, prime: true, platform: true)
                        number(hero, prime: false, platform: true)
                        number(hero, prime: true, platform: false)
                    }
                }
            } else {
                Image(systemName: p.emptySymbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(p.state.leg.statusLevel >= 2 ? GlancePalette.islandBad : GlancePalette.islandInk2)
            }
        }
        .frame(maxWidth: IslandLayout.compactTrailing, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.hero.map { p.spoken($0) } ?? (p.empty ?? .finished).title)
    }

    private func number(_ hero: TrajetActivityAttributes.Dep, prime: Bool, platform: Bool) -> some View {
        let p = presentation
        return HStack(spacing: 3) {
            GlanceNumber(moment: p.moment(hero), style: .compact,
                         ink: p.isOff ? GlancePalette.islandOff : GlancePalette.islandInk,
                         ink2: GlancePalette.islandInk2, prime: prime, showsUnit: false, showsTimeLabel: false)
                .fixedSize()
            if platform, let via = p.via(hero) {
                GlancePlatformMark(via: via, size: .mini, tone: p.isOff ? .off : .live, onIsland: true,
                                   probableInk: GlancePalette.islandInk)
            }
        }
    }

    /// «andén» sobre la vía (≠ «ya», R15).
    private func atStop(_ hero: TrajetActivityAttributes.Dep) -> some View {
        let p = presentation
        return VStack(spacing: 0) {
            Text(verbatim: "andén")
                .font(GlanceFont.word(9, .heavy))
                .foregroundStyle(p.isOff ? GlancePalette.islandOff : Tokens.okText.color(for: .dark))
                .fixedSize()
            if let via = p.via(hero) {
                GlancePlatformMark(via: via, size: .mini, tone: p.isOff ? .off : .live, onIsland: true,
                                   probableInk: GlancePalette.islandInk)
            }
        }
    }
}

// MARK: - Mínima

struct IslandMinimal: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        let oval = isOval
        ZStack {
            if oval {
                Capsule().strokeBorder(ringColor, lineWidth: 2.5)
            } else {
                Circle().strokeBorder(ringColor, lineWidth: 2.5)
            }
            inner
                .padding(.horizontal, oval ? 5 : 3)
        }
        .frame(width: oval ? 44 : 34, height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.hero.map { p.spoken($0) } ?? (p.empty ?? .finished).title)
    }

    /// Ovalada (hasta 45 pt) para «1h46» y la hora fija.
    private var isOval: Bool {
        guard !presentation.isEnded, let hero = presentation.hero, !hero.atStop else { return false }
        switch presentation.moment(hero) {
        case .long, .time: return true
        case .minutes, .now, .atStop: return false
        }
    }

    private var ringColor: Color {
        let p = presentation
        if p.isOff { return GlancePalette.islandRingOff }
        if p.isEnded { return Tokens.okText.color(for: .dark) }
        if p.hero?.atStop == true { return Palette.ok }
        return LineColor.parse(p.state.leg.lineColor)
    }

    @ViewBuilder
    private var inner: some View {
        let p = presentation
        let ink = p.isOff ? GlancePalette.islandOff : GlancePalette.islandInk
        if p.isEnded {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Tokens.okText.color(for: .dark))
        } else if let hero = p.hero {
            if hero.atStop {
                VStack(spacing: 0) {
                    Text(verbatim: "andén")
                        .font(GlanceFont.word(7, .heavy))
                        .foregroundStyle(ink)
                        .fixedSize()
                    if let via = p.via(hero) {
                        Text(verbatim: via.number)
                            .font(GlanceFont.black(10))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                }
            } else {
                switch p.moment(hero) {
                case .minutes(let m):
                    VStack(spacing: -3) {
                        Text(verbatim: "\(m)")
                            .font(GlanceFont.number(15))
                            .foregroundStyle(ink)
                            .contentTransition(.numericText(countsDown: true))
                        Text(verbatim: "min")
                            .font(GlanceFont.word(7, .bold))
                            .foregroundStyle(GlancePalette.islandInk2)
                    }
                case .now:
                    Text(verbatim: "ya")
                        .font(GlanceFont.number(13))
                        .foregroundStyle(ink)
                case .long(let text), .time(let text):
                    Text(verbatim: text)
                        .font(GlanceFont.number(11))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                case .atStop:
                    Text(verbatim: "andén")
                        .font(GlanceFont.word(7, .heavy))
                        .foregroundStyle(ink)
                }
            }
        } else {
            Image(systemName: p.emptySymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(p.state.leg.statusLevel >= 2 ? GlancePalette.islandBad : GlancePalette.islandInk2)
        }
    }
}

// MARK: - Expandida

/// Distintivo y destino en una línea (abreviado sin cortar palabras).
struct IslandExpandedLeading: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        VStack(alignment: .leading, spacing: 4) {
            GlanceBadge(code: p.state.leg.lineCode, color: p.state.leg.lineColor, size: 24,
                        tone: p.isOff ? .off : .live)
            if !p.isEnded {
                GlanceDestination(variants: p.destinations, size: 15, weight: .bold, color: GlancePalette.islandInk)
            }
        }
        .padding(.leading, 4)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// La cifra y la vía juntas, como en la compacta (P1-6).
struct IslandExpandedTrailing: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        let tone: GlanceTone = p.isOff ? .off : .live
        let ink = p.isOff ? GlancePalette.islandOff : GlancePalette.islandInk
        HStack(spacing: 6) {
            if p.isEnded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Tokens.okText.color(for: .dark))
            } else if let hero = p.hero {
                if hero.atStop {
                    ViewThatFits(in: .horizontal) {
                        stopWord("En andén", off: p.isOff)
                        stopWord("andén", off: p.isOff)
                    }
                } else {
                    let moment = p.moment(hero)
                    ViewThatFits(in: .horizontal) {
                        GlanceNumber(moment: moment, style: .expanded, ink: ink, ink2: GlancePalette.islandInk2)
                            .fixedSize()
                        GlanceNumber(moment: moment, style: .expanded, ink: ink, ink2: GlancePalette.islandInk2,
                                     prime: true)
                            .fixedSize()
                        GlanceNumber(moment: moment, style: .expanded, ink: ink, ink2: GlancePalette.islandInk2,
                                     showsUnit: false, showsTimeLabel: false)
                            .fixedSize()
                    }
                }
                if let via = p.via(hero) {
                    GlancePlatformMark(via: via, size: .box, tone: tone, onIsland: true,
                                       probableInk: GlancePalette.islandInk)
                }
            } else {
                Text(verbatim: (p.empty ?? .finished).title)
                    .font(GlanceFont.word(14, .heavy))
                    .foregroundStyle(p.empty == .cut ? GlancePalette.islandBad : GlancePalette.islandInk)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.trailing, 4)
    }

    private func stopWord(_ text: String, off: Bool) -> some View {
        Text(verbatim: text)
            .font(GlanceFont.number(20))
            .foregroundStyle(off ? GlancePalette.islandOff : Tokens.okText.color(for: .dark))
            .lineLimit(1)
            .fixedSize()
    }
}

/// El estado de la línea, «tramo 1 de 2» o «sale 12:56 +2 min».
struct IslandExpandedCenter: View {
    let presentation: ActivityPresentation

    var body: some View {
        let p = presentation
        Group {
            if p.isEnded {
                Text(verbatim: "Trayecto terminado")
                    .glanceText(13, .heavy, relativeTo: .footnote)
                    .foregroundStyle(GlancePalette.islandInk)
            } else if p.hero != nil, p.statusLevel > 0 {
                LineStatusChip(level: p.statusLevel, showsWord: true, surface: .island,
                               tone: p.isOff ? .off : .live)
            } else if let legText = p.legText {
                centerText(legText)
            } else if let hero = p.hero, !p.isStale, !hero.atStop {
                HStack(spacing: 6) {
                    centerText("sale \(GlanceClock.hhmm(hero.at))")
                    if let delay = hero.delay, delay != 0 {
                        Text(verbatim: Fmt.delay(delay))
                            .glanceText(13, .heavy, relativeTo: .footnote, tabular: true)
                            .foregroundStyle(delay > 0 ? GlancePalette.islandWarn : GlancePalette.islandInk2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func centerText(_ text: String) -> some View {
        Text(verbatim: text)
            .glanceText(13, .semibold, relativeTo: .footnote, tabular: true)
            .foregroundStyle(GlancePalette.islandInk2)
            .lineLimit(1)
    }
}

/// Abajo: la franja de vía cuando la alerta abre la isla (vía nueva o
/// cambio de vía) o el pie de siempre; y la antigüedad con «Parar».
struct IslandExpandedBottom: View {
    let presentation: ActivityPresentation
    let routeName: String

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isLuminanceReduced) var luminanceReduced

    var body: some View {
        let p = presentation
        let tone: GlanceTone = p.isOff ? .off : .live
        let kind = ActivityAgeKind(p)
        VStack(alignment: .leading, spacing: 8) {
            if p.isEnded {
                ActivityEndedView(presentation: p, routeName: routeName, surface: .island)
            } else {
                if p.showsPlatformBand, let hero = p.hero, let via = p.via(hero) {
                    PlatformBand(via: via)
                        .transition(bandTransition)
                } else {
                    ActivityFootRow(presentation: p, surface: .island, tone: tone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        ForEach(0..<kind.prefixes.count, id: \.self) { index in
                            ActivityAgeLabel(presentation: p, prefixIndex: index, surface: .island)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 6)
                    StopTripButton(surface: .island)
                }
            }
        }
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .animation(luminanceReduced ? nil : .easeInOut(duration: reduceMotion ? Motion.Timing.reduced : 0.5),
                   value: p.showsPlatformBand)
    }

    private var bandTransition: AnyTransition {
        reduceMotion || luminanceReduced ? .opacity : .push(from: .bottom)
    }
}

/// La franja de vía a lo ancho (de C): «Vía 21 · anunciada ahora» o
/// «Vía 23 · cambio de vía · antes 21». Solo viva y con la vía real.
struct PlatformBand: View {
    let via: GlanceVia

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let long: String
        let short: String
        let spokenText: String
        if let before = via.before {
            long = "cambio de vía · antes \(before)"
            short = "antes vía \(before)"
            spokenText = "Cambio de vía: ahora vía \(via.number), antes \(before)"
        } else {
            long = "anunciada ahora"
            short = "ahora"
            spokenText = "Se acaba de anunciar la vía \(via.number)"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "Vía")
                .font(GlanceFont.word(14, .heavy))
            Text(verbatim: via.number)
                .font(GlanceFont.black(26))
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                bandText(long)
                bandText(short)
            }
        }
        .foregroundStyle(Palette.viaInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(shape.fill(Palette.via))
        .overlay(shape.strokeBorder(Palette.viaEdge, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private func bandText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(GlanceFont.word(13, .heavy))
            .lineLimit(1)
            .fixedSize()
    }
}
