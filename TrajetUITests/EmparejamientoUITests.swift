import XCTest

/// Emparejar con el código escrito a mano (escenario `emparejar`, código
/// DEMO-2026) hasta ver el tablero.
final class EmparejamientoUITests: TrajetUITestCase {

    /// Sin emparejar, la primera pantalla es la de emparejar; se escribe el
    /// código, se empareja y se llega al tablero con datos.
    @MainActor
    func testEmparejarConCodigoAManoHastaElTablero() {
        arrancar("emparejar")

        // La pantalla de emparejar, con los dos caminos.
        esperar(app.staticTexts["Trajet"])
        esperar(app.buttons["Escanear el QR"])
        let manual = app.buttons["Escribir a mano"]
        esperar(manual)
        manual.tap()

        // La hoja a mano: el código, con la dirección de la demo ya puesta.
        let code = app.textFields["emparejar.codigo"]
        esperar(code)
        let send = identificado("emparejar.enviar")
        esperar(send)
        XCTAssertFalse(send.isEnabled, "Sin código no se puede emparejar")

        escribir(Self.demoCode, en: code)
        XCTAssertTrue(send.isEnabled, "Con el código escrito se puede emparejar")
        send.tap()

        // Emparejado: «Listo» y, tras un momento, las pestañas.
        esperar(pestana("Tablero"), 20)
        esperar(app.buttons["Ajustes"], 10)
        esperar(identificado("tablero.tramo.0"), 15)
        esperar(identificado("tablero.empezar"), 10)
    }

    /// Un código que no vale se dice en la misma hoja, sin cerrarla.
    @MainActor
    func testCodigoQueNoValeSeDiceEnLaHoja() {
        arrancar("emparejar")
        let manual = app.buttons["Escribir a mano"]
        esperar(manual)
        manual.tap()

        let code = app.textFields["emparejar.codigo"]
        escribir("ABCD-EFGH", en: code)
        let send = identificado("emparejar.enviar")
        esperar(send)
        send.tap()

        esperar(elementoQueContiene("Ese código ya no vale"), 10)
        // Sigue en la hoja: el campo del código está ahí.
        XCTAssertTrue(code.exists)
        XCTAssertFalse(pestana("Tablero").exists)
    }
}
