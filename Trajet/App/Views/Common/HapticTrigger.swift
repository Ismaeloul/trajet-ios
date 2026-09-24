import Foundation

/// Disparador de una háptica a partir de un EVENTO (no de un valor que cambia
/// solo). Las hápticas del sistema (`Haptic`, Motion.swift) se disparan
/// cuando cambia su `trigger`; esto es un contador que se sube a mano cuando
/// el momento clave se cumple de verdad (vía publicada con el dato vivo, tren
/// a 2 minutos, empezar el trayecto…):
///
/// ```swift
/// @State private var started = HapticTrigger()
/// Button("Empezar") { started.fire() }
///     .haptic(.tripStart, trigger: started)
/// ```
///
/// Nunca con el dato viejo ni en cada refresco (sistema.md §9.5): eso lo
/// decide quien llama a `fire()`. «Reducir movimiento» no quita las hápticas.
struct HapticTrigger: Equatable, Sendable {
    private(set) var count = 0

    init() {}

    mutating func fire() {
        count &+= 1
    }
}
