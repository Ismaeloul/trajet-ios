import SwiftUI
import WidgetKit

// Widgets de la pantalla de inicio, variante A «Billete»
// (docs/diseno/decisiones-la-widgets.md §2.3, sistema.md §12.7):
// - pequeño: cabecera · billete con la cifra a 54 pt · vía o «luego» y la
//   antigüedad (anatomía fija; «luego» cae antes que la antigüedad);
// - mediano: la columna del pequeño · «desde X», dos filas con destino y la
//   antigüedad; un solo nivel de abreviatura en todo el widget;
// - grande: la ruta y la antigüedad · un bloque por tramo (billete + fichas).
// Minutos y vía siempre en piezas opacas; la antigüedad siempre a la vista.

enum WidgetLayout {
    /// Márgenes de 14 pt (la HIG da 11–16).
    static let margin: CGFloat = 14
    /// La columna del pequeño dentro del mediano.
    static let column: CGFloat = 128
}

struct TrajetHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrajetWidgetKind.home, provider: TrajetTimelineProvider()) { entry in
            TrajetHomeWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Trajet")
        .description("La salida que toca, con su vía y lo viejo que es el dato.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TrajetHomeWidgetView: View {
    let snapshot: WidgetSnapshot

    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .padding(WidgetLayout.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(snapshot.url)
            // Opaco: con «Reducir transparencia» no cambia nada que se lea.
            .containerBackground(for: .widget) {
                Palette.surface
            }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.content {
        case .noAppGroup:
            WidgetUnavailableView(reason: .noAppGroup, compact: family == .systemSmall)
        case .noBoard:
            WidgetUnavailableView(reason: .noBoard, compact: family == .systemSmall)
        case .board:
            if let main = snapshot.legView(0) {
                switch family {
                case .systemMedium:
                    MediumWidgetView(snapshot: snapshot, main: main)
                case .systemLarge:
                    LargeWidgetView(snapshot: snapshot)
                default:
                    SmallWidgetView(snapshot: snapshot, main: main)
                }
            } else {
                WidgetUnavailableView(reason: .noBoard, compact: family == .systemSmall)
            }
        }
    }
}

// MARK: - Sin datos que enseñar

/// Sin App Group (IPA full firmada con un Apple ID gratuito, R60) o sin
/// tablero todavía: un mensaje claro en vez de datos.
struct WidgetUnavailableView: View {
    enum Reason: Hashable, Sendable {
        case noAppGroup
        case noBoard
    }

    let reason: Reason
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: reason == .noAppGroup ? "exclamationmark.triangle.fill" : "tram.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(reason == .noAppGroup ? Palette.warnText : Palette.ink3)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .glanceText(compact ? 14 : 16, .heavy, relativeTo: .headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: message)
                .glanceText(12, .semibold, relativeTo: .caption)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch reason {
        case .noAppGroup: "Widgets no disponibles"
        case .noBoard: "Aún no hay salidas"
        }
    }

    private var message: String {
        switch reason {
        case .noAppGroup:
            compact
                ? "Esta instalación no los permite. Abre Trajet."
                : "Esta instalación de Trajet no comparte datos con los widgets (firma sin App Group). Tus salidas están en la app."
        case .noBoard:
            "Abre Trajet para ver tu ruta."
        }
    }
}

// MARK: - Piezas comunes de los widgets de inicio

/// Símbolo de estado junto al distintivo: por qué está apagado (sin red, sin
/// clave, sin datos recientes), el aviso de la línea o el tren cancelado.
struct WidgetStateMark: Hashable, Sendable {
    let symbol: String
    let isBad: Bool
    let label: String

