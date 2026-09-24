import XCTest
@testable import Trajet

/// La lógica del Historial (Views/Stats/StatsLogic.swift). Cada test lleva en
/// el nombre las reglas que cubre (docs/reglas.md).
final class StatsLogicTests: XCTestCase {

    private var stats: StatsResponse { PreviewData.stats }
    private var routes: [SavedRoute] { PreviewData.routes }

    // MARK: - R11 · el acierto SOLO de /api/v1/platform-model

    func testR11AciertoSoloDePlatformModel() throws {
        let model = PreviewData.platformModel
        let route = try XCTUnwrap(routes.first { $0.id == model.routeId })
        let summary = StatsText.accuracy(model, route: route, routes: routes)
        XCTAssertEqual(summary.percent, "84\u{202F}%")
        XCTAssertEqual(summary.hitsText, "179 aciertos de 214")
        XCTAssertEqual(summary.basisText, "4820 trenes en 26 días · el servidor se puntúa solo")
        XCTAssertNil(summary.waitingText)
        XCTAssertEqual(summary.coverageTitle, "Cobertura en Casa → Trabajo")
        XCTAssertTrue(summary.spoken.contains("84 por ciento"))

        // La única entrada es la respuesta de /platform-model: sin `rate`, «—».
        let noData = PreviewData.decode(PreviewData.platformModelNoDataJSON, as: PlatformModelResponse.self)
        let waiting = StatsText.accuracy(noData, route: nil)
        XCTAssertEqual(waiting.percent, "—")
        XCTAssertNil(waiting.hitsText)
        XCTAssertEqual(waiting.waitingText, StatsText.waiting)
        XCTAssertTrue(waiting.coverage.isEmpty)
        XCTAssertNil(waiting.coverageTitle)
        XCTAssertTrue(waiting.spoken.contains("aún sin datos"))

        // Redondeo del porcentaje.
        let half = PreviewData.decode(#"{"accuracy": {"predictions": 3, "hits": 2, "rate": 0.666}}"#,
                                      as: PlatformModelResponse.self)
        XCTAssertEqual(StatsText.percent(half.accuracy), "67\u{202F}%")
    }

    @MainActor
    func testR11UnFalloDeLaPrevisionSeCallaYNoBorraNada() async {
        let model = StatsModel()
        let stats = self.stats
        let platform = PreviewData.platformModel
        await model.load(stats: { stats }, platformModel: { platform })
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.platformModel?.accuracy.rate, 0.84)

