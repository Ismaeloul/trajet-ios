import SwiftUI
import WidgetKit

// La extensión de widgets de la IPA full (en la lite no existe): widgets de
// inicio (pequeño, mediano y grande), de la pantalla de bloqueo (circular,
// rectangular y en línea) y la Live Activity del modo trayecto.
// Diseño: variante A «Billete» (docs/diseno/decisiones-la-widgets.md).
@main
struct TrajetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrajetHomeWidget()
        TrajetLockWidget()
        TrajetLiveActivity()
    }
}
