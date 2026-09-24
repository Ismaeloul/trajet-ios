import XCTest
@testable import Trajet

/// La lógica de Rutas, el editor, «montar un tramo» y el planificador
/// (Views/Routes/RoutesLogic.swift). Cada test lleva en el nombre las reglas
/// que cubre (docs/reglas.md).
final class RoutesLogicTests: XCTestCase {

    private var routes: [SavedRoute] { PreviewData.routes }

    private func route(_ id: Int) throws -> SavedRoute {
        try XCTUnwrap(routes.first { $0.id == id })
    }

    private var stops: [StopResult] {
        PreviewData.decode(PreviewData.stopSearchJSON, as: StopSearchResponse.self).stops
    }

    private var places: [PlaceResult] {
        PreviewData.decode(PreviewData.placeSearchJSON, as: PlaceSearchResponse.self).places
    }

    // MARK: - R31 · buscadores: 2 caracteres y 350 ms

    func testR31MinimoDosCaracteres() {
        XCTAssertNil(SearchRules.query(""))
        XCTAssertNil(SearchRules.query("a"))
        XCTAssertNil(SearchRules.query("   a  "))
        XCTAssertEqual(SearchRules.query("ab"), "ab")
        XCTAssertEqual(SearchRules.query("  Gare  "), "Gare")
        XCTAssertEqual(SearchRules.query(String(repeating: "x", count: 120))?.count, 80)
        XCTAssertEqual(SearchRules.minimumCharacters, 2)
        XCTAssertEqual(SearchRules.delay, .milliseconds(350))
    }

    @MainActor
    func testR31Debounce350msYMinimo2() async {
        let sleeps = DurationLog()
        let performed = StringLog()
        let debouncer = SearchDebouncer(sleep: { duration in await sleeps.add(duration) })

        // Menos de 2 caracteres: no se programa nada.
        XCTAssertFalse(debouncer.schedule("G") { q in await performed.add(q) })
        XCTAssertFalse(debouncer.schedule("  G ") { q in await performed.add(q) })
        // Tres teclas seguidas: cada una cancela la anterior; solo busca la última.
        XCTAssertTrue(debouncer.schedule("Ga") { q in await performed.add(q) })
        XCTAssertTrue(debouncer.schedule("Gar") { q in await performed.add(q) })
        XCTAssertTrue(debouncer.schedule(" Gare ") { q in await performed.add(q) })
        await debouncer.waitForPending()

        let queries = await performed.values
        XCTAssertEqual(queries, ["Gare"])
        let durations = await sleeps.values
        XCTAssertFalse(durations.isEmpty)
        XCTAssertTrue(durations.allSatisfy { $0 == .milliseconds(350) })
    }

    @MainActor
    func testR31BuscadorDeParadasNoGastaCuotaConUnaLetra() async {
        let calls = StringLog()
        let found = stops
        let model = StopSearchModel(debouncer: SearchDebouncer(sleep: { _ in }))

        model.textChanged("G") { q in
            await calls.add(q)
            return found
        }
        await model.waitForPending()
        XCTAssertEqual(model.phase, .idle)
        let none = await calls.values
        XCTAssertEqual(none, [])

        model.textChanged("Gare") { q in
            await calls.add(q)
            return found
        }
        await model.waitForPending()
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.results.map(\.name), ["Gare Saint-Lazare", "Argenteuil"])
        let one = await calls.values
        XCTAssertEqual(one, ["Gare"])

