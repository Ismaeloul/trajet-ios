import MapKit
import Observation
import SwiftUI

/// A dónde se va andando: el acceso más cercano de la estación de subida (de
/// los datos abiertos de IDFM) o, si no hay accesos, la propia estación.
struct WalkingTarget: Hashable, Sendable {
    var stationName: String
    var point: GeoPoint
    /// «r. Budapest», «acceso 1 · cour de Rome»…
    var accessName: String?
    /// Segundos del acceso al andén (pathways de IDFM), si se saben.
    var insideSeconds: Int?

    /// La subida del tramo `legSeq` (o del primero) y, si se sabe dónde está
    /// uno, su acceso de entrada más cercano.
    static func resolve(map: RouteMap, legSeq: Int?, user: GeoPoint?) -> WalkingTarget? {
        let lines = map.lines.sorted { $0.seq < $1.seq }
        guard let line = lines.first(where: { $0.seq == legSeq }) ?? lines.first else { return nil }
        let stop = line.from
        let station = map.station(zdc: stop.zdc)
        let name = station?.name ?? stop.name
        let entries = map.accesses(zdc: stop.zdc).filter { $0.entry && $0.geoPoint.isValid }
        if let user, let nearest = entries.min(by: { user.distance(to: $0.geoPoint) < user.distance(to: $1.geoPoint) }) {
            let paths = nearest.toStop
            let inside = paths.first(where: { $0.stopId == stop.stopId && $0.s != nil })?.s
                ?? paths.compactMap(\.s).first
            return WalkingTarget(stationName: name, point: nearest.geoPoint,
                                 accessName: accessLabel(nearest), insideSeconds: inside)
        }
        let point = station?.geoPoint ?? stop.geoPoint
        guard point.isValid else { return nil }
        return WalkingTarget(stationName: name, point: point, accessName: nil, insideSeconds: nil)
    }

    static func accessLabel(_ access: MapAccess) -> String? {
        let name = access.name.trimmingCharacters(in: .whitespaces)
        if let number = access.number, !number.isEmpty {
            return name.isEmpty ? "acceso \(number)" : "acceso \(number) · \(name)"
        }
        return name.isEmpty ? nil : name
    }
}

/// El camino a pie hasta la estación, con MKDirections (`.walking`). Solo
/// con permiso de ubicación. Se calcula de vez en cuando (Apple limita las
/// peticiones): al cambiar de destino, al moverse más de 75 m o cada 3 min.
@MainActor
@Observable
final class WalkingGuide {

    struct Route: Equatable, Sendable {
        var path: [GeoPoint]
        var seconds: TimeInterval
        var meters: Double
    }

    /// Más cerca que esto ya se está en la estación.
    nonisolated static let arrivedDistance: Double = 60
    /// Más lejos que esto no se propone ir andando.
    nonisolated static let maxDistance: Double = 4_000

    private(set) var target: WalkingTarget? = nil
    private(set) var route: Route? = nil

    @ObservationIgnored private var lastOrigin: GeoPoint? = nil
    @ObservationIgnored private var lastTarget: WalkingTarget? = nil
    @ObservationIgnored private var lastAt: Date? = nil

    init() {}

    /// Minutos a pie (los de MKDirections, no los de la API).
    var minutes: Int? {
        guard let route else { return nil }
        return max(1, Int((route.seconds / 60).rounded(.up)))
    }

    /// Lo que queda dentro de la estación, en minutos (pathways de IDFM).
    var insideMinutes: Int? {
        guard let seconds = target?.insideSeconds, seconds > 0 else { return nil }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    func clear() {
        target = nil
        route = nil
    }

    func update(user: TripLocation?, target: WalkingTarget?) async {
        self.target = target
        guard let user, let target else {
            route = nil
            return
        }
        let distance = user.point.distance(to: target.point)
        guard distance > Self.arrivedDistance, distance < Self.maxDistance else {
            route = nil
            return
        }
        if route != nil, lastTarget == target, let lastOrigin, let lastAt,
           lastOrigin.distance(to: user.point) < 75, Date().timeIntervalSince(lastAt) < 180 {
            return
        }
        lastOrigin = user.point
        lastTarget = target
        lastAt = Date()
        let result = await Self.calculate(from: user.point, to: target.point)
        guard !Task.isCancelled, self.target == target else { return }
        route = result
    }

    /// MKDirections fuera del MainActor: entra y sale solo con valores
    /// `Sendable` (los objetos de MapKit no cruzan de actor).
    nonisolated static func calculate(from origin: GeoPoint, to destination: GeoPoint) async -> Route? {
        let request = MKDirections.Request()
        // TODO-COMPILAR: `MKPlacemark` y `MKMapItem(placemark:)` están
        // obsoletos en iOS 26 (aviso, no error); la alternativa nueva es
        // `MKMapItem(location:address:)`.
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else { return nil }
            return Route(path: points(of: best.polyline), seconds: best.expectedTravelTime, meters: best.distance)
        } catch {
            return nil
        }
    }

    nonisolated private static func points(of polyline: MKPolyline) -> [GeoPoint] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                                   count: count)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
        return coordinates.map { GeoPoint($0) }
    }
}
