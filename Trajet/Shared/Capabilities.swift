import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Qué puede hacer esta instalación. Se mira en tiempo de ejecución: la IPA
/// full firmada con un Apple ID gratuito se queda sin App Group, y entonces
/// la app no ofrece widgets ni Live Activity en vez de romperse (R60).
enum Capabilities {

    /// El App Group que comparten la app, los widgets y la Live Activity.
    static let appGroupID = "group.com.ismaeloul.trajet"

    /// Hay contenedor del App Group. En la lite no se mira siquiera: en el
    /// simulador iOS devuelve una carpeta aunque falte el entitlement.
    static var hasAppGroup: Bool {
        if isLite { return false }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// Carpeta del App Group, si existe.
    static var appGroupContainer: URL? {
        if isLite { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// IPA lite (condición de compilación `TRAJET_LITE`): sin extensiones ni
    /// App Group.
    static var isLite: Bool {
#if TRAJET_LITE
        return true
#else
        return false
#endif
    }

    /// Esto es la extensión de widgets (condición `TRAJET_WIDGETS`).
    static var isWidgetExtension: Bool {
#if TRAJET_WIDGETS
        return true
#else
        return false
#endif
    }

    /// Se puede empezar una Live Activity: no es la lite, hay App Group (la
    /// extensión lee de ahí) y el usuario no las ha apagado en Ajustes.
    static var liveActivitiesAvailable: Bool {
        guard !isLite, hasAppGroup else { return false }
#if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
#else
        return false
#endif
    }
}
