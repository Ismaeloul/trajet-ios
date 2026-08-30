import SwiftUI

/// La pantalla que se mira de pie.
///
/// Todo lo de aquí está ordenado por una sola pregunta: ¿corro o no corro? Los
/// minutos son lo primero, el estado de la línea lo segundo y el resto se lee
/// solo si sobra tiempo.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    /// Reloj propio para envejecer el dato sin repintar el tablero a 60 fps.
    @State private var now = Date()
    @State private var alternativesFor: Int?
    @State private var detailLeg: Leg?

    private var board: Board? { model.board.board }
    private var isStale: Bool { board?.isStale(now: now) ?? false }

    var body: some View {
        ZStack(alignment: .top) {
            content
            RefreshBar(nextRefreshAt: model.board.nextRefreshAt,
                       isLoading: model.board.isLoading)
        }
        .background(Palette.background)
        .task(id: "clock") {
            // Un latido cada 5 s: suficiente para la antigüedad y para cruzar
            // el umbral de dato viejo sin que se note.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                now = .now
            }
        }
        .task { await model.routes.loadIfNeeded() }
        .sheet(item: $detailLeg) { leg in
            LegDetailSheet(leg: leg)
        }
        .sheet(item: Binding(
            get: { alternativesFor.map(IdentifiableInt.init) },
            set: { alternativesFor = $0?.value }
        )) { wrapped in
            AlternativesSheet(routeId: wrapped.value)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let board, board.empty {
            EmptyBoardState()
        } else if let board, board.hasContent {
            loaded(board)
        } else if model.board.isLoading {
            BoardSkeleton()
        } else {
            UnreachableState(message: model.board.lastError) {
                Task { await model.board.refresh() }
            }
        }
    }

    // ---------------- el tablero con datos ----------------

    private func loaded(_ board: Board) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(board)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)

                legs(board)
                    .padding(.horizontal, 16)

                footer(board)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            .padding(.top, 18)
            .padding(.bottom, 110)   // hueco para la pastilla flotante
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.board.refresh() }
        // Con el dato viejo se apaga el tablero ENTERO, no una etiqueta suelta.
        .opacity(isStale ? 0.5 : 1)
        .grayscale(isStale ? 0.45 : 0)
        .animation(.easeInOut(duration: 0.45), value: isStale)
    }

    private func header(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(board.autoSelected ? "Ruta activa" : "Ruta elegida")
                        .overlineStyle()
                    routePicker(board)
                }

                Spacer(minLength: 10)

                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes")
            }

            FreshnessPill(board: board, now: now, error: model.board.lastError)
        }
    }

    /// El nombre de la ruta es el selector: un toque y se cambia. Es el gesto
    /// más frecuente después de mirar los minutos.
    private func routePicker(_ board: Board) -> some View {
        Menu {
            Button {
                model.board.select(routeId: nil)
            } label: {
                Label("La que toque ahora", systemImage: "clock.badge.checkmark")
            }

            Divider()

            ForEach(model.routes.routes) { route in
                Button {
                    model.board.select(routeId: route.id)
                } label: {
                    if route.id == board.route?.id {
                        Label(route.name, systemImage: "checkmark")
                    } else {
                        Text(route.name)
                    }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RouteTitle(name: board.route?.name ?? "Trajet")
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("Ruta \(board.route?.name ?? ""), tocar para cambiar")
    }

    private func legs(_ board: Board) -> some View {
        let density = ChipDensity(legCount: board.legs.count)
        return VStack(spacing: 0) {
            ForEach(Array(board.legs.enumerated()), id: \.element.id) { index, leg in
                LegRow(
                    leg: leg,
                    nextColor: index < board.legs.count - 1
                        ? board.legs[index + 1].lineColor : nil,
                    density: density,
                    onSearchAlternative: { alternativesFor = board.route?.id },
                    onTap: { detailLeg = leg }
                )
            }
        }
    }

    /// El pie: los tramos que han fallado y la cuota que queda. Información de
    /// servicio, sin alarmar.
    @ViewBuilder
    private func footer(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Un fallo en una estación no puede tumbar a las otras: se dice
            // aquí abajo y el resto del tablero sigue vivo.
            ForEach(Array(board.errors.prefix(3).enumerated()), id: \.offset) { _, err in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10, weight: .bold))
                    Text(err)
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.warn.opacity(0.75))
            }

            if let remaining = board.remainingCalls {
                Text(Fmt.quota(remaining))
                    .overlineStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

/// «Casa → Trabajo», con la flecha en gris para que los dos extremos pesen
/// más que el separador.
struct RouteTitle: View {
    let name: String

    var body: some View {
        let parts = name.components(separatedBy: "→")
        if parts.count >= 2 {
            (Text(parts[0].trimmingCharacters(in: .whitespaces))
             + Text("  →  ").foregroundColor(Palette.inkFaint)
             + Text(parts.dropFirst().joined(separator: "→")
                        .trimmingCharacters(in: .whitespaces)))
                .font(TypeScale.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
        } else {
            Text(name)
                .font(TypeScale.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }
}

/// De cuándo es lo que se está viendo. Cuando la API cae, esto es lo único
/// que cambia en pantalla: el dato se queda, con su edad.
struct FreshnessPill: View {
    let board: Board
    let now: Date
    let error: String?

    private var stale: Bool { board.isStale(now: now) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: error != nil ? "wifi.slash"
                  : (stale ? "clock.badge.exclamationmark" : "dot.radiowaves.up.forward"))
                .font(.system(size: 10, weight: .bold))
            Text(Fmt.age(board.ageSeconds(now: now)))
                .font(.system(size: 11, weight: .heavy))
                .monospacedDigit()
            if error != nil {
                Text("· sin conexión")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(error != nil || stale ? Palette.bad : Palette.ok)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(
            Capsule().fill((error != nil || stale ? Palette.bad : Palette.ok).opacity(0.12))
        )
        .accessibilityLabel(
            error != nil
            ? "Sin conexión. Dato de \(Fmt.age(board.ageSeconds(now: now)))"
            : "Dato de \(Fmt.age(board.ageSeconds(now: now)))"
        )
    }
}

/// La barra de 30 s: dice cuándo llega el dato siguiente sin que haya que
/// preguntárselo a nadie.
struct RefreshBar: View {
    let nextRefreshAt: Date
    let isLoading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Palette.ok.opacity(isLoading ? 0.85 : 0.45))
                .frame(width: proxy.size.width * fill, height: 2)
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ignoresSafeArea(edges: .horizontal)
        .onChange(of: nextRefreshAt, initial: true) { _, next in
            let remaining = max(0, next.timeIntervalSinceNow)
            fill = 0
            guard !reduceMotion, remaining > 0 else { fill = 1; return }
            withAnimation(.linear(duration: remaining)) { fill = 1 }
        }
        .accessibilityHidden(true)
    }
}

// ---------------- los estados que no son el caso feliz ----------------

/// Primera apertura del día, con la red de una estación. Se pinta el esqueleto
/// de las tarjetas: así se ve dónde va a estar cada cosa antes de que llegue.
struct BoardSkeleton: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 8).fill(Palette.surface)
                .frame(width: 210, height: 30)
                .padding(.bottom, 26)

            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.surface)
                        .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
                    RoundedRectangle(cornerRadius: 22).fill(Palette.surface)
                        .frame(height: 112)
                }
                .padding(.bottom, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .opacity(shimmer ? 0.45 : 0.8)
        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
        .accessibilityLabel("Cargando el tablero")
    }
}

