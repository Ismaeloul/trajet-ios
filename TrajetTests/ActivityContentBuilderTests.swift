#if canImport(ActivityKit)
import XCTest
@testable import Trajet

/// El `ContentState` de la Live Activity sale del tablero y de nada más
/// (docs/diseno/sistema.md §12.4), y la vista pinta solo esa foto
/// (`ActivityPresentation`, decisiones-la-widgets.md §5.3).
final class ActivityContentBuilderTests: XCTestCase {

    typealias State = TrajetActivityAttributes.ContentState
    typealias Options = ActivityContentBuilder.Options

    /// 24/09/2026 a las 12:50 de París (10:50 UTC): la hora de los bancos de
    /// `PreviewData`.
    let ref = Date(timeIntervalSince1970: 1_790_247_000)

    private func board(_ c: PreviewData.BoardCase, edit: (inout Board) -> Void = { _ in }) -> Board {
        var b = PreviewData.board(c)
        edit(&b)
        return b
    }

    private func make(_ board: Board, after seconds: TimeInterval = 0, options: Options = Options()) -> State {
        ActivityContentBuilder.make(board: board, receivedAt: ref, routeID: board.route?.id ?? 0,
                                    now: ref.addingTimeInterval(seconds), options: options)
    }

    private func present(_ state: State, stale: Bool = false, routeID: Int = 5) -> ActivityPresentation {
        ActivityPresentation(state: state, isStale: stale, routeID: routeID)
    }

    // MARK: - Lo que se copia del tablero

    /// R2, R10: la vía real y la probable llegan cada una por su sitio.
    func testViaRealYProbableDelTablero() throws {
        let s = make(board(.viaAparece))
        XCTAssertEqual(s.leg.seq, 0)
        XCTAssertEqual(s.leg.lineCode, "J")
        XCTAssertEqual(s.leg.lineColor, "CEC73D")
        XCTAssertTrue(s.leg.platformExpected)
        XCTAssertEqual(s.leg.direction, ["Ermont - Eaubonne", "Ermont-Eaubonne", "Ermont"])
        XCTAssertEqual(s.leg.departures.count, 3)
        XCTAssertEqual(s.legIndex, 0)
        XCTAssertEqual(s.legCount, 1)
        XCTAssertNil(s.next)
        XCTAssertEqual(s.receivedAt, ref)
        XCTAssertEqual(s.dataAge, 2.1, accuracy: 0.001)
        XCTAssertEqual(s.refreshHint, 30)
        XCTAssertEqual(s.connection, .ok)
        XCTAssertNil(s.ended)

        let d0 = s.leg.departures[0]
        XCTAssertEqual(d0.jid, "j1")
        XCTAssertEqual(d0.at, ref.addingTimeInterval(7 * 60))     // «12:57» de París
        XCTAssertEqual(d0.minutes, 7)
        XCTAssertEqual(d0.platform, "21")
        XCTAssertTrue(d0.platformNew)
        XCTAssertNil(d0.guessPlatform)
        XCTAssertNil(d0.platformBefore)
        XCTAssertEqual(d0.length, "long")
        XCTAssertEqual(d0.destination, ["Ermont - Eaubonne", "Ermont-Eaubonne", "Ermont"])

        let d1 = s.leg.departures[1]
        XCTAssertNil(d1.platform)
        XCTAssertFalse(d1.platformNew)
        XCTAssertEqual(d1.guessPlatform, "21")
        XCTAssertEqual(try XCTUnwrap(d1.guessShare), 0.9, accuracy: 0.0001)

        let d2 = s.leg.departures[2]
        XCTAssertNil(d2.platform)
        XCTAssertNil(d2.guessPlatform)
    }

    /// R3: metro, bus y tranvía no publican vía: ni real ni probable.
    func testSinViaEnMetroBusYTranvia() {
        for c in [PreviewData.BoardCase.tranquilo, .cincoTramos, .destinosMezclados] {
            let s = make(board(c))
            XCTAssertFalse(s.leg.platformExpected, c.rawValue)
            for d in s.leg.departures {
                XCTAssertNil(d.platform, c.rawValue)
                XCTAssertNil(d.guessPlatform, c.rawValue)
                XCTAssertNil(present(s).via(d), c.rawValue)
            }
        }
    }

    /// R4, R14: retraso solo con hora teórica y distinto de cero.
    func testRetrasoSoloConHoraTeorica() {
        XCTAssertEqual(make(board(.cincoTramos)).leg.departures[0].delay, 11)
        XCTAssertNil(make(board(.destinosMezclados)).leg.departures[0].delay)   // metro: sin hora teórica
        XCTAssertNil(make(board(.viaAparece)).leg.departures[0].delay)          // +0 no se pinta
        XCTAssertEqual(make(board(.casosLimite)).leg.departures[0].delay, -1)   // adelanto
    }

