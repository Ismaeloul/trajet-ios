import SwiftUI
import WidgetKit

// Widgets de la pantalla de bloqueo, variante A (decisiones §2.4, sistema.md
// §12.7–12.8). Se pintan en modo VIBRANTE: ni color de línea ni amarillo.
// La vía real es una caja llena con el número calado + «Vía»; la probable,
// un recuadro punteado + «prob.» (R10), por forma y palabra. Lo apagado
// lleva su símbolo. Un solo enlace por widget: la ruta y el tramo que toca.

struct TrajetLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrajetWidgetKind.lock, provider: TrajetTimelineProvider()) { entry in
            TrajetLockWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Trajet")
        .description("Minutos y vía de la salida que toca.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TrajetLockWidgetView: View {
    let snapshot: WidgetSnapshot

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockCircularView(snapshot: snapshot)
                .widgetURL(snapshot.url)
                .containerBackground(for: .widget) {
                    AccessoryWidgetBackground()
                }
        case .accessoryRectangular:
            LockRectangularView(snapshot: snapshot)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .widgetURL(snapshot.url)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        default:
            LockInlineView(snapshot: snapshot)
                .widgetURL(snapshot.url)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
    }
}

/// Lo que dicen los tres de bloqueo, en valores (sin vistas).
struct LockGlance {
    let snapshot: WidgetSnapshot
    let main: WidgetLegView?

    init(_ snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
        self.main = snapshot.legView(0)
    }

    var hero: WidgetDeparture? { main?.hero }

    var lineCode: String { main?.leg.lineCode ?? "" }

    /// El símbolo del estado: fallo de la recarga, sin datos recientes, aviso
    /// de la línea o tren cancelado.
    var symbol: String? {
        guard let main else { return nil }
        return WidgetStateMark.make(snapshot, main)?.symbol
    }

    /// Minutos para el arco del circular: solo con 30 min o menos y cuenta
    /// atrás (con más, o con la hora fija, un arco lleno no diría nada).
    var arcMinutes: Int? {
        guard let hero else { return nil }
        switch snapshot.moment(hero) {
        case .minutes(let m): return m <= 30 ? m : nil
        case .now: return 0
        case .long, .atStop, .time: return nil
        }
    }

    /// El widget en línea: «J · 6 min · Vía 21 · hace 5 min»; si no cabe,
    /// cae por el final. La probable dice «prob. 21», nunca «vía 21 prob.».
    var inlineText: String {
        guard let main else {
            switch snapshot.content {
            case .noAppGroup: return "Trajet · abre la app"
            case .noBoard, .board: return "Trajet · sin salidas todavía"
            }
        }
        let code = main.leg.lineCode.isEmpty ? "Trajet" : main.leg.lineCode
        guard let hero else {
            return "\(code) · \((main.empty ?? .finished).lowercased)"
        }
        var parts = [code, snapshot.moment(hero).inline]
        if let via = hero.via { parts.append(via.inline) }
        parts.append(snapshot.ageText)
        return parts.joined(separator: " · ")
    }

    /// VoiceOver.
    var spoken: String {
        guard let main else { return inlineText }
        guard let hero else {
            return "Línea \(main.leg.lineCode): \((main.empty ?? .finished).lowercased), \(snapshot.ageText)"
        }
        return "\(snapshot.spoken(hero, in: main.leg)), \(snapshot.ageText)"
    }
}

// MARK: - Circular (72)

