import Foundation

/// Atajos para decodificar sin que una respuesta a la que le falta un campo
/// tumbe la pantalla. La promesa de la app es que nunca se queda en blanco, y
/// eso empieza aquí: un JSON raro degrada, no revienta.
extension KeyedDecodingContainer {

    /// Valor, o el de reserva si la clave no está, es `null` o no casa el tipo.
    func get<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Valor opcional, tragándose cualquier error de tipo.
    func opt<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Texto que en el JSON puede venir como cadena o como número.
    /// El número de misión es "135711" unas veces y 135711 otras.
    func text(_ key: Key) -> String? {
        if let s: String = opt(key) { return s.isEmpty ? nil : s }
        if let n: Int = opt(key) { return String(n) }
        return nil
    }
}

extension JSONDecoder {
    /// El servidor habla snake_case en todas partes.
    static let trajet: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

extension JSONEncoder {
    static let trajet: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
