import XCTest

/// Abrir el mapa: desde el tablero (el mapa entero de la ruta) y en la
/// pestaña Trayecto (mapa con la tarjeta del modo trayecto).
final class MapaUITests: TrajetUITestCase {

    /// El botón redondo del tablero abre el mapa entero, con el nombre de la
    /// ruta y el atajo a la pestaña Trayecto.
    @MainActor
    func testAbrirElMapaDesdeElTablero() {
        arrancarTablero("tranquilo")
        let open = app.buttons["Abrir el mapa de la ruta"]
        esperar(open)
        open.tap()

        esperar(app.navigationBars["Trabajo → Casa"], 10)
        let toTrip = app.navigationBars.buttons["Trayecto"]
        esperar(toTrip)
        pausa(1)
        toTrip.tap()
        // Salta a la pestaña Trayecto, con la tarjeta del modo trayecto.
        esperar(identificado("trayecto.empezar"), 10)
    }

    /// La pestaña Trayecto: píldora de ruta, encuadrar, mi posición y la
    /// tarjeta con el tren que toca.
    @MainActor
    func testPestanaTrayecto() {
        arrancarTablero("cincoTramos")
        irA("Trayecto")
        esperar(identificado("trayecto.empezar"), 15)
        esperar(elementoQueEmpieza("Ruta: Casa → Trabajo"))
        esperar(app.buttons["Encuadrar la ruta"])
        esperar(app.buttons["Mi posición"])
        // El tren del primer tramo, como una frase (R50).
        esperar(elementoQueContiene("Línea 6424 a Pont de Bezons"))
        esperar(elementoQueContiene("tramo 1 de 5"))
        let center = app.buttons["Encuadrar la ruta"]
        center.tap()
        // Sigue todo en su sitio.
        esperar(identificado("trayecto.empezar"))
        // Volver al tablero: sigue ahí.
        irA("Tablero")
        esperar(identificado("tablero.tramo.0"))
    }
}
