import XCTest

/// El tablero con datos de prueba: vía real, vía probable punteada con
/// «probable», bus a 1h46, línea cortada, aviso en francés «traduciendo» y
/// el detalle de un tramo.
final class TableroUITests: TrajetUITestCase {

    /// Cinco tramos (el caso difícil): cabecera con la ruta, píldora en
    /// directo, tarjetas, metro cortado con aviso sin traducir y el botón rojo
    /// de alternativa.
    @MainActor
    func testTableroCincoTramos() {
        arrancarTablero("cincoTramos")

        // Cabecera: quién eligió la ruta y cuál es (R37).
        esperar(app.staticTexts["La que toca ahora"])
        esperar(elementoQueEmpieza("Ruta: Casa → Trabajo"))
        // Píldora: en directo, con la antigüedad (R17, R18).
        esperar(elementoQueEmpieza("Dato de hace"))

        // Los cinco tramos existen.
        for seq in 0...4 {
            esperar(identificado("tablero.tramo.\(seq)"))
        }
        // El bus con retraso: «+11 min» en el billete (R14) y la frase entera
        // de VoiceOver (R50).
        esperar(elementoQueContiene("Bus a Pont de Bezons, en 6 minutos, a las 12:56, 11 minutos de retraso"))
        // El tranvía sin salidas y la línea normal: «Servicio finalizado» (R25).
        esperar(elementoQueEmpieza("Servicio finalizado"))

        // El metro 13 está cortado y su aviso sigue en francés (R8, R27).
        let metro = identificado("tablero.tramo.3")
        XCTAssertTrue(desplazarHasta(metro))
        esperar(app.staticTexts["Interrumpida"])
        esperar(elemento("Traduciendo el aviso"))
        esperar(elementoQueContiene("Le trafic est interrompu"))
        // Metro: sin vía, ni hueco (R3): el tren parado en el andén se dice.
        esperar(elementoQueContiene("Metro a Châtillon - Montrouge, parado en el andén"))

        // Abajo, el botón de alternativa en rojo con la línea cortada (R29).
        let alternatives = botonQueEmpieza("Buscar alternativa")
        XCTAssertTrue(desplazarHasta(alternatives))
        XCTAssertEqual(alternatives.label, "Buscar alternativa · línea 13 cortada")
        // Y el pie con la cuota y el ritmo (R46, R7).
        esperar(elementoQueContiene("llamadas hoy · se refresca cada 30 s mientras miras"))
    }

    /// Vía probable: recuadro «probable» con el porcentaje, nunca «Vía» (R10),
    /// y su explicación en el detalle (R49).
    @MainActor
    func testViaProbableYSuExplicacion() {
        arrancarTablero("viaProbable")
        // El billete lo dice como una frase (R50): «vía 21 probable, 90 por ciento».
        esperar(elementoQueContiene("vía 21 probable, 90 por ciento"))
        XCTAssertFalse(elementoQueContiene("Tren a Ermont - Eaubonne, en 7 minutos, a las 12:57, vía 21,").exists,
                       "Una vía probable nunca se lee como vía real")

        abrirTramo(0)
        esperar(app.navigationBars["Línea J"])
        esperar(elementoQueContiene("Sale por la 21 el 90"))
        esperar(elementoQueContiene("20 observaciones, por el número de tren"))
        app.buttons["Cerrar"].tap()
        esperarQueDesaparezca(app.navigationBars["Línea J"])
    }

    /// Vía real: «Vía 21» sólida en el billete y probable en la ficha.
    @MainActor
    func testViaRealEnElBillete() {
        arrancarTablero("unTramo")
        esperar(elementoQueContiene("Tren a Ermont - Eaubonne, en 7 minutos, a las 12:57, vía 21, tren largo."))
        esperar(elementoQueContiene("en 22 minutos, a las 13:12, vía 21 probable, 90 por ciento"))
    }

    /// Bus a 1h46: minutos largos sin «min» (R6), leídos «1 hora y 46 minutos».
    @MainActor
    func testBusAUnaHoraCuarentaYSeis() {
        arrancarTablero("bus106")
        esperar(elementoQueContiene("Bus a Sartrouville RER, en 12 minutos"))
        esperar(elementoQueContiene("en 1 hora, a las 13:50"))
        esperar(elementoQueContiene("en 1 hora y 46 minutos, a las 14:36, 11 minutos de retraso"))
        esperar(elementoQueContiene("en 2 horas y 45 minutos"))
    }

    /// Línea cortada: «Sin circulación» (R25), «Interrumpida» con el aviso ya
    /// traducido y el botón rojo «Buscar alternativa · línea 14 cortada».
    @MainActor
    func testLineaCortada() {
        arrancarTablero("lineaCortada")
        esperar(elementoQueEmpieza("Sin circulación"))
        esperar(app.staticTexts["Interrumpida"])
        esperar(elementoQueContiene("Tráfico interrumpido en toda la línea"))
        XCTAssertFalse(elemento("Traduciendo el aviso").exists, "Ya está traducido")
        let alternatives = botonQueEmpieza("Buscar alternativa")
        XCTAssertTrue(desplazarHasta(alternatives))
        XCTAssertEqual(alternatives.label, "Buscar alternativa · línea 14 cortada")
    }

    /// El detalle del metro cortado: aviso en los dos idiomas (R27), «Aún sin
    /// traducir» mientras no llega (R8), y cada salida como una frase.
    @MainActor
    func testDetalleDelTramoCortado() {
        arrancarTablero("cincoTramos")
        abrirTramo(3)
        esperar(app.navigationBars["Línea 13"])
        esperar(app.staticTexts["Interrumpida"])
        esperar(app.staticTexts["Aún sin traducir"])
        esperar(app.staticTexts["Original en francés"])
        esperar(elementoQueContiene("Le trafic est interrompu"))
        esperar(elementoQueContiene("parado en el andén"))
        app.buttons["Cerrar"].tap()
        esperarQueDesaparezca(app.navigationBars["Línea 13"])
    }

    /// Dato viejo (R19): la píldora lo dice y el tablero sigue (R9).
    @MainActor
    func testDatoViejoSeDiceYElTableroSigue() {
        arrancarTablero("viejo")
        esperar(elementoQueEmpieza("Dato viejo, de hace"))
        esperar(identificado("tablero.tramo.0"))
    }

    /// Sin conexión con caché: el último tablero con su antigüedad (R9).
    @MainActor
    func testSinConexionConservaElUltimoTablero() {
        arrancarTablero("sinConexion")
        esperar(elementoQueEmpieza("Sin conexión. Último tablero de hace 4 minutos"), 15)
        esperar(identificado("tablero.tramo.0"))
    }

    /// Sin rutas: el vacío dice qué hacer (R53) y lleva a Rutas.
    @MainActor
    func testSinRutasDiceQueHacer() {
        arrancarTablero("vacio")
        esperar(app.staticTexts["Todavía no hay ninguna ruta"])
        let create = app.buttons["Crear una ruta"]
        esperar(create)
        create.tap()
        esperar(app.navigationBars["Rutas"])
        esperar(app.staticTexts["Aún no hay ninguna ruta"])
    }
}
