import SwiftUI

/// Todas las rutas guardadas, y las dos maneras de crear una.
struct RoutesView: View {
    @Environment(AppModel.self) private var model

    @State private var showCreationChoice = false
    @State private var editing: RouteEditorTarget?
    @State private var goToPlanner = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if model.routes.routes.isEmpty && model.routes.hasLoadedOnce {
                    emptyState
                } else {
                    ForEach(model.routes.routes) { route in
                        RouteCard(route: route,
                                  isActive: route.id == model.routes.activeId)
                            .onTapGesture { editing = .edit(route) }
                            .contextMenu {
                                Button {
                                    model.board.select(routeId: route.id)
                                } label: {
                                    Label("Ver en el tablero", systemImage: "clock.fill")
                                }
                                Button(role: .destructive) {
                                    Task { await delete(route) }
                                } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .refreshable { await model.routes.load() }
        .task { await model.routes.loadIfNeeded() }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(text: toast).padding(.bottom, 96)
            }
        }
        .confirmationDialog("¿Cómo quieres crearla?",
                            isPresented: $showCreationChoice,
                            titleVisibility: .visible) {
            Button("Buscar trayecto") { goToPlanner = true }
            Button("Montar a mano") { editing = .create }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Buscar va de una dirección a otra. A mano es para cuando ya sabes el camino exacto.")
        }
        .sheet(item: $editing) { target in
            RouteEditorView(target: target) { message in
                showToast(message)
                model.board.invalidate()
            }
        }
        .sheet(isPresented: $goToPlanner) {
            NavigationStack { PlanView(embedded: true) }
                .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mis rutas")
                .font(TypeScale.title)
                .foregroundStyle(Palette.ink)
            Spacer()
            Button { showCreationChoice = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                    Text("Nueva")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aún no hay ninguna ruta")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Palette.ink)
            Text("Empieza por **Buscar trayecto**: dices de dónde a dónde vas, eliges el itinerario que usas de verdad y queda vigilado.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func delete(_ route: SavedRoute) async {
        do {
            try await model.routes.delete(id: route.id)
            showToast("Ruta borrada")
            model.board.invalidate()
        } catch {
            showToast("No se ha podido borrar")
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == message { toast = nil }
        }
    }
}

/// El resumen de una ruta: su nombre, cuándo se usa y las líneas encadenadas.
struct RouteCard: View {
    let route: SavedRoute
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(route.name)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isActive {
                    Text("ahora")
                        .font(.system(size: 9.5, weight: .black))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Palette.ok)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.ok.opacity(0.14)))
                }
            }

            Text("\(route.daysLabel) · \(route.scheduleLabel)")
                .overlineStyle(Palette.inkMuted)

            if route.legs.isEmpty {
                Text("sin tramos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
            } else {
                LineChain(legs: route.legs)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Las líneas de la ruta, encadenadas por un hilo corto del color de cada una.
struct LineChain: View {
    let legs: [SavedLeg]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 {
                        LinearGradient(
                            colors: [LineColor.parse(legs[index - 1].lineColor),
                                     LineColor.parse(leg.lineColor)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 16, height: 4)
                        .clipShape(Capsule())
                        .opacity(0.8)
                    }
                    LineBadge(code: leg.lineCode, color: leg.lineColor, size: 32)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Aviso efímero. Nada de diálogos que corten el paso.
struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.ink))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.isStaticText)
    }
}

#if DEBUG
#Preview("Rutas") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(PreviewData.routes) { route in
                RouteCard(route: route, isActive: route.id == 3)
            }
        }
        .padding()
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
