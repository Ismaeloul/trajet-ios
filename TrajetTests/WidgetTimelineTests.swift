import XCTest
@testable import Trajet

/// Los widgets son «una foto con fecha» (decisiones-la-widgets.md §5.5):
/// entradas por minuto con el dato tal como llegó, antigüedad siempre, una
/// entrada final «Sin datos recientes» y recargas con cuentagotas.
final class WidgetTimelineTests: XCTestCase {

    /// 24/09/2026 a las 12:50 de París (10:50 UTC): la hora de los bancos de
    /// `PreviewData`.
    let ref = Date(timeIntervalSince1970: 1_790_247_000)

    private func cached(_ c: PreviewData.BoardCase, edit: (inout Board) -> Void = { _ in }) -> CachedBoard {
        var b = PreviewData.board(c)
        edit(&b)
        return CachedBoard(board: b, receivedAt: ref, routeID: nil)
    }

    private func plan(_ cached: CachedBoard?, failure: WidgetFailure? = nil) -> WidgetTimelinePlan {
        WidgetTimelinePlanner.plan(cached: cached, hasAppGroup: true, failure: failure, now: ref)
    }

    private func plan(_ c: PreviewData.BoardCase, failure: WidgetFailure? = nil) -> WidgetTimelinePlan {
        plan(cached(c), failure: failure)
    }

    /// La entrada que se ve `seconds` después de la recarga.
    private func snapshot(_ p: WidgetTimelinePlan, at seconds: TimeInterval) -> WidgetSnapshot {
        let date = ref.addingTimeInterval(seconds)
        return p.snapshots.last(where: { $0.date <= date }) ?? p.snapshots[0]
    }

    // MARK: - Sin datos

    /// R60: sin App Group (Apple ID gratuito) se dice, no se inventa.
    func testSinAppGroupLoDice() {
        let p = WidgetTimelinePlanner.plan(cached: cached(.unTramo), hasAppGroup: false, failure: nil, now: ref)
        XCTAssertEqual(p.snapshots.count, 1)
        XCTAssertEqual(p.snapshots[0].content, .noAppGroup)
        XCTAssertNil(p.reloadDate)
        XCTAssertEqual(p.snapshots[0].url, AppLink.board.url)
    }

    func testSinTablero() {
        let p = plan(nil as CachedBoard?)
        XCTAssertEqual(p.snapshots.map(\.content), [.noBoard])
        XCTAssertEqual(p.reloadDate, ref.addingTimeInterval(3600))
    }

    // MARK: - Las entradas

    func testEntradasPorMinutoHastaLaFinal() {
        let p = plan(.viaAparece)
        let dates = p.snapshots.map(\.date)
        XCTAssertEqual(dates.first, ref)
        XCTAssertEqual(dates[1], ref.addingTimeInterval(60))
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        // Cuando se va cada salida (12:57:45) y la final, cuando se va la
        // última (13:27:45).
        XCTAssertTrue(dates.contains(ref.addingTimeInterval(7 * 60 + 45)))
        XCTAssertEqual(dates.last, ref.addingTimeInterval(37 * 60 + 45))
        XCTAssertEqual(dates.count, 41)          // ahora + 37 minutos + 2 salidas + final
        XCTAssertLessThanOrEqual(dates.count, WidgetTimelinePlanner.maxEntries)
    }

    /// La cifra baja entrada a entrada aunque el widget no se recargue.
    func testLaCifraBajaEntradaAEntrada() {
        let p = plan(.viaAparece)
        let at3 = snapshot(p, at: 180)
        XCTAssertEqual(at3.legView(0)?.hero?.id, "j1")
        XCTAssertEqual(at3.legView(0)?.hero.map { at3.moment($0) }, .minutes(4))
        let at7 = snapshot(p, at: 7 * 60)
        XCTAssertEqual(at7.legView(0)?.hero.map { at7.moment($0) }, .now)
        // A las 12:57:45 ya manda el siguiente.
        let gone = snapshot(p, at: 7 * 60 + 45)
        XCTAssertEqual(gone.legView(0)?.hero?.id, "j2")
        XCTAssertEqual(gone.legView(0)?.hero.map { gone.moment($0) }, .minutes(15))
    }

    /// R10: la probable sigue probable en todas las entradas (el widget no
    /// «publica» vías: enseña el dato tal como llegó).
    func testLaProbableSigueProbable() {
        let p = plan(.viaAparece)
        for s in p.snapshots {
            guard let j2 = s.legView(0)?.remaining.first(where: { $0.id == "j2" }) else { continue }
            XCTAssertEqual(j2.via, .probable("21", share: 0.9))
        }
        let first = snapshot(p, at: 0).legView(0)?.hero
        XCTAssertEqual(first?.via, .real("21", isNew: false, before: nil))
    }

