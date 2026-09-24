import AppIntents
import SwiftUI
import WidgetKit

// Piezas comunes de la Live Activity y los widgets (variante A «Billete»,
// docs/diseno/sistema.md §12.5): cabecera, estado de la línea, antigüedad,
// destino que se abrevia sin cortar palabras y «Parar».

/// Los colores de alrededor del billete: la pantalla de bloqueo (claro u
/// oscuro, los de `Palette`) o la isla (siempre negra, colores fijos).
struct GlanceSurface: Sendable {
    let ink: Color
    let ink2: Color
    let ink3: Color
    let warnText: Color
    let badText: Color
    let noticeWarn: Color
    let noticeBad: Color
    let stopFill: Color
    let onIsland: Bool

    static let lock = GlanceSurface(
        ink: Palette.ink, ink2: Palette.ink2, ink3: Palette.ink3,
        warnText: Palette.warnText, badText: Palette.badText,
        noticeWarn: Palette.noticeWarn, noticeBad: Palette.noticeBad,
        stopFill: Palette.rule, onIsland: false)

    static let island = GlanceSurface(
        ink: GlancePalette.islandInk, ink2: GlancePalette.islandInk2, ink3: GlancePalette.islandInk3,
        warnText: GlancePalette.islandWarn, badText: GlancePalette.islandBad,
        noticeWarn: Tokens.noticeWarn.color(for: .dark), noticeBad: Tokens.noticeBad.color(for: .dark),
        stopFill: GlancePalette.islandStopFill, onIsland: true)

    /// La tinta de las cifras secundarias («luego», transbordo) apagadas.
    func number(off: Bool) -> Color {
        off ? (onIsland ? GlancePalette.islandOff : ink2) : ink
    }
}

/// El destino de una cabecera o una fila: la primera variante que cabe
/// entera; si no cabe ninguna, nada (nunca «Ermont - Eaub…»).
struct GlanceDestination: View {
    let variants: [String]
    var size: CGFloat = 14
    var weight: Font.Weight = .bold
    var color: Color = Palette.ink

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(variants, id: \.self) { name in
                Text(verbatim: name)
                    .glanceText(size, weight, relativeTo: .subheadline)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            }
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// Estado de la línea: símbolo + palabra («⚠ perturbada»); la palabra cae
/// antes que el destino y queda el símbolo (P1-9). Nunca solo color.
struct LineStatusChip: View {
    let level: Int
    var showsWord: Bool = true
    var surface: GlanceSurface = .lock
    var tone: GlanceTone = .live
    var size: CGFloat = 12

    var body: some View {
        let cut = level >= 2
        HStack(spacing: 3) {
            Image(systemName: cut ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: size, weight: .bold))
            if showsWord {
                Text(verbatim: cut ? "interrumpida" : "perturbada")
                    .glanceText(size, .bold, relativeTo: .caption)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(cut ? surface.badText : surface.warnText)
        .padding(.leading, 5)
        .padding(.trailing, showsWord ? 7 : 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(cut ? surface.noticeBad : surface.noticeWarn))
        .saturation(tone == .off ? 0 : 1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cut ? "línea interrumpida" : "línea perturbada")
    }
}

/// Por qué la Live Activity está apagada, dicho con símbolo y palabra.
enum ActivityAgeKind: Hashable, Sendable {
    case live
    case stale
    case offline
    case noKey

    init(_ p: ActivityPresentation) {
        if p.isStale {
            self = .stale
        } else {
            switch p.state.connection {
            case .ok: self = .live
            case .offline: self = .offline
            case .noKey: self = .noKey
            }
        }
    }

    /// Prefijos de la antigüedad, del más largo al más corto (el último vacío).
    var prefixes: [String] {
        switch self {
        case .live: [""]
        case .stale: ["sin actualizar · ", "dato de ", ""]
        case .offline: ["sin conexión · ", ""]
        case .noKey: ["servidor sin clave · ", "sin clave · ", ""]
        }
    }

    var symbol: String? {
        switch self {
        case .live: nil
        case .stale: "clock"
        case .offline: "wifi.slash"
        case .noKey: "server.rack"
        }
    }

