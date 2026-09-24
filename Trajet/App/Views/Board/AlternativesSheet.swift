import SwiftUI
import Observation

/// Buscar alternativa cuando una línea de la ruta está tocada (R29, R30).
///
/// - Se pide SOLO al abrir esta hoja: nunca en el refresco de 30 s, porque
///   comparte la bolsa de mil llamadas diarias con el buscador (R29).
/// - Una alternativa que pasa por otra línea caída no es una alternativa:
///   «No sirve», atenuada (R30).
/// - Sin opciones, «Buscar de todas formas» repite con `force=true` (R30).
/// - Minutos totales con el formato «1h02» (R6) y horas de Navitia a «HH:MM»
///   (R56). Sin «Usar hoy»: no hay API para eso (ajustes-b.md A13).
struct AlternativesSheet: View {
    let routeID: Int

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model: BoardAlternativesModel

    init(routeID: Int) {
        self.routeID = routeID
        _model = State(initialValue: BoardAlternativesModel(routeID: routeID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Metrics.Space.gutter)
                    .padding(.vertical, Metrics.Space.l)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Alternativas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // R29: la única llamada es esta, al abrir la hoja.
            if model.phase == .idle {
                await load(force: false)
            }
        }
    }

    private var loadingText: String {
        model.lastForce ? "Buscando de todas formas…" : "Buscando otro camino…"
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            VStack(spacing: Metrics.Space.ml) {
                ProgressView()
                Text(loadingText)
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.Space.xxl)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            MessageStateView(symbol: "wifi.slash", tint: Palette.badText,
                             title: "No se ha podido buscar", message: message) {
                Button {
                    Task { await load(force: model.lastForce) }
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .cristalButton()
                .controlSize(.large)
            }
        case .loaded(let reply):
            loaded(reply)
        }
    }

    @ViewBuilder
    private func loaded(_ reply: AlternativesResponse) -> some View {
        VStack(spacing: Metrics.Space.gutter) {
            if let banner = BoardAlternativesText.banner(reply.affected) {
                AffectedBanner(title: banner, subtitle: BoardAlternativesText.baseline(reply.baselineMinutes))
            } else if let baseline = BoardAlternativesText.baseline(reply.baselineMinutes) {
                Text(baseline)
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if reply.options.isEmpty {
                MessageStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                 title: BoardAlternativesText.emptyTitle(needed: reply.needed)) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Label("Buscar de todas formas", systemImage: "magnifyingglass")
                    }
                    .filledButton(.primary)
                }
            } else {
                ForEach(reply.options) { option in
                    AlternativeOptionCard(option: option)
                }
            }
        }
    }

    private func load(force: Bool) async {
        let api = services.api
        await model.load(force: force) { id, force in
            try await api.alternatives(routeID: id, force: force)
        }
    }
}

/// Lo que pasa en la hoja de alternativas. Separado de la vista para
/// probarlo: nada se pide hasta que se llama a `load` (R29) y «Buscar de
/// todas formas» pasa `force` (R30).
@MainActor
@Observable
final class BoardAlternativesModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(AlternativesResponse)
        case failed(String)
    }

    /// Quién hace la llamada (en la app, `TrajetAPI.alternatives`).
    typealias Fetch = @Sendable (_ routeID: Int, _ force: Bool) async throws -> AlternativesResponse

    let routeID: Int
    private(set) var phase: Phase = .idle
    /// La última búsqueda fue forzada («Buscar de todas formas»).
    private(set) var lastForce = false
    /// Cuántas veces se ha llamado al servidor.
    private(set) var requests = 0

    init(routeID: Int) {
        self.routeID = routeID
    }

    func load(force: Bool, using fetch: Fetch) async {
        lastForce = force
        requests += 1
        phase = .loading
        do {
            let reply = try await fetch(routeID, force)
            phase = .loaded(reply)
        } catch is CancellationError {
            // Se ha cerrado la hoja: no es un error que haya que enseñar.
            phase = .idle
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "El servidor no ha respondido.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// «Línea 14 interrumpida · tu ruta tarda 47 min cuando funciona».
private struct AffectedBanner: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Space.ml) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(title)
                    .textLevel(.bodyStrong)
                if let subtitle {
                    Text(subtitle)
                        .textLevel(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.onAccent)
        .padding(Metrics.Size.cardPadding + Metrics.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bad, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Una opción: minutos totales, diferencia, horas, cadena de tramos con su
/// estado y transbordos. La que no sirve, atenuada y dicho por qué (R30).
struct AlternativeOptionCard: View {
    let option: AlternativeOption

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.sm) {
                // La cifra y la diferencia no se parten nunca («5» / «9» con
                // letra grande): si no cabe, las horas de la derecha ceden.
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.minutes(option.totalMinutes))
                        .numberFont(.stat)
                        .foregroundStyle(Palette.ink)
                    if let unit = Fmt.minutesUnit(option.totalMinutes) {
                        Text(unit)
                            .textLevel(.unit)
                            .foregroundStyle(Palette.ink3)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                if let delta = option.deltaLabel {
                    Text(delta)
                        .textLevel(.status)
                        .foregroundStyle((option.deltaMinutes ?? 0) > 0 ? Palette.warnText : Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: Metrics.Space.sm)
                if let times = BoardAlternativesText.times(option) {
                    Text(times)
                        .textLevel(.meta)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.trailing)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                ForEach(Array(option.legs.enumerated()), id: \.offset) { _, leg in
                    AlternativeLegRow(leg: leg)
                }
            }
            if option.usable {
                Text(BoardAlternativesText.transfers(option.transfers))
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink2)
            } else {
                Label(BoardAlternativesText.unusable, systemImage: "xmark.circle.fill")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.badText)
            }
        }
        .padding(Metrics.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .opacity(option.usable ? 1 : Metrics.Opacity.unusable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardAlternativesText.spoken(option))
    }
}

private struct AlternativeLegRow: View {
    let leg: AlternativeLeg

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            LineBadge(code: leg.code, color: leg.color, size: Metrics.Size.badgeSmall)
            VStack(alignment: .leading, spacing: 0) {
                Text(leg.direction.isEmpty ? "Línea \(leg.code)" : leg.direction)
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(detail)
                    .textLevel(.footnote)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 0)
        }
    }

    private var detail: String {
        let unit = Fmt.minutesUnit(leg.minutes).map { " \($0)" } ?? ""
        let minutes = Fmt.minutes(leg.minutes) + unit
        guard !leg.status.isEmpty, leg.status != "normal" else { return minutes }
        return "\(minutes) · \(leg.status)"
    }

    private var statusColor: Color {
        switch leg.status {
        case "interrumpida": Palette.badText
        case "perturbada": Palette.warnText
        default: Palette.ink3
        }
    }
}

#if DEBUG
#Preview("Alternativas (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AlternativesSheet(routeID: 3)
            }
    }
}

#Preview("Opciones") {
    let reply = PreviewData.alternatives
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            ForEach(reply.options) { option in
                AlternativeOptionCard(option: option)
            }
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
