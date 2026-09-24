import SwiftUI

/// Un extremo del planificador («Desde» / «Hasta»): enseña el sitio elegido
/// y, al tocarlo, abre la búsqueda (`PlaceSearchSheet`).
struct PlaceSearchField: View {
    let label: String
    let symbol: String
    let place: PlaceResult?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Space.ml) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .textLevel(.kicker)
                        .foregroundStyle(Palette.ink3)
                    Text(place?.name ?? "Sin elegir")
                        .textLevel(.bodyStrong)
                        .foregroundStyle(place == nil ? Palette.ink3 : Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let place, !place.city.isEmpty {
                        Text(place.city)
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.ink3)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(place?.name ?? "sin elegir")")
        .accessibilityHint("Toca para buscar el sitio")
        .accessibilityAddTraits(.isButton)
    }
}

/// «¿Desde dónde?» / «¿Hasta dónde?» (F41): paradas, direcciones y sitios
/// de `/search/places`. Mínimo 2 caracteres y 350 ms de espera; cada tecla
/// cancela la búsqueda anterior (R31: gasta cuota).
struct PlaceSearchSheet: View {
    let title: String
    let onPick: (PlaceResult) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = PlaceSearchModel()
    @FocusState private var focused: Bool

    // Explícito: con estado privado, el inicializador sintetizado sería privado.
    init(title: String, onPick: @escaping (PlaceResult) -> Void) {
        self.title = title
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SearchFieldRow(prompt: "Calle, parada o sitio…", text: $query, focused: $focused)
                        .listRowBackground(Palette.surface)
                }
                results
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: query) { _, text in
            let api = services.api
            search.textChanged(text) { q in try await api.searchPlaces(q) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
    }

    @ViewBuilder
    private var results: some View {
        switch search.phase {
        case .idle:
            Section {
                Text(query.isEmpty ? "Una calle con su número, una parada o un sitio conocido." : SearchText.typeMore)
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
                    Text(SearchText.noPlaces)
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(search.results) { place in
                        Button {
                            onPick(place)
                            dismiss()
                        } label: {
                            PlaceResultRow(place: place)
                        }
                        .listRowBackground(Palette.surface)
                    }
                }
            }
        }
    }
}

/// Un sitio en los resultados: icono por tipo, nombre y «tipo · ciudad».
private struct PlaceResultRow: View {
    let place: PlaceResult

    var body: some View {
        HStack(spacing: Metrics.Space.ml) {
            Image(systemName: place.symbol)
                .font(.body)
                .foregroundStyle(Palette.ink2)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                Text(place.name.isEmpty ? "Sin nombre" : place.name)
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                let subtitle = SearchText.placeSubtitle(place)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.Size.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Buscar sitio (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        PlaceSearchSheet(title: "¿Desde dónde?") { _ in }
    }
}
#endif
