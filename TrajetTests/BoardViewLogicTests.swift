import XCTest
@testable import Trajet

/// La lógica del tablero que no es vista (Views/Board/BoardViewLogic.swift y
/// piezas de Views/Common): qué se dice, qué se enseña y cuándo. Cada test
/// lleva en el nombre las reglas que cubre (docs/reglas.md).
final class BoardViewLogicTests: XCTestCase {

    /// Un instante redondo: las restas de segundos salen exactas.
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func firstDeparture(_ c: PreviewData.BoardCase, leg index: Int = 0,
                                departure: Int = 0) throws -> (Departure, Leg) {
        let board = PreviewData.board(c)
        let leg = try XCTUnwrap(board.legs.indices.contains(index) ? board.legs[index] : nil)
        let dep = try XCTUnwrap(leg.departures.indices.contains(departure) ? leg.departures[departure] : nil)
        return (dep, leg)
    }

    private func rerLeg(_ departures: [Departure] = [], platformExpected: Bool? = nil) -> Leg {
        Leg(seq: 0, lineCode: "E", lineMode: "RER", fromName: "Haussmann Saint-Lazare",
            toName: "Chelles - Gournay", directions: ["Chelles - Gournay"],
            departures: departures, platformExpected: platformExpected)
    }

    private var guess21: PlatformGuess {
        PlatformGuess(platform: "21", share: 0.9, samples: 20, basis: "mision", why: "por el número de tren")
    }

    // MARK: - R50 · VoiceOver: una frase por salida

