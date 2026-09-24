import Charts
import SwiftUI

/// El Historial (F45–F49, sistema.md §7.16): cómo han ido tus trayectos los
/// últimos 90 días y cuánto acierta la previsión de vía.
///
/// - Resumen: consultas, retraso medio (con coma decimal, R56) y retraso
///   máximo. Los datos no dicen «días con datos» ni «peor día» (A14).
/// - Días con incidencias por mes: barras de Swift Charts («11/21», mes
///   completo) que crecen con muelle al aparecer (nada con «Reducir
///   movimiento», R51).
/// - Qué línea falla más: `by_line[].n` son veces que fue la peor (filas del
///   historial), no días.
/// - Acierto de la previsión de vía: SOLO de /api/v1/platform-model (R11) y
///   con la cobertura por tramo. La app nunca pregunta si acertó.
///
/// Se pide al entrar en la pestaña y al tirar (F49). No gasta cuota de PRIM.
struct StatsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model = StatsModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.gutter) {
                    content
                }
                .padding(.horizontal, Metrics.Space.gutter)
                .padding(.vertical, Metrics.Space.l)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Historial")
            .refreshable { await load() }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: Metrics.Space.ml) {
                ProgressView()
                Text("Cargando el historial…")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.Space.xxl)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            MessageStateView(symbol: "wifi.slash", tint: Palette.badText,
                             title: "No se ha podido cargar el historial", message: message) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                }
                .filledButton(.primary)
            }
        case .loaded:
            if let stats = model.stats {
                loaded(stats)
            }
        }
    }

    @ViewBuilder
    private func loaded(_ stats: StatsResponse) -> some View {
        if let error = model.refreshError {
            Label(error, systemImage: "exclamationmark.triangle")
                .textLevel(.footnote)
                .foregroundStyle(Palette.warnText)
        }
        sectionTitle("Últimos \(StatsText.periodDays) días")
        StatTilesRow(tiles: StatsText.tiles(stats.overall))

        sectionTitle("Días con incidencias")
        let bars = StatsText.monthBars(stats.byMonth)
        if bars.isEmpty {
            emptyNote("Aún no hay historial: se va llenando con cada consulta del tablero.")
        } else {
            MonthIncidentsChart(bars: bars)
                .padding(Metrics.Size.cardPadding)
                .cardBackground()
        }

        sectionTitle("Qué línea falla más")
        let lines = StatsText.lineFailures(stats.byLine, routes: services.routes.routes)
        if lines.isEmpty {
            emptyNote("Ninguna línea ha fallado en estos \(StatsText.periodDays) días.")
        } else {
            LineFailuresChart(lines: lines)
                .padding(Metrics.Size.cardPadding)
                .cardBackground()
        }

        if let platformModel = model.platformModel {
            sectionTitle("Previsión de vía")
            AccuracyCard(summary: StatsText.accuracy(platformModel,
                                                     route: services.routes.route(id: platformModel.routeId),
                                                     routes: services.routes.routes))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .textLevel(.kicker)
            .foregroundStyle(Palette.ink3)
            .padding(.top, Metrics.Space.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .textLevel(.callout)
            .foregroundStyle(Palette.ink2)
            .padding(Metrics.Size.cardPadding + Metrics.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }

    private func load() async {
        let api = services.api
        // F49: la previsión, de la ruta que se ve en el tablero (si hay).
        let routeID = services.board.currentRouteID
        let days = StatsText.periodDays
        await model.load(stats: { try await api.stats(days: days) },
                         platformModel: { try await api.platformModel(routeID: routeID) })
        // Los colores de las líneas y la cobertura por tramo salen de las
        // rutas (una sola carga, R41).
        await services.routes.loadIfNeeded()
    }
}

/// Las tres cifras del resumen. Con letra muy grande, una debajo de otra.
private struct StatTilesRow: View {
    let tiles: [StatTileModel]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.Space.sm) {
                ForEach(tiles) { StatTile(tile: $0) }
            }
            VStack(spacing: Metrics.Space.sm) {
                ForEach(tiles) { StatTile(tile: $0) }
            }
        }
    }
}

private struct StatTile: View {
    let tile: StatTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.hair) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value)
                    .numberFont(.stat)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = tile.unit {
                    Text(unit)
                        .textLevel(.unit)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Text(tile.caption)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
                .lineLimit(2)
        }
        .padding(Metrics.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.Radius.tile, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.tile, style: .continuous)
            .strokeBorder(Palette.rule, lineWidth: Metrics.Size.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken)
    }
}

/// Días con incidencias por mes: la pista es el total de días con datos y
/// la barra, los que tuvieron alguna incidencia.
///
/// TODO-COMPILAR: `BarMark(xStart:xEnd:y:)`, `.accessibilityHidden(_:)` y
/// `.accessibilityLabel(Text)` sobre `ChartContent` (Swift Charts, iOS 16).
/// Si alguno no casa, quitar ese modificador: el gráfico se sigue leyendo
/// con el «audio graph» del sistema.
private struct MonthIncidentsChart: View {
    let bars: [MonthBar]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    init(bars: [MonthBar]) {
        self.bars = bars
    }

