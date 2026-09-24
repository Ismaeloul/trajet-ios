import XCTest

/// Capturas automáticas de TODAS las pantallas y estados importantes, en modo
/// demo. Cada captura se guarda como PNG en la carpeta de la variable de
/// entorno `TRAJET_CAPTURAS_DIR` (en xcodebuild: `TEST_RUNNER_TRAJET_CAPTURAS_DIR`)
/// con un nombre claro, y además como adjunto del resultado (`XCTAttachment`).
///
/// Las lanza `scripts/ci-capturas.sh` (modo `capturas` del CI) en iPhone SE,
/// iPhone 16 y iPhone 16 Pro Max, en claro y oscuro, y con letra grande. No
/// forman parte de los tests de interfaz normales (`ci-tests.sh` las salta).
///
/// Un paso que no encuentra lo que busca no para el recorrido: se apunta y
/// se sigue (`continueAfterFailure`).
final class CapturasUITests: TrajetUITestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Capturar

    /// Guarda la pantalla entera del simulador (con la barra de estado).
    @MainActor
    func capturar(_ nombre: String, tras espera: TimeInterval = 0.8) {
        pausa(espera)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = nombre
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["TRAJET_CAPTURAS_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        let file = folder.appendingPathComponent("\(nombre).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: file, options: .atomic)
        } catch {
            // Queda el adjunto; el script del CI lo saca del .xcresult.
            print("No se ha podido escribir \(file.path): \(error)")
        }
    }

    /// Espera a algo sin parar el recorrido; dice si estaba.
    @MainActor
    @discardableResult
    func ver(_ element: XCUIElement, _ segundos: TimeInterval = 10, _ que: String = "") -> Bool {
        let ok = element.waitForExistence(timeout: segundos)
        if !ok {
            XCTFail("No aparece \(que.isEmpty ? "\(element)" : que)")
        }
        return ok
    }

    /// Arranca un escenario emparejado y espera al tablero (sin parar si no llega).
    @MainActor
    func tablero(_ escenario: String, extra: [String] = []) {
        arrancar(escenario, extra: extra)
        ver(pestana("Tablero"), 15, "las pestañas (\(escenario))")
        pausa(1.2)
    }

    // MARK: - 0x Emparejar

    @MainActor
    func testCapturas0Emparejar() {
        arrancar("emparejar")
        ver(app.buttons["Escanear el QR"], 10, "la pantalla de emparejar")
        capturar("01-emparejar-inicio")

        // En el simulador no hay cámara: es el estado que se ve al tocar
        // «Escanear el QR» (el escáner de verdad se prueba en el iPhone).
        app.buttons["Escanear el QR"].tap()
        ver(app.staticTexts["No hay cámara"], 5, "«No hay cámara»")
        capturar("02-emparejar-sin-camara")

        let manual = app.buttons["Escribir a mano"]
        if ver(manual, 5, "«Escribir a mano»") {
            manual.tap()
        }
        let code = app.textFields["emparejar.codigo"]
        ver(code, 10, "la hoja de emparejar a mano")
        capturar("03-emparejar-a-mano")

        escribir(Self.demoCode, en: code)
        capturar("04-emparejar-a-mano-codigo", tras: 0.5)

        // El teclado tapa el botón: se recoge y se baja hasta él.
        cerrarTeclado()
        let send = identificado("emparejar.enviar")
        if ver(send, 5) {
            desplazarHasta(send)
            send.tap()
        }
        // «Listo» se ve 1,2 s antes de pasar a las pestañas.
        if aparece(elementoQueEmpieza("Listo."), 8) {
            capturar("05-emparejar-listo", tras: 0.1)
        }
        ver(identificado("tablero.tramo.0"), 20, "el tablero tras emparejar")
        capturar("06-tablero-recien-emparejado")
    }

    // MARK: - 1x El tablero con datos

    @MainActor
    func testCapturas1Tablero() {
        tablero("cincoTramos")
        ver(identificado("tablero.tramo.0"), 15)
        capturar("10-tablero-cinco-tramos")
        // El RER E con la vía recién publicada (late 25 s) y el metro cortado.
        desplazarHasta(identificado("tablero.tramo.2"))
        capturar("11-tablero-cinco-tramos-via-nueva-y-metro-cortado")
        desplazarHasta(identificado("tablero.tramo.4"))
        capturar("12-tablero-cinco-tramos-bus-perturbado")
        desplazarHasta(botonQueEmpieza("Buscar alternativa"))
        desplazar(0.3)
        capturar("13-tablero-cinco-tramos-pie")

        tablero("tranquilo")
        capturar("14-tablero-tranquilo-ruta-elegida")

        tablero("viaProbable")
        capturar("15-tablero-via-probable")

        tablero("unTramo")
        capturar("16-tablero-via-real-un-tramo")

        tablero("enAnden")
        capturar("17-tablero-en-anden")

        tablero("bus106")
        capturar("18-tablero-bus-1h46")

        tablero("lineaCortada")
        capturar("19-tablero-linea-cortada")
        desplazarHasta(botonQueEmpieza("Buscar alternativa"))
        capturar("20-tablero-linea-cortada-boton-rojo")

        tablero("destinosMezclados")
        capturar("21-tablero-destinos-mezclados")

        tablero("seisTramos")
        capturar("22-tablero-seis-tramos-compacto")
        desplazarHasta(identificado("tablero.tramo.3"))
        capturar("23-tablero-seis-tramos-compacto-abajo")

        tablero("viejo")
        capturar("24-tablero-dato-viejo-apagado")

        tablero("casosLimite")
        capturar("25-tablero-casos-limite")
        desplazarHasta(identificado("tablero.tramo.3"))
        capturar("26-tablero-casos-limite-estacion-caida")
        desplazarHasta(botonQueEmpieza("Buscar alternativa"))
        desplazar(0.3)
        capturar("27-tablero-casos-limite-pie-errores")

        tablero("cuotaJusta")
        capturar("28-tablero-cuota-justa-ahorrando")

        tablero("transbordo")
        capturar("29-tablero-transbordo")
    }

    // MARK: - 3x Estados sin datos y errores diseñados

    @MainActor
    func testCapturas3EstadosSinDatos() {
        tablero("sinConexion")
        ver(elementoQueEmpieza("Sin conexión."), 15, "la píldora sin conexión")
        capturar("30-tablero-sin-conexion-con-cache")
        tablero("sinConexion", extra: ["-demoSinCache"])
        ver(app.staticTexts["No se llega al servidor"], 15)
        capturar("31-tablero-sin-conexion-sin-cache")

        tablero("sinClave")
        ver(elementoQueContiene("clave de PRIM"), 15)
        capturar("32-tablero-sin-clave-con-cache")
        tablero("sinClave", extra: ["-demoSinCache"])
        ver(app.staticTexts["El servidor no tiene clave de PRIM"], 15)
        capturar("33-tablero-sin-clave-sin-cache")

        tablero("cuotaAgotada")
        ver(elementoQueContiene("cuota"), 15)
        capturar("34-tablero-cuota-agotada-con-cache")
        tablero("cuotaAgotada", extra: ["-demoSinCache"])
        ver(app.staticTexts["Se acabó la cuota de hoy"], 15)
        capturar("35-tablero-cuota-agotada-sin-cache")

        tablero("revocado")
        ver(elementoQueContiene("emparejado"), 15)
        capturar("36-tablero-revocado-con-cache")
        tablero("revocado", extra: ["-demoSinCache"])
        ver(app.staticTexts["Este iPhone no está emparejado"], 15)
        capturar("37-tablero-revocado-sin-cache")

        tablero("vacio")
        ver(app.staticTexts["Todavía no hay ninguna ruta"], 15)
        capturar("38-tablero-sin-rutas")
        irA("Trayecto")
        ver(app.staticTexts["Sin ruta que enseñar"], 10)
        capturar("39-trayecto-sin-ruta")
        irA("Rutas")
        ver(app.staticTexts["Aún no hay ninguna ruta"], 10)
        capturar("40-rutas-vacio")
    }

    // MARK: - 4x Detalle de tramo y alternativas

    @MainActor
    func testCapturas4DetalleYAlternativas() {
        tablero("viaProbable")
        abrirTramo(0)
        ver(app.navigationBars["Línea J"], 10, "el detalle de la J")
        capturar("41-detalle-via-probable-explicada")
        app.buttons["Cerrar"].tap()

        tablero("lineaCortada")
        abrirTramo(0)
        ver(app.navigationBars["Línea 14"], 10, "el detalle de la 14")
        capturar("42-detalle-linea-cortada-bilingue")
        app.buttons["Cerrar"].tap()

        tablero("cincoTramos")
        abrirTramo(3)
        ver(app.navigationBars["Línea 13"], 10, "el detalle de la 13")
        capturar("43-detalle-metro-cortado-traduciendo")
        app.buttons["Cerrar"].tap()
        pausa(0.8)
        abrirTramo(2)
        ver(app.navigationBars["Línea E"], 10, "el detalle del RER E")
        capturar("44-detalle-rer-e-via-real-y-probables")
        desplazar(0.4)
        capturar("45-detalle-rer-e-salidas")
        app.buttons["Cerrar"].tap()
        pausa(0.8)

        let alternatives = botonQueEmpieza("Buscar alternativa")
        desplazarHasta(alternatives)
        alternatives.tap()
        ver(app.navigationBars["Alternativas"], 10, "la hoja de alternativas")
        ver(elementoQueContiene("No sirve"), 10, "la opción que no sirve")
        capturar("46-alternativas-opciones-y-no-sirve")
        app.buttons["Cerrar"].tap()

        tablero("lineaCortada")
        let button = botonQueEmpieza("Buscar alternativa")
        desplazarHasta(button)
        button.tap()
        ver(app.staticTexts["El calculador no encuentra otro camino ahora mismo."], 10)
        capturar("47-alternativas-sin-opciones")
        let force = app.buttons["Buscar de todas formas"]
        if ver(force, 5) {
            force.tap()
            pausa(1)
            capturar("48-alternativas-buscar-de-todas-formas")
        }
    }

    // MARK: - 5x Mapa y modo trayecto

    @MainActor
    func testCapturas5MapaYTrayecto() {
        tablero("cincoTramos")
        let open = app.buttons["Abrir el mapa de la ruta"]
        if ver(open, 10, "el botón del mapa") {
            open.tap()
            ver(app.navigationBars["Casa → Trabajo"], 10, "el mapa entero")
            capturar("50-mapa-entero-desde-tablero", tras: 2.5)
            atras()
        }

        irA("Trayecto")
        ver(identificado("trayecto.empezar"), 15, "la tarjeta del trayecto")
        capturar("51-trayecto-mapa-y-tarjeta", tras: 2.5)
        identificado("trayecto.empezar").tap()
        ver(identificado("trayecto.parar"), 15, "el trayecto en marcha")
        capturar("52-trayecto-en-marcha", tras: 1.5)
        irA("Tablero")
        desplazarHasta(identificado("tablero.parar"))
        capturar("53-tablero-con-trayecto-en-marcha")
        irA("Trayecto")
        identificado("trayecto.parar").tap()
        ver(identificado("trayecto.empezar"), 10)
        capturar("54-trayecto-parado")

        // La J de Saint-Lazare a Argenteuil: el mapa con la vía en su andén.
        tablero("unTramo")
        irA("Trayecto")
        ver(identificado("trayecto.empezar"), 15)
        capturar("55-trayecto-mapa-j-argenteuil", tras: 2.5)

        // Sin permiso de ubicación: se explica antes, y sin GPS sigue igual.
        tablero("tranquilo", extra: ["-demoSinUbicacion"])
        irA("Trayecto")
        ver(identificado("trayecto.empezar"), 15)
        identificado("trayecto.empezar").tap()
        let alert = app.alerts["Ubicación durante el trayecto"]
        if ver(alert, 10, "la explicación de la ubicación") {
            capturar("56-trayecto-explicacion-ubicacion", tras: 0.5)
            alert.buttons["Sin ubicación"].tap()
        }
        ver(identificado("trayecto.parar"), 15)
        capturar("57-trayecto-sin-ubicacion")
        identificado("trayecto.parar").tap()
    }

    // MARK: - 6x Rutas, editor, tramo nuevo y planificador

    @MainActor
    func testCapturas6RutasYPlanificador() {
        tablero("cincoTramos")
        irA("Rutas")
        ver(app.navigationBars["Rutas"], 10, "la lista de rutas")
        ver(elementoQueEmpieza("Casa → Trabajo"), 10)
        capturar("60-rutas-lista")

        let order = app.buttons["Ordenar"]
        if aparece(order, 3) {
            order.tap()
            capturar("61-rutas-ordenar")
            let done = app.buttons["Hecho"]
            if aparece(done, 3) { done.tap() }
        }

        let first = elementoQueEmpieza("Casa → Trabajo")
        if ver(first, 5) {
            desplazarHasta(first)
            first.tap()
        }
        ver(app.navigationBars["Editar ruta"], 10, "el editor")
        capturar("62-ruta-editor")
        desplazar(0.5)
        capturar("63-ruta-editor-itinerario")
        desplazar(0.5)
        capturar("64-ruta-editor-final")
        atras()
        ver(app.navigationBars["Rutas"], 10)

        // Nueva ruta a mano y montar un tramo en tres pasos.
        let plus = elemento("Nueva ruta")
        if ver(plus, 5, "el «+» de rutas") {
            plus.tap()
            capturar("65-rutas-menu-nueva", tras: 0.5)
            let manual = elemento("Montar a mano")
            if ver(manual, 5) { manual.tap() }
        }
        ver(app.navigationBars["Nueva ruta"], 10, "la ruta nueva")
        capturar("66-ruta-nueva")
        // En el SE queda fuera de pantalla: se baja hasta él antes de buscarlo.
        let addLeg = app.buttons["Añadir el primer tramo"]
        desplazarHasta(addLeg)
        if ver(addLeg, 5) {
            addLeg.tap()
            ver(app.navigationBars["¿Desde qué parada?"], 10, "el paso de la parada")
            capturar("67-tramo-parada")
            // El campo de la hoja, no el del editor que hay detrás.
            let field = identificado("buscar.campo")
            if ver(field, 5) {
                escribir("Saint", en: field)
                let stop = elementoQueEmpieza("Gare Saint-Lazare")
                ver(stop, 10, "los resultados de paradas")
                capturar("68-tramo-parada-resultados")
                if stop.exists { stop.tap() }
                ver(app.staticTexts["¿Qué línea coges?"], 10, "el paso de la línea")
                capturar("69-tramo-linea")
                let lineJ = elementoQueEmpieza("J, Línea J")
                let anyJ = lineJ.exists ? lineJ : elementoQueContiene("Línea J")
                if ver(anyJ, 5, "la línea J") { anyJ.tap() }
                ver(app.buttons["Añadir el tramo"], 10, "el paso del sentido")
                capturar("70-tramo-sentido")
                let direction = elemento("Dirección Ermont - Eaubonne")
                if aparece(direction, 5) { direction.tap() }
                capturar("71-tramo-sentido-elegido", tras: 0.4)
                app.buttons["Añadir el tramo"].tap()
            }
            ver(app.navigationBars["Nueva ruta"], 10)
            capturar("72-ruta-nueva-con-tramo")
            let cancel = app.buttons["Cancelar"]
            if aparece(cancel, 3) {
                cancel.tap()
                let discard = app.buttons["Descartar"]
                if aparece(discard, 3) {
                    capturar("73-ruta-nueva-descartar", tras: 0.3)
                    discard.tap()
                }
            }
        }
        ver(app.navigationBars["Rutas"], 10)

        // El planificador de principio a fin. El botón está al final de la
        // lista de rutas (fuera de pantalla en el SE).
        let search = app.buttons["Buscar un trayecto"]
        desplazarHasta(search)
        if ver(search, 5, "«Buscar un trayecto»") {
            search.tap()
        }
        ver(app.navigationBars["Buscar trayecto"], 10, "el planificador")
        capturar("74-planificador")
        let from = elemento("Desde: sin elegir")
        if ver(from, 5) {
            from.tap()
            ver(app.navigationBars["¿Desde dónde?"], 10)
            capturar("75-planificador-buscar-sitio")
            let field = identificado("buscar.campo")
            if ver(field, 5) {
                escribir("Saint", en: field)
                let place = elementoQueEmpieza("Gare Saint-Lazare")
                ver(place, 10, "los resultados de sitios")
                capturar("76-planificador-buscar-sitio-resultados")
                if place.exists { place.tap() }
            }
        }
        let to = elemento("Hasta: sin elegir")
        if ver(to, 5) {
            to.tap()
            ver(app.navigationBars["¿Hasta dónde?"], 10)
            let field = identificado("buscar.campo")
            if ver(field, 5) {
                escribir("Paris", en: field)
                let place = elementoQueEmpieza("12 Rue de Paris")
                if ver(place, 10) { place.tap() }
            }
        }
        capturar("77-planificador-relleno")
        let go = app.buttons["Buscar itinerarios"]
        if ver(go, 5), go.isEnabled {
            go.tap()
            ver(app.buttons["Guardar ruta"].firstMatch, 15, "los itinerarios")
            capturar("78-planificador-resultados")
            desplazar(0.5)
            capturar("79-planificador-resultados-abajo")
            let save = app.buttons["Guardar ruta"].firstMatch
            if desplazarHasta(save) {
                save.tap()
                ver(app.navigationBars["Guardar ruta"], 10, "guardar desde el planificador")
                capturar("80-guardar-ruta")
                let confirm = app.navigationBars.buttons["Guardar"]
                if ver(confirm, 5) {
                    confirm.tap()
                    ver(app.staticTexts["Guardada, pero con un aviso"], 10, "el aviso de tramo sin sentido (R33)")
                    capturar("81-guardar-ruta-aviso-sin-sentido")
                    let done = app.buttons["Hecho"]
                    if aparece(done, 3) { done.tap() }
                }
            }
        }
    }

    // MARK: - 8x Historial y Ajustes

    @MainActor
    func testCapturas8HistorialYAjustes() {
        tablero("cincoTramos")
        irA("Historial")
        ver(app.staticTexts["Últimos 90 días"], 15, "el historial")
        capturar("82-historial", tras: 1.5)
        desplazar(0.5)
        capturar("83-historial-linea-que-falla")
        desplazarHasta(app.staticTexts["Previsión de vía"])
        desplazar(0.3)
        capturar("84-historial-prevision-de-via")

        irA("Tablero")
        let gear = app.buttons["Ajustes"]
        if ver(gear, 10, "el botón de Ajustes") { gear.tap() }
        ver(app.navigationBars["Ajustes"], 10, "Ajustes")
        ver(app.staticTexts["Servidor"], 10, "la sección del servidor")
        capturar("85-ajustes-servidor")
        desplazar(0.55)
        capturar("86-ajustes-estado-y-cuota")
        desplazar(0.55)
        capturar("87-ajustes-recolector-y-tablero")
        desplazar(0.55)
        capturar("88-ajustes-trayecto-y-permisos")
        desplazar(0.55)
        capturar("89-ajustes-widgets-y-version")
        desplazar(0.55)
        capturar("90-ajustes-final")
        app.buttons["Cerrar"].tap()

        // Con el servidor sin clave, Ajustes lo dice y el tablero también.
        tablero("sinClave")
        let gear2 = app.buttons["Ajustes"]
        if ver(gear2, 10) { gear2.tap() }
        ver(app.navigationBars["Ajustes"], 10)
        ver(app.staticTexts["Servidor"], 10)
        capturar("91-ajustes-servidor-sin-clave")
        // El estado del servidor está más abajo (la lista solo tiene lo que se ve).
        desplazarHasta(elementoQueContiene("sin clave"))
        ver(elementoQueContiene("sin clave"), 10, "el estado «sin clave»")
        capturar("92-ajustes-servidor-sin-clave-estado")
        app.buttons["Cerrar"].tap()

        // Emparejar de nuevo desde Ajustes: la pantalla de emparejar con «Cancelar».
        tablero("cincoTramos")
        let gear3 = app.buttons["Ajustes"]
        if ver(gear3, 10) { gear3.tap() }
        ver(app.navigationBars["Ajustes"], 10)
        let repair = app.buttons["Emparejar de nuevo"]
        desplazarHasta(repair)
        if ver(repair, 10, "«Emparejar de nuevo»") {
            repair.tap()
            ver(app.buttons["Escanear el QR"], 10)
            capturar("93-ajustes-emparejar-de-nuevo")
            let cancel = app.buttons["Cancelar"]
            if aparece(cancel, 3) { cancel.tap() }
        }
    }
}
