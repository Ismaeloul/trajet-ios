import SwiftUI
import WidgetKit

/// Colores del billete según el tono y el modo de pintado (sistema.md §12.2,
/// §12.8): vivo (`ticket`), en el andén (verde `ok`), apagado (gris OPACO,
/// R19) o monocromo (contorno blanco en el inicio tintado).
struct GlanceTicketColors: Hashable, Sendable {
    let fill: Color
    let ink: Color
    let ink2: Color
    let warn: Color
    /// Trazo en vez de relleno (acentuado, contorno).
    let outlined: Bool

    static func make(tone: GlanceTone, atStop: Bool, ink: GlanceInk) -> GlanceTicketColors {
        if ink.isMono {
            return GlanceTicketColors(fill: .clear, ink: .white, ink2: Color.white.opacity(0.82),
                                      warn: .white, outlined: true)
        }
        if tone == .off {
            return GlanceTicketColors(fill: GlancePalette.ticketOff, ink: GlancePalette.ticketOffInk,
                                      ink2: GlancePalette.ticketOffInk2, warn: GlancePalette.ticketOffInk,
                                      outlined: false)
        }
        if atStop {
            return GlanceTicketColors(fill: Palette.ok, ink: Palette.atStopInk, ink2: Palette.atStopInk,
                                      warn: Palette.atStopInk, outlined: false)
        }
        return GlanceTicketColors(fill: Palette.ticket, ink: Palette.ticketInk, ink2: Palette.ticketInk2,
                                  warn: Palette.ticketWarn, outlined: false)
    }
}

/// El billete de la variante A (sistema.md §12.5): la cifra a la izquierda,
/// hasta dos líneas secundarias que caen enteras por prioridad (cambio de vía
/// > retraso > hora > longitud > tramo) y la vía en su «matriz» a la derecha.
/// Opaco siempre: el cristal nunca va debajo de minutos y vía (R1).
struct GlanceTicket: View {

    enum Size: Hashable, Sendable {
        case large     // 56 pt (Live Activity, primer tramo del widget grande)
        case medium    // 50 pt
        case small     // 42 pt (widget grande con tres tramos)

        var height: CGFloat {
            switch self {
            case .large: 56
            case .medium: 50
            case .small: 42
            }
        }

        var radius: CGFloat {
            switch self {
            case .large: 16
            case .medium: 14
            case .small: 12
            }
        }

        var numberStyle: GlanceNumberStyle {
            switch self {
            case .large: .ticketLarge
            case .medium: .ticketMedium
            case .small: .ticketSmall
            }
        }

        var stub: GlancePlatformMark.Size {
            switch self {
            case .large: .stub
            case .medium: .stubMedium
            case .small: .stubSmall
            }
        }

        var metaSize: CGFloat { self == .small ? 12 : 13 }
        var numberMinWidth: CGFloat {
            switch self {
            case .large: 78
            case .medium: 68
            case .small: 56
            }
        }
    }

