#if DEBUG
import Foundation

// Bancos de prueba para las vistas previas de Xcode. Son respuestas con la
// forma exacta de la API, no maquetas: así lo que se ve en el lienzo es lo
// que se va a ver en el andén.
//
// Cubren los casos que el manual manda dibujar y que un JSON feliz esconde:
// tramo vacío, línea cortada, aviso sin traducir, vía que aparece, vía solo
// probable, bus a 106 minutos, tren parado en el andén y destinos mezclados.

enum PreviewData {

    static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) -> T {
        // swiftlint:disable:next force_try
        try! JSONDecoder.trajet.decode(T.self, from: Data(json.utf8))
    }

    /// Cinco tramos: es la ruta real de casa al trabajo y el caso difícil.
    static var fiveLegBoard: Board { decode(fiveLegJSON) }

    /// Dos tramos, todo normal. El caso corriente.
    static var calmBoard: Board { decode(calmJSON) }

    /// Instalación limpia.
    static var emptyBoard: Board { decode(#"{"empty": true, "message": "todavia no hay rutas guardadas"}"#) }

    static var guess: PlatformGuess {
        decode(#"{"platform":"11","share":0.82,"samples":17,"basis":"mision","why":"por el número de tren"}"#)
    }

    static var routes: [SavedRoute] { decode(routesJSON, as: RoutesResponse.self).routes }
    static var stats: StatsResponse { decode(statsJSON) }
    static var platformModel: PlatformModelResponse { decode(platformModelJSON) }
    static var planOptions: [PlanOption] { decode(planJSON, as: PlanResponse.self).options }
    static var alternatives: AlternativesResponse { decode(alternativesJSON) }

    // ---------------- los JSON ----------------

    static let fiveLegJSON = """
    {
      "route": {"id": 3, "name": "Casa → Trabajo",
                "origin_name": "6 Rue de la Marseillaise", "dest_name": "74 Rue de Paris"},
      "worst_level": 2, "worst_line": "13", "max_delay": 11,
      "updated_at": "2026-08-30T12:50:03+00:00", "data_age": 8.2, "stale": false,
      "errors": ["Victor Basch: tiempo de espera agotado"],
      "quota": {"stop-monitoring": 282, "general-message": 946, "navitia": 915},
      "last_error": null, "auto_selected": true,
      "legs": [
        {"seq": 0, "line_id": "line:IDFM:C00306", "line_code": "6424", "line_name": "6424",
         "line_mode": "Bus", "line_color": "A50034", "from_name": "Marseillaise",
         "to_name": "Pont de Bezons", "directions": ["Pont de Bezons"],
         "status": {"level": 0, "label": "normal", "messages": [], "planned": 0},
         "age": 4.1,
         "departures": [
           {"jid": "b1", "minutes": 6, "at": "12:56", "aimed_at": "12:45",
            "destination": "Pont de Bezons", "platform": null, "platform_new": false,
            "delay": 11, "status": "delayed", "at_stop": false, "train": null, "length": null},
           {"jid": "b2", "minutes": 56, "at": "13:46", "aimed_at": "13:45",
            "destination": "Pont de Bezons", "platform": null, "platform_new": false,
            "delay": 1, "status": "onTime", "at_stop": false, "train": null, "length": null},
           {"jid": "b3", "minutes": 106, "at": "14:36", "aimed_at": "14:35",
            "destination": "Pont de Bezons", "platform": null, "platform_new": false,
            "delay": 1, "status": "onTime", "at_stop": false, "train": null, "length": null}
         ]},

        {"seq": 1, "line_id": "line:IDFM:C01390", "line_code": "T2", "line_name": "T2",
         "line_mode": "Tramway", "line_color": "C4318E", "from_name": "Parc de Bezons",
         "to_name": "Porte de Versailles", "directions": ["Porte de Versailles"],
         "status": {"level": 0, "label": "normal", "messages": [], "planned": 0},
         "age": 3.0, "departures": []},

        {"seq": 2, "line_id": "line:IDFM:C01743", "line_code": "E", "line_name": "E",
         "line_mode": "RER", "line_color": "B94E9A", "from_name": "Haussmann Saint-Lazare",
         "to_name": "Chelles - Gournay", "directions": ["Chelles - Gournay"],
         "status": {"level": 0, "label": "normal", "messages": [], "planned": 1},
         "age": 2.4,
         "departures": [
           {"jid": "e1", "minutes": 4, "at": "12:54", "aimed_at": "12:52",
            "destination": "Chelles - Gournay", "platform": "11", "platform_new": true,
            "delay": 2, "status": "onTime", "at_stop": false, "train": "135711", "length": "long"},
           {"jid": "e2", "minutes": 12, "at": "13:02", "aimed_at": "13:02",
            "destination": "Chelles - Gournay", "platform": null, "platform_new": false,
            "delay": 0, "status": "onTime", "at_stop": false, "train": "135713",
            "guess": {"platform": "11", "share": 0.82, "samples": 17,
                      "basis": "mision", "why": "por el número de tren"},
            "length": "short"},
           {"jid": "e3", "minutes": 22, "at": "13:12", "aimed_at": "13:12",
            "destination": "Chelles - Gournay", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": "135715",
            "guess": {"platform": "7", "share": 0.55, "samples": 9,
                      "basis": "hora", "why": "por la hora habitual"},
            "length": null}
         ]},

        {"seq": 3, "line_id": "line:IDFM:C01383", "line_code": "13", "line_name": "13",
         "line_mode": "Métro", "line_color": "82C8E6", "from_name": "Gare Saint-Lazare",
         "to_name": "", "directions": [],
         "status": {"level": 2, "label": "interrumpida",
                    "messages": ["Le trafic est interrompu entre Châtillon-Montrouge et Montparnasse suite à un incident technique."],
                    "messages_es": [null], "translating": true, "planned": 0},
         "age": 1.8,
         "departures": [
           {"jid": "m1", "minutes": 0, "at": "12:50", "aimed_at": "",
            "destination": "Place d'Italie", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": true, "train": null, "length": null},
           {"jid": "m2", "minutes": 3, "at": "12:53", "aimed_at": "",
            "destination": "Bobigny-Pablo-Picasso", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null},
           {"jid": "m3", "minutes": 9, "at": "12:59", "aimed_at": "",
            "destination": "Place d'Italie", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null}
         ]},

        {"seq": 4, "line_id": "line:IDFM:C01199", "line_code": "147", "line_name": "147",
         "line_mode": "Bus", "line_color": "E4022D", "from_name": "Église de Pantin",
         "to_name": "Gallieni", "directions": ["Gallieni - Pont de Bondy"],
         "status": {"level": 1, "label": "perturbada",
                    "messages": ["Trafic ralenti en raison de travaux sur la voirie."],
                    "messages_es": ["Tráfico lento por obras en la calzada."],
                    "translating": false, "planned": 0},
         "age": 5.5,
         "departures": [
           {"jid": "s1", "minutes": 2, "at": "12:52", "aimed_at": "",
            "destination": "Gallieni - Pont de Bondy", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null},
           {"jid": "s2", "minutes": 27, "at": "13:17", "aimed_at": "",
            "destination": "Gallieni - Pont de Bondy", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null}
         ]}
      ]
    }
    """

    static let calmJSON = """
    {
      "route": {"id": 1, "name": "Trabajo → Casa",
                "origin_name": "Gare Saint-Lazare", "dest_name": "Argenteuil"},
      "worst_level": 0, "worst_line": "", "max_delay": 0,
      "updated_at": "2026-08-30T12:50:03+00:00", "data_age": 6.0, "stale": false,
      "errors": [], "quota": {"stop-monitoring": 640}, "auto_selected": false,
      "legs": [
        {"seq": 0, "line_id": "line:IDFM:C01739", "line_code": "J", "line_name": "J",
         "line_mode": "Train Transilien", "line_color": "CEC73D",
         "from_name": "Gare Saint-Lazare", "to_name": "Ermont - Eaubonne",
         "directions": ["Ermont - Eaubonne"],
         "status": {"level": 0, "label": "normal", "messages": [], "planned": 0},
         "age": 3.2,
         "departures": [
           {"jid": "j1", "minutes": 6, "at": "12:56", "aimed_at": "12:56",
            "destination": "Ermont - Eaubonne", "platform": "21", "platform_new": false,
            "delay": 0, "status": "onTime", "at_stop": false, "train": "137412", "length": "long"},
           {"jid": "j2", "minutes": 21, "at": "13:11", "aimed_at": "13:11",
            "destination": "Ermont - Eaubonne", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": "137416",
            "guess": {"platform": "21", "share": 0.9, "samples": 20,
                      "basis": "mision", "why": "por el número de tren"},
            "length": "short"},
           {"jid": "j3", "minutes": 36, "at": "13:26", "aimed_at": "13:26",
            "destination": "Ermont - Eaubonne", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": "137420", "length": null}
         ]},
        {"seq": 1, "line_id": "line:IDFM:C01372", "line_code": "14", "line_name": "14",
         "line_mode": "Métro", "line_color": "640082", "from_name": "Saint-Lazare",
         "to_name": "Olympiades", "directions": ["Olympiades"],
         "status": {"level": 0, "label": "normal", "messages": [], "planned": 0},
         "age": 2.0,
         "departures": [
           {"jid": "q1", "minutes": 1, "at": "12:51", "aimed_at": "",
            "destination": "Olympiades", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null},
           {"jid": "q2", "minutes": 3, "at": "12:53", "aimed_at": "",
            "destination": "Olympiades", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null},
           {"jid": "q3", "minutes": 6, "at": "12:56", "aimed_at": "",
            "destination": "Olympiades", "platform": null, "platform_new": false,
            "delay": null, "status": "onTime", "at_stop": false, "train": null, "length": null}
         ]}
      ]
    }
    """

    static let routesJSON = """
    {"active_id": 3, "routes": [
      {"id": 3, "name": "Casa → Trabajo", "origin_id": "a", "origin_name": "6 Rue de la Marseillaise",
       "dest_id": "b", "dest_name": "74 Rue de Paris", "days": [0,1,2,3,4],
       "time_from": "07:15", "time_to": "09:15", "time_mode": "arrival", "time_at": "09:00",
       "duration_min": 62, "position": 0, "legs": [
         {"id": 1, "route_id": 3, "seq": 0, "line_id": "line:IDFM:C00306", "line_code": "6424",
          "line_name": "6424", "line_mode": "Bus", "line_color": "A50034",
          "from_id": "s1", "from_name": "Marseillaise", "to_id": "s2",
          "to_name": "Pont de Bezons", "directions": ["Pont de Bezons"]},
         {"id": 2, "route_id": 3, "seq": 1, "line_id": "line:IDFM:C01743", "line_code": "E",
          "line_name": "E", "line_mode": "RER", "line_color": "B94E9A",
          "from_id": "s3", "from_name": "Haussmann Saint-Lazare", "to_id": "s4",
          "to_name": "Chelles", "directions": ["Chelles - Gournay"]},
         {"id": 3, "route_id": 3, "seq": 2, "line_id": "line:IDFM:C01383", "line_code": "13",
          "line_name": "13", "line_mode": "Métro", "line_color": "82C8E6",
          "from_id": "s5", "from_name": "Gare Saint-Lazare", "to_id": "s6",
          "to_name": "", "directions": []}
       ]},
      {"id": 4, "name": "Trabajo → Casa", "origin_id": "b", "origin_name": "74 Rue de Paris",
       "dest_id": "a", "dest_name": "6 Rue de la Marseillaise", "days": [0,1,2,3,4],
       "time_from": "17:00", "time_to": "20:00", "time_mode": "window", "time_at": "",
       "duration_min": 0, "position": 1, "legs": [
         {"id": 4, "route_id": 4, "seq": 0, "line_id": "line:IDFM:C01739", "line_code": "J",
          "line_name": "J", "line_mode": "Train Transilien", "line_color": "CEC73D",
          "from_id": "s7", "from_name": "Gare Saint-Lazare", "to_id": "s8",
          "to_name": "Ermont", "directions": ["Ermont - Eaubonne"]}
       ]}
    ]}
    """

    static let statsJSON = """
    {"by_month": [
       {"month": "2026-08", "bad_days": 11, "total_days": 21, "avg_delay": 3.42},
       {"month": "2026-07", "bad_days": 6, "total_days": 22, "avg_delay": 1.9}],
     "by_line": [
       {"worst_line": "13", "n": 24, "avg_delay": 4.6},
       {"worst_line": "J", "n": 9, "avg_delay": 6.1},
       {"worst_line": "147", "n": 4, "avg_delay": 2.0}],
     "overall": {"n": 128, "avg_delay": 3.42, "max_delay": 27.0}}
    """

    static let platformModelJSON = """
    {"accuracy": {"predictions": 214, "hits": 179, "rate": 0.84,
                  "observations": 4820, "days": 26},
     "route": {"id": 3, "name": "Casa → Trabajo"},
     "coverage": [
       {"seq": 0, "line_code": "6424", "observations": 0, "days": 0, "platforms": 0},
       {"seq": 2, "line_code": "E", "observations": 3120, "days": 26, "platforms": 4},
       {"seq": 3, "line_code": "13", "observations": 0, "days": 0, "platforms": 0}]}
    """

    static let planJSON = """
    {"age": 1.2, "options": [
      {"kind": "best", "minutes": 47, "walk_minutes": 11, "transfers": 1,
       "departure": "08:07", "arrival": "08:54", "legs": [
        {"line_id": "line:IDFM:C01739", "line_code": "J", "line_name": "J",
         "line_mode": "Train Transilien", "line_color": "CEC73D", "from_id": "s1",
         "from_name": "Argenteuil", "to_id": "s2", "to_name": "Gare Saint-Lazare",
         "direction": "Paris Saint-Lazare", "minutes": 17, "at": "08:12"},
        {"line_id": "line:IDFM:C01383", "line_code": "13", "line_name": "13",
         "line_mode": "Métro", "line_color": "82C8E6", "from_id": "s3",
         "from_name": "Gare Saint-Lazare", "to_id": "s4", "to_name": "Châtillon",
         "direction": "Châtillon - Montrouge", "minutes": 23, "at": "08:31"}]},
      {"kind": "less_fallback", "minutes": 54, "walk_minutes": 6, "transfers": 0,
       "departure": "08:02", "arrival": "08:56", "legs": [
        {"line_id": "line:IDFM:C01743", "line_code": "E", "line_name": "E",
         "line_mode": "RER", "line_color": "B94E9A", "from_id": "s5",
         "from_name": "Haussmann Saint-Lazare", "to_id": "s6", "to_name": "Chelles",
         "direction": "Chelles - Gournay", "minutes": 48, "at": "08:08"}]}
    ]}
    """

    static let alternativesJSON = """
    {"needed": true, "baseline_minutes": 47,
     "affected": [{"line_id": "line:IDFM:C01383", "line_code": "13",
                   "level": 2, "label": "interrumpida"}],
     "options": [
       {"total_minutes": 59, "transfers": 1, "delta_minutes": 12, "usable": true,
        "worst_level": 0, "departure": "12:55", "arrival": "13:54", "legs": [
          {"code": "14", "mode": "Métro", "direction": "Olympiades",
           "color": "640082", "minutes": 18, "status": "normal"},
          {"code": "6", "mode": "Métro", "direction": "Nation",
           "color": "6ECA97", "minutes": 22, "status": "normal"}]},
       {"total_minutes": 51, "transfers": 1, "delta_minutes": 4, "usable": false,
        "worst_level": 2, "departure": "12:52", "arrival": "13:43", "legs": [
          {"code": "13", "mode": "Métro", "direction": "Châtillon",
           "color": "82C8E6", "minutes": 20, "status": "interrumpida"},
          {"code": "4", "mode": "Métro", "direction": "Mairie de Montrouge",
           "color": "BE418D", "minutes": 19, "status": "normal"}]}
     ]}
    """
}

extension PlatformGuess {
    static var preview: PlatformGuess { PreviewData.guess }
}
#endif
