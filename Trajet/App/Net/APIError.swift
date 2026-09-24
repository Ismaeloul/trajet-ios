import Foundation

/// Lo que puede salir mal al hablar con el servidor.
///
/// La diferencia importante (R42, R44): `.network` es que no se llega por
/// ninguna dirección; todo lo demás es que el servidor SÍ ha contestado.
/// Una cancelación no es un error de estos: el cliente lanza
/// `CancellationError` y quien llama la ignora.
enum APIError: Error, Sendable, Equatable {
    /// No hay token en el Llavero: hay que emparejar.
    case notPaired
    /// 401: el token no vale o está revocado (panel → «Revocar»).
    case unauthorized
    /// 404 (`not_found`): la ruta ya no existe, o no hay itinerario.
    case notFound
    /// Cualquier otro error con el sobre `ErrorV1` (o sin él).
    case server(code: String, message: String, status: Int, retryAfter: Int?)
    /// No se llega al servidor por ninguna dirección.
    case network(String)
    /// El servidor ha contestado algo que no se entiende.
    case decoding(String)

    /// El código estable del contrato, si lo hay.
    var serverCode: ServerErrorCode? {
        switch self {
        case .server(let code, _, _, _): ServerErrorCode(code: code)
        case .unauthorized: .unauthorized
        case .notFound: .notFound
        case .notPaired, .network, .decoding: nil
        }
    }

    /// No se ha llegado al servidor.
    var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }

    /// Hay que (volver a) emparejar.
    var needsPairing: Bool {
        switch self {
        case .notPaired, .unauthorized: true
        case .notFound, .server, .network, .decoding: false
        }
    }

    /// Segundos que el servidor pide esperar (cuota, demasiados intentos).
    var retryAfter: Int? {
        if case .server(_, _, _, let retry) = self { return retry }
        return nil
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notPaired:
            "Este iPhone no está emparejado con ningún servidor."
        case .unauthorized:
            "El servidor ya no reconoce este iPhone. Vuelve a emparejarlo."
        case .notFound:
            "No se ha encontrado."
        case .server(_, let message, let status, _):
            message.isEmpty ? "El servidor ha respondido \(status)." : message
        case .network(let message):
            message
        case .decoding:
            "El servidor ha contestado algo que no se entiende."
        }
    }
}
