import SwiftUI

/// Montar un tramo en tres pasos (F36–F39), en su propia pila:
///
/// 1. **Parada**: buscador con 2 caracteres como mínimo y 350 ms de espera;
///    cada tecla cancela la búsqueda anterior (R31: gasta cuota).
/// 2. **Línea**: las de la parada en el orden en que las manda el servidor
///    (metro, RER, Transilien, TER, tranvía y los buses al final; la app no
///    reordena, R62). Si la llamada falla o viene vacía, las del buscador.
/// 3. **Sentido**: de los que circulan AHORA (`/stops/{id}/directions`), con
///    selección múltiple; sin elegir ninguno = todos, y se avisa (R32). El
///    sentido se elige, no se escribe: un texto mal escrito dejaría el
///    tablero vacío sin decir nada.
///
/// «Cancelar» en el primer paso; «atrás» (el de la pila) en los otros.
struct LegBuilderView: View {
    let onAdd: (RouteDraft.LegDraft) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var path: [LegBuilderStep] = []
    @State private var query = ""
    @State private var search = StopSearchModel()
    @FocusState private var searchFocused: Bool

    // Explícito: con estado privado, el inicializador sintetizado sería privado.
    init(onAdd: @escaping (RouteDraft.LegDraft) -> Void) {
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    SearchFieldRow(prompt: "Gare Saint-Lazare…", text: $query, focused: $searchFocused)
                        .listRowBackground(Palette.surface)
                }
                results
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("¿Desde qué parada?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .navigationDestination(for: LegBuilderStep.self) { step in
                switch step {
                case .lines(let stop):
                    LegLineStep(stop: stop) { line in
                        path.append(.directions(stop, line))
                    }
                case .directions(let stop, let line):
                    LegDirectionStep(stop: stop, line: line) { leg in
                        onAdd(leg)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: query) { _, text in
            let api = services.api
            search.textChanged(text) { q in try await api.searchStops(q) }
        }
        .task {
            // Que se pueda escribir sin tocar el campo.
            try? await Task.sleep(for: .milliseconds(350))
            searchFocused = true
        }
    }

    @ViewBuilder
    private var results: some View {
        switch search.phase {
        case .idle:
            Section {
                Text(query.isEmpty ? "Escribe el nombre de la parada donde subes." : SearchText.typeMore)
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink3)
                    .listRowBackground(Color.clear)
            }
        case .searching where search.results.isEmpty:
            Section {
                SearchingRow()
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.badText)
                    .listRowBackground(Color.clear)
            }
        default:
            if search.results.isEmpty {
                Section {
                    Text(SearchText.noStops)
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(search.results) { stop in
                        Button {
                            path.append(.lines(stop))
                        } label: {
                            StopResultRow(stop: stop)
                        }
                        .listRowBackground(Palette.surface)
                    }
                }
            }
        }
    }
}

/// Los pasos 2 y 3 en la pila.
enum LegBuilderStep: Hashable {
    case lines(StopResult)
    case directions(StopResult, StopLine)
}

/// Una parada en los resultados: nombre y ciudad, y los distintivos de las
/// líneas que trae el buscador (si trae).
private struct StopResultRow: View {
    let stop: StopResult