        // Borrar hasta una letra vacía la lista sin llamar.
        model.textChanged("G") { q in
            await calls.add(q)
            return found
        }
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.results.isEmpty)
    }

    @MainActor
    func testR31FalloDelBuscadorSeDice() async {
        let model = PlaceSearchModel(debouncer: SearchDebouncer(sleep: { _ in }))
        model.textChanged("Rue de Paris") { _ in
            throw APIError.network("No se llega al servidor.")
        }
        await model.waitForPending()
        XCTAssertEqual(model.phase, .failed("No se llega al servidor."))
        XCTAssertTrue(model.results.isEmpty)
    }

    // MARK: - R35, R36 · horario y días como se definieron

    func testR35EtiquetaHorario() throws {
        XCTAssertEqual(RouteText.scheduleLabel(mode: .arrival, at: "09:00", from: "07:13", to: "09:15"), "llego 09:00")
        XCTAssertEqual(RouteText.scheduleLabel(mode: .departure, at: "08:00", from: "07:15", to: "09:30"), "salgo 08:00")
        XCTAssertEqual(RouteText.scheduleLabel(mode: .window, at: "", from: "07:00", to: "10:00"), "07:00–10:00")
        // Sin hora, lo que haya de franja.
        XCTAssertEqual(RouteText.scheduleLabel(mode: .arrival, at: "", from: "07:00", to: "10:00"), "07:00–10:00")
        // Lo mismo que dice el modelo para cada ruta guardada.
        for r in routes {
            XCTAssertEqual(RouteText.scheduleLabel(mode: r.timeMode, at: r.timeAt, from: r.timeFrom, to: r.timeTo),
                           r.scheduleLabel)
        }
        XCTAssertEqual(RouteText.summary(try route(3)), "entre semana · llego 09:00")
        XCTAssertEqual(RouteText.summary(try route(4)), "todos los días · 17:00–20:00")
        XCTAssertEqual(RouteText.summary(try route(5)), "fin de semana · salgo 10:30")
        XCTAssertEqual(RouteText.summary(try route(6)), "M J · salgo 21:00")
        XCTAssertEqual(RouteText.spokenSchedule(mode: .arrival, at: "09:00", from: "", to: ""), "llego a las 09:00")
        XCTAssertEqual(RouteText.spokenSchedule(mode: .window, at: "", from: "07:00", to: "10:00"), "de 07:00 a 10:00")
    }

    func testR36EtiquetaDias() {
        XCTAssertEqual(RouteText.daysLabel(Set(0...4)), "entre semana")
        XCTAssertEqual(RouteText.daysLabel([5, 6]), "fin de semana")
        XCTAssertEqual(RouteText.daysLabel(Set(0...6)), "todos los días")
        XCTAssertEqual(RouteText.daysLabel([4, 0, 2]), "L X V")
        XCTAssertEqual(RouteText.daysLabel([6]), "D")
        for r in routes {
            XCTAssertEqual(RouteText.daysLabel(Set(r.days)), r.daysLabel)
        }
        // VoiceOver: 0 = lunes.
        XCTAssertEqual(RouteText.spokenDays([1, 3]), "martes y jueves")
        XCTAssertEqual(RouteText.spokenDays([4, 0, 2]), "lunes, miércoles y viernes")
        XCTAssertEqual(RouteText.spokenDays([0, 1, 2, 3, 4]), "entre semana")
        XCTAssertEqual(RouteText.spokenDays([]), "ningún día")
        XCTAssertEqual(RouteText.spokenDays([9]), "ningún día")
    }

    func testR36RutaNuevaLunesAViernesLlegoALasNueve() {
        let state = RouteEditorState(route: nil)
        XCTAssertEqual(state.days, Set(0...4))
        XCTAssertEqual(state.timeMode, .arrival)
        XCTAssertEqual(state.timeAt, "09:00")
        XCTAssertEqual(state.timeFrom, "07:00")
        XCTAssertEqual(state.timeTo, "10:00")
        XCTAssertTrue(state.legs.isEmpty)
        XCTAssertNil(state.draft())
    }

    func testR36R50TarjetaDeRutaParaVoiceOver() throws {
        let spoken = RouteText.spoken(try route(6), isActive: false)
        XCTAssertTrue(spoken.hasPrefix("Vuelta de clase."))
        XCTAssertTrue(spoken.contains("de Châtelet - Les Halles a Nanterre - Préfecture"))
        XCTAssertTrue(spoken.contains("martes y jueves"))
        XCTAssertTrue(spoken.contains("salgo a las 21:00"))
        XCTAssertTrue(spoken.contains("línea A"))
        XCTAssertFalse(spoken.contains("toca ahora"))
        XCTAssertTrue(RouteText.spoken(try route(3), isActive: true).contains("es la que toca ahora"))
        XCTAssertTrue(RouteText.spoken(try route(3), isActive: true).contains("líneas 6424, T2, E, 13 y 147"))
    }

    // MARK: - R38 · la franja que calcula el servidor

    func testR38FranjaDerivada() {
        XCTAssertEqual(RouteText.derivedWindow(mode: .arrival, at: "09:00", durationMin: 62),
                       TimeWindow(from: "07:13", to: "09:15"))
        XCTAssertEqual(RouteText.derivedWindow(mode: .departure, at: "08:00", durationMin: 0),
                       TimeWindow(from: "07:15", to: "09:30"))
        // Sin cruzar la medianoche.
        XCTAssertEqual(RouteText.derivedWindow(mode: .arrival, at: "00:30", durationMin: 60),
                       TimeWindow(from: "00:00", to: "00:45"))
        XCTAssertEqual(RouteText.derivedWindow(mode: .departure, at: "23:30", durationMin: 60),
                       TimeWindow(from: "22:45", to: "23:59"))
        XCTAssertNil(RouteText.derivedWindow(mode: .window, at: "09:00", durationMin: 30))
        XCTAssertNil(RouteText.derivedWindow(mode: .arrival, at: "", durationMin: 30))
    }

    func testR38TextoDeSalgoACuentaLaMediaHoraTrasLlegar() {
        let departure = RouteText.windowExplanation(mode: .departure, at: "08:00", durationMin: 0)
        XCTAssertTrue(departure.contains("30 min después de llegar"))
        XCTAssertTrue(departure.contains("de 07:15 a 09:30"))
        XCTAssertTrue(departure.contains("1 h"))
        let arrival = RouteText.windowExplanation(mode: .arrival, at: "09:00", durationMin: 62)
        XCTAssertTrue(arrival.contains("62 min"))
        XCTAssertTrue(arrival.contains("de 07:13 a 09:15"))
    }

    func testHorasHHMM() throws {
        XCTAssertEqual(ClockTime.minutes("09:00"), 540)
        XCTAssertEqual(ClockTime.minutes("9:05"), 545)
        XCTAssertEqual(ClockTime.minutes("23:59"), 1439)
        XCTAssertNil(ClockTime.minutes("24:00"))
        XCTAssertNil(ClockTime.minutes("09:60"))
        XCTAssertNil(ClockTime.minutes("+9:00"))
        XCTAssertNil(ClockTime.minutes("0900"))
        XCTAssertNil(ClockTime.minutes(""))
        XCTAssertEqual(ClockTime.text(minutes: 433), "07:13")
        XCTAssertEqual(ClockTime.text(minutes: -5), "00:00")
        XCTAssertEqual(ClockTime.text(minutes: 2000), "23:59")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let day = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let date = ClockTime.date("07:13", calendar: calendar, on: day)
        XCTAssertEqual(ClockTime.text(from: date, calendar: calendar), "07:13")
    }

    // MARK: - RouteInput desde el editor

    func testRouteInputSinCambiosEsLaMismaRuta() {
        // Editar y guardar sin tocar nada manda la ruta tal cual (PUT).
        for r in routes {
            XCTAssertEqual(RouteEditorState(route: r).draft(), RouteDraft(r), "ruta \(r.id)")
        }
    }

    func testRouteInputNuevaSaleDeLosTramos() throws {
        let stop = try XCTUnwrap(stops.first)
        let line = try XCTUnwrap(stop.lines.first)
        var state = RouteEditorState(route: nil)
        state.name = "  Casa  "
        state.addLeg(LegBuilderLogic.leg(stop: stop, line: line, chosen: ["Ermont - Eaubonne"],
                                         available: ["Ermont - Eaubonne", "Mantes-la-Jolie"]))

        let draft = try XCTUnwrap(state.draft())
        XCTAssertEqual(draft.name, "Casa")
        XCTAssertEqual(draft.originId, "stop_area:IDFM:71370")
        XCTAssertEqual(draft.originName, "Gare Saint-Lazare")
        // Sin bajada: la parada del último tramo y su primer sentido (F35).
        XCTAssertEqual(draft.destId, "stop_area:IDFM:71370")
        XCTAssertEqual(draft.destName, "Ermont - Eaubonne")
        XCTAssertEqual(draft.days, [0, 1, 2, 3, 4])
        XCTAssertEqual(draft.timeMode, .arrival)
        XCTAssertEqual(draft.timeAt, "09:00")
        XCTAssertEqual(draft.durationMin, 0)
        XCTAssertEqual(draft.position, 0)
        XCTAssertEqual(draft.legs.count, 1)
        XCTAssertEqual(draft.legs.first?.lineId, "line:IDFM:C01739")
        XCTAssertEqual(draft.legs.first?.lineCode, "J")
        XCTAssertEqual(draft.legs.first?.fromId, "stop_area:IDFM:71370")
        XCTAssertEqual(draft.legs.first?.toId, "")
        XCTAssertEqual(draft.legs.first?.directions, ["Ermont - Eaubonne"])

        // Lo que viaja: snake_case y los campos obligatorios del contrato.
        let data = try JSONEncoder.trajet.encode(draft)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["origin_id"] as? String, "stop_area:IDFM:71370")
        XCTAssertEqual(json["dest_name"] as? String, "Ermont - Eaubonne")
        XCTAssertEqual(json["time_mode"] as? String, "arrival")
        XCTAssertEqual(json["time_at"] as? String, "09:00")
        XCTAssertEqual(json["days"] as? [Int], [0, 1, 2, 3, 4])
        let legs = try XCTUnwrap(json["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.first?["line_id"] as? String, "line:IDFM:C01739")
        XCTAssertEqual(legs.first?["from_id"] as? String, "stop_area:IDFM:71370")
        XCTAssertEqual(legs.first?["directions"] as? [String], ["Ermont - Eaubonne"])
    }

    func testRouteInputFranjaSinHoraYDiasOrdenados() throws {
        var state = RouteEditorState(route: try route(5))
        state.timeMode = .window
        state.timeFrom = "06:30"
        state.timeTo = "08:00"
        state.toggleDay(0)
        state.toggleDay(6)
        let draft = try XCTUnwrap(state.draft())
        XCTAssertEqual(draft.timeMode, .window)
        XCTAssertEqual(draft.timeAt, "")
        XCTAssertEqual(draft.timeFrom, "06:30")
        XCTAssertEqual(draft.timeTo, "08:00")
        XCTAssertEqual(draft.days, [0, 5])
        XCTAssertEqual(draft.position, 2)
    }

    func testEditorDiceLoQueFalta() {
        var state = RouteEditorState(route: nil)
        XCTAssertEqual(state.problems, [.name, .legs])
        XCTAssertEqual(state.problemsText, "Para guardar falta el nombre y al menos un tramo.")
        state.name = "Casa"
        state.days = []
        XCTAssertEqual(state.problems, [.days, .legs])
        state.timeMode = .window
        state.timeFrom = "10:00"
        state.timeTo = "09:00"
        XCTAssertTrue(state.problems.contains(.window))
        XCTAssertFalse(state.canSave)
        XCTAssertNil(state.draft())
    }

    func testOrigenPropioSeConservaAlCambiarTramos() throws {
        // Casa → Trabajo sale de una dirección (planificador), no de una parada.
        var state = RouteEditorState(route: try route(3))
        XCTAssertEqual(state.originID, "2.24731;48.92644")
        XCTAssertEqual(state.originName, "6 Rue de la Marseillaise")
        state.removeLeg(at: 0)
        let draft = try XCTUnwrap(state.draft())
        XCTAssertEqual(draft.originId, "2.24731;48.92644")
        XCTAssertEqual(draft.originName, "6 Rue de la Marseillaise")
        XCTAssertEqual(draft.destId, "2.40452;48.89217")
        XCTAssertEqual(draft.legs.count, 4)
        XCTAssertEqual(draft.durationMin, 62)
    }

    func testOrigenQueSaleDeLosTramosLosSigue() throws {
        var state = RouteEditorState(route: try route(5))
        XCTAssertEqual(state.originID, "")
        XCTAssertEqual(state.originName, "")
        let other = try XCTUnwrap(stops.first { $0.name == "Argenteuil" })
        let line = PreviewData.decode(PreviewData.stopLinesJSON, as: StopLinesResponse.self).lines[2]
        state.removeLeg(at: 0)
        state.addLeg(LegBuilderLogic.leg(stop: other, line: line, chosen: [], available: []))
        let draft = try XCTUnwrap(state.draft())
        XCTAssertEqual(draft.originId, "stop_area:IDFM:65063")
        XCTAssertEqual(draft.originName, "Argenteuil")
        XCTAssertEqual(draft.destName, "Argenteuil")
    }

    // MARK: - R32, R62 · montar un tramo

    func testR62LasLineasNoSeReordenan() throws {
        let loaded = PreviewData.decode(PreviewData.stopLinesJSON, as: StopLinesResponse.self).lines
        XCTAssertEqual(LegBuilderLogic.lines(loaded: loaded, fallback: []).map(\.code), ["14", "E", "J", "272"])
        // F37: si falla o viene vacía, las del buscador (sin las que no tienen id).
        let fallback = try XCTUnwrap(stops.first).lines
        XCTAssertEqual(LegBuilderLogic.lines(loaded: [], fallback: fallback).map(\.id),
                       ["line:IDFM:C01739", "line:IDFM:C01384"])
        XCTAssertEqual(LegBuilderLogic.lines(loaded: nil, fallback: fallback).count, 2)
        XCTAssertEqual(LegBuilderLogic.lineSubtitle(loaded[0]), "Métro")
    }

    func testR32SentidoSeEligeDeLista() throws {
        let stop = try XCTUnwrap(stops.first)
        let line = try XCTUnwrap(stop.lines.first)
        let available = PreviewData.decode(PreviewData.directionsJSON, as: DirectionsResponse.self).directions
        // Solo de los que circulan, en el orden del servidor.
        let leg = LegBuilderLogic.leg(stop: stop, line: line, chosen: ["Gisors", "Inventado", "Ermont - Eaubonne"],
                                      available: available)
        XCTAssertEqual(leg.directions, ["Ermont - Eaubonne", "Gisors"])
        // Sin elegir ninguno = todos, y se avisa.
        let all = LegBuilderLogic.leg(stop: stop, line: line, chosen: [], available: available)
        XCTAssertEqual(all.directions, [])
        XCTAssertEqual(RouteText.direction(all.directions), "todos los sentidos")
        XCTAssertEqual(RouteText.direction(["Ermont - Eaubonne", "Gisors"]), "dirección Ermont - Eaubonne · Gisors")
        XCTAssertEqual(LegBuilderLogic.directionsHeader(available), "Sentidos que circulan ahora")
        XCTAssertEqual(LegBuilderLogic.directionsHeader([]), "Ahora mismo no circula nada por aquí")
        XCTAssertTrue(LegBuilderLogic.allDirectionsFooter.contains("en los dos sentidos"))

        var state = RouteEditorState(route: nil)
        state.addLeg(leg)
        state.addLeg(all)
        XCTAssertEqual(state.legsWithoutDirection.count, 1)
        XCTAssertEqual(RouteEditorState(route: try route(3)).legsWithoutDirection.map(\.lineCode), ["13"])
    }

    // MARK: - Orden de las rutas

    func testOrdenDeLasRutas() {
        XCTAssertEqual(RouteOrdering.move([3, 4, 5, 6], from: IndexSet(integer: 2), to: 0), [5, 3, 4, 6])
        XCTAssertEqual(RouteOrdering.move([3, 4, 5, 6], from: IndexSet(integer: 0), to: 2), [4, 3, 5, 6])
        XCTAssertEqual(RouteOrdering.move([3, 4, 5, 6], from: IndexSet(integer: 0), to: 4), [4, 5, 6, 3])
        XCTAssertEqual(RouteOrdering.move([3, 4, 5, 6], from: IndexSet([0, 1]), to: 4), [5, 6, 3, 4])
        XCTAssertEqual(RouteOrdering.move([3, 4], from: IndexSet(integer: 7), to: 0), [3, 4])

        // Las rutas de prueba tienen position 0, 1, 2, 3: solo cambian las que se mueven.
        XCTAssertEqual(RouteOrdering.updates(routes: routes, order: [5, 3, 4, 6]),
                       [RouteOrdering.Update(id: 5, position: 0),
                        RouteOrdering.Update(id: 3, position: 1),
                        RouteOrdering.Update(id: 4, position: 2)])
        XCTAssertEqual(RouteOrdering.updates(routes: routes, order: [3, 4, 5, 6]), [])
    }

    // MARK: - R34 · planificador

    @MainActor
    func testR34PlanModoArrivalDeparture() async throws {
        let places = self.places
        let model = PlannerModel()
        XCTAssertFalse(model.canSearch)
        model.from = places[1]
        model.to = places[1]
        XCTAssertFalse(model.canSearch, "Mismo origen y destino")
        model.to = places[0]
        XCTAssertTrue(model.canSearch)
        XCTAssertEqual(model.timing, .arrival)
        XCTAssertEqual(model.time, "09:00")

        let log = PlanLog()
        let plan = PreviewData.plan
        let fetch: PlannerModel.Fetch = { from, to, when, mode in
            await log.add(PlanCall(from: from, to: to, when: when, mode: mode))
            return plan
        }
        await model.search(fetch)
        model.timing = .departure
        model.time = "08:30"
        await model.search(fetch)
        model.timing = .now
        await model.search(fetch)

        let calls = await log.values
        XCTAssertEqual(calls, [
            PlanCall(from: "2.25212;48.94702", to: "stop_area:IDFM:71370", when: "09:00", mode: .arrival),
            PlanCall(from: "2.25212;48.94702", to: "stop_area:IDFM:71370", when: "08:30", mode: .departure),
            PlanCall(from: "2.25212;48.94702", to: "stop_area:IDFM:71370", when: nil, mode: .departure),
        ])
        guard case .loaded(let reply, let search) = model.phase else {
            return XCTFail("Tenía que haber opciones")
        }
        XCTAssertEqual(reply.options.count, 3)
        XCTAssertEqual(search.heading, "Saliendo ahora")

        model.swapEnds()
        XCTAssertEqual(model.from?.id, "stop_area:IDFM:71370")
        XCTAssertEqual(model.to?.id, "2.25212;48.94702")
    }

    @MainActor
    func testR34PlanSinOpcionesY404() async {
        let places = self.places
        let model = PlannerModel()
        model.from = places[0]
        model.to = places[2]
        let empty = PreviewData.decode(#"{"options": [], "age": 0}"#, as: PlanResponse.self)
        await model.search { _, _, _, _ in empty }
        guard case .empty = model.phase else { return XCTFail("Sin opciones es «ningún trayecto»") }
        await model.search { _, _, _, _ in throw APIError.notFound }
        guard case .empty = model.phase else { return XCTFail("Un 404 es «ningún trayecto», no un error") }
        await model.search { _, _, _, _ in throw APIError.network("No se llega al servidor.") }
        XCTAssertEqual(model.phase, .failed("No se llega al servidor."))
    }

    func testF42RotuloDeLaBusquedaHecha() {
        let places = self.places
        var search = PlannerSearch(from: places[1], to: places[0], timing: .arrival, time: "09:00")
        XCTAssertEqual(search.heading, "Para llegar a las 09:00")
        XCTAssertEqual(search.apiWhen, "09:00")
        XCTAssertEqual(search.apiMode, .arrival)
        search.timing = .departure
        XCTAssertEqual(search.heading, "Saliendo a las 09:00")
        XCTAssertEqual(search.apiMode, .departure)
        search.timing = .now
        XCTAssertEqual(search.heading, "Saliendo ahora")
        XCTAssertNil(search.apiWhen)
        XCTAssertEqual(search.apiMode, .departure)
    }

    // MARK: - R33 · guardar desde el planificador

    func testR33AvisaTramosSinSentido() {
        XCTAssertNil(PlannerText.withoutDirection([]))
        XCTAssertNil(PlannerText.withoutDirection(["", " "]))
        let one = PlannerText.withoutDirection(["13"])
        XCTAssertEqual(one?.hasPrefix("La línea 13 se ha guardado sin sentido"), true)
        XCTAssertEqual(one?.contains("en los dos sentidos"), true)
        let two = PlannerText.withoutDirection(["13", "E"])
        XCTAssertEqual(two?.hasPrefix("Las líneas 13 y E se han guardado sin sentido"), true)
        // El servidor lo dice en `without_direction`.
        let saved = PreviewData.decode(PreviewData.planSavedWithoutDirectionJSON, as: PlanSaveResponse.self)
        XCTAssertNotNil(PlannerText.withoutDirection(saved.withoutDirection))
        let clean = PreviewData.decode(PreviewData.planSavedJSON, as: PlanSaveResponse.self)
        XCTAssertNil(PlannerText.withoutDirection(clean.withoutDirection))
    }

    func testR33R34R35MetaAlGuardarDesdeElPlanificador() throws {
        let places = self.places
        let option = try XCTUnwrap(PreviewData.planOptions.first)
        let arrival = PlannerSearch(from: places[1], to: places[0], timing: .arrival, time: "09:00")
        let meta = PlannerText.saveMeta(search: arrival, option: option, name: "  ", days: [4, 0, 2])
        XCTAssertEqual(meta.name, "12 Rue de Paris → Gare Saint-Lazare")
        XCTAssertEqual(meta.originId, "2.25212;48.94702")
        XCTAssertEqual(meta.originName, "12 Rue de Paris")
        XCTAssertEqual(meta.destId, "stop_area:IDFM:71370")
        XCTAssertEqual(meta.destName, "Gare Saint-Lazare")
        XCTAssertEqual(meta.days, [0, 2, 4])
        XCTAssertEqual(meta.timeMode, .arrival)
        XCTAssertEqual(meta.timeAt, "09:00")
        XCTAssertEqual(PlannerText.saveExplanation(meta: meta, option: option),
                       "Se guardará como «llego 09:00», y la franja se calculará con los 47 min que dura: de 07:28 a 09:15.")

        let departure = PlannerSearch(from: places[1], to: places[0], timing: .departure, time: "08:00")
        let named = PlannerText.saveMeta(search: departure, option: option, name: " Al trabajo ", days: [0])
        XCTAssertEqual(named.name, "Al trabajo")
        XCTAssertEqual(named.timeMode, .departure)
        XCTAssertEqual(named.timeAt, "08:00")

        // «Ahora» se guarda como «salgo a» la hora a la que sale la opción.
        let now = PlannerSearch(from: places[1], to: places[0], timing: .now, time: "09:00")
        let meta3 = PlannerText.saveMeta(search: now, option: option, name: "", days: [0])
        XCTAssertEqual(meta3.timeMode, .departure)
        XCTAssertEqual(meta3.timeAt, "08:07")
    }

    func testR6R56TextosDelPlanificador() throws {
        let options = PreviewData.planOptions
        XCTAssertEqual(PlannerText.summary(options[0]), "1 transbordo · 11 min a pie")
        XCTAssertEqual(PlannerText.summary(options[1]), "directo · 6 min a pie")
        XCTAssertEqual(PlannerText.summary(options[2]), "2 transbordos · 3 min a pie")
        XCTAssertEqual(PlannerText.times(options[0]), "08:07 → 08:54")
        XCTAssertEqual(PlannerText.kind("best"), "Recomendado")
        XCTAssertEqual(PlannerText.kind("less_fallback"), "Menos a pie")
        XCTAssertEqual(PlannerText.kind("less_walk"), "Menos a pie")
        XCTAssertEqual(PlannerText.kind("comfort"), "Más cómodo")
        XCTAssertEqual(PlannerText.kind("rapid"), "Más rápido")
        XCTAssertNil(PlannerText.kind("non_pt_walk"))
        let firstLeg = try XCTUnwrap(options[0].legs.first)
        XCTAssertEqual(PlannerText.legDetail(firstLeg), "17 min · sale 08:12")
        XCTAssertEqual(PlannerText.legTitle(firstLeg), "dirección Paris Saint-Lazare")
        let long = PreviewData.decode(#"{"line_code": "6424", "minutes": 106, "at": "08:12"}"#, as: PlanLeg.self)
        XCTAssertEqual(PlannerText.legDetail(long), "1h46 · sale 08:12")
        let spoken = PlannerText.spoken(options[0])
        XCTAssertTrue(spoken.hasPrefix("47 minutos, recomendado, sale a las 08:07, llega a las 08:54, 1 transbordo"))
        XCTAssertTrue(spoken.contains("línea J desde Argenteuil dirección Paris Saint-Lazare"))
        XCTAssertEqual(SearchText.placeSubtitle(places[1]), "dirección · Argenteuil")
    }
}

// MARK: - Ayudas

private actor StringLog {
    private(set) var values: [String] = []
    func add(_ value: String) { values.append(value) }
}

private actor DurationLog {
    private(set) var values: [Duration] = []
    func add(_ value: Duration) { values.append(value) }
}

private struct PlanCall: Equatable, Sendable {
    var from: String
    var to: String
    var when: String?
    var mode: TimeMode
}

private actor PlanLog {
    private(set) var values: [PlanCall] = []
    func add(_ value: PlanCall) { values.append(value) }
}
