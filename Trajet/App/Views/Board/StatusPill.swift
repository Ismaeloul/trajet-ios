import SwiftUI

/// La píldora de estado, encima de los tramos (sistema.md §7.9): si el dato
/// está vivo y de cuándo es. Lo que dice sale de `BoardPill` (R9, R17–R19):
///
/// - en directo: cristal, punto verde con onda, «en directo · hace 6 s»;
/// - ahorrando cuota: cristal, tortuga, «ahorrando cuota · cada 2 min · …»;
/// - dato viejo, sin conexión, errores, servidor sin clave: OPACA, con su
///   icono y su palabra. El amarillo no se usa aquí (es de la vía).
///
/// La antigüedad se ve siempre (R17, R18). Debajo, la barra del próximo
/// refresco (R54). La píldora NO se apaga con el dato viejo: lo explica.
struct StatusPill: View {
    let pill: BoardPill
    /// Último intento y siguiente refresco (barra de R54). nil = sin barra.
    var refreshFrom: Date?
    var refreshTo: Date?
    /// Para decir «próximo en 25 s» con «Reducir movimiento».
    var now: Date = .now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            icon
            Text(text)
                .textLevel(.status)
                .foregroundStyle(Palette.ink2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metrics.Space.l)
        .padding(.vertical, Metrics.Space.sm)
        .frame(minHeight: 36)
        .modifier(PillSurface(pill: pill))
        .overlay(alignment: .bottom) {
            RefreshBar(from: refreshFrom, to: refreshTo)
                .padding(.horizontal, Metrics.Space.xl)
                .padding(.bottom, 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.spoken)
    }

    /// Con «Reducir movimiento» la barra no corre: el resto se dice en texto.
    private var text: String {
        guard reduceMotion, let refreshTo,
              let next = BoardText.nextRefresh(in: refreshTo.timeIntervalSince(now))
        else { return pill.text }
        return "\(pill.text) · \(next)"
    }

    @ViewBuilder
    private var icon: some View {
        if let symbol = pill.symbol {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
        } else {
            LiveDot()
        }
    }

    private var iconColor: Color {
        switch pill.kind {
        case .live, .degraded: Palette.ink3
        case .stale: Palette.warnText
        case .offline, .noKey, .serverError: Palette.badText
        }
    }
}

/// Cristal si el dato está vivo; opaca con canto si algo pasa.
private struct PillSurface: ViewModifier {
    let pill: BoardPill

    @ViewBuilder
    func body(content: Content) -> some View {
        if pill.isOpaque {
            content
                .background(Palette.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(pill.kind == .stale ? Palette.warn : Palette.rule, lineWidth: 1)
                }
                .trajetShadow(Metrics.Shadow.card)
        } else {
            content.cristal(.bar, in: Capsule())
        }
    }
}

/// La barra del próximo refresco (R54): 2 pt que se llenan hasta que llega
/// el dato siguiente. La anima el sistema (`ProgressView(timerInterval:)`),
/// sin que nadie tenga que latir a 60 fps. Con «Reducir movimiento», llena y
/// quieta (el resto se dice en texto en la píldora).
struct RefreshBar: View {
    let from: Date?
    let to: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let from, let to, to > from {
            Group {
                if reduceMotion {
                    Capsule()
                        .fill(Palette.ink3.opacity(0.5))
                        .frame(height: Metrics.Size.refreshBar)
                } else {
                    ProgressView(timerInterval: from...to, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(Palette.ink3)
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    .frame(height: Metrics.Size.refreshBar)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// El punto «en directo»: verde con una onda que crece y se apaga cada 2 s.
/// Con «Reducir movimiento», punto fijo sin onda (R51).
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripple = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Palette.okText)
                    .scaleEffect(ripple ? 2.1 : 1)
                    .opacity(ripple ? 0 : 0.6)
            }
            Circle()
                .fill(Palette.okText)
        }
        .frame(width: Metrics.Size.liveDot, height: Metrics.Size.liveDot)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: Motion.Timing.live).repeatForever(autoreverses: false)) {
                ripple = true
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Píldora de estado") {
    let now = Date()
    let pills: [BoardPill] = {
        var vivo = PreviewData.board(.tranquilo)
        vivo.receivedAt = now.addingTimeInterval(-4)
        var viejo = PreviewData.board(.tranquilo)
        viejo.receivedAt = now.addingTimeInterval(-240)
        var cuota = PreviewData.board(.cuotaJusta)
        cuota.receivedAt = now
        return [
            BoardPill.make(board: vivo, issue: nil, server: vivo.server, now: now),
            BoardPill.make(board: cuota, issue: nil, server: cuota.server, now: now),
            BoardPill.make(board: viejo, issue: nil, server: viejo.server, now: now),
            BoardPill.make(board: viejo, issue: .offline(""), server: viejo.server, now: now),
            BoardPill.make(board: viejo, issue: .noKey, server: viejo.server, now: now),
            BoardPill.make(board: viejo, issue: .quotaExhausted(retryAfter: nil), server: viejo.server, now: now),
        ].compactMap { $0 }
    }()
    ZStack {
        LinearGradient(colors: [.mint, .blue], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                StatusPill(pill: pill, refreshFrom: now, refreshTo: now.addingTimeInterval(30), now: now)
            }
        }
        .padding(Metrics.Space.gutter)
    }
}
#endif