        // Recarga en la que falla la previsión: se queda la de antes.
        await model.load(stats: { stats }, platformModel: { throw APIError.network("sin red") })
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.platformModel?.accuracy.rate, 0.84)
        XCTAssertNil(model.refreshError)

        // Falla todo con datos en pantalla: se quedan y se dice (R9).
        await model.load(stats: { throw APIError.network("No se llega al servidor.") },
                         platformModel: { throw APIError.network("sin red") })
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertNotNil(model.stats)
        XCTAssertEqual(model.refreshError, "No se llega al servidor.")
    }

    @MainActor
    func testFalloSinNadaQueEnsenarSeDice() async {
        let model = StatsModel()
        XCTAssertEqual(model.phase, .loading)
        await model.load(stats: { throw APIError.network("No se llega al servidor.") },
                         platformModel: { PreviewData.platformModel })
        XCTAssertEqual(model.phase, .failed("No se llega al servidor."))
        XCTAssertNil(model.stats)
    }

    func testR3CoberturaPorTramo() throws {
        let model = PreviewData.platformModel
        let route = try XCTUnwrap(routes.first { $0.id == 3 })
        let rows = StatsText.accuracy(model, route: route, routes: routes).coverage
        XCTAssertEqual(rows.map(\.code), ["6424", "E", "13"])
        // Bus y metro no publican vía (R3).
        XCTAssertEqual(rows[0].text, "esta línea no publica vía")
        XCTAssertFalse(rows[0].publishesPlatform)
        XCTAssertEqual(rows[1].text, "3120 trenes vistos · 26 días · 4 vías")
        XCTAssertTrue(rows[1].publishesPlatform)
        XCTAssertEqual(rows[1].color, "B94E9A")
        XCTAssertEqual(rows[2].text, "esta línea no publica vía")
    }

    // MARK: - R56 · formatos en español

    func testR56DecimalesConComa() {
        XCTAssertEqual(StatsText.decimal(3.42), "3,4")
        XCTAssertEqual(StatsText.decimal(27.0), "27")
        XCTAssertEqual(StatsText.decimal(4.6), "4,6")
        XCTAssertEqual(StatsText.minutes(3.42), "3,4 min")
        XCTAssertEqual(StatsText.minutes(nil), "—")
    }

    func testR56ResumenConLoQueDicenLosDatos() {
        let tiles = StatsText.tiles(stats.overall)
        XCTAssertEqual(tiles.map(\.value), ["128", "3,4", "27"])
        XCTAssertEqual(tiles.map(\.caption), ["consultas", "retraso medio", "retraso máximo"])
        XCTAssertEqual(tiles.map(\.unit), [nil, "min", "min"])
        XCTAssertEqual(tiles[1].spoken, "retraso medio, 3,4 minutos")

        let empty = StatsText.tiles(PreviewData.decode("{}", as: OverallStat.self))
        XCTAssertEqual(empty.map(\.value), ["0", "—", "—"])
        XCTAssertEqual(empty.map(\.unit), [nil, nil, nil])
    }

    func testR56DiasConIncidenciasPorMes() {
        let bars = StatsText.monthBars(stats.byMonth)
        XCTAssertEqual(bars.map(\.label), ["septiembre 2026", "agosto 2026", "julio 2026"])
        XCTAssertEqual(bars.map(\.fraction), ["9/17", "11/21", "6/22"])
        XCTAssertEqual(bars[1].spokenValue, "11 de 21 días con incidencias")
    }

    func testLaLineaQueMasFallaSonVecesNoDias() {
        let lines = StatsText.lineFailures(stats.byLine, routes: routes)
        XCTAssertEqual(lines.map(\.code), ["13", "J", "147"])
        XCTAssertEqual(lines[0].timesText, "24 veces la peor")
        XCTAssertEqual(lines[0].delayText, "retraso medio 4,6 min")
        XCTAssertEqual(lines[0].annotation, "24 · 4,6 min")
        XCTAssertEqual(lines[2].delayText, nil)
        XCTAssertEqual(lines[2].annotation, "4")
        // El color sale de las rutas guardadas; si no está, el gris de reserva (R57).
        XCTAssertEqual(lines[0].color, "82C8E6")
        XCTAssertEqual(lines[1].color, "CEC73D")
        XCTAssertEqual(StatsText.lineColor(code: "99", routes: routes), "")
        let once = PreviewData.decode(#"{"worst_line": "5", "n": 1, "avg_delay": 0}"#, as: LineStat.self)
        XCTAssertEqual(StatsText.lineFailures([once], routes: []).first?.timesText, "1 vez la peor")
        XCTAssertNil(StatsText.lineFailures([once], routes: []).first?.delayText)
    }
}