    /// La entrada final: «Sin datos recientes · abre Trajet», nunca
    /// «Servicio finalizado».
    func testEntradaFinalSinDatosRecientes() throws {
        let last = try XCTUnwrap(plan(.viaAparece).snapshots.last)
        let main = try XCTUnwrap(last.legView(0))
        XCTAssertNil(main.hero)
        XCTAssertTrue(main.isFinal)
        XCTAssertEqual(main.empty, .noRecentData)
        XCTAssertTrue(last.isOff)
        XCTAssertEqual(last.url, AppLink.board.url)
    }

    /// R6: con una hora o más, hora fija (el sistema no sabe decir «1h46»);
    /// más allá de la primera hora de entradas, todo con hora fija.
    func testUnaHoraOMasEsHoraFija() throws {
        let p = plan(.bus106)
        let now = snapshot(p, at: 0)
        let deps = try XCTUnwrap(now.legView(0)).remaining
        XCTAssertEqual(deps.map { now.moment($0) }, [.minutes(12), .time("13:50"), .time("14:36"), .time("15:35")])
        // A las 13:50 (una hora después) el de las 13:50 aún se ve, con su hora.
        let later = snapshot(p, at: 3600)
        XCTAssertFalse(later.countdownValid)
        XCTAssertEqual(later.legView(0)?.hero?.id, "n2")
        XCTAssertEqual(later.legView(0)?.hero.map { later.moment($0) }, .time("13:50"))
        XCTAssertEqual(p.snapshots.last?.date, ref.addingTimeInterval(2 * 3600 + 45 * 60 + 45))
        XCTAssertLessThanOrEqual(p.snapshots.count, WidgetTimelinePlanner.maxEntries)
    }

    /// R15: «En andén» solo con el dato recién llegado; después, el siguiente.
    func testEnAndenSoloConDatoReciente() {
        let p = plan(.enAnden)
        let now = snapshot(p, at: 0)
        XCTAssertEqual(now.legView(0)?.hero.map { now.moment($0) }, .atStop)
        let later = snapshot(p, at: 120)
        XCTAssertEqual(later.legView(0)?.hero?.id, "j1")
    }

    // MARK: - Recargas

    /// `.after(mín(última salida, ahora + 15 min))`.
    func testPoliticaDeRecarga() {
        XCTAssertEqual(plan(.viaAparece).reloadDate, ref.addingTimeInterval(15 * 60))
        // La última del metro sale a las 12:59: se recarga al irse (12:59:45).
        XCTAssertEqual(plan(.destinosMezclados).reloadDate, ref.addingTimeInterval(9 * 60 + 45))
    }

    func testRecargasConCuentagotas() {
        let t0 = ref
        XCTAssertEqual(WidgetRefresher.decision(now: t0, lastReload: nil, lastSignature: nil, signature: "a"), .reload)
        // Nada nuevo: como mucho cada 15 min.
        XCTAssertEqual(WidgetRefresher.decision(now: t0.addingTimeInterval(300), lastReload: t0,
                                                lastSignature: "a", signature: "a"), .skip)
        XCTAssertEqual(WidgetRefresher.decision(now: t0.addingTimeInterval(901), lastReload: t0,
                                                lastSignature: "a", signature: "a"), .reload)
        // Algo nuevo: con 2 min de separación; si es pronto, se deja pendiente.
        XCTAssertEqual(WidgetRefresher.decision(now: t0.addingTimeInterval(30), lastReload: t0,
                                                lastSignature: "a", signature: "b"),
                       .later(t0.addingTimeInterval(WidgetRefresher.minimumGap)))
        XCTAssertEqual(WidgetRefresher.decision(now: t0.addingTimeInterval(180), lastReload: t0,
                                                lastSignature: "a", signature: "b"), .reload)
        // El reloj ha ido hacia atrás.
        XCTAssertTrue(WidgetRefresher.shouldReload(now: t0.addingTimeInterval(-10), lastReload: t0,
                                                   lastSignature: "a", signature: "a"))
    }

    /// Lo que se ve cambia con la vía, no con la hora de llegada.
    func testFirmaDeLoQueSeVe() {
        let base = cached(.viaProbable)
        let withPlatform = cached(.viaProbable) { $0.legs[0].departures[0].platform = "21" }
        let later = CachedBoard(board: PreviewData.board(.viaProbable), receivedAt: ref.addingTimeInterval(30), routeID: nil)
        XCTAssertNotEqual(WidgetRefresher.signature(of: base), WidgetRefresher.signature(of: withPlatform))
        XCTAssertEqual(WidgetRefresher.signature(of: base), WidgetRefresher.signature(of: later))
        XCTAssertEqual(WidgetRefresher.signature(of: nil), "vacío")
    }

    // MARK: - Estados