    var isBad: Bool { self == .offline || self == .noKey }
}

/// La antigüedad de la Live Activity, siempre a la vista (R17, R18): un
/// texto de fecha del sistema, que envejece solo aunque la app no escriba.
/// Si algo va mal, píldora con símbolo y palabra.
struct ActivityAgeLabel: View {
    let presentation: ActivityPresentation
    var prefixIndex: Int = 0
    var surface: GlanceSurface = .lock
    var size: CGFloat = 12

    var body: some View {
        let kind = ActivityAgeKind(presentation)
        let state = presentation.state
        // Antigüedad = desde la llegada al teléfono + la que ya traía (R17).
        let reference = state.receivedAt.addingTimeInterval(-state.dataAge)
        let prefixes = kind.prefixes
        let prefix = prefixes[min(max(0, prefixIndex), prefixes.count - 1)]
        if let symbol = kind.symbol {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: size + 1, weight: .bold))
                Text("\(prefix)hace \(reference, style: .relative)")
                    .glanceText(size, .bold, relativeTo: .caption, tabular: true)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(kind.isBad ? surface.badText : surface.warnText)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(kind.isBad ? surface.noticeBad : surface.noticeWarn))
            .fixedSize()
        } else {
            Text("hace \(reference, style: .relative)")
                .glanceText(size, .semibold, relativeTo: .caption, tabular: true)
                .foregroundStyle(surface.ink2)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// La antigüedad de un widget: es contenido, no pie de página («hace 5–60
/// min»). Estática en cada entrada (hay una por minuto). Si la recarga falló,
/// píldora con símbolo (y palabra si cabe).
struct WidgetAgeLabel: View {
    let snapshot: WidgetSnapshot
    /// «sin conexión ·», «servidor sin clave ·», «último dato ·» si caben.
    var words: Bool = true
    var icon: Bool = true
    var size: CGFloat = 12

    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let mono = GlanceInk(renderingMode).isMono
        if let failure = snapshot.failure {
            pill(symbol: failure == .offline ? "wifi.slash" : "server.rack",
                 prefixes: failure == .offline ? ["sin conexión · "] : ["servidor sin clave · ", "sin clave · "],
                 foreground: mono ? .white : Palette.badText,
                 background: mono ? .clear : Palette.noticeBad)
        } else if snapshot.legView(0)?.isFinal == true {
            pill(symbol: "clock", prefixes: ["último dato · "],
                 foreground: mono ? .white : Palette.warnText,
                 background: mono ? .clear : Palette.noticeWarn)
        } else {
            Text(verbatim: snapshot.ageText)
                .glanceText(size, .semibold, relativeTo: .caption, tabular: true)
                .foregroundStyle(mono ? Color.white.opacity(0.82) : Palette.ink2)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func pill(symbol: String, prefixes: [String], foreground: Color, background: Color) -> some View {
        let options = (words ? prefixes : []) + [""]
        return ViewThatFits(in: .horizontal) {
            ForEach(options, id: \.self) { prefix in
                HStack(spacing: 4) {
                    if icon {
                        Image(systemName: symbol)
                            .font(.system(size: size + 1, weight: .bold))
                    }
                    Text(verbatim: prefix + snapshot.ageText)
                        .glanceText(size, .bold, relativeTo: .caption, tabular: true)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(foreground)
                .padding(.leading, icon ? 6 : 8)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(background))
                .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Parar»: píldora de 32 pt con 44 pt de área táctil (R52), nunca apagada
/// (P0-3). Ejecuta `StopTripIntent` en el proceso de la app; con el iPhone
/// bloqueado, el sistema pide Face ID.
struct StopTripButton: View {
    var surface: GlanceSurface = .lock

    var body: some View {
        Button(intent: StopTripIntent()) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Palette.bad)
                    .frame(width: 10, height: 10)
                Text(verbatim: "Parar")
                    .glanceText(14, .bold, relativeTo: .subheadline)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(surface.onIsland ? Color.white : Palette.ink)
            .padding(.leading, 11)
            .padding(.trailing, 13)
            .frame(height: 32)
            .background(Capsule().fill(surface.stopFill))
            // 44 pt de área sin que la fila crezca: se amplía el área y se
            // devuelve el hueco con un relleno negativo.
            // TODO-PROBAR: que el área de 44 pt responda en la Live Activity.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
        .accessibilityLabel("Parar el trayecto")
    }
}
