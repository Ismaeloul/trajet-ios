#if DEBUG
import SwiftUI

/// Para las vistas previas que necesitan la app entera: crea los servicios
/// de la demo (el servidor falso en proceso, `AppServices.demo`), la
/// navegación y los avisos efímeros, los pone en el entorno y pide el tablero
/// una vez. Solo existe en Debug, como la demo.
///
/// ```swift
/// #Preview {
///     DemoServicesPreview("cincoTramos") {
///         LegDetailSheet(legSeq: 3)
///     }
/// }
/// ```
///
/// `escenario` es un `PreviewData.BoardCase` («cincoTramos», «viaProbable»…)
/// o uno de los de la demo («vacio», «sinConexion», «sinClave»…).
struct DemoServicesPreview<Content: View>: View {
    @State private var services: AppServices
    @State private var navigator = AppNavigator()
    private let loadsBoard: Bool
    private let content: Content

    init(_ escenario: String, loadsBoard: Bool = true, @ViewBuilder content: () -> Content) {
        _services = State(initialValue: AppServices.demo(escenario: escenario))
        self.loadsBoard = loadsBoard
        self.content = content()
    }

    var body: some View {
        content
            .environment(services)
            .environment(navigator)
            .environment(navigator.toasts)
            .toastHost(navigator.toasts)
            .task {
                guard loadsBoard else { return }
                await services.board.refresh()
            }
    }
}
#endif
