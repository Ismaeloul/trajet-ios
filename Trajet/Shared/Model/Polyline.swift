import CoreLocation
import Foundation

/// Polilínea codificada de Google, precisión 5 (la `polyline5` del mapa).
///
/// Cada coordenada va como diferencia con la anterior, en grupos de 5 bits
/// desplazados a ASCII 63…126. Tolerante: si la cadena viene rota, devuelve
/// los puntos que se hayan podido leer hasta ahí, nunca revienta.
enum Polyline {

    static let precision: Double = 1e5

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(bytes.count / 4)
        var index = 0
        var lat = 0
        var lon = 0
        while index < bytes.count {
            guard let dLat = nextValue(bytes, &index),
                  let dLon = nextValue(bytes, &index)
            else { break }
            lat += dLat
            lon += dLon
            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / precision,
                                                      longitude: Double(lon) / precision))
        }
        return coordinates
    }

    /// El camino inverso. Solo lo usan los tests y los bancos de prueba.
    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> String {
        var out = ""
        var prevLat = 0
        var prevLon = 0
        for c in coordinates {
            let lat = Int((c.latitude * precision).rounded())
            let lon = Int((c.longitude * precision).rounded())
            out += encodeValue(lat - prevLat)
            out += encodeValue(lon - prevLon)
            prevLat = lat
            prevLon = lon
        }
        return out
    }

    // MARK: - Fontanería

    private static func nextValue(_ bytes: [UInt8], _ index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < bytes.count {
            let chunk = Int(bytes[index]) - 63
            index += 1
            guard (0...63).contains(chunk), shift <= 30 else { return nil }
            result |= (chunk & 0x1F) << shift
            shift += 5
            if chunk < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        return nil   // cadena cortada a mitad de un número
    }

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : (value << 1)
        var out = ""
        while v >= 0x20 {
            out.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63))))
            v >>= 5
        }
        out.append(Character(UnicodeScalar(UInt8(v + 63))))
        return out
    }
}
