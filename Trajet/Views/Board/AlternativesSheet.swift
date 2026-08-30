import SwiftUI

/// Alternativas cuando algo está cortado.
///
/// Esta llamada NO va en el refresco de 30 s: comparte la bolsa de mil
/// llamadas diarias con el buscador y solo se pide cuando hace falta de
/// verdad, que es exactamente cuando se abre esta hoja.
struct AlternativesSheet: View {
    let routeId: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var response: AlternativesResponse?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    UnreachableState(message: error) { Task { await load(force: false) } }
                } else if let response {
                    content(for: response)
                }
            }
            .background(Palette.background)
            .navigationTitle("Alternativas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await load(force: false) }
    }

    @ViewBuilder
    private func content(for response: AlternativesResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !response.affected.isEmpty {
                    affectedBlock(response.affected)
                }

                if response.options.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(response.needed
                             ? "El calculador no encuentra otro camino ahora mismo."
                             : "Ninguna línea de esta ruta está tocada.")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await load(force: true) }
                        } label: {
                            Text("Buscar de todas formas")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(Palette.ink))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    if let base = response.baselineMinutes {
                        Text("Tu ruta suele durar \(base) min")
                            .overlineStyle()
                    }
                    ForEach(response.options) { option in
                        AlternativeCard(option: option)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private func affectedBlock(_ affected: [AffectedLine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Líneas tocadas").overlineStyle()
            HStack(spacing: 8) {
                ForEach(affected) { line in
                    HStack(spacing: 6) {
                        Text(line.lineCode)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Text(line.label)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(line.level >= 2 ? Palette.bad : Palette.warn)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(
                        Capsule().fill((line.level >= 2 ? Palette.bad : Palette.warn)
                            .opacity(0.14))
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func load(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await model.api.alternatives(routeId: routeId, force: force)
            error = nil
        } catch {
            self.error = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

/// Una alternativa. La que no sirve se marca sin ambigüedad: pasar por otra
/// línea que también está caída no es una alternativa.
struct AlternativeCard: View {
    let option: AlternativeOption

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(option.totalMinutes)")
                    .font(TypeScale.minutes(28))
                    .foregroundStyle(Palette.ink)
                Text("min")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)

                if let delta = option.deltaLabel {
                    Text(delta)
                        .font(.system(size: 11.5, weight: .heavy))
                        .foregroundStyle((option.deltaMinutes ?? 0) > 0
                                         ? Palette.warn : Palette.ok)
                }

                Spacer(minLength: 0)

                Text(option.transfersLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }

            HStack(spacing: 6) {
                ForEach(Array(option.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    LineBadge(code: leg.code, color: leg.color, size: 30)
                }
                Spacer(minLength: 0)
            }

            if !option.departure.isEmpty || !option.arrival.isEmpty {
                Text("sale \(hhmm(option.departure)) · llega \(hhmm(option.arrival))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.inkMuted)
            }

            if !option.usable {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("No sirve: también pasa por una línea cortada")
                        .font(.system(size: 11.5, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.bad)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.bad.opacity(0.12))
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(option.usable ? 1 : 0.62)
    }

    /// Navitia manda "20260831T083100"; el servidor ya recorta casi todo, pero
    /// por si acaso se deja solo la hora.
    private func hhmm(_ raw: String) -> String {
        if raw.count == 15, raw.contains("T") {
            let time = raw.split(separator: "T").last ?? ""
            return String(time.prefix(2)) + ":" + String(time.dropFirst(2).prefix(2))
        }
        return raw
    }
}

#if DEBUG
#Preview("Alternativas") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(PreviewData.alternatives.options) { AlternativeCard(option: $0) }
        }
        .padding()
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
