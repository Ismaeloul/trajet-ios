#if DEBUG
import Foundation

// Bancos de prueba (R13). Son respuestas con la forma EXACTA de /api/v1
// (docs/openapi.yaml), no maquetas: así lo que se ve en el lienzo, en la demo
// (`-demo`) y en los tests es lo que se va a ver en el andén.
//
// Cubren los casos que el manual manda dibujar y que un JSON feliz esconde
// (docs/inventario-funcional.md F77–F79): tramo vacío, línea cortada, aviso
// sin traducir, vía que aparece, vía solo probable, bus a 106 y 165 minutos,
// tren parado en el andén, destinos mezclados, tablero viejo, cuota justa,
// servidor sin clave, 1 y 6 tramos, transbordo, colores de línea raros…
//
// Uso: `PreviewData.board(.viaProbable)`, `PreviewData.payload(.cincoTramos)`,
// `PreviewData.health(.sinClave)`, `PreviewData.routeMap`…
// `PreviewData.catalog` los lista todos con su tipo (los decodifica el test).
// Lo que NO tiene la forma de la API (JSON raros para probar la tolerancia,
// R21/R22) va aparte, en `OddCase`.
//
// Horas: en torno a las 12:50 de París del 24/09/2026 (10:50 UTC).

enum PreviewData {

