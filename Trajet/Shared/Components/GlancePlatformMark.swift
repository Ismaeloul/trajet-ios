import SwiftUI
import WidgetKit

/// La vía, por FORMA y PALABRA (R10), segura en monocromo:
/// - real: caja llena con «Vía» (amarilla con canto; apagada, gris; en los
///   widgets vibrantes, blanca con el número «calado»; en el acentuado, trazo
///   continuo o calado);
/// - probable: recuadro PUNTEADO con «probable» / «prob.», nunca «Vía» ni
///   relleno.
/// En la isla compacta y la mínima solo va la forma (la palabra, a VoiceOver).
struct GlancePlatformMark: View {

    /// Tallas del laboratorio (sistema.md §12.3 y §12.5).
    enum Size: Hashable, Sendable {
        /// La «matriz» del billete de 56 pt: 62 × 46.
        case stub
        /// Matriz del billete de 50 pt.
        case stubMedium
        /// Matriz del billete de 42 pt.
        case stubSmall
        /// Junto a la cifra de la isla expandida: 38 × 38.
        case box
        /// Chips en línea: palabra + número.
        case chipM, chipS, chipXS
        /// Solo la forma: 20 × 18 (isla compacta y mínima).
        case mini
    }

    /// Qué palabra lleva la probable.
    enum Word: Hashable, Sendable {
        case full      // «probable»
        case short     // «prob.»
    }

