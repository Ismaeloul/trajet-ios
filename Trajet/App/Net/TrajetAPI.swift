import Foundation

/// Lo único que el tablero necesita del cliente. Existe para poder probar
/// `BoardStore` con un servidor de mentira.
protocol BoardFetching: Sendable {
    func board(routeID: Int?, logHistory: Bool) async throws -> BoardPayload
}

/// Respuesta condicional (ETag/304): no ha cambiado, o esto es lo nuevo.
enum ConditionalFetch<Value: Sendable>: Sendable {
    case notModified
    case modified(Value, etag: String?, raw: Data)
}

/// Cliente de /api/v1.
///
/// - Dos direcciones en orden (la que respondió la última vez, casa,
///   Tailscale) y se recuerda la que contesta. Un error HTTP NO salta a la
///   otra dirección —si ha contestado es que está ahí— y un fallo de red SÍ
///   (R42).
/// - Tiempos cortos (6 s / 12 s) y sin caché HTTP (R43): si la red de casa no
///   está, hay que descartarla rápido y saltar a Tailscale.
/// - `Authorization: Bearer` con el token del Llavero; `ETag` guardado por URL
///   y `If-None-Match` en la siguiente; un 304 devuelve lo guardado.
/// - Decodifica aquí, fuera del MainActor.
/// - Una cancelación (el bucle del tablero se para) lanza `CancellationError`,
///   nunca un `.network`: no es «sin conexión».
actor TrajetAPI: BoardFetching {

    static let requestTimeout: TimeInterval = 6
    static let resourceTimeout: TimeInterval = 12

    /// Configuración de la sesión (R43).
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = requestTimeout
        c.timeoutIntervalForResource = resourceTimeout
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        return c
    }

    /// La sesión de la app. Los tests y la demo pasan su `URLProtocol`.
    static func makeSession(protocolClasses: [AnyClass] = []) -> URLSession {
        let c = makeSessionConfiguration()
        if !protocolClasses.isEmpty { c.protocolClasses = protocolClasses }
        return URLSession(configuration: c)
    }

    private let config: ServerConfig
    private let tokens: TokenStore
    private let session: URLSession
    private var etags: [String: CachedResponse] = [:]

    private struct CachedResponse {
        let etag: String
        let data: Data
    }

    init(config: ServerConfig, tokens: TokenStore = .keychain, session: URLSession = TrajetAPI.makeSession()) {
        self.config = config
        self.tokens = tokens
        self.session = session
    }

    // MARK: - Emparejamiento (sin token)

    /// ¿Hay un Trajet aquí? Con las direcciones guardadas.
    func ping() async throws -> PingResponse {
        try await fetch(PingResponse.self, Call(path: "/api/v1/ping", auth: .optional))
    }

    /// ¿Hay un Trajet en esta dirección? Solo esa, sin saltar a otra.
    func ping(baseURL: String) async throws -> PingResponse {
        try await fetch(PingResponse.self, Call(path: "/api/v1/ping", auth: .optional, baseURL: baseURL))
    }

    /// Canjea el código del QR por un token. `pairing_invalid` (401) llega como
    /// `.server(code: "pairing_invalid", …)`; `rate_limited` (429) con
    /// `retryAfter`.
    func pair(_ request: PairRequest, baseURL: String) async throws -> PairResult {
        try await fetch(PairResult.self, Call(method: "POST", path: "/api/v1/pair",
                                              body: try Self.encode(request),
                                              auth: .omitted, baseURL: baseURL))
    }

    // MARK: - Dispositivo

    func me() async throws -> DeviceInfo {
        try await fetch(DeviceInfo.self, Call(path: "/api/v1/devices/me"))
    }

    /// Desempareja este iPhone: el servidor revoca el token.
    @discardableResult
    func unpair() async throws -> Bool {
        try await fetch(UnpairResult.self, Call(method: "DELETE", path: "/api/v1/devices/me")).revoked
    }

    // MARK: - Salud

    func health() async throws -> ServerHealth {
        try await fetch(ServerHealth.self, Call(path: "/api/v1/health"))
    }

    // MARK: - Tablero

    /// El tablero. Sin `routeID` manda el servidor, que sabe cuál toca (R37).
    /// `logHistory: false` en los refrescos automáticos (R40).
    func board(routeID: Int?, logHistory: Bool = true) async throws -> BoardPayload {
        var query: [URLQueryItem] = []
        if let routeID { query.append(URLQueryItem(name: "route_id", value: String(routeID))) }
        if !logHistory { query.append(URLQueryItem(name: "log_history", value: "false")) }
        return try await fetch(BoardPayload.self, Call(path: "/api/v1/board", query: query))
    }

    /// Alternativas evitando las líneas tocadas. Solo al pedirlas, nunca en el
    /// refresco (R29); `force` busca aunque no haya nada tocado (R30).
    func alternatives(routeID: Int, force: Bool = false) async throws -> AlternativesResponse {
        var query: [URLQueryItem] = []
        if force { query.append(URLQueryItem(name: "force", value: "true")) }
        return try await fetch(AlternativesResponse.self,
                               Call(path: "/api/v1/alternatives/\(routeID)", query: query))
    }

    // MARK: - Rutas

    func routes() async throws -> RoutesResponse {
        try await fetch(RoutesResponse.self, Call(path: "/api/v1/routes"))
    }

    func route(id: Int) async throws -> SavedRoute {
        try await fetch(SavedRoute.self, Call(path: "/api/v1/routes/\(id)"))
    }

    func createRoute(_ draft: RouteDraft) async throws -> RouteSaved {
        try await fetch(RouteSaved.self, Call(method: "POST", path: "/api/v1/routes",
                                              body: try Self.encode(draft)))
    }

    func updateRoute(id: Int, _ draft: RouteDraft) async throws -> RouteSaved {
        try await fetch(RouteSaved.self, Call(method: "PUT", path: "/api/v1/routes/\(id)",
                                              body: try Self.encode(draft)))
    }

    /// Borra la ruta (y su historial). Devuelve el id borrado.
    @discardableResult
    func deleteRoute(id: Int) async throws -> Int {
        try await fetch(RouteDeleted.self, Call(method: "DELETE", path: "/api/v1/routes/\(id)")).deleted
    }

    /// Guarda como ruta una opción del planificador (R33: mira `withoutDirection`).
    func routeFromPlan(_ request: PlanSaveRequest) async throws -> PlanSaveResponse {
        try await fetch(PlanSaveResponse.self, Call(method: "POST", path: "/api/v1/routes/from-plan",
                                                    body: try Self.encode(request)))
    }

    // MARK: - Mapa

    /// El mapa de una ruta (ETag en memoria).
    func routeMap(routeID: Int) async throws -> RouteMap {
        try await fetch(RouteMap.self, Call(path: "/api/v1/routes/\(routeID)/map"))
    }

    /// El mapa con un ETag que guarda quien llama (MapStore, en disco).
    func routeMap(routeID: Int, etag: String?) async throws -> ConditionalFetch<RouteMap> {
        let raw = try await send(Call(path: "/api/v1/routes/\(routeID)/map", ifNoneMatch: etag))
        switch raw.status {
        case 304:
            return .notModified
        case 200..<300:
            return .modified(try Self.decode(RouteMap.self, from: raw.data), etag: raw.etag, raw: raw.data)
        default:
            throw Self.error(status: raw.status, data: raw.data, retryAfterHeader: raw.retryAfter)
        }
    }

    // MARK: - Buscadores (gastan cuota: mínimo 2 caracteres y 350 ms, R31)

    /// Solo paradas. Para el editor manual.
    func searchStops(_ text: String) async throws -> [StopResult] {
        try await fetch(StopSearchResponse.self,
                        Call(path: "/api/v1/search/stops", query: [URLQueryItem(name: "q", value: text)])).stops
    }

    /// Paradas, direcciones y sitios. Para el planificador.
    func searchPlaces(_ text: String) async throws -> [PlaceResult] {
        try await fetch(PlaceSearchResponse.self,
                        Call(path: "/api/v1/search/places", query: [URLQueryItem(name: "q", value: text)])).places
    }

    /// Líneas de una parada, ya ordenadas por el servidor (R62).
    func stopLines(stopID: String) async throws -> [StopLine] {
        try await fetch(StopLinesResponse.self,
                        Call(path: "/api/v1/stops/\(Self.escape(stopID))/lines")).lines
    }

    /// Sentidos que circulan AHORA (R32).
    func stopDirections(stopID: String, lineID: String) async throws -> [String] {
        try await fetch(DirectionsResponse.self,
                        Call(path: "/api/v1/stops/\(Self.escape(stopID))/directions",
                             query: [URLQueryItem(name: "line_id", value: lineID)])).directions
    }

    // MARK: - Planificador

    /// «Llegar a» ≠ «salir a» (R34): el servidor solo entiende `arrival` y
    /// `departure`. `when` es «HH:MM» (París) o nil para ahora.
    func plan(from: String, to: String, when: String?, mode: TimeMode) async throws -> PlanResponse {
        var query = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "mode", value: mode == .arrival ? "arrival" : "departure"),
        ]
        if let when, !when.isEmpty { query.append(URLQueryItem(name: "when", value: when)) }
        return try await fetch(PlanResponse.self, Call(path: "/api/v1/plan", query: query))
    }

    // MARK: - Estadísticas

    func stats(days: Int = 90) async throws -> StatsResponse {
        try await fetch(StatsResponse.self,
                        Call(path: "/api/v1/stats", query: [URLQueryItem(name: "days", value: String(days))]))
    }

    /// La única fuente del porcentaje de acierto de la vía (R11).
    func platformModel(routeID: Int?) async throws -> PlatformModelResponse {
        var query: [URLQueryItem] = []
        if let routeID { query.append(URLQueryItem(name: "route_id", value: String(routeID))) }
        return try await fetch(PlatformModelResponse.self, Call(path: "/api/v1/platform-model", query: query))
    }

    // MARK: - Caché de ETag

    /// Olvida los ETag (al desemparejar o cambiar de servidor).
    func clearETags() {
        etags.removeAll()
    }

    // MARK: - Fontanería

    /// Qué hacer con el token.
    private enum Auth {
        case required      // sin token → `.notPaired` sin llamar
        case optional      // se manda si lo hay (ping)
        case omitted       // no se manda (pair)
    }

    private struct Call {
        var method = "GET"
        var path: String
        var query: [URLQueryItem] = []
        var body: Data?
        var auth: Auth = .required
        /// Una dirección concreta, sin saltar a otra (emparejamiento).
        var baseURL: String?
        var ifNoneMatch: String?

        init(method: String = "GET", path: String, query: [URLQueryItem] = [], body: Data? = nil,
             auth: Auth = .required, baseURL: String? = nil, ifNoneMatch: String? = nil) {
            self.method = method
            self.path = path
            self.query = query
            self.body = body
            self.auth = auth
            self.baseURL = baseURL
            self.ifNoneMatch = ifNoneMatch
        }

        var cacheKey: String {
            path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        }
    }

    private struct RawResponse {
        let status: Int
        let data: Data
        let etag: String?
        let retryAfter: Int?
    }

    /// Petición con ETag: manda `If-None-Match` si hay copia y la devuelve
    /// con un 304.
    private func fetch<T: Decodable & Sendable>(_ type: T.Type, _ call: Call) async throws -> T {
        var call = call
        let key = call.method == "GET" ? call.cacheKey : nil
        let cached = key.flatMap { etags[$0] }
        if call.ifNoneMatch == nil, let cached { call.ifNoneMatch = cached.etag }

        var raw = try await send(call)
        if raw.status == 304, cached == nil {
            // Un 304 sin copia (se borraron los ETag a mitad): se pide entero.
            call.ifNoneMatch = nil
            raw = try await send(call)
        }

        let data: Data
        switch raw.status {
        case 304:
            data = cached?.data ?? Data()
        case 200..<300:
            data = raw.data
            if let key, let etag = raw.etag, !etag.isEmpty {
                etags[key] = CachedResponse(etag: etag, data: raw.data)
            }
        default:
            throw Self.error(status: raw.status, data: raw.data, retryAfterHeader: raw.retryAfter)
        }
        return try Self.decode(T.self, from: data)
    }

    /// Prueba cada dirección hasta que una conteste (R42).
    private func send(_ call: Call) async throws -> RawResponse {
        let token: String?
        switch call.auth {
        case .required:
            guard let t = tokens.read(), !t.isEmpty else { throw APIError.notPaired }
            token = t
        case .optional:
            token = tokens.read()
        case .omitted:
            token = nil
        }

        let hosts: [String]
        let remembers: Bool
        if let base = call.baseURL {
            guard let normalized = ServerConfig.normalize(base) else {
                throw APIError.network("La dirección «\(base)» no es válida.")
            }
            hosts = [normalized]
            remembers = false
        } else {
            hosts = await config.candidates
            remembers = true
        }
        guard !hosts.isEmpty else {
            throw APIError.network("No hay ninguna dirección del servidor. Empareja el iPhone o escríbela en Ajustes.")
        }

        var lastFailure = ""
        for host in hosts {
            try Task.checkCancellation()
            guard let url = Self.url(base: host, path: call.path, query: call.query) else {
                lastFailure = "dirección no válida"
                continue
            }
            var request = URLRequest(url: url)
            request.httpMethod = call.method
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let body = call.body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let etag = call.ifNoneMatch, !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastFailure = "respuesta que no es HTTP"
                    continue
                }
                // Ha contestado: esta es la buena, aunque sea con un error.
                if remembers { await config.remember(host) }
                return RawResponse(status: http.statusCode, data: data,
                                   etag: http.value(forHTTPHeaderField: "ETag"),
                                   retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) })
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                lastFailure = Self.describe(error)
                continue          // no se llega: la siguiente dirección
            }
        }

        let base = hosts.count > 1
            ? "No se llega al servidor ni por la red de casa ni por Tailscale"
            : "No se llega al servidor"
        throw APIError.network(lastFailure.isEmpty ? base + "." : "\(base) (\(lastFailure)).")
    }

    /// Traduce una respuesta de error al enumerado.
    static func error(status: Int, data: Data, retryAfterHeader: Int?) -> APIError {
        let body = APIErrorBody.parse(data)
        let code = body?.code ?? ""
        if status == 401 && code != ServerErrorCode.pairingInvalid.rawValue { return .unauthorized }
        if status == 404 { return .notFound }
        return .server(code: code, message: body?.message ?? "", status: status,
                       retryAfter: body?.retryAfter ?? retryAfterHeader)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.trajet.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder.trajet.encode(value)
        } catch {
            throw APIError.decoding("No se ha podido preparar la petición: \(error)")
        }
    }

    static func url(base: String, path: String, query: [URLQueryItem]) -> URL? {
        guard var comps = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty {
            comps.queryItems = query
            // URLComponents deja el «+» tal cual y el servidor lo leería como
            // un espacio.
            comps.percentEncodedQuery = comps.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        return comps.url
    }

    /// Un id de parada dentro de la ruta de la URL (sin «/», «?» ni «#»).
    static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .timedOut: return "tiempo de espera agotado"
        case .notConnectedToInternet: return "el iPhone no tiene conexión"
        case .cannotFindHost, .dnsLookupFailed: return "no se encuentra la dirección"
        case .cannotConnectToHost: return "el servidor no responde"
        case .networkConnectionLost: return "se ha cortado la conexión"
        case .appTransportSecurityRequiresSecureConnection: return "iOS no deja usar esa dirección sin HTTPS"
        default: return e.localizedDescription
        }
    }
}
