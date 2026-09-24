import Foundation
@preconcurrency import WidgetKit

/// Los tipos (`kind`) de los widgets de Trajet.
enum TrajetWidgetKind {
    /// Pantalla de inicio: pequeño, mediano y grande.
    static let home = "trajet.inicio"
    /// Pantalla de bloqueo: circular, rectangular y en línea.
    static let lock = "trajet.bloqueo"
}

/// Por qué la última recarga no trajo un tablero nuevo (el widget lo dice con
/// símbolo y palabra: «sin conexión · hace 20 min», «servidor sin clave»).
enum WidgetFailure: String, Codable, Hashable, Sendable {
    case offline
    case noKey
}

/// Avisa a los widgets de que hay un tablero nuevo en la caché del App Group.
///
/// WidgetKit da unas 40–70 recargas al día (sistema.md §12.7): aquí se
/// reparten con cuentagotas. Se recarga ya si ha cambiado lo que se ve (otra
/// ruta, otro primer tren, una vía, un aviso) y hace al menos 2 min de la
/// última recarga; si no ha cambiado nada, como mucho cada 15 min (la
/// antigüedad y las cuentas atrás ya corren solas en el timeline).
///
/// Seguro de llamar desde la app en cualquier hilo. No hace nada en la
/// extensión, en la IPA lite ni sin App Group (firma gratuita, R60).
enum WidgetRefresher {

    /// Separación mínima entre dos recargas cuando cambia lo que se ve.
    static let minimumGap: TimeInterval = 120
    /// Separación entre recargas cuando no cambia nada que se vea.
    static let idleGap: TimeInterval = 15 * 60

    /// Lo llama `BoardStore` justo después de guardar el tablero en
    /// `BoardCache`. Un tablero bueno borra el fallo apuntado.
    ///
    /// Si lo que se ve ha cambiado pero la última recarga fue hace menos de
    /// `minimumGap`, la recarga se deja pendiente y sale en cuanto se cumple
    /// (mientras la app siga viva; si no, la hace el propio timeline).
    static func boardDidChange() {
        guard isEnabled else { return }
        clearFailure()
        let seen = signature(of: BoardCache.load())
        switch throttle.decide(signature: seen, now: Date()) {
        case .reload:
            reloadAll()
        case .later(let date):
            schedulePending(at: date)
        case .skip:
            break
        }
    }

