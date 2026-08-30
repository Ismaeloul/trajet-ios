import SwiftUI

/// Buscar trayecto: de una dirección postal (o parada, o sitio) a otra.
///
/// El criterio de hora no es un adorno. «Llegar a las 09:00» y «salir a las
/// 09:00» no son el mismo resultado reordenado: la API resuelve hacia atrás, y
/// por llegada gana el itinerario que te deja salir más tarde, no el más
/// rápido. Así es como se piensa de verdad ir al trabajo.
struct PlanView: View {
    var embedded = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var origin: PlaceResult?
    @State private var destination: PlaceResult?
    @State private var mode: TimeMode = .arrival
    @State private var time = "09:00"

    @State private var options: [PlanOption] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var picking: PlaceField?
    @State private var saving: PlanOption?
    @State private var toast: String?

    enum PlaceField: String, Identifiable {
        case origin, destination
        var id: String { rawValue }
        var title: String { self == .origin ? "¿Desde dónde?" : "¿Hasta dónde?" }
    }

    private var canSearch: Bool {
        origin != nil && destination != nil && !isSearching
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !embedded {
                    Text("Buscar")
                        .font(TypeScale.title)
                        .foregroundStyle(Palette.ink)
                }

                form

                if let error {
                    Text(error)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !options.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(mode == .arrival
                             ? "Para llegar a las \(time)" : "Saliendo a las \(time)")
                            .overlineStyle()
                        ForEach(options) { option in
                            PlanOptionCard(option: option)
                                .onTapGesture { saving = option }
                        }
                        Text("Toca el itinerario que uses de verdad para guardarlo como ruta vigilada.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .padding(.top, embedded ? 4 : 18)
            .padding(.bottom, embedded ? 30 : 110)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .navigationTitle(embedded ? "Buscar trayecto" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast { Toast(text: toast).padding(.bottom, embedded ? 24 : 96) }
        }
        .sheet(item: $picking) { field in
            PlaceSearchView(title: field.title) { place in
                if field == .origin { origin = place } else { destination = place }
            }
        }
        .sheet(item: $saving) { option in
            SavePlanView(option: option, origin: origin, destination: destination,
                         mode: mode, time: time) { message in
                toast = message
                model.board.invalidate()
                Task {
                    try? await Task.sleep(for: .seconds(2.4))
                    toast = nil
                    if embedded { dismiss() }
                }
            }
        }
    }

    private var form: some View {
        VStack(spacing: 12) {
            VStack(spacing: 9) {
                PlaceButton(role: "Origen", place: origin, dot: Palette.ok) {
                    picking = .origin
                }
                PlaceButton(role: "Destino", place: destination, dot: Palette.bad) {
                    picking = .destination
                }
            }

            HStack(spacing: 10) {
                Picker("Criterio", selection: $mode) {
                    Text("Llegar a").tag(TimeMode.arrival)
                    Text("Salir a").tag(TimeMode.departure)
                }
                .pickerStyle(.segmented)

                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            Button {
                Task { await search() }
            } label: {
                Group {
                    if isSearching { ProgressView().tint(.black) }
                    else { Text("Buscar itinerarios") }
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Capsule().fill(canSearch ? Palette.ink : Palette.inkFaint))
            }
            .buttonStyle(.plain)
            .disabled(!canSearch)
        }
        .padding(14)
        .cardSurface()
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let parts = time.split(separator: ":")
                var c = DateComponents()
                c.hour = parts.count == 2 ? Int(parts[0]) ?? 9 : 9
                c.minute = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    private func search() async {
        guard let origin, let destination else { return }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let reply = try await model.api.plan(from: origin.id, to: destination.id,
                                                 when: time, mode: mode)
            options = reply.options
            if options.isEmpty {
                error = "No hay ningún trayecto en transporte público entre esos dos puntos a esa hora."
            }
        } catch {
            options = []
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

/// El botón que abre el buscador de sitios, con su punto de color.
struct PlaceButton: View {
    let role: String
    let place: PlaceResult?
    let dot: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle().fill(dot).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(role).overlineStyle()
                    Text(place?.name ?? "Sin elegir")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(place == nil ? Palette.inkFaint : Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Palette.surfaceHi)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Un itinerario propuesto.
struct PlanOptionCard: View {
    let option: PlanOption

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(option.minutes)")
                    .font(TypeScale.minutes(28))
                    .foregroundStyle(Palette.ink)
                Text("min")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                Spacer(minLength: 0)
                Text("\(option.departure) → \(option.arrival)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
            }

            HStack(spacing: 0) {
                ForEach(Array(option.legs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 {
                        LinearGradient(
                            colors: [LineColor.parse(option.legs[index - 1].lineColor),
                                     LineColor.parse(leg.lineColor)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 14, height: 4)
                        .clipShape(Capsule())
                    }
                    LineBadge(code: leg.lineCode, color: leg.lineColor, size: 30)
                }
                Spacer(minLength: 0)
            }

            Text("\(option.transfersLabel) · \(option.walkMinutes) min andando")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

#if DEBUG
#Preview("Itinerarios") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(PreviewData.planOptions) { PlanOptionCard(option: $0) }
        }
        .padding()
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
