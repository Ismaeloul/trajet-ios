import SwiftUI

/// Crear o editar una ruta a mano (F33–F35, sistema.md §7.15).
///
/// - Nombre, origen y destino (si se dejan vacíos salen de los tramos),
///   días (L M X J V S D, 0 = lunes, lunes a viernes por defecto, R36) y
///   cuándo toca: «Llego a / Salgo a / Franja» (por defecto «Llego a
///   09:00»). Con «Llego a» y «Salgo a» el servidor calcula la franja (R38);
///   aquí se dice cómo y cuál sale.
/// - Tramos: se montan en tres pasos (`LegBuilderView`: parada, línea y
///   sentido de los que circulan ahora, R31, R32, R62). Uno sin sentido se
///   marca en color de aviso: se verán todos los pasos de la línea (R32).
/// - «Guardar» manda `RouteInput` (`routes.create/update`); el tablero se
///   refresca solo (R39) y se dice con un aviso efímero (R55). El error se
///   enseña debajo, sin cerrar.
/// - Editando: «Eliminar ruta», con confirmación.
///
/// Se usa empujada desde Rutas (editar) o dentro de una hoja con su
/// `NavigationStack` (nueva). Cierra con `dismiss` en los dos casos.
struct RouteEditorView: View {
    let route: SavedRoute?

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.dismiss) private var dismiss

    @State private var state: RouteEditorState
    private let initial: RouteEditorState
    // Las horas del selector nativo (se pasan a «HH:MM» al cambiar).
    @State private var atDate: Date
    @State private var fromDate: Date
    @State private var toDate: Date

    @State private var addingLeg = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false

    init(route: SavedRoute?) {
        self.route = route
        let start = RouteEditorState(route: route)
        self.initial = start
        _state = State(initialValue: start)
        _atDate = State(initialValue: ClockTime.date(start.timeAt))
        _fromDate = State(initialValue: ClockTime.date(start.timeFrom))
        _toDate = State(initialValue: ClockTime.date(start.timeTo))
    }

    private var isNew: Bool { route == nil }
    private var hasChanges: Bool { state != initial }

    var body: some View {
        Form {
            nameSection
            endpointsSection
            daysSection
            scheduleSection
            legsSection
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.badText)
                }
            }
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Eliminar ruta", systemImage: "trash")
                            .foregroundStyle(Palette.badText)
                            .frame(minHeight: Metrics.Size.hit)
                    }
                    .disabled(saving)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle(isNew ? "Nueva ruta" : "Editar ruta")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges || saving)
        .toolbar { editorToolbar }
        .interactiveDismissDisabled(hasChanges || saving)
        .sheet(isPresented: $addingLeg) {
            LegBuilderView { leg in
                state.addLeg(leg)
            }
            .environment(services)
        }
        .confirmationDialog("¿Descartar los cambios?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Seguir editando", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar «\(state.trimmedName.isEmpty ? "esta ruta" : state.trimmedName)»?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar ruta", role: .destructive) { deleteRoute() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra también su historial. Los andenes aprendidos se quedan.")
        }
        .onChange(of: atDate) { _, date in state.timeAt = ClockTime.text(from: date) }
        .onChange(of: fromDate) { _, date in state.timeFrom = ClockTime.text(from: date) }
        .onChange(of: toDate) { _, date in state.timeTo = ClockTime.text(from: date) }
    }

    // MARK: - Secciones

    private var nameSection: some View {
        Section {
            TextField("Casa → Trabajo", text: $state.name)
                .textLevel(.bodyStrong)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .accessibilityLabel("Nombre de la ruta")
        } header: {
            sectionHeader("Nombre")
        }
    }

    private var endpointsSection: some View {
        let derived = state.derived
        return Section {
            LabeledContent {
                TextField("Origen", text: $state.originName,
                          prompt: Text(derived.originName.isEmpty ? "la primera parada" : derived.originName))
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Origen")
            } label: {
                Text("Origen")
            }
            LabeledContent {
                TextField("Destino", text: $state.destName,
                          prompt: Text(derived.destName.isEmpty ? "el último sentido" : derived.destName))
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Destino")
            } label: {
                Text("Destino")
            }
        } header: {
            sectionHeader("De dónde a dónde")
        } footer: {
            Text("Si los dejas vacíos, salen de los tramos: la parada del primero y el sentido del último.")
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }

    private var daysSection: some View {
        Section {
            WeekdayPicker(days: state.days) { day in
                state.toggleDay(day)
            }
            .listRowInsets(EdgeInsets(top: Metrics.Space.sm, leading: Metrics.Space.sm,
                                      bottom: Metrics.Space.sm, trailing: Metrics.Space.sm))
        } header: {
            sectionHeader("Días de uso")
        } footer: {
            Text(state.days.isEmpty ? "Ningún día marcado." : "Se usa \(RouteText.daysLabel(state.days)).")
                .textLevel(.footnote)
                .foregroundStyle(state.days.isEmpty ? Palette.warnText : Palette.ink3)
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Cuándo toca", selection: $state.timeMode) {
                ForEach(TimeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: Metrics.Space.sm, leading: Metrics.Space.ml,
                                      bottom: Metrics.Space.sm, trailing: Metrics.Space.ml))
            switch state.timeMode {
            case .arrival:
                DatePicker("Llego a las", selection: $atDate, displayedComponents: .hourAndMinute)
            case .departure:
                DatePicker("Salgo a las", selection: $atDate, displayedComponents: .hourAndMinute)
            case .window:
                DatePicker("Desde", selection: $fromDate, displayedComponents: .hourAndMinute)
                DatePicker("Hasta", selection: $toDate, displayedComponents: .hourAndMinute)
            }
        } header: {
            sectionHeader("Cuándo toca")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                Text(RouteText.windowExplanation(mode: state.timeMode, at: state.timeAt, durationMin: state.durationMin))
                if state.problems.contains(.window) {
                    Text("«Desde» tiene que ser antes que «Hasta»: la franja no cruza la medianoche.")
                        .foregroundStyle(Palette.warnText)
                }
            }
            .textLevel(.footnote)
            .foregroundStyle(Palette.ink3)
        }
    }

    private var legsSection: some View {
        Section {
            ForEach(Array(state.legs.enumerated()), id: \.offset) { index, leg in
                legRow(leg, index: index)
            }
            Button {
                addingLeg = true
            } label: {
                Label(state.legs.isEmpty ? "Añadir el primer tramo" : "Añadir transbordo",
                      systemImage: "plus.circle.fill")
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: Metrics.Size.hit)
            }
            .disabled(saving)
        } header: {
            sectionHeader("Itinerario")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                if !state.legsWithoutDirection.isEmpty {
                    Label(RouteText.allDirectionsWarning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warnText)
                }
                if let problems = state.problemsText, hasChanges || !isNew {
                    Text(problems)
                }
            }
            .textLevel(.footnote)
            .foregroundStyle(Palette.ink3)
        }
    }

    private func legRow(_ leg: RouteDraft.LegDraft, index: Int) -> some View {
        let code = leg.lineCode.isEmpty ? leg.lineName : leg.lineCode
        let hasDirection = leg.directions.contains { !$0.isEmpty }
        return HStack(spacing: Metrics.Space.ml) {
            LineBadge(code: code, color: leg.lineColor, size: Metrics.Size.badge)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(RouteText.legTitle(fromName: leg.fromName, toName: leg.toName))
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if hasDirection {
                    Text(RouteText.direction(leg.directions))
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                } else {
                    Label(RouteText.allDirections, systemImage: "exclamationmark.triangle")
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.warnText)
                }
            }
            Spacer(minLength: 0)
            Button {
                state.removeLeg(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.ink3)
                    .hitTarget()
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .accessibilityLabel("Quitar el tramo \(code)")
        }
        .accessibilityElement(children: .contain)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .textLevel(.kicker)
            .foregroundStyle(Palette.ink3)
    }

    // MARK: - Barra

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        if isNew || hasChanges {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    if hasChanges { confirmingDiscard = true } else { dismiss() }
                }
                .disabled(saving)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if saving {
                ProgressView()
                    .accessibilityLabel("Guardando")
            } else {
                Button("Guardar") { save() }
                    .fontWeight(.semibold)
                    .disabled(!state.canSave || (!isNew && !hasChanges))
            }
        }
    }

    // MARK: - Acciones

    private func save() {
        guard let draft = state.draft(), !saving else { return }
        saving = true
        saveError = nil
        let store = services.routes
        let toasts = self.toasts
        let routeID = route?.id
        Task {
            do {
                if let routeID {
                    try await store.update(id: routeID, draft)
                    toasts?.show("Ruta actualizada", symbol: "checkmark")
                } else {
                    try await store.create(draft)
                    toasts?.show("Ruta guardada", symbol: "checkmark")
                }
                saving = false
                dismiss()
            } catch {
                saving = false
                saveError = Self.message(error)
            }
        }
    }

    private func deleteRoute() {
        guard let routeID = route?.id, !saving else { return }
        saving = true
        saveError = nil
        let store = services.routes
        let toasts = self.toasts
        Task {
            do {
                try await store.delete(id: routeID)
                toasts?.show("Ruta borrada", symbol: "trash")
                saving = false
                dismiss()
            } catch {
                saving = false
                saveError = "No se ha podido borrar. \(Self.message(error))"
            }
        }
    }

    private static func message(_ error: Error) -> String {
        if let api = error as? APIError, let text = api.errorDescription { return text }
        return "No se ha podido guardar."
    }
}

#if DEBUG
#Preview("Editar ruta (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        NavigationStack {
            RouteEditorView(route: PreviewData.routes.first)
        }
    }
}

#Preview("Ruta nueva") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        NavigationStack {
            RouteEditorView(route: nil)
        }
    }
}
#endif