    /// Como mucho tres salidas (tope de 4 KB del estado).
    func testTresSalidasComoMucho() {
        XCTAssertEqual(make(board(.unTramo)).leg.departures.map(\.jid), ["j1", "j2", "j3"])
    }

    /// R24: sin sentido y con destinos distintos, cada salida dice a dónde va.
    func testDestinosMezclados() {
        let s = make(board(.destinosMezclados))
        XCTAssertTrue(s.leg.mixed)
        XCTAssertEqual(s.leg.departures.map { $0.destination.last }, ["Châtillon", "Les Courtilles", "St-Denis"])
        XCTAssertFalse(make(board(.unTramo)).leg.mixed)
    }

    // MARK: - El tiempo

    /// La app reescribe la cifra cada minuto desde su último tablero.
    func testMinutosAlEscribir() {
        XCTAssertEqual(make(board(.viaAparece), after: 59).leg.departures[0].minutes, 7)
        XCTAssertEqual(make(board(.viaAparece), after: 150).leg.departures[0].minutes, 5)
        // A las 12:57:20 el tren aún está («ya»).
        let s = make(board(.viaAparece), after: 440)
        XCTAssertEqual(s.leg.departures[0].jid, "j1")
        XCTAssertEqual(present(s).moment(s.leg.departures[0]), .now)
    }

    /// A los 45 s de su hora, la salida se va y manda la siguiente.
    func testLasQueYaSalieronSeVan() {
        let s = make(board(.viaAparece), after: 480)
        XCTAssertEqual(s.leg.departures.map(\.jid), ["j2", "j3"])
        XCTAssertEqual(s.leg.departures[0].minutes, 14)
    }

    /// R15: «En andén» (confirmado) no es «ya»; se queda mientras el tablero
    /// sea reciente.
    func testEnAndenNoEsYa() {
        let s = make(board(.enAnden), after: 60)
        let d0 = s.leg.departures[0]
        XCTAssertTrue(d0.atStop)
        XCTAssertEqual(present(s).moment(d0), .atStop)
        XCTAssertNotEqual(present(s).moment(d0), .now)
        XCTAssertEqual(present(s).via(d0), .real("21", isNew: false, before: nil))
        // Con el tablero de hace 2 min ya no se puede decir que siga ahí.
        XCTAssertEqual(make(board(.enAnden), after: 120).leg.departures.first?.jid, "j1")
    }

    /// R6: con una hora o más, «1h46».
    func testMinutosLargos() {
        let s = make(board(.bus106) { $0.legs[0].departures.removeFirst(2) })
        let p = present(s, routeID: 6)
        let hero = try? XCTUnwrap(p.hero)
        XCTAssertEqual(hero.map { p.moment($0) }, .long("1h46"))
        XCTAssertEqual(hero.map { p.meta($0) }, [.time("14:36"), .delay(11)])
    }

    // MARK: - Tramos y transbordo

    func testTransbordo() {
        let s = make(board(.transbordo))
        XCTAssertEqual(s.legCount, 2)
        XCTAssertEqual(s.leg.lineCode, "A")
        XCTAssertEqual(s.leg.toName, "Auber")
        XCTAssertEqual(s.next?.lineCode, "J")
        XCTAssertEqual(s.next?.first?.jid, "j2")
        XCTAssertEqual(s.next?.first?.guessPlatform, "21")
        // Varios sentidos: el destino de la cabecera es el del primer tren.
        XCTAssertEqual(s.leg.direction, ["Cergy - Le Haut", "Cergy-Le Haut", "Cergy"])
        let p = present(s, routeID: 10)
        XCTAssertEqual(p.link?.jid, "j2")
        XCTAssertEqual(p.transferNames, ["Auber"])
        XCTAssertEqual(p.linkVia(try! XCTUnwrap(p.link)), .probable("21", share: 0.9))
        XCTAssertEqual(p.legText, "tramo 1 de 2")
        XCTAssertTrue(p.meta(try! XCTUnwrap(p.hero)).contains(.leg("tramo 1 de 2")))
    }

    /// El tramo lo decide el modo trayecto (geocercas); si no, el primero.
    func testTramoQueDiceElModoTrayecto() {
        let s = make(board(.tranquilo), options: Options(legSeq: 1))
        XCTAssertEqual(s.leg.lineCode, "J")
        XCTAssertEqual(s.legIndex, 1)
        XCTAssertNil(s.next)
        XCTAssertEqual(make(board(.tranquilo), options: Options(legSeq: 9)).leg.lineCode, "14")
    }

