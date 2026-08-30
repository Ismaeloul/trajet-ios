import SwiftUI

enum RouteEditorTarget: Identifiable {
    case create
    case edit(SavedRoute)

    var id: Int {
        switch self {
        case .create: -1
        case .edit(let route): route.id
        }
    }

    var route: SavedRoute? {
        if case .edit(let route) = self { return route }
        return nil
    }
}

/// Un tramo mientras se está montando, antes de guardarlo.
struct DraftLeg: Identifiable, Hashable {
    let id = UUID()
    var stopId: String
    var stopName: String
    var lineId: String
    var lineCode: String
    var lineName: String
    var lineMode: String
    var lineColor: String
    var directions: [String]
}

/// Montar o corregir una ruta a mano.
///
/// El sentido NO se escribe: se elige entre los destinos que están circulando
/// en ese momento, porque el texto del tiempo real no coincide con el del
/// planificador y un sentido mal escrito deja el tablero vacío sin decir nada.
struct RouteEditorView: View {
    let target: RouteEditorTarget
    let onSaved: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var days: Set<Int> = [0, 1, 2, 3, 4]
    @State private var timeMode: TimeMode = .arrival
    @State private var timeAt = "09:00"
    @State private var timeFrom = "07:00"
    @State private var timeTo = "10:00"
    @State private var legs: [DraftLeg] = []

    @State private var addingLeg = false
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool { target.route != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !legs.isEmpty && !days.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field("Nombre") {
                        TextField("Casa → Trabajo", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(13)
                            .cardSurface(15, fill: Palette.surfaceHi)
                    }

                    field("Días de uso") { DayPicker(days: $days) }

                    field("Horario") { scheduleSection }

                    field("Itinerario") { legsSection }

                    if let error {
                        Text(error)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Palette.background)
            .navigationTitle(isEditing ? "Editar ruta" : "Nueva ruta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else {
                            Text("Guardar").font(.system(size: 15, weight: .heavy))
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $addingLeg) {
                LegBuilderView { leg in
                    legs.append(leg)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    // ---------------- secciones ----------------

    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).overlineStyle()
            content()
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Picker("Horario", selection: $timeMode) {
                ForEach(TimeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if timeMode == .window {
                HStack(spacing: 10) {
                    TimeField(label: "Desde", value: $timeFrom)
                    TimeField(label: "Hasta", value: $timeTo)
                }
            } else {
                TimeField(label: timeMode == .arrival ? "Llego a las" : "Salgo a las",
                          value: $timeAt)
                Text(timeMode == .arrival
                     ? "La franja se calcula hacia atrás desde esa hora, con lo que dura el trayecto."
                     : "La franja va desde 45 min antes hasta que llegas.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var legsSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                HStack(spacing: 11) {
                    LineBadge(code: leg.lineCode, color: leg.lineColor, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.stopName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(leg.directions.isEmpty
                             ? "todos los sentidos"
                             : "dirección \(leg.directions.joined(separator: " · "))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(leg.directions.isEmpty
                                             ? Palette.warn : Palette.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        legs.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar el tramo \(leg.lineCode)")
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .padding(.vertical, 8)
                .cardSurface(16, fill: Palette.surfaceHi)
            }

            Button { addingLeg = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text(legs.isEmpty ? "Añadir el primer tramo" : "Añadir transbordo")
                }
                .font(.system(size: 13.5, weight: .heavy))
                .foregroundStyle(Palette.inkMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairlineHi,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // ---------------- guardar ----------------

    private func prefill() {
        guard let route = target.route, legs.isEmpty else { return }
        name = route.name
        days = Set(route.days)
        timeMode = route.timeMode
        timeAt = route.timeAt.isEmpty ? "09:00" : route.timeAt
        timeFrom = route.timeFrom
        timeTo = route.timeTo
        legs = route.legs.map {
            DraftLeg(stopId: $0.fromId, stopName: $0.fromName,
                     lineId: $0.lineId, lineCode: $0.lineCode,
                     lineName: $0.lineName, lineMode: $0.lineMode,
                     lineColor: $0.lineColor, directions: $0.directions)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let draft = RouteDraft(
            name: name.trimmingCharacters(in: .whitespaces),
            originId: legs.first?.stopId ?? "",
            originName: legs.first?.stopName ?? "",
            destId: legs.last?.stopId ?? "",
            destName: legs.last?.directions.first ?? legs.last?.stopName ?? "",
            days: days.sorted(),
            timeFrom: timeFrom,
            timeTo: timeTo,
            timeMode: timeMode.rawValue,
            timeAt: timeMode == .window ? "" : timeAt,
            durationMin: target.route?.durationMin ?? 0,
            legs: legs.map {
                RouteDraft.LegDraft(
                    lineId: $0.lineId, lineCode: $0.lineCode, lineName: $0.lineName,
                    lineMode: $0.lineMode, lineColor: $0.lineColor,
                    fromId: $0.stopId, fromName: $0.stopName,
                    toId: "", toName: "", directions: $0.directions)
            })

        do {
            if let route = target.route {
                try await model.routes.update(id: route.id, draft)
            } else {
                try await model.routes.create(draft)
            }
            onSaved(target.route == nil ? "Ruta guardada" : "Ruta actualizada")
            dismiss()
        } catch {
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

/// Los siete días, con la inicial española.
struct DayPicker: View {
    @Binding var days: Set<Int>
    private let letters = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let on = days.contains(index)
                Button {
                    if on { days.remove(index) } else { days.insert(index) }
                } label: {
                    Text(letters[index])
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(on ? .black : Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(on ? Palette.ink : Palette.surfaceHi)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullName(index))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    private func fullName(_ index: Int) -> String {
        ["lunes", "martes", "miércoles", "jueves", "viernes",
         "sábado", "domingo"][index]
    }
}

/// Una hora "HH:MM", con el selector nativo por debajo.
struct TimeField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).overlineStyle()
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var binding: Binding<Date> {
        Binding(
            get: {
                let parts = value.split(separator: ":")
                var comps = DateComponents()
                comps.hour = parts.count == 2 ? Int(parts[0]) ?? 9 : 9
                comps.minute = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                value = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }
}
