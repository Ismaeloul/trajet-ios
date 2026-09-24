import XCTest
@testable import Trajet

/// La lógica de la pantalla de emparejar (Views/Pairing/PairingViewLogic.swift):
/// qué hacer con un QR leído, el formulario a mano, el estado de la pantalla
/// y los textos de cada fallo (sistema.md §7.17, docs/arquitectura.md §4).
final class PairingViewLogicTests: XCTestCase {

    // MARK: - QR leído

    func testQRDelPanelEmpareja() throws {
        let decision = PairingScanDecision.decide(PreviewData.pairingLink)
        let url = try XCTUnwrap(URL(string: PreviewData.pairingLink))
        XCTAssertEqual(decision, .pair(url))
        XCTAssertNil(decision.hint)
        // Con espacios alrededor (algunos lectores los dejan).
        XCTAssertEqual(PairingScanDecision.decide("  \(PreviewData.pairingLink)\n"), .pair(url))
    }

    func testQRQueNoEsDeTrajetNoParaDeBuscar() {
        XCTAssertEqual(PairingScanDecision.decide("https://www.ratp.fr"), .notTrajet)
        XCTAssertEqual(PairingScanDecision.decide("Hola"), .notTrajet)
        XCTAssertEqual(PairingScanDecision.decide(""), .notTrajet)
        XCTAssertEqual(PairingScanDecision.decide("trajet://ruta/5"), .otherTrajetLink)
        XCTAssertEqual(PairingScanDecision.decide("trajet://tablero"), .otherTrajetLink)
        XCTAssertNotNil(PairingScanDecision.notTrajet.hint)
        XCTAssertNotNil(PairingScanDecision.otherTrajetLink.hint)
    }

    // MARK: - Código a mano

    func testCodigoAManoComoLoEscribeUnaPersona() {
        XCTAssertEqual(ManualPairingInput(code: "abcd efgh").normalizedCode, "ABCDEFGH")
        XCTAssertEqual(ManualPairingInput(code: "ABCD-EFGH").normalizedCode, "ABCD-EFGH")
        XCTAssertEqual(ManualPairingInput(code: " demo-2026 ").normalizedCode, "DEMO-2026")
        XCTAssertNil(ManualPairingInput(code: "ABC").normalizedCode)
        XCTAssertNil(ManualPairingInput(code: "ABCD-EFG!").normalizedCode)
        // Sin escribir nada no se riñe; con algo que no vale, sí.
        XCTAssertNil(ManualPairingInput(code: "").codeProblem)
        XCTAssertNil(ManualPairingInput(code: "ABCD-EFGH").codeProblem)
        XCTAssertEqual(ManualPairingInput(code: "AB").codeProblem, PairingLinkError.badCode.errorDescription)
    }

    func testDireccionesAMano() {
        var input = ManualPairingInput(code: "ABCD-EFGH", lan: "192.168.1.10:7796/", tailscale: "")
        XCTAssertEqual(input.lanURL, "http://192.168.1.10:7796")
        XCTAssertNil(input.tailscaleURL)
        XCTAssertEqual(input.typedAddresses, ["http://192.168.1.10:7796"])
        XCTAssertTrue(input.canSubmit(hasSavedAddresses: false))

        // Sin direcciones: vale si ya hay alguna guardada.
        input.lan = ""
        XCTAssertFalse(input.canSubmit(hasSavedAddresses: false))
        XCTAssertTrue(input.canSubmit(hasSavedAddresses: true))

        // Una escrita que no se entiende bloquea.
        input.tailscale = "ftp://casa"
        XCTAssertFalse(input.canSubmit(hasSavedAddresses: true))
        XCTAssertNotNil(input.tailscaleProblem)

        // Tailscale por IP y MagicDNS valen (ATS), una pública por HTTP no.
        input.tailscale = "http://100.64.0.10:7796"
        XCTAssertNil(input.tailscaleProblem)
        input.tailscale = "mi-umbrel.tail1234.ts.net:7796"
        XCTAssertNil(input.tailscaleProblem)
        input.lan = "http://trajet.example.com:7796"
        XCTAssertEqual(input.lanProblem, ServerAddressRules.note(.needsHTTPS))

        // Código malo: nunca.
        input = ManualPairingInput(code: "X", lan: "192.168.1.10:7796")
        XCTAssertFalse(input.canSubmit(hasSavedAddresses: true))
    }

    // MARK: - Estado de la pantalla

