import Foundation

enum TrajetError: LocalizedError {
    case unreachable            // ninguna de las direcciones responde
    case http(Int, String)      // el servidor contestó, pero con error
    case badPayload

    var errorDescription: String? {
        switch self {
        case .unreachable:
            "No se llega al servidor. Ni por la red de casa ni por Tailscale."
        case .http(let code, let detail):
            detail.isEmpty ? "El servidor ha respondido \(code)." : detail
        case .badPayload:
            "El servidor ha contestado algo que no se entiende."
        }
    }

    /// Un 404 de ruta borrada no es lo mismo que quedarse sin red.
    var isNotFound: Bool {
        if case .http(404, _) = self { return true }
        return false
    }
}

/// Cliente de la API. Todas las llamadas prueban las direcciones conocidas en
/// orden y recuerdan la que funciona.
@MainActor
final class TrajetAPI {

    private let config: ServerConfig
    private let session: URLSession

    init(config: ServerConfig) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        // Corto a propósito: si la red de casa no está, hay que descartarla
        // rápido y saltar a Tailscale antes de que el refresco de 30 s pase.
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 12
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c)
    }

    // ---------------- tablero ----------------

    /// El tablero. `logHistory: false` para los refrescos que no queremos que
    /// engorden el historial (una consulta cada 30 s no es una consulta real).
    func board(routeId: Int?, logHistory: Bool = true) async throws -> Board {
        var items: [URLQueryItem] = []
        if let routeId { items.append(.init(name: "route_id", value: String(routeId))) }
        if !logHistory { items.append(.init(name: "log_history", value: "false")) }
        return try await get("/api/board", items)
    }

    // ---------------- rutas ----------------

    func routes() async throws -> RoutesResponse {
        try await get("/api/routes")
    }

    @discardableResult
    func createRoute(_ draft: RouteDraft) async throws -> Int {
        struct Reply: Decodable { let id: Int }
        let reply: Reply = try await send("/api/routes", method: "POST", body: draft)
        return reply.id
    }

    func updateRoute(id: Int, _ draft: RouteDraft) async throws {
        struct Reply: Decodable { let id: Int }
        let _: Reply = try await send("/api/routes/\(id)", method: "PUT", body: draft)
    }

    func deleteRoute(id: Int) async throws {
        struct Reply: Decodable { let deleted: Int }
        let _: Reply = try await send("/api/routes/\(id)", method: "DELETE",
                                      body: Optional<RouteDraft>.none)
    }

    // ---------------- buscadores ----------------

    /// Direcciones postales, paradas y sitios. Para el planificador.
    func searchPlaces(_ q: String) async throws -> [PlaceResult] {
        struct Reply: Decodable { let places: [PlaceResult] }
        let reply: Reply = try await get("/api/search/places",
                                         [.init(name: "q", value: q)])
        return reply.places
    }

    /// Solo paradas. Para el editor manual.
    func searchStops(_ q: String) async throws -> [StopResult] {
        struct Reply: Decodable { let stops: [StopResult] }
        let reply: Reply = try await get("/api/search/stops",
                                         [.init(name: "q", value: q)])
        return reply.stops
    }

    /// Líneas de una parada, ya ordenadas por el servidor: metro, RER,
    /// Transilien, TER, tranvía y los buses al final.
    func lines(atStop stopId: String) async throws -> [StopLine] {
        struct Reply: Decodable { let lines: [StopLine] }
        let reply: Reply = try await get("/api/stops/\(escape(stopId))/lines")
        return reply.lines
    }

    /// Sentidos que circulan AHORA. El sentido se elige de esta lista, no se
    /// escribe: el texto del tiempo real no coincide con el del planificador.
    func directions(atStop stopId: String, lineId: String) async throws -> [String] {
        struct Reply: Decodable { let directions: [String] }
        let reply: Reply = try await get("/api/stops/\(escape(stopId))/directions",
                                         [.init(name: "line_id", value: lineId)])
        return reply.directions
    }

    // ---------------- planificador ----------------

    func plan(from: String, to: String, when: String?,
              mode: TimeMode) async throws -> PlanResponse {
        var items: [URLQueryItem] = [
            .init(name: "from", value: from),
            .init(name: "to", value: to),
            // El servidor solo entiende 'departure' y 'arrival'.
            .init(name: "mode", value: mode == .arrival ? "arrival" : "departure"),
        ]
        if let when, !when.isEmpty { items.append(.init(name: "when", value: when)) }
        return try await get("/api/plan", items)
    }

    func saveFromPlan(_ request: PlanSaveRequest) async throws -> PlanSaveResponse {
        try await send("/api/routes/from-plan", method: "POST", body: request)
    }

    // ---------------- lo demás ----------------

    func alternatives(routeId: Int, force: Bool = false) async throws -> AlternativesResponse {
        var items: [URLQueryItem] = []
        if force { items.append(.init(name: "force", value: "true")) }
        return try await get("/api/alternatives/\(routeId)", items)
    }

    func stats(days: Int = 90) async throws -> StatsResponse {
        try await get("/api/stats", [.init(name: "days", value: String(days))])
    }

    func platformModel(routeId: Int?) async throws -> PlatformModelResponse {
        var items: [URLQueryItem] = []
        if let routeId { items.append(.init(name: "route_id", value: String(routeId))) }
        return try await get("/api/platform-model", items)
    }

    func health() async throws -> HealthResponse {
        try await get("/api/health")
    }

    // ---------------- fontanería ----------------

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func get<T: Decodable>(_ path: String,
                                   _ query: [URLQueryItem] = []) async throws -> T {
        try await perform(path: path, query: query, method: "GET", body: nil)
    }

    private func send<Body: Encodable, T: Decodable>(
        _ path: String, method: String, body: Body?
    ) async throws -> T {
        let data = try body.map { try JSONEncoder.trajet.encode($0) }
        return try await perform(path: path, query: [], method: method, body: data)
    }

    /// Prueba cada dirección conocida hasta que una conteste.
    ///
    /// Un error del servidor (4xx/5xx) NO hace saltar a la siguiente: si ha
    /// contestado es que está ahí, y probar la otra solo alargaría la espera
    /// para dar el mismo error.
    private func perform<T: Decodable>(path: String, query: [URLQueryItem],
                                       method: String, body: Data?) async throws -> T {
        let hosts = config.candidates
        guard !hosts.isEmpty else { throw TrajetError.unreachable }

        var lastTransportError: Error?

        for host in hosts {
            guard var components = URLComponents(string: host + path) else { continue }
            if !query.isEmpty { components.queryItems = query }
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TrajetError.badPayload
                }
                config.remember(host)

                guard (200..<300).contains(http.statusCode) else {
                    throw TrajetError.http(http.statusCode, Self.detail(from: data))
                }
                do {
                    return try JSONDecoder.trajet.decode(T.self, from: data)
                } catch {
                    throw TrajetError.badPayload
                }
            } catch let error as TrajetError {
                throw error                      // contestó: no hay que reintentar
            } catch {
                lastTransportError = error       // no se llega: probamos la siguiente
                continue
            }
        }

        _ = lastTransportError
        throw TrajetError.unreachable
    }

    /// FastAPI manda los errores como {"detail": "..."}.
    private static func detail(from data: Data) -> String {
        struct Detail: Decodable { let detail: String? }
        return (try? JSONDecoder().decode(Detail.self, from: data))?.detail ?? ""
    }
}