    static func make(_ snapshot: WidgetSnapshot, _ main: WidgetLegView) -> WidgetStateMark? {
        if let failure = snapshot.failure {
            return failure == .offline
                ? WidgetStateMark(symbol: "wifi.slash", isBad: true, label: "sin conexión")
                : WidgetStateMark(symbol: "server.rack", isBad: true, label: "servidor sin clave")
        }
        if main.isFinal {
            return WidgetStateMark(symbol: "clock", isBad: false, label: "sin datos recientes")
        }
        if main.statusLevel >= 2 {
            return WidgetStateMark(symbol: "xmark.octagon.fill", isBad: true, label: "línea interrumpida")
        }
        if main.statusLevel == 1 {
            return WidgetStateMark(symbol: "exclamationmark.triangle.fill", isBad: false, label: "línea perturbada")
        }
        if main.cancelled != nil {
            return WidgetStateMark(symbol: "xmark.circle.fill", isBad: true, label: "tren cancelado")
        }
        return nil
    }
}

/// La cabecera del pequeño y de la columna del mediano: distintivo, símbolo
/// de estado y destino (o «12:56 cancelado»), que se abrevia sin cortar.
struct WidgetLegHeader: View {
    let snapshot: WidgetSnapshot
    let main: WidgetLegView
    var level: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            GlanceBadge(code: main.leg.lineCode, color: main.leg.lineColor, size: 22,
                        tone: snapshot.isOff ? .off : .live)
            if let mark = WidgetStateMark.make(snapshot, main) {
                Image(systemName: mark.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(mark.isBad ? Palette.badText : Palette.warnText)
                    .accessibilityLabel(mark.label)
            }
            // Con prioridad: si no, el HStack le ofrece la mitad del hueco
            // (lo reparte con el Spacer) y abreviaría antes de tiempo.
            if let cancelled = main.cancelled {
                ViewThatFits(in: .horizontal) {
                    headText("\(cancelled.atText) cancelado")
                    headText(cancelled.atText)
                    Color.clear.frame(width: 1, height: 1)
                }
                .layoutPriority(1)
            } else {
                GlanceDestination(variants: main.destinationVariants, fromLevel: level, size: 14)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func headText(_ text: String) -> some View {
        Text(verbatim: text)
            .glanceText(14, .bold, relativeTo: .subheadline)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .fixedSize()
    }
}

/// «luego 21 min [prob. 21]»: el tren siguiente, con su vía si la tiene.
struct WidgetNextPiece: View {
    let snapshot: WidgetSnapshot
    let dep: WidgetDeparture
    let leg: WidgetLeg
    var showsDestination: Bool = false
    var tone: GlanceTone = .live

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "luego")
                .glanceText(11, .bold, relativeTo: .caption)
                .foregroundStyle(Palette.ink2)
                .fixedSize()
            GlanceNumber(moment: snapshot.moment(dep), style: .next, ink: Palette.ink, ink2: Palette.ink2,
                         showsTimeLabel: false)
                .fixedSize()
            if showsDestination, let short = dep.destinationVariants.last {
                Text(verbatim: short)
                    .glanceText(11, .semibold, relativeTo: .caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let via = dep.via {
                GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Luego: \(snapshot.spoken(dep, in: leg))")
    }
}

/// El billete de una salida en un widget, o lo que se dice sin ella.
struct WidgetHeroTicket: View {
    let snapshot: WidgetSnapshot
    let main: WidgetLegView
    var style: GlanceNumberStyle = .widgetSmall

    var body: some View {
        if let hero = main.hero {
            GlanceHeroTicket(moment: snapshot.moment(hero), style: style,
                             tone: snapshot.isOff ? .off : .live, timer: snapshot.timerRange(hero))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.spoken(hero, in: main.leg))
        } else {
            GlanceEmptyTicket(kind: main.empty ?? .finished, compact: true, height: nil)
        }
    }
}

// MARK: - Pequeño (158 × 158)

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot
    let main: WidgetLegView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetLegHeader(snapshot: snapshot, main: main)
            WidgetHeroTicket(snapshot: snapshot, main: main, style: .widgetSmall)
                .frame(maxHeight: .infinity)
            footer
        }
    }

    /// Abajo, la vía (o «luego») y la antigüedad; si no cabe todo, cae
    /// «luego» y se queda la antigüedad (R17).
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                lead
                Spacer(minLength: 4)
                WidgetAgeLabel(snapshot: snapshot, words: false, icon: false, size: 11)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                WidgetAgeLabel(snapshot: snapshot, words: false, icon: false, size: 11)
            }
        }
    }

    @ViewBuilder
    private var lead: some View {
        let tone: GlanceTone = snapshot.isOff ? .off : .live
        if let hero = main.hero, let via = hero.via {
            GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone)
        } else if main.hero != nil, let second = main.second {
            WidgetNextPiece(snapshot: snapshot, dep: second, leg: main.leg, tone: tone)
        }
    }
}