    /// Servidor sin clave: se sabe por el propio tablero; toca → Ajustes.
    func testServidorSinClave() {
        let p = plan(cached(.unTramo) { $0.server = ServerState(primKey: .missing) })
        let s = snapshot(p, at: 0)
        XCTAssertEqual(s.failure, .noKey)
        XCTAssertTrue(s.isOff)
        XCTAssertEqual(s.url, AppLink.serverSettings.url)
    }

    /// La recarga falló: apagado y «dato sin actualizar» en VoiceOver.
    func testFalloApuntadoPorLaApp() throws {
        let p = plan(.unTramo, failure: .offline)
        XCTAssertTrue(p.snapshots.allSatisfy { $0.failure == .offline && $0.isOff })
        let s = snapshot(p, at: 0)
        let main = try XCTUnwrap(s.legView(0))
        let hero = try XCTUnwrap(main.hero)
        XCTAssertTrue(s.spoken(hero, in: main.leg).contains("dato sin actualizar"))
    }

    func testTrenCancelado() throws {
        let p = plan(cached(.viaAparece) { $0.legs[0].departures[0].status = "cancelled" })
        let main = try XCTUnwrap(snapshot(p, at: 0).legView(0))
        XCTAssertEqual(main.cancelled?.id, "j1")
        XCTAssertEqual(main.hero?.id, "j2")
        XCTAssertEqual(main.following.map(\.id), ["j3"])
    }

    /// R25: cortada → «Sin circulación» y alternativas; normal → «Servicio
    /// finalizado».
    func testLineaCortadaYServicioFinalizado() throws {
        let cut = snapshot(plan(.lineaCortada), at: 0)
        let cutMain = try XCTUnwrap(cut.legView(0))
        XCTAssertEqual(cutMain.empty, .cut)
        XCTAssertEqual(cutMain.statusLevel, 0)
        XCTAssertEqual(cut.url, AppLink.alternatives(routeID: 4).url)

        let empty = try XCTUnwrap(snapshot(plan(.tramoVacio), at: 0).legView(0))
        XCTAssertFalse(empty.isFinal)
        XCTAssertEqual(empty.empty, .finished)
    }

    /// R3: metro sin vía; R24: destinos mezclados.
    func testMetroSinViaYDestinosMezclados() throws {
        let metro = try XCTUnwrap(snapshot(plan(.tranquilo), at: 0).legView(0))
        XCTAssertTrue(metro.remaining.allSatisfy { $0.via == nil })
        XCTAssertTrue(try XCTUnwrap(snapshot(plan(.destinosMezclados), at: 0).legView(0)).leg.mixed)
        XCTAssertFalse(try XCTUnwrap(snapshot(plan(.unTramo), at: 0).legView(0)).leg.mixed)
    }

    /// R4, R14: retraso solo con hora teórica y distinto de cero.
    func testRetrasoSoloConHoraTeorica() throws {
        let bus = try XCTUnwrap(snapshot(plan(.cincoTramos), at: 0).legView(0))
        XCTAssertEqual(bus.remaining.map(\.delay), [11, 1, 1])
        let metro = try XCTUnwrap(snapshot(plan(.destinosMezclados), at: 0).legView(0))
        XCTAssertTrue(metro.remaining.allSatisfy { $0.delay == nil })
        let train = try XCTUnwrap(snapshot(plan(.viaAparece), at: 0).legView(0))
        XCTAssertNil(train.hero?.delay)
    }

    /// R17, R18: la antigüedad cuenta desde la llegada más `data_age`.
    func testAntiguedadSiempreALaVista() {
        let s = snapshot(plan(.viaAparece), at: 300)
        XCTAssertEqual(s.ageSeconds, 302.1, accuracy: 0.001)
        XCTAssertEqual(s.ageText, "hace 5 min")
    }

    /// Texto secundario del billete del grande: hora, retraso y longitud.
    func testTextoDelBillete() throws {
        let s = snapshot(plan(.unTramo), at: 0)
        let hero = try XCTUnwrap(s.legView(0)?.hero)
        XCTAssertEqual(s.meta(hero), [.time("12:57"), .length(.long)])
        XCTAssertNil(s.timerRange(hero))      // la cifra la pone la entrada
    }

    /// Enlaces: el widget va a la ruta y el tramo; cada fila, a su salida.
    func testEnlaces() throws {
        let s = snapshot(plan(.unTramo), at: 0)
        let main = try XCTUnwrap(s.legView(0))
        XCTAssertEqual(s.url, AppLink.route(id: 5, legSeq: 0, departureJID: nil).url)
        XCTAssertEqual(s.url(leg: main.leg, departure: main.second),
                       AppLink.route(id: 5, legSeq: 0, departureJID: "j2").url)
    }

    func testMuestraDelMarcador() throws {
        let sample = WidgetSnapshot.sample(now: ref)
        let main = try XCTUnwrap(sample.legView(0))
        XCTAssertEqual(main.hero?.id, "a")
        XCTAssertEqual(sample.url, AppLink.board.url)
    }
}
