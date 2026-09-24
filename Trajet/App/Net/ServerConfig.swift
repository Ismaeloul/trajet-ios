import Foundation
import Observation

/// Dónde vive el servidor.
///
/// El mismo Umbrel se alcanza de dos maneras: por la red de casa, que es
/// instantánea, y por Tailscale, que funciona desde cualquier sitio. La app
/// no pregunta cuál usar: prueba, se queda con la que responde y la recuerda
/// (R42). En un vestíbulo de metro esa decisión no se le puede pasar al
/// usuario.
///
/// Las direcciones llegan con el QR del emparejamiento (nunca hay IPs fijas en
/// el código) y se pueden editar a mano en Ajustes: se guardan según se
/// escriben, sin botón de guardar (R61). «Restablecer» vuelve a las del
/// emparejamiento y olvida la preferida.
@MainActor
@Observable
final class ServerConfig {

    enum Key {
        static let lan = "server.lan"
        static let tailscale = "server.tailscale"
        static let preferred = "server.preferred"
        static let name = "server.name"
        static let pairedLAN = "server.paired.lan"
        static let pairedTailscale = "server.paired.tailscale"
    }

    // Almacenado aparte y expuesto con propiedades calculadas: así cada
    // escritura se persiste sin mezclar `didSet` con el macro @Observable.
    private var storedLAN: String
    private var storedTailscale: String
    private var storedName: String

    /// La última que respondió. Se prueba primero para no pagar el tiempo de
    /// espera de la que está caída en cada refresco.
    private(set) var preferredURL: String?

    /// Las del emparejamiento: a ellas vuelve «Restablecer».
    private(set) var pairedLAN: String?
    private(set) var pairedTailscale: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedLAN = defaults.string(forKey: Key.lan) ?? ""
        storedTailscale = defaults.string(forKey: Key.tailscale) ?? ""
        storedName = defaults.string(forKey: Key.name) ?? ""
        preferredURL = defaults.string(forKey: Key.preferred)
        pairedLAN = defaults.string(forKey: Key.pairedLAN)
        pairedTailscale = defaults.string(forKey: Key.pairedTailscale)
    }

    /// Red de casa, p. ej. «http://192.168.1.10:7796». Se guarda al escribir.
    var lanURL: String {
        get { storedLAN }
        set {
            let old = storedLAN
            storedLAN = newValue
            defaults.set(newValue, forKey: Key.lan)
            forgetPreferred(ifItWas: old)
        }
    }

    /// Tailscale, p. ej. «http://100.64.1.2:7796». Se guarda al escribir.
    var tailscaleURL: String {
        get { storedTailscale }
        set {
            let old = storedTailscale
            storedTailscale = newValue
            defaults.set(newValue, forKey: Key.tailscale)
            forgetPreferred(ifItWas: old)
        }
    }

    /// Nombre del servidor (el que se puso en el panel).
    var serverName: String {
        get { storedName }
        set {
            storedName = newValue
            defaults.set(newValue, forKey: Key.name)
        }
    }

    /// Las direcciones a probar, en orden (R42): primero la que funcionó la
    /// última vez, luego casa y luego Tailscale; sin vacías ni repetidas.
    var candidates: [String] {
        var out: [String] = []
        for raw in [preferredURL ?? "", storedLAN, storedTailscale] {
            guard let url = Self.normalize(raw), !out.contains(url) else { continue }
            out.append(url)
        }
        return out
    }

    /// Hay al menos una dirección a la que llamar.
    var hasAddresses: Bool { !candidates.isEmpty }

    /// Apunta la dirección que acaba de responder.
    func remember(_ url: String) {
        guard let url = Self.normalize(url), preferredURL != url else { return }
        preferredURL = url
        defaults.set(url, forKey: Key.preferred)
    }

    /// Nombre corto para Ajustes: «red de casa», «Tailscale» o la dirección.
    func label(for url: String?) -> String {
        guard let url = url.flatMap(Self.normalize) else { return "—" }
        if url == Self.normalize(storedLAN) { return "red de casa" }
        if url == Self.normalize(storedTailscale) { return "Tailscale" }
        return url
    }

    /// Por dónde se está hablando ahora mismo con el servidor.
    var connectedVia: String? {
        preferredURL.map { label(for: $0) }
    }

    /// Guarda lo que trae el emparejamiento: direcciones, nombre y la que
    /// respondió.
    func applyPairing(lan: String?, tailscale: String?, name: String?, reachable: String?) {
        let lanValue = lan.flatMap(Self.normalize) ?? ""
        let tsValue = tailscale.flatMap(Self.normalize) ?? ""
        storedLAN = lanValue
        storedTailscale = tsValue
        pairedLAN = lanValue.isEmpty ? nil : lanValue
        pairedTailscale = tsValue.isEmpty ? nil : tsValue
        defaults.set(lanValue, forKey: Key.lan)
        defaults.set(tsValue, forKey: Key.tailscale)
        defaults.set(pairedLAN, forKey: Key.pairedLAN)
        defaults.set(pairedTailscale, forKey: Key.pairedTailscale)
        if let name, !name.isEmpty { serverName = name }
        preferredURL = nil
        defaults.removeObject(forKey: Key.preferred)
        if let reachable { remember(reachable) }
    }

    /// «Restablecer direcciones» (R61): vuelve a las del emparejamiento y
    /// olvida la preferida.
    func reset() {
        storedLAN = pairedLAN ?? ""
        storedTailscale = pairedTailscale ?? ""
        defaults.set(storedLAN, forKey: Key.lan)
        defaults.set(storedTailscale, forKey: Key.tailscale)
        preferredURL = nil
        defaults.removeObject(forKey: Key.preferred)
    }

    /// Al desemparejar: se olvida todo.
    func clearAll() {
        storedLAN = ""
        storedTailscale = ""
        storedName = ""
        preferredURL = nil
        pairedLAN = nil
        pairedTailscale = nil
        for key in [Key.lan, Key.tailscale, Key.preferred, Key.name, Key.pairedLAN, Key.pairedTailscale] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Editar una dirección olvida la preferida si era la antigua: si no, la
    /// dirección vieja se seguiría probando la primera mientras respondiese.
    private func forgetPreferred(ifItWas old: String) {
        guard let preferredURL, let oldURL = Self.normalize(old), preferredURL == oldURL else { return }
        self.preferredURL = nil
        defaults.removeObject(forKey: Key.preferred)
    }

    /// «192.168.1.10:7796/» → «http://192.168.1.10:7796». nil si está vacía.
    nonisolated static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let comps = URLComponents(string: s), let host = comps.host, !host.isEmpty,
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return s
    }
}