    let moment: GlanceMoment
    var meta: [GlanceMeta] = []
    var via: GlanceVia?
    var size: Size = .large
    var tone: GlanceTone = .live
    /// «90 %» en la matriz (widget grande, vía probable).
    var showsShare: Bool = false
    /// Cuenta atrás del sistema (solo con `GlanceCountdown.usesSystemTimer`).
    var timer: ClosedRange<Date>? = nil

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let isAtStop = moment == .atStop
        let colors = GlanceTicketColors.make(tone: tone, atStop: isAtStop, ink: GlanceInk(renderingMode))
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        HStack(spacing: 0) {
            GlanceNumber(moment: moment, style: size.numberStyle, ink: colors.ink, ink2: colors.ink2,
                         showsTimeLabel: size != .small, timer: timer)
                .padding(.leading, size == .small ? 11 : 14)
                .padding(.trailing, 4)
                .frame(minWidth: size.numberMinWidth, alignment: .leading)
                .layoutPriority(2)
            metaView(colors)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let via {
                // La vía que aparece o cambia entra con escala 0,3 → 1 (la
                // animación la pone quien la usa; sistema.md §12.10).
                GlancePlatformMark(via: via, size: size.stub, word: size == .small ? .short : .full,
                                   showsShare: showsShare, tone: tone, probableInk: colors.ink)
                    .id(via.isReal ? "vía \(via.number)" : "prob. \(via.number)")
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .layoutPriority(1)
            }
        }
        .frame(height: size.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if colors.outlined {
                shape.strokeBorder(Color.white, lineWidth: 2).widgetAccentable()
            } else {
                shape.fill(colors.fill).widgetAccentable()
            }
        }
        .clipShape(shape)
    }

    /// Las líneas secundarias: la primera variante que cabe entera.
    @ViewBuilder
    private func metaView(_ colors: GlanceTicketColors) -> some View {
        let steps = GlanceMeta.ladder(meta)
        if !meta.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, pieces in
                    metaLines(pieces, colors: colors)
                }
            }
        }
    }

    private func metaLines(_ pieces: [GlanceMetaPiece], colors: GlanceTicketColors) -> some View {
        let first = pieces.filter { $0.meta.isFirstLine }
        let second = size == .small ? [] : pieces.filter { !$0.meta.isFirstLine }
        return VStack(alignment: .leading, spacing: 4) {
            if !first.isEmpty { line(first, colors: colors) }
            if !second.isEmpty { line(second, colors: colors) }
        }
    }

    private func line(_ pieces: [GlanceMetaPiece], colors: GlanceTicketColors) -> some View {
        HStack(spacing: 8) {
            ForEach(pieces, id: \.self) { piece in
                Text(verbatim: piece.text)
                    .glanceText(size.metaSize, weight(piece.meta), relativeTo: .footnote, tabular: true)
                    .foregroundStyle(color(piece.meta, colors: colors))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func weight(_ meta: GlanceMeta) -> Font.Weight {
        switch meta {
        case .time: .bold
        case .delay, .platformChange: .heavy
        case .length, .leg: .semibold
        }
    }

    private func color(_ meta: GlanceMeta, colors: GlanceTicketColors) -> Color {
        switch meta {
        case .time: colors.ink
        case .delay(let d): d > 0 ? colors.warn : colors.ink2
        case .platformChange: colors.warn
        case .length, .leg: colors.ink2
        }
    }
}

/// El billete de los widgets pequeño y mediano: la cifra ocupa el centro
/// (54 / 50 pt) y, como mucho, el retraso al lado.
struct GlanceHeroTicket: View {
    let moment: GlanceMoment
    var delay: Int?
    var style: GlanceNumberStyle = .widgetSmall
    var tone: GlanceTone = .live
    /// Cuenta atrás del sistema (solo con `GlanceCountdown.usesSystemTimer`).
    var timer: ClosedRange<Date>? = nil

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let colors = GlanceTicketColors.make(tone: tone, atStop: moment == .atStop, ink: GlanceInk(renderingMode))
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            GlanceNumber(moment: moment, style: style, ink: colors.ink, ink2: colors.ink2, minimumScale: 0.7,
                         timer: timer)
            if let delay, delay != 0, moment != .atStop {
                Text(verbatim: Fmt.delay(delay))
                    .glanceText(12, .heavy, relativeTo: .caption)
                    .foregroundStyle(delay > 0 ? colors.warn : colors.ink2)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if colors.outlined {
                shape.strokeBorder(Color.white, lineWidth: 2).widgetAccentable()
            } else {
                shape.fill(colors.fill).widgetAccentable()
            }
        }
    }
}

/// Sin salida que enseñar: «Servicio finalizado» (R25), «Sin circulación ·
/// toca para ver alternativas» o «Sin datos recientes · abre Trajet».
struct GlanceEmptyTicket: View {
    let kind: GlanceEmpty
    /// Sin la segunda línea (widgets pequeños).
    var compact: Bool = false
    /// Alto fijo (billete) o nil para ocupar lo que haya.
    var height: CGFloat? = 56
    var radius: CGFloat = 16

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let mono = GlanceInk(renderingMode).isMono
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: compact ? 18 : 20, weight: .bold))
                .foregroundStyle(mono ? Color.white : iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: kind.title)
                    .glanceText(compact ? 14 : 16, .heavy, relativeTo: .subheadline)
                    .foregroundStyle(mono ? Color.white : titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !compact {
                    Text(verbatim: kind.subtitle)
                        .glanceText(12, .semibold, relativeTo: .caption)
                        .foregroundStyle(mono ? Color.white.opacity(0.82) : subtitleColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height ?? .infinity, alignment: .leading)
        .background {
            if mono {
                shape.strokeBorder(Color.white, lineWidth: 2).widgetAccentable()
            } else {
                shape.fill(fill)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        kind == .cut ? Palette.bad : Palette.surfaceHi
    }

    private var titleColor: Color {
        kind == .cut ? Palette.onAccent : Palette.ink
    }

    private var subtitleColor: Color {
        kind == .cut ? Palette.onAccent.opacity(0.9) : Palette.ink2
    }

    private var iconColor: Color {
        switch kind {
        case .cut: Palette.onAccent
        case .noRecentData: Palette.warnText
        case .finished: Palette.ink3
        }
    }
}

/// El distintivo de línea, seguro en monocromo: en color es `LineBadge`
/// (R12; apagado, sin saturación, R19); en el modo vibrante, caja blanca con
/// el código negro (queda «calado»); en el acentuado, trazo con el código.
struct GlanceBadge: View {
    let code: String
    let color: String
    var size: CGFloat = 22
    var tone: GlanceTone = .live

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        switch GlanceInk(renderingMode) {
        case .color:
            LineBadge(code: code, color: color, size: size)
                .saturation(tone == .off ? 0 : 1)
        case .vibrant:
            monoBadge(filled: true)
        case .accented:
            monoBadge(filled: false)
        }
    }

    private func monoBadge(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * Metrics.Radius.badgeRatio, style: .continuous)
        let ratio: CGFloat = code.count <= 2 ? 0.5 : (code.count == 3 ? 0.44 : 0.38)
        return Text(verbatim: code.isEmpty ? "?" : code)
            .font(GlanceFont.black(size * ratio))
            .foregroundStyle(filled ? Color.black : Color.white)
            .lineLimit(1)
            .padding(.horizontal, size * 0.2)
            .frame(minWidth: size, minHeight: size, maxHeight: size)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                if filled {
                    shape.fill(Color.white)
                } else {
                    shape.strokeBorder(Color.white, lineWidth: 1.5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Línea \(code)")
    }
}