// MARK: - Mediano (338 × 158)

struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot
    let main: WidgetLegView

    /// Dos filas; con un cancelado delante, una.
    private var rows: [WidgetDeparture] {
        Array(main.following.prefix(main.cancelled == nil ? 2 : 1))
    }

    /// El nivel de abreviatura común a la cabecera y a las filas.
    private var level: Int {
        var slots = [DestinationAbbreviator.Slot(variants: main.destinationVariants,
                                                 room: Double(WidgetLayout.column - 32), size: 14)]
        for dep in rows {
            slots.append(DestinationAbbreviator.Slot(variants: dep.destinationVariants, room: 160, size: 12))
        }
        return DestinationAbbreviator.sharedLevel(slots)
    }

    var body: some View {
        let tone: GlanceTone = snapshot.isOff ? .off : .live
        let shared = level
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetLegHeader(snapshot: snapshot, main: main, level: shared)
                WidgetHeroTicket(snapshot: snapshot, main: main, style: .widgetMedium)
                    .frame(maxHeight: .infinity)
                heroFooter(tone: tone)
            }
            .frame(width: WidgetLayout.column)

            VStack(alignment: .leading, spacing: 4) {
                // Con prioridad para que el VStack le ofrezca todo el alto
                // que deja la antigüedad (si no, lo reparte con el Spacer).
                ViewThatFits(in: .vertical) {
                    rightColumn(rowCount: 2, level: shared, tone: tone)
                    rightColumn(rowCount: 1, level: shared, tone: tone)
                    rightColumn(rowCount: 0, level: shared, tone: tone)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                WidgetAgeLabel(snapshot: snapshot, words: true, icon: true, size: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Bajo el billete: la vía con palabra (o «sale 12:56») y el retraso.
    @ViewBuilder
    private func heroFooter(tone: GlanceTone) -> some View {
        if let hero = main.hero {
            let moment = snapshot.moment(hero)
            ViewThatFits(in: .horizontal) {
                heroFooterLine(hero, moment: moment, tone: tone, delay: true)
                heroFooterLine(hero, moment: moment, tone: tone, delay: false)
            }
        }
    }

    private func heroFooterLine(_ hero: WidgetDeparture, moment: GlanceMoment, tone: GlanceTone,
                                delay: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let via = hero.via {
                GlancePlatformMark(via: via, size: .chipS, word: .short, tone: tone)
            } else if !moment.isTime, !hero.atStop {
                Text(verbatim: "sale \(hero.atText)")
                    .glanceText(12, .bold, relativeTo: .caption, tabular: true)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize()
            }
            if delay, let d = hero.delay, d != 0 {
                Text(verbatim: Fmt.delay(d))
                    .glanceText(12, .heavy, relativeTo: .caption, tabular: true)
                    .foregroundStyle(d > 0 ? Palette.warnText : Palette.ink2)
                    .fixedSize()
            }
        }
    }

    private func rightColumn(rowCount: Int, level: Int, tone: GlanceTone) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            rightHeader(tone: tone)
            if let cancelled = main.cancelled, rowCount > 0 {
                cancelledRow(cancelled)
            }
            ForEach(Array(rows.prefix(rowCount))) { dep in
                Link(destination: snapshot.url(leg: main.leg, departure: dep)) {
                    row(dep, level: level, tone: tone)
                }
            }
            if rows.isEmpty, main.cancelled == nil {
                Text(verbatim: noMoreText)
                    .glanceText(12, .semibold, relativeTo: .caption)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «desde Gare Saint-Lazare» como una sola pieza que cae entera; con la
    /// línea perturbada, el aviso en su lugar.
    @ViewBuilder
    private func rightHeader(tone: GlanceTone) -> some View {
        if main.statusLevel > 0 {
            LineStatusChip(level: main.statusLevel, showsWord: true, tone: tone)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(DestinationAbbreviator.variants(main.leg.fromName), id: \.self) { name in
                    Text(verbatim: "desde \(name)")
                        .glanceText(12, .semibold, relativeTo: .caption)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    private func row(_ dep: WidgetDeparture, level: Int, tone: GlanceTone) -> some View {
        let moment = snapshot.moment(dep)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                GlanceNumber(moment: moment, style: .row, ink: Palette.ink, ink2: Palette.ink2,
                             showsTimeLabel: false)
                    .fixedSize()
                if let via = dep.via {
                    GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone)
                } else if let d = dep.delay, d != 0 {
                    Text(verbatim: Fmt.delay(d))
                        .glanceText(12, .heavy, relativeTo: .caption, tabular: true)
                        .foregroundStyle(d > 0 ? Palette.warnText : Palette.ink2)
                        .fixedSize()
                } else if !moment.isTime {
                    Text(verbatim: dep.atText)
                        .glanceText(12, .semibold, relativeTo: .caption, tabular: true)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize()
                }
            }
            GlanceDestination(variants: dep.destinationVariants, fromLevel: level, size: 12,
                              weight: .semibold, color: Palette.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.spoken(dep, in: main.leg))
    }

    private func cancelledRow(_ dep: WidgetDeparture) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .heavy))
            Text(verbatim: dep.atText)
                .glanceText(15, .heavy, relativeTo: .subheadline, tabular: true)
                .strikethrough()
            Text(verbatim: "cancelado")
                .glanceText(12, .bold, relativeTo: .caption)
        }
        .foregroundStyle(Palette.badText)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("El de las \(dep.atText), cancelado")
    }

    private var noMoreText: String {
        if main.hero != nil { return "no hay más salidas anunciadas" }
        switch main.empty ?? .finished {
        case .noRecentData: return "abre Trajet para actualizar"
        case .cut: return "toca para ver alternativas"
        case .finished: return "no hay más salidas"
        }
    }
}