    /// La app no ha podido refrescar (sin red, servidor sin clave). Opcional:
    /// si alguien lo llama, los widgets lo dicen con su símbolo; si no, se
    /// quedan con la antigüedad, que ya dice lo viejo que es el dato.
    static func refreshFailed(_ failure: WidgetFailure) {
        guard isEnabled, let defaults = groupDefaults else { return }
        let changed = defaults.string(forKey: Keys.failure) != failure.rawValue
        defaults.set(failure.rawValue, forKey: Keys.failure)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.failureAt)
        guard changed else { return }
        switch throttle.decide(signature: "fallo|\(failure.rawValue)", now: Date()) {
        case .reload:
            reloadAll()
        case .later(let date):
            schedulePending(at: date)
        case .skip:
            break
        }
    }

    /// El fallo apuntado después de `date` (la llegada del tablero que hay en
    /// la caché), si lo hay. Lo lee el `TimelineProvider`.
    static func recordedFailure(after date: Date) -> WidgetFailure? {
        guard Capabilities.hasAppGroup, let defaults = groupDefaults,
              let raw = defaults.string(forKey: Keys.failure),
              let failure = WidgetFailure(rawValue: raw)
        else { return nil }
        let at = Date(timeIntervalSince1970: defaults.double(forKey: Keys.failureAt))
        return at > date ? failure : nil
    }

    // MARK: - Lógica pura (tests)

    /// Lo que se ve en los widgets, resumido: si cambia, merece recarga.
    static func signature(of cached: CachedBoard?) -> String {
        guard let cached else { return "vacío" }
        var parts: [String] = ["ruta \(cached.board.route?.id ?? -1)"]
        for leg in cached.board.legs.prefix(WidgetTimelinePlanner.maxLegs) {
            var bit = "\(leg.seq):\(leg.lineId):\(leg.status.level)"
            for d in leg.departures.prefix(2) {
                bit += "|\(d.id)@\(d.at)/\(d.platform ?? "-")/\(d.guess?.platform ?? "-")/\(d.isCancelled ? "x" : "o")"
            }
            parts.append(bit)
        }
        return parts.joined(separator: " ")
    }

    /// ¿Toca recargar? Con cambios, si hace `minimumGap` de la última; sin
    /// cambios, si hace `idleGap`. La primera vez, siempre.
    static func shouldReload(now: Date, lastReload: Date?, lastSignature: String?, signature: String) -> Bool {
        decision(now: now, lastReload: lastReload, lastSignature: lastSignature, signature: signature) == .reload
    }

    /// Lo mismo, diciendo cuándo si ha cambiado algo y aún es pronto.
    static func decision(now: Date, lastReload: Date?, lastSignature: String?, signature: String) -> WidgetReloadDecision {
        guard let lastReload else { return .reload }
        let elapsed = now.timeIntervalSince(lastReload)
        if elapsed < 0 { return .reload }          // el reloj ha ido hacia atrás
        if signature != lastSignature {
            return elapsed >= minimumGap ? .reload : .later(lastReload.addingTimeInterval(minimumGap))
        }
        return elapsed >= idleGap ? .reload : .skip
    }

    // MARK: - Fontanería

    private static var isEnabled: Bool {
        !Capabilities.isWidgetExtension && !Capabilities.isLite && Capabilities.hasAppGroup
    }

    private static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: Capabilities.appGroupID)
    }

    private enum Keys {
        static let failure = "widget.failure"
        static let failureAt = "widget.failureAt"
    }

    private static func clearFailure() {
        guard let defaults = groupDefaults, defaults.string(forKey: Keys.failure) != nil else { return }
        defaults.removeObject(forKey: Keys.failure)
        defaults.removeObject(forKey: Keys.failureAt)
    }

    private static func reloadAll() {
        // En el hilo principal: WidgetCenter no promete ser seguro entre
        // hilos y así da igual desde dónde se llame.
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Una sola recarga pendiente a la vez: la hace quien llegue a `date`.
    private static func schedulePending(at date: Date) {
        guard throttle.markPending() else { return }
        let wait = max(1, date.timeIntervalSinceNow)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if WidgetRefresher.throttle.firePending(now: Date()) {
                WidgetRefresher.reloadAll()
            }
        }
    }

    private static let throttle = RefreshThrottle()
}

/// Qué hacer con un aviso de tablero nuevo.
enum WidgetReloadDecision: Equatable, Sendable {
    /// Recargar ya.
    case reload
    /// Ha cambiado lo que se ve, pero hace poco de la última: a esta hora.
    case later(Date)
    /// No ha cambiado nada que se vea.
    case skip
}

/// Cuándo fue la última recarga y qué se veía. Con cerrojo: se puede llamar
/// desde cualquier hilo.
private final class RefreshThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReload: Date?
    private var lastSignature: String?
    private var pendingSignature: String?
    private var hasPendingTask = false

    func decide(signature: String, now: Date) -> WidgetReloadDecision {
        lock.lock()
        defer { lock.unlock() }
        let decision = WidgetRefresher.decision(now: now, lastReload: lastReload,
                                                lastSignature: lastSignature, signature: signature)
        switch decision {
        case .reload:
            lastReload = now
            lastSignature = signature
            pendingSignature = nil
        case .later:
            pendingSignature = signature
        case .skip:
            break
        }
        return decision
    }

    /// true si no había ya una tarea esperando.
    func markPending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasPendingTask { return false }
        hasPendingTask = true
        return true
    }

    /// La tarea pendiente ha despertado: true si aún hay algo que recargar.
    func firePending(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        hasPendingTask = false
        guard let pendingSignature else { return false }
        lastReload = now
        lastSignature = pendingSignature
        self.pendingSignature = nil
        return true
    }
}
