import SwiftUI

/// El aviso de la línea, DENTRO de la tarjeta de su tramo (R27): una franja
/// global no diría qué tramo está tocado (sistema.md §7.7).
///
/// - Perturbada (nivel 1) en ámbar, interrumpida (nivel 2) en rojo, con icono
///   y palabra (nunca solo color).
/// - Mientras falte la traducción se enseña el FRANCÉS, en cursiva y con voz
///   francesa, con «traduciendo» al lado; cuando llega, se sustituye por el
///   español. Nunca se espera al traductor (R8).
/// - En la tarjeta caben 2 mensajes; el resto y los dos idiomas, en el
///   detalle (R27).
/// - Obras con fecha futura (`planned`): NO encienden el aviso (R28). Se
///   dicen aparte, en el detalle (`BoardText.plannedWorks`).
struct LineStatusNotice: View {
    let status: LegStatus
    /// Mensajes que caben (2 en la tarjeta).
    var limit: Int = 2

    var body: some View {
        if let notice = BoardNotice(status: status, limit: limit) {
            NoticeBox(notice: notice)
        }
    }
}

private struct NoticeBox: View {
    let notice: BoardNotice

    private var interrupted: Bool { notice.level >= 2 }

    private var hiddenText: String {
        notice.hiddenCount == 1
            ? "1 aviso más en el detalle"
            : "\(notice.hiddenCount) avisos más en el detalle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            HStack(spacing: Metrics.Space.s) {
                Image(systemName: interrupted ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(interrupted ? Palette.badText : Palette.warn)
                    .modifier(BounceOnLevelChange(level: notice.level))
                    .accessibilityHidden(true)
                Text(notice.title)
                    .textLevel(.noticeTitle)
                    .foregroundStyle(interrupted ? Palette.badText : Palette.warnText)
                Spacer(minLength: Metrics.Space.sm)
                if notice.translating {
                    TranslatingLabel()
                }
            }
            ForEach(Array(notice.lines.enumerated()), id: \.offset) { _, line in
                NoticeMessageText(text: line.text, isFrench: line.isFrench)
            }
            if notice.hiddenCount > 0 {
                Text(hiddenText)
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .padding(.vertical, Metrics.Space.m)
        .padding(.horizontal, Metrics.Space.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(interrupted ? Palette.noticeBad : Palette.noticeWarn,
                    in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Un mensaje del aviso. El francés sin traducir va en cursiva, en `ink2` y
/// marcado como francés para que VoiceOver lo lea con voz francesa
/// (ajustes-b.md A31); el cambio al español es un fundido.
struct NoticeMessageText: View {
    let text: String
    let isFrench: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(attributed)
            .italic(isFrench)
            .textLevel(.callout)
            .foregroundStyle(isFrench ? Palette.ink2 : Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(Motion.animation(.ease, reduceMotion: reduceMotion), value: text)
    }

    private var attributed: AttributedString {
        var value = AttributedString(text)
        if isFrench {
            // TODO-COMPILAR: `languageIdentifier` es el atributo de Foundation
            // (iOS 15). Si no casa, quitar esta línea: solo se pierde la voz
            // francesa de VoiceOver.
            value.languageIdentifier = "fr"
        }
        return value
    }
}

/// «traduciendo» con los tres puntos que se mueven; quietos con «Reducir
/// movimiento» (R51).
struct TranslatingLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            Text("traduciendo")
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
        }
        .textLevel(.label)
        .foregroundStyle(Palette.ink3)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Traduciendo el aviso")
    }
}

/// «No se han podido leer los avisos»: el «normal» de las líneas no es de
/// fiar (`disruptions_ok` = false).
struct DisruptionsUnreadNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.sm) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(Palette.ink2)
                .accessibilityHidden(true)
            Text("No se han podido leer los avisos: el «normal» de las líneas no es seguro.")
                .textLevel(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Metrics.Space.m)
        .padding(.horizontal, Metrics.Space.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: Metrics.Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// El icono del aviso rebota cuando el nivel cambia (nada con «Reducir
/// movimiento»).
private struct BounceOnLevelChange: ViewModifier {
    let level: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.symbolEffect(.bounce, value: reduceMotion ? 0 : level)
    }
}

#if DEBUG
#Preview("Avisos de línea") {
    let cinco = PreviewData.board(.cincoTramos)
    let limite = PreviewData.board(.casosLimite)
    ScrollView {
        VStack(spacing: Metrics.Space.m) {
            // Interrumpida, aún en francés: «traduciendo» (R8).
            LineStatusNotice(status: cinco.legs[3].status)
            // Perturbada y ya traducida.
            LineStatusNotice(status: cinco.legs[4].status)
            // Dos avisos, uno sin traducir.
            LineStatusNotice(status: limite.legs[1].status)
            // Solo obras futuras: no se enciende nada (R28).
            LineStatusNotice(status: cinco.legs[2].status)
            DisruptionsUnreadNotice()
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.surface)
}
#endif
