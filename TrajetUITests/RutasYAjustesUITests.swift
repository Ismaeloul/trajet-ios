import XCTest

/// Rutas (lista y editor), el planificador, el historial y Ajustes: que se
/// abren, enseñan lo suyo y se cierran sin romper nada.
final class RutasYAjustesUITests: TrajetUITestCase {

    /// La lista de rutas (la misma que el selector del tablero, R41) con la
    /// que toca marcada, y el editor al tocar una.
    @MainActor
    func testListaYEditorDeRutas() {
        arrancarTablero("cincoTramos")
        irA("Rutas")
        esperar(app.navigationBars["Rutas"])
        esperar(app.staticTexts["Se elige sola según el día y la hora"])
        // Las cuatro rutas de la demo, dichas como una frase.
        let active = elementoQueEmpieza("Casa → Trabajo. es la que toca ahora")
        esperar(active)
        esperar(elementoQueEmpieza("Trabajo → Casa"))
        esperar(elementoQueEmpieza("Saint-Lazare → Argenteuil"))
        esperar(elementoQueEmpieza("Vuelta de clase"))
        // Días en español y el horario tal como se definió (R35, R36).
        esperar(elementoQueContiene("entre semana"))

        XCTAssertTrue(desplazarHasta(active))
        active.tap()
        esperar(app.navigationBars["Editar ruta"], 10)
        esperar(app.textFields["Nombre de la ruta"])
        esperar(app.staticTexts["Itinerario"])
        // Sin cambios, «Guardar» está apagado y se puede volver.
        let save = app.buttons["Guardar"]
        esperar(save)
        XCTAssertFalse(save.isEnabled)
        atras()
        esperar(app.navigationBars["Rutas"])
    }

    /// «+» → «Montar a mano»: la ruta nueva, y cancelar sin guardar.
    @MainActor
    func testNuevaRutaAManoYCancelar() {
        arrancarTablero("cincoTramos")
        irA("Rutas")
        let plus = elemento("Nueva ruta")
        esperar(plus)
        plus.tap()
        let manual = elemento("Montar a mano")
        esperar(manual)
        manual.tap()

        esperar(app.navigationBars["Nueva ruta"], 10)
        esperar(app.buttons["Añadir el primer tramo"])
        // Lunes a viernes por defecto (R36) y «Llego a» (R38).
        esperar(elementoQueContiene("entre semana"))
        esperar(elementoQueEmpieza("Llego a las"))
        let cancel = app.buttons["Cancelar"]
        esperar(cancel)
        cancel.tap()
        esperarQueDesaparezca(app.navigationBars["Nueva ruta"])
        esperar(app.navigationBars["Rutas"])
    }

    /// El planificador: nada se pide hasta «Buscar» y los sitios se eligen
    /// buscando (R31).
    @MainActor
    func testPlanificadorSeAbreYSeCierra() {
        arrancarTablero("cincoTramos")
        irA("Rutas")
        let search = app.buttons["Buscar un trayecto"]
        XCTAssertTrue(desplazarHasta(search))
        search.tap()

        esperar(app.navigationBars["Buscar trayecto"], 10)
        let from = elemento("Desde: sin elegir")
        esperar(from)
        let go = app.buttons["Buscar itinerarios"]
        esperar(go)
        XCTAssertFalse(go.isEnabled, "Sin origen ni destino no se busca")

        from.tap()
        esperar(app.navigationBars["¿Desde dónde?"], 10)
        app.buttons["Cancelar"].tap()
        esperarQueDesaparezca(app.navigationBars["¿Desde dónde?"])

        app.buttons["Cerrar"].tap()
        esperarQueDesaparezca(app.navigationBars["Buscar trayecto"])
    }

    /// El historial: resumen, gráficos y la previsión de vía (R11).
    @MainActor
    func testHistorial() {
        arrancarTablero("cincoTramos")
        irA("Historial")
        esperar(app.navigationBars["Historial"])
        esperar(app.staticTexts["Últimos 90 días"], 10)
        esperar(app.staticTexts["Días con incidencias"])
        esperar(elementoQueEmpieza("128"))
        // Coma decimal (R56).
        esperar(elementoQueContiene("3,4"))
        let accuracy = app.staticTexts["Previsión de vía"]
        XCTAssertTrue(desplazarHasta(accuracy))
        esperar(elementoQueContiene("84"))
    }

    /// Ajustes se abre como hoja desde el tablero, enseña el servidor y la
    /// versión, y se cierra.
    @MainActor
    func testAjustesSeAbrenYSeCierran() {
        arrancarTablero("cincoTramos")
        let gear = app.buttons["Ajustes"]
        esperar(gear)
        gear.tap()

        esperar(app.navigationBars["Ajustes"], 10)
        esperar(app.staticTexts["Servidor"])
        esperar(app.textFields["Nombre del servidor"])
        esperar(app.buttons["Probar conexión"])
        esperar(app.staticTexts["Este iPhone"])
        // El estado del servidor llega del /health de la demo (sin cuota).
        // Está más abajo: la lista solo tiene lo que se ve, hay que bajar.
        XCTAssertTrue(desplazarHasta(app.staticTexts["Estado del servidor"]),
                      "No se llega al estado del servidor")
        esperar(elementoQueContiene("Clave de PRIM"), 10)
        // Abajo: el modo trayecto, permisos y la versión.
        let version = app.staticTexts["Versión de la app"]
        XCTAssertTrue(desplazarHasta(version, intentos: 12))
        esperar(elementoQueContiene("Modo demostración"))

        app.buttons["Cerrar"].tap()
        esperarQueDesaparezca(app.navigationBars["Ajustes"])
        esperar(identificado("tablero.tramo.0"))
    }

    /// Pasar por las cuatro pestañas y volver: nada se rompe y el tablero
    /// sigue con sus datos.
    @MainActor
    func testRecorrerLasPestanas() {
        arrancarTablero("cincoTramos")
        irA("Trayecto")
        esperar(identificado("trayecto.empezar"), 15)
        irA("Rutas")
        esperar(app.navigationBars["Rutas"])
        irA("Historial")
        esperar(app.navigationBars["Historial"])
        irA("Tablero")
        esperar(identificado("tablero.tramo.0"))
        esperar(elementoQueEmpieza("Ruta: Casa → Trabajo"))
    }
}