    func testSinTramos() {
        let s = make(Board(route: BoardRoute(id: 1, name: "Vacía"), legs: []))
        XCTAssertEqual(s.legCount, 0)
        XCTAssertTrue(s.leg.departures.isEmpty)
        XCTAssertEqual(present(s).empty, .finished)
    }

    // MARK: - Estados

    /// R25: sin salidas, «Sin circulación» si está cortada; toca → alternativas.
    func testLineaCortada() {
        let s = make(board(.lineaCortada))
        XCTAssertEqual(s.leg.statusLevel, 2)
        XCTAssertTrue(s.leg.departures.isEmpty)
        XCTAssertEqual(s.next?.lineCode, "J")
        let p = present(s, routeID: 4)
        XCTAssertEqual(p.empty, .cut)
        XCTAssertEqual(p.statusLevel, 0)          // el billete ya lo dice (P2-17)
        XCTAssertEqual(p.url, AppLink.alternatives(routeID: 4).url)
        XCTAssertEqual(ActivityContentBuilder.alert(previous: make(board(.tranquilo)), current: s),
                       .lineCut(line: "14"))
    }

    /// R25: línea normal y sin salidas, «Servicio finalizado».
    func testServicioFinalizado() {
        XCTAssertEqual(present(make(board(.tramoVacio)), routeID: 4).empty, .finished)
    }

    func testCambioDeVia() throws {
        let before = make(board(.viaAparece))
        let changed = board(.viaAparece) {
            $0.legs[0].departures[0].platform = "23"
            $0.legs[0].departures[0].platformNew = false
        }
        let s = make(changed, after: 30, options: Options(previous: before))
        let d0 = s.leg.departures[0]
        XCTAssertEqual(d0.platform, "23")
        XCTAssertEqual(d0.platformBefore, "21")
        let p = present(s)
        XCTAssertEqual(p.via(d0), .real("23", isNew: false, before: "21"))
        XCTAssertEqual(p.meta(d0).first, .platformChange(before: "21"))
        XCTAssertTrue(p.showsPlatformBand)
        XCTAssertEqual(ActivityContentBuilder.alert(previous: before, current: s),
                       .platformChanged(platform: "23", before: "21"))
        // La siguiente escritura con la misma vía conserva «antes 21» y no avisa otra vez.
        let again = make(changed, after: 60, options: Options(previous: s))
        XCTAssertEqual(again.leg.departures[0].platformBefore, "21")
        XCTAssertNil(ActivityContentBuilder.alert(previous: s, current: again))
    }

    /// R2: la vía se acaba de publicar → alerta y franja.
    func testViaPublicada() {
        let before = make(board(.viaProbable))
        let s = make(board(.viaAparece), after: 30, options: Options(previous: before))
        XCTAssertEqual(ActivityContentBuilder.alert(previous: before, current: s), .platformPublished(platform: "21"))
        XCTAssertTrue(present(s).showsPlatformBand)
        // Nunca por un cambio de minuto.
        XCTAssertNil(ActivityContentBuilder.alert(previous: s, current: make(board(.viaAparece), after: 90)))
    }

    func testTrenCancelado() {
        let cancelled = board(.viaAparece) { $0.legs[0].departures[0].status = "cancelled" }
        let s = make(cancelled)
        XCTAssertTrue(s.leg.departures[0].cancelled)
        let p = present(s)
        XCTAssertEqual(p.cancelled?.jid, "j1")
        XCTAssertEqual(p.hero?.jid, "j2")
        XCTAssertEqual(p.second?.jid, "j3")
        XCTAssertEqual(ActivityContentBuilder.alert(previous: make(board(.viaAparece)), current: s),
                       .cancelled(time: "12:57"))
    }

    func testServidorSinClave() {
        let noKey = board(.unTramo) { $0.server = ServerState(primKey: .missing) }
        let s = make(noKey)
        XCTAssertEqual(s.connection, .noKey)
        let p = present(s)
        XCTAssertTrue(p.isOff)
        XCTAssertEqual(p.url, AppLink.serverSettings.url)
    }

    func testSinConexionPorTiempo() {
        XCTAssertEqual(make(board(.unTramo), after: 120).connection, .offline)
        XCTAssertEqual(make(board(.unTramo), after: 120, options: Options(connection: .ok)).connection, .ok)
        XCTAssertEqual(make(board(.unTramo), after: 30).connection, .ok)
    }

    // MARK: - Caducada (la app dejó de escribir)

