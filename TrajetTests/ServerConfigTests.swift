import XCTest
@testable import Trajet

/// Direcciones del servidor: se guardan al escribir y «Restablecer» olvida la
/// preferida (R61); orden de prueba (R42).
final class ServerConfigTests: XCTestCase {

    @MainActor
    func testPersisteAlEscribir() {
        let defaults = makeTestDefaults()
        let config = ServerConfig(defaults: defaults)
        config.lanURL = "http://casa.test:7796"
        config.tailscaleURL = "http://ts.test:7796"
        config.serverName = "Casa"
        // Sin botón de guardar: ya está en disco.
        XCTAssertEqual(defaults.string(forKey: ServerConfig.Key.lan), "http://casa.test:7796")
        XCTAssertEqual(defaults.string(forKey: ServerConfig.Key.tailscale), "http://ts.test:7796")
        let again = ServerConfig(defaults: defaults)
        XCTAssertEqual(again.lanURL, "http://casa.test:7796")
        XCTAssertEqual(again.tailscaleURL, "http://ts.test:7796")
        XCTAssertEqual(again.serverName, "Casa")
    }

    @MainActor
    func testRestablecer() {
        let defaults = makeTestDefaults()
        let config = ServerConfig(defaults: defaults)
        config.applyPairing(lan: "http://casa.test:7796/", tailscale: "ts.test:7796", name: "Casa",
                            reachable: "http://ts.test:7796")
        XCTAssertEqual(config.lanURL, "http://casa.test:7796")
        XCTAssertEqual(config.tailscaleURL, "http://ts.test:7796")
        XCTAssertEqual(config.preferredURL, "http://ts.test:7796")

        config.lanURL = "http://otra.test:1"
        config.reset()
        XCTAssertEqual(config.lanURL, "http://casa.test:7796")
        XCTAssertEqual(config.tailscaleURL, "http://ts.test:7796")
        XCTAssertNil(config.preferredURL)
        let again = ServerConfig(defaults: defaults)
        XCTAssertNil(again.preferredURL)
        XCTAssertEqual(again.lanURL, "http://casa.test:7796")

        config.clearAll()
        XCTAssertEqual(config.lanURL, "")
        XCTAssertFalse(config.hasAddresses)
        XCTAssertNil(ServerConfig(defaults: defaults).pairedLAN)
    }

    /// R42: la preferida primero, luego casa y Tailscale; sin vacías ni
    /// repetidas.
    @MainActor
    func testOrdenDeCandidatos() {
        let config = ServerConfig(defaults: makeTestDefaults())
        XCTAssertEqual(config.candidates, [])
        config.lanURL = " casa.test:7796 "
        config.tailscaleURL = ""
        XCTAssertEqual(config.candidates, ["http://casa.test:7796"])
        config.tailscaleURL = "http://ts.test:7796"
        XCTAssertEqual(config.candidates, ["http://casa.test:7796", "http://ts.test:7796"])
        config.remember("http://ts.test:7796")
        XCTAssertEqual(config.candidates, ["http://ts.test:7796", "http://casa.test:7796"])
        XCTAssertEqual(config.label(for: "http://ts.test:7796"), "Tailscale")
        XCTAssertEqual(config.label(for: "http://casa.test:7796"), "red de casa")
        XCTAssertEqual(config.connectedVia, "Tailscale")
    }

    /// Cambiar la dirección que era la preferida la olvida: si no, la vieja
    /// se seguiría probando la primera.
    @MainActor
    func testEditarOlvidaLaPreferida() {
        let config = ServerConfig(defaults: makeTestDefaults())
        config.lanURL = "http://casa.test:7796"
        config.tailscaleURL = "http://ts.test:7796"
        config.remember("http://ts.test:7796")
        config.lanURL = "http://casa2.test:7796"          // no era la preferida
        XCTAssertEqual(config.preferredURL, "http://ts.test:7796")
        config.tailscaleURL = "http://ts2.test:7796"      // sí lo era
        XCTAssertNil(config.preferredURL)
        XCTAssertEqual(config.candidates, ["http://casa2.test:7796", "http://ts2.test:7796"])
    }

    func testNormalizar() {
        XCTAssertEqual(ServerConfig.normalize("192.168.1.10:7796/"), "http://192.168.1.10:7796")
        XCTAssertEqual(ServerConfig.normalize("https://mi.ts.net"), "https://mi.ts.net")
        XCTAssertNil(ServerConfig.normalize("   "))
        XCTAssertNil(ServerConfig.normalize("ftp://casa"))
    }
}
