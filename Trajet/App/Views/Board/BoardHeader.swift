import SwiftUI

/// La cabecera de cristal del tablero (sistema.md §7.1): el rótulo de quién
/// eligió la ruta, el nombre de la ruta y, a la derecha, Ajustes.
///
/// El nombre es un menú (F8, R37, R39): «La que toca ahora» (la decide el
/// servidor por día y franja) y las rutas guardadas. Elegir una la fija y
/// refresca al momento; el tablero anterior se queda hasta que llega el nuevo
/// (R9). El rótulo dice «La que toca ahora» si la eligió el servidor y «Ruta
/// elegida» si la fijó la persona.
struct BoardHeader: View {
    let board: Board?
    let pinnedRouteID: Int?
    let isSwitching: Bool
    let routes: [SavedRoute]
    let onSelect: (Int?) -> Void
    let onSettings: () -> Void

    private var title: String {
        if let name = board?.route?.name, !name.isEmpty { return name }
        if let pinnedRouteID, let route = routes.first(where: { $0.id == pinnedRouteID }) { return route.name }
        return "Tablero"
    }

    var body: some View {
        HStack(spacing: Metrics.Space.ml) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BoardText.routeKicker(board: board, pinnedRouteID: pinnedRouteID, isSwitching: isSwitching))
                    .textLevel(.kicker)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                routeMenu
            }
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .cristalButton(circle: true)
            .accessibilityLabel("Ajustes")
        }
        .padding(.vertical, Metrics.Space.m)
        .padding(.leading, 18)
        .padding(.trailing, Metrics.Space.m)
        .frame(minHeight: 64)
        .cristal(.bar)
    }

    private var routeMenu: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                if pinnedRouteID == nil {
                    Label("La que toca ahora", systemImage: "checkmark")
                } else {
                    Text("La que toca ahora")
                }
            }
            if !routes.isEmpty {
                Divider()
                ForEach(routes) { route in
                    Button {
                        onSelect(route.id)
                    } label: {
                        if pinnedRouteID == route.id {
                            Label(route.name, systemImage: "checkmark")
                        } else {
                            Text(route.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Metrics.Space.xs) {
                Text(BoardTitleText.route(title))
                    .textLevel(.routeTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.ink3)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(minHeight: Metrics.Size.hit, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tint(Palette.ink)
        .accessibilityLabel("Ruta: \(title)")
        .accessibilityHint("Toca para cambiar de ruta")
    }
}

#if DEBUG
#Preview("Cabecera del tablero") {
    let auto = PreviewData.board(.cincoTramos)
    let elegida = PreviewData.board(.tranquilo)
    ZStack(alignment: .top) {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        VStack(spacing: Metrics.Space.l) {
            BoardHeader(board: auto, pinnedRouteID: nil, isSwitching: false,
                        routes: PreviewData.routes, onSelect: { _ in }, onSettings: {})
            BoardHeader(board: elegida, pinnedRouteID: 4, isSwitching: false,
                        routes: PreviewData.routes, onSelect: { _ in }, onSettings: {})
            BoardHeader(board: elegida, pinnedRouteID: 5, isSwitching: true,
                        routes: PreviewData.routes, onSelect: { _ in }, onSettings: {})
            BoardHeader(board: nil, pinnedRouteID: nil, isSwitching: false,
                        routes: [], onSelect: { _ in }, onSettings: {})
        }
        .padding(Metrics.Space.gutter)
    }
}
#endif
