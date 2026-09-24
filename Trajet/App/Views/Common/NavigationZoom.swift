import SwiftUI

// El zoom de iOS 18 entre una pieza y la pantalla que abre (tablero → mapa,
// tarjeta → detalle; sistema.md §9.3). En iOS 17 no hace nada: queda el push
// normal del `NavigationStack`. `matchedGeometryEffect` no cruza un
// `NavigationStack`, así que no se usa para esto. El zoom del sistema ya
// respeta «Reducir movimiento».
//
// ```swift
// @Namespace private var zoom
// origen.trajetZoomSource(id: "mapa", in: zoom)
// destino.trajetZoomTransition(sourceID: "mapa", in: zoom)
// ```

extension View {
    /// Marca esta vista como origen del zoom (iOS 18+).
    func trajetZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomSourceModifier(id: id, namespace: namespace))
    }

    /// La pantalla empujada entra con zoom desde su origen (iOS 18+).
    func trajetZoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomTransitionModifier(id: sourceID, namespace: namespace))
    }
}

private struct ZoomSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct ZoomTransitionModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
