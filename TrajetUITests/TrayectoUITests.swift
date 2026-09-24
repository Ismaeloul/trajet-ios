import XCTest

/// Empezar y parar un trayecto, desde el tablero y desde la pestaña Trayecto;
/// y sin permiso de ubicación el trayecto sigue sin GPS.
final class TrayectoUITests: TrajetUITestCase {

    /// Desde el tablero: «Empezar trayecto» → «Trayecto en marcha» + «Parar
    /// trayecto» → «Empezar trayecto» otra vez.
    @MainActor
    func testEmpezarYPararDesdeElTablero() {
        arrancarTablero("cincoTramos")
        let start = identificado("tablero.empezar")
        XCTAssertTrue(desplazarHasta(start))
        start.tap()

        let stop = identificado("tablero.parar")
        esperar(stop, 15)
        esperar(elementoQueContiene("Trayecto en marcha"))
        // La pestaña Trayecto también lo sabe.
        irA("Trayecto")
        esperar(identificado("trayecto.parar"), 10)
        esperar(elementoQueEmpieza("Sigue en segundo plano · se apaga al llegar"))
        irA("Tablero")

        XCTAssertTrue(desplazarHasta(stop))
        stop.tap()
        esperar(start, 10)
        XCTAssertFalse(elementoQueContiene("Trayecto en marcha").exists)
    }

    /// Desde la pestaña Trayecto (la tarjeta del mapa), con la ubicación de
    /// la demo ya permitida: no sale ninguna pregunta.
    @MainActor
    func testEmpezarYPararDesdeElMapa() {
        arrancarTablero("tranquilo")
        irA("Trayecto")
        let start = identificado("trayecto.empezar")
        esperar(start, 15)
        // El billete del tramo que toca y el pie con el tiempo máximo.
        esperar(elementoQueContiene("Refresca los trenes y la Live Activity hasta que llegues"))
        start.tap()

        let stop = identificado("trayecto.parar")
        esperar(stop, 15)
        esperar(elementoQueEmpieza("Sigue en segundo plano"))
        // Con un trayecto en marcha la ruta no se puede cambiar.
        let pill = elementoQueEmpieza("Ruta: ")
        esperar(pill)
        XCTAssertFalse(pill.isEnabled, "La píldora de ruta se bloquea durante el trayecto")

        stop.tap()
        esperar(start, 10)
        XCTAssertTrue(pill.isEnabled)
    }

    /// Sin permiso de ubicación (`-demoSinUbicacion`): se explica antes de
    /// pedirlo, «Sin ubicación» arranca igual y el pie dice que se apaga solo.
    @MainActor
    func testSinPermisoDeUbicacionElTrayectoSigueSinGPS() {
        arrancarTablero("tranquilo", extra: ["-demoSinUbicacion"])
        irA("Trayecto")
        let start = identificado("trayecto.empezar")
        esperar(start, 15)
        start.tap()

        // La explicación, antes de que iOS pregunte nada.
        let alert = app.alerts["Ubicación durante el trayecto"]
        esperar(alert, 10)
        esperar(alert.buttons["Sin ubicación"])
        alert.buttons["Sin ubicación"].tap()

        let stop = identificado("trayecto.parar")
        esperar(stop, 15)
        esperar(elementoQueEmpieza("Sin ubicación: no sabe cuándo llegas · se apaga solo a las"))
        stop.tap()
        esperar(start, 10)
    }

    /// Con «Continuar» el sistema (aquí la demo) deniega: el trayecto sigue
    /// sin GPS y ofrece dar el permiso en Ajustes.
    @MainActor
    func testPermisoDenegadoNoParaElTrayecto() {
        arrancarTablero("tranquilo", extra: ["-demoSinUbicacion"])
        irA("Trayecto")
        let start = identificado("trayecto.empezar")
        esperar(start, 15)
        start.tap()

        let alert = app.alerts["Ubicación durante el trayecto"]
        esperar(alert, 10)
        alert.buttons["Continuar"].tap()

        let stop = identificado("trayecto.parar")
        esperar(stop, 15)
        esperar(elementoQueEmpieza("Sin ubicación: no sabe cuándo llegas"))
        esperar(app.buttons["Dar permiso de ubicación en Ajustes"])
        stop.tap()
        esperar(start, 10)
    }
}