    func testR50R5FraseCompletaConViaYLongitud() throws {
        let (dep, leg) = try firstDeparture(.viaAparece)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg),
                       "Tren a Ermont - Eaubonne, en 7 minutos, a las 12:57, vía 21, tren largo.")
    }

    func testR50R2FraseDeViaRecienPublicada() throws {
        let (dep, leg) = try firstDeparture(.viaAparece)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg, isNewPlatform: true),
                       "Tren a Ermont - Eaubonne, en 7 minutos, a las 12:57, acaba de salir la vía 21, tren largo.")
    }

    func testR50R49FraseDeViaProbable() throws {
        let (dep, leg) = try firstDeparture(.viaProbable)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg),
                       "Tren a Ermont - Eaubonne, en 7 minutos, a las 12:57, vía 21 probable, 90 por ciento sobre 20 observaciones, por el número de tren, tren largo.")
    }

    func testR50R6R14ConcordanciaEnHorasYRetraso() throws {
        let (n3, bus) = try firstDeparture(.bus106, departure: 2)
        XCTAssertEqual(BoardSpeech.sentence(n3, leg: bus),
                       "Bus a Sartrouville RER, en 1 hora y 46 minutos, a las 14:36, 11 minutos de retraso.")
        let (n2, _) = try firstDeparture(.bus106, departure: 1)
        XCTAssertEqual(BoardSpeech.sentence(n2, leg: bus), "Bus a Sartrouville RER, en 1 hora, a las 13:50.")
        let (n4, _) = try firstDeparture(.bus106, departure: 3)
        XCTAssertTrue(BoardSpeech.sentence(n4, leg: bus).contains("en 2 horas y 45 minutos"))
    }

    func testR50R15ParadoEnElAndenSinHora() throws {
        let (dep, leg) = try firstDeparture(.enAnden)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg),
                       "Tren a Ermont - Eaubonne, parado en el andén, vía 21, tren largo.")
    }

    func testR50R14AdelantoEnSingular() throws {
        let (dep, leg) = try firstDeparture(.casosLimite)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg),
                       "Tren a Chelles - Gournay, en 1 minuto, a las 12:51, 1 minuto de adelanto, vía 9, tren corto.")
    }

    func testR50R3MetroSinVia() throws {
        let (dep, leg) = try firstDeparture(.cincoTramos, leg: 3, departure: 1)
        XCTAssertEqual(BoardSpeech.sentence(dep, leg: leg), "Metro a Les Courtilles, en 3 minutos, a las 12:53.")
    }

    func testR50SuprimidoYSaleYa() {
        let cancelled = Departure(minutes: 5, at: "12:55", destination: "Poissy", status: "cancelled")
        XCTAssertEqual(BoardSpeech.sentence(cancelled, leg: rerLeg()),
                       "Tren a Poissy, suprimido, en 5 minutos, a las 12:55.")
        let now = Departure(minutes: 0, at: "12:50", destination: "Poissy")
        XCTAssertEqual(BoardSpeech.sentence(now, leg: rerLeg()), "Tren a Poissy, sale ya.")
    }

    func testR50ModoDesconocidoYSinDestino() {
        let funicular = Leg(seq: 0, lineCode: "FUN", lineMode: "Funicular")
        XCTAssertEqual(BoardSpeech.sentence(Departure(minutes: 4, destination: "Sacré-Cœur"), leg: funicular),
                       "Hacia Sacré-Cœur, en 4 minutos.")
        XCTAssertEqual(BoardSpeech.sentence(Departure(minutes: 4), leg: funicular), "Salida, en 4 minutos.")
    }

    func testR50R6DuracionesYAntiguedadDichas() {
        XCTAssertEqual(BoardSpeech.duration(minutes: 1), "1 minuto")
        XCTAssertEqual(BoardSpeech.duration(minutes: 6), "6 minutos")
        XCTAssertEqual(BoardSpeech.duration(minutes: 60), "1 hora")
        XCTAssertEqual(BoardSpeech.duration(minutes: 61), "1 hora y 1 minuto")
        XCTAssertEqual(BoardSpeech.duration(minutes: 106), "1 hora y 46 minutos")
        XCTAssertEqual(BoardSpeech.duration(minutes: 121), "2 horas y 1 minuto")
        XCTAssertEqual(BoardSpeech.age(1), "1 segundo")
        XCTAssertEqual(BoardSpeech.age(10), "10 segundos")
        XCTAssertEqual(BoardSpeech.age(240), "4 minutos")
        XCTAssertEqual(BoardSpeech.age(7200), "2 horas")
    }

    // MARK: - R4 · R14 · retraso

    func testR4SinHoraTeoricaNoHayRetraso() {
        let metro = Departure(minutes: 5, at: "12:55", aimedAt: "", destination: "Gallieni", delay: 5)
        XCTAssertNil(BoardText.visibleDelay(metro))
        XCTAssertNil(BoardText.delay(metro))
        XCTAssertFalse(BoardSpeech.sentence(metro, leg: rerLeg()).contains("retraso"))
    }

    func testR14RetrasoCeroNoSePintaYConSigno() throws {
        let (zero, _) = try firstDeparture(.casosLimite, departure: 1)
        XCTAssertNil(BoardText.delay(zero))
        let (early, _) = try firstDeparture(.casosLimite)
        XCTAssertEqual(BoardText.delay(early), "-1 min")
        let (late, _) = try firstDeparture(.bus106)
        XCTAssertEqual(BoardText.delay(late), "+2 min")
    }

    // MARK: - R6 · R15 · R16 · momento y ritmo

    func testR6MinutosLargos() {
        XCTAssertEqual(DepartureMoment(Departure(minutes: 106)).text, "1h46")
        XCTAssertNil(DepartureMoment(Departure(minutes: 106)).unit)
        XCTAssertEqual(DepartureMoment(Departure(minutes: 60)).text, "1h")
        XCTAssertEqual(DepartureMoment(Departure(minutes: 59)).text, "59")
        XCTAssertEqual(DepartureMoment(Departure(minutes: 59)).unit, "min")
    }

    func testR15EnAndenDistintoDeYa() {
        let atStop = Departure(minutes: 0, atStop: true)
        let zero = Departure(minutes: 0)
        XCTAssertEqual(DepartureMoment(atStop).text, "En andén")
        XCTAssertEqual(DepartureMoment(zero).text, "ya")
        XCTAssertNil(BoardText.paceLabel(for: atStop))
        XCTAssertEqual(BoardText.paceLabel(for: zero), "Corre")
        XCTAssertEqual(BoardSpeech.moment(atStop), "parado en el andén")
        XCTAssertEqual(BoardSpeech.moment(zero), "sale ya")
    }

    func testR16RitmoCorroAndoConCalma() {
        XCTAssertEqual(BoardText.paceLabel(for: Departure(minutes: 3)), "Corre")
        XCTAssertEqual(BoardText.paceLabel(for: Departure(minutes: 4)), "Anda")
        XCTAssertEqual(BoardText.paceLabel(for: Departure(minutes: 8)), "Anda")
        XCTAssertEqual(BoardText.paceLabel(for: Departure(minutes: 9)), "Con calma")
        XCTAssertEqual(BoardText.pace(.run), "Corre")
        XCTAssertEqual(BoardText.pace(.walk), "Anda")
        XCTAssertEqual(BoardText.pace(.easy), "Con calma")
    }

    func testR5LongitudDelTren() {
        XCTAssertEqual(BoardText.length(.short), "corto")
        XCTAssertEqual(BoardText.length(.long), "largo")
    }

    // MARK: - R2 · R3 · R10 · la vía

    func testR3MetroBusTranviaSinHuecoDeVia() {
        let withEverything = Departure(minutes: 3, platform: "2", guess: guess21)
        let metro = Leg(seq: 0, lineCode: "13", lineMode: "Métro", departures: [withEverything])
        let bus = Leg(seq: 0, lineCode: "147", lineMode: "Bus", departures: [withEverything])
        let tram = Leg(seq: 0, lineCode: "T2", lineMode: "Tramway", departures: [withEverything])
        for leg in [metro, bus, tram] {
            XCTAssertEqual(BoardPlatformState(departure: withEverything, leg: leg), .none)
            XCTAssertNil(BoardSpeech.platform(BoardPlatformState(departure: withEverything, leg: leg), isNew: false))
        }
        // Manda `platform_expected` del servidor, no el modo.
        XCTAssertEqual(BoardPlatformState(departure: withEverything, leg: rerLeg(platformExpected: false)), .none)
        XCTAssertEqual(BoardPlatformState(departure: withEverything, leg: Leg(seq: 0, lineCode: "X", lineMode: "Bus",
                                                                              platformExpected: true)),
                       .real("2"))
    }

    func testR10RealManda_ProbableSoloSinReal() {
        let leg = rerLeg()
        XCTAssertEqual(BoardPlatformState(departure: Departure(minutes: 3, platform: "21", guess: guess21), leg: leg),
                       .real("21"))
        XCTAssertEqual(BoardPlatformState(departure: Departure(minutes: 3, platform: "", guess: guess21), leg: leg),
                       .probable(guess21))
        XCTAssertEqual(BoardPlatformState(departure: Departure(minutes: 3, guess: guess21), leg: leg).guess, guess21)
    }

    func testR2SinViaNiPrevisionNoHayHueco() {
        let leg = rerLeg()
        XCTAssertTrue(BoardPlatformState(departure: Departure(minutes: 3), leg: leg).isNone)
        var emptyGuess = guess21
        emptyGuess.platform = ""
        XCTAssertTrue(BoardPlatformState(departure: Departure(minutes: 3, guess: emptyGuess), leg: leg).isNone)
    }

    func testR2ViaNuevaDuranteVeinticincoSegundos() {
        let dep = Departure(jid: "j1", minutes: 7, platform: "21", platformNew: false)
        let leg = rerLeg([dep])
        let event = PlatformEvent(id: UUID(), legSeq: 0, departureID: "j1", platform: "21", previous: nil,
                                  at: t0.addingTimeInterval(-10))
        XCTAssertTrue(BoardPlatformState.isNew(departure: dep, leg: leg, event: event, receivedAt: t0,
                                               now: t0, live: true))
        XCTAssertFalse(BoardPlatformState.isNew(departure: dep, leg: leg, event: event, receivedAt: t0,
                                                now: t0.addingTimeInterval(16), live: true))
        // Otra vía (ha cambiado desde el evento): no es la nueva.
        let other = PlatformEvent(id: UUID(), legSeq: 0, departureID: "j1", platform: "19", previous: nil, at: t0)
        XCTAssertFalse(BoardPlatformState.isNew(departure: dep, leg: leg, event: other, receivedAt: t0,
                                                now: t0, live: true))
    }

    func testR2PlatformNewDelServidorYNadaConElDatoViejo() {
        let dep = Departure(jid: "j1", minutes: 7, platform: "21", platformNew: true)
        let leg = rerLeg([dep])
        XCTAssertTrue(BoardPlatformState.isNew(departure: dep, leg: leg, event: nil,
                                               receivedAt: t0.addingTimeInterval(-5), now: t0, live: true))
        XCTAssertFalse(BoardPlatformState.isNew(departure: dep, leg: leg, event: nil,
                                                receivedAt: t0.addingTimeInterval(-30), now: t0, live: true))
        // R19 · ajustes A3: con el tablero apagado no late.
        XCTAssertFalse(BoardPlatformState.isNew(departure: dep, leg: leg, event: nil,
                                                receivedAt: t0, now: t0, live: false))
        // Una probable nunca es «nueva».
        let probable = Departure(jid: "j2", minutes: 7, platformNew: true, guess: guess21)
        XCTAssertFalse(BoardPlatformState.isNew(departure: probable, leg: rerLeg([probable]), event: nil,
                                                receivedAt: t0, now: t0, live: true))
    }

    @MainActor
    func testR10R50EtiquetasDeLaVia() {
        XCTAssertEqual(BoardSpeech.platform(.real("21"), isNew: false), "vía 21")
        XCTAssertEqual(BoardSpeech.platform(.real("21"), isNew: true), "acaba de salir la vía 21")
        XCTAssertEqual(PlatformBadge.capitalizedFirst(BoardSpeech.platform(.probable(guess21), isNew: false) ?? ""),
                       "Vía 21 probable, 90 por ciento sobre 20 observaciones, por el número de tren")
    }

    // MARK: - R49 · la probable se explica

    func testR49ExplicaViaProbable() {
        XCTAssertEqual(BoardText.probableExplanation(guess21),
                       "Sale por la 21 el 90\u{00A0}% de las veces (20 observaciones, por el número de tren).")
        let one = PlatformGuess(platform: "7", share: 0.55, samples: 1, basis: "hora", why: "")
        XCTAssertEqual(BoardText.probableExplanation(one), "Sale por la 7 el 55\u{00A0}% de las veces (1 observación).")
        XCTAssertEqual(BoardText.percent(84), "84\u{00A0}%")
    }

    // MARK: - R24 · R47 · fichas y densidad

    func testR47DensidadPorTramos() {
        XCTAssertEqual(BoardDensity(legCount: 1), .roomy)
        XCTAssertEqual(BoardDensity(legCount: 2), .roomy)
        XCTAssertEqual(BoardDensity(legCount: 3), .regular)
        XCTAssertEqual(BoardDensity(legCount: 4), .regular)
        XCTAssertEqual(BoardDensity(legCount: 5), .compact)
        XCTAssertEqual(BoardDensity(legCount: 6), .compact)
        XCTAssertEqual(BoardDensity.roomy.ticketNumber, .ticket)
        XCTAssertEqual(BoardDensity.compact.ticketNumber, .ticketCompact)
        XCTAssertTrue(BoardDensity.regular.chipShowsSecondLine)
        XCTAssertFalse(BoardDensity.compact.chipShowsSecondLine)
    }

    func testR24DestinoSoloSiMezcla_TambienEnCompacto() throws {
        let (k2, mixed) = try firstDeparture(.destinosMezclados, departure: 1)
        XCTAssertTrue(mixed.mixesDestinations)
        XCTAssertEqual(BoardChipContent(departure: k2, leg: mixed, density: .roomy).destination, "Les Courtilles")
        XCTAssertNil(BoardChipContent(departure: k2, leg: mixed, density: .roomy).time)
        XCTAssertEqual(BoardChipContent(departure: k2, leg: mixed, density: .compact).destination, "Les Courtilles")
        XCTAssertEqual(BoardText.legSubtitle(mixed), "todos los sentidos")
    }

    func testR47R5R10FichaHolgadaYCompacta() throws {
        let (j2, legJ) = try firstDeparture(.tranquilo, leg: 1, departure: 1)
        let roomy = BoardChipContent(departure: j2, leg: legJ, density: .roomy)
        XCTAssertNil(roomy.destination)
        XCTAssertEqual(roomy.time, "13:21")
        XCTAssertEqual(roomy.length, .short)
        XCTAssertEqual(roomy.platform.guess?.platform, "21")
        let compact = BoardChipContent(departure: j2, leg: legJ, density: .compact)
        XCTAssertNil(compact.time)
        XCTAssertNil(compact.length)
        XCTAssertNil(compact.delay)
        // La vía no se quita nunca.
        XCTAssertEqual(compact.platform.guess?.platform, "21")
        XCTAssertEqual(BoardText.legSubtitle(legJ), "dirección Ermont - Eaubonne")
    }

    func testR24UnSoloDestinoNoEsMezcla() throws {
        let board = PreviewData.board(.casosLimite)
        let bus = board.legs[2]
        XCTAssertFalse(bus.mixesDestinations)
        XCTAssertEqual(BoardText.legSubtitle(bus), "dirección Gallieni - Pont de Bondy")
    }

    func testR14FichaSinRetrasoCero() throws {
        let (l2, leg) = try firstDeparture(.casosLimite, departure: 1)
        XCTAssertNil(BoardChipContent(departure: l2, leg: leg, density: .roomy).delay)
        let (l1, _) = try firstDeparture(.casosLimite)
        XCTAssertEqual(BoardChipContent(departure: l1, leg: leg, density: .roomy).delay, -1)
    }

    // MARK: - R25 · R26 · tramos vacíos y fallos de estación

    func testR25TramoVacioCortadoVsFinalizado() {
        let cut = PreviewData.board(.lineaCortada).legs[0]
        XCTAssertEqual(BoardLegEmpty(leg: cut), .suspended)
        XCTAssertEqual(BoardLegEmpty.suspended.title, "Sin circulación")
        XCTAssertEqual(BoardLegEmpty.suspended.subtitle, "no hay más salidas")
        XCTAssertEqual(BoardLegEmpty.suspended.detail, "La línea no está circulando.")
        let night = PreviewData.board(.tramoVacio).legs[0]
        XCTAssertEqual(BoardLegEmpty(leg: night), .finished)
        XCTAssertEqual(BoardLegEmpty.finished.title, "Servicio finalizado")
        XCTAssertEqual(BoardLegEmpty.finished.detail, "No quedan más salidas hoy.")
        XCTAssertNil(BoardLegEmpty(leg: PreviewData.board(.tranquilo).legs[0]))
    }

    func testR26EstacionCaidaNoTumbaElTablero() {
        let board = PreviewData.board(.casosLimite)
        let down = board.legs[3]
        XCTAssertEqual(BoardLegEmpty(leg: down), .stationDown)
        XCTAssertEqual(BoardText.stationError(for: down, in: board), "Parc de Bezons: tiempo de espera agotado")
        XCTAssertNil(BoardText.stationError(for: board.legs[0], in: board))
        XCTAssertEqual(BoardContentState.make(board: board, emptyMessage: nil, issue: nil), .board)
    }

    func testR26ErroresDeEstacionEnPie() {
        let board = PreviewData.board(.casosLimite)
        let errors = BoardText.stationErrors(board.errors)
        XCTAssertEqual(errors.shown.count, 3)
        XCTAssertEqual(errors.hidden, 2)
        XCTAssertEqual(BoardText.moreErrors(errors.hidden), "y 2 errores más")
        XCTAssertEqual(BoardText.moreErrors(1), "y 1 error más")
        XCTAssertNil(BoardText.moreErrors(0))
        let clean = BoardText.stationErrors(["", "  ", "Gallieni: respuesta vacía"])
        XCTAssertEqual(clean.shown, ["Gallieni: respuesta vacía"])
        XCTAssertEqual(clean.hidden, 0)
    }

    func testR9TramoConservadoDiceSuAntiguedad() {
        XCTAssertEqual(BoardText.retained(age: 184), "salidas de hace 3 min · la estación no responde")
    }

    // MARK: - R8 · R27 · R28 · avisos

    func testR8FrancesMientrasTraduce() throws {
        let cut = PreviewData.board(.cincoTramos).legs[3]
        let notice = try XCTUnwrap(BoardNotice(status: cut.status))
        XCTAssertEqual(notice.level, 2)
        XCTAssertEqual(notice.title, "Interrumpida")
        XCTAssertTrue(notice.translating)
        XCTAssertEqual(notice.lines.count, 1)
        XCTAssertTrue(notice.lines[0].isFrench)
        XCTAssertEqual(notice.lines[0].text, cut.status.messages[0])
    }

    func testR8TraducidoSustituyeAlFrances() throws {
        let bus = PreviewData.board(.cincoTramos).legs[4]
        let notice = try XCTUnwrap(BoardNotice(status: bus.status))
        XCTAssertEqual(notice.title, "Perturbada")
        XCTAssertFalse(notice.translating)
        XCTAssertEqual(notice.lines, [BoardNotice.Line(text: "Tráfico lento por obras en la calzada.", isFrench: false)])
    }

    func testR8MedioTraducidoSigueTraduciendo() throws {
        let metro = PreviewData.board(.casosLimite).legs[1]
        let notice = try XCTUnwrap(BoardNotice(status: metro.status))
        XCTAssertTrue(notice.translating)
        XCTAssertEqual(notice.lines.map(\.isFrench), [false, true])
    }

    func testR27DosMensajesEnLaTarjetaYLosDosIdiomasEnElDetalle() throws {
        let status = LegStatus(level: 1, label: "perturbada",
                               messages: ["Un.", "Deux.", "Trois."],
                               messagesEs: ["Uno.", nil, "  "], translating: false)
        let notice = try XCTUnwrap(BoardNotice(status: status))
        XCTAssertEqual(notice.lines.count, 2)
        XCTAssertEqual(notice.hiddenCount, 1)
        let both = BoardNotice.bilingual(status)
        XCTAssertEqual(both.count, 3)
        XCTAssertEqual(both[0], BoardNotice.Bilingual(spanish: "Uno.", french: "Un."))
        XCTAssertEqual(both[1], BoardNotice.Bilingual(spanish: nil, french: "Deux."))
        // Una traducción en blanco no cuenta como traducción.
        XCTAssertEqual(both[2], BoardNotice.Bilingual(spanish: nil, french: "Trois."))
    }

    func testR28ObrasFuturasNoEnciendenElAvisoYSeCuentan() {
        let worksOnly = PreviewData.board(.cincoTramos).legs[2].status
        XCTAssertEqual(worksOnly.level, 0)
        XCTAssertNil(BoardNotice(status: worksOnly))
        XCTAssertEqual(BoardText.plannedWorks(1, alongsideNotice: false),
                       "Hay 1 aviso de obras con fecha futura, que no afecta a hoy.")
        XCTAssertEqual(BoardText.plannedWorks(2, alongsideNotice: true),
                       "Además hay 2 avisos de obras con fecha futura, que no afectan a hoy.")
        XCTAssertNil(BoardText.plannedWorks(0, alongsideNotice: false))
    }

    // MARK: - R9 · R17 · R18 · R19 · píldora y apagado

    func testR17R18EnDirectoConSuAntiguedad() throws {
        var board = PreviewData.board(.tranquilo)
        board.receivedAt = t0.addingTimeInterval(-4)
        let pill = try XCTUnwrap(BoardPill.make(board: board, issue: nil, server: board.server, now: t0))
        XCTAssertEqual(pill.kind, .live)
        XCTAssertEqual(pill.text, "en directo · hace 10 s")
        XCTAssertEqual(pill.spoken, "Dato de hace 10 segundos, en directo.")
        XCTAssertFalse(pill.isOpaque)
        XCTAssertNil(pill.symbol)
    }

    func testR19ViejoA90Segundos() throws {
        var board = PreviewData.board(.tranquilo)
        board.receivedAt = t0.addingTimeInterval(-90)
        XCTAssertFalse(BoardDimming.isDimmed(board: board, now: t0))
        XCTAssertEqual(try XCTUnwrap(BoardPill.make(board: board, issue: nil, server: board.server, now: t0)).kind,
                       .live)
        board.receivedAt = t0.addingTimeInterval(-91)
        XCTAssertTrue(BoardDimming.isDimmed(board: board, now: t0))
        let pill = try XCTUnwrap(BoardPill.make(board: board, issue: nil, server: board.server, now: t0))
        XCTAssertEqual(pill.kind, .stale)
        XCTAssertEqual(pill.text, "dato viejo · hace 1 min")
        XCTAssertTrue(pill.isOpaque)
    }

    func testR19StaleDelServidorApagaYDataAgeNo() throws {
        var old = PreviewData.board(.viejo)
        old.receivedAt = t0
        XCTAssertTrue(BoardDimming.isDimmed(board: old, now: t0))
        XCTAssertEqual(try XCTUnwrap(BoardPill.make(board: old, issue: nil, server: old.server, now: t0)).text,
                       "dato viejo · hace 5 min")
        // Una estación con el tren a 40 min se pide cada 5 min: no es viejo.
        let slow = Board(route: nil, legs: [], dataAge: 300, stale: false, receivedAt: t0)
        XCTAssertFalse(BoardDimming.isDimmed(board: slow, now: t0))
        XCTAssertFalse(BoardDimming.isDimmed(board: nil, now: t0))
        XCTAssertEqual(BoardDimming.opacity(dimmed: true), Metrics.Opacity.stale)
        XCTAssertEqual(BoardDimming.saturation(dimmed: true), Metrics.Opacity.staleSaturation)
        XCTAssertEqual(BoardDimming.opacity(dimmed: false), 1)
    }

    func testR9SinConexionConservaElTableroYDiceSuEdad() throws {
        var board = PreviewData.board(.tranquilo)
        board.receivedAt = t0.addingTimeInterval(-240)
        let pill = try XCTUnwrap(BoardPill.make(board: board, issue: .offline(""), server: board.server, now: t0))
        XCTAssertEqual(pill.kind, .offline)
        XCTAssertEqual(pill.text, "sin conexión · último tablero hace 4 min")
        XCTAssertEqual(pill.spoken, "Sin conexión. Último tablero de hace 4 minutos.")
        XCTAssertEqual(BoardContentState.make(board: board, emptyMessage: nil, issue: .offline("")), .board)
    }

    func testR9ServidorSinClaveDisenado() throws {
        var board = PreviewData.board(.tranquilo)
        board.receivedAt = t0
        let byError = try XCTUnwrap(BoardPill.make(board: board, issue: .noKey, server: board.server, now: t0))
        XCTAssertEqual(byError.kind, .noKey)
        XCTAssertEqual(byError.text, "servidor sin clave de PRIM · hace 6 s")
        let byState = try XCTUnwrap(BoardPill.make(board: board, issue: nil,
                                                   server: ServerState(primKey: .missing), now: t0))
        XCTAssertEqual(byState.kind, .noKey)
        XCTAssertNil(BoardPill.make(board: nil, issue: .noKey, server: nil, now: t0))
    }

    func testR7AhorrandoCuotaDiceSuRitmo() throws {
        var board = PreviewData.board(.cuotaJusta)
        board.receivedAt = t0
        let pill = try XCTUnwrap(BoardPill.make(board: board, issue: nil, server: board.server, now: t0))
        XCTAssertEqual(pill.kind, .degraded)
        XCTAssertEqual(pill.text, "ahorrando cuota · cada 2 min · hace 48 s")
    }

    func testR46CuotaAgotadaVuelveAMedianocheUTC() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T10:50:00Z"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        XCTAssertEqual(BoardText.quotaReturn(now: now, retryAfter: 3600, timeZone: utc), "11:50")
        XCTAssertEqual(BoardText.quotaReturn(now: now, retryAfter: nil, timeZone: utc), "00:00")
        XCTAssertEqual(BoardText.quotaReturn(now: now, retryAfter: nil, timeZone: paris), "02:00")
    }

    // MARK: - R53 · R9 · qué ocupa la pantalla

    func testR53EstadosVacioCargaError() {
        let board = PreviewData.board(.tranquilo)
        XCTAssertEqual(BoardContentState.make(board: nil, emptyMessage: nil, issue: nil), .loading)
        XCTAssertEqual(BoardContentState.make(board: nil, emptyMessage: "todavía no hay rutas guardadas", issue: nil),
                       .noRoutes("todavía no hay rutas guardadas"))
        XCTAssertEqual(BoardContentState.make(board: nil, emptyMessage: nil, issue: .offline("x")),
                       .issue(.offline("x")))
        XCTAssertEqual(BoardContentState.make(board: board, emptyMessage: nil, issue: .upstream), .board)
        let noLegs = Board(route: BoardRoute(id: 9, name: "Vacía"), legs: [])
        XCTAssertEqual(BoardContentState.make(board: noLegs, emptyMessage: nil, issue: nil), .noLegs)
    }

    func testR53ErrorDisenadoDiceQueHacer() {
        XCTAssertEqual(BoardIssueCopy.title(.offline("")), "No se llega al servidor")
        XCTAssertEqual(BoardIssueCopy.message(.offline("")), "Ni por la red de casa ni por Tailscale.")
        XCTAssertEqual(BoardIssueCopy.title(.noKey), "El servidor no tiene clave de PRIM")
        XCTAssertTrue(BoardIssueCopy.offersServerSettings(.noKey))
        XCTAssertTrue(BoardIssueCopy.offersServerSettings(.keyRejected))
        XCTAssertFalse(BoardIssueCopy.offersServerSettings(.offline("")))
        XCTAssertTrue(BoardIssueCopy.allowsRetry(.offline("")))
        XCTAssertFalse(BoardIssueCopy.allowsRetry(.notPaired))
        XCTAssertTrue(BoardIssueCopy.offersRepair(.notPaired))
        XCTAssertEqual(BoardIssueCopy.symbol(.noKey), "key.fill")
    }

    // MARK: - R46 · R7 · pie y ritmo

    func testR46CuotaEnPie() {
        XCTAssertEqual(BoardText.footer(board: PreviewData.board(.cincoTramos)),
                       "282 llamadas hoy · se refresca cada 30 s mientras miras")
        XCTAssertEqual(BoardText.footer(board: PreviewData.board(.cuotaJusta)),
                       "74 llamadas hoy · se refresca cada 2 min mientras miras")
    }

    func testR7NuncaMenosDeTreintaSegundos() {
        let eager = Board(route: nil, legs: [], quota: [:], server: ServerState(refreshHintS: 10))
        XCTAssertEqual(BoardText.footer(board: eager), "se refresca cada 30 s mientras miras")
        XCTAssertEqual(BoardText.every(45), "cada 45 s")
        XCTAssertEqual(BoardText.every(60), "cada 1 min")
        XCTAssertEqual(BoardText.every(90), "cada 90 s")
        XCTAssertEqual(BoardText.every(300), "cada 5 min")
    }

    func testR7TironesConTresSegundosDeSeparacion() {
        var throttle = BoardRefreshThrottle()
        XCTAssertTrue(throttle.allow(at: t0))
        XCTAssertFalse(throttle.allow(at: t0.addingTimeInterval(2.9)))
        XCTAssertTrue(throttle.allow(at: t0.addingTimeInterval(3)))
        XCTAssertFalse(throttle.allow(at: t0.addingTimeInterval(4)))
    }

    func testR7BucleSoloEnTableroYTrayecto() {
        XCTAssertTrue(AppTab.board.refreshesBoard)
        XCTAssertTrue(AppTab.trip.refreshesBoard)
        XCTAssertFalse(AppTab.routes.refreshesBoard)
        XCTAssertFalse(AppTab.history.refreshesBoard)
    }

    // MARK: - R54 · barra del próximo refresco

    func testR54BarraDeRefrescoEnTexto() {
        XCTAssertEqual(BoardText.nextRefresh(in: 25), "próximo en 25 s")
        XCTAssertEqual(BoardText.nextRefresh(in: 3), "próximo en 5 s")
        XCTAssertEqual(BoardText.nextRefresh(in: 120), "próximo en 2 min")
        XCTAssertNil(BoardText.nextRefresh(in: 0))
        XCTAssertNil(BoardText.nextRefresh(in: -4))
    }

    // MARK: - R37 · la ruta que toca

    func testR37RotuloRutaQueTocaFrenteAElegida() {
        let auto = PreviewData.board(.cincoTramos)
        let chosen = PreviewData.board(.tranquilo)
        XCTAssertEqual(BoardText.routeKicker(board: auto, pinnedRouteID: nil, isSwitching: false), "La que toca ahora")
        XCTAssertEqual(BoardText.routeKicker(board: auto, pinnedRouteID: 3, isSwitching: false), "Ruta elegida")
        XCTAssertEqual(BoardText.routeKicker(board: chosen, pinnedRouteID: nil, isSwitching: false), "Ruta elegida")
        XCTAssertEqual(BoardText.routeKicker(board: auto, pinnedRouteID: 4, isSwitching: true), "Cambiando de ruta…")
        XCTAssertEqual(BoardText.routeKicker(board: nil, pinnedRouteID: nil, isSwitching: false), "Trajet")
    }

    func testTituloDelTramoConFlecha() {
        XCTAssertEqual(String(BoardTitleText.arrow(from: "Gare Saint-Lazare", to: "Argenteuil").characters),
                       "Gare Saint-Lazare → Argenteuil")
        XCTAssertEqual(String(BoardTitleText.arrow(from: "Saint-Lazare", to: "").characters), "Saint-Lazare")
        let metro = PreviewData.board(.cincoTramos).legs[3]
        XCTAssertEqual(BoardText.legTitle(metro).from, "Saint-Lazare")
        XCTAssertEqual(BoardText.legTitle(metro).to, "")
    }

    // MARK: - Hápticas (sistema.md §9.5)

    func testHapticaTrenADosMinutos() {
        typealias W = BoardHapticRules.Watch
        let three = W(routeID: 3, departureID: "e1", minutes: 3, atStop: false)
        let two = W(routeID: 3, departureID: "e1", minutes: 2, atStop: false)
        let one = W(routeID: 3, departureID: "e1", minutes: 1, atStop: false)
        XCTAssertTrue(BoardHapticRules.trainSoon(from: three, to: two))
        XCTAssertFalse(BoardHapticRules.trainSoon(from: two, to: one))
        XCTAssertFalse(BoardHapticRules.trainSoon(from: three, to: W(routeID: 3, departureID: "e2", minutes: 2, atStop: false)))
        XCTAssertFalse(BoardHapticRules.trainSoon(from: three, to: W(routeID: 4, departureID: "e1", minutes: 2, atStop: false)))
        XCTAssertFalse(BoardHapticRules.trainSoon(from: three, to: W(routeID: 3, departureID: "e1", minutes: 0, atStop: true)))
        XCTAssertFalse(BoardHapticRules.trainSoon(from: nil, to: two))
        XCTAssertEqual(BoardHapticRules.watch(board: PreviewData.board(.cincoTramos)),
                       W(routeID: 3, departureID: "b1", minutes: 6, atStop: false))
    }

    func testHapticaSoloCuandoElNivelSube() {
        typealias L = BoardHapticRules.LevelWatch
        XCTAssertEqual(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 0), to: L(routeID: 3, level: 1)),
                       .disruption)
        XCTAssertEqual(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 1), to: L(routeID: 3, level: 2)),
                       .interruption)
        XCTAssertEqual(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 0), to: L(routeID: 3, level: 2)),
                       .interruption)
        XCTAssertNil(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 2), to: L(routeID: 3, level: 1)))
        XCTAssertNil(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 1), to: L(routeID: 3, level: 1)))
        XCTAssertNil(BoardHapticRules.levelHaptic(from: L(routeID: 3, level: 0), to: L(routeID: 4, level: 2)))
    }

    func testHapticTriggerCuentaEventos() {
        var trigger = HapticTrigger()
        let before = trigger
        trigger.fire()
        XCTAssertNotEqual(trigger, before)
        XCTAssertEqual(trigger.count, 1)
    }

    // MARK: - R29 · R30 · alternativas

    func testR29BotonDeAlternativasNoPideNada() {
        let cut = PreviewData.board(.lineaCortada)
        XCTAssertTrue(BoardText.alternativesIsUrgent(cut))
        XCTAssertEqual(BoardText.alternativesTitle(cut), "Buscar alternativa · línea 14 cortada")
        let calm = PreviewData.board(.tranquilo)
        XCTAssertFalse(BoardText.alternativesIsUrgent(calm))
        XCTAssertEqual(BoardText.alternativesTitle(calm), "Buscar alternativa")
        let anonymous = Board(route: nil, legs: [], worstLevel: 2, worstLine: "")
        XCTAssertEqual(BoardText.alternativesTitle(anonymous), "Buscar alternativa · línea cortada")
    }

    @MainActor
    func testR29AlternativasSoloAlPedirlas() async {
        let recorder = FetchRecorder()
        let model = BoardAlternativesModel(routeID: 3)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.requests, 0)
        let calls = await recorder.forces
        XCTAssertEqual(calls, [])

        await model.load(force: false) { id, force in
            await recorder.record(id, force)
            return PreviewData.alternatives
        }
        XCTAssertEqual(model.requests, 1)
        XCTAssertEqual(model.phase, .loaded(PreviewData.alternatives))
        let routes = await recorder.routeIDs
        XCTAssertEqual(routes, [3])
    }

    @MainActor
    func testR30BuscarDeTodasFormasForce() async {
        let recorder = FetchRecorder()
        let model = BoardAlternativesModel(routeID: 4)
        await model.load(force: true) { id, force in
            await recorder.record(id, force)
            return PreviewData.alternatives
        }
        XCTAssertTrue(model.lastForce)
        let forces = await recorder.forces
        XCTAssertEqual(forces, [true])
    }

    @MainActor
    func testR30FalloDeRedYCancelacion() async {
        let model = BoardAlternativesModel(routeID: 3)
        await model.load(force: false) { _, _ in throw APIError.network("sin red") }
        XCTAssertEqual(model.phase, .failed("sin red"))
        await model.load(force: false) { _, _ in throw CancellationError() }
        XCTAssertEqual(model.phase, .idle)
    }

    func testR30NoUsableSeMarca() throws {
        let reply = PreviewData.alternatives
        let bad = try XCTUnwrap(reply.options.first { !$0.usable })
        let good = try XCTUnwrap(reply.options.first { $0.usable })
        XCTAssertTrue(BoardAlternativesText.isUnusable(bad))
        XCTAssertFalse(BoardAlternativesText.isUnusable(good))
        XCTAssertTrue(BoardAlternativesText.spoken(bad).contains("No sirve: pasa por la línea cortada"))
        XCTAssertFalse(BoardAlternativesText.spoken(good).contains("No sirve"))
        XCTAssertEqual(BoardAlternativesText.banner(reply.affected), "Línea 13 interrumpida")
    }

    func testR56R6AlternativasEnEspanol() throws {
        let option = try XCTUnwrap(PreviewData.alternatives.options.first)
        XCTAssertEqual(BoardAlternativesText.times(option), "12:55 → 13:54")
        XCTAssertEqual(BoardAlternativesText.transfers(0), "directo")
        XCTAssertEqual(BoardAlternativesText.transfers(1), "1 transbordo")
        XCTAssertEqual(BoardAlternativesText.transfers(2), "2 transbordos")
        XCTAssertEqual(BoardAlternativesText.baseline(47), "tu ruta tarda 47 min cuando funciona")
        XCTAssertEqual(BoardAlternativesText.baseline(62), "tu ruta tarda 1h02 cuando funciona")
        XCTAssertNil(BoardAlternativesText.baseline(nil))
        XCTAssertEqual(BoardAlternativesText.spoken(option),
                       "59 minutos; 12 minutos más de lo normal; sale a las 12:55; llega a las 13:54; 1 transbordo; línea 14 dirección Olympiades, 18 minutos; línea 6 dirección Nation, 22 minutos.")
    }

    // MARK: - Navegación y avisos efímeros

    @MainActor
    func testEnlacesAbrenLoQuePiden() {
        let navigator = AppNavigator(tab: .routes, toasts: ToastCenter())
        navigator.open(.route(id: 3, legSeq: 2, departureJID: "e1"))
        XCTAssertEqual(navigator.tab, .board)
        XCTAssertEqual(navigator.focusLegSeq, 2)

        navigator.show(.history)
        navigator.open(.alternatives(routeID: 3))
        XCTAssertEqual(navigator.tab, .board)
        XCTAssertEqual(navigator.alternativesRouteID, 3)

        XCTAssertFalse(navigator.showingSettings)
        navigator.open(.serverSettings)
        XCTAssertTrue(navigator.showingSettings)
        navigator.showingSettings = false
        navigator.open(.settings)
        XCTAssertTrue(navigator.showingSettings)

        navigator.show(.trip)
        navigator.open(.board)
        XCTAssertEqual(navigator.tab, .board)
    }

    @MainActor
    func testR55ToastEfimero() {
        XCTAssertEqual(ToastCenter.duration, 2.4, accuracy: 0.0001)
        let center = ToastCenter()
        let first = center.show("Ruta guardada", symbol: "checkmark")
        XCTAssertEqual(center.current, first)
        // Un temporizador viejo no se lleva un aviso nuevo.
        let second = center.show("Esa ruta ya no existe")
        center.dismiss(first.id)
        XCTAssertEqual(center.current, second)
        center.dismiss(second.id)
        XCTAssertNil(center.current)
    }

    @MainActor
    func testFinDeTrayectoSeDiceSoloSiNoFueAMano() {
        XCTAssertEqual(BoardTripControls.endedText(.arrived), "Has llegado: trayecto terminado")
        XCTAssertNil(BoardTripControls.endedText(.manual))
        XCTAssertEqual(BoardTripControls.endedText(.failed("")), "El trayecto se ha parado")
    }
}

/// Apunta las llamadas a «alternativas» (R29, R30).
private actor FetchRecorder {
    private(set) var routeIDs: [Int] = []
    private(set) var forces: [Bool] = []

    func record(_ routeID: Int, _ force: Bool) {
        routeIDs.append(routeID)
        forces.append(force)
    }
}
