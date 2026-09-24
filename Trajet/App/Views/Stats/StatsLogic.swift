import Foundation
import Observation

// Lógica del Historial que NO es vista (F45–F49, sistema.md §7.16): qué se
// dice de /api/v1/stats y de /api/v1/platform-model. Funciones puras sobre
// los modelos de la API, para probarlas sin pintar nada
// (TrajetTests/StatsLogicTests.swift).
//
// Dos cosas que no se pueden torcer:
// - R11: el porcentaje de acierto de la previsión de vía sale SOLO de
//   /api/v1/platform-model. La app nunca pregunta al usuario si acertó. Por
//   eso `StatsText.accuracy` solo acepta un `PlatformModelResponse` (ni la
//   salud del servidor ni nada calculado aquí).
// - Los datos dicen lo que dicen (ajustes-b.md A14): `overall.n` son
//   consultas y `by_line[].n` son filas del historial («veces la peor»), no
//   días; `max_delay` es el retraso máximo, no «el peor día».

/// Una ficha de cifra (consultas, retraso medio, retraso máximo).
struct StatTileModel: Equatable, Sendable, Identifiable {
    var id: String { caption }
    var value: String
    var unit: String?
    var caption: String
    var spoken: String
}

/// Una barra de «días con incidencias» de un mes.
struct MonthBar: Equatable, Sendable, Identifiable {
    var id: String
    /// «agosto 2026» (mes completo, R56).
    var label: String
    var bad: Int
    var total: Int
    /// «11/21».
    var fraction: String
    /// «11 de 21 días con incidencias».
    var spokenValue: String
}

/// Una línea de «la que más me falla».
struct LineFailure: Equatable, Sendable, Identifiable {
    var id: String { code }
    var code: String
    var color: String
    var n: Int
    /// «24 veces la peor».
    var timesText: String
    /// «retraso medio 4,6 min», si hay.
    var delayText: String?
    /// «24 · 4,6 min».
    var annotation: String
    var spokenValue: String
}

/// Una fila de la cobertura de la previsión por tramo.
struct CoverageRow: Equatable, Sendable, Identifiable {
    var id: Int { seq }
    var seq: Int
    var code: String
    var color: String
    var publishesPlatform: Bool
    var text: String
}

/// Lo que se enseña de la previsión de vía (R11).
struct AccuracySummary: Equatable, Sendable {
    /// «84 %» (con espacio fino no separable) o «—».
    var percent: String
    /// «179 aciertos de 214», si ya hay previsiones puntuadas.
    var hitsText: String?
    /// «4820 trenes en 26 días · el servidor se puntúa solo».
    var basisText: String
    /// Aún no hay con qué puntuar.
    var waitingText: String?
    /// «Cobertura en Casa → Trabajo».
    var coverageTitle: String?
    var coverage: [CoverageRow]
    var spoken: String
}

enum StatsText {
    /// Los días que se piden (F49).
    static let periodDays = 90
    static let spanish = Locale(identifier: "es_ES")

