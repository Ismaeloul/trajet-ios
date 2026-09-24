import XCTest

/// Base de los tests de interfaz. Arranca la app en modo demo (el servidor
/// falso vive dentro del proceso: nada de red), en español y sin animaciones,
/// y da las ayudas para esperar, buscar por etiqueta y moverse por las
/// pestañas.
///
/// Los escenarios son los de `DemoServer`: cualquier `PreviewData.BoardCase`
/// (`cincoTramos`, `viaProbable`, `lineaCortada`, `bus106`…) o `emparejar`,
/// `vacio`, `sinConexion`, `sinClave`, `cuotaAgotada` y `revocado`. Argumentos
/// sueltos: `-demoSinCache` y `-demoSinUbicacion`.
class TrajetUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// El código de emparejamiento que acepta la demo.
    static let demoCode = "DEMO-2026"

    // MARK: - Arrancar

    /// Arranca la app con un escenario de la demo.
    @MainActor
    @discardableResult
    func arrancar(_ escenario: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoEscenario", escenario, "-sinAnimaciones",
                               "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        // Permisos del sistema (ubicación, red local): en la demo no salen,
        // pero si salieran se aceptan para que el flujo siga.
        addUIInterruptionMonitor(withDescription: "Permisos del sistema") { alert in
            let titles = ["Permitir mientras se usa la app", "Permitir una vez", "Permitir",
                          "Allow While Using App", "Allow Once", "Allow", "OK"]
            for title in titles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
        self.app = app
        return app
    }

    /// Arranca un escenario emparejado y espera a que el tablero esté delante.
    @MainActor
    @discardableResult
    func arrancarTablero(_ escenario: String = "cincoTramos", extra: [String] = []) -> XCUIApplication {
        let app = arrancar(escenario, extra: extra)
        esperar(pestana("Tablero"), 15)
        return app
    }

    // MARK: - Buscar

    /// Cualquier elemento (del tipo que sea) con esa etiqueta exacta.
    @MainActor
    func elemento(_ etiqueta: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", etiqueta)).firstMatch
    }

    /// Cualquier elemento cuya etiqueta empiece por ese texto.
    @MainActor
    func elementoQueEmpieza(_ prefijo: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefijo)).firstMatch
    }

    /// Cualquier elemento cuya etiqueta contenga ese trozo.
    @MainActor
    func elementoQueContiene(_ trozo: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", trozo)).firstMatch
    }

    /// Un botón cuya etiqueta empiece por ese texto («Buscar alternativa…»).
    @MainActor
    func botonQueEmpieza(_ prefijo: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefijo)).firstMatch
    }

    /// Un elemento por su `accessibilityIdentifier`.
    @MainActor
    func identificado(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Una pestaña de la barra del sistema.
    @MainActor
    func pestana(_ nombre: String) -> XCUIElement {
        let tab = app.tabBars.buttons[nombre]
        return tab.exists ? tab : app.buttons[nombre]
    }

    // MARK: - Esperar y actuar

    /// Espera a que exista. Falla el test si no aparece.
    @MainActor
    @discardableResult
    func esperar(_ element: XCUIElement, _ segundos: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = element.waitForExistence(timeout: segundos)
        XCTAssertTrue(ok, "No aparece: \(element)", file: file, line: line)
        return ok
    }

    /// Espera a que exista, sin fallar (para pasos opcionales).
    @MainActor
    func aparece(_ element: XCUIElement, _ segundos: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: segundos)
    }

    /// Espera a que deje de existir.
    @MainActor
    @discardableResult
    func esperarQueDesaparezca(_ element: XCUIElement, _ segundos: TimeInterval = 10,
                               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let fin = Date().addingTimeInterval(segundos)
        while element.exists, Date() < fin {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(element.exists, "Sigue ahí: \(element)", file: file, line: line)
        return !element.exists
    }

    /// Cambia de pestaña.
    @MainActor
    func irA(_ pestanaNombre: String) {
        let tab = pestana(pestanaNombre)
        esperar(tab)
        tab.tap()
    }

    /// Un respiro para que la pantalla se asiente (mapas, hojas).
    func pausa(_ segundos: TimeInterval = 0.6) {
        Thread.sleep(forTimeInterval: segundos)
    }

    /// El `ScrollView` más grande que hay a la vista (el de la pantalla, no
    /// la tira horizontal de fichas).
    @MainActor
    func scrollPrincipal() -> XCUIElement {
        var best: XCUIElement?
        var bestArea: CGFloat = 0
        for candidate in app.scrollViews.allElementsBoundByIndex where candidate.exists {
            let frame = candidate.frame
            let area = frame.width * frame.height
            if area > bestArea {
                bestArea = area
                best = candidate
            }
        }
        return best ?? app
    }

    /// Desplaza la pantalla hacia arriba (para ver lo de abajo), un tramo
    /// controlado en vez de un manotazo.
    @MainActor
    func desplazar(_ fraccion: CGFloat = 0.45) {
        arrastrar(desde: 0.72, hasta: max(0.08, 0.72 - fraccion))
    }

    /// Desplaza hacia abajo (para volver a ver lo de arriba).
    @MainActor
    func desplazarAbajo(_ fraccion: CGFloat = 0.45) {
        arrastrar(desde: 0.35, hasta: min(0.9, 0.35 + fraccion))
    }

    @MainActor
    private func arrastrar(desde: CGFloat, hasta: CGFloat) {
        let scroll = scrollPrincipal()
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: desde))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: hasta))
        start.press(forDuration: 0.05, thenDragTo: end)
        pausa(0.4)
    }

    /// Desplaza hasta que el elemento quede en la franja central de la
    /// pantalla (fuera de la cabecera flotante y de la barra de pestañas), de
    /// modo que se pueda tocar sin dar en otra cosa.
    @MainActor
    @discardableResult
    func desplazarHasta(_ element: XCUIElement, intentos: Int = 10) -> Bool {
        let height = app.frame.height
        let top = height * 0.18
        let bottom = height * 0.8
        for _ in 0..<intentos {
            guard element.exists else {
                desplazar()
                continue
            }
            let frame = element.frame
            // Lo que interesa tocar: el centro, o el tercio de arriba si es alto.
            let y = frame.height > (bottom - top) ? frame.minY + 60 : frame.midY
            if y >= top, y <= bottom { return true }
            if y > bottom {
                desplazar(0.35)
            } else {
                desplazarAbajo(0.35)
            }
        }
        return element.exists && element.isHittable
    }

    /// Toca un elemento por su tercio de arriba (por si es más alto que la
    /// franja visible).
    @MainActor
    func tocarArriba(_ element: XCUIElement) {
        let frame = element.frame
        let dy: CGFloat = frame.height > 200 ? min(0.3, 60 / max(frame.height, 1)) : 0.5
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
    }

    /// Toca el detalle de un tramo del tablero («tablero.tramo.N»).
    @MainActor
    func abrirTramo(_ seq: Int) {
        let card = identificado("tablero.tramo.\(seq)")
        esperar(card)
        XCTAssertTrue(desplazarHasta(card), "El tramo \(seq) no se puede tocar")
        tocarArriba(card)
    }

    /// Escribe en un campo (lo toca antes para que tenga el foco).
    @MainActor
    func escribir(_ texto: String, en campo: XCUIElement) {
        esperar(campo)
        campo.tap()
        pausa(0.3)
        campo.typeText(texto)
    }

    /// Recoge el teclado si está a la vista. Los formularios de SwiftUI lo
    /// recogen al desplazarse: un arrastre corto hacia ARRIBA sobre el
    /// contenido, por encima del teclado (hacia abajo no: en una hoja la
    /// cerraría). Con el teclado puesto, un botón del final del formulario
    /// queda debajo y tocarlo no hace nada.
    @MainActor
    func cerrarTeclado() {
        // El aviso «desliza para escribir» del simulador, si saliera (el CI
        // lo apaga en scripts/ci-sim.sh).
        let skip = app.buttons["Continue"]
        if skip.exists {
            skip.tap()
        }
        guard app.keyboards.count > 0 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        pausa(0.5)
    }

    /// El botón de atrás de la barra de navegación.
    @MainActor
    func atras() {
        let bar = app.navigationBars.firstMatch
        esperar(bar)
        bar.buttons.element(boundBy: 0).tap()
    }
}
