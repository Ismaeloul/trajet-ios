import Foundation

/// El último tablero bueno, con su hora de llegada al teléfono.
///
/// Se guarda la hora de llegada junto al tablero y no se pierde nunca: si se
/// recuperase sin ella, el tablero de anoche parecería recién hecho, que es
/// justo la mentira que la app promete no contar (R20). Al leerlo,
/// `board.receivedAt` vale siempre `receivedAt`.
struct CachedBoard: Codable, Hashable, Sendable {
    let board: Board
    let receivedAt: Date
    /// La ruta fijada a mano cuando se guardó (nil = la elegía el servidor).
    let routeID: Int?

    init(board: Board, receivedAt: Date, routeID: Int?) {
        var b = board
        b.receivedAt = receivedAt
        self.board = b
        self.receivedAt = receivedAt
        self.routeID = routeID
    }

    enum CodingKeys: String, CodingKey {
        case board, receivedAt
        // `route_id` → «routeId» con convertFromSnakeCase.
        case routeID = "routeId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date = try c.decode(Date.self, forKey: .receivedAt)
        var b = try c.decode(Board.self, forKey: .board)
        b.receivedAt = date
        board = b
        receivedAt = date
        routeID = c.opt(.routeID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(board, forKey: .board)
        try c.encode(receivedAt, forKey: .receivedAt)
        try c.encodeIfPresent(routeID, forKey: .routeID)
    }
}

/// El tablero en disco: JSON (la forma de la API, snake_case) más la fecha de
/// llegada. Vive en el App Group si existe —lo leen los widgets y la Live
/// Activity— y si no en Application Support. Lectura y escritura síncronas;
/// la escritura es atómica (fichero temporal + renombrado), así que otro
/// proceso nunca lee un fichero a medias.
enum BoardCache {

    static let fileName = "last-board.json"

    /// Dónde se guarda ahora mismo.
    static var fileURL: URL? {
        groupFileURL ?? localFileURL
    }

    /// En el App Group (compartido con la extensión).
    static var groupFileURL: URL? {
        guard let container = Capabilities.appGroupContainer else { return nil }
        return directory(container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true))?
            .appendingPathComponent(fileName)
    }

    /// En la app (lite, o full sin App Group).
    static var localFileURL: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
        else { return nil }
        return base.appendingPathComponent(fileName)
    }

    /// El último tablero guardado. Primero el del App Group; si no hay, el
    /// local (una instalación que acaba de ganar el App Group no pierde nada).
    static func load() -> CachedBoard? {
        if let url = groupFileURL, let cached = load(from: url) { return cached }
        if let url = localFileURL, let cached = load(from: url) { return cached }
        return nil
    }

    static func save(_ cached: CachedBoard) {
        guard let url = fileURL else { return }
        save(cached, to: url)
    }

    /// Borra el tablero guardado (desemparejar, o ya no hay rutas).
    static func clear() {
        for url in [groupFileURL, localFileURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Con un fichero concreto (tests y usos avanzados)

    static func load(from url: URL) -> CachedBoard? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.trajet.decode(CachedBoard.self, from: data)
    }

    @discardableResult
    static func save(_ cached: CachedBoard, to url: URL) -> Bool {
        guard let data = try? JSONEncoder.trajet.encode(cached) else { return false }
        do {
            // Protección «hasta el primer desbloqueo»: el modo trayecto y los
            // widgets la leen con el iPhone bloqueado.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private static func directory(_ url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }
}
