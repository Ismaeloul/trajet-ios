import SwiftUI

/// Buscar trayecto (F40–F44, sistema.md §7.15): de un sitio a otro (paradas,
/// direcciones y sitios), cuándo, y las opciones con su duración,
/// transbordos, lo que se camina y las líneas. La opción que se use de
/// verdad se guarda como ruta vigilada («Guardar ruta»).
///
/// - Nada se pide hasta «Buscar» (el planificador gasta cuota de Navitia).
/// - «Llegar a» ≠ «Salir a» (R34): el servidor solo entiende `arrival` y
///   `departure`, con `when` «HH:MM»; «Ahora» va sin `when`.
/// - El rótulo de los resultados es el de la búsqueda hecha, no el del
///   formulario (F42).
/// - Al guardar, los tramos que se quedan sin sentido se dicen (R33).
///
/// Vive dentro de Rutas, en una hoja con «Cerrar»; trae su propia pila.
struct PlannerScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    @State private var model = PlannerModel()
    @State private var picking: PlannerEnd?
    @State private var saving: PlannerSaveItem?
    @State private var timeDate = ClockTime.date("09:00")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.gutter) {
                    form
                    results
                }
                .padding(.horizontal, Metrics.Space.gutter)
                .padding(.vertical, Metrics.Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Buscar trayecto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
        }
        .sheet(item: $picking) { end in
            PlaceSearchSheet(title: end == .from ? "¿Desde dónde?" : "¿Hasta dónde?") { place in
                switch end {
                case .from: model.from = place
                case .to: model.to = place
                }
            }
            .environment(services)
        }
        .sheet(item: $saving) { item in
            SavePlanSheet(search: item.search, option: item.option) {
                saving = nil
                if isPresented { dismiss() }
            }
            .environment(services)
            .environment(toasts)
        }
        .onChange(of: timeDate) { _, date in
            model.time = ClockTime.text(from: date)
        }
    }

    // MARK: - Formulario

    private var form: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.ml) {
            VStack(spacing: 0) {
                PlaceSearchField(label: "Desde", symbol: "smallcircle.filled.circle", place: model.from) {
                    picking = .from
                }
                HStack {
                    Rectangle()
                        .fill(Palette.rule)
                        .frame(height: Metrics.Size.hairline)
                    Button {
                        model.swapEnds()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .hitTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.from == nil && model.to == nil)
                    .accessibilityLabel("Dar la vuelta")
                }
                PlaceSearchField(label: "Hasta", symbol: "mappin.and.ellipse", place: model.to) {
                    picking = .to
                }
            }
            .padding(.horizontal, Metrics.Size.cardPadding + Metrics.Space.xs)
            .padding(.vertical, Metrics.Space.xs)
            .cardBackground()

            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                Picker("Cuándo", selection: $model.timing) {
                    ForEach(PlannerTiming.allCases) { timing in
                        Text(timing.label).tag(timing)
                    }
                }
                .pickerStyle(.segmented)
                if model.timing != .now {
                    DatePicker(timeTitle, selection: $timeDate, displayedComponents: .hourAndMinute)
                        .textLevel(.body)
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(Metrics.Size.cardPadding + Metrics.Space.xs)
            .cardBackground()

            Button {
                runSearch()
            } label: {
                HStack(spacing: Metrics.Space.sm) {
                    if model.isSearching {
                        ProgressView()
                            .tint(Palette.onAccent)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Buscar itinerarios")
                }
            }
            .filledButton(.primary)
            .disabled(!model.canSearch)
            .accessibilityHint(searchHint)
        }
    }

    private var timeTitle: String {
        model.timing == .arrival ? "Llegar a las" : "Salir a las"
    }

    private var searchHint: String {
        if model.from == nil || model.to == nil { return "Elige primero de dónde y a dónde." }
        if model.from?.id == model.to?.id { return "El origen y el destino son el mismo sitio." }
        return ""
    }

    // MARK: - Resultados

    @ViewBuilder
    private var results: some View {
        switch model.phase {
        case .idle, .searching:
            if model.from != nil, model.to != nil, model.from?.id == model.to?.id {
                Text("El origen y el destino son el mismo sitio.")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.warnText)
            }
        case .empty(let search):
            heading(search, age: nil)
            MessageStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                             title: "Ningún trayecto", message: PlannerText.noOptions)
        case .failed(let message):
            MessageStateView(symbol: "exclamationmark.triangle", tint: Palette.badText,
                             title: "No se ha podido buscar", message: message) {
                Button {
                    runSearch()
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .cristalButton()
                .controlSize(.large)
                .disabled(!model.canSearch)
            }
        case .loaded(let reply, let search):
            heading(search, age: reply.age)
            Text(PlannerText.tip)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
            ForEach(reply.options) { option in
                PlanOptionCard(option: option) {
                    saving = PlannerSaveItem(search: search, option: option)
                }
            }
        }
    }

    private func heading(_ search: PlannerSearch, age: Double?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(search.heading)
                .textLevel(.kicker)
                .foregroundStyle(Palette.ink2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.Space.sm)
            if let age {
                Text(Fmt.age(age))
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.top, Metrics.Space.sm)
    }

    private func runSearch() {
        let api = services.api
        Task {
            await model.search { from, to, when, mode in
                try await api.plan(from: from, to: to, when: when, mode: mode)
            }
        }
    }
}

/// Qué extremo se está eligiendo.
enum PlannerEnd: String, Identifiable, Hashable {
    case from
    case to

    var id: String { rawValue }
}

/// La opción que se va a guardar (con la búsqueda que la dio).
struct PlannerSaveItem: Identifiable, Equatable {
    let search: PlannerSearch
    let option: PlanOption