    /// Decimales con coma (R56): 3.42 → «3,4»; 27.0 → «27».
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(spanish))
    }

    /// «3,4 min» o «—».
    static func minutes(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(decimal(value)) min"
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    // MARK: Resumen (F45)

    static func tiles(_ overall: OverallStat) -> [StatTileModel] {
        let avg = overall.avgDelay.map(decimal)
        let max = overall.maxDelay.map(decimal)
        return [
            StatTileModel(value: "\(overall.n)", unit: nil,
                          caption: overall.n == 1 ? "consulta" : "consultas",
                          spoken: count(overall.n, "consulta", "consultas")),
            StatTileModel(value: avg ?? "—", unit: avg == nil ? nil : "min", caption: "retraso medio",
                          spoken: avg.map { "retraso medio, \($0) minutos" } ?? "retraso medio, sin datos"),
            StatTileModel(value: max ?? "—", unit: max == nil ? nil : "min", caption: "retraso máximo",
                          spoken: max.map { "retraso máximo, \($0) minutos" } ?? "retraso máximo, sin datos"),
        ]
    }

    // MARK: Días con incidencias por mes (F46)

    static func monthBars(_ months: [MonthStat]) -> [MonthBar] {
        months.map { m in
            MonthBar(id: m.month, label: m.monthLabel, bad: m.badDays, total: m.totalDays,
                     fraction: "\(m.badDays)/\(m.totalDays)",
                     spokenValue: "\(m.badDays) de \(count(m.totalDays, "día", "días")) con incidencias")
        }
    }

    // MARK: La que más me falla (F47)

    /// El color de una línea: el de algún tramo guardado con ese código; si
    /// no hay, "" (el distintivo pone el gris de reserva, R57).
    static func lineColor(code: String, routes: [SavedRoute]) -> String {
        for route in routes {
            if let leg = route.legs.first(where: { $0.lineCode == code && !$0.lineColor.isEmpty }) {
                return leg.lineColor
            }
        }
        return ""
    }

    static func lineFailures(_ lines: [LineStat], routes: [SavedRoute]) -> [LineFailure] {
        lines.filter { !$0.worstLine.isEmpty }.map { line in
            let times = "\(count(line.n, "vez", "veces")) la peor"
            let delay = line.avgDelay.flatMap { $0 > 0 ? "retraso medio \(minutes($0))" : nil }
            let annotation = line.avgDelay.flatMap { $0 > 0 ? "\(line.n) · \(minutes($0))" : nil } ?? "\(line.n)"
            var spoken = times
            if let delay { spoken += ", \(delay)" }
            return LineFailure(code: line.worstLine, color: lineColor(code: line.worstLine, routes: routes),
                               n: line.n, timesText: times, delayText: delay, annotation: annotation,
                               spokenValue: spoken)
        }
    }

    // MARK: Previsión de vía (F48, R11)

    static let waiting = "La vía solo aparece en el 17 % de los trenes, así que hacen falta unos cuantos días."

    /// «84 %» con espacio fino no separable (en B se partía en dos líneas).
    /// Solo de `accuracy.rate` de /api/v1/platform-model (R11); sin dato, «—».
    static func percent(_ accuracy: PlatformAccuracy) -> String {
        guard let rate = accuracy.rate else { return "—" }
        return "\(Int((rate * 100).rounded()))\u{202F}%"
    }

    /// Todo lo que se enseña de la previsión. SOLO de /api/v1/platform-model
    /// (R11): no hay otra entrada.
    static func accuracy(_ model: PlatformModelResponse, route: SavedRoute?, routes: [SavedRoute] = []) -> AccuracySummary {
        let a = model.accuracy
        let percentText = percent(a)
        let hits = a.predictions > 0 ? "\(a.hits) \(a.hits == 1 ? "acierto" : "aciertos") de \(a.predictions)" : nil
        let basis = "\(count(a.observations, "tren", "trenes")) en \(count(a.days, "día", "días")) · el servidor se puntúa solo"
        let waitingText = a.predictions == 0 || a.rate == nil ? waiting : nil
        let rows = model.coverage.map { coverageRow($0, route: route, routes: routes) }
        let name = model.routeName ?? route?.name
        let title = rows.isEmpty ? nil : (name.map { "Cobertura en \($0)" } ?? "Cobertura por tramo")
        var spoken = a.rate == nil ? "Acierto de la previsión de vía: aún sin datos" : "Acierto de la previsión de vía: \(Int(((a.rate ?? 0) * 100).rounded())) por ciento"
        if let hits { spoken += ", \(hits)" }
        spoken += ". \(basis)."
        return AccuracySummary(percent: percentText, hitsText: hits, basisText: basis, waitingText: waitingText,
                               coverageTitle: title, coverage: rows, spoken: spoken)
    }

    /// Un tramo de la cobertura: «esta línea no publica vía» en metro, bus y
    /// tranvía (R3); si no, lo que se lleva visto.
    static func coverageRow(_ c: PlatformCoverage, route: SavedRoute?, routes: [SavedRoute]) -> CoverageRow {
        let leg = route?.legs.first { $0.seq == c.seq }
        let color = leg?.lineColor ?? lineColor(code: c.lineCode, routes: routes)
        let publishes = leg?.mode.publishesPlatform ?? (c.observations > 0)
        let text: String
        if c.observations == 0 {
            text = publishes ? "aún sin andenes vistos" : "esta línea no publica vía"
        } else {
            text = "\(count(c.observations, "tren visto", "trenes vistos")) · \(count(c.days, "día", "días")) · \(count(c.platforms, "vía", "vías"))"
        }
        return CoverageRow(seq: c.seq, code: c.lineCode.isEmpty ? (leg?.lineCode ?? "?") : c.lineCode,
                           color: color, publishesPlatform: publishes, text: text)
    }
}

/// El Historial: `/api/v1/stats?days=90` y después `/api/v1/platform-model`
/// con la ruta que se ve en el tablero (F49). Se pide al entrar y al tirar.
/// Un fallo de las estadísticas se enseña; uno de la previsión se calla y
/// oculta ese bloque. Nunca se borra lo que ya se tenía (R9).
@MainActor
@Observable
final class StatsModel {
    enum Phase: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var stats: StatsResponse?
    private(set) var platformModel: PlatformModelResponse?
    private(set) var phase: Phase = .loading
    /// El último fallo al recargar, con datos de antes en pantalla.
    private(set) var refreshError: String?
    private(set) var isLoading = false

    init() {}

    func load(stats fetchStats: @Sendable () async throws -> StatsResponse,
              platformModel fetchModel: @Sendable () async throws -> PlatformModelResponse) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if stats == nil { phase = .loading }
        do {
            stats = try await fetchStats()
            refreshError = nil
            phase = .loaded
        } catch is CancellationError {
            if stats != nil { phase = .loaded }
            return
        } catch {
            let message = (error as? APIError)?.errorDescription ?? "No se ha podido cargar el historial."
            if stats == nil {
                phase = .failed(message)
            } else {
                refreshError = message
                phase = .loaded
            }
        }
        do {
            platformModel = try await fetchModel()
        } catch {
            // F49: un fallo de la previsión se calla (se queda la anterior,
            // o el bloque no sale).
        }
    }
}
