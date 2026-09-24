import Foundation

/// Los enlaces `trajet://` que abre la app (docs/diseno/decisiones-la-widgets.md §6).
///
/// Los construyen los widgets y la Live Activity (`url`) y los recibe la app en
/// `onOpenURL` (`init?(url:)`). El QR del panel es también un enlace de este
/// esquema (`trajet://pair?…`), que se lee aparte (`PairingLink`).
///
/// | Enlace | Caso |
/// |---|---|
/// | `trajet://pair?v=1&code=…&lan=…&ts=…&name=…` | `.pair` |
/// | `trajet://ruta/{id}?tramo={seq}&salida={jid}` (también `route`) | `.route` |
/// | `trajet://ruta/{id}/alternativas` | `.alternatives` |
/// | `trajet://tablero` | `.board` |
/// | `trajet://ajustes/servidor` | `.serverSettings` |
/// | `trajet://ajustes` | `.settings` |
enum AppLink: Hashable, Sendable {
    static let scheme = "trajet"

    case pair(URL)
    case route(id: Int, legSeq: Int?, departureJID: String?)
    case alternatives(routeID: Int)
    case board
    case settings
    case serverSettings

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path.split(separator: "/").map { String($0).lowercased() }
        let query = comps.queryItems ?? []
        func item(_ name: String) -> String? {
            query.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        switch host {
        case "pair":
            self = .pair(url)
        case "ruta", "route":
            guard let first = path.first, let id = Int(first) else { return nil }
            if path.count >= 2, ["alternativas", "alternatives"].contains(path[1]) {
                self = .alternatives(routeID: id)
            } else {
                self = .route(id: id,
                              legSeq: item("tramo").flatMap(Int.init) ?? item("leg").flatMap(Int.init),
                              departureJID: item("salida") ?? item("departure"))
            }
        case "tablero", "board":
            self = .board
        case "ajustes", "settings":
            self = path.first.map { ["servidor", "server"].contains($0) } == true
                ? .serverSettings : .settings
        default:
            return nil
        }
    }

    /// El enlace como URL, para `widgetURL` y `Link`.
    var url: URL {
        var comps = URLComponents()
        comps.scheme = Self.scheme
        switch self {
        case .pair(let url):
            return url
        case .route(let id, let legSeq, let jid):
            comps.host = "ruta"
            comps.path = "/\(id)"
            var items: [URLQueryItem] = []
            if let legSeq { items.append(URLQueryItem(name: "tramo", value: String(legSeq))) }
            if let jid, !jid.isEmpty { items.append(URLQueryItem(name: "salida", value: jid)) }
            if !items.isEmpty { comps.queryItems = items }
        case .alternatives(let id):
            comps.host = "ruta"
            comps.path = "/\(id)/alternativas"
        case .board:
            comps.host = "tablero"
        case .settings:
            comps.host = "ajustes"
        case .serverSettings:
            comps.host = "ajustes"
            comps.path = "/servidor"
        }
        return comps.url ?? URL(fileURLWithPath: "/")
    }
}