    func testEstadosDeLaPantalla() {
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: false, camera: .notDetermined, didPair: false), .intro)
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: true, camera: .authorized, didPair: false), .scanning)
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: true, camera: .denied, didPair: false), .cameraDenied)
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: true, camera: .restricted, didPair: false), .cameraDenied)
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: true, camera: .unavailable, didPair: false),
                       .cameraUnavailable)
        // Conectando manda sobre la cámara: también con el enlace de la cámara del sistema.
        XCTAssertEqual(PairingStage.make(phase: .checking, wantsCamera: false, camera: .notDetermined, didPair: false),
                       .connecting)
        XCTAssertEqual(PairingStage.make(phase: .pairing, wantsCamera: true, camera: .authorized, didPair: false),
                       .connecting)
        XCTAssertEqual(PairingStage.make(phase: .failed(.codeRejected), wantsCamera: true, camera: .authorized,
                                         didPair: false), .failed(.codeRejected))
        XCTAssertEqual(PairingStage.make(phase: .idle, wantsCamera: false, camera: .authorized, didPair: true), .paired)

        XCTAssertTrue(PairingStage.connecting.frameFound)
        XCTAssertFalse(PairingStage.scanning.frameFound)
        XCTAssertTrue(PairingStage.scanning.showsCamera)
        XCTAssertFalse(PairingStage.intro.showsCamera)
        XCTAssertTrue(CameraPermission.notDetermined.canScan)
        XCTAssertFalse(CameraPermission.denied.canScan)
    }

    // MARK: - Textos de los fallos (A28: diseñados)

    func testR86CodigoQueNoValeNoDistingueCaducadoNiUsado() {
        let copy = PairingText.failure(.codeRejected, addresses: [])
        XCTAssertEqual(copy.title, "Ese código ya no vale")
        XCTAssertTrue(copy.message.contains("5 minutos"))
        XCTAssertEqual(copy.actions.first, .scanAgain)
    }

    func testDemasiadosIntentosDiceCuantoEsperar() {
        XCTAssertEqual(PairingText.failure(.rateLimited(retryAfter: 45), addresses: []).message, "Prueba dentro de 45 s.")
        XCTAssertEqual(PairingText.failure(.rateLimited(retryAfter: 300), addresses: []).message, "Prueba dentro de 5 min.")
        XCTAssertEqual(PairingText.failure(.rateLimited(retryAfter: 61), addresses: []).message, "Prueba dentro de 2 min.")
        XCTAssertEqual(PairingText.failure(.rateLimited(retryAfter: nil), addresses: []).message,
                       "Espera un poco y vuelve a probar.")
    }

    func testR45ServidorQueNoAparecePistaDeRed() {
        let local = PairingText.failure(.unreachable("No se llega al servidor."),
                                        addresses: ["http://192.168.1.10:7796"])
        XCTAssertEqual(local.title, "No encuentro el servidor")
        XCTAssertEqual(local.hint?.contains("Red local"), true)
        XCTAssertEqual(local.actions, [.scanAgain, .typeManually])

        let both = PairingText.failure(.unreachable(""),
                                       addresses: ["http://192.168.1.10:7796", "http://100.64.0.10:7796"])
        XCTAssertEqual(both.message, "No responde en ninguna de sus direcciones.")
        XCTAssertEqual(both.hint?.contains("Tailscale"), true)

        // ATS: una dirección que no es de casa ni de Tailscale por HTTP.
        let ats = PairingText.failure(.unreachable("No se llega al servidor (iOS no deja usar esa dirección sin HTTPS)."),
                                      addresses: ["http://trajet.example.com:7796"])
        XCTAssertEqual(ats.hint?.contains("HTTPS"), true)
    }

    func testOtrosFallos() {
        XCTAssertEqual(PairingText.failure(.notTrajet, addresses: []).title, "Ahí no hay un Trajet")
        XCTAssertEqual(PairingText.failure(.invalidLink(.badCode), addresses: []).message,
                       PairingLinkError.badCode.errorDescription)
        XCTAssertEqual(PairingText.failure(.keychain, addresses: []).title, "No se ha podido guardar la llave")
        XCTAssertEqual(PairingText.failure(.server("Error interno."), addresses: []).message, "Error interno.")
        XCTAssertEqual(PairingText.cameraDenied.actions, [.openSettings, .typeManually])
        XCTAssertEqual(PairingText.cameraUnavailable.actions, [.typeManually])
        XCTAssertEqual(PairingText.actionTitle(.openSettings), "Abrir Ajustes")
    }

    func testTextosDeProgreso() {
        XCTAssertEqual(PairingText.connecting(serverName: "Trajet de casa"), "Conectando con «Trajet de casa»…")
        XCTAssertEqual(PairingText.connecting(serverName: nil), "Conectando con el servidor…")
        XCTAssertEqual(PairingText.paired(deviceName: "iPhone de Isma"), "Listo. iPhone de Isma emparejado.")
        XCTAssertEqual(PairingText.paired(deviceName: ""), "Listo. Este iPhone ya está emparejado.")
    }

    // MARK: - Con el emparejamiento de verdad (servidor falso)

    /// El código escrito a mano con `ManualPairingInput` llega tal cual al
    /// servidor y deja el iPhone emparejado; uno que no vale se dice.
    @MainActor
    func testEmparejarAManoContraElServidorFalso() async throws {
        MockURLProtocol.registry.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/ping") { return MockReply.json(PreviewData.pingJSON) }
            if path.hasSuffix("/pair") { return MockReply.json(PreviewData.pairResultJSON()) }
            return MockReply.json("{}", status: 404)
        }
        defer { MockURLProtocol.registry.reset(nil) }
        let (api, config) = makeMockAPI(token: nil, lan: "", tailscale: "")
        let store = PairingStore(api: api, config: config, tokens: .memory(nil))
        let input = ManualPairingInput(code: "abcd efgh", lan: "casa.test:7796")
        XCTAssertTrue(input.canSubmit(hasSavedAddresses: config.hasAddresses))
        let ok = await store.pair(code: input.code, lanURL: input.lanURL, tailscaleURL: input.tailscaleURL)
        XCTAssertTrue(ok)
        XCTAssertTrue(store.isPaired)
        XCTAssertEqual(PairingStage.make(phase: store.phase, wantsCamera: false, camera: .unavailable, didPair: ok),
                       .paired)

        MockURLProtocol.registry.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/ping") { return MockReply.json(PreviewData.pingJSON) }
            return MockReply.error(.codigoNoValido)
        }
        let (api2, config2) = makeMockAPI(token: nil, lan: "", tailscale: "")
        let store2 = PairingStore(api: api2, config: config2, tokens: .memory(nil))
        let failed = await store2.pair(code: "ABCD-EFGH", lanURL: "http://casa.test:7796", tailscaleURL: nil)
        XCTAssertFalse(failed)
        let failure = try XCTUnwrap(store2.failure)
        XCTAssertEqual(PairingText.failure(failure, addresses: ["http://casa.test:7796"]).title, "Ese código ya no vale")
    }
}