// MARK: - Grande (338 × 354)

struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let legs = snapshot.legViews
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let board = snapshot.board, !board.routeName.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        Text(verbatim: board.routeName)
                            .glanceText(16, .heavy, relativeTo: .headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize()
                        Color.clear.frame(width: 1, height: 1)
                    }
                    .layoutPriority(1)
                }
                Spacer(minLength: 4)
                WidgetAgeLabel(snapshot: snapshot, words: true, icon: true, size: 12)
            }
            // Si con las fichas no cabe, se quedan los billetes.
            ViewThatFits(in: .vertical) {
                sections(legs, chips: true)
                sections(legs, chips: false)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
    }

    private func sections(_ legs: [WidgetLegView], chips: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(legs.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.rule)
                        .frame(height: 1)
                }
                Link(destination: snapshot.url(leg: legs[index].leg)) {
                    LargeLegSection(snapshot: snapshot, view: legs[index], index: index,
                                    count: legs.count, chips: chips)
                }
            }
        }
    }
}

/// Un tramo del widget grande: cabecera (distintivo, «desde → hasta» y el
/// estado de la línea), billete (56/50/42 pt) y fichas.
struct LargeLegSection: View {
    let snapshot: WidgetSnapshot
    let view: WidgetLegView
    let index: Int
    let count: Int
    let chips: Bool

    private var dense: Bool { count > 2 }

    private var size: GlanceTicket.Size {
        if dense { return .small }
        return index == 0 ? .large : .medium
    }

