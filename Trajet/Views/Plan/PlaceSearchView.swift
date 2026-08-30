import SwiftUI

/// Buscador de sitios: paradas, direcciones postales y puntos de interés.
struct PlaceSearchView: View {
    let title: String
    let onPick: (PlaceResult) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var places: [PlaceResult] = []
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(places) { place in
                    Button {
                        onPick(place)
                        dismiss()
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: place.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.inkFaint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text([place.kind, place.city]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · "))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 48)
                    }
                    .listRowBackground(Palette.surface)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.bad)
                        .listRowBackground(Color.clear)
                } else if places.isEmpty && query.count >= 2 && !isSearching {
                    Text("Nada con ese nombre")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.inkMuted)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Calle, parada o sitio…")
            .overlay { if isSearching { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task(id: query) {
                guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                    places = []
                    return
                }
                // El buscador comparte la bolsa de mil llamadas diarias con el
                // planificador: no se llama por cada tecla.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func search() async {
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            places = try await model.api.searchPlaces(query)
        } catch {
            places = []
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

/// Guardar el itinerario elegido como ruta vigilada.
struct SavePlanView: View {
    let option: PlanOption
    let origin: PlaceResult?
    let destination: PlaceResult?
    let mode: TimeMode
    let time: String
    let onSaved: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var days: Set<Int> = [0, 1, 2, 3, 4]
    @State private var isSaving = false
    @State private var error: String?
    /// Tramos que se guardan sin sentido porque el texto de Navitia no casaba
    /// con el del tiempo real. Se dice, no se calla.
    @State private var warning: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PlanOptionCard(option: option)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Nombre").overlineStyle()
                        TextField(suggestedName, text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(13)
                            .cardSurface(15, fill: Palette.surfaceHi)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Días de uso").overlineStyle()
                        DayPicker(days: $days)
                    }

                    Text(mode == .arrival
                         ? "Se guardará como «llego a las \(time)», y la franja se calculará con los \(option.minutes) min que dura."
                         : "Se guardará como «salgo a las \(time)».")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !warning.isEmpty {
                        warningBlock
                    }

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
            .navigationTitle("Guardar ruta")
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
                    .disabled(isSaving || days.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var warningBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Guardada, pero con un aviso", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Palette.warn)
            Text("En \(warning.joined(separator: ", ")) no se ha podido casar el sentido con el que usa el tiempo real, así que se enseñarán los pasos en los dos sentidos. Se puede corregir a mano desde Mis rutas.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.warn.opacity(0.10))
        )
    }

    private var suggestedName: String {
        let from = origin?.name ?? option.legs.first?.fromName ?? ""
        let to = destination?.name ?? option.legs.last?.toName ?? ""
        return "\(from) → \(to)"
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        let request = PlanSaveRequest(
            option: option,
            meta: .init(
                name: name.trimmingCharacters(in: .whitespaces).isEmpty
                    ? suggestedName : name.trimmingCharacters(in: .whitespaces),
                originId: origin?.id ?? "",
                originName: origin?.name ?? "",
                destId: destination?.id ?? "",
                destName: destination?.name ?? "",
                days: days.sorted(),
                timeMode: mode == .arrival ? "arrival" : "departure",
                timeAt: time,
                timeFrom: "07:00",
                timeTo: "10:00"))

        do {
            let reply = try await model.api.saveFromPlan(request)
            await model.routes.load()
            if reply.withoutDirection.isEmpty {
                onSaved("Ruta guardada")
                dismiss()
            } else {
                // Se ha guardado igual, pero hay algo que decir antes de irse.
                warning = reply.withoutDirection
            }
        } catch {
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