    var body: some View {
        HStack(spacing: Metrics.Space.ml) {
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(stop.name.isEmpty ? "Parada sin nombre" : stop.name)
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                if !stop.city.isEmpty {
                    Text(stop.city)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                let lines = stop.lines.filter { !$0.displayCode.isEmpty }
                if !lines.isEmpty {
                    RouteLineChain(codes: lines.prefix(8).map { LineChainItem(code: $0.displayCode, color: $0.color) })
                        .padding(.top, Metrics.Space.hair)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.Size.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stop.city.isEmpty ? stop.name : "\(stop.name), \(stop.city)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Paso 2: la línea.
private struct LegLineStep: View {
    let stop: StopResult
    let onPick: (StopLine) -> Void

    @Environment(AppServices.self) private var services
    @State private var loaded: [StopLine]?
    @State private var isLoading = true

    init(stop: StopResult, onPick: @escaping (StopLine) -> Void) {
        self.stop = stop
        self.onPick = onPick
    }

    var body: some View {
        List {
            if isLoading {
                Section { SearchingRow(text: "Buscando las líneas…") }
            } else {
                let lines = LegBuilderLogic.lines(loaded: loaded, fallback: stop.lines)
                if lines.isEmpty {
                    Section {
                        Text("No se ha encontrado ninguna línea en esta parada.")
                            .textLevel(.callout)
                            .foregroundStyle(Palette.ink2)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(lines) { line in
                            Button {
                                onPick(line)
                            } label: {
                                lineRow(line)
                            }
                            .listRowBackground(Palette.surface)
                        }
                    } header: {
                        Text("¿Qué línea coges?")
                            .textLevel(.kicker)
                            .foregroundStyle(Palette.ink3)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle(stop.name.isEmpty ? "Línea" : stop.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard loaded == nil else { return }
            let api = services.api
            let stopID = stop.id
            do {
                loaded = try await api.stopLines(stopID: stopID)
            } catch {
                // F37: si falla, las que trajo el buscador.
                loaded = []
            }
            isLoading = false
        }
    }

    private func lineRow(_ line: StopLine) -> some View {
        HStack(spacing: Metrics.Space.ml) {
            LineBadge(code: line.displayCode, color: line.color, size: Metrics.Size.badge)
            VStack(alignment: .leading, spacing: 0) {
                Text("Línea \(line.displayCode)")
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                let subtitle = LegBuilderLogic.lineSubtitle(line)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: line.transport.symbol)
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.Size.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Paso 3: el sentido (R32).
private struct LegDirectionStep: View {
    let stop: StopResult
    let line: StopLine
    let onAdd: (RouteDraft.LegDraft) -> Void

    @Environment(AppServices.self) private var services
    @State private var directions: [String] = []
    @State private var chosen: Set<String> = []
    @State private var phase: DirectionsPhase = .loading

    enum DirectionsPhase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    init(stop: StopResult, line: StopLine, onAdd: @escaping (RouteDraft.LegDraft) -> Void) {
        self.stop = stop
        self.line = line
        self.onAdd = onAdd
    }

    var body: some View {
        List {
            switch phase {
            case .loading:
                Section { SearchingRow(text: "Mirando qué circula ahora…") }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.badText)
                    Button("Reintentar") {
                        Task { await load() }
                    }
                    .frame(minHeight: Metrics.Size.hit)
                }
                .listRowBackground(Palette.surface)
            case .loaded:
                Section {
                    ForEach(directions, id: \.self) { direction in
                        directionRow(direction)
                    }
                } header: {
                    Text(LegBuilderLogic.directionsHeader(directions))
                        .textLevel(.kicker)
                        .foregroundStyle(Palette.ink3)
                } footer: {
                    Text(LegBuilderLogic.allDirectionsFooter)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            if phase != .loading, chosen.isEmpty {
                Section {
                    Label(RouteText.allDirectionsWarning, systemImage: "exclamationmark.triangle")
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.warnText)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Línea \(line.displayCode)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd(LegBuilderLogic.leg(stop: stop, line: line, chosen: chosen, available: directions))
            } label: {
                Label("Añadir el tramo", systemImage: "plus")
            }
            .filledButton(.primary)
            .disabled(phase == .loading)
            .padding(.horizontal, Metrics.Space.gutter)
            .padding(.vertical, Metrics.Space.sm)
            .background(Palette.bg.opacity(0.92))
        }
        .task {
            if phase == .loading { await load() }
        }
    }

    private func directionRow(_ direction: String) -> some View {
        let isOn = chosen.contains(direction)
        return Button {
            if isOn { chosen.remove(direction) } else { chosen.insert(direction) }
        } label: {
            HStack(spacing: Metrics.Space.ml) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                Text(direction)
                    .textLevel(.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Metrics.Size.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .accessibilityLabel("Dirección \(direction)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func load() async {
        phase = .loading
        let api = services.api
        let stopID = stop.id
        let lineID = line.id
        do {
            directions = try await api.stopDirections(stopID: stopID, lineID: lineID)
            chosen = chosen.intersection(directions)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as APIError {
            phase = .failed((error.errorDescription ?? "No se ha podido mirar.") + " Puedes añadir el tramo sin sentido y elegirlo luego.")
        } catch {
            phase = .failed("No se ha podido mirar qué circula. Puedes añadir el tramo sin sentido y elegirlo luego.")
        }
    }
}

/// «Buscando…» con su rueda.
struct SearchingRow: View {
    var text: String = "Buscando…"

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            ProgressView()
            Text(text)
                .textLevel(.callout)
                .foregroundStyle(Palette.ink2)
        }
        .frame(minHeight: Metrics.Size.row)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// Campo de búsqueda: lupa, texto y botón para borrar. Sin autocorrección:
/// los nombres de estaciones no están en el diccionario.
struct SearchFieldRow: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textLevel(.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.ink3)
                        .hitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar el texto")
            }
        }
        .frame(minHeight: Metrics.Size.hit)
    }
}

#if DEBUG
#Preview("Montar un tramo (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        LegBuilderView { _ in }
    }
}
#endif
