#if DEBUG
import Foundation

/// Escenarios de la demo. Se eligen al lanzar la app:
/// `-demo` (escenario «cincoTramos») o `-demo -demoEscenario <nombre>`.
///
/// - Cualquier `PreviewData.BoardCase` (`viaProbable`, `lineaCortada`…): el
///   tablero de ese caso, emparejado.
/// - `emparejar`: sin emparejar; el código es `DEMO-2026`.
/// - `vacio`: emparejado, sin rutas.
/// - `sinConexion`: no se llega al servidor; se ve el último tablero (4 min).
/// - `sinClave`: el servidor no tiene clave de PRIM (503 `prim_key_missing`).
/// - `cuotaAgotada`: 503 `prim_quota_exhausted`.
/// - `revocado`: el servidor ya no reconoce el token (401).
///
/// Argumentos sueltos (para los tests de interfaz y las capturas):
/// - `-demoSinCache`: sin tablero guardado, para ver los estados de error a
///   pantalla completa (R53).
/// - `-demoSinUbicacion`: el permiso de ubicación está sin contestar y, al
///   pedirlo, se deniega (el trayecto sigue sin GPS).
enum DemoScenario: Equatable, Sendable {
    case board(PreviewData.BoardCase)
    case unpaired
    case empty
    case offline
    case noKey
    case quotaExhausted
    case revoked

    init(name: String) {
        let key = name.trimmingCharacters(in: .whitespaces)
        if let c = PreviewData.BoardCase.allCases.first(where: { $0.rawValue.lowercased() == key.lowercased() }) {
            self = .board(c)
            return
        }
        switch key.lowercased() {
        case "emparejar", "sinemparejar": self = .unpaired
        case "vacio", "vacío": self = .empty
        case "sinconexion", "sinconexión": self = .offline
        case "sinclave": self = .noKey
        case "cuotaagotada": self = .quotaExhausted
        case "revocado": self = .revoked
        default: self = .board(.cincoTramos)
        }
    }

    var name: String {
        switch self {
        case .board(let c): c.rawValue
        case .unpaired: "emparejar"
        case .empty: "vacio"
        case .offline: "sinConexion"
        case .noKey: "sinClave"
        case .quotaExhausted: "cuotaAgotada"
        case .revoked: "revocado"
        }
    }

    var startsPaired: Bool { self != .unpaired }

    /// El tablero que se ve nada más abrir (de la caché), si hay.
    var cachedBoard: PreviewData.BoardCase? {
        switch self {
        case .offline, .noKey, .quotaExhausted, .revoked: .tranquilo
        case .board, .unpaired, .empty: nil
        }
    }
}

/// Servidor falso en proceso para la demo, los tests de interfaz y las
/// capturas. Es un `URLProtocol`: la sesión de la demo lo lleva en
/// `protocolClasses` y responde a TODO /api/v1 con `PreviewData`, sin red.
///
/// El escenario va en la dirección: `http://demo.trajet.invalid/e/<escenario>`.
final class DemoServer: URLProtocol, @unchecked Sendable {

    static let host = "demo.trajet.invalid"
    static let serverName = "Trajet de demostración"

    /// La dirección «de casa» de un escenario.
    static func baseURL(for scenario: DemoScenario) -> String {
        "http://\(host)/e/\(scenario.name)"
    }

    /// Lee los argumentos de lanzamiento: nil si no es la demo.
    static func scenarioName(arguments: [String]) -> String? {
        guard arguments.contains("-demo") else { return nil }
        if let i = arguments.firstIndex(of: "-demoEscenario"), arguments.indices.contains(i + 1) {
            return arguments[i + 1]
        }
        return DemoScenario.board(.cincoTramos).name
    }

