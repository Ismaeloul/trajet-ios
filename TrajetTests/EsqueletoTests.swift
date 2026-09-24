import XCTest
@testable import Trajet

// ESQUELETO: comprueba que el target de tests enlaza con la app y que los
// bancos de prueba decodifican. Lo sustituyen los tests de verdad.
final class EsqueletoTests: XCTestCase {
    func testPreviewDataDecodifica() {
        XCTAssertEqual(PreviewData.fiveLegBoard.legs.count, 5)
        XCTAssertFalse(PreviewData.routes.isEmpty)
    }
}
