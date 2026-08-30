import SwiftUI

/// Lo único que se consulta sentado.
///
/// Aquí sí hay sitio y tiempo, así que se puede leer con calma: qué línea
/// falla más, cuánto se retrasa de media y qué sabe ya la previsión del andén.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    @State private var stats: StatsResponse?
    @State private var platform: PlatformModelResponse?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Historial")
                    .font(TypeScale.title)
                    .foregroundStyle(Palette.ink)

                if let stats {
                    bigNumbers(stats.overall)
                    if !stats.byMonth.isEmpty { months(stats.byMonth) }
                    if !stats.byLine.isEmpty { lines(stats.byLine) }
                }

                if let platform { platformBlock(platform) }

                if let error {
                    Text(error)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.bad)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .refreshable { await load() }
        .task { await load() }
    }

    // ---------------- cifras grandes ----------------

    private func bigNumbers(_ overall: OverallStat) -> some View {
        HStack(spacing: 12) {
            StatTile(value: "\(overall.n)", unit: nil, label: "Consultas")
            StatTile(value: decimal(overall.avgDelay), unit: "min",
                     label: "Retraso medio")
        }
    }

    private func months(_ rows: [MonthStat]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Días con incidencia").overlineStyle()
            VStack(spacing: 10) {
                ForEach(rows) { month in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(month.monthLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(month.badDays) de \(month.totalDays)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.inkMuted)
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.surfaceHi)
                                Capsule().fill(Palette.warn.opacity(0.8))
                                    .frame(width: max(3, proxy.size.width * month.badShare))
                            }
                        }
                        .frame(height: 7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    private func lines(_ rows: [LineStat]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("La que más me falla").overlineStyle()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    HStack(spacing: 12) {
                        Text(row.worstLine)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .frame(minWidth: 34, alignment: .leading)
                        Text("\(row.n) incidencias")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkMuted)
                        Spacer(minLength: 0)
                        if row.avgDelay > 0 {
                            Text("\(decimal(row.avgDelay)) min")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Palette.warn)
                                .monospacedDigit()
                        }
                    }
                    .frame(minHeight: 46)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    // ---------------- previsión del andén ----------------

    /// El porcentaje de acierto sale de aquí y solo de aquí. El servidor se
    /// puntúa solo y sin sesgo: cuando aparece la vía real le pregunta al
    /// modelo qué habría dicho SIN los datos de hoy y compara. Por eso la app
    /// no le pregunta nunca al usuario si acertó.
    private func platformBlock(_ info: PlatformModelResponse) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Previsión del andén").overlineStyle()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    StatTile(value: info.accuracy.percentLabel, unit: nil,
                             label: "Acierto", compact: true)
                    StatTile(value: "\(info.accuracy.observations)", unit: nil,
                             label: "Andenes vistos", compact: true)
                    StatTile(value: "\(info.accuracy.days)", unit: nil,
                             label: "Días aprendiendo", compact: true)
                }

                if info.accuracy.predictions == 0 {
                    Text("Todavía no ha hecho ninguna previsión que puntuar. La vía solo aparece en el 17 % de los trenes, así que hacen falta unos cuantos días.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !info.coverage.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(info.routeName.map { "Cobertura en \($0)" } ?? "Cobertura")
                            .overlineStyle()
                        ForEach(info.coverage) { leg in
                            HStack(spacing: 10) {
                                Text(leg.lineCode)
                                    .font(.system(size: 12.5, weight: .black, design: .rounded))
                                    .foregroundStyle(Palette.ink)
                                    .frame(minWidth: 34, alignment: .leading)
                                Text(leg.observations == 0
                                     ? "esta línea no publica vía"
                                     : "\(leg.observations) andenes · \(leg.days) días · \(leg.platforms) vías")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(leg.observations == 0
                                                     ? Palette.inkFaint : Palette.inkMuted)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 30)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // ---------------- carga ----------------

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await model.api.stats()
            platform = try? await model.api.platformModel(
                routeId: model.board.currentRouteId)
            error = nil
        } catch {
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

/// Una cifra grande con su rótulo.
struct StatTile: View {
    let value: String
    let unit: String?
    let label: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(TypeScale.minutes(compact ? 24 : 36))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Text(label).overlineStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 11 : 15)
        .cardSurface(compact ? 15 : 20)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Historial") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                StatTile(value: "128", unit: nil, label: "Consultas")
                StatTile(value: "3,4", unit: "min", label: "Retraso medio")
            }
            HStack(spacing: 12) {
                StatTile(value: "84 %", unit: nil, label: "Acierto", compact: true)
                StatTile(value: "4820", unit: nil, label: "Andenes vistos", compact: true)
                StatTile(value: "26", unit: nil, label: "Días", compact: true)
            }
        }
        .padding()
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
