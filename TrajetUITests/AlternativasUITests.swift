import XCTest

/// Buscar una alternativa (R29, R30): la hoja con opciones y «No sirve», y
/// sin opciones «Buscar de todas formas».
final class AlternativasUITests: TrajetUITestCase {

    /// Con la 13 cortada: banner, una opción que sirve y otra que no.
    @MainActor
    func testHojaConOpcionesYNoSirve() {
        arrancarTablero("cincoTramos")
        let button = botonQueEmpieza("Buscar alternativa")
        XCTAssertTrue(desplazarHasta(button))
        button.tap()

        esperar(app.navigationBars["Alternativas"], 10)
        esperar(elementoQueContiene("Línea 13 interrumpida"))
        esperar(elementoQueContiene("tu ruta tarda 47 min cuando funciona"))
        // La opción que sirve: 59 min, 12 más, 1 transbordo (R6, R56).
        esperar(elementoQueEmpieza("59 minutos; 12 minutos más de lo normal; sale a las 12:55; llega a las 13:54; 1 transbordo"))
        // La que pasa por la línea cortada no sirve (R30).
        esperar(elementoQueContiene("No sirve: pasa por la línea cortada"))

        app.buttons["Cerrar"].tap()
        esperarQueDesaparezca(app.navigationBars["Alternativas"])
    }

    /// Sin otro camino: se dice, y «Buscar de todas formas» vuelve a pedirlo
    /// con `force` (R30).
    @MainActor
    func testSinOpcionesYBuscarDeTodasFormas() {
        arrancarTablero("lineaCortada")
        let button = botonQueEmpieza("Buscar alternativa")
        XCTAssertTrue(desplazarHasta(button))
        button.tap()

        esperar(app.navigationBars["Alternativas"], 10)
        esperar(elementoQueContiene("Línea 14 interrumpida"))
        esperar(app.staticTexts["El calculador no encuentra otro camino ahora mismo."])
        let force = app.buttons["Buscar de todas formas"]
        esperar(force)
        force.tap()
        // La demo sigue sin encontrar nada: se vuelve a decir, sin cerrar la hoja.
        esperar(app.staticTexts["El calculador no encuentra otro camino ahora mismo."], 10)
        XCTAssertTrue(app.navigationBars["Alternativas"].exists)
        app.buttons["Cerrar"].tap()
    }
}