    var id: String { option.id }
}

/// Una opción del planificador: minutos (con «1h02» si pasa de la hora,
/// R6), qué tipo es, «08:07 → 08:54», los tramos con su distintivo y
/// «1 transbordo · 11 min a pie». Tarjeta opaca, como las alternativas.
struct PlanOptionCard: View {
    let option: PlanOption
    var onSave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.minutes(option.minutes))
                        .numberFont(.stat)
                        .foregroundStyle(Palette.ink)
                    if let unit = Fmt.minutesUnit(option.minutes) {
                        Text(unit)
                            .textLevel(.unit)
                            .foregroundStyle(Palette.ink3)
                    }
                }
                if let kind = PlannerText.kind(option.kind) {
                    Text(kind)
                        .textLevel(.label)
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, Metrics.Space.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.surfaceHi))
                }
                Spacer(minLength: Metrics.Space.sm)
                if let times = PlannerText.times(option) {
                    Text(times)
                        .textLevel(.meta)
                        .foregroundStyle(Palette.ink2)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                ForEach(Array(option.legs.enumerated()), id: \.offset) { _, leg in
                    PlanLegRow(leg: leg)
                }
            }
            HStack(alignment: .center, spacing: Metrics.Space.sm) {
                Text(PlannerText.summary(option))
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: Metrics.Space.sm)
                if let onSave {
                    Button(action: onSave) {
                        Label("Guardar ruta", systemImage: "plus")
                            .textLevel(.buttonSmall)
                    }
                    .cristalButton()
                    .accessibilityHint("Guarda este itinerario como ruta vigilada")
                }
            }
        }
        .padding(Metrics.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PlannerText.spoken(option))
    }
}

private struct PlanLegRow: View {
    let leg: PlanLeg

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            LineBadge(code: leg.lineCode.isEmpty ? leg.lineName : leg.lineCode, color: leg.lineColor,
                      size: Metrics.Size.badgeSmall)
            VStack(alignment: .leading, spacing: 0) {
                Text(PlannerText.legTitle(leg))
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                let detail = [leg.fromName, PlannerText.legDetail(leg)].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

/// «Guardar ruta» desde el planificador (F43): nombre (por defecto «origen
/// → destino»), días (lunes a viernes) y cómo se guardará el horario. Si el
/// servidor dice que algún tramo se quedó sin sentido, se queda abierta y lo
/// dice (R33); «Guardar» ya no se puede volver a pulsar (la v1 dejaba crear
/// otra ruta igual).
struct SavePlanSheet: View {
    let search: PlannerSearch
    let option: PlanOption
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var days: Set<Int> = [0, 1, 2, 3, 4]
    @State private var saving = false
    @State private var saveError: String?
    /// Guardada con tramos sin sentido: el aviso (R33).
    @State private var warning: String?

    init(search: PlannerSearch, option: PlanOption, onFinished: @escaping () -> Void) {
        self.search = search
        self.option = option
        self.onFinished = onFinished
        _name = State(initialValue: PlannerText.defaultName(search))
    }

    private var meta: PlanSaveRequest.Meta {
        PlannerText.saveMeta(search: search, option: option, name: name, days: days)
    }

    private var saved: Bool { warning != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlanOptionCard(option: option)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if let warning {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                                Text("Guardada, pero con un aviso")
                                    .textLevel(.bodyStrong)
                                Text(warning)
                                    .textLevel(.callout)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(Palette.warnText)
                    }
                }
                Section {
                    TextField("Nombre", text: $name)
                        .textLevel(.bodyStrong)
                        .disabled(saved)
                        .accessibilityLabel("Nombre de la ruta")
                } header: {
                    Text("Nombre")
                        .textLevel(.kicker)
                        .foregroundStyle(Palette.ink3)
                }
                Section {
                    WeekdayPicker(days: days) { day in
                        guard !saved else { return }
                        if days.contains(day) { days.remove(day) } else { days.insert(day) }
                    }
                    .listRowInsets(EdgeInsets(top: Metrics.Space.sm, leading: Metrics.Space.sm,
                                              bottom: Metrics.Space.sm, trailing: Metrics.Space.sm))
                } header: {
                    Text("Días de uso")
                        .textLevel(.kicker)
                        .foregroundStyle(Palette.ink3)
                } footer: {
                    Text(PlannerText.saveExplanation(meta: meta, option: option))
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .textLevel(.callout)
                            .foregroundStyle(Palette.badText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Guardar ruta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                            .disabled(saving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                            .accessibilityLabel("Guardando")
                    } else if saved {
                        Button("Hecho") { onFinished() }
                            .fontWeight(.semibold)
                    } else {
                        Button("Guardar") { save() }
                            .fontWeight(.semibold)
                            .disabled(days.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard !saving, !saved else { return }
        saving = true
        saveError = nil
        let store = services.routes
        let toasts = self.toasts
        let request = PlanSaveRequest(option: option, meta: meta)
        Task {
            do {
                let reply = try await store.saveFromPlan(request)
                saving = false
                toasts?.show("Ruta guardada", symbol: "checkmark")
                if let text = PlannerText.withoutDirection(reply.withoutDirection) {
                    warning = text
                } else {
                    onFinished()
                }
            } catch {
                saving = false
                if let api = error as? APIError, let text = api.errorDescription {
                    saveError = text
                } else {
                    saveError = "No se ha podido guardar."
                }
            }
        }
    }
}

#if DEBUG
#Preview("Buscar trayecto (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        PlannerScreen()
    }
}

#Preview("Opciones del planificador") {
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            ForEach(PreviewData.planOptions) { option in
                PlanOptionCard(option: option) {}
            }
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
