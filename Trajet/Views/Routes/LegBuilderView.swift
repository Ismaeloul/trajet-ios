import SwiftUI

/// Montar un tramo en tres pasos: la parada, la línea y el sentido.
///
/// El tercero es el que importa. El sentido se elige entre los destinos que
/// están circulando AHORA por esa parada, nunca se escribe: el planificador
/// dice «La Défense (Puteaux)» y el tiempo real dice «La Défense», y copiar el
/// texto a mano deja el tablero mudo sin explicar por qué.
struct LegBuilderView: View {
    let onDone: (DraftLeg) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var stops: [StopResult] = []
    @State private var searching = false

    @State private var stop: StopResult?
    @State private var lines: [StopLine] = []
    @State private var loadingLines = false

    @State private var line: StopLine?
    @State private var directions: [String] = []
    @State private var loadingDirections = false
    @State private var chosen: Set<String> = []

    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let stop, let line {
                    directionStep(stop: stop, line: line)
                } else if let stop {
                    lineStep(stop: stop)
                } else {
                    stopStep
                }
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(stop == nil ? "Cancelar" : "Atrás") { back() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func back() {
        if line != nil { line = nil; directions = []; chosen = [] }
        else if stop != nil { stop = nil; lines = [] }
        else { dismiss() }
    }

    // ---------------- 1. la parada ----------------

    private var stopStep: some View {
        List {
            ForEach(stops) { result in
                Button {
                    stop = result
                    Task { await loadLines(result) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        if !result.city.isEmpty {
                            Text(result.city)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .listRowBackground(Palette.surface)
            }

            if let error {
                Text(error)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.bad)
                    .listRowBackground(Color.clear)
            } else if stops.isEmpty && !query.isEmpty && !searching {
                Text("Ninguna parada con ese nombre")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.inkMuted)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("¿Desde qué parada?")
        .searchable(text: $query, prompt: "Gare Saint-Lazare…")
        .overlay { if searching { ProgressView() } }
        .task(id: query) {
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                stops = []
                return
            }
            // Un respiro antes de llamar: la cuota es de mil al día y no hay
            // que gastar una por cada tecla.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await searchStops()
        }
    }

    private func searchStops() async {
        searching = true
        defer { searching = false }
        do {
            stops = try await model.api.searchStops(query)
            self.error = nil
        } catch {
            stops = []
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // ---------------- 2. la línea ----------------

    private func lineStep(stop: StopResult) -> some View {
        List {
            // El servidor ya las manda ordenadas: metro, RER, Transilien, TER,
            // tranvía y los buses al final. Saint-Lazare tiene 38 líneas y 30
            // son buses; por orden alfabético el metro quedaba enterrado.
            ForEach(lines) { candidate in
                Button {
                    line = candidate
                    Task { await loadDirections(stop: stop, line: candidate) }
                } label: {
                    HStack(spacing: 12) {
                        LineBadge(code: candidate.code, color: candidate.color, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name.isEmpty ? candidate.code : candidate.name)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(candidate.mode)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(stop.name)
        .overlay { if loadingLines { ProgressView() } }
    }

    private func loadLines(_ stop: StopResult) async {
        loadingLines = true
        defer { loadingLines = false }
        do {
            lines = try await model.api.lines(atStop: stop.id)
            if lines.isEmpty { lines = stop.lines }
        } catch {
            lines = stop.lines            // lo que trajo el buscador ya sirve
        }
    }

    // ---------------- 3. el sentido ----------------

    private func directionStep(stop: StopResult, line: StopLine) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(directions, id: \.self) { destination in
                        Button {
                            if chosen.contains(destination) { chosen.remove(destination) }
                            else { chosen.insert(destination) }
                        } label: {
                            HStack {
                                Text(destination)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if chosen.contains(destination) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.ok)
                                }
                            }
                            .frame(minHeight: 48)
                        }
                        .listRowBackground(Palette.surface)
                    }
                } header: {
                    Text(directions.isEmpty
                         ? "Ahora mismo no circula nada por aquí"
                         : "Sentidos que circulan ahora")
                        .overlineStyle()
                } footer: {
                    Text("Si no eliges ninguno se enseñan todos los pasos de la línea, en los dos sentidos.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            Button {
                onDone(DraftLeg(
                    stopId: stop.id, stopName: stop.name,
                    lineId: line.id, lineCode: line.code,
                    lineName: line.name, lineMode: line.mode,
                    lineColor: line.color, directions: chosen.sorted()))
                dismiss()
            } label: {
                Text("Añadir el tramo")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .navigationTitle("Línea \(line.code)")
        .overlay { if loadingDirections { ProgressView() } }
    }

    private func loadDirections(stop: StopResult, line: StopLine) async {
        loadingDirections = true
        defer { loadingDirections = false }
        directions = (try? await model.api.directions(atStop: stop.id,
                                                      lineId: line.id)) ?? []
    }
}
