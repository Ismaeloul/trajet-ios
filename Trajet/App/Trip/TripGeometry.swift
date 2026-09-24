import Foundation

/// El mapa de una ruta, visto desde el modo trayecto (en los tests, uno
/// falso). `MapStore` ya lo cumple.
@MainActor
protocol RouteMapProviding: AnyObject {
    func map(for routeID: Int) -> RouteMap?
    func load(routeID: Int, force: Bool) async
}

extension MapStore: RouteMapProviding {}

/// Las cuentas del modo trayecto, sin estado (se prueban solas).
enum TripGeometry {

    /// A menos de esto de la estación de destino, se ha llegado.
    static let arrivalRadius: Double = 150
    /// Hay que haber estado al menos así de lejos del destino para que
    /// acercarse cuente como llegar (empezar al lado no es llegar).
    static let armDistance: Double = 400
    /// Posiciones peores que esto (antenas lejanas) no deciden nada.
    static let maxUsableAccuracy: Double = 250
    /// Posiciones más viejas que esto (la última que tenía iOS) tampoco.
    static let maxFixAge: TimeInterval = 120
    /// Cerca de la subida de un tramo siguiente = ya se va por ese tramo.
    static let legReachRadius: Double = 250

    /// Dónde se acaba la ruta: la estación con papel «destino» del mapa o,
    /// si no la hay (mapa aún calculándose), la bajada del último tramo.
    static func destination(in map: RouteMap?) -> GeoPoint? {
        guard let map else { return nil }
        if let station = map.stations.first(where: { $0.role == .destination }), station.geoPoint.isValid {
            return station.geoPoint
        }
        if let last = map.lines.max(by: { $0.seq < $1.seq }), last.to.geoPoint.isValid {
            return last.to.geoPoint
        }
        return nil
    }

    /// La posición sirve para decidir (precisión razonable y reciente).
    static func isUsable(_ fix: TripLocation, now: Date) -> Bool {
        fix.point.isValid
            && fix.horizontalAccuracy >= 0
            && fix.horizontalAccuracy <= maxUsableAccuracy
            && now.timeIntervalSince(fix.timestamp) <= maxFixAge
    }

    /// Llegada: a menos de `radius` metros del destino.
    static func hasArrived(_ fix: TripLocation, destination: GeoPoint, radius: Double = arrivalRadius) -> Bool {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxUsableAccuracy else { return false }
        return fix.point.distance(to: destination) <= radius
    }

    /// El tramo por el que se va: el último tramo posterior al actual cuya
    /// subida está cerca. Nunca vuelve atrás.
    static func legSeq(current: Int, fix: GeoPoint, lines: [MapLine]) -> Int {
        var result = current
        for line in lines.sorted(by: { $0.seq < $1.seq }) where line.seq > current {
            let boarding = line.from.geoPoint
            if boarding.isValid, fix.distance(to: boarding) <= legReachRadius {
                result = line.seq
            }
        }
        return result
    }
}
