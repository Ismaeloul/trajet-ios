import Foundation

// El sobre de error de /api/v1 (`ErrorV1` del contrato):
//   {"error": {"code": "prim_key_missing", "message": "…", "retry_after": 60}}
// `code` es estable y es lo que mira la app para enseñar un estado diseñado;
// `message` va en español para personas. Por tolerancia se lee también el
// `{"detail": "…"}` de la API 0.3.0.

/// Los códigos de error que el contrato declara. Uno desconocido es `.unknown`.
enum ServerErrorCode: String, Sendable, CaseIterable {
    case badRequest = "bad_request"
    case unauthorized
    case forbidden
    case notFound = "not_found"
    case pairingInvalid = "pairing_invalid"
    case rateLimited = "rate_limited"
    case primKeyMissing = "prim_key_missing"
    case primKeyInvalid = "prim_key_invalid"
    case primQuotaExhausted = "prim_quota_exhausted"
    case primUnreachable = "prim_unreachable"
    case upstream
    case primKeyRejected = "prim_key_rejected"
    case `internal`
    case unknown

    init(code: String) {
        self = ServerErrorCode(rawValue: code) ?? .unknown
    }
}

/// Cuerpo de un error de la API, ya aplanado.
struct APIErrorBody: Decodable, Hashable, Sendable {
    var code: String
    var message: String
    var retryAfter: Int?

    private enum Keys: String, CodingKey { case error, detail }
    private enum Inner: String, CodingKey { case code, message, retryAfter }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let inner = try? c.nestedContainer(keyedBy: Inner.self, forKey: .error) {
            code       = inner.get(.code, "")
            message    = inner.get(.message, "")
            retryAfter = inner.opt(.retryAfter)
        } else {
            // API 0.3.0: {"detail": "…"}; los 422 traen una lista, que no sirve.
            code       = ""
            message    = c.get(.detail, "")
            retryAfter = nil
        }
    }

    init(code: String, message: String, retryAfter: Int? = nil) {
        self.code = code
        self.message = message
        self.retryAfter = retryAfter
    }

    var knownCode: ServerErrorCode { ServerErrorCode(code: code) }

    /// Lee el cuerpo de una respuesta de error; nil si no es un sobre legible.
    static func parse(_ data: Data) -> APIErrorBody? {
        guard let body = try? JSONDecoder.trajet.decode(APIErrorBody.self, from: data),
              !(body.code.isEmpty && body.message.isEmpty)
        else { return nil }
        return body
    }
}