    /// P0-1: caducada, horas fijas; la vía tal como llegó y sin «nueva».
    func testCaducadaMuestraHoraFija() throws {
        let s = make(board(.viaAparece))
        let p = present(s, stale: true)
        let hero = try XCTUnwrap(p.hero)
        XCTAssertEqual(hero.jid, "j1")
        XCTAssertEqual(p.moment(hero), .time("12:57"))
        XCTAssertEqual(p.via(hero), .real("21", isNew: false, before: nil))
        XCTAssertTrue(p.isOff)
        XCTAssertFalse(p.showsPlatformBand)
        XCTAssertTrue(p.spoken(hero).contains("dato sin actualizar"))
        XCTAssertFalse(p.meta(hero).contains(.time("12:57")))     // la hora ya es la cifra
    }

    /// Sin conexión y caducada: el tren enseñado ya salió, pasa al siguiente
    /// de la foto (nunca «publica» una vía que no llegó).
    func testCaducadaPasaAlSiguienteDeLaFoto() throws {
        let s = make(board(.viaAparece), after: 240, options: Options(connection: .offline))
        let p = present(s, stale: true)
        let hero = try XCTUnwrap(p.hero)
        XCTAssertEqual(hero.jid, "j2")
        XCTAssertEqual(p.moment(hero), .time("13:12"))
        XCTAssertEqual(p.via(hero), .probable("21", share: 0.9))
    }

    /// staleDate = el primero de: dato viejo, tren enseñado + 60 s, siguiente
    /// cambio de minuto + 30 s (decisiones §5.3).
    func testStaleDate() {
        let live = make(board(.viaAparece), after: 10)
        XCTAssertEqual(ActivityContentBuilder.staleDate(for: live, writtenAt: ref.addingTimeInterval(10)),
                       ref.addingTimeInterval(90))
        // Sin conexión el dato viejo no cuenta: manda el cambio de minuto.
        let offline = make(board(.viaAparece), after: 200, options: Options(connection: .offline))
        XCTAssertEqual(ActivityContentBuilder.staleDate(for: offline, writtenAt: ref.addingTimeInterval(200)),
                       ref.addingTimeInterval(270))
        // Y si el tren sale antes, el tren (12:57 + 60 s < 12:58 + 30 s).
        let late = make(board(.viaAparece), after: 430, options: Options(connection: .offline))
        XCTAssertEqual(ActivityContentBuilder.staleDate(for: late, writtenAt: ref.addingTimeInterval(430)),
                       ref.addingTimeInterval(7 * 60 + 60))
    }

    // MARK: - Enlaces, voz, fin y tamaño

    func testEnlaceALaRuta() {
        let p = present(make(board(.unTramo)))
        XCTAssertEqual(p.url, AppLink.route(id: 5, legSeq: 0, departureJID: nil).url)
        XCTAssertEqual(AppLink(url: p.url), .route(id: 5, legSeq: 0, departureJID: nil))
    }

    /// R50: una frase por salida.
    func testVozUnaFrasePorSalida() throws {
        let s = make(board(.viaAparece))
        let p = present(s)
        let sentence = p.spoken(try XCTUnwrap(p.hero))
        XCTAssertTrue(sentence.hasPrefix("Línea J a Ermont - Eaubonne"), sentence)
        XCTAssertTrue(sentence.contains("en 7 minutos"), sentence)
        XCTAssertTrue(sentence.contains("vía 21"), sentence)
        XCTAssertFalse(sentence.contains("dato sin actualizar"), sentence)
        let early = make(board(.casosLimite))
        XCTAssertTrue(present(early, routeID: 12).spoken(early.leg.departures[0]).contains("1 minuto de adelanto"))
    }

    func testTerminado() {
        let s = ActivityContentBuilder.ended(make(board(.unTramo)), reason: .arrived)
        XCTAssertEqual(s.ended, .arrived)
        let p = present(s)
        XCTAssertTrue(p.isEnded)
        XCTAssertEqual(p.url, AppLink.route(id: 5, legSeq: nil, departureJID: nil).url)
        XCTAssertNil(ActivityContentBuilder.alert(previous: make(board(.viaProbable)), current: s))
    }

