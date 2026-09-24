import Foundation

// Emparejamiento y dispositivo: /api/v1/ping, /api/v1/pair y
// /api/v1/devices/me (`Ping`, `PairRequest`, `PairResult`, `Device`,
// `ServerUrl` del contrato).

/// GET /api/v1/ping: ¿hay un Trajet aquí? No pide token ni gasta cuota.
struct PingResponse: Codable, Hashable, Sendable {
    var ok: Bool
    var service: String           // "trajet"
    var api: Int                  // 1
    var version: String           // "0.4.0"
    var paired: Bool              // el token de la petición (si lo hay) vale

    enum CodingKeys: String, CodingKey { case ok, service, api, version, paired }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok      = c.get(.ok, false)
        service = c.get(.service, "")
        api     = c.get(.api, 0)
        version = c.get(.version, "")
        paired  = c.get(.paired, false)
    }

    init(ok: Bool = true, service: String = "trajet", api: Int = 1,
         version: String = "", paired: Bool = false) {
        self.ok = ok
        self.service = service
        self.api = api
        self.version = version
        self.paired = paired
    }

    /// Es un Trajet que habla la API v1.
    var isTrajet: Bool { ok && service == "trajet" && api >= 1 }
}

/// Cuerpo de POST /api/v1/pair. Se codifica a snake_case con
/// `JSONEncoder.trajet`. Los campos que sobran el servidor los ignora.
struct PairRequest: Encodable, Hashable, Sendable {
    var code: String              // «ABCD-EFGH» (minúsculas y espacios valen)
    var deviceName: String        // 1…60
    var deviceModel: String?      // ≤ 60, p. ej. «iPhone17,1»
    var appVersion: String?       // ≤ 30

    init(code: String, deviceName: String, deviceModel: String? = nil, appVersion: String? = nil) {
        self.code = code
        self.deviceName = String(deviceName.prefix(60))
        self.deviceModel = deviceModel.map { String($0.prefix(60)) }
        self.appVersion = appVersion.map { String($0.prefix(30)) }
    }

    enum CodingKeys: String, CodingKey { case code, deviceName, deviceModel, appVersion }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(deviceName, forKey: .deviceName)
        if let deviceModel, !deviceModel.isEmpty { try c.encode(deviceModel, forKey: .deviceModel) }
        if let appVersion, !appVersion.isEmpty { try c.encode(appVersion, forKey: .appVersion) }
    }
}

/// Una dirección del servidor (`ServerUrl`): casa, Tailscale u otra.
struct ServerURL: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case lan, tailscale, other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }
    }

    var kind: Kind
    var url: String               // base sin barra final: http://192.168.1.10:7796

    enum CodingKeys: String, CodingKey { case kind, url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.get(.kind, Kind.other)
        url  = c.get(.url, "")
    }

    init(kind: Kind, url: String) {
        self.kind = kind
        self.url = url
    }
}

/// `Device`: este iPhone tal como lo ve el servidor.
struct DeviceInfo: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var model: String
    var appVersion: String
    var createdAt: String         // ISO 8601
    var lastUsedAt: String?

    enum CodingKeys: String, CodingKey { case id, name, model, appVersion, createdAt, lastUsedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = c.get(.id, 0)
        name       = c.get(.name, "")
        model      = c.get(.model, "")
        appVersion = c.get(.appVersion, "")
        createdAt  = c.get(.createdAt, "")
        lastUsedAt = c.opt(.lastUsedAt)
    }

    init(id: Int, name: String, model: String = "", appVersion: String = "",
         createdAt: String = "", lastUsedAt: String? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// POST /api/v1/pair → 200. El token solo se ve esta vez: va al Llavero.
struct PairResult: Codable, Hashable, Sendable {
    struct Server: Codable, Hashable, Sendable {
        var name: String
        var version: String
        var urls: [ServerURL]

        enum CodingKeys: String, CodingKey { case name, version, urls }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name    = c.get(.name, "")
            version = c.get(.version, "")
            urls    = c.get(.urls, [])
        }

        init(name: String, version: String = "", urls: [ServerURL] = []) {
            self.name = name
            self.version = version
            self.urls = urls
        }

        func url(_ kind: ServerURL.Kind) -> String? {
            urls.first(where: { $0.kind == kind && !$0.url.isEmpty })?.url
        }
    }

    var token: String             // trj_ + 43 caracteres base64url
    var device: DeviceInfo
    var server: Server

    enum CodingKeys: String, CodingKey { case token, device, server }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token  = c.get(.token, "")
        device = c.get(.device, DeviceInfo(id: 0, name: ""))
        server = c.get(.server, Server(name: ""))
    }

    init(token: String, device: DeviceInfo, server: Server) {
        self.token = token
        self.device = device
        self.server = server
    }
}

/// DELETE /api/v1/devices/me → `{"revoked": true}`.
struct UnpairResult: Decodable, Hashable, Sendable {
    var revoked: Bool

    enum CodingKeys: String, CodingKey { case revoked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revoked = c.get(.revoked, false)
    }
}