/// La lógica de Ajustes (Views/Settings/SettingsLogic.swift): cuota (R46),
/// clave de PRIM sin enseñarla, direcciones y ATS (R61), permisos (R45),
/// extras (R60) y versión.
final class SettingsLogicTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let paris = TimeZone(identifier: "Europe/Paris") ?? .current

    // MARK: - R46 · cuota por endpoint

    func testR46CuotaPorEndpoint() {
        let quota = PreviewData.health(.conClave).quota
        let ordered = QuotaText.ordered(quota.endpoints)
        XCTAssertEqual(ordered.map(\.label), ["Tablero", "Avisos", "Buscador"])
        let board = ordered[0]
        XCTAssertEqual(QuotaText.usage(board), "318 de 1000")
        XCTAssertEqual(QuotaText.remaining(board), "quedan 682")
        XCTAssertEqual(QuotaText.level(board), SettingsStatus(text: "normal", tone: .ok))
        XCTAssertEqual(QuotaText.spoken(board), "Tablero: 318 de 1000 llamadas hoy, quedan 682, normal.")
        XCTAssertNil(QuotaText.overall(quota))
    }

    func testR46CuotaSeReiniciaAMedianocheUTC() {
        let quota = PreviewData.health(.conClave).quota
        XCTAssertEqual(QuotaText.footer(quota, timeZone: utc),
                       "La cuota es de 1000 llamadas al día por endpoint y se reinicia a medianoche UTC (a las 00:00 aquí). El tablero se refresca cada 30 s, y solo mientras lo miras o en modo trayecto.")
        // En París (verano, UTC+2) son las 02:00.
        XCTAssertTrue(QuotaText.footer(quota, timeZone: paris).contains("(a las 02:00 aquí)"))
    }

    func testR46R7CuotaJustaConSusNiveles() {
        let quota = PreviewData.health(.cuotaJusta).quota
        let ordered = QuotaText.ordered(quota.endpoints)
        // 926 de 1000: casi agotada.
        XCTAssertEqual(QuotaText.level(ordered[0]), SettingsStatus(text: "casi agotada", tone: .bad))
        XCTAssertEqual(QuotaText.level(ordered[1]), SettingsStatus(text: "normal", tone: .ok))
        XCTAssertEqual(QuotaText.overall(quota)?.tone, .bad)
        XCTAssertEqual(QuotaText.refresh(quota), "El tablero se refresca cada 2 min, y solo mientras lo miras o en modo trayecto, para ahorrar cuota.")
        XCTAssertEqual(QuotaText.tone(.warn), .warn)
        XCTAssertEqual(QuotaText.tone(.critical), .bad)
    }

    // MARK: - Clave de PRIM: estado y origen, nunca la clave

    func testClavePRIMEstadoYOrigen() {
        let ok = PreviewData.health(.conClave).prim
        XCTAssertEqual(PrimKeyText.status(ok), SettingsStatus(text: "válida", tone: .ok))
        XCTAssertEqual(PrimKeyText.source(ok), "guardada en el panel")
        XCTAssertNil(PrimKeyText.advice(ok))
        XCTAssertEqual(PrimKeyText.checked(ok, timeZone: utc), "comprobada a las 08:12")

        let missing = PreviewData.health(.sinClave).prim
        XCTAssertEqual(PrimKeyText.status(missing), SettingsStatus(text: "sin clave", tone: .bad))
        XCTAssertNil(PrimKeyText.source(missing))
        XCTAssertEqual(PrimKeyText.advice(missing)?.contains("panel"), true)
        XCTAssertNil(PrimKeyText.checked(missing))
    }

    // MARK: - Recolector y traductor

    func testRecolectorYTraductor() {
        let health = PreviewData.health(.conClave)
        XCTAssertEqual(CollectorText.status(health.collector), SettingsStatus(text: "aprendiendo", tone: .ok))
        XCTAssertEqual(CollectorText.detail(health.collector),
                       "última pasada a las 12:41:07 · 3 estaciones · 2 andenes nuevos · la siguiente en 7 min · ritmo normal")
        XCTAssertEqual(TranslatorText.status(health.translator), SettingsStatus(text: "listo", tone: .ok))
        XCTAssertEqual(TranslatorText.detail(health.translator), "qwen2.5:3b")

        let down = PreviewData.health(.traductorCaido).translator
        XCTAssertEqual(TranslatorText.status(down).tone, .warn)
        XCTAssertEqual(TranslatorText.detail(down), "no responde: timed out. Los avisos se ven en francés mientras tanto.")

        let off = PreviewData.health(.sinClave).collector
        XCTAssertEqual(CollectorText.status(off), SettingsStatus(text: "parado", tone: .warn))
    }

    // MARK: - R61 · direcciones y ATS

    func testR61DireccionesYExcepcionDeTailscale() {
        XCTAssertEqual(ServerAddressRules.classify(""), .empty)
        XCTAssertEqual(ServerAddressRules.classify("192.168.1.10:7796"), .localNetwork)
        XCTAssertEqual(ServerAddressRules.classify("http://10.0.0.2:7796"), .localNetwork)
        XCTAssertEqual(ServerAddressRules.classify("http://172.20.1.1:7796"), .localNetwork)
        XCTAssertEqual(ServerAddressRules.classify("http://umbrel.local:7796"), .localNetwork)
        XCTAssertEqual(ServerAddressRules.classify("http://umbrel:7796"), .localNetwork)
        XCTAssertEqual(ServerAddressRules.classify("http://100.99.38.76:7796"), .tailscaleIP)
        XCTAssertEqual(ServerAddressRules.classify("http://100.64.0.1:7796"), .tailscaleIP)
        XCTAssertEqual(ServerAddressRules.classify("http://100.128.0.1:7796"), .needsHTTPS)
        XCTAssertEqual(ServerAddressRules.classify("mi-umbrel.tail1234.ts.net:7796"), .magicDNS)
        XCTAssertEqual(ServerAddressRules.classify("https://trajet.example.com"), .https)
        XCTAssertEqual(ServerAddressRules.classify("http://trajet.example.com:7796"), .needsHTTPS)
        XCTAssertEqual(ServerAddressRules.classify("http://8.8.8.8:7796"), .needsHTTPS)
        XCTAssertEqual(ServerAddressRules.classify("ftp://casa"), .invalid)
        XCTAssertNotNil(ServerAddressRules.note(.tailscaleIP))
        XCTAssertNotNil(ServerAddressRules.note(.magicDNS))
        XCTAssertNil(ServerAddressRules.note(.localNetwork))
        XCTAssertEqual(ServerAddressRules.tone(.needsHTTPS), .warn)
        XCTAssertTrue(ServerAddressRules.footer.contains("100.x"))
        XCTAssertTrue(ServerAddressRules.footer.contains("*.ts.net"))
        XCTAssertNil(ServerAddressRules.ipv4("256.1.1.1"))
        XCTAssertEqual(ServerAddressRules.ipv4("100.64.0.10"), [100, 64, 0, 10])
    }

    /// R61: escribir una dirección la guarda al momento, y «Restablecer»
    /// vuelve a las del emparejamiento y olvida la preferida.
    @MainActor
    func testR61PersisteAlEscribirYRestablecer() {
        let defaults = makeTestDefaults()
        let config = ServerConfig(defaults: defaults)
        config.applyPairing(lan: "http://192.168.1.10:7796", tailscale: "http://100.64.0.10:7796",
                            name: "Trajet de casa", reachable: "http://192.168.1.10:7796")
        config.lanURL = "http://192.168.1.20:7796"
        XCTAssertEqual(ServerConfig(defaults: defaults).lanURL, "http://192.168.1.20:7796")
        config.reset()
        XCTAssertEqual(config.lanURL, "http://192.168.1.10:7796")
        XCTAssertNil(config.preferredURL)
    }

    @MainActor
    func testProbarConexionDiceCualResponde() async {
        let probe = ConnectionProbeModel()
        let paired = PreviewData.decode(PreviewData.pingPairedJSON, as: PingResponse.self)
        let answering = await probe.run(lanURL: "http://192.168.1.10:7796", tailscaleURL: "http://100.64.0.10:7796") { url in
            if url.contains("192.168") { throw APIError.network("tiempo de espera agotado") }
            return paired
        }
        XCTAssertEqual(answering, "http://100.64.0.10:7796")
        XCTAssertEqual(probe.lan, .failed("tiempo de espera agotado"))
        XCTAssertEqual(probe.tailscale, .answered(version: "0.4.0", paired: true))
        XCTAssertEqual(probe.tailscale.status, SettingsStatus(text: "responde · Trajet 0.4.0", tone: .ok))
        XCTAssertEqual(probe.lan.status?.tone, .bad)
        XCTAssertFalse(probe.isRunning)

        let unpaired = PreviewData.ping
        _ = await probe.run(lanURL: "http://192.168.1.10:7796", tailscaleURL: "") { _ in unpaired }
        XCTAssertEqual(probe.lan.status?.tone, .warn)
        XCTAssertEqual(probe.tailscale, .notTried)
    }

    // MARK: - R45 · permisos

    func testR45Permisos() {
        XCTAssertEqual(PermissionText.location(.whenInUse), SettingsStatus(text: "al usar la app", tone: .ok))
        XCTAssertEqual(PermissionText.location(.denied).tone, .bad)
        XCTAssertTrue(PermissionText.locationNote(.whenInUse).contains("«Siempre»"))
        XCTAssertEqual(PermissionText.camera(.unavailable).text, "no hay cámara")
        XCTAssertEqual(PermissionText.camera(.denied).tone, .bad)
        XCTAssertTrue(PermissionText.localNetworkNote.contains("Red local"))
        XCTAssertTrue(PermissionText.localNetworkNote.contains("Tailscale"))
    }

    // MARK: - R60 · widgets y Live Activity

    func testR60ExtrasSegunLaInstalacion() {
        let lite = ExtrasAvailability.make(isLite: true, hasAppGroup: true, liveActivitiesEnabled: true)
        XCTAssertEqual(lite, .lite)
        XCTAssertEqual(lite.widgets.text, "no disponibles")
        XCTAssertEqual(lite.explanation?.contains("lite"), true)

        let noGroup = ExtrasAvailability.make(isLite: false, hasAppGroup: false, liveActivitiesEnabled: true)
        XCTAssertEqual(noGroup, .noAppGroup)
        XCTAssertEqual(noGroup.liveActivity.text, "no disponible")
        XCTAssertEqual(noGroup.explanation?.contains("App Group"), true)

        let full = ExtrasAvailability.make(isLite: false, hasAppGroup: true, liveActivitiesEnabled: true)
        XCTAssertEqual(full.widgets, SettingsStatus(text: "disponibles", tone: .ok))
        XCTAssertEqual(full.liveActivity, SettingsStatus(text: "disponible", tone: .ok))

        let off = ExtrasAvailability.make(isLite: false, hasAppGroup: true, liveActivitiesEnabled: false)
        XCTAssertEqual(off.liveActivity.tone, .warn)
    }

    // MARK: - Versión, dispositivo y modo trayecto

    func testVersionYBuild() {
        XCTAssertEqual(AppVersionText.make(short: "2.0", build: "1"), "2.0 (1)")
        XCTAssertEqual(AppVersionText.make(short: "2.0", build: nil), "2.0")
        XCTAssertEqual(AppVersionText.make(short: nil, build: nil), "—")
        XCTAssertFalse(AppVersionText.current.isEmpty)
    }

    func testEsteDispositivo() {
        let device = PreviewData.device
        XCTAssertEqual(DeviceText.pairedOn(device, timeZone: utc), "emparejado el 24 de septiembre de 2026")
        let now = ISO8601Parsing.date("2026-09-24T10:52:03+00:00") ?? Date()
        XCTAssertEqual(DeviceText.lastUsed(device, now: now), "último uso hace 2 min")
        XCTAssertEqual(DeviceText.detail(device), "iPhone17,1 · app 2.0 (1)")
    }

    func testR6TiempoMaximoDelTrayecto() {
        XCTAssertEqual(TripSettingsText.maxMinutes(90), "1h30")
        XCTAssertEqual(TripSettingsText.maxMinutes(45), "45 min")
        XCTAssertEqual(TripSettingsText.maxMinutes(60), "1h")
        XCTAssertEqual(TripSettingsText.step, 15)
    }
}