    /// Las fichas que caben: tres en el primero, dos si hay tres tramos y
    /// ninguna en los demás tramos de un widget con tres.
    private var chipDeps: [WidgetDeparture] {
        if dense, index > 0 { return [] }
        return Array(view.following.prefix(dense ? 2 : 3))
    }

    var body: some View {
        let tone: GlanceTone = snapshot.isOff ? .off : .live
        VStack(alignment: .leading, spacing: 6) {
            header(tone: tone)
            ticket(tone: tone)
            if chips, !chipDeps.isEmpty || view.cancelled != nil {
                ViewThatFits(in: .horizontal) {
                    chipRow(Array(chipDeps.prefix(3)), tone: tone)
                    chipRow(Array(chipDeps.prefix(2)), tone: tone)
                    chipRow(Array(chipDeps.prefix(1)), tone: tone)
                }
            }
        }
    }

    private func header(tone: GlanceTone) -> some View {
        let from = DestinationAbbreviator.variants(view.leg.fromName)
        let to = DestinationAbbreviator.variants(view.leg.toName.isEmpty ? view.leg.direction : view.leg.toName)
        var titles: [String] = []
        if let f = from.first, let t = to.first { titles.append("\(f) → \(t)") }
        if let f = from.last, let t = to.last { titles.append("\(f) → \(t)") }
        if let f = from.last { titles.append(f) }
        var unique: [String] = []
        for title in titles where !unique.contains(title) { unique.append(title) }
        return HStack(spacing: 6) {
            GlanceBadge(code: view.leg.lineCode, color: view.leg.lineColor, size: 20, tone: tone)
            ViewThatFits(in: .horizontal) {
                ForEach(unique, id: \.self) { title in
                    Text(verbatim: title)
                        .glanceText(13, .bold, relativeTo: .subheadline)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
                Color.clear.frame(width: 1, height: 1)
            }
            .layoutPriority(1)
            if view.statusLevel > 0 {
                LineStatusChip(level: view.statusLevel, showsWord: true, tone: tone, size: 11)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func ticket(tone: GlanceTone) -> some View {
        if let hero = view.hero {
            GlanceTicket(moment: snapshot.moment(hero), meta: snapshot.meta(hero), via: hero.via,
                         size: size, tone: tone, showsShare: !dense && index == 0,
                         timer: snapshot.timerRange(hero))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.spoken(hero, in: view.leg))
        } else {
            GlanceEmptyTicket(kind: view.empty ?? .finished, compact: size == .small,
                              height: size.height, radius: size.radius)
        }
    }

    private func chipRow(_ deps: [WidgetDeparture], tone: GlanceTone) -> some View {
        HStack(spacing: 6) {
            if let cancelled = view.cancelled {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                    Text(verbatim: cancelled.atText)
                        .glanceText(14, .heavy, relativeTo: .subheadline, tabular: true)
                        .strikethrough()
                    Text(verbatim: "cancelado")
                        .glanceText(11, .bold, relativeTo: .caption)
                }
                .foregroundStyle(Palette.badText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceHi))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("El de las \(cancelled.atText), cancelado")
            }
            ForEach(deps) { dep in
                chip(dep, tone: tone)
            }
        }
    }

    private func chip(_ dep: WidgetDeparture, tone: GlanceTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            GlanceNumber(moment: snapshot.moment(dep), style: .chip, ink: Palette.ink, ink2: Palette.ink2,
                         showsTimeLabel: false)
                .fixedSize()
            // R24: con destinos mezclados, cada ficha dice a dónde va.
            if view.leg.mixed, let short = dep.destinationVariants.last {
                Text(verbatim: short)
                    .glanceText(11, .semibold, relativeTo: .caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let via = dep.via {
                GlancePlatformMark(via: via, size: .chipXS, word: .short, tone: tone)
            } else if let d = dep.delay, d != 0 {
                Text(verbatim: Fmt.delay(d))
                    .glanceText(11, .heavy, relativeTo: .caption, tabular: true)
                    .foregroundStyle(d > 0 ? Palette.warnText : Palette.ink2)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceHi))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.spoken(dep, in: view.leg))
    }
}
