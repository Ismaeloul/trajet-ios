import CoreLocation
import XCTest
@testable import Trajet

/// Polilínea codificada de Google, precisión 5 (el trazado del mapa).
final class PolylineTests: XCTestCase {

    /// El ejemplo de la documentación de Google.
    func testEjemploDeGoogle() {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        assertPoint(points[0], 38.5, -120.2)
        assertPoint(points[1], 40.7, -120.95)
        assertPoint(points[2], 43.252, -126.453)
    }

    /// El trazado de la J del banco de pruebas: de Saint-Lazare a Argenteuil.
    func testTrazadoDeLaJ() throws {
        let path = try XCTUnwrap(PreviewData.routeMap.lines.first?.path)
        let coarse = path.coarseCoordinates
        XCTAssertEqual(coarse.count, 6)
        assertPoint(coarse[0], 48.87748, 2.32444)
        assertPoint(try XCTUnwrap(coarse.last), 48.9469, 2.25791)
        let fine = path.fineCoordinates
        XCTAssertEqual(fine.count, 18)
        assertPoint(fine[0], 48.87748, 2.32444)
        // Todo el trazado cae entre las dos estaciones.
        for p in fine {
            XCTAssertTrue((48.87...48.95).contains(p.latitude))
            XCTAssertTrue((2.25...2.33).contains(p.longitude))
        }
    }

    func testIdaYVuelta() {
        let encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        XCTAssertEqual(Polyline.encode(Polyline.decode(encoded)), encoded)
        let coarse = PreviewData.routeMap.lines[0].path?.coarse ?? ""
        XCTAssertEqual(Polyline.encode(Polyline.decode(coarse)), coarse)
    }

    /// Una cadena rota no revienta: devuelve lo que se haya podido leer.
    func testCadenaRotaYVacia() {
        XCTAssertTrue(Polyline.decode("").isEmpty)
        let cut = Polyline.decode("_p~iF~ps|U_ulL")
        XCTAssertEqual(cut.count, 1)
        assertPoint(cut[0], 38.5, -120.2)
        let junk = Polyline.decode("_p~iF~ps|U  \u{1}")
        XCTAssertEqual(junk.count, 1)
    }

    private func assertPoint(_ p: CLLocationCoordinate2D, _ lat: Double, _ lon: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.latitude, lat, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(p.longitude, lon, accuracy: 0.00001, file: file, line: line)
    }
}