    var body: some View {
        let top = Double(max(bars.map(\.total).max() ?? 1, 1))
        Chart {
            ForEach(bars) { bar in
                BarMark(xStart: .value("Inicio", 0.0),
                        xEnd: .value("Días con datos", grown ? Double(bar.total) : 0),
                        y: .value("Mes", bar.label))
                    .foregroundStyle(Palette.surfaceHi)
                    .cornerRadius(5)
                    .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                        Text(bar.fraction)
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.ink2)
                    }
                    .accessibilityHidden(true)
                BarMark(xStart: .value("Inicio", 0.0),
                        xEnd: .value("Con incidencias", grown ? Double(bar.bad) : 0),
                        y: .value("Mes", bar.label))
                    .foregroundStyle(Palette.accent)
                    .cornerRadius(5)
                    .accessibilityLabel(Text(bar.label))
                    .accessibilityValue(Text(bar.spokenValue))
            }
        }
        .chartXScale(domain: 0.0...(top * 1.3))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .frame(height: CGFloat(bars.count) * 40 + 8)
        .onAppear {
            withMotion(.barGrow, reduceMotion: reduceMotion) {
                grown = true
            }
        }
    }
}

/// La línea que más falla: una barra por línea con su color oficial (R12) y
/// su distintivo; «24 · 4,6 min» al final (veces la peor y retraso medio).
///
/// TODO-COMPILAR: `AxisValueLabel { … }` con una vista dentro (el
/// distintivo). Si no casa, `AxisValueLabel()` a secas (el código en texto).
private struct LineFailuresChart: View {
    let lines: [LineFailure]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    init(lines: [LineFailure]) {
        self.lines = lines
    }

    var body: some View {
        let top = Double(max(lines.map(\.n).max() ?? 1, 1))
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Chart {
                ForEach(lines) { line in
                    BarMark(x: .value("Veces la peor", grown ? Double(line.n) : 0),
                            y: .value("Línea", line.code))
                        .foregroundStyle(LineColor.parse(line.color))
                        .cornerRadius(5)
                        .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                            Text(line.annotation)
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink2)
                        }
                        .accessibilityLabel(Text("Línea \(line.code)"))
                        .accessibilityValue(Text(line.spokenValue))
                }
            }
            .chartXScale(domain: 0.0...(top * 1.45))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let code = value.as(String.self) {
                            LineBadge(code: code, color: color(for: code), size: Metrics.Size.badgeSmall)
                        }
                    }
                }
            }
            .frame(height: CGFloat(lines.count) * 40 + 8)
            Text("Veces que fue la peor línea de la ruta, y su retraso medio.")
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
        .onAppear {
            withMotion(.barGrow, reduceMotion: reduceMotion) {
                grown = true
            }
        }
    }

    private func color(for code: String) -> String {
        lines.first { $0.code == code }?.color ?? ""
    }
}

/// Previsión de vía: el porcentaje del servidor (R11), cuántos aciertos y
/// con cuántos trenes, y la cobertura por tramo.
private struct AccuracyCard: View {
    let summary: AccuracySummary

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(alignment: .center, spacing: Metrics.Space.l) {
                Text(summary.percent)
                    .numberFont(.statBig)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                    if let hits = summary.hitsText {
                        Text(hits)
                            .textLevel(.bodyStrong)
                            .foregroundStyle(Palette.ink)
                    }
                    Text(summary.basisText)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.spoken)
            if let waiting = summary.waitingText {
                Text(waiting)
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            }
            if let title = summary.coverageTitle, !summary.coverage.isEmpty {
                Rectangle()
                    .fill(Palette.rule)
                    .frame(height: Metrics.Size.hairline)
                Text(title)
                    .textLevel(.kicker)
                    .foregroundStyle(Palette.ink3)
                ForEach(summary.coverage) { row in
                    HStack(spacing: Metrics.Space.sm) {
                        LineBadge(code: row.code, color: row.color, size: Metrics.Size.badgeSmall)
                        Text(row.text)
                            .textLevel(.callout)
                            .foregroundStyle(row.publishesPlatform ? Palette.ink2 : Palette.ink3)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Metrics.Size.cardPadding + Metrics.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

#if DEBUG
#Preview("Historial (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        StatsScreen()
    }
}

#Preview("Gráficos") {
    let stats = PreviewData.stats
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            StatTilesRow(tiles: StatsText.tiles(stats.overall))
            MonthIncidentsChart(bars: StatsText.monthBars(stats.byMonth))
                .padding(Metrics.Size.cardPadding)
                .cardBackground()
            LineFailuresChart(lines: StatsText.lineFailures(stats.byLine, routes: PreviewData.routes))
                .padding(Metrics.Size.cardPadding)
                .cardBackground()
            AccuracyCard(summary: StatsText.accuracy(PreviewData.platformModel,
                                                     route: PreviewData.routes.first,
                                                     routes: PreviewData.routes))
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
