import Foundation
import Observation

/// Los mapas de las rutas (GET /api/v1/routes/{id}/map), en memoria y en
/// disco, con su ETag: volver a abrir el mapa de una ruta cuesta un 304 y
/// nada más. No gasta cuota de PRIM.
///
/// Si el servidor aún lo está calculando (`pending: true`), se vuelve a pedir
/// solo, unas cuantas veces, cada pocos segundos.
@MainActor
@Observable
final class MapStore {

    /// Tras esto se revalida con el servidor (con ETag) al volver a pedirlo.
    static let freshFor: TimeInterval = 10 * 60
    static let pendingRetryDelay: TimeInterval = 5
    static let pendingMaxRetries = 6

    private(set) var maps: [Int: RouteMap] = [:]
    private(set) var loading: Set<Int> = []
    private(set) var errors: [Int: APIError] = [:]

    private let api: TrajetAPI
    private let directory: URL?
    private let clock: @Sendable () -> Date

    @ObservationIgnored private var etags: [Int: String] = [:]
    @ObservationIgnored private var fetchedAt: [Int: Date] = [:]
    @ObservationIgnored private var retries: [Int: Int] = [:]

    /// `directory` nil = solo memoria (demo y tests).
    init(api: TrajetAPI, directory: URL? = MapStore.defaultDirectory,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.directory = directory
        self.clock = now
    }

    /// Caches/maps de la app.
    nonisolated static var defaultDirectory: URL? {
        guard let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
        else { return nil }
        let dir = caches.appendingPathComponent("maps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func map(for routeID: Int) -> RouteMap? { maps[routeID] }
    func isLoading(_ routeID: Int) -> Bool { loading.contains(routeID) }
    func error(for routeID: Int) -> APIError? { errors[routeID] }

    /// Memoria → disco → red (con ETag). `force` revalida aunque sea reciente.
    func load(routeID: Int, force: Bool = false) async {
        guard !loading.contains(routeID) else { return }

        if maps[routeID] == nil, let directory {
            if let stored = await Self.readDisk(directory: directory, routeID: routeID) {
                maps[routeID] = stored.map
                etags[routeID] = stored.etag
            }
        }

        if !force, let map = maps[routeID], !map.pending,
           let at = fetchedAt[routeID], clock().timeIntervalSince(at) < Self.freshFor {
            return
        }

        loading.insert(routeID)
        defer { loading.remove(routeID) }
        do {
            let etag = maps[routeID] == nil ? nil : etags[routeID]
            switch try await api.routeMap(routeID: routeID, etag: etag) {
            case .notModified:
                break
            case .modified(let map, let newEtag, let raw):
                maps[routeID] = map
                etags[routeID] = newEtag
                if let directory {
                    await Self.writeDisk(directory: directory, routeID: routeID, data: raw, etag: newEtag)
                }
            }
            fetchedAt[routeID] = clock()
            errors[routeID] = nil
        } catch is CancellationError {
            return
        } catch let error as APIError {
            errors[routeID] = error
            return
        } catch {
            errors[routeID] = .network(error.localizedDescription)
            return
        }

        schedulePendingRetry(routeID: routeID)
    }

    /// El servidor aún lo calcula: se vuelve a pedir en unos segundos.
    private func schedulePendingRetry(routeID: Int) {
        guard maps[routeID]?.pending == true else {
            retries[routeID] = nil
            return
        }
        let count = retries[routeID, default: 0]
        guard count < Self.pendingMaxRetries else { return }
        retries[routeID] = count + 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pendingRetryDelay))
            await self?.load(routeID: routeID, force: true)
        }
    }

    /// Olvida un mapa (ruta borrada o editada).
    func forget(routeID: Int) {
        maps[routeID] = nil
        etags[routeID] = nil
        fetchedAt[routeID] = nil
        errors[routeID] = nil
        if let directory {
            try? FileManager.default.removeItem(at: Self.jsonURL(directory, routeID))
            try? FileManager.default.removeItem(at: Self.etagURL(directory, routeID))
        }
    }

    /// Al desemparejar: fuera todo, también el disco.
    func clear() {
        maps = [:]
        errors = [:]
        loading = []
        etags = [:]
        fetchedAt = [:]
        retries = [:]
        if let directory,
           let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("route-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Disco (fuera del MainActor)

    nonisolated private static func jsonURL(_ dir: URL, _ id: Int) -> URL {
        dir.appendingPathComponent("route-\(id).json")
    }

    nonisolated private static func etagURL(_ dir: URL, _ id: Int) -> URL {
        dir.appendingPathComponent("route-\(id).etag")
    }

    private struct Stored: Sendable {
        let map: RouteMap
        let etag: String?
    }

    nonisolated private static func readDisk(directory: URL, routeID: Int) async -> Stored? {
        let json = MapStore.jsonURL(directory, routeID)
        let tag = MapStore.etagURL(directory, routeID)
        return await Task.detached(priority: .utility) { () -> Stored? in
            guard let data = try? Data(contentsOf: json),
                  let map = try? JSONDecoder.trajet.decode(RouteMap.self, from: data)
            else { return nil }
            let etag = try? String(contentsOf: tag, encoding: .utf8)
            return Stored(map: map, etag: etag)
        }.value
    }

    nonisolated private static func writeDisk(directory: URL, routeID: Int, data: Data, etag: String?) async {
        let json = MapStore.jsonURL(directory, routeID)
        let tag = MapStore.etagURL(directory, routeID)
        await Task.detached(priority: .utility) {
            try? data.write(to: json, options: .atomic)
            if let etag {
                try? Data(etag.utf8).write(to: tag, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: tag)
            }
        }.value
    }
}