struct LockCircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let glance = LockGlance(snapshot)
        Group {
            if let minutes = glance.arcMinutes {
                // El arco baja con los minutos (una entrada por minuto).
                Gauge(value: Double(minutes), in: 0...30) {
                    Text(verbatim: glance.lineCode)
                } currentValueLabel: {
                    centerStack(glance)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                centerStack(glance)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glance.spoken)
    }

    private func centerStack(_ glance: LockGlance) -> some View {
        VStack(spacing: 0) {
            center(glance)
            HStack(spacing: 2) {
                if let symbol = glance.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                }
                Text(verbatim: glance.lineCode)
                    .font(GlanceFont.black(10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func center(_ glance: LockGlance) -> some View {
        if let hero = glance.hero {
            let moment = snapshot.moment(hero)
            switch moment {
            case .minutes(let m):
                VStack(spacing: -3) {
                    Text(verbatim: "\(m)")
                        .font(GlanceFont.number(22))
                    Text(verbatim: "min")
                        .font(GlanceFont.word(9, .bold))
                }
            case .now:
                Text(verbatim: "ya")
                    .font(GlanceFont.number(20))
            case .atStop:
                Text(verbatim: "andén")
                    .font(GlanceFont.number(12))
                    .minimumScaleFactor(0.7)
            case .long(let text):
                Text(verbatim: text)
                    .font(GlanceFont.number(14))
                    .minimumScaleFactor(0.7)
            case .time(let text):
                VStack(spacing: -1) {
                    Text(verbatim: "sale")
                        .font(GlanceFont.word(9, .bold))
                    Text(verbatim: text)
                        .font(GlanceFont.number(14))
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            Image(systemName: (glance.main?.empty ?? .noRecentData).symbol)
                .font(.system(size: 18, weight: .bold))
        }
    }
}

// MARK: - Rectangular (160 × 72)

struct LockRectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let glance = LockGlance(snapshot)
        VStack(alignment: .leading, spacing: 1) {
            firstLine(glance)
            secondLine(glance)
            WidgetAgeLabel(snapshot: snapshot, words: true, icon: true, size: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glance.spoken)
    }

    /// Línea + destino (ajustable) o «12:56 cancelado».
    private func firstLine(_ glance: LockGlance) -> some View {
        HStack(spacing: 4) {
            if let main = glance.main {
                GlanceBadge(code: main.leg.lineCode, color: main.leg.lineColor, size: 16)
                if let symbol = glance.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                }
                if let cancelled = main.cancelled {
                    ViewThatFits(in: .horizontal) {
                        lineText("\(cancelled.atText) cancelado")
                        lineText("cancelado")
                    }
                    .layoutPriority(1)
                } else {
                    GlanceDestination(variants: main.destinationVariants, size: 14, weight: .bold, color: .primary)
                        .layoutPriority(1)
                }
            } else {
                lineText("Trajet")
            }
            Spacer(minLength: 0)
        }
    }

    private func lineText(_ text: String) -> some View {
        Text(verbatim: text)
            .glanceText(14, .bold, relativeTo: .subheadline)
            .lineLimit(1)
            .fixedSize()
    }

    /// La cifra y la vía (o lo que se dice sin salida).
    @ViewBuilder
    private func secondLine(_ glance: LockGlance) -> some View {
        if let main = glance.main, let hero = main.hero {
            HStack(alignment: .center, spacing: 6) {
                GlanceNumber(moment: snapshot.moment(hero), style: .rectangular, ink: .primary, ink2: .secondary,
                             showsTimeLabel: false, minimumScale: 0.8)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                if let via = hero.via {
                    GlancePlatformMark(via: via, size: .chipS, word: .short, probableInk: .primary)
                }
            }
        } else if let main = glance.main {
            Text(verbatim: (main.empty ?? .finished).title)
                .glanceText(15, .heavy, relativeTo: .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(verbatim: snapshot.content == .noAppGroup ? "Abre Trajet" : "Sin salidas todavía")
                .glanceText(15, .heavy, relativeTo: .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - En línea (234 × 26)

struct LockInlineView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let glance = LockGlance(snapshot)
        // El sistema solo pinta un texto y, como mucho, un símbolo delante.
        if let symbol = glance.symbol {
            Label(glance.inlineText, systemImage: symbol)
        } else {
            Text(verbatim: glance.inlineText)
        }
    }
}