    let via: GlanceVia
    var size: Size = .chipS
    var word: Word = .short
    /// «90 %» debajo del número (solo la probable y solo en la matriz).
    var showsShare: Bool = false
    var tone: GlanceTone = .live
    /// Sobre la isla (siempre negra): colores fijos.
    var onIsland: Bool = false
    /// Color de la probable (texto y punteado): el del sitio donde va.
    var probableInk: Color = Palette.ink

    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorSchemeContrast) var contrast

    private var ink: GlanceInk { GlanceInk(renderingMode) }

    /// Calado de verdad (solo la real en el modo acentuado, si se activa).
    private var knockout: Bool {
        via.isReal && ink == .accented && GlanceInk.accentedKnockout
    }

    var body: some View {
        content
            .compositingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(via.spoken)
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .stub, .stubMedium, .stubSmall:
            stub
        case .box:
            box
        case .chipM, .chipS, .chipXS:
            chip
        case .mini:
            mini
        }
    }

    // MARK: - Formas

    private var stub: some View {
        let m = metrics
        let label = via.isReal ? "Vía" : (size == .stubSmall ? "prob." : "probable")
        let share = showsShare ? via.sharePercent : nil
        return VStack(spacing: 2) {
            wordText(label, size: m.word)
            numberText(size: share == nil ? m.number : m.number - 4)
            if let share {
                Text(verbatim: share)
                    .font(GlanceFont.word(11, .bold))
                    .foregroundStyle(textColor.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: m.width)
        .frame(maxHeight: .infinity)
        .background { shapeFill(radius: m.radius) }
        .overlay { shapeStroke(radius: m.radius, dashWidth: 2) }
        .padding(m.margin)
    }

    private var box: some View {
        VStack(spacing: 1) {
            wordText(via.isReal ? "Vía" : "prob.", size: 12)
            numberText(size: 19)
        }
        .padding(.horizontal, 3)
        .frame(minWidth: 38, minHeight: 38)
        .background { shapeFill(radius: 9) }
        .overlay { shapeStroke(radius: 9, dashWidth: 1.5) }
        .fixedSize()
    }

    private var chip: some View {
        let m = metrics
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            wordText(via.isReal ? "Vía" : (word == .full ? "probable" : "prob."), size: m.word)
            numberText(size: m.number)
        }
        .padding(.horizontal, m.padH)
        .padding(.vertical, m.padV)
        .background { shapeFill(radius: m.radius) }
        .overlay { shapeStroke(radius: m.radius, dashWidth: 1.5) }
        .fixedSize()
    }

    private var mini: some View {
        Text(verbatim: via.number)
            .font(GlanceFont.black(12))
            .foregroundStyle(textColor)
            .blendMode(knockout ? .destinationOut : .normal)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(minWidth: 20, minHeight: 18)
            .background { shapeFill(radius: 5) }
            .overlay { shapeStroke(radius: 5, dashWidth: 1.5) }
            .fixedSize()
    }

    // MARK: - Piezas

    private func wordText(_ text: String, size: CGFloat) -> some View {
        Text(verbatim: text)
            .font(GlanceFont.word(size))
            .foregroundStyle(textColor)
            .blendMode(knockout ? .destinationOut : .normal)
            .lineLimit(1)
            .fixedSize()
    }

    private func numberText(size: CGFloat) -> some View {
        Text(verbatim: via.number)
            .font(GlanceFont.black(size))
            .tracking(-0.02 * size)
            .foregroundStyle(textColor)
            .blendMode(knockout ? .destinationOut : .normal)
            .lineLimit(1)
            .fixedSize()
    }

    /// Relleno de la real (la probable no lleva relleno nunca).
    @ViewBuilder
    private func shapeFill(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if via.isReal {
            switch ink {
            case .color:
                shape.fill(realFill)
            case .vibrant:
                // Caja blanca con el número negro: el modo vibrante pinta por
                // luminancia y el número queda «calado».
                shape.fill(Color.white)
            case .accented:
                if knockout {
                    shape.fill(Color.white).widgetAccentable()
                } else {
                    Color.clear
                }
            }
        } else {
            Color.clear
        }
    }

    /// Canto de la real, trazo del contorno o punteado de la probable.
    @ViewBuilder
    private func shapeStroke(radius: CGFloat, dashWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if via.isReal {
            switch ink {
            case .color:
                // Canto de 1 pt siempre que esté viva (más grueso con
                // «Aumentar contraste»); apagada, sin canto.
                if tone == .live {
                    shape.strokeBorder(Palette.viaEdge, lineWidth: contrast == .increased ? 1.5 : 1)
                }
            case .vibrant:
                EmptyView()
            case .accented:
                if !knockout {
                    shape.strokeBorder(Color.white, lineWidth: 2.5)
                }
            }
        } else {
            shape.strokeBorder(textColor, style: StrokeStyle(lineWidth: contrast == .increased ? 2 : dashWidth,
                                                             dash: Metrics.Size.dash))
        }
    }

    private var realFill: Color {
        if tone == .off { return onIsland ? GlancePalette.islandOff : GlancePalette.viaOff }
        return Palette.via
    }

    private var textColor: Color {
        if via.isReal {
            switch ink {
            case .color:
                if tone == .off { return onIsland ? GlancePalette.islandOffInk : GlancePalette.viaOffInk }
                return Palette.viaInk
            case .vibrant:
                return Color.black
            case .accented:
                return knockout ? Color.black : Color.white
            }
        }
        if ink.isMono { return Color.white }
        if onIsland { return tone == .off ? GlancePalette.islandOff : GlancePalette.islandInk }
        return probableInk
    }

    private struct SizeMetrics {
        var word: CGFloat
        var number: CGFloat
        var width: CGFloat = 0
        var margin: CGFloat = 0
        var radius: CGFloat
        var padH: CGFloat = 0
        var padV: CGFloat = 0
    }

    private var metrics: SizeMetrics {
        switch size {
        case .stub: SizeMetrics(word: 12, number: 26, width: 62, margin: 5, radius: 11)
        case .stubMedium: SizeMetrics(word: 11, number: 22, width: 54, margin: 4, radius: 10)
        case .stubSmall: SizeMetrics(word: 11, number: 18, width: 46, margin: 3, radius: 9)
        case .box: SizeMetrics(word: 12, number: 19, radius: 9)
        case .chipM: SizeMetrics(word: 12, number: 20, radius: 8, padH: 8, padV: 5)
        case .chipS: SizeMetrics(word: 11, number: 16, radius: 7, padH: 6, padV: 4)
        case .chipXS: SizeMetrics(word: 11, number: 14, radius: 6, padH: 5, padV: 3)
        case .mini: SizeMetrics(word: 0, number: 12, radius: 5)
        }
    }
}
