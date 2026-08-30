import Foundation
import Observation

/// Dónde vive el servidor.
///
/// El mismo Umbrel se alcanza de dos maneras: por la red de casa, que es
/// instantánea, y por Tailscale, que funciona desde cualquier sitio. La app
/// no pregunta cuál usar: prueba, se queda con la que responde y la recuerda.
/// En un vestíbulo de metro esa decisión no se le puede pasar al usuario.
///
/// Las propiedades son almacenadas y sin `didSet` a propósito: el macro
/// `@Observable` reescribe los accesores, y mezclarlo con observadores de
/// propiedad es pedir problemas. Aquí se persiste llamando a `persist()`.
@MainActor
@Observable
final class ServerConfig {

    /// Red de casa. Es la primera opción porque no pasa por el relé.
    static let defaultLAN = "http://192.168.1.188:7796"
    /// Tailnet del Umbrel. Funciona desde la calle y desde datos móviles.
    static let defaultTailscale = "http://100.99.38.76:7796"

    private enum Key {
        static let lan = "server.lan"
        static let tailscale = "server.tailscale"
        static let preferred = "server.preferred"
    }

    var lan: String
    var tailscale: String

    /// La última que funcionó. Se prueba primero para no pagar el tiempo de
    /// espera de la que está caída en cada refresco.
    private(set) var preferred: String?

    init() {
        let d = UserDefaults.standard
        lan = d.string(forKey: Key.lan) ?? Self.defaultLAN
        tailscale = d.string(forKey: Key.tailscale) ?? Self.defaultTailscale
        preferred = d.string(forKey: Key.preferred)
    }

    /// Guarda las direcciones que se escriben en Ajustes.
    func persist() {
        let d = UserDefaults.standard
        d.set(lan, forKey: Key.lan)
        d.set(tailscale, forKey: Key.tailscale)
    }

    /// Las direcciones a probar, en orden: primero la que funcionó la última
    /// vez, luego las demás sin repetir.
    var candidates: [String] {
        var out: [String] = []
        if let preferred, !preferred.isEmpty { out.append(preferred) }
        for host in [lan, tailscale] where !host.isEmpty && !out.contains(host) {
            out.append(host)
        }
        return out
    }

    func remember(_ host: String) {
        guard preferred != host else { return }
        preferred = host
        UserDefaults.standard.set(host, forKey: Key.preferred)
    }

    /// Nombre corto para Ajustes: «red de casa» o «Tailscale».
    func label(for host: String) -> String {
        if host == lan { return "red de casa" }
        if host == tailscale { return "Tailscale" }
        return host
    }

    func resetToDefaults() {
        lan = Self.defaultLAN
        tailscale = Self.defaultTailscale
        preferred = nil
        persist()
        UserDefaults.standard.removeObject(forKey: Key.preferred)
    }
}
