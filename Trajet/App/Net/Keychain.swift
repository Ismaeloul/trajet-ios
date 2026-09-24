import Foundation
import Security

/// El token del dispositivo en el Llavero.
///
/// `kSecAttrAccessibleAfterFirstUnlock`: tras el primer desbloqueo se puede
/// leer con el iPhone bloqueado, que es cuando el modo trayecto refresca el
/// tablero en segundo plano. Con App Group se guarda además en el grupo de
/// acceso del App Group, para que la extensión de widgets pueda leerlo; si el
/// grupo no está disponible (lite, o firma sin entitlement), en el de la app.
enum Keychain {

    static let service = "com.ismaeloul.trajet"
    static let tokenAccount = "device-token"

    /// Guarda el token (sustituye al que hubiera).
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        deleteToken()
        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if Capabilities.hasAppGroup {
            var shared = query
            shared[kSecAttrAccessGroup as String] = Capabilities.appGroupID
            if SecItemAdd(shared as CFDictionary, nil) == errSecSuccess { return true }
        }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// El token guardado, busque donde busque (grupo compartido o el de la app).
    static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Borra el token de todos los grupos a los que llega la app.
    static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
    }
}

/// De dónde saca el cliente el token. En la app, del Llavero; en los tests y
/// en la demo, de memoria (para no tocar el Llavero de verdad).
struct TokenStore: Sendable {
    var read: @Sendable () -> String?
    var save: @Sendable (String) -> Bool
    var delete: @Sendable () -> Void

    init(read: @escaping @Sendable () -> String?,
         save: @escaping @Sendable (String) -> Bool,
         delete: @escaping @Sendable () -> Void) {
        self.read = read
        self.save = save
        self.delete = delete
    }

    static let keychain = TokenStore(
        read: { Keychain.readToken() },
        save: { Keychain.saveToken($0) },
        delete: { Keychain.deleteToken() }
    )

    /// En memoria, empezando con `initial`.
    static func memory(_ initial: String? = nil) -> TokenStore {
        let box = LockedBox<String?>(initial)
        return TokenStore(
            read: { box.value },
            save: { box.value = $0; return true },
            delete: { box.value = nil }
        )
    }
}

/// Un valor protegido con un cerrojo, para compartirlo entre hilos.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }

    /// Cambia el valor dentro del cerrojo y devuelve lo que diga `body`.
    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&stored)
    }
}