    static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) -> T {
        // swiftlint:disable:next force_try
        try! JSONDecoder.trajet.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Tableros (BoardV1)

    enum BoardCase: String, CaseIterable, Sendable {
        /// Cinco tramos «Casa → Trabajo»: el caso difícil. Bus con retraso +11
        /// y a 106 min, tranvía sin salidas, RER con vía que aparece y dos
        /// probables, metro cortado con aviso sin traducir, tren en el andén y
        /// destinos mezclados, bus perturbado con el aviso ya traducido.
        case cincoTramos
        /// Dos tramos (14 + J) sin nada raro. Ruta elegida a mano.
        case tranquilo
        /// El servidor sirve un dato viejo (`stale`, `data_age` 312, degradado).
        case viejo
        /// La 14 cortada entera, con aviso traducido y sin salidas; la J sigue.
        case lineaCortada
        /// Cuota justa: `refresh_hint_s` 120, nivel crítico.
        case cuotaJusta
        /// Bus a 12 min, 1h, 1h46 y 2h45 (R6).
        case bus106
        /// La vía 21 se acaba de publicar (`platform_new`, R2).
        case viaAparece
        /// Solo vías probables: por misión, por hora y por línea (R10, R49).
        case viaProbable
        /// El tren está parado en el andén (`at_stop`, R15).
        case enAnden
        /// Metro sin sentido elegido: cada paso va a un sitio (R24).
        case destinosMezclados
        /// La 14 ya no tiene más salidas esta noche (R25).
        case tramoVacio
        /// Un solo tramo (densidad holgada, R47).
        case unTramo
        /// Seis tramos (densidad compacta, R47).
        case seisTramos
        /// RER A hasta Auber y J desde Saint-Lazare (transbordo andando).
        case transbordo
        /// Colores de línea vacío, de 3 dígitos, con «#» e inválido (R57).
        case coloresRaros
        /// Adelanto, 1h, dos avisos con uno traducido, solo obras futuras,
        /// una estación caída, 5 errores, sin avisos leídos.
        case casosLimite

        var title: String {
            switch self {
            case .cincoTramos: "Cinco tramos"
            case .tranquilo: "Tranquilo"
            case .viejo: "Dato viejo"
            case .lineaCortada: "Línea cortada"
            case .cuotaJusta: "Cuota justa"
            case .bus106: "Bus a 1h46"
            case .viaAparece: "Vía que aparece"
            case .viaProbable: "Vía probable"
            case .enAnden: "Tren en el andén"
            case .destinosMezclados: "Destinos mezclados"
            case .tramoVacio: "Tramo vacío"
            case .unTramo: "Un tramo"
            case .seisTramos: "Seis tramos"
            case .transbordo: "Transbordo"
            case .coloresRaros: "Colores raros"
            case .casosLimite: "Casos límite"
            }
        }
    }

    static func board(_ c: BoardCase) -> Board { decode(boardJSON(c)) }
    static func payload(_ c: BoardCase) -> BoardPayload { decode(boardJSON(c)) }

    /// El tablero como si hubiera llegado hace `secondsAgo` (sin conexión,
    /// dato viejo en el teléfono).
    static func cached(_ c: BoardCase, receivedSecondsAgo secondsAgo: TimeInterval,
                       routeID: Int? = nil, now: Date = .now) -> CachedBoard {
        CachedBoard(board: board(c), receivedAt: now.addingTimeInterval(-secondsAgo), routeID: routeID)
    }

    /// Compatibilidad con las vistas previas de la v1.
    static var fiveLegBoard: Board { board(.cincoTramos) }
    static var calmBoard: Board { board(.tranquilo) }

    static var guess: PlatformGuess {
        decode(#"{"platform": "11", "share": 0.82, "samples": 17, "basis": "mision", "why": "por el número de tren"}"#)
    }

    /// Instalación limpia: el servidor aún no tiene rutas (`BoardEmptyV1`).
    static let emptyBoardJSON = """
    {"empty": true, "message": "todavía no hay rutas guardadas", "server": \(serverNormal)}
    """
    static var emptyPayload: BoardPayload { decode(emptyBoardJSON) }

    static func boardJSON(_ c: BoardCase) -> String {
        switch c {
        case .cincoTramos:
            return boardV1(
                route: (3, "Casa → Trabajo", "6 Rue de la Marseillaise", "74 Rue de Paris"),
                legs: [
                    leg(0, bus6424, from: marseillaise, to: pontBezons, directions: ["Pont de Bezons"], age: 4.1, departures: [
                        dep("b1", 6, "12:56", aimed: "12:45", to: "Pont de Bezons", delay: 11, status: "delayed"),
                        dep("b2", 56, "13:46", aimed: "13:45", to: "Pont de Bezons", delay: 1),
                        dep("b3", 106, "14:36", aimed: "14:35", to: "Pont de Bezons", delay: 1),
                    ]),
                    leg(1, tramT2, from: parcBezons, to: porteVersailles, directions: ["Porte de Versailles"], age: 3.0, departures: []),
                    leg(2, rerE, from: haussmann, to: chelles, directions: ["Chelles - Gournay"],
                        status: lineStatus(0, planned: 1), age: 2.4, departures: [
                            dep("e1", 4, "12:54", aimed: "12:52", to: "Chelles - Gournay", platform: "11", new: true,
                                delay: 2, train: "135711", length: "long"),
                            dep("e2", 12, "13:02", aimed: "13:02", to: "Chelles - Gournay", delay: 0,
                                train: "135713", length: "short", guess: guessJSON("11", 0.82, 17, "mision")),
                            dep("e3", 22, "13:12", aimed: "13:12", to: "Chelles - Gournay",
                                train: "135715", guess: guessJSON("7", 0.55, 9, "hora")),
                        ]),
                    leg(3, metro13, from: saintLazareMetro, to: ("", ""), directions: [],
                        status: lineStatus(2, messages: ["Le trafic est interrompu entre Châtillon-Montrouge et Montparnasse suite à un incident technique."],
                                           es: [nil], translating: true),
                        age: 1.8, departures: [
                            dep("m1", 0, "12:50", to: "Châtillon - Montrouge", atStop: true),
                            dep("m2", 3, "12:53", to: "Les Courtilles"),
                            dep("m3", 9, "12:59", to: "Châtillon - Montrouge"),
                        ]),
                    leg(4, bus147, from: eglisePantin, to: gallieni, directions: ["Gallieni - Pont de Bondy"],
                        status: lineStatus(1, messages: ["Trafic ralenti en raison de travaux sur la voirie."],
                                           es: ["Tráfico lento por obras en la calzada."]),
                        age: 5.5, departures: [
                            dep("s1", 2, "12:52", to: "Gallieni - Pont de Bondy"),
                            dep("s2", 27, "13:17", to: "Gallieni - Pont de Bondy"),
                        ]),
                ],
                worstLevel: 2, worstLine: "13", maxDelay: 11, dataAge: 8.2,
                quota: #"{"stop-monitoring": 282, "general-message": 946, "navitia": 915}"#)

        case .tranquilo:
            return boardV1(route: route4, legs: [leg14(), legJ(dataAge: 3.2)],
                           dataAge: 6.0, autoSelected: false)

        case .viejo:
            return boardV1(route: route4, legs: [leg14(age: 305), legJ(dataAge: 312.4)],
                           dataAge: 312.4, stale: true,
                           lastError: "TimeoutError: stop-monitoring no responde",
                           autoSelected: false,
                           server: serverJSON(quota: "ok", hint: 30, degraded: true))

        case .lineaCortada:
            return boardV1(route: route4, legs: [
                leg(0, metro14, from: olympiades, to: saintLazareMetro, directions: ["Saint-Denis Pleyel"],
                    status: lineStatus(2, messages: ["Trafic interrompu sur l'ensemble de la ligne en raison d'un incident technique. Reprise estimée à 14h00."],
                                       es: ["Tráfico interrumpido en toda la línea por un incidente técnico. Reanudación prevista a las 14:00."]),
                    age: 2.0, departures: []),
                legJ(dataAge: 3.2),
            ], worstLevel: 2, worstLine: "14", dataAge: 3.2, autoSelected: true)

        case .cuotaJusta:
            return boardV1(route: route4, legs: [leg14(age: 44), legJ(dataAge: 48)],
                           dataAge: 48, quota: #"{"stop-monitoring": 74, "general-message": 380, "navitia": 610}"#,
                           server: serverJSON(quota: "critical", hint: 120, degraded: true))

        case .bus106:
            return boardV1(route: (6, "Bus de la tarde", "Gare d'Argenteuil", "Sartrouville"), legs: [
                leg(0, bus272, from: argenteuilBus, to: sartrouville, directions: ["Sartrouville RER"], age: 5.0, departures: [
                    dep("n1", 12, "13:02", aimed: "13:00", to: "Sartrouville RER", delay: 2, status: "delayed"),
                    dep("n2", 60, "13:50", aimed: "13:50", to: "Sartrouville RER", delay: 0),
                    dep("n3", 106, "14:36", aimed: "14:25", to: "Sartrouville RER", delay: 11, status: "delayed"),
                    dep("n4", 165, "15:35", aimed: "15:35", to: "Sartrouville RER", delay: 0),
                ]),
            ], maxDelay: 11, dataAge: 5.0)

        case .viaAparece:
            return boardV1(route: route5, legs: [
                leg(0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 2.1, departures: [
                    dep("j1", 7, "12:57", aimed: "12:57", to: "Ermont - Eaubonne", platform: "21", new: true,
                        delay: 0, train: "137408", length: "long"),
                    dep("j2", 22, "13:12", aimed: "13:12", to: "Ermont - Eaubonne",
                        train: "137412", length: "short", guess: guessJSON("21", 0.9, 20, "mision")),
                    dep("j3", 37, "13:27", aimed: "13:27", to: "Ermont - Eaubonne", train: "137416"),
                ]),
            ], dataAge: 2.1)

        case .viaProbable:
            return boardV1(route: route5, legs: [
                leg(0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 2.1, departures: [
                    dep("j1", 7, "12:57", aimed: "12:57", to: "Ermont - Eaubonne", delay: 0,
                        train: "137408", length: "long", guess: guessJSON("21", 0.9, 20, "mision")),
                    dep("j2", 22, "13:12", aimed: "13:12", to: "Ermont - Eaubonne",
                        train: "137412", guess: guessJSON("19", 0.62, 13, "hora")),
                    dep("j3", 37, "13:27", aimed: "13:27", to: "Ermont - Eaubonne",
                        train: "137416", guess: guessJSON("21", 0.55, 9, "linea")),
                ]),
            ], dataAge: 2.1)

        case .enAnden:
            return boardV1(route: route5, legs: [
                leg(0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 1.2, departures: [
                    dep("j0", 0, "12:50", aimed: "12:50", to: "Ermont - Eaubonne", platform: "21",
                        delay: 0, atStop: true, train: "137404", length: "long"),
                    dep("j1", 15, "13:05", aimed: "13:05", to: "Ermont - Eaubonne",
                        train: "137408", guess: guessJSON("21", 0.9, 20, "mision")),
                    dep("j2", 30, "13:20", aimed: "13:20", to: "Ermont - Eaubonne", train: "137412"),
                ]),
            ], dataAge: 1.2)

        case .destinosMezclados:
            return boardV1(route: (8, "Al cine", "Gare Saint-Lazare", "Montparnasse"), legs: [
                leg(0, metro13, from: saintLazareMetro, to: ("", ""), directions: [], age: 1.5, departures: [
                    dep("k1", 2, "12:52", to: "Châtillon - Montrouge"),
                    dep("k2", 4, "12:54", to: "Les Courtilles"),
                    dep("k3", 6, "12:56", to: "Saint-Denis - Université"),
                    dep("k4", 9, "12:59", to: "Châtillon - Montrouge"),
                ]),
            ], dataAge: 1.5)

        case .tramoVacio:
            return boardV1(route: route4, legs: [
                leg(0, metro14, from: olympiades, to: saintLazareMetro, directions: ["Saint-Denis Pleyel"],
                    age: 20.0, departures: []),
                leg(1, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 22.0, departures: [
                    dep("jn", 34, "01:24", aimed: "01:24", to: "Ermont - Eaubonne", train: "137498"),
                ]),
            ], dataAge: 22.0, autoSelected: false, updatedAt: "2026-09-24T22:50:03+00:00")

        case .unTramo:
            return boardV1(route: route5, legs: [
                leg(0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 2.8, departures: [
                    dep("j1", 7, "12:57", aimed: "12:57", to: "Ermont - Eaubonne", platform: "21",
                        delay: 0, train: "137408", length: "long"),
                    dep("j2", 22, "13:12", aimed: "13:12", to: "Ermont - Eaubonne",
                        train: "137412", length: "short", guess: guessJSON("21", 0.9, 20, "mision")),
                    dep("j3", 37, "13:27", aimed: "13:27", to: "Ermont - Eaubonne", train: "137416"),
                    dep("j4", 52, "13:42", aimed: "13:42", to: "Ermont - Eaubonne", train: "137420", length: "long"),
                ]),
            ], dataAge: 2.8)

        case .seisTramos:
            return boardV1(route: (9, "La vuelta larga", "6 Rue de la Marseillaise", "Place d'Italie"), legs: [
                leg(0, bus6424, from: marseillaise, to: pontBezons, directions: ["Pont de Bezons"], age: 4.0, departures: [
                    dep("x1", 5, "12:55", to: "Pont de Bezons"), dep("x2", 25, "13:15", to: "Pont de Bezons"),
                ]),
                leg(1, tramT2, from: parcBezons, to: porteVersailles, directions: ["Porte de Versailles"], age: 3.0, departures: [
                    dep("x3", 3, "12:53", to: "Porte de Versailles"), dep("x4", 9, "12:59", to: "Porte de Versailles"),
                ]),
                leg(2, rerE, from: haussmann, to: chelles, directions: ["Chelles - Gournay"], age: 2.4, departures: [
                    dep("x5", 4, "12:54", aimed: "12:54", to: "Chelles - Gournay", platform: "11", delay: 0, train: "135711"),
                    dep("x6", 14, "13:04", aimed: "13:04", to: "Chelles - Gournay", train: "135713",
                        guess: guessJSON("11", 0.82, 17, "mision")),
                ]),
                leg(3, metro13, from: saintLazareMetro, to: montparnasse, directions: ["Châtillon - Montrouge"], age: 1.8, departures: [
                    dep("x7", 1, "12:51", to: "Châtillon - Montrouge"), dep("x8", 4, "12:54", to: "Châtillon - Montrouge"),
                ]),
                leg(4, bus147, from: eglisePantin, to: gallieni, directions: ["Gallieni - Pont de Bondy"], age: 5.5, departures: [
                    dep("x9", 8, "12:58", to: "Gallieni - Pont de Bondy"),
                ]),
                leg(5, metro5, from: gareNord, to: placeItalie, directions: ["Place d'Italie"], age: 2.2, departures: [
                    dep("y1", 2, "12:52", to: "Place d'Italie"), dep("y2", 5, "12:55", to: "Place d'Italie"),
                ]),
            ], dataAge: 5.5)

        case .transbordo:
            return boardV1(route: (10, "Nation → Argenteuil", "Nation", "Argenteuil"), legs: [
                leg(0, rerA, from: nation, to: auber, directions: ["Saint-Germain-en-Laye", "Cergy - Le Haut", "Poissy"],
                    age: 2.6, departures: [
                        dep("a1", 3, "12:53", aimed: "12:52", to: "Cergy - Le Haut", platform: "1", delay: 1, train: "UPAC54"),
                        dep("a2", 8, "12:58", aimed: "12:58", to: "Saint-Germain-en-Laye", delay: 0, train: "QIKI52",
                            guess: guessJSON("1", 0.97, 31, "linea")),
                        dep("a3", 13, "13:03", aimed: "13:03", to: "Poissy", train: "ZEUS58"),
                    ]),
                leg(1, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: 3.2, departures: [
                    dep("j2", 22, "13:12", aimed: "13:12", to: "Ermont - Eaubonne", train: "137412",
                        guess: guessJSON("21", 0.9, 20, "mision")),
                    dep("j3", 37, "13:27", aimed: "13:27", to: "Ermont - Eaubonne", train: "137416"),
                ]),
            ], maxDelay: 1, dataAge: 3.2)

        case .coloresRaros:
            return boardV1(route: (11, "Colores raros", "Aquí", "Allí"), legs: [
                leg(0, Line(id: "line:IDFM:C00001", code: "N1", mode: "Bus", color: ""),
                    from: marseillaise, to: pontBezons, directions: ["Sin color"], age: 3.0, departures: [
                        dep("c1", 4, "12:54", to: "Sin color"),
                    ]),
                leg(1, Line(id: "line:IDFM:C00002", code: "147", mode: "Bus", color: "F90"),
                    from: eglisePantin, to: gallieni, directions: ["Tres dígitos"], age: 3.0, departures: [
                        dep("c2", 6, "12:56", to: "Tres dígitos"),
                    ]),
                leg(2, Line(id: "line:IDFM:C01383", code: "13", mode: "Métro", color: "#82C8E6"),
                    from: saintLazareMetro, to: montparnasse, directions: ["Con almohadilla"], age: 3.0, departures: [
                        dep("c3", 2, "12:52", to: "Con almohadilla"),
                    ]),
                leg(3, Line(id: "line:IDFM:C00003", code: "T99", mode: "Tramway", color: "ZZZZZZ"),
                    from: parcBezons, to: porteVersailles, directions: ["Inválido"], age: 3.0, departures: [
                        dep("c4", 8, "12:58", to: "Inválido"),
                    ]),
            ], dataAge: 3.0)

        case .casosLimite:
            return boardV1(route: (12, "Casos límite", "Aquí", "Allí"), legs: [
                // Adelanto (retraso negativo), 1h justa y un tren de 1 min.
                leg(0, rerE, from: haussmann, to: chelles, directions: ["Chelles - Gournay"], age: 2.0, departures: [
                    dep("l1", 1, "12:51", aimed: "12:52", to: "Chelles - Gournay", platform: "9", delay: -1,
                        status: "early", train: "135709", length: "short"),
                    dep("l2", 60, "13:50", aimed: "13:50", to: "Chelles - Gournay", delay: 0, train: "135731"),
                ]),
                // Dos avisos, solo uno traducido: sigue «traduciendo» (R8).
                leg(1, metro13, from: saintLazareMetro, to: montparnasse, directions: ["Châtillon - Montrouge"],
                    status: lineStatus(1, messages: ["Trafic perturbé entre Invalides et Montparnasse.",
                                                     "Station Liège fermée jusqu'à nouvel ordre."],
                                       es: ["Tráfico perturbado entre Invalides y Montparnasse.", nil],
                                       translating: true),
                    age: 2.0, departures: [
                        dep("l3", 3, "12:53", to: "Châtillon - Montrouge"),
                    ]),
                // Solo obras futuras: la línea está normal (R28); sin sentido
                // pero con un solo destino (no es mezcla, R24).
                leg(2, bus147, from: eglisePantin, to: gallieni, directions: [],
                    status: lineStatus(0, planned: 2), age: 4.0, departures: [
                        dep("l4", 5, "12:55", to: "Gallieni - Pont de Bondy"),
                        dep("l5", 19, "13:09", to: "Gallieni - Pont de Bondy"),
                    ]),
                // La estación falló sin caché: age null y sin salidas.
                leg(3, tramT2, from: parcBezons, to: porteVersailles, directions: ["Porte de Versailles"],
                    age: nil, departures: []),
            ], worstLevel: 1, worstLine: "13", dataAge: 4.0, stale: true,
               errors: ["Parc de Bezons: tiempo de espera agotado",
                        "Victor Basch: tiempo de espera agotado",
                        "Porte de Versailles: tiempo de espera agotado",
                        "Église de Pantin: respuesta vacía",
                        "avisos: tiempo de espera agotado"],
               lastError: "TimeoutError: general-message",
               server: serverJSON(quota: "warn", hint: 60, degraded: true),
               disruptionsOK: false)
        }
    }

    // MARK: - Errores (ErrorV1)

    enum ErrorCase: String, CaseIterable, Sendable {
        case sinClave, claveRechazada, cuotaAgotada, primCaido, noEmparejado
        case rutaNoEncontrada, codigoNoValido, demasiadosIntentos, errorInterno

        var status: Int {
            switch self {
            case .sinClave, .claveRechazada, .cuotaAgotada: 503
            case .primCaido: 502
            case .noEmparejado, .codigoNoValido: 401
            case .rutaNoEncontrada: 404
            case .demasiadosIntentos: 429
            case .errorInterno: 500
            }
        }

        var code: String {
            switch self {
            case .sinClave: "prim_key_missing"
            case .claveRechazada: "prim_key_invalid"
            case .cuotaAgotada: "prim_quota_exhausted"
            case .primCaido: "prim_unreachable"
            case .noEmparejado: "unauthorized"
            case .rutaNoEncontrada: "not_found"
            case .codigoNoValido: "pairing_invalid"
            case .demasiadosIntentos: "rate_limited"
            case .errorInterno: "internal"
            }
        }
    }

    static func errorJSON(_ c: ErrorCase) -> String {
        switch c {
        case .sinClave:
            #"{"error": {"code": "prim_key_missing", "message": "el servidor no tiene clave de PRIM configurada"}}"#
        case .claveRechazada:
            #"{"error": {"code": "prim_key_invalid", "message": "PRIM rechaza la clave del servidor"}}"#
        case .cuotaAgotada:
            #"{"error": {"code": "prim_quota_exhausted", "message": "cuota diaria de PRIM agotada; vuelve a haber a medianoche UTC", "retry_after": 3600}}"#
        case .primCaido:
            #"{"error": {"code": "prim_unreachable", "message": "la API de IDFM no responde"}}"#
        case .noEmparejado:
            #"{"error": {"code": "unauthorized", "message": "el token no vale o el dispositivo esta revocado; vuelve a emparejar"}}"#
        case .rutaNoEncontrada:
            #"{"error": {"code": "not_found", "message": "ruta no encontrada"}}"#
        case .codigoNoValido:
            #"{"error": {"code": "pairing_invalid", "message": "el código no vale: puede estar mal escrito, caducado o ya usado; genera otro en el panel"}}"#
        case .demasiadosIntentos:
            #"{"error": {"code": "rate_limited", "message": "demasiados intentos de emparejar; vuelve a probar en 60 s", "retry_after": 60}}"#
        case .errorInterno:
            #"{"error": {"code": "internal", "message": "error interno del servidor"}}"#
        }
    }

    static func error(_ c: ErrorCase) -> APIErrorBody { decode(errorJSON(c)) }

    // MARK: - Salud (HealthV1)

    enum HealthCase: String, CaseIterable, Sendable {
        case conClave, sinClave, traductorCaido, cuotaJusta
    }

    static func health(_ c: HealthCase) -> ServerHealth { decode(healthJSON(c)) }

    static func healthJSON(_ c: HealthCase) -> String {
        switch c {
        case .conClave:
            return healthV1(prim: primValid, quota: quotaSnapshot(level: "ok", hint: 30, used: (318, 88, 70)),
                            collector: collectorRunning, accuracy: accuracyGood, translator: translatorOK)
        case .sinClave:
            return healthV1(prim: #"{"key_state": "missing", "key_source": "none", "checked_at": null, "last_error": null}"#,
                            quota: quotaSnapshot(level: "ok", hint: 30, used: (0, 0, 0)),
                            collector: #"{"enabled": true, "running": false, "last_at": "", "session_total": 0, "stations": 0, "recorded": 0, "reason": "sin clave de PRIM", "interval": 0, "remaining": null, "priority": false}"#,
                            accuracy: #"{"predictions": 0, "hits": 0, "rate": null, "observations": 0, "days": 0}"#,
                            translator: #"{"ok": false, "reason": "sin configurar"}"#)
        case .traductorCaido:
            return healthV1(prim: primValid, quota: quotaSnapshot(level: "ok", hint: 30, used: (318, 88, 70)),
                            collector: collectorRunning, accuracy: accuracyGood,
                            translator: #"{"ok": false, "reason": "no responde: timed out", "models": []}"#)
        case .cuotaJusta:
            return healthV1(prim: primValid, quota: quotaSnapshot(level: "critical", hint: 120, used: (926, 620, 390)),
                            collector: collectorRunning, accuracy: accuracyGood, translator: translatorOK)
        }
    }

    // MARK: - Emparejamiento

    /// El código que acepta el servidor de la demo.
    static let demoCode = "DEMO-2026"
    /// Token de mentira con la forma del de verdad (trj_ + 43). No vale en
    /// ningún servidor.
    static let demoToken = "trj_DEMO000000000000000000000000000000000000000"

    /// Un QR del panel.
    static let pairingLink = "trajet://pair?v=1&code=ABCD-EFGH&lan=http%3A%2F%2F192.168.1.10%3A7796&ts=http%3A%2F%2F100.64.0.10%3A7796&name=Trajet%20de%20casa"

    static let pingJSON = #"{"ok": true, "service": "trajet", "api": 1, "version": "0.4.0", "paired": false}"#
    static let pingPairedJSON = #"{"ok": true, "service": "trajet", "api": 1, "version": "0.4.0", "paired": true}"#

    static let deviceJSON = """
    {"id": 3, "name": "iPhone de Isma", "model": "iPhone17,1", "app_version": "2.0 (1)", "created_at": "2026-09-24T10:40:12+00:00", "last_used_at": "2026-09-24T10:50:03+00:00"}
    """

    static let unpairJSON = #"{"revoked": true}"#

    /// PairResult con las direcciones dadas (la demo pone la suya).
    static func pairResultJSON(lan: String = "http://192.168.1.10:7796",
                               tailscale: String? = "http://100.64.0.10:7796",
                               name: String = "Trajet de casa") -> String {
        var urls = [#"{"kind": "lan", "url": \#(j(lan))}"#]
        if let tailscale { urls.append(#"{"kind": "tailscale", "url": \#(j(tailscale))}"#) }
        let urlsText = urls.joined(separator: ", ")
        var s = #"{"token": \#(j(demoToken)), "device": \#(deviceJSON), "#
        s += #""server": {"name": \#(j(name)), "version": "0.4.0", "urls": [\#(urlsText)]}}"#
        return s
    }

    static var ping: PingResponse { decode(pingJSON) }
    static var pairResult: PairResult { decode(pairResultJSON()) }
    static var device: DeviceInfo { decode(deviceJSON) }

    // MARK: - Rutas (RouteList, Route, RouteSaved…)

    static let routesJSON: String = {
        let r3 = routeJSON(id: 3, name: "Casa → Trabajo", origin: ("2.24731;48.92644", "6 Rue de la Marseillaise"),
                           dest: ("2.40452;48.89217", "74 Rue de Paris"), days: [0, 1, 2, 3, 4],
                           from: "07:13", to: "09:15", mode: "arrival", at: "09:00", duration: 62, position: 0, legs: [
                            routeLeg(11, 3, 0, bus6424, from: marseillaise, to: pontBezons, directions: ["Pont de Bezons"]),
                            routeLeg(12, 3, 1, tramT2, from: parcBezons, to: porteVersailles, directions: ["Porte de Versailles"]),
                            routeLeg(13, 3, 2, rerE, from: haussmann, to: chelles, directions: ["Chelles - Gournay"]),
                            routeLeg(14, 3, 3, metro13, from: saintLazareMetro, to: ("", ""), directions: []),
                            routeLeg(15, 3, 4, bus147, from: eglisePantin, to: gallieni, directions: ["Gallieni - Pont de Bondy"]),
                           ])
        let r4 = routeJSON(id: 4, name: "Trabajo → Casa", origin: (olympiades.0, olympiades.1),
                           dest: (argenteuil.0, argenteuil.1), days: [0, 1, 2, 3, 4, 5, 6],
                           from: "17:00", to: "20:00", mode: "window", at: "", duration: 0, position: 1, legs: [
                            routeLeg(21, 4, 0, metro14, from: olympiades, to: saintLazareMetro, directions: ["Saint-Denis Pleyel"]),
                            routeLeg(22, 4, 1, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"]),
                           ])
        let r5 = routeJSON(id: 5, name: "Saint-Lazare → Argenteuil", origin: (saintLazare.0, saintLazare.1),
                           dest: (argenteuil.0, argenteuil.1), days: [5, 6],
                           from: "09:45", to: "11:14", mode: "departure", at: "10:30", duration: 14, position: 2, legs: [
                            routeLeg(31, 5, 0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"]),
                           ])
        let r6 = routeJSON(id: 6, name: "Vuelta de clase", origin: (chatelet.0, chatelet.1),
                           dest: (nanterre.0, nanterre.1), days: [1, 3],
                           from: "20:15", to: "22:30", mode: "departure", at: "21:00", duration: 0, position: 3, legs: [
                            routeLeg(41, 6, 0, rerA, from: chatelet, to: nanterre,
                                     directions: ["Saint-Germain-en-Laye", "Cergy - Le Haut"]),
                           ])
        return #"{"active_id": 3, "routes": [\#(r3), \#(r4), \#(r5), \#(r6)]}"#
    }()

    static var routesResponse: RoutesResponse { decode(routesJSON) }
    static var routes: [SavedRoute] { routesResponse.routes }

    /// Una ruta suelta (GET /routes/5).
    static var singleRouteJSON: String {
        routeJSON(id: 5, name: "Saint-Lazare → Argenteuil", origin: (saintLazare.0, saintLazare.1),
                  dest: (argenteuil.0, argenteuil.1), days: [5, 6],
                  from: "09:45", to: "11:14", mode: "departure", at: "10:30", duration: 14, position: 2, legs: [
                    routeLeg(31, 5, 0, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"]),
                  ])
    }

    /// POST/PUT /routes → RouteSaved.
    static var routeSavedJSON: String { #"{"id": 5, "route": \#(singleRouteJSON)}"# }
    static let routeDeletedJSON = #"{"deleted": 5}"#

    /// POST /routes/from-plan sin avisos y con un tramo sin sentido (R33).
    static var planSavedJSON: String {
        #"{"id": 7, "route": \#(singleRouteJSON), "without_direction": []}"#
    }
    static var planSavedWithoutDirectionJSON: String {
        #"{"id": 7, "route": \#(singleRouteJSON), "without_direction": ["13"]}"#
    }

    // MARK: - Mapa (RouteMap): la J de Saint-Lazare a Argenteuil

    static var routeMap: RouteMap { decode(routeMapJSON()) }

    /// Trazado y paradas con coordenadas de los datos abiertos de IDFM
    /// (trajet-server/tests/fixtures/idfm); la polilínea, simplificada.
    static func routeMapJSON(routeID: Int = 5) -> String {
        """
        {"route_id": \(routeID), "generated_at": "2026-09-24T05:30:12+00:00", "pending": false, "stale": false,
         "lines": [
          {"seq": 0, "line_id": "line:IDFM:C01739", "code": "J", "mode": "rail",
           "color": "#CEC73D", "text_color": "#000000",
           "from": {"zdc": "71370", "stop_id": "IDFM:monomodalStopPlace:58566", "name": "Gare Saint-Lazare", "lat": 48.877476, "lon": 2.324439},
           "to": {"zdc": "65063", "stop_id": "IDFM:monomodalStopPlace:47875", "name": "Argenteuil", "lat": 48.946895, "lon": 2.257914},
           "path": {"encoding": "polyline5",
                    "coarse": "gkiiHw~dMqdAfiB}jBlvC_pBhtCoo@eI{}A~Q",
                    "fine": "gkiiHw~dMqTv]oUla@uX|g@}[zl@o]fj@yXfa@qUd[ySh^g^vg@cZrc@w`@tg@_XgBoV_FcYp@{YbFmUrEmRtB",
                    "tolerance_m": {"coarse": 20, "fine": 2}},
           "length_m": 9612,
           "via": [
             {"name": "Asnières-sur-Seine", "lat": 48.905875, "lon": 2.283211},
             {"name": "Bois-Colombes", "lat": 48.914196, "lon": 2.271649},
             {"name": "Colombes", "lat": 48.923958, "lon": 2.259319},
             {"name": "Le Stade", "lat": 48.93172, "lon": 2.260949}],
           "source": "gtfs"}],
         "stations": [
          {"zdc": "71370", "name": "Gare Saint-Lazare", "lat": 48.876837, "lon": 2.324738, "role": "origin",
           "platforms": [
             {"id": "STIF:StopPoint:Q:470692:", "line": "J", "name": "Paris Saint-Lazare", "lat": 48.877279, "lon": 2.323937},
             {"id": "STIF:StopPoint:Q:472110:", "line": "J", "name": "Paris Saint-Lazare", "lat": 48.877729, "lon": 2.325553}],
           "tracks": [
             {"voie": "9", "lat": 48.877279, "lon": 2.323937},
             {"voie": "13", "lat": 48.877317, "lon": 2.324304},
             {"voie": "21", "lat": 48.877602, "lon": 2.324921},
             {"voie": "24", "lat": 48.877772, "lon": 2.325171},
             {"voie": "27", "lat": 48.877729, "lon": 2.325553}]},
          {"zdc": "65063", "name": "Argenteuil", "lat": 48.946797, "lon": 2.257897, "role": "destination",
           "platforms": [
             {"id": "STIF:StopPoint:Q:41166:", "line": "J", "name": "Argenteuil", "lat": 48.946878, "lon": 2.257957}],
           "tracks": []}],
         "accesses": [
          {"id": "50170773", "zdc": "71370", "name": "r. Budapest", "number": null, "entry": true, "exit": true,
           "lat": 48.877115, "lon": 2.326802,
           "to_stop": [{"stop_id": "IDFM:monomodalStopPlace:58566", "m": 142.5, "s": 150}]},
          {"id": "50147869", "zdc": "71370", "name": "cour de Rome", "number": "1", "entry": true, "exit": true,
           "lat": 48.87568, "lon": 2.324189,
           "to_stop": [{"stop_id": "IDFM:monomodalStopPlace:58566", "m": null, "s": null}]},
          {"id": "50170422", "zdc": "65063", "name": "Entrée / Sortie", "number": null, "entry": true, "exit": true,
           "lat": 48.946529, "lon": 2.257598,
           "to_stop": [{"stop_id": "IDFM:monomodalStopPlace:47875", "m": 56.14, "s": 59}]}],
         "transfers": [],
         "sources": {"acces": "2026-09-23T00:30:34+00:00", "emplacement-des-gares-idf": "2026-09-22T04:10:00+00:00",
                     "traces-des-lignes-de-transport-en-commun-idfm": "2026-09-23T15:00:42+00:00"},
         "license": "Datos: Île-de-France Mobilités — Référentiel des arrêts, accès et tracés du réseau ferré (Licence Ouverte v2.0, mise à jour du 23/09/2026) ; tracés des lignes, référentiel des lignes, arrêts et lignes associées (ODbL) ; horaires GTFS (Licence Mobilités). Tracés calculés sur OpenStreetMap © contributeurs OpenStreetMap."}
        """
    }

    /// El mapa aún se está calculando: solo las paradas, sin trazado.
    static let routeMapPendingJSON = """
    {"route_id": 5, "generated_at": "2026-09-24T10:50:03+00:00", "pending": true, "stale": false,
     "lines": [
      {"seq": 0, "line_id": "line:IDFM:C01739", "code": "J", "mode": "rail", "color": "#CEC73D", "text_color": "#000000",
       "from": {"zdc": "71370", "stop_id": null, "name": "Gare Saint-Lazare", "lat": 48.876837, "lon": 2.324738},
       "to": {"zdc": "65063", "stop_id": null, "name": "Argenteuil", "lat": 48.946797, "lon": 2.257897},
       "path": null, "length_m": null, "via": [], "source": "recta"}],
     "stations": [], "accesses": [], "transfers": [], "sources": {}, "license": ""}
    """

    // MARK: - Planificador (Plan, PlanOption)

    static let planJSON = """
    {"age": 1.2, "options": [
      {"kind": "best", "minutes": 47, "walk_minutes": 11, "transfers": 1,
       "departure": "08:07", "arrival": "08:54", "legs": [
        {"line_id": "line:IDFM:C01739", "line_code": "J", "line_name": "J",
         "line_mode": "Train Transilien", "line_color": "CEC73D", "from_id": "stop_area:IDFM:65063",
         "from_name": "Argenteuil", "to_id": "stop_area:IDFM:71370", "to_name": "Gare Saint-Lazare",
         "direction": "Paris Saint-Lazare", "minutes": 17, "at": "08:12"},
        {"line_id": "line:IDFM:C01383", "line_code": "13", "line_name": "13",
         "line_mode": "Métro", "line_color": "82C8E6", "from_id": "stop_area:IDFM:71370",
         "from_name": "Gare Saint-Lazare", "to_id": "stop_area:IDFM:71456", "to_name": "Châtillon - Montrouge",
         "direction": "Châtillon - Montrouge", "minutes": 23, "at": "08:31"}]},
      {"kind": "less_fallback", "minutes": 54, "walk_minutes": 6, "transfers": 0,
       "departure": "08:02", "arrival": "08:56", "legs": [
        {"line_id": "line:IDFM:C01729", "line_code": "E", "line_name": "E",
         "line_mode": "RER", "line_color": "B94E9A", "from_id": "stop_area:IDFM:71359",
         "from_name": "Haussmann Saint-Lazare", "to_id": "stop_area:IDFM:68385", "to_name": "Chelles - Gournay",
         "direction": "Chelles - Gournay", "minutes": 48, "at": "08:08"}]},
      {"kind": "less_walk", "minutes": 58, "walk_minutes": 3, "transfers": 2,
       "departure": "08:00", "arrival": "08:58", "legs": [
        {"line_id": "line:IDFM:C01254", "line_code": "272", "line_name": "272",
         "line_mode": "Bus", "line_color": "FF5A00", "from_id": "stop_area:IDFM:411436",
         "from_name": "Gare d'Argenteuil", "to_id": "stop_area:IDFM:43191", "to_name": "Sartrouville",
         "direction": "Sartrouville RER", "minutes": 14, "at": "08:03"},
        {"line_id": "line:IDFM:C01742", "line_code": "A", "line_name": "A",
         "line_mode": "RER", "line_color": "E3051C", "from_id": "stop_area:IDFM:43191",
         "from_name": "Sartrouville", "to_id": "stop_area:IDFM:473829", "to_name": "Auber",
         "direction": "Boissy-Saint-Léger", "minutes": 21, "at": "08:20"},
        {"line_id": "line:IDFM:C01383", "line_code": "13", "line_name": "13",
         "line_mode": "Métro", "line_color": "82C8E6", "from_id": "stop_area:IDFM:71370",
         "from_name": "Gare Saint-Lazare", "to_id": "stop_area:IDFM:71456", "to_name": "Châtillon - Montrouge",
         "direction": "Châtillon - Montrouge", "minutes": 14, "at": "08:43"}]}
    ]}
    """

    static var plan: PlanResponse { decode(planJSON) }
    static var planOptions: [PlanOption] { plan.options }

    // MARK: - Alternativas (Alternatives, AlternativesNotNeeded)

    static let alternativesJSON = """
    {"needed": true, "baseline_minutes": 47, "age": 2.1,
     "quota": {"stop-monitoring": 282, "general-message": 946, "navitia": 912},
     "affected": [{"line_id": "line:IDFM:C01383", "line_code": "13", "level": 2, "label": "interrumpida"}],
     "options": [
       {"total_minutes": 59, "transfers": 1, "delta_minutes": 12, "usable": true,
        "worst_level": 0, "departure": "20260924T125500", "arrival": "20260924T135400", "legs": [
          {"code": "14", "mode": "Métro", "direction": "Olympiades",
           "color": "640082", "minutes": 18, "status": "normal"},
          {"code": "6", "mode": "Métro", "direction": "Nation",
           "color": "6ECA97", "minutes": 22, "status": "normal"}]},
       {"total_minutes": 51, "transfers": 1, "delta_minutes": 4, "usable": false,
        "worst_level": 2, "departure": "20260924T125200", "arrival": "20260924T134300", "legs": [
          {"code": "13", "mode": "Métro", "direction": "Châtillon - Montrouge",
           "color": "82C8E6", "minutes": 20, "status": "interrumpida"},
          {"code": "4", "mode": "Métro", "direction": "Mairie de Montrouge",
           "color": "BE418D", "minutes": 19, "status": "normal"}]}
     ]}
    """

    /// Ninguna línea tocada y sin `force`: la respuesta corta.
    static let alternativesNotNeededJSON = #"{"needed": false, "affected": [], "options": []}"#

    /// Hay línea tocada pero el calculador no encuentra otro camino.
    static let alternativesNoOptionsJSON = """
    {"needed": true, "baseline_minutes": 47, "age": 0.8, "quota": {"navitia": 911},
     "affected": [{"line_id": "line:IDFM:C01384", "line_code": "14", "level": 2, "label": "interrumpida"}],
     "options": []}
    """

    /// Diferencias 0, negativa y desconocida; una usable pero perturbada.
    static let alternativesDeltasJSON = """
    {"needed": false, "baseline_minutes": null, "age": 1.0, "quota": {"navitia": 905},
     "affected": [],
     "options": [
       {"total_minutes": 47, "transfers": 0, "delta_minutes": 0, "usable": true, "worst_level": 1,
        "departure": "20260924T125800", "arrival": "20260924T134500", "legs": [
          {"code": "E", "mode": "RER", "direction": "Chelles - Gournay", "color": "B94E9A", "minutes": 40, "status": "perturbada"}]},
       {"total_minutes": 44, "transfers": 1, "delta_minutes": -3, "usable": true, "worst_level": 0,
        "departure": "20260924T130100", "arrival": "20260924T134500", "legs": [
          {"code": "J", "mode": "Train Transilien", "direction": "Gare Saint-Lazare", "color": "CEC73D", "minutes": 17, "status": "normal"},
          {"code": "14", "mode": "Métro", "direction": "Olympiades", "color": "640082", "minutes": 16, "status": "normal"}]}
     ]}
    """

    static var alternatives: AlternativesResponse { decode(alternativesJSON) }

    // MARK: - Estadísticas (StatsV1, PlatformModel)

    static let statsJSON = """
    {"by_month": [
       {"month": "2026-09", "bad_days": 9, "total_days": 17, "avg_delay": 2.8},
       {"month": "2026-08", "bad_days": 11, "total_days": 21, "avg_delay": 3.42},
       {"month": "2026-07", "bad_days": 6, "total_days": 22, "avg_delay": null}],
     "by_line": [
       {"worst_line": "13", "n": 24, "avg_delay": 4.6},
       {"worst_line": "J", "n": 9, "avg_delay": 6.1},
       {"worst_line": "147", "n": 4, "avg_delay": null}],
     "overall": {"n": 128, "avg_delay": 3.42, "max_delay": 27.0}}
    """

    static let platformModelJSON = """
    {"accuracy": {"predictions": 214, "hits": 179, "rate": 0.84, "observations": 4820, "days": 26},
     "collector": \(collectorRunning),
     "route": {"id": 3, "name": "Casa → Trabajo"},
     "coverage": [
       {"seq": 0, "line_code": "6424", "observations": 0, "days": 0, "platforms": 0},
       {"seq": 2, "line_code": "E", "observations": 3120, "days": 26, "platforms": 4},
       {"seq": 3, "line_code": "13", "observations": 0, "days": 0, "platforms": 0}]}
    """

    /// Aún no hay con qué puntuar: el porcentaje es «—» (R11).
    static let platformModelNoDataJSON = """
    {"accuracy": {"predictions": 0, "hits": 0, "rate": null, "observations": 12, "days": 1},
     "collector": \(collectorRunning)}
    """

    static var stats: StatsResponse { decode(statsJSON) }
    static var platformModel: PlatformModelResponse { decode(platformModelJSON) }

    // MARK: - Buscadores

    static let stopSearchJSON = """
    {"age": 0, "stops": [
      {"id": "stop_area:IDFM:71370", "name": "Gare Saint-Lazare", "city": "Paris", "lines": [
        {"id": "line:IDFM:C01739", "code": "J", "mode": "Train Transilien", "color": "CEC73D"},
        {"id": "line:IDFM:C01384", "code": "14", "mode": "Métro", "color": "640082"},
        {"id": null, "code": null, "mode": "", "color": ""}]},
      {"id": "stop_area:IDFM:65063", "name": "Argenteuil", "city": "Argenteuil", "lines": []}]}
    """

    static let placeSearchJSON = """
    {"places": [
      {"id": "stop_area:IDFM:71370", "name": "Gare Saint-Lazare", "city": "Paris", "kind": "parada"},
      {"id": "2.25212;48.94702", "name": "12 Rue de Paris", "city": "Argenteuil", "kind": "dirección"},
      {"id": "poi:osm:node:3112427551", "name": "Stade de France", "city": "Saint-Denis", "kind": "sitio"}]}
    """

    static let stopLinesJSON = """
    {"lines": [
      {"id": "line:IDFM:C01384", "code": "14", "name": "14", "mode": "Métro", "color": "640082"},
      {"id": "line:IDFM:C01729", "code": "E", "name": "E", "mode": "RER", "color": "B94E9A"},
      {"id": "line:IDFM:C01739", "code": "J", "name": "J", "mode": "Train Transilien", "color": "CEC73D"},
      {"id": "line:IDFM:C01254", "code": "272", "name": "272", "mode": "Bus", "color": "FF5A00"}]}
    """

    static let directionsJSON = #"{"directions": ["Ermont - Eaubonne", "Mantes-la-Jolie", "Gisors"], "age": 12.4}"#

    // MARK: - JSON raros (NO son la forma de la API: prueban la tolerancia)

    enum OddCase: String, CaseIterable, Sendable {
        /// `{}`: un tablero vacío, sin reventar.
        case objetoVacio
        /// Tipos cambiados: minutos como texto, tramos como texto, nulos.
        case tiposCambiados
        /// El número de tren como número (R22).
        case trenNumero
        /// Fichero antiguo con `age` en vez de `data_age` (R22).
        case ageAntiguo
        /// `route: null` y sin `server` ni `disruptions_ok` (tablero 0.3.0).
        case tableroSinRuta
        /// Enumerados con valores que la app no conoce.
        case enumsDesconocidos
        /// `time_mode` desconocido y días fuera de rango.
        case rutaRara
        /// Plan sin opciones.
        case planVacio
        /// Mapa mínimo, casi sin nada.
        case mapaMinimo
        /// Error de la API 0.3.0: `{"detail": "…"}`.
        case errorLegado
    }

    static func oddJSON(_ c: OddCase) -> String {
        switch c {
        case .objetoVacio:
            return "{}"
        case .tiposCambiados:
            return """
            {"route": {"id": "3", "name": 42}, "legs": [
              {"seq": "0", "line_code": 13, "line_color": null, "directions": "todas", "status": {"level": "2", "messages": null},
               "departures": [{"jid": null, "minutes": "6", "at": 1250, "platform": 11, "platform_new": "sí",
                               "delay": "tarde", "at_stop": 1, "length": "medium", "guess": {"platform": 7, "share": "mucha"}}],
               "age": "viejo", "platform_expected": "no"}],
             "worst_level": null, "data_age": "8", "stale": "no", "errors": "ninguno", "quota": {"stop-monitoring": "282"},
             "server": "bien", "disruptions_ok": null}
            """
        case .trenNumero:
            return """
            {"legs": [{"seq": 0, "line_code": "J", "line_mode": "Train Transilien", "departures": [
              {"jid": "t1", "minutes": 6, "at": "12:56", "train": 135711},
              {"jid": "t2", "minutes": 21, "at": "13:11", "train": "135713"}]}]}
            """
        case .ageAntiguo:
            return #"{"age": 12, "legs": [], "stale": false}"#
        case .tableroSinRuta:
            return """
            {"route": null, "legs": [], "worst_level": 0, "worst_line": "", "max_delay": 0,
             "updated_at": "2026-08-30T12:50:03+00:00", "data_age": 6.0, "stale": false, "errors": [],
             "quota": {}, "last_error": null, "auto_selected": true}
            """
        case .enumsDesconocidos:
            return """
            {"prim_key": "rara", "quota_level": "nuevo", "refresh_hint_s": "treinta", "degraded": "quizá"}
            """
        case .rutaRara:
            return """
            {"id": 9, "name": "Rara", "days": [0, 1, 2, 3, 4, 5, 6, 9], "time_mode": "fortnight",
             "time_from": null, "legs": [{"seq": 1, "line_code": "A"}, {"seq": 0, "line_code": "B"}]}
            """
        case .planVacio:
            return #"{"options": [], "age": 0}"#
        case .mapaMinimo:
            return #"{"route_id": 1, "lines": [{"seq": 0, "code": "J", "mode": "hovercraft", "path": null}]}"#
        case .errorLegado:
            return #"{"detail": "ruta no encontrada"}"#
        }
    }

    // MARK: - Catálogo (lo recorre DecodingTests)

    struct Sample: Sendable {
        let name: String
        let json: String
        let check: @Sendable (Data) throws -> Void
    }

    // `Sendable`: el cierre es @Sendable y se lleva el tipo (Swift 6.2 avisa
    // si su metatipo no lo es). Todos los modelos lo son.
    static func sample<T: Decodable & Sendable>(_ name: String, _ json: String, as type: T.Type) -> Sample {
        Sample(name: name, json: json) { data in
            _ = try JSONDecoder.trajet.decode(T.self, from: data)
        }
    }

    /// Todos los bancos con la forma de la API, cada uno con su tipo.
    static var catalog: [Sample] {
        var all: [Sample] = []
        for c in BoardCase.allCases {
            all.append(sample("tablero.\(c.rawValue)", boardJSON(c), as: Board.self))
            all.append(sample("payload.\(c.rawValue)", boardJSON(c), as: BoardPayload.self))
        }
        all.append(sample("tablero.vacio", emptyBoardJSON, as: BoardPayload.self))
        for c in ErrorCase.allCases { all.append(sample("error.\(c.rawValue)", errorJSON(c), as: APIErrorBody.self)) }
        for c in HealthCase.allCases { all.append(sample("salud.\(c.rawValue)", healthJSON(c), as: ServerHealth.self)) }
        all += [
            sample("ping", pingJSON, as: PingResponse.self),
            sample("ping.emparejado", pingPairedJSON, as: PingResponse.self),
            sample("pair", pairResultJSON(), as: PairResult.self),
            sample("dispositivo", deviceJSON, as: DeviceInfo.self),
            sample("desemparejar", unpairJSON, as: UnpairResult.self),
            sample("rutas", routesJSON, as: RoutesResponse.self),
            sample("ruta", singleRouteJSON, as: SavedRoute.self),
            sample("ruta.guardada", routeSavedJSON, as: RouteSaved.self),
            sample("ruta.borrada", routeDeletedJSON, as: RouteDeleted.self),
            sample("plan.guardado", planSavedJSON, as: PlanSaveResponse.self),
            sample("plan.guardadoSinSentido", planSavedWithoutDirectionJSON, as: PlanSaveResponse.self),
            sample("mapa", routeMapJSON(), as: RouteMap.self),
            sample("mapa.calculando", routeMapPendingJSON, as: RouteMap.self),
            sample("plan", planJSON, as: PlanResponse.self),
            sample("alternativas", alternativesJSON, as: AlternativesResponse.self),
            sample("alternativas.noHacenFalta", alternativesNotNeededJSON, as: AlternativesResponse.self),
            sample("alternativas.sinOpciones", alternativesNoOptionsJSON, as: AlternativesResponse.self),
            sample("alternativas.diferencias", alternativesDeltasJSON, as: AlternativesResponse.self),
            sample("estadisticas", statsJSON, as: StatsResponse.self),
            sample("prevision", platformModelJSON, as: PlatformModelResponse.self),
            sample("prevision.sinDatos", platformModelNoDataJSON, as: PlatformModelResponse.self),
            sample("buscar.paradas", stopSearchJSON, as: StopSearchResponse.self),
            sample("buscar.sitios", placeSearchJSON, as: PlaceSearchResponse.self),
            sample("parada.lineas", stopLinesJSON, as: StopLinesResponse.self),
            sample("parada.sentidos", directionsJSON, as: DirectionsResponse.self),
        ]
        return all
    }

    // MARK: - Fontanería de los JSON

    struct Line: Sendable {
        let id: String
        let code: String
        let mode: String
        let color: String
    }

    typealias Stop = (String, String)       // (id, nombre)

    static let lineJ = Line(id: "line:IDFM:C01739", code: "J", mode: "Train Transilien", color: "CEC73D")
    static let metro14 = Line(id: "line:IDFM:C01384", code: "14", mode: "Métro", color: "640082")
    static let metro13 = Line(id: "line:IDFM:C01383", code: "13", mode: "Métro", color: "82C8E6")
    static let metro5 = Line(id: "line:IDFM:C01375", code: "5", mode: "Métro", color: "FF7E2E")
    static let rerE = Line(id: "line:IDFM:C01729", code: "E", mode: "RER", color: "B94E9A")
    static let rerA = Line(id: "line:IDFM:C01742", code: "A", mode: "RER", color: "E3051C")
    static let tramT2 = Line(id: "line:IDFM:C01390", code: "T2", mode: "Tramway", color: "C4318E")
    static let bus6424 = Line(id: "line:IDFM:C00306", code: "6424", mode: "Bus", color: "A50034")
    static let bus147 = Line(id: "line:IDFM:C01199", code: "147", mode: "Bus", color: "E4022D")
    static let bus272 = Line(id: "line:IDFM:C01254", code: "272", mode: "Bus", color: "FF5A00")

    static let saintLazare: Stop = ("stop_area:IDFM:71370", "Gare Saint-Lazare")
    static let saintLazareMetro: Stop = ("stop_area:IDFM:71370", "Saint-Lazare")
    static let argenteuil: Stop = ("stop_area:IDFM:65063", "Argenteuil")
    static let olympiades: Stop = ("stop_area:IDFM:70604", "Olympiades")
    static let haussmann: Stop = ("stop_area:IDFM:71359", "Haussmann Saint-Lazare")
    static let chelles: Stop = ("stop_area:IDFM:68385", "Chelles - Gournay")
    static let marseillaise: Stop = ("stop_area:IDFM:420512", "Marseillaise")
    static let pontBezons: Stop = ("stop_area:IDFM:418834", "Pont de Bezons")
    static let parcBezons: Stop = ("stop_area:IDFM:418835", "Parc de Bezons")
    static let porteVersailles: Stop = ("stop_area:IDFM:71138", "Porte de Versailles")
    static let eglisePantin: Stop = ("stop_area:IDFM:70021", "Église de Pantin")
    static let gallieni: Stop = ("stop_area:IDFM:70003", "Gallieni")
    static let montparnasse: Stop = ("stop_area:IDFM:71139", "Montparnasse Bienvenüe")
    static let gareNord: Stop = ("stop_area:IDFM:71410", "Gare du Nord")
    static let placeItalie: Stop = ("stop_area:IDFM:70375", "Place d'Italie")
    static let nation: Stop = ("stop_area:IDFM:71673", "Nation")
    static let auber: Stop = ("stop_area:IDFM:473829", "Auber")
    static let chatelet: Stop = ("stop_area:IDFM:474151", "Châtelet - Les Halles")
    static let nanterre: Stop = ("stop_area:IDFM:470549", "Nanterre - Préfecture")
    static let argenteuilBus: Stop = ("stop_area:IDFM:411436", "Gare d'Argenteuil")
    static let sartrouville: Stop = ("stop_area:IDFM:43191", "Sartrouville")

    static let route4 = (4, "Trabajo → Casa", "Olympiades", "Argenteuil")
    static let route5 = (5, "Saint-Lazare → Argenteuil", "Gare Saint-Lazare", "Argenteuil")

    static let serverNormal = serverJSON(quota: "ok", hint: 30, degraded: false)

    static func serverJSON(key: String = "valid", quota: String, hint: Int, degraded: Bool) -> String {
        #"{"prim_key": "\#(key)", "quota_level": "\#(quota)", "refresh_hint_s": \#(hint), "degraded": \#(degraded)}"#
    }

    static let primValid = #"{"key_state": "valid", "key_source": "panel", "checked_at": "2026-09-24T08:12:40+00:00", "last_error": null}"#
    static let collectorRunning = #"{"enabled": true, "running": true, "last_at": "12:41:07", "session_total": 38, "stations": 3, "recorded": 2, "reason": "ritmo normal", "interval": 420, "remaining": 682, "priority": true}"#
    static let accuracyGood = #"{"predictions": 214, "hits": 179, "rate": 0.84, "observations": 4820, "days": 26}"#
    static let translatorOK = #"{"ok": true, "reason": "", "model": "qwen2.5:3b", "models": ["qwen2.5:3b", "llama3.2:3b"]}"#

    /// Texto JSON (con comillas) o `null`.
    static func j(_ s: String?) -> String {
        guard let s else { return "null" }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func guessJSON(_ platform: String, _ share: Double, _ samples: Int, _ basis: String) -> String {
        let why: String
        switch basis {
        case "mision": why = "por el número de tren"
        case "hora": why = "por la hora habitual"
        default: why = "por la línea"
        }
        return #"{"platform": \#(j(platform)), "share": \#(share), "samples": \#(samples), "basis": \#(j(basis)), "why": \#(j(why))}"#
    }

    static func dep(_ jid: String, _ minutes: Int, _ at: String, aimed: String = "", to destination: String,
                    platform: String? = nil, new: Bool = false, delay: Int? = nil, status: String = "onTime",
                    atStop: Bool = false, train: String? = nil, length: String? = nil, guess: String? = nil) -> String {
        let delayText = delay.map { String($0) } ?? "null"
        var s = #"{"jid": \#(j(jid)), "minutes": \#(minutes), "at": \#(j(at)), "aimed_at": \#(j(aimed)), "#
        s += #""destination": \#(j(destination)), "platform": \#(j(platform)), "platform_new": \#(new), "#
        s += #""delay": \#(delayText), "status": \#(j(status)), "at_stop": \#(atStop), "#
        s += #""train": \#(j(train)), "length": \#(j(length))"#
        if let guess { s += #", "guess": \#(guess)"# }
        return s + "}"
    }

    static func lineStatus(_ level: Int, messages: [String] = [], es: [String?] = [],
                           translating: Bool = false, planned: Int = 0) -> String {
        let labels = ["normal", "perturbada", "interrumpida"]
        let label = labels[min(max(level, 0), 2)]
        let fr = messages.map { j($0) }.joined(separator: ", ")
        var s = #"{"level": \#(level), "label": "\#(label)", "messages": [\#(fr)], "planned": \#(planned)"#
        if !messages.isEmpty {
            let translated = es.map { j($0) }.joined(separator: ", ")
            s += #", "messages_es": [\#(translated)], "translating": \#(translating)"#
        }
        return s + "}"
    }

    static let normalStatus = lineStatus(0)

    /// ¿Publica vía este modo? Lo que manda el servidor en `platform_expected`.
    static func platformExpected(_ mode: String) -> Bool {
        ["RER", "Train Transilien", "Train", "TER"].contains(mode)
    }

    static func leg(_ seq: Int, _ line: Line, from: Stop, to: Stop, directions: [String],
                    status: String = PreviewData.normalStatus, age: Double? = 3.0, departures: [String]) -> String {
        let dirs = directions.map { j($0) }.joined(separator: ", ")
        let ageText = age.map { String($0) } ?? "null"
        let expected = platformExpected(line.mode)
        let deps = departures.joined(separator: ", ")
        var s = #"{"seq": \#(seq), "line_id": \#(j(line.id)), "line_code": \#(j(line.code)), "line_name": \#(j(line.code)), "#
        s += #""line_mode": \#(j(line.mode)), "line_color": \#(j(line.color)), "#
        s += #""from_id": \#(j(from.0)), "from_name": \#(j(from.1)), "to_id": \#(j(to.0)), "to_name": \#(j(to.1)), "#
        s += #""directions": [\#(dirs)], "status": \#(status), "age": \#(ageText), "#
        s += #""platform_expected": \#(expected), "departures": [\#(deps)]}"#
        return s
    }

    static func leg14(age: Double = 2.0) -> String {
        leg(0, metro14, from: olympiades, to: saintLazareMetro, directions: ["Saint-Denis Pleyel"], age: age, departures: [
            dep("q1", 1, "12:51", to: "Saint-Denis Pleyel"),
            dep("q2", 3, "12:53", to: "Saint-Denis Pleyel"),
            dep("q3", 6, "12:56", to: "Saint-Denis Pleyel"),
        ])
    }

    static func legJ(dataAge: Double) -> String {
        leg(1, lineJ, from: saintLazare, to: argenteuil, directions: ["Ermont - Eaubonne"], age: dataAge, departures: [
            dep("j1", 16, "13:06", aimed: "13:06", to: "Ermont - Eaubonne", platform: "21",
                delay: 0, train: "137412", length: "long"),
            dep("j2", 31, "13:21", aimed: "13:21", to: "Ermont - Eaubonne",
                train: "137416", length: "short", guess: guessJSON("21", 0.9, 20, "mision")),
            dep("j3", 46, "13:36", aimed: "13:36", to: "Ermont - Eaubonne", train: "137420"),
        ])
    }

    static func boardV1(route: (Int, String, String, String), legs: [String], worstLevel: Int = 0,
                        worstLine: String = "", maxDelay: Double = 0, dataAge: Double = 6.2,
                        stale: Bool = false, errors: [String] = [],
                        quota: String = #"{"stop-monitoring": 640, "general-message": 912, "navitia": 930}"#,
                        lastError: String? = nil, autoSelected: Bool = true,
                        server: String = PreviewData.serverNormal, disruptionsOK: Bool = true,
                        updatedAt: String = "2026-09-24T10:50:03+00:00") -> String {
        let routeText = #"{"id": \#(route.0), "name": \#(j(route.1)), "origin_name": \#(j(route.2)), "dest_name": \#(j(route.3))}"#
        let legsText = legs.joined(separator: ",\n  ")
        let errorsText = errors.map { j($0) }.joined(separator: ", ")
        var s = #"{"route": \#(routeText), "legs": [\#(legsText)], "#
        s += #""worst_level": \#(worstLevel), "worst_line": \#(j(worstLine)), "max_delay": \#(maxDelay), "#
        s += #""updated_at": \#(j(updatedAt)), "data_age": \#(dataAge), "stale": \#(stale), "#
        s += #""errors": [\#(errorsText)], "quota": \#(quota), "last_error": \#(j(lastError)), "#
        s += #""auto_selected": \#(autoSelected), "server": \#(server), "disruptions_ok": \#(disruptionsOK)}"#
        return s
    }

    static func healthV1(prim: String, quota: String, collector: String, accuracy: String, translator: String) -> String {
        var s = #"{"ok": true, "version": "0.4.0", "api": 1, "now_paris": "2026-09-24 12:50:03", "schema_version": 2, "#
        s += #""prim": \#(prim), "quota": \#(quota), "collector": \#(collector), "#
        s += #""platform_model": \#(accuracy), "translator": \#(translator)}"#
        return s
    }

    static func quotaSnapshot(level: String, hint: Int, used: (Int, Int, Int)) -> String {
        func endpoint(_ name: String, _ n: Int, reported: Bool) -> String {
            let lvl: String
            if n >= 950 { lvl = "exhausted" } else if n >= 850 { lvl = "critical" } else if n >= 700 { lvl = "warn" } else { lvl = "ok" }
            let remaining = reported ? String(1000 - n) : "null"
            return #"{"endpoint": "\#(name)", "used": \#(n), "cap": 1000, "remaining_reported": \#(remaining), "level": "\#(lvl)"}"#
        }
        let sm = endpoint("stop-monitoring", used.0, reported: used.0 > 0)
        let gm = endpoint("general-message", used.1, reported: used.1 > 0)
        let nv = endpoint("navitia", used.2, reported: false)
        var s = #"{"day_utc": "2026-09-24", "resets_at": "2026-09-25T00:00:00+00:00", "#
        s += #""level": "\#(level)", "refresh_hint_s": \#(hint), "endpoints": [\#(sm), \#(gm), \#(nv)]}"#
        return s
    }

    static func routeLeg(_ id: Int, _ routeID: Int, _ seq: Int, _ line: Line, from: Stop, to: Stop,
                         directions: [String]) -> String {
        let dirs = directions.map { j($0) }.joined(separator: ", ")
        var s = #"{"id": \#(id), "route_id": \#(routeID), "seq": \#(seq), "line_id": \#(j(line.id)), "#
        s += #""line_code": \#(j(line.code)), "line_name": \#(j(line.code)), "line_mode": \#(j(line.mode)), "#
        s += #""line_color": \#(j(line.color)), "from_id": \#(j(from.0)), "from_name": \#(j(from.1)), "#
        s += #""to_id": \#(j(to.0)), "to_name": \#(j(to.1)), "directions": [\#(dirs)]}"#
        return s
    }

    static func routeJSON(id: Int, name: String, origin: Stop, dest: Stop, days: [Int], from: String, to: String,
                          mode: String, at: String, duration: Int, position: Int, legs: [String]) -> String {
        let daysText = days.map { String($0) }.joined(separator: ", ")
        let legsText = legs.joined(separator: ", ")
        var s = #"{"id": \#(id), "name": \#(j(name)), "origin_id": \#(j(origin.0)), "origin_name": \#(j(origin.1)), "#
        s += #""dest_id": \#(j(dest.0)), "dest_name": \#(j(dest.1)), "days": [\#(daysText)], "#
        s += #""time_from": \#(j(from)), "time_to": \#(j(to)), "time_mode": \#(j(mode)), "time_at": \#(j(at)), "#
        s += #""duration_min": \#(duration), "position": \#(position), "created_at": "2026-09-01 07:12:44", "#
        s += #""legs": [\#(legsText)]}"#
        return s
    }
}

extension PlatformGuess {
    static var preview: PlatformGuess { PreviewData.guess }
}
#endif
