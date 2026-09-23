/* Datos de prueba, calcados de Trajet/Resources/PreviewData.swift.
   Tienen la forma EXACTA de la API (snake_case): no hay ningún campo aquí
   que el servidor no mande. Los prototipos solo leen de aquí. */
window.TrajetData = (() => {

  // ---------- GET /api/board  ·  el caso corriente (J + 14) ----------
  const calmBoard = {
    route: { id: 1, name: "Trabajo → Casa", origin_name: "Gare Saint-Lazare", dest_name: "Argenteuil" },
    worst_level: 0, worst_line: "", max_delay: 0,
    updated_at: "2026-08-30T12:50:03+00:00", data_age: 6.0, stale: false,
    errors: [], quota: { "stop-monitoring": 640 }, auto_selected: true,
    legs: [
      { seq: 0, line_id: "line:IDFM:C01739", line_code: "J", line_name: "J",
        line_mode: "Train Transilien", line_color: "CEC73D",
        from_name: "Gare Saint-Lazare", to_name: "Argenteuil",
        directions: ["Ermont - Eaubonne"],
        status: { level: 0, label: "normal", messages: [], messages_es: [], translating: false, planned: 0 },
        age: 3.2,
        departures: [
          { jid: "j1", minutes: 6, at: "12:56", aimed_at: "12:56", destination: "Ermont - Eaubonne",
            platform: "21", platform_new: false, delay: 0, status: "onTime", at_stop: false, train: "137412", length: "long" },
          { jid: "j2", minutes: 21, at: "13:11", aimed_at: "13:11", destination: "Ermont - Eaubonne",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: "137416",
            guess: { platform: "21", share: 0.9, samples: 20, basis: "mision", why: "por el número de tren" },
            length: "short" },
          { jid: "j3", minutes: 36, at: "13:26", aimed_at: "13:24", destination: "Ermont - Eaubonne",
            platform: null, platform_new: false, delay: 2, status: "delayed", at_stop: false, train: "137420", length: null },
          { jid: "j4", minutes: 51, at: "13:41", aimed_at: "13:41", destination: "Ermont - Eaubonne",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: "137424", length: "long" }
        ] },
      { seq: 1, line_id: "line:IDFM:C01372", line_code: "14", line_name: "14",
        line_mode: "Métro", line_color: "640082",
        from_name: "Saint-Lazare", to_name: "Olympiades", directions: ["Olympiades"],
        status: { level: 0, label: "normal", messages: [], messages_es: [], translating: false, planned: 0 },
        age: 2.0,
        departures: [
          { jid: "q1", minutes: 1, at: "12:51", aimed_at: "", destination: "Olympiades",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: null, length: null },
          { jid: "q2", minutes: 3, at: "12:53", aimed_at: "", destination: "Olympiades",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: null, length: null },
          { jid: "q3", minutes: 6, at: "12:56", aimed_at: "", destination: "Olympiades",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: null, length: null },
          { jid: "q4", minutes: 9, at: "12:59", aimed_at: "", destination: "Olympiades",
            platform: null, platform_new: false, delay: null, status: "onTime", at_stop: false, train: null, length: null }
        ] }
    ]
  };

  // Tramo de bus que se añade con el escenario «bus a 1h46» (línea 6424 del banco de 5 tramos).
  const busLeg = {
    seq: 2, line_id: "line:IDFM:C00306", line_code: "6424", line_name: "6424",
    line_mode: "Bus", line_color: "A50034",
    from_name: "Marseillaise", to_name: "Pont de Bezons", directions: ["Pont de Bezons"],
    status: { level: 0, label: "normal", messages: [], messages_es: [], translating: false, planned: 0 },
    age: 4.1,
    departures: [
      { jid: "b1", minutes: 106, at: "14:36", aimed_at: "14:25", destination: "Pont de Bezons",
        platform: null, platform_new: false, delay: 11, status: "delayed", at_stop: false, train: null, length: null },
      { jid: "b2", minutes: 165, at: "15:35", aimed_at: "15:35", destination: "Pont de Bezons",
        platform: null, platform_new: false, delay: 0, status: "onTime", at_stop: false, train: null, length: null }
    ]
  };

  // Avisos reales (en francés) que usan los escenarios.
  const notices = {
    slow: { fr: "Trafic ralenti en raison de travaux sur la voirie.", es: "Tráfico lento por obras en la calzada." },
    cut:  { fr: "Le trafic est interrompu entre Châtillon-Montrouge et Montparnasse suite à un incident technique.",
            es: "El tráfico está interrumpido entre Châtillon-Montrouge y Montparnasse por un incidente técnico." },
    cut14:{ fr: "Le trafic est interrompu sur l'ensemble de la ligne en raison d'un incident technique. Reprise estimée à 14h00.",
            es: "El tráfico está interrumpido en toda la línea por un incidente técnico. Reanudación prevista a las 14:00." }
  };

  // ---------- GET /api/routes ----------
  const routes = {
    active_id: 4,
    routes: [
      { id: 3, name: "Casa → Trabajo", origin_id: "a", origin_name: "6 Rue de la Marseillaise",
        dest_id: "b", dest_name: "74 Rue de Paris", days: [0, 1, 2, 3, 4],
        time_from: "07:15", time_to: "09:15", time_mode: "arrival", time_at: "09:00",
        duration_min: 62, position: 0,
        legs: [
          { id: 1, route_id: 3, seq: 0, line_id: "line:IDFM:C00306", line_code: "6424", line_name: "6424",
            line_mode: "Bus", line_color: "A50034", from_id: "s1", from_name: "Marseillaise",
            to_id: "s2", to_name: "Pont de Bezons", directions: ["Pont de Bezons"] },
          { id: 2, route_id: 3, seq: 1, line_id: "line:IDFM:C01743", line_code: "E", line_name: "E",
            line_mode: "RER", line_color: "B94E9A", from_id: "s3", from_name: "Haussmann Saint-Lazare",
            to_id: "s4", to_name: "Chelles", directions: ["Chelles - Gournay"] },
          { id: 3, route_id: 3, seq: 2, line_id: "line:IDFM:C01383", line_code: "13", line_name: "13",
            line_mode: "Métro", line_color: "82C8E6", from_id: "s5", from_name: "Gare Saint-Lazare",
            to_id: "s6", to_name: "", directions: [] }
        ] },
      { id: 4, name: "Trabajo → Casa", origin_id: "b", origin_name: "Gare Saint-Lazare",
        dest_id: "a", dest_name: "Argenteuil", days: [0, 1, 2, 3, 4],
        time_from: "17:00", time_to: "20:00", time_mode: "window", time_at: "",
        duration_min: 0, position: 1,
        legs: [
          { id: 4, route_id: 4, seq: 0, line_id: "line:IDFM:C01739", line_code: "J", line_name: "J",
            line_mode: "Train Transilien", line_color: "CEC73D", from_id: "s7", from_name: "Gare Saint-Lazare",
            to_id: "s8", to_name: "Argenteuil", directions: ["Ermont - Eaubonne"] },
          { id: 5, route_id: 4, seq: 1, line_id: "line:IDFM:C01372", line_code: "14", line_name: "14",
            line_mode: "Métro", line_color: "640082", from_id: "s9", from_name: "Saint-Lazare",
            to_id: "s10", to_name: "Olympiades", directions: ["Olympiades"] }
        ] },
      { id: 5, name: "Vuelta de clase", origin_id: "c", origin_name: "Nanterre-Université",
        dest_id: "a", dest_name: "6 Rue de la Marseillaise", days: [1, 3],
        time_from: "20:30", time_to: "22:30", time_mode: "departure", time_at: "21:00",
        duration_min: 40, position: 2,
        legs: [
          { id: 6, route_id: 5, seq: 0, line_id: "line:IDFM:C01742", line_code: "A", line_name: "A",
            line_mode: "RER", line_color: "E3051C", from_id: "s11", from_name: "Nanterre-Université",
            to_id: "s12", to_name: "La Défense", directions: ["Boissy-Saint-Léger", "Marne-la-Vallée"] },
          { id: 7, route_id: 5, seq: 1, line_id: "line:IDFM:C01390", line_code: "T2", line_name: "T2",
            line_mode: "Tramway", line_color: "C4318E", from_id: "s13", from_name: "La Défense",
            to_id: "s14", to_name: "Parc de Bezons", directions: ["Pont de Bezons"] }
        ] }
    ]
  };

  // ---------- GET /api/stats ----------
  const stats = {
    by_month: [
      { month: "2026-09", bad_days: 5, total_days: 16, avg_delay: 2.8 },
      { month: "2026-08", bad_days: 11, total_days: 21, avg_delay: 3.42 },
      { month: "2026-07", bad_days: 6, total_days: 22, avg_delay: 1.9 },
      { month: "2026-06", bad_days: 8, total_days: 21, avg_delay: 2.4 }
    ],
    by_line: [
      { worst_line: "13", n: 24, avg_delay: 4.6 },
      { worst_line: "J", n: 9, avg_delay: 6.1 },
      { worst_line: "147", n: 4, avg_delay: 2.0 }
    ],
    overall: { n: 128, avg_delay: 3.42, max_delay: 27.0 }
  };

  // ---------- GET /api/platform-model ----------
  const platformModel = {
    accuracy: { predictions: 214, hits: 179, rate: 0.84, observations: 4820, days: 26 },
    route: { id: 4, name: "Trabajo → Casa" },
    coverage: [
      { seq: 0, line_code: "J", observations: 3120, days: 26, platforms: 4 },
      { seq: 1, line_code: "14", observations: 0, days: 0, platforms: 0 }
    ]
  };

  // ---------- GET /api/plan ----------
  const plan = {
    age: 1.2,
    options: [
      { kind: "best", minutes: 47, walk_minutes: 11, transfers: 1, departure: "08:07", arrival: "08:54",
        legs: [
          { line_id: "line:IDFM:C01739", line_code: "J", line_name: "J", line_mode: "Train Transilien",
            line_color: "CEC73D", from_id: "s1", from_name: "Argenteuil", to_id: "s2",
            to_name: "Gare Saint-Lazare", direction: "Paris Saint-Lazare", minutes: 17, at: "08:12" },
          { line_id: "line:IDFM:C01383", line_code: "13", line_name: "13", line_mode: "Métro",
            line_color: "82C8E6", from_id: "s3", from_name: "Gare Saint-Lazare", to_id: "s4",
            to_name: "Châtillon", direction: "Châtillon - Montrouge", minutes: 23, at: "08:31" }
        ] },
      { kind: "less_fallback", minutes: 54, walk_minutes: 6, transfers: 0, departure: "08:02", arrival: "08:56",
        legs: [
          { line_id: "line:IDFM:C01743", line_code: "E", line_name: "E", line_mode: "RER",
            line_color: "B94E9A", from_id: "s5", from_name: "Haussmann Saint-Lazare", to_id: "s6",
            to_name: "Chelles", direction: "Chelles - Gournay", minutes: 48, at: "08:08" }
        ] },
      { kind: "less_walk", minutes: 58, walk_minutes: 3, transfers: 2, departure: "08:04", arrival: "09:02",
        legs: [
          { line_id: "line:IDFM:C01739", line_code: "J", line_name: "J", line_mode: "Train Transilien",
            line_color: "CEC73D", from_id: "s1", from_name: "Argenteuil", to_id: "s2",
            to_name: "Gare Saint-Lazare", direction: "Paris Saint-Lazare", minutes: 17, at: "08:09" },
          { line_id: "line:IDFM:C01372", line_code: "14", line_name: "14", line_mode: "Métro",
            line_color: "640082", from_id: "s9", from_name: "Saint-Lazare", to_id: "s15",
            to_name: "Châtelet", direction: "Olympiades", minutes: 4, at: "08:30" },
          { line_id: "line:IDFM:C01374", line_code: "4", line_name: "4", line_mode: "Métro",
            line_color: "BE418D", from_id: "s15", from_name: "Châtelet", to_id: "s16",
            to_name: "Montparnasse", direction: "Bagneux", minutes: 9, at: "08:38" }
        ] }
    ]
  };

  // ---------- GET /api/alternatives/{id} ----------
  const alternatives = {
    needed: true, baseline_minutes: 47,
    affected: [{ line_id: "line:IDFM:C01372", line_code: "14", level: 2, label: "interrumpida" }],
    options: [
      { total_minutes: 59, transfers: 1, delta_minutes: 12, usable: true, worst_level: 0,
        departure: "12:55", arrival: "13:54",
        legs: [
          { code: "J", mode: "Train Transilien", direction: "Ermont - Eaubonne", color: "CEC73D", minutes: 18, status: "normal" },
          { code: "6", mode: "Métro", direction: "Nation", color: "6ECA97", minutes: 22, status: "normal" }
        ] },
      { total_minutes: 63, transfers: 2, delta_minutes: 16, usable: true, worst_level: 1,
        departure: "12:58", arrival: "14:01",
        legs: [
          { code: "J", mode: "Train Transilien", direction: "Ermont - Eaubonne", color: "CEC73D", minutes: 18, status: "normal" },
          { code: "147", mode: "Bus", direction: "Gallieni", color: "E4022D", minutes: 14, status: "perturbada" },
          { code: "T2", mode: "Tramway", direction: "Porte de Versailles", color: "C4318E", minutes: 9, status: "normal" }
        ] },
      { total_minutes: 51, transfers: 1, delta_minutes: 4, usable: false, worst_level: 2,
        departure: "12:52", arrival: "13:43",
        legs: [
          { code: "14", mode: "Métro", direction: "Olympiades", color: "640082", minutes: 20, status: "interrumpida" },
          { code: "4", mode: "Métro", direction: "Mairie de Montrouge", color: "BE418D", minutes: 19, status: "normal" }
        ] }
    ]
  };

  // ---------- GET /api/health ----------
  const health = {
    ok: true, key_configured: true,
    quota: { "stop-monitoring": 640, "general-message": 946, "navitia": 915 },
    last_error: null, now_paris: "12:50",
    translator: { ok: true, reason: "modelo cargado", model: "qwen2.5:3b" }
  };

  // Panel de administración del servidor (solo lo enseña el panel web).
  const admin = {
    devices: [
      { name: "iPhone de Isma", paired_at: "2026-09-20T18:12:00+02:00", last_seen: "hace 3 min", via: "tailnet", active: true },
      { name: "iPhone (antiguo)", paired_at: "2026-08-30T13:40:00+02:00", last_seen: "hace 12 días", via: "casa", active: false }
    ],
    pairing: { url: "http://100.99.38.76:7796/pair?t=•••••", expires_in: 300 },
    quotaHistory: [412, 530, 488, 602, 575, 640, 618],   // llamadas usadas, 7 días
    learning: { observations: 4820, days: 26, predictions: 214, hits: 179 }
  };

  // ---------- Geografía de la línea J (Saint-Lazare → Argenteuil) ----------
  // Trazado creíble sobre OSM: la trinchera de Batignolles, Asnières, la
  // rama de Argenteuil cruzando el Sena en Le Stade. [lon, lat].
  const lineJ = {
    color: "CEC73D",
    path: [
      [2.3253, 48.8763], [2.3232, 48.8792], [2.3205, 48.8828], [2.3172, 48.8860],
      [2.3147, 48.8877], [2.3090, 48.8912], [2.3030, 48.8945], [2.2985, 48.8971],
      [2.2935, 48.9000], [2.2880, 48.9028], [2.2822, 48.9056], [2.2760, 48.9100],
      [2.2683, 48.9152], [2.2610, 48.9185], [2.2545, 48.9213], [2.2490, 48.9255],
      [2.2440, 48.9297], [2.2405, 48.9350], [2.2402, 48.9400], [2.2425, 48.9435],
      [2.2452, 48.9457]
    ],
    stops: [
      { name: "Paris Saint-Lazare", lonlat: [2.3253, 48.8763], served: true, origin: true },
      { name: "Pont-Cardinet", lonlat: [2.3147, 48.8877], served: false },
      { name: "Clichy-Levallois", lonlat: [2.2985, 48.8971], served: false },
      { name: "Asnières-sur-Seine", lonlat: [2.2822, 48.9056], served: true },
      { name: "Bois-Colombes", lonlat: [2.2683, 48.9152], served: true },
      { name: "Colombes", lonlat: [2.2545, 48.9213], served: true },
      { name: "Le Stade", lonlat: [2.2440, 48.9297], served: true },
      { name: "Argenteuil", lonlat: [2.2452, 48.9457], served: true, dest: true }
    ],
    // Metro 14 en Saint-Lazare: el transbordo, solo un trozo hacia el sureste.
    transfer: { code: "14", color: "640082", path: [[2.3253, 48.8763], [2.3290, 48.8745], [2.3330, 48.8720]] },
    // Dónde estoy y el camino a pie hasta la estación.
    me: [2.3218, 48.8789],
    walk: [[2.3218, 48.8789], [2.3230, 48.8781], [2.3241, 48.8772], [2.3253, 48.8763]],
    walkMinutes: 4,
    center: [2.285, 48.909],
    bounds: [[2.232, 48.872], [2.335, 48.951]]
  };

  return { calmBoard, busLeg, notices, routes, stats, platformModel, plan, alternatives, health, admin, lineJ };
})();