/// Instalación limpia. Tiene que decir qué hacer, no solo que está vacío.
struct EmptyBoardState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.inkFaint)
            Text("Todavía no hay ninguna ruta")
                .font(TypeScale.section)
                .foregroundStyle(Palette.ink)
            Text("Ve a **Buscar**, di de dónde a dónde vas y guarda el trayecto que uses de verdad. A partir de ahí el tablero se abre solo en la ruta que toque.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// No se llega al servidor y encima no hay nada guardado que enseñar. Es el
/// único caso en que la pantalla está vacía, y entonces dice por qué.
struct UnreachableState: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.bad.opacity(0.8))
            Text("No se llega al servidor")
                .font(TypeScale.section)
                .foregroundStyle(Palette.ink)
            Text(message ?? "Ni por la red de casa ni por Tailscale.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: retry) {
                Text("Reintentar")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Envoltorio para poder usar un Int como item de `.sheet`.
struct IdentifiableInt: Identifiable {
    let value: Int
    var id: Int { value }
    init(_ value: Int) { self.value = value }
}

#if DEBUG
#Preview("Tablero · 5 tramos") {
    BoardPreviewHost(board: PreviewData.fiveLegBoard)
}

#Preview("Tablero · tranquilo") {
    BoardPreviewHost(board: PreviewData.calmBoard)
}

/// Las vistas previas no hablan con el servidor: se les da el tablero hecho.
struct BoardPreviewHost: View {
    let board: Board
    @State private var now = Date()

    var body: some View {
        let density = ChipDensity(legCount: board.legs.count)
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ruta activa").overlineStyle()
                    RouteTitle(name: board.route?.name ?? "")
                    FreshnessPill(board: board, now: now, error: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    ForEach(Array(board.legs.enumerated()), id: \.element.id) { i, leg in
                        LegRow(leg: leg,
                               nextColor: i < board.legs.count - 1
                                   ? board.legs[i + 1].lineColor : nil,
                               density: density,
                               onSearchAlternative: {}, onTap: {})
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 24)
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }
}
#endif