    /// Cuándo arrancó la demo (la vía de `viaAparece` aparece a los 20 s).
    static let launchedAt = Date()

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let reply = Self.respond(to: request)
        switch reply {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let body, let headers):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                 headerFields: headers.merging(["Content-Type": "application/json"]) { a, _ in a })
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    // MARK: - Respuestas

    enum Reply: Equatable {
        case json(status: Int, body: String, headers: [String: String])
        case failure(URLError.Code)

        static func ok(_ body: String, status: Int = 200) -> Reply {
            .json(status: status, body: body, headers: [:])
        }

        static func error(_ c: PreviewData.ErrorCase) -> Reply {
            .json(status: c.status, body: PreviewData.errorJSON(c), headers: [:])
        }
    }

    static func respond(to request: URLRequest) -> Reply {
        guard let url = request.url else { return .failure(.badURL) }
        var parts = url.path.split(separator: "/").map(String.init)
        // /e/<escenario>/api/v1/…
        guard parts.count >= 4, parts[0] == "e" else { return .error(.rutaNoEncontrada) }
        let scenario = DemoScenario(name: parts[1])
        parts.removeFirst(2)
        guard parts.count >= 2, parts[0] == "api", parts[1] == "v1" else { return .error(.rutaNoEncontrada) }
        let path = Array(parts.dropFirst(2))
        let method = request.httpMethod ?? "GET"
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if scenario == .offline { return .failure(.cannotConnectToHost) }

        let token = request.value(forHTTPHeaderField: "Authorization")
        let authorized = token == "Bearer \(PreviewData.demoToken)"

        switch (method, path.first ?? "") {
        case ("GET", "ping"):
            return .ok(authorized && scenario != .revoked ? PreviewData.pingPairedJSON : PreviewData.pingJSON)
        case ("POST", "pair"):
            return pair(request: request, scenario: scenario)
        default:
            break
        }

        guard authorized, scenario != .revoked else { return .error(.noEmparejado) }
        return routeAuthorized(method: method, path: path, query: query, scenario: scenario)
    }

    private static func pair(request: URLRequest, scenario: DemoScenario) -> Reply {
        struct Body: Decodable { let code: String? }
        let data = request.httpBody ?? readStream(request.httpBodyStream)
        let code = (try? JSONDecoder().decode(Body.self, from: data))?.code ?? ""
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized == "DEMO2026" else { return .error(.codigoNoValido) }
        return .ok(PreviewData.pairResultJSON(lan: baseURL(for: scenario), tailscale: nil, name: serverName))
    }

    private static func routeAuthorized(method: String, path: [String], query: [URLQueryItem],
                                        scenario: DemoScenario) -> Reply {
        let head = path.first ?? ""
        switch (method, head) {
        case ("GET", "health"):
            switch scenario {
            case .noKey: return .ok(PreviewData.healthJSON(.sinClave))
            case .board(.cuotaJusta), .quotaExhausted: return .ok(PreviewData.healthJSON(.cuotaJusta))
            default: return .ok(PreviewData.healthJSON(.conClave))
            }

        case ("GET", "board"):
            return board(scenario: scenario)

        case ("GET", "devices"):
            return .ok(PreviewData.deviceJSON)
        case ("DELETE", "devices"):
            return .ok(PreviewData.unpairJSON)

        case ("GET", "routes"):
            if path.count == 1 {
                return .ok(scenario == .empty ? #"{"routes": [], "active_id": null}"# : PreviewData.routesJSON)
            }
            guard let id = Int(path[1]) else { return .error(.rutaNoEncontrada) }
            if path.count >= 3, path[2] == "map" {
                return .json(status: 200, body: PreviewData.routeMapJSON(routeID: id),
                             headers: ["ETag": #"W/"demo-mapa-\#(id)""#])
            }
            return PreviewData.routes.contains { $0.id == id }
                ? .ok(PreviewData.singleRouteJSON) : .error(.rutaNoEncontrada)
        case ("POST", "routes"):
            if path.count >= 2, path[1] == "from-plan" {
                return .ok(PreviewData.planSavedWithoutDirectionJSON, status: 201)
            }
            return .ok(PreviewData.routeSavedJSON, status: 201)
        case ("PUT", "routes"):
            return .ok(PreviewData.routeSavedJSON)
        case ("DELETE", "routes"):
            let id = path.count >= 2 ? (Int(path[1]) ?? 0) : 0
            return .ok(#"{"deleted": \#(id)}"#)

        case ("GET", "search"):
            let kind = path.count >= 2 ? path[1] : ""
            return .ok(kind == "places" ? PreviewData.placeSearchJSON : PreviewData.stopSearchJSON)
        case ("GET", "stops"):
            let kind = path.count >= 3 ? path[2] : ""
            return .ok(kind == "directions" ? PreviewData.directionsJSON : PreviewData.stopLinesJSON)

        case ("GET", "plan"):
            return .ok(PreviewData.planJSON)
        case ("GET", "alternatives"):
            let force = query.contains { $0.name == "force" && $0.value == "true" }
            switch scenario {
            case .board(.lineaCortada): return .ok(PreviewData.alternativesNoOptionsJSON)
            case .board(.cincoTramos): return .ok(PreviewData.alternativesJSON)
            default: return .ok(force ? PreviewData.alternativesDeltasJSON : PreviewData.alternativesNotNeededJSON)
            }

        case ("GET", "stats"):
            return .ok(PreviewData.statsJSON)
        case ("GET", "platform-model"):
            return .ok(PreviewData.platformModelJSON)

        default:
            return .error(.rutaNoEncontrada)
        }
    }

    private static func board(scenario: DemoScenario) -> Reply {
        switch scenario {
        case .board(let c):
            var shown = c
            // La vía aparece a los 20 s de abrir la demo (R2).
            if c == .viaAparece, Date().timeIntervalSince(launchedAt) < 20 { shown = .viaProbable }
            return .json(status: 200, body: DemoClock.realign(json: PreviewData.boardJSON(shown)),
                         headers: ["ETag": #"W/"demo-\#(shown.rawValue)""#])
        case .empty:
            return .ok(PreviewData.emptyBoardJSON)
        case .noKey:
            return .error(.sinClave)
        case .quotaExhausted:
            return .error(.cuotaAgotada)
        case .unpaired:
            // Recién emparejado con DEMO-2026: el tablero de siempre.
            return .json(status: 200, body: DemoClock.realign(json: PreviewData.boardJSON(.cincoTramos)), headers: [:])
        case .revoked:
            return .error(.noEmparejado)
        case .offline:
            return .failure(.cannotConnectToHost)
        }
    }

    private static func readStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// Los datos de prueba tienen las horas fijas («12:56») y los minutos
/// relativos («en 6 min»), como si el tablero fuera de las 12:50. La app se
/// fía de la hora para saber si un tren ya se ha ido (tarjeta del trayecto,
/// Live Activity, widgets): pasadas las 12:56 de verdad, la demo enseñaba
/// «Sin salidas de este tramo». Aquí se recolocan las horas para que casen
/// con los minutos contados desde `now` (hora de París); la hora teórica se
/// mueve lo mismo, así el retraso no cambia. Lo que no sea una hora «HH:MM»
/// (los casos límite, a propósito mal formados) se deja como está.
enum DemoClock {
    /// El tablero JSON de `PreviewData` con las horas recolocadas. Si el JSON
    /// no se entiende, se devuelve tal cual.
    static func realign(json: String, now: Date = .now) -> String {
        guard var root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              var legs = root["legs"] as? [[String: Any]]
        else { return json }
        for i in legs.indices {
            guard var departures = legs[i]["departures"] as? [[String: Any]] else { continue }
            for j in departures.indices {
                var d = departures[j]
                let minutes = (d["minutes"] as? Int) ?? (d["minutes"] as? String).flatMap(Int.init)
                guard let minutes, let at = d["at"] as? String, let oldAt = Departure.parisDate(at, near: now)
                else { continue }
                let newAt = now.addingTimeInterval(TimeInterval(minutes) * 60)
                d["at"] = time(newAt)
                if let aimed = d["aimed_at"] as? String, let oldAimed = Departure.parisDate(aimed, near: now) {
                    d["aimed_at"] = time(newAt.addingTimeInterval(oldAimed.timeIntervalSince(oldAt)))
                }
                departures[j] = d
            }
            legs[i]["departures"] = departures
        }
        root["legs"] = legs
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return json }
        return text
    }

    /// Un `Board` ya decodificado (la caché de la demo) con las horas
    /// recolocadas desde `now` (cuando «llegó»).
    static func realign(board: Board, now: Date) -> Board {
        var result = board
        for i in result.legs.indices {
            for j in result.legs[i].departures.indices {
                var d = result.legs[i].departures[j]
                guard let oldAt = Departure.parisDate(d.at, near: now) else { continue }
                let newAt = now.addingTimeInterval(TimeInterval(d.minutes) * 60)
                if let oldAimed = Departure.parisDate(d.aimedAt, near: now) {
                    d.aimedAt = time(newAt.addingTimeInterval(oldAimed.timeIntervalSince(oldAt)))
                }
                d.at = time(newAt)
                result.legs[i].departures[j] = d
            }
        }
        return result
    }

    /// «HH:MM» en hora de París, como lo escribe el servidor.
    static func time(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension AppServices {
    /// La app con el servidor falso en proceso (`-demo`). No toca el Llavero,
    /// ni las preferencias, ni la caché de disco de verdad.
    static func demo(escenario: String) -> AppServices {
        let scenario = DemoScenario(name: escenario)
        let suite = "com.ismaeloul.trajet.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfig(defaults: defaults)
        let base = DemoServer.baseURL(for: scenario)
        let tokens = TokenStore.memory(scenario.startsPaired ? PreviewData.demoToken : nil)
        if scenario.startsPaired {
            config.applyPairing(lan: base, tailscale: nil, name: DemoServer.serverName, reachable: base)
        } else {
            // Sin emparejar, pero con la dirección puesta: con el código basta.
            config.lanURL = base
        }
        let api = TrajetAPI(config: config, tokens: tokens,
                            session: TrajetAPI.makeSession(protocolClasses: [DemoServer.self]))
        let sinCache = ProcessInfo.processInfo.arguments.contains("-demoSinCache")
        let cached = sinCache ? nil : scenario.cachedBoard.map { c -> CachedBoard in
            // Llegó hace 4 min: las horas de sus trenes, contadas desde entonces.
            let receivedAt = Date().addingTimeInterval(-240)
            return CachedBoard(board: DemoClock.realign(board: PreviewData.board(c), now: receivedAt),
                               receivedAt: receivedAt, routeID: nil)
        }
        return AppServices(config: config, api: api, tokens: tokens,
                           persistence: .memory(cached), mapDirectory: nil, isDemo: true)
    }
}
#endif