    /// Con la hora de fin, «se quita sola a las 13:05» (12:50 + 15 min, hora
    /// de París); sin ella, «en unos minutos», que siempre es verdad.
    func testTerminadoDiceCuandoSeQuita() throws {
        let s = ActivityContentBuilder.ended(make(board(.unTramo)), reason: .arrived, at: ref)
        XCTAssertEqual(s.endedAt, ref)
        let p = present(s)
        XCTAssertEqual(p.dismissesAt, ref.addingTimeInterval(15 * 60))
        XCTAssertEqual(p.endedDetail, "Has llegado · se quita sola a las 13:05 · toca para abrir la ruta")

        let limit = ActivityContentBuilder.ended(make(board(.unTramo)), reason: .maxDuration, at: ref)
        XCTAssertTrue(present(limit).endedDetail.hasPrefix("Llegó al tiempo máximo · se quita sola a las 13:05"))

        let unknown = ActivityContentBuilder.ended(make(board(.unTramo)), reason: .arrived)
        XCTAssertNil(unknown.endedAt)
        XCTAssertNil(present(unknown).dismissesAt)
        XCTAssertEqual(present(unknown).endedDetail, "Has llegado · se quita sola en unos minutos · toca para abrir la ruta")

        // Un estado viejo (sin el campo) se sigue leyendo.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json.removeValue(forKey: "endedAt")
        let old = try JSONDecoder().decode(State.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.endedAt)
        XCTAssertEqual(old.ended, .arrived)
    }

    /// El estado cabe de sobra en los 4 KB de ActivityKit.
    func testCabeEnCuatroKB() throws {
        for (c, seq) in [(PreviewData.BoardCase.cincoTramos, 2), (.transbordo, 0), (.unTramo, 0)] {
            let s = make(board(c), options: Options(legSeq: seq))
            let bytes = try JSONEncoder().encode(s).count
            XCTAssertLessThan(bytes, 4096, c.rawValue)
        }
    }

    // MARK: - Piezas del billete

    /// Lo secundario cae entero y por prioridad: tramo, longitud, hora; luego
    /// «antes vía 21»; lo último, el cambio de vía.
    func testEscaleraDelTextoSecundario() {
        let ladder = GlanceMeta.ladder([.platformChange(before: "21"), .time("12:56"), .delay(2),
                                        .length(.long), .leg("tramo 1 de 2")])
        XCTAssertEqual(ladder.count, 7)
        XCTAssertEqual(ladder[0].map(\.text), ["cambio de vía · antes 21", "sale 12:56", "+2 min",
                                               "tren largo", "tramo 1 de 2"])
        XCTAssertEqual(ladder[3].map(\.text), ["cambio de vía · antes 21", "+2 min"])
        XCTAssertEqual(ladder[4].map(\.text), ["antes vía 21", "+2 min"])
        XCTAssertEqual(ladder.last, [])
    }

    /// La cabecera: cae antes «perturbada», luego se abrevia el destino,
    /// luego el prefijo de la antigüedad y lo último el destino entero.
    func testEscaleraDeLaCabecera() {
        let steps = GlanceHeaderStep.ladder(destinations: ["Ermont - Eaubonne", "Ermont-Eaubonne", "Ermont"],
                                            hasStatusWord: true, agePrefixCount: 3)
        XCTAssertEqual(steps.first, GlanceHeaderStep(destination: "Ermont - Eaubonne", statusWord: true, agePrefix: 0))
        XCTAssertEqual(steps[1], GlanceHeaderStep(destination: "Ermont - Eaubonne", statusWord: false, agePrefix: 0))
        XCTAssertEqual(steps.last, GlanceHeaderStep(destination: nil, statusWord: false, agePrefix: 2))
        XCTAssertEqual(steps.count, 7)
    }

    func testMomentosDeLaCifra() {
        XCTAssertEqual(GlanceMoment.from(minutes: 6, atStop: false), .minutes(6))
        XCTAssertEqual(GlanceMoment.from(minutes: 0, atStop: false), .now)
        XCTAssertEqual(GlanceMoment.from(minutes: 0, atStop: true), .atStop)
        XCTAssertEqual(GlanceMoment.from(minutes: 106, atStop: false), .long("1h46"))
        XCTAssertEqual(GlanceMoment.minutes(6).unit, "min")
        XCTAssertNil(GlanceMoment.now.unit)
        XCTAssertEqual(GlanceVia.probable("21", share: 0.9).inline, "prob. 21")
        XCTAssertEqual(GlanceVia.real("21", isNew: false, before: nil).inline, "Vía 21")
        XCTAssertEqual(GlanceVia.probable("21", share: 0.9).sharePercent, "90 %")
        // R3: sin vía esperada no hay nada, ni la probable.
        XCTAssertNil(GlanceVia.make(expected: false, platform: "21", guess: "21", share: 0.9))
        XCTAssertEqual(GlanceVia.make(expected: true, platform: "", guess: "7", share: 0.5), .probable("7", share: 0.5))
    }
}
#endif
