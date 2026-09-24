import XCTest

final class EsqueletoUITests: XCTestCase {
    @MainActor
    func testArranca() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Trajet"].waitForExistence(timeout: 10))
    }
}
