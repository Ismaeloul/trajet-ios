/* B v2 · Live Activity y widgets (FASE 2B.2–2B.3)

   Tres variantes dentro del lenguaje «Cristal», pensadas para cómo iOS los
   enseña de verdad (docs/diseno/referencias-la-widgets.md):

     A · «Billete»  un solo billete opaco por superficie: la cifra a la
                    izquierda y la vía en la «matriz» del billete, a la derecha.
                    Lo demás, en UNA línea debajo. Siempre la misma anatomía.
     B · «Tablero»  un tablero de salidas en miniatura: filas con la cifra en
                    una baldosa opaca, destino por fila y vía por fila. El
                    siguiente tren y el transbordo son filas de pleno derecho.
     C · «Fases»    dos baldosas gemelas: la de la izquierda siempre es el
                    tiempo; la de la derecha cambia según el momento del viaje
                    (luego → vía → andén → transbordo → sin servicio).

   Reglas comunes (las tres):
   - Solo datos de /api/v1/board (BoardV1, BoardLegV1, Departure, LineStatus,
     PlatformGuess). Nada de ocupación, posición del tren ni hora de llegada.
   - UNA cuenta atrás, de minuto en minuto y calculada desde la HORA de salida
     (`at`, HH:MM de París), no desde un número congelado: es lo que en iOS
     hace un texto de fecha del sistema (Text(timerInterval:) / formatos de
     iOS 18 con precisión de minuto) y sigue bajando aunque la app no actualice.
   - La antigüedad del dato siempre a la vista; «sin conexión» y «sin
     actualizar» (staleDate vencida) diseñados.
   - Vía real = caja sólida + «Vía»; probable = recuadro punteado +
     «probable»/«prob.». En la isla compacta y la mínima basta la forma.
   - El destino nunca se corta a mitad de palabra: abreviar() + ViewThatFits.
   - El cristal nunca va debajo de los minutos ni de la vía: van opacos. */
(() => {
  'use strict';
  const T = window.Trajet;
  const { fmt, line, esc, scenarios, clock } = T;
  const qs = new URLSearchParams(location.search);
  const ICON = T.parts.icon;

  // =================================================================== dispositivos
  // Puntos de la HIG (referencias-la-widgets.md §3 y §5). El 16 Pro Max usa
  // la fila de 430 pt para widgets e isla (sin fila oficial propia) y 408 pt
  // para la Live Activity; el SE no tiene isla.
  const DEVICES = {
    se:  { id: 'se',  name: 'iPhone SE', w: 375, h: 667, radius: 0, sb: 20,
           island: null, la: 353,
           wS: 148, wM: [321, 148], wL: [321, 324], lwC: 68, lwR: [153, 68], lwI: [225, 26], icon: 60 },
    i16: { id: 'i16', name: 'iPhone 16', w: 393, h: 852, radius: 55, sb: 54,
           island: { side: 52.33, total: 230, h: 36.67, top: 11, exp: 371 }, la: 371,
           wS: 158, wM: [338, 158], wL: [338, 354], lwC: 72, lwR: [160, 72], lwI: [234, 26], icon: 62 },
    max: { id: 'max', name: 'iPhone 16 Pro Max', w: 440, h: 956, radius: 62, sb: 60,
           island: { side: 62.33, total: 250, h: 36.67, top: 12, exp: 408 }, la: 408,
           wS: 170, wM: [364, 170], wL: [364, 382], lwC: 76, lwR: [172, 76], lwI: [257, 26], icon: 66 }
  };
  const VARIANTS = {
    A: { id: 'A', name: 'Billete', idea: 'Un billete opaco por superficie; la vía en la matriz del billete.' },
    B: { id: 'B', name: 'Tablero', idea: 'Un tablero de salidas en miniatura: filas con baldosa, destino y vía.' },
    C: { id: 'C', name: 'Fases', idea: 'Dos baldosas: el tiempo y lo que toca ahora (vía, andén, transbordo).' }
  };

  // =================================================================== estado del laboratorio
  const LAB_KEY = 'trajet-lab.v2';
  const readJSON = k => { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } };
  const writeJSON = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* modo privado */ } };
  const lab = Object.assign({ v: 'A', view: 'lamina', device: 'i16', island: 'compact', zoom: 0 }, readJSON(LAB_KEY) || {});
  const saveLab = () => writeJSON(LAB_KEY, { v: lab.v, view: lab.view, device: lab.device, island: lab.island, zoom: lab.zoom });
  let frozenSince = null;          // cuándo dejó de actualizarse la Live Activity (escenario «dato antiguo»)

  // =================================================================== abreviar destinos
  /* abreviar(nombre) → lista de variantes, de la más completa a la más corta,
     SIN cortar nunca una palabra. La vista se queda con la primera que cabe
     (en SwiftUI: ViewThatFits con un Text por variante y lineLimit(1)); si no
     cabe ninguna, el destino se quita entero: nunca «Ermont - Eaub…».

     Reglas, en orden (cada una da una variante nueva solo si cambia algo):
       1. Completo, normalizado (espacios dobles, guiones largos).
       2. Compactar sin perder información:
          · « - » → «-» (Ermont - Eaubonne → Ermont-Eaubonne);
          · fuera los paréntesis ((RER), (Grande Arche));
          · fuera «Paris » delante de otro nombre (Paris Saint-Lazare →
            Saint-Lazare) y «Gare » delante de un nombre propio (Gare
            Saint-Lazare → Saint-Lazare). «Gare de Lyon» y «Gare du Nord» se
            quedan: «Lyon» o «Nord» solos confunden.
       3. Diccionario de abreviaturas de la señalética RATP/SNCF, solo en
          palabras enteras (también dentro de un compuesto con guiones):
          Saint → St, Sainte → Ste, Saints → Sts, Porte → Pte, Place → Pl.,
          Pont → Pt, Château → Chât., Université → Univ., Aéroport → Aérop.,
          Charles de Gaulle → CDG, Avenue → Av., Boulevard → Bd,
          Faubourg → Fg, Terminal → T.
       4. Quitar la parte secundaria de un nombre doble SNCF (el separado con
          « - », no el guion de «Saint-Lazare»): Ermont - Eaubonne → Ermont,
          Châtillon - Montrouge → Châtillon, Chelles - Gournay → Chelles.
       5. Alias corto de la lista NOMBRES_CORTOS (cómo se dice en el andén):
          Saint-Denis Pleyel → Pleyel, Marne-la-Vallée Chessy → Chessy…
       6. Nada (''): la vista quita el destino. En un tramo con un solo
          sentido ya lo dice la cabecera (R24 solo exige destino por fila
          cuando se mezclan destinos).
     Todas las variantes caben de sobra en los 4 KB del ContentState: la app
     las calcula y la vista elige. */
  // Palabra entera con letras de cualquier alfabeto (\b de JavaScript no ve
  // la «é» como letra: «Université» no se abreviaba).
  const palabra = w => new RegExp(`(?<!\\p{L})${w}(?!\\p{L})`, 'gu');
  const ABREV = [
    ['Saintes', 'Stes'], ['Saints', 'Sts'], ['Sainte', 'Ste'], ['Saint', 'St'],
    ['Porte', 'Pte'], ['Place', 'Pl.'], ['Pont', 'Pt'], ['Château', 'Chât.'],
    ['Université', 'Univ.'], ['Aéroport', 'Aérop.'], ['Charles[ -]de[ -]Gaulle', 'CDG'],
    ['Avenue', 'Av.'], ['Boulevard', 'Bd'], ['Faubourg', 'Fg'], ['Terminal', 'T']
  ].map(([w, to]) => [palabra(w), to]);
  const NOMBRES_CORTOS = {
    'Saint-Denis Pleyel': 'Pleyel', 'Marne-la-Vallée Chessy': 'Chessy', 'Aéroport Charles de Gaulle 2 TGV': 'CDG 2',
    'Aéroport Charles de Gaulle 1': 'CDG 1', 'Saint-Rémy-lès-Chevreuse': 'St-Rémy', 'Saint-Germain-en-Laye': 'St-Germain',
    'Saint-Quentin-en-Yvelines': 'St-Quentin', 'Boissy-Saint-Léger': 'Boissy', 'Mantes-la-Jolie': 'Mantes',
    'Versailles Château Rive Gauche': 'Versailles RG', 'Cergy-le-Haut': 'Cergy', 'Mairie de Montrouge': 'Montrouge',
    'Pont de Bezons': 'Bezons'
  };
  function abreviar(nombre) {
    const out = [];
    const push = v => { v = (v || '').replace(/\s+/g, ' ').trim(); if (v && !out.includes(v) && (!out.length || v.length < out[out.length - 1].length)) out.push(v); };
    const full = (nombre || '').replace(/[–—]/g, '-').replace(/\s+/g, ' ').trim();
    if (!full) return [];
    push(full);
    // 2 · compactar sin perder nada
    let c = full.replace(/\s*\([^)]*\)/g, '').replace(/\s+-\s+/g, '-')
      .replace(/^Paris\s+(?=\S)/, '').replace(/^Gare\s+(?!de\b|du\b|d'|des\b)/, '');
    push(c);
    // 3 · abreviaturas en palabras enteras
    let a = c; ABREV.forEach(([re, to]) => { a = a.replace(re, to); });
    push(a);
    // 4 · parte principal de un nombre doble «A - B» (solo el guion con espacios del original)
    if (/\s-\s/.test(full)) {
      let p = full.split(/\s-\s/)[0].replace(/\s*\([^)]*\)/g, '').replace(/^Paris\s+(?=\S)/, '').replace(/^Gare\s+(?!de\b|du\b|d'|des\b)/, '');
      ABREV.forEach(([re, to]) => { p = p.replace(re, to); });
      push(p);
    }
    // 5 · alias corto
    if (NOMBRES_CORTOS[full]) push(NOMBRES_CORTOS[full]);
    return out;
  }
  /** Atributos para que fit() elija la primera variante que cabe (ViewThatFits). */
  const fitAttr = (nombre, lines = 1) => `data-fit="${esc(abreviar(nombre).join('|'))}"${lines > 1 ? ` data-lines="${lines}"` : ''}`;
  const fitFirst = nombre => esc(abreviar(nombre)[0] || '');
  /** Varias frases alternativas (de la más larga a la más corta) para un mismo hueco. */
  const fitAlts = alts => `data-fit="${esc(alts.filter(Boolean).join('|'))}"`;

  // =================================================================== tiempo
  const GRACE = 45;                                     // un «ya» sigue 45 s (como el tablero)
  const secOf = hhmm => { const [h, m] = hhmm.split(':').map(Number); return h * 3600 + m * 60; };
  function secsUntil(at, now) {
    let d = secOf(at) - (((now % 86400) + 86400) % 86400);
    if (d < -43200) d += 86400; else if (d > 43200) d -= 86400;   // cambio de día a medianoche
    return d;
  }
  /** La cifra de una salida, calculada SIEMPRE desde su hora: en iOS es un
      texto de fecha del sistema, que baja solo. Precisión de minuto (el dato
      no tiene segundos: nada de «05:58»). «En andén» ≠ «ya» (R15). */
  function countdown(dep, now) {
    const secs = secsUntil(dep.at, now);
    const min = Math.max(0, Math.ceil(secs / 60));
    if (dep.at_stop) return { secs, min: 0, n: 'andén', u: '', kind: 'stop' };
    if (min <= 0) return { secs, min: 0, n: 'ya', u: '', kind: 'now' };
    if (min >= 60) return { secs, min, n: fmt.minutes(min), u: '', kind: 'long' };   // 1h46 (R6)
    return { secs, min, n: String(min), u: 'min', kind: 'min' };
  }
  const cdText = (cd, f) => f === 'p' ? (cd.kind === 'min' ? cd.n + '′' : cd.n) : f === 'nu' ? (cd.u ? `${cd.n} ${cd.u}` : cd.n) : cd.n;
  const ageText = (sec, f) => {
    const t = fmt.age(sec);                                                     // R18: hace N s / min / h
    if (f === 'corto') return t.replace('hace ', '');
    if (f === 'act') return 'actualizado ' + t;
    return t;
  };

  // =================================================================== colores
  function rgbOf(hex) { const s = String(hex || '').replace('#', ''); if (!/^[0-9a-f]{6}$/i.test(s)) return null; const v = parseInt(s, 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
  function lum(c) { const f = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); }
  /** Tinta del distintivo: negro o blanco, el que más contraste dé (sistema.md §3.6; el tablero no trae text_color). */
  function inkFor(hex) { const c = rgbOf(hex); if (!c) return '#fff'; const L = lum(c); return (L + 0.05) / 0.05 >= 1.05 / (L + 0.05) ? '#000' : '#fff'; }

  // =================================================================== modelo
  /* Lo que la app metería en el ContentState de la Live Activity (≤ 4 KB) y
     en la entrada del timeline de los widgets, sacado de BoardV1. Nada más. */
  function viaOf(d, leg) {
    if (!line.publishesPlatform(leg.line_mode)) return { kind: 'na' };            // = platform_expected false (R3)
    if (d.platform) return { kind: d._isNew ? 'new' : 'real', num: d.platform };
    if (d.guess) return { kind: 'guess', num: d.guess.platform, share: d.guess.share };
    return { kind: 'none' };
  }
  function enrich(d, leg, now) {
    return Object.assign({}, d, {
      cd: countdown(d, now), via: viaOf(d, leg),
      delayTxt: d.delay && d.aimed_at ? fmt.delay(d.delay) : '',                  // R4 + R14
      lenTxt: d.length === 'long' ? 'tren largo' : d.length === 'short' ? 'tren corto' : ''   // R5
    });
  }
  /** Escenas nuevas de la 2B.4 que el núcleo no conoce, aplicadas encima del
      tablero con la misma forma de la API: destinos mezclados (R24), cambio
      de vía (misma jid, otra vía: lo detecta la app), tren cancelado
      (`status: "cancelled"` de SIRI) y nombres largos (auditoría de recortes).
      Las ven las tres variantes; B y C no las tratan aparte (se quedan tal cual). */
  function tweakBoard(b, s) {
    const now = clock.now();
    b.legs.forEach(leg => {
      if (leg.line_code === 'J') {
        const a = leg.departures[0];
        if (s.mixed) { leg.directions = []; leg.departures.forEach((d, i) => { d.destination = i % 2 ? 'Mantes-la-Jolie' : 'Ermont - Eaubonne'; }); }
        if (a && s.platformChange && a.platform) {
          a._prev = a.platform; a.platform = '23';
          const since = s.platformChangeAt != null ? now - s.platformChangeAt : 999;
          a._isNew = since >= 0 && since < 25; a.platform_new = false;
        }
        if (a && s.cancelled) a.status = 'cancelled';
        if (s.longNames) {
          Object.assign(leg, { line_code: 'B', line_name: 'B', line_mode: 'RER', line_color: '5291CE', from_name: 'Châtelet - Les Halles',
            to_name: 'Aéroport Charles de Gaulle 2 TGV', directions: ['Aéroport Charles de Gaulle 2 TGV'] });
          leg.departures.forEach(d => { d.destination = 'Aéroport Charles de Gaulle 2 TGV'; });
        }
      } else if (leg.line_code === '14' && s.longNames) {
        Object.assign(leg, { line_code: 'N145', line_name: 'N145', line_mode: 'Bus', line_color: '0064B0', from_name: 'Gare de Lyon - Diderot',
          to_name: 'Châtelet - Les Halles', directions: ['Saint-Rémy-lès-Chevreuse'] });
        leg.departures.forEach(d => { d.destination = 'Saint-Rémy-lès-Chevreuse'; });
      }
    });
    return b;
  }
  function model() {
    const s = scenarios.get(), now = clock.now();
    const board = tweakBoard(T.buildBoard(s), s);
    let legs = board.legs.map(l => Object.assign({}, l));
    let route = Object.assign({}, board.route);
    if (s.busLong) {                                  // el bus manda: la ruta «Casa → Trabajo» empieza en el 6424
      const i = legs.findIndex(l => l.line_code === '6424');
      if (i > 0) { const [bus] = legs.splice(i, 1); legs.unshift(bus); }
      route = { id: 3, name: 'Casa → Trabajo', origin_name: legs[0].from_name, dest_name: 'Trabajo' };
    }
    legs.forEach(l => {
      l.deps = l.departures.filter(d => d.at_stop || secsUntil(d.at, now) > -GRACE).slice(0, 4).map(d => enrich(d, l, now));
      l.dir = l.directions && l.directions.length === 1 ? l.directions[0] : (l.deps[0] ? l.deps[0].destination : l.to_name);
    });
    // El trayecto: con «transbordo», la ruta encadenada 14 → J; si no, el primer tramo
    // (el tablero de calma J + 14 no es una cadena, ver shared/data.js).
    const trip = s.transfer ? legs : [legs[0]];
    const idx = s.transfer ? Math.max(0, Math.min(s.legNow || 0, trip.length - 1)) : 0;
    const leg = trip[idx], next = trip[idx + 1] || null;
    const head = leg.deps[0] || null, second = leg.deps[1] || null;
    // Antigüedad (R17): la del tablero más lo que lleva en el teléfono.
    const laConn = s.offline ? 'offline' : s.frozen ? 'frozen' : 'live';
    if (s.frozen && frozenSince == null) frozenSince = now;
    if (!s.frozen) frozenSince = null;
    const laAge = laConn === 'frozen' ? 360 + Math.max(0, now - frozenSince) : board.data_age;
    // Widgets: se recargan con cuentagotas (40–70 al día). Aquí, cada 15 min.
    const wConn = s.offline ? 'offline' : 'live';
    const wAge = s.offline ? 52 * 60 + Math.max(0, now - (s.offlineSince || now)) : (now - Math.floor(now / 900) * 900) + 8;
    return {
      s, now, board, route, legs, trip, idx, leg, next, head, second,
      laConn, laAge, laStale: laConn !== 'live', wConn, wAge, wStale: wConn !== 'live',
      ended: !!s.tripEnded, legCount: trip.length
    };
  }

  // =================================================================== piezas comunes
  function badge(leg, size, extra = '') {
    const code = String(leg.line_code || '?'); const c = line.color(leg.line_color);
    const len = code.length;
    return `<span class="bdg${len >= 4 ? ' l4' : len === 3 ? ' l3' : ''} ${extra}" style="--lc:${c};--li:${inkFor(c)};--s:${size}px" role="img" aria-label="Línea ${esc(code)}">${esc(code)}</span>`;
  }
  const isReal = v => v && (v.kind === 'real' || v.kind === 'new');
  const hasVia = v => v && (isReal(v) || v.kind === 'guess');
  /** La vía con forma y palabra. word: full («probable») | short («prob.») | pct (con el %). */
  function via(v, { sz = 'm', word = 'full', cls = '' } = {}) {
    if (!hasVia(v)) return '';
    const real = isReal(v);
    const lab = real ? 'Vía' : (word === 'short' ? 'prob.' : 'probable');
    const pct = !real && word === 'pct' ? `<em>${Math.round(v.share * 100)} %</em>` : '';
    const al = real ? `vía ${v.num}` : `vía ${v.num} probable, ${Math.round(v.share * 100)} por ciento`;
    return `<span class="via ${real ? 'via-r' : 'via-p'}${v.kind === 'new' ? ' is-new' : ''} sz-${sz} ${cls}" role="img" aria-label="${al}"><small>${lab}</small><b>${esc(v.num)}</b>${pct}</span>`;
  }
  /** Solo la forma (isla compacta y mínima): caja llena = real, punteada = probable. */
  function viaMini(v, cls = '') {
    if (!hasVia(v)) return '';
    return `<span class="vmini ${isReal(v) ? 'via-r' : 'via-p'}${v.kind === 'new' ? ' is-new' : ''} ${cls}" role="img" aria-label="${isReal(v) ? 'vía ' + v.num : 'vía ' + v.num + ' probable'}">${esc(v.num)}</span>`;
  }
  const cdNum = (d, f = 'n', cls = '') => `<b class="n ${cls} k-${d.cd.kind}" data-cd="${d.jid}" data-cdf="${f}">${esc(cdText(d.cd, f))}</b>`;
  const cdUnit = (d, cls = 'u') => d.cd.u ? `<i class="${cls}" data-cdu="${d.jid}">${d.cd.u}</i>` : '';
  const ageEl = (which, sec, f = 'hace') => `<span data-age="${which}" data-agef="${f}">${esc(ageText(sec, f))}</span>`;
  const stopBtn = (cls = '') => `<button class="stop ${cls}" aria-label="Parar el trayecto"><i class="ico-stop"></i><span>Parar</span></button>`;
  const statusWord = st => st.level >= 2 ? 'interrumpida' : st.level === 1 ? 'perturbada' : '';
  /** Marca de estado de la línea sin palabra (compacta, circular): la palabra va en VoiceOver. */
  const statusMark = (st, cls = '') => st.level ? `<span class="stmark lvl-${st.level} ${cls}" role="img" aria-label="línea ${statusWord(st)}">${ICON(st.level >= 2 ? 'x' : 'warn')}</span>` : '';
  const statusChip = (st, cls = '') => st.level ? `<span class="stchip lvl-${st.level} ${cls}">${ICON(st.level >= 2 ? 'x' : 'warn')}<span>${statusWord(st)}</span></span>` : '';
  /** Estado de la conexión de la Live Activity, dicho con palabra + símbolo. */
  function ageLA(m, f = 'hace') {
    if (m.laConn === 'offline') return `<span class="age is-bad">${ICON('wifiOff')}<span class="fit" ${fitAlts(['sin conexión · ' + ageText(m.laAge, 'hace'), 'sin red · ' + ageText(m.laAge, 'corto'), ageText(m.laAge, 'corto')])} data-agefit="la">sin conexión · ${ageText(m.laAge, 'hace')}</span></span>`;
    if (m.laConn === 'frozen') return `<span class="age is-warn">${ICON('clock')}<span class="fit" ${fitAlts(['sin actualizar · ' + ageText(m.laAge, 'hace'), 'dato de ' + ageText(m.laAge, 'hace'), ageText(m.laAge, 'corto')])} data-agefit="la">sin actualizar · ${ageText(m.laAge, 'hace')}</span></span>`;
    return `<span class="age">${ageEl('la', m.laAge, f)}</span>`;
  }
  function ageW(m, f = 'hace') {
    if (m.wConn === 'offline') return `<span class="age is-bad">${ICON('wifiOff')}${ageEl('w', m.wAge, f)}</span>`;
    return `<span class="age">${ageEl('w', m.wAge, f)}</span>`;
  }
  /** Líneas secundarias por prioridad (principio 7): retraso > longitud > hora > tramo. */
  function metaBits(d, m, { tramo = true } = {}) {
    const bits = [];
    bits.push(`<span class="mt-at">sale ${esc(d.at)}</span>`);
    if (d.delayTxt) bits.push(`<span class="mt-late${d.delay < 0 ? ' is-early' : ''}">${esc(d.delayTxt)}</span>`);
    if (d.lenTxt) bits.push(`<span class="mt-len">${esc(d.lenTxt)}</span>`);
    if (tramo && m && m.legCount > 1) bits.push(`<span class="mt-leg">tramo ${m.idx + 1} de ${m.legCount}</span>`);
    return bits;
  }
  const nextTimes = (leg, n = 2) => leg.deps.slice(0, n).map(d => d.at).join(' · ');
  function xferAlts(m) {
    const st = m.leg.to_name || m.next.from_name;
    const ab = abreviar(st);
    return [`Transbordo en ${ab[0]}`, `Transbordo en ${ab[ab.length - 1]}`, `en ${ab[ab.length - 1]}`, ab[ab.length - 1]];
  }
  /** Sin salidas: «Sin circulación» si la línea está cortada, «Servicio finalizado» si no (R25). */
  const emptyWord = leg => leg.status.level >= 2 ? 'Sin circulación' : 'Servicio finalizado';
  /** Lo mismo, con variantes más cortas para huecos pequeños (nunca cortado). */
  const emptyFit = (leg, lines = 1) => `<b class="fit" ${fitAlts(leg.status.level >= 2 ? ['Sin circulación', 'Cortada'] : ['Servicio finalizado', 'Finalizado'])}${lines > 1 ? ` data-lines="${lines}"` : ''}>${esc(emptyWord(leg))}</b>`;
  const emptySub = leg => leg.status.level >= 2 ? `Línea ${leg.line_code} interrumpida` : 'no hay más salidas';
  const ariaDep = (d, leg) => {
    const que = d.at_stop ? 'parado en el andén' : d.cd.kind === 'now' ? 'sale ya' : `en ${d.cd.kind === 'long' ? d.cd.n.replace('h', ' h ') : d.cd.n + ' minutos'}`;
    const v = isReal(d.via) ? `, vía ${d.via.num}` : d.via.kind === 'guess' ? `, vía ${d.via.num} probable` : '';
    return `Línea ${leg.line_code} a ${d.destination}, ${que}${v}`;
  };

  // =================================================================== A · Billete (2B.4, la elegida)
  /* La variante elegida (docs/diseno/decisiones-la-widgets.md). Sobre la de
     la 2B.3 corrige la lista del revisor (su número entre corchetes):

     · [P0-1] La Live Activity pinta SOLO su ContentState: la «foto» que la
       app escribió la última vez (modelA → la). Si la app deja de escribir,
       la vista no cambia de tren ni «publica» vías: la cuenta atrás sigue
       por fecha y, al vencer staleDate, pasa a horas de salida fijas y
       apagada. Los widgets pintan cada entrada del timeline con el dato tal
       como llegó en la última recarga y acaban en «Sin datos recientes».
     · [P0-2] La cifra tiene versiones («Cifra» en el panel): la que escribe
       la app (dos tallas, «′», «ya», «1h46»), el texto de fecha del sistema
       de una sola talla («6 min») y el de iOS 17 con segundos («5:59»). En
       los widgets la app no escribe la cifra: número suelto del sistema
       (hipótesis H1) o texto de una talla; con 60 min o más, la hora fija.
     · [P0-3] «Parar» nunca se apaga. [P0-4] Una sola regla de apagado
       (.A-off): todo en gris con contraste ≥ 4,5:1, menos «Parar» y el aviso
       que explica por qué.
     · [P1] Compacta ≤ 52,33 pt por lado con alternativas (ViewThatFits);
       expandida con cifra + vía juntas y franja de vía para la alerta;
       palabras de R10 ≥ 11 pt (12 en la Live Activity); «Parar» con 44 pt
       de área; filas que caen por prioridad; Live Activity de 150 pt.
     · [P2] Vía del tren de enlace, destinos mezclados, cancelado, cambio de
       vía, «andén» en la mínima, anatomía fija del pequeño, un solo nivel de
       abreviatura por widget, «Sin circulación» + lo útil, arco solo con
       ≤ 30 min, fin a mano sin estado final. */
  const A = {};
  const HINT = 30;            // server.refresh_hint_s del tablero de prueba
  const ENTRY_GAP = 300;      // entradas del timeline separadas ≥ 5 min (WidgetKit)
  const absAt = (at, ref) => ref + secsUntil(at, ref);
  const isCancel = d => !!d && /cancel/i.test(d.status || '');
  const uniq = xs => xs.filter((x, i) => x != null && xs.indexOf(x) === i);
  let frozenFallback = null;  // «La app no actualiza» sin hora fija: dejó de escribir hace 6 min

  /** El tablero tal como llegó a la hora t (el núcleo lo construye «desde t»). */
  function boardAt(s, t) {
    return tweakBoard(T.buildBoard(Object.assign({}, s, { offline: true, offlineSince: t })), s);
  }
  /** Vía con forma y palabra (R10) y el cambio de vía, que detecta la app
      comparando la misma jid entre dos tableros (la API no lo marca). */
  function viaA(d, leg) {
    if (!leg.pexp) return { kind: 'na' };                               // platform_expected false (R3)
    if (d.platform) return { kind: d._isNew ? 'new' : 'real', num: d.platform, prev: d._prev || null, changed: !!d._prev };
    if (d.guess) return { kind: 'guess', num: d.guess.platform, share: d.guess.share };
    return { kind: 'none' };
  }
  function prepLeg(l, t) {
    const leg = Object.assign({}, l);
    leg.pexp = line.publishesPlatform(l.line_mode);
    leg.mixed = !(l.directions && l.directions.length) && new Set(l.departures.map(d => d.destination)).size > 1;   // R24
    leg.dir = l.directions && l.directions.length === 1 ? l.directions[0] : (l.departures[0] ? l.departures[0].destination : l.to_name);
    leg.all = l.departures.map(d => Object.assign({}, d, {
      atAbs: absAt(d.at, t), via: viaA(d, leg),
      delayTxt: d.delay && d.aimed_at ? fmt.delay(d.delay) : '',                                     // R4 + R14
      lenTxt: d.length === 'long' ? 'tren largo' : d.length === 'short' ? 'tren corto' : ''          // R5
    }));
    return leg;
  }
  function arrange(b, s, t) {
    const legs = b.legs.map(l => prepLeg(l, t));
    let route = Object.assign({}, b.route);
    if (s.busLong) {
      const i = legs.findIndex(l => l.line_code === '6424');
      if (i > 0) { const [bus] = legs.splice(i, 1); legs.unshift(bus); }
      route = { id: 3, name: 'Casa → Trabajo', origin_name: legs[0].from_name, dest_name: 'Trabajo' };
    }
    return { legs, route };
  }

  /* ---------- el modelo de A: lo que hay en el ContentState y en cada entrada del timeline */
  function modelA(over = {}, ns = 'm') {
    const s = Object.assign({}, scenarios.get(), over);
    const now = clock.now();
    const mode = s.numMode || 'app';

    // ---- Live Activity: la foto que escribió la app
    let conn = s.noKey ? 'nokey' : s.offline ? 'offline' : s.frozen ? 'frozen' : 'live';
    if (conn === 'frozen' && s.frozenAt != null && now < s.frozenAt) conn = 'live';   // todavía no ha dejado de escribir
    let snapT = now;
    if (conn === 'frozen') {
      if (s.frozenAt != null) snapT = s.frozenAt;
      else { if (frozenFallback == null) frozenFallback = now - 360; snapT = frozenFallback; }
    } else if (conn !== 'live') snapT = s.offlineSince != null ? s.offlineSince : now;
    if (ns === 'm' && !s.frozen) frozenFallback = null;
    // Viva (o sin conexión, que la app sigue viva): la app reescribe la foto
    // cada minuto desde su último tablero. Congelada: la última escritura.
    const writtenAt = conn === 'frozen' ? snapT : now;
    const b = conn === 'live' ? tweakBoard(T.buildBoard(s), s) : boardAt(s, snapT);
    const { legs, route } = arrange(b, s, snapT);
    const trip = s.transfer ? legs : [legs[0]];
    const idx = s.transfer ? Math.max(0, Math.min(s.legNow || 0, trip.length - 1)) : 0;
    const leg = trip[idx], nextLeg = trip[idx + 1] || null;
    const visible = (l, t) => l.all.filter(d => d.at_stop || d.atAbs - t > -GRACE);
    const cs = visible(leg, writtenAt);                         // las salidas del ContentState (≤ 3 en iOS)
    // staleDate: solo vence si la app deja de escribir.
    let staleAt = Infinity;
    if (conn === 'frozen') {
      staleAt = snapT + Math.max(90, 2 * HINT);                 // el tablero es viejo (R19)
      const h0 = cs.find(d => !isCancel(d));
      if (h0 && !h0.at_stop) staleAt = Math.min(staleAt, h0.atAbs + 60);   // el tren enseñado ya salió
      if (mode === 'app') staleAt = Math.min(staleAt, Math.floor(snapT / 60) * 60 + 90);   // la cifra escrita ya no vale
    }
    const stale = now >= staleAt;
    // Ya caducada, la vista enseña horas fijas: el primer tren que sale más
    // de 60 s después de staleDate (la vista no sabe qué hora es).
    const pool = stale ? cs.filter(d => d.at_stop || d.atAbs - 60 > staleAt) : cs;
    const cancelled = pool.length && isCancel(pool[0]) ? pool[0] : null;
    const valid = pool.filter(d => !isCancel(d));
    const hero = valid[0] || null, second = valid[1] || null;
    const final = !hero && leg.all.some(d => !isCancel(d));      // había salidas, pero ya pasaron todas las de la foto
    const link = nextLeg ? (visible(nextLeg, writtenAt).filter(d => !isCancel(d))[0] || null) : null;
    const laAge = conn === 'live' ? b.data_age : conn === 'frozen' ? now - snapT + 6 : now - snapT + 240;
    const rid = route.id;
    const la = {
      conn, stale, staleAt, snapT, writtenAt, age: laAge, off: conn === 'offline' || conn === 'nokey' || stale,
      trip, idx, leg, nextLeg, cs, hero, second, cancelled, link, final, legCount: trip.length,
      ended: s.tripEnded ? (s.endReason || 'auto') : null,
      url: conn === 'nokey' ? 'trajet://ajustes/servidor' : !hero && leg.status.level >= 2 ? `trajet://ruta/${rid}/alternativas` : `trajet://ruta/${rid}?tramo=${leg.seq}`
    };

    // ---- Widgets: la última recarga y la entrada del timeline que toca
    const wConn = s.noKey ? 'nokey' : s.offline ? 'offline' : 'live';
    const R = wConn === 'live' ? Math.floor(now / 900) * 900                                  // recarga cada 15 min
      : (s.offlineSince != null ? s.offlineSince : now) - (s.wOldMin != null ? s.wOldMin : 20) * 60;   // la última buena
    const wb = boardAt(s, R);
    const W = arrange(wb, s, R);
    const entryOf = ls => {
      const ds = [R, ...ls.flatMap(l => l.all.map(d => d.atAbs)).filter(x => x > R)].sort((p, q) => p - q);
      const kept = [];
      ds.forEach(x => { if (!kept.length || x - kept[kept.length - 1] >= ENTRY_GAP) kept.push(x); });
      let E = R; kept.forEach(x => { if (x <= now) E = x; });
      return E;
    };
    const atEntry = (l, E) => l.all.filter(d => d.atAbs > E || (d.at_stop && E === R));
    const pack = (l, E) => {
      const ds = atEntry(l, E);
      const had = l.all.length > 0;
      const c = ds.length && isCancel(ds[0]) ? ds[0] : null;
      const v = ds.filter(d => !isCancel(d));
      return { leg: l, deps: v, hero: v[0] || null, second: v[1] || null, cancelled: c, final: had && !ds.length, E };
    };
    const E1 = entryOf([W.legs[0]]);
    const main = pack(W.legs[0], E1);
    const Eall = entryOf(W.legs.slice(0, 3));
    const large = W.legs.slice(0, 3).map(l => pack(l, Eall));
    const w = {
      conn: wConn, R, age: now - R + 8, off: wConn !== 'live' || main.final, final: main.final, main, large, route: W.route,
      url: wConn === 'nokey' ? 'trajet://ajustes/servidor' : main.final ? 'trajet://tablero' : !main.hero && main.leg.status.level >= 2 ? `trajet://ruta/${W.route.id}/alternativas` : `trajet://ruta/${W.route.id}?tramo=${main.leg.seq}`
    };
    const a = { ns, s, now, mode, route, la, w };
    a.dep = (ctx, jid) => {
      const ls = ctx === 'la' ? [leg, nextLeg].filter(Boolean) : W.legs;
      for (const l of ls) { const d = l.all.find(x => x.jid === jid); if (d) return d; }
      return null;
    };
    return a;
  }

  /** La cifra de una salida según quién la escribe (P0-2).
      la · app   : la escribe la app (reescribe cada minuto): dos tallas, «ya», «1h46».
      *  · sys   : texto de fecha del sistema, UNA talla: «6 min» (iOS 18+).
      *  · ios17 : Text(timerInterval:) con segundos: «5:59».
      w  · h1    : número suelto del sistema (.timer con maxFieldCount 1, a verificar) + «min» fijo.
      Caducada, la Live Activity enseña la hora fija. Con ≥ 60 min, el
      sistema no sabe decir «1h46»: la hora fija. */
  function numA(d, a, ctx) {
    if (d.at_stop) return { kind: 'stop', n: 'En andén', u: '' };
    if (ctx === 'la' && a.la.stale) return { kind: 'time', n: d.at, u: '' };
    const mode = ctx === 'la' ? a.mode : a.mode === 'app' ? 'h1' : a.mode;
    const t = ctx === 'la' && mode === 'app' ? a.la.writtenAt : a.now;
    const secs = d.atAbs - t;
    if (mode === 'app') {
      const min = Math.max(0, Math.ceil(secs / 60));
      if (min <= 0) return { kind: 'now', n: 'ya', u: '' };
      if (min >= 60) return { kind: 'long', n: fmt.minutes(min), u: '' };
      return { kind: 'min', n: String(min), u: 'min' };
    }
    if (secs >= 3600) return { kind: 'time', n: d.at, u: '' };
    if (mode === 'ios17') { const x = Math.max(0, Math.ceil(secs)); return { kind: 'sec', n: `${Math.floor(x / 60)}:${String(x % 60).padStart(2, '0')}`, u: '' }; }
    const min = Math.max(0, Math.ceil(secs / 60));
    return mode === 'h1' ? { kind: 'min', n: String(min), u: 'min' } : { kind: 'sys', n: `${min} min`, u: '' };
  }
  const numTextA = (x, f) => f === 'p' && x.kind === 'min' ? x.n + '′' : f === 'nu' ? (x.u ? `${x.n} ${x.u}` : x.n) : x.n;
  function ariaA(d, leg, x, a) {
    const que = d.at_stop ? 'parado en el andén' : x.kind === 'time' ? `sale a las ${d.at}` : x.kind === 'now' ? 'sale ya' : x.kind === 'long' ? `en ${x.n.replace('h', ' h ')}` : `en ${parseInt(x.n, 10)} minutos`;
    const v = isReal(d.via) ? `, vía ${d.via.num}${d.via.changed ? `, cambio de vía, antes ${d.via.prev}` : ''}` : d.via.kind === 'guess' ? `, vía ${d.via.num} probable, ${Math.round(d.via.share * 100)} por ciento` : '';
    return `Línea ${leg.line_code} a ${d.destination}, ${que}${v}${d.delayTxt ? ', ' + d.delayTxt.replace('+', '') + ' de retraso' : ''}${a && a.la && a.la.off && x.kind === 'time' ? ', dato sin actualizar' : ''}`;
  }

  /* ---------- piezas de A */
  const key = (a, ctx, d) => `${a.ns}|${ctx}|${d.jid}`;
  /** La cifra (con su «min» si lo lleva). prime: «6′» (compacta). label: «sale a las» sobre la hora fija. */
  A.num = (a, ctx, d, { cls = '', prime = false, unit = true, label = true } = {}) => {
    const x = numA(d, a, ctx), k = key(a, ctx, d);
    if (x.kind === 'time') return label ? `<span class="A-tm ${cls}"><small>sale a las</small><b class="n k-time">${esc(x.n)}</b></span>` : `<b class="n k-time ${cls}">${esc(x.n)}</b>`;
    if (x.kind === 'stop') return `<b class="n k-stop ${cls}">En andén</b>`;
    const f = prime ? 'p' : 'n';
    return `<b class="n k-${x.kind} ${cls}" data-acd="${k}" data-acf="${f}">${esc(numTextA(x, f))}</b>${unit && !prime && x.u ? `<i class="A-u" data-acu="${k}">${x.u}</i>` : ''}`;
  };
  /** Vía con forma y palabra: real = caja sólida «Vía»; probable = punteada «prob.»/«probable» (R10). */
  A.via = (v, { sz = 's', word = 'short', pct = false } = {}) => {
    if (!hasVia(v)) return '';
    const real = isReal(v);
    const al = real ? `vía ${v.num}${v.changed ? `, cambio de vía, antes ${v.prev}` : ''}` : `vía ${v.num} probable, ${Math.round(v.share * 100)} por ciento`;
    return `<span class="A-via ${real ? 'is-real' : 'is-prob'} sz-${sz}${v.kind === 'new' ? ' is-new' : ''}" role="img" aria-label="${esc(al)}"><small>${real ? 'Vía' : word === 'full' ? 'probable' : 'prob.'}</small><b>${esc(v.num)}</b>${pct && !real ? `<em>${Math.round(v.share * 100)} %</em>` : ''}</span>`;
  };
  /** Solo la forma (compacta, mínima): caja llena = real, punteada = probable. */
  A.vmini = (v, cls = '') => hasVia(v) ? `<span class="A-vm ${isReal(v) ? 'is-real' : 'is-prob'}${v.kind === 'new' ? ' is-new' : ''} ${cls}" role="img" aria-label="${isReal(v) ? 'vía ' + esc(v.num) : 'vía ' + esc(v.num) + ' probable'}">${esc(v.num)}</span>` : '';
  /** La «matriz» del billete: la vía en su columna. */
  A.stub = (v, { pct = false } = {}) => {
    if (!hasVia(v)) return '';
    const real = isReal(v);
    return `<span class="A-stub ${real ? 'is-real' : 'is-prob'}${v.kind === 'new' ? ' is-new' : ''}${pct && !real ? ' has-pct' : ''}" role="img" aria-label="${real ? 'vía ' + esc(v.num) : 'vía ' + esc(v.num) + ' probable'}"><small>${real ? 'Vía' : 'probable'}</small><b>${esc(v.num)}</b>${pct && !real ? `<em>${Math.round(v.share * 100)} %</em>` : ''}</span>`;
  };
  /** Destino ajustable: variantes de abreviar() y, al final, nada (nunca cortado). */
  A.dest = (name, prio = 2, group = '', cls = 'A-dst') => {
    const al = abreviar(name);
    const steps = al.map((_, i) => i < al.length - 1 ? prio : prio + 3).join(' ');
    return al.length ? `<span class="fitr ${cls}" data-alts="${esc([...al, ''].join('|'))}" data-prio="${steps}"${group ? ` data-fitgroup="${group}"` : ''}>${esc(al[0])}</span>` : '';
  };
  /** Estado de la línea: símbolo + palabra; la palabra cae antes que la antigüedad (P1-9). */
  A.stChip = (leg, { word = true, prio = 1 } = {}) => {
    const lv = leg.status.level; if (!lv) return '';
    const w = statusWord(leg.status);
    return `<span class="A-st lvl-${lv}" role="img" aria-label="línea ${w}">${ICON(lv >= 2 ? 'x' : 'warn')}${word ? `<span class="fitr" data-alts="${w}|" data-prio="${prio}">${w}</span>` : ''}</span>`;
  };
  const stateIcon = conn => conn === 'offline' ? 'wifiOff' : conn === 'nokey' ? 'server' : 'clock';
  /** Antigüedad de la Live Activity (R17, R18) y, si está apagada, por qué. */
  A.stateLA = a => {
    const L = a.la, age = `<span class="A-agev" data-aage="${a.ns}|la">${esc(ageText(L.age, 'hace'))}</span>`;
    const pre = (alts, cls, ico) => `<span class="A-age ${cls}">${ICON(ico)}<span class="fitr" data-alts="${esc([...alts, ''].join('|'))}" data-prio="3">${esc(alts[0])}</span>${age}</span>`;
    if (L.stale) return pre(['sin actualizar ·', 'dato de'], 'is-warn', 'clock');
    if (L.conn === 'offline') return pre(['sin conexión ·'], 'is-bad', 'wifiOff');
    if (L.conn === 'nokey') return pre(['servidor sin clave ·', 'sin clave ·'], 'is-bad', 'server');
    return `<span class="A-age">${age}</span>`;
  };
  /** Antigüedad de un widget: es contenido (15–60 min), con su símbolo si la recarga falló. */
  A.stateW = (a, { words = false, icon = true } = {}) => {
    const W = a.w, age = `<span class="A-agev" data-aage="${a.ns}|w">${esc(ageText(W.age, 'hace'))}</span>`;
    const pre = (alts, cls, ico) => `<span class="A-age ${cls}">${icon ? ICON(ico) : ''}${words ? `<span class="fitr" data-alts="${esc([...alts, ''].join('|'))}" data-prio="3">${esc(alts[0])}</span>` : ''}${age}</span>`;
    if (W.conn === 'offline') return pre(['sin conexión ·'], 'is-bad', 'wifiOff');
    if (W.conn === 'nokey') return pre(['servidor sin clave ·', 'sin clave ·'], 'is-bad', 'server');
    if (W.final) return pre(['último dato'], 'is-warn', 'clock');
    return `<span class="A-age">${age}</span>`;
  };
  /** «Parar»: se ve a 32 pt y toca a 44 (contentShape); nunca se apaga (P0-3, P1-8). */
  A.stop = (cls = '') => `<button class="A-stop ${cls}" aria-label="Parar el trayecto"><i class="ico-stop"></i><span>Parar</span></button>`;

  /** El billete: cifra · una línea secundaria que cae por prioridad · la vía en su matriz. */
  A.ticket = (a, ctx, d, leg, { size = 'l', tramo = null, stub = true, pct = false } = {}) => {
    if (!d) return A.empty(leg, size, { final: ctx === 'la' && a.la.final });
    const x = numA(d, a, ctx);
    const l1 = [], l2 = [];
    // Prioridad (dp alto = se queda): cambio de vía > retraso > hora > longitud > tramo.
    if (d.via.changed) l1.push(`<span class="A-chg fitr" data-alts="${esc(`cambio de vía · antes ${d.via.prev}|antes vía ${d.via.prev}`)}" data-prio="1" data-dp="7">cambio de vía · antes ${esc(d.via.prev)}</span>`);
    // «sale 12:56» cae antes de acortar «cambio de vía» (fitr de prioridad 0).
    if (x.kind !== 'time') l1.push(`<span class="mt-at fitr" data-alts="${esc(`sale ${d.at}`)}|" data-prio="0" data-dp="4">sale ${esc(d.at)}</span>`);
    if (d.delayTxt) l1.push(`<span class="mt-late${d.delay < 0 ? ' is-early' : ''}" data-dp="5">${esc(d.delayTxt)}</span>`);
    if (d.lenTxt) l2.push(`<span class="mt-len" data-dp="3">${esc(d.lenTxt)}</span>`);
    if (tramo) l2.push(`<span class="mt-leg" data-dp="2">${esc(tramo)}</span>`);
    return `<div class="A-tk sz-${size} k-${x.kind}${d.at_stop ? ' is-stop' : ''}" aria-label="${esc(ariaA(d, leg, x, a))}">
      <div class="A-num">${A.num(a, ctx, d)}</div>
      <div class="A-meta" data-droprow>${l1.length ? `<span class="ln" data-fitrow>${l1.join('')}</span>` : ''}${l2.length ? `<span class="ln">${l2.join('')}</span>` : ''}</div>
      ${stub ? A.stub(d.via, { pct }) : ''}
    </div>`;
  };
  /** Sin salida que enseñar: «Sin circulación» (+ lo útil), «Servicio finalizado» (R25) o el final del timeline. */
  A.empty = (leg, size, { final = false, compact = false } = {}) => {
    if (final) return `<div class="A-tk sz-${size} is-empty is-final" data-droprow="x"><span class="A-eico" data-dp="1">${ICON('clock')}</span><div><b>Sin datos recientes</b>${compact ? '' : '<small>abre Trajet para actualizar</small>'}</div></div>`;
    const cut = leg.status.level >= 2;
    return `<div class="A-tk sz-${size} is-empty${cut ? ' is-cut' : ''}" data-droprow="x"><span class="A-eico" data-dp="1">${ICON(cut ? 'x' : 'moon')}</span><div><b>${cut ? 'Sin circulación' : 'Servicio finalizado'}</b>${compact ? '' : `<small>${cut ? 'toca para ver alternativas' : 'no hay más salidas'}</small>`}</div></div>`;
  };
  /** El tren siguiente: «luego 21 min» (o la hora fija si está caducada), con su vía. */
  A.luego = (a, ctx, d, leg) => `<span class="A-nx" data-fitrow><span class="lbl">luego</span>${A.num(a, ctx, d, { cls: 'sm', label: false })}${leg.mixed ? A.dest(d.destination, 1, '', 'A-nxd') : ''}${A.via(d.via, { sz: 'xs' })}</span>`;
  /** Transbordo: dónde, la línea, la hora del primer enlace y SU vía; la vía manda sobre la hora (P2-11). */
  A.xfer = (a, fromLeg, nl, d) => {
    const st = abreviar(fromLeg.to_name || nl.from_name);
    const alts = uniq([`Transbordo en ${st[0]}`, ...st.map(x => `en ${x}`), '']);
    return `<span class="A-xf" data-fitrow>${ICON('swap')}<span class="fitr" data-alts="${esc(alts.join('|'))}" data-prio="1">${esc(alts[0])}</span>${badge(nl, 18)}${d
      ? `<span class="fitr A-xt" data-alts="${esc(d.at)}|" data-prio="2">${esc(d.at)}</span>${A.via(d.via, { sz: 'xs' })}`
      : `<span class="A-xt">${nl.status.level >= 2 ? 'sin circulación' : '—'}</span>`}</span>`;
  };
  A.foot = a => {
    const L = a.la;
    if (L.cancelled) return `<span class="A-fn is-bad" data-fitrow>${ICON('x')}<span class="fitr" data-alts="${esc(`el de las ${L.cancelled.at}, cancelado|${L.cancelled.at} cancelado|cancelado`)}" data-prio="1">el de las ${esc(L.cancelled.at)}, cancelado</span></span>`;
    if (L.nextLeg) return A.xfer(a, L.leg, L.nextLeg, L.link);
    if (L.second) return A.luego(a, 'la', L.second, L.leg);
    return '<span class="A-fsp"></span>';
  };

  // ---------- Live Activity en la pantalla de bloqueo (371 × 150 pt)
  A.la = m => {
    const a = m.A, L = a.la;
    if (L.ended) return A.ended(a);
    const leg = L.leg, h = L.hero;
    const tramo = L.legCount > 1 ? `tramo ${L.idx + 1} de ${L.legCount}` : null;
    return `<div class="la A-la${L.off ? ' A-off' : ''}" data-link="${esc(L.url)}">
      <div class="A-head" data-fitrow>${badge(leg, 22)}${A.dest(h ? h.destination : leg.dir)}${h ? A.stChip(leg) : ''}${A.stateLA(a)}</div>
      ${A.ticket(a, 'la', h, leg, { size: 'l', tramo })}
      <div class="A-foot">${A.foot(a)}${A.stop()}</div>
    </div>`;
  };
  /** Fin automático (llegada o duración máxima): resumen que se quita a los 15 min.
      Parado a mano: end(…, dismissalPolicy: .immediate), sin estado final. */
  A.ended = a => {
    const L = a.la;
    if (L.ended === 'manual') return `<div class="A-gone"><b>Parado a mano</b><small>La Live Activity se quita al momento (dismissalPolicy .immediate): no deja resumen.</small></div>`;
    const t = fmt.hhmm(a.now), q = fmt.hhmm(a.now + 900);
    return `<div class="la A-la is-ended" data-link="trajet://ruta/${a.route.id}">
      <div class="A-head" data-fitrow>${badge(L.leg, 22)}<b class="A-endt">Trayecto terminado</b><span class="A-age"><span>${esc(t)}</span></span></div>
      <div class="A-tk is-end">${ICON('check', 'A-endi')}<div class="A-endb"><b class="fitr" data-alts="${esc(a.route.name)}|" data-prio="1">${esc(a.route.name)}</b><small>Se quita sola a las ${esc(q)} · toca para abrir la ruta</small></div></div>
    </div>`;
  };

  // ---------- Dynamic Island
  const stateMark = L => L.off ? `<span class="A-dmark is-state s-${L.stale ? 'stale' : L.conn}">${ICON(stateIcon(L.stale ? 'frozen' : L.conn))}</span>` : '';
  A.compact = (m, I) => {
    const a = m.A, L = a.la, h = L.hero, leg = L.leg;
    const side = I ? I.side : 52.33, max = (side - 9).toFixed(2), lmax = (side - 7.5).toFixed(2);
    const smark = stateMark(L);
    const lmark = smark || (h && leg.status.level ? `<span class="A-dmark lvl-${leg.status.level}">${ICON(leg.status.level >= 2 ? 'x' : 'warn')}</span>` : '');
    const sysMode = a.mode !== 'app' && !L.stale;
    let lead, alts;
    if (!h) alts = [`<span class="A-dx${leg.status.level >= 2 ? ' is-cut' : ''}">${ICON(L.final ? 'clock' : leg.status.level >= 2 ? 'x' : 'moon')}</span>`];
    else if (h.at_stop) alts = [`<span class="A-dstop"><small>andén</small>${A.vmini(h.via)}</span>`];
    else if (L.stale) alts = [`<b class="n A-dn k-time">${esc(h.at)}</b>`];
    else if (!sysMode) {
      const v = A.vmini(h.via);
      alts = [A.num(a, 'la', h, { cls: 'A-dn', prime: true }) + v, A.num(a, 'la', h, { cls: 'A-dn', unit: false }) + v, A.num(a, 'la', h, { cls: 'A-dn', prime: true })];
    } else alts = [A.num(a, 'la', h, { cls: 'A-dn' })];
    // Con el texto del sistema («6 min») no cabe la vía a la derecha: pasa a la izquierda.
    const lv = sysMode && h && !h.at_stop ? A.vmini(h.via) : '';
    lead = `<span class="A-dl${L.off ? ' is-off' : ''}" data-altset data-altmax="${lmax}">${[badge(leg, 22) + lmark + lv, badge(leg, 22) + lv, badge(leg, 22) + lmark, badge(leg, 22)].map(x => `<span class="A-alt" data-alt>${x}</span>`).join('')}</span>`;
    // Con el texto del sistema, «59 min» se encoge (minimumScaleFactor, 0,7 como mucho) antes que ensanchar la isla.
    const trail = `<span class="A-dt${L.off ? ' is-off' : ''}" data-altset data-altmax="${max}"${sysMode ? ` data-shrink style="max-width:${max}px;overflow:hidden"` : ''}>${alts.map(x => `<span class="A-alt" data-alt>${x}</span>`).join('')}</span>`;
    return { lead, trail };
  };
  A.minimal = m => {
    const a = m.A, L = a.la, h = L.hero, leg = L.leg;
    const ring = L.off ? 'var(--a-ring-off)' : h && h.at_stop ? 'var(--ok)' : line.color(leg.line_color);
    let inner;
    if (!h) inner = `<span class="A-mx${leg.status.level >= 2 ? ' is-cut' : ''}">${ICON(L.final ? 'clock' : leg.status.level >= 2 ? 'x' : 'moon')}</span>`;
    else if (h.at_stop) inner = `<small class="A-mw">andén</small>${A.vmini(h.via, 'A-mv')}`;
    else if (L.stale) inner = `<b class="n A-mn k-time">${esc(h.at)}</b>`;
    else {
      const x = numA(h, a, 'la');
      inner = x.kind === 'min' ? `${A.num(a, 'la', h, { cls: 'A-mn', unit: false })}<i>min</i>` : A.num(a, 'la', h, { cls: 'A-mn' });
    }
    return `<span class="A-min${L.off ? ' is-off' : ''}" style="--ring:${ring}">${inner}</span>`;
  };
  /** Circular (36,67) u ovalada (hasta 45 pt) si la cifra es larga. */
  A.minW = (m, I) => {
    const a = m.A, L = a.la, h = L.hero;
    if (!h || h.at_stop) return I.h;
    const x = numA(h, a, 'la');
    return L.stale || ['long', 'sys', 'sec', 'time'].includes(x.kind) ? 45 : I.h;
  };
  /** La vía junto a la cifra en la expandida: la matriz del billete en pequeño (palabra arriba, número abajo). */
  A.xv = v => hasVia(v) ? `<span class="A-xv ${isReal(v) ? 'is-real' : 'is-prob'}${v.kind === 'new' ? ' is-new' : ''}" role="img" aria-label="${isReal(v) ? 'vía ' + esc(v.num) : 'vía ' + esc(v.num) + ' probable'}"><small>${isReal(v) ? 'Vía' : 'prob.'}</small><b>${esc(v.num)}</b></span>` : '';
  /** Franja de vía a lo ancho: solo cuando la alerta abre la isla (vía nueva o cambio de vía). */
  A.band = v => `<div class="A-band${v.changed ? ' is-chg' : ''} is-new" role="img" aria-label="${v.changed ? `cambio de vía: ahora vía ${esc(v.num)}, antes ${esc(v.prev)}` : `se acaba de anunciar la vía ${esc(v.num)}`}"><small>Vía</small><b>${esc(v.num)}</b><span>${v.changed ? `cambio de vía · antes ${esc(v.prev)}` : 'anunciada ahora'}</span></div>`;
  A.expanded = (m, I) => {
    const a = m.A, L = a.la, h = L.hero, leg = L.leg;
    const lead = `${badge(leg, 24)}<span class="A-xd" data-fitrow>${A.dest(h ? h.destination : leg.dir, 1)}</span>`;
    let trail;
    if (!h) trail = `<span class="A-xe${leg.status.level >= 2 && !L.final ? ' is-cut' : ''}">${L.final ? 'Sin datos recientes' : leg.status.level >= 2 ? 'Sin circulación' : 'Servicio finalizado'}</span>`;
    else if (h.at_stop) trail = `<span class="A-xt" data-altset>${['En andén', 'andén'].map(w => `<span class="A-alt" data-alt><span class="A-xstop">${w}</span>${A.xv(h.via)}</span>`).join('')}</span>`;
    else if (L.stale) trail = `<span class="A-xt">${A.num(a, 'la', h, { cls: 'A-xn' })}${A.xv(h.via)}</span>`;
    // Cifra + vía juntas, como en la compacta (P1-6); si «59 min» no cabe, «59′».
    else trail = `<span class="A-xt" data-altset>${[A.num(a, 'la', h, { cls: 'A-xn' }), A.num(a, 'la', h, { cls: 'A-xn', prime: true }), A.num(a, 'la', h, { cls: 'A-xn', unit: false })].map(n => `<span class="A-alt" data-alt>${n}${A.xv(h.via)}</span>`).join('')}</span>`;
    const center = h && leg.status.level ? A.stChip(leg, { prio: 9 })
      : L.legCount > 1 ? `<span class="A-xc">tramo ${L.idx + 1} de ${L.legCount}</span>`
      : h && !L.stale && !h.at_stop ? `<span class="A-xc">sale ${esc(h.at)}${h.delayTxt ? ` <em>${esc(h.delayTxt)}</em>` : ''}</span>` : '';
    const band = h && !L.off && (h.via.kind === 'new' || h.via.changed) ? A.band(h.via) : '';
    const row1 = band || `<div class="A-xr">${A.foot(a)}</div>`;
    const row2 = `<div class="A-xr A-xf2">${A.stateLA(a)}${A.stop('on-dark')}</div>`;
    return { lead, trail, center, bottom: row1 + row2, cls: `A-x${L.off ? ' A-off' : ''}`, link: L.url };
  };

  // ---------- Widgets de inicio
  /** El billete de un widget: la cifra la pone el sistema (ctx «w»). */
  A.wticket = (a, d, leg, { size = 'l', meta = false, stub = false } = {}) => {
    const x = numA(d, a, 'w');
    return `<div class="A-wtk sz-${size} k-${x.kind}${d.at_stop ? ' is-stop' : ''}" aria-label="${esc(ariaA(d, leg, x, null))}"><span class="A-wn" data-shrink>${A.num(a, 'w', d)}</span>${meta && d.delayTxt && x.kind !== 'stop' ? `<span class="mt-late">${esc(d.delayTxt)}</span>` : ''}${stub ? A.stub(d.via) : ''}</div>`;
  };
  A.small = m => {
    const a = m.A, W = a.w, M = W.main, leg = M.leg, d = M.hero;
    const head = M.cancelled
      ? `<span class="fitr A-hc" data-alts="${esc(`${M.cancelled.at} cancelado|${M.cancelled.at}|`)}" data-prio="2">${esc(M.cancelled.at)} cancelado</span>`
      : A.dest(d ? d.destination : leg.dir, 2, 'ws');
    const warn = W.off ? `<span class="A-dmark is-state s-${W.final ? 'stale' : W.conn}" role="img" aria-label="${W.final ? 'sin datos recientes' : W.conn === 'nokey' ? 'servidor sin clave' : 'sin conexión'}">${ICON(W.final ? 'clock' : stateIcon(W.conn))}</span>` : d && leg.status.level ? `<span class="A-dmark lvl-${leg.status.level}" role="img" aria-label="línea ${statusWord(leg.status)}">${ICON(leg.status.level >= 2 ? 'x' : 'warn')}</span>` : M.cancelled ? `<span class="A-dmark lvl-2">${ICON('x')}</span>` : '';
    const tk = d ? A.wticket(a, d, leg) : A.empty(leg, 's', { final: M.final, compact: true });
    // Anatomía fija (P2-15): abajo, la vía o «luego», y la antigüedad; «luego» cae antes que la edad.
    const left = d && hasVia(d.via) ? `<span data-dp="9">${A.via(d.via, { sz: 'xs' })}</span>`
      : M.second ? `<span class="A-wlg" data-dp="1"><span class="lbl">luego</span>${A.num(a, 'w', M.second, { cls: 'sm', label: false })}</span>` : '';
    return `<div class="wd A-ws${W.off ? ' A-off' : ''}" data-link="${esc(W.url)}">
      <div class="A-wh" data-fitrow>${badge(leg, 22)}${warn}${head}</div>
      ${tk}
      <div class="A-wf" data-droprow="x">${left}${A.stateW(a, { icon: false })}</div>
    </div>`;
  };
  A.medium = m => {
    const a = m.A, W = a.w, M = W.main, leg = M.leg, d = M.hero;
    const rows = [];
    if (M.cancelled) rows.push(`<div class="A-mr is-cancel" data-dp="8" data-link="trajet://ruta/${W.route.id}?tramo=${leg.seq}"><div class="A-mr1">${ICON('x')}<b>${esc(M.cancelled.at)}</b><span>cancelado</span></div></div>`);
    M.deps.slice(1, M.cancelled ? 2 : 3).forEach((x, i) => rows.push(`<div class="A-mr" data-dp="${6 - i * 2}" data-link="trajet://ruta/${W.route.id}?tramo=${leg.seq}&amp;salida=${esc(x.jid)}" aria-label="${esc(ariaA(x, leg, numA(x, a, 'w'), null))}">
        <div class="A-mr1">${A.num(a, 'w', x, { cls: 'mrn', label: false })}${hasVia(x.via) ? A.via(x.via, { sz: 'xs' }) : x.delayTxt ? `<span class="mt-late">${esc(x.delayTxt)}</span>` : numA(x, a, 'w').kind === 'time' ? '' : `<span class="mrt">${esc(x.at)}</span>`}</div>
        <div class="A-mrd" data-fitrow>${A.dest(x.destination, 2, 'wm')}</div></div>`));
    const from = abreviar(leg.from_name);
    const lh = leg.status.level && d ? `<span data-fitrow data-dp="3" class="A-mlh">${A.stChip(leg)}</span>`
      : `<span data-fitrow data-dp="2" class="A-mlh"><span class="fitr" data-alts="${esc(uniq([...from.map(f => 'desde ' + f), '']).join('|'))}" data-prio="1">desde ${esc(from[0] || '')}</span></span>`;
    return `<div class="wd A-wm${W.off ? ' A-off' : ''}" data-link="${esc(W.url)}">
      <div class="A-mcol">
        <div class="A-wh" data-fitrow>${badge(leg, 22)}${A.dest(d ? d.destination : leg.dir, 2, 'wm')}</div>
        ${d ? A.wticket(a, d, leg) : A.empty(leg, 's', { final: M.final, compact: true })}
        ${d ? `<div class="A-wf">${hasVia(d.via) ? A.via(d.via, { sz: 'm', word: 'full' }) : numA(d, a, 'w').kind !== 'time' ? `<span class="mt-at">sale ${esc(d.at)}</span>` : ''}${d.delayTxt ? `<span class="mt-late">${esc(d.delayTxt)}</span>` : ''}</div>` : ''}
      </div>
      <div class="A-mlist" data-droprow>
        ${lh}
        ${rows.join('') || `<p class="A-mnone">${d ? 'no hay más salidas anunciadas' : M.final ? 'abre Trajet para actualizar' : leg.status.level >= 2 ? 'toca para ver alternativas' : 'no hay más salidas'}</p>`}
        <div class="A-mage" data-fitrow>${A.stateW(a, { words: true })}</div>
      </div>
    </div>`;
  };
  A.large = m => {
    const a = m.A, W = a.w, secs = W.large; const dense = secs.length > 2;
    const sec = (P, i) => {
      const leg = P.leg, d = P.hero;
      const chips = [];
      if (P.cancelled) chips.push(`<span class="A-lc is-cancel">${ICON('x')}<b>${esc(P.cancelled.at)}</b>cancelado</span>`);
      (dense && i > 0 ? [] : P.deps.slice(1, dense ? 3 : 4)).forEach(x => chips.push(`<span class="A-lc" data-dp="${9 - chips.length}">${A.num(a, 'w', x, { label: false })}${leg.mixed ? `<small class="A-lcd">${esc(abreviar(x.destination).pop())}</small>` : ''}${hasVia(x.via) ? A.via(x.via, { sz: 'xs' }) : x.delayTxt ? `<em class="mt-late">${esc(x.delayTxt)}</em>` : ''}</span>`));
      const fr = abreviar(leg.from_name), to = abreviar(leg.to_name || leg.dir);
      const title = uniq([`${fr[0]} → ${to[0]}`, `${fr[fr.length - 1]} → ${to[to.length - 1]}`, fr[fr.length - 1], '']);
      return `<section class="A-ls" data-link="trajet://ruta/${W.route.id}?tramo=${leg.seq}">
        <div class="A-lh" data-fitrow>${badge(leg, 20)}<span class="fitr" data-alts="${esc(title.join('|'))}" data-prio="2">${esc(title[0])}</span>${d ? A.stChip(leg) : ''}</div>
        ${d ? A.ticket(a, 'w', d, leg, { size: dense ? 's' : i === 0 ? 'l' : 'm', pct: !dense && i === 0 }) : A.empty(leg, dense ? 's' : 'm', { final: P.final })}
        ${chips.length ? `<div class="A-lcs" data-droprow="x" data-dp="${i === 0 ? 4 : 2}">${chips.join('')}</div>` : ''}
      </section>`;
    };
    return `<div class="wd A-wl${dense ? ' is-dense' : ''}${W.off ? ' A-off' : ''}" data-droprow data-link="trajet://ruta/${W.route.id}">
      <div class="A-lt" data-fitrow><b class="fitr" data-alts="${esc(W.route.name)}|" data-prio="4">${esc(W.route.name)}</b>${A.stateW(a, { words: true })}</div>
      ${secs.map(sec).join('')}
    </div>`;
  };

  // ---------- Widgets de la pantalla de bloqueo (vibrantes: ni color de línea ni amarillo)
  A.circ = m => {
    const a = m.A, W = a.w, M = W.main, d = M.hero, leg = M.leg;
    const x = d ? numA(d, a, 'w') : null;
    // Arco solo con 30 min o menos: ProgressView(timerInterval: salida−30 min...salida, countsDown: true).
    const arc = d && !d.at_stop && x.kind !== 'time' && d.atAbs - a.now <= 1800;
    let inner;
    if (!d) inner = `<span class="lwc-x">${ICON(M.final ? 'clock' : leg.status.level >= 2 ? 'x' : 'moon')}</span>`;
    else if (d.at_stop) inner = '<span class="A-cw">andén</span>';
    else if (x.kind === 'time') inner = `<small class="A-cs">sale</small><b class="n A-cn k-time">${esc(x.n)}</b>`;
    else if (x.kind === 'min') inner = `${A.num(a, 'w', d, { cls: 'A-cn', unit: false })}<i class="A-cu">min</i>`;
    else inner = A.num(a, 'w', d, { cls: 'A-cn' });
    const sym = W.off ? ICON(W.final ? 'clock' : stateIcon(W.conn)) : d && leg.status.level ? ICON(leg.status.level >= 2 ? 'x' : 'warn') : '';
    const g = arc ? `<svg class="gauge" viewBox="0 0 72 72" aria-hidden="true"><circle class="g-tr" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="75 100" transform="rotate(135 36 36)"/><circle class="g-v" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="${(Math.max(0, Math.min(1, (d.atAbs - a.now) / 1800)) * 75).toFixed(2)} 100" data-agauge="${key(a, 'w', d)}" transform="rotate(135 36 36)"/></svg>` : '';
    return `<div class="lw lw-c A-lwc${W.off ? ' A-off' : ''}" data-link="${esc(W.url)}">${g}<span class="lwc-in">${inner}</span><span class="A-clab">${sym ? `<span class="A-csym">${sym}</span>` : ''}${esc(leg.line_code)}</span></div>`;
  };
  A.rect = m => {
    const a = m.A, W = a.w, M = W.main, d = M.hero, leg = M.leg;
    const warn = d && leg.status.level ? `<span class="A-dmark">${ICON(leg.status.level >= 2 ? 'x' : 'warn')}</span>` : '';
    const x = d ? numA(d, a, 'w') : null;
    const big = !d ? `<b class="A-rbig">${M.final ? 'Sin datos recientes' : leg.status.level >= 2 ? 'Sin circulación' : 'Servicio finalizado'}</b>`
      : d.at_stop ? '<b class="A-rbig">En andén</b>'
      : x.kind === 'time' ? `<span class="A-rtm"><small>sale</small><b class="n A-rn k-time">${esc(x.n)}</b></span>` : A.num(a, 'w', d, { cls: 'A-rn' });
    return `<div class="lw lw-r A-lwr${W.off ? ' A-off' : ''}" data-link="${esc(W.url)}">
      <div class="A-r1" data-fitrow>${badge(leg, 16, 'ko')}${warn}${M.cancelled ? `<span class="fitr" data-alts="${esc(M.cancelled.at)} cancelado|cancelado" data-prio="2">${esc(M.cancelled.at)} cancelado</span>` : A.dest(d ? d.destination : leg.dir, 2, '', 'A-rd')}</div>
      <div class="A-r2">${big}${d ? A.via(d.via, { sz: 's' }) : ''}</div>
      <div class="A-r3" data-fitrow>${A.stateW(a, { words: true })}</div>
    </div>`;
  };
  A.inline = m => {
    const a = m.A, W = a.w, M = W.main, d = M.hero, leg = M.leg;
    const sym = W.off ? ICON(W.final ? 'clock' : stateIcon(W.conn)) : d && leg.status.level ? ICON(leg.status.level >= 2 ? 'x' : 'warn') : M.cancelled ? ICON('x') : '';
    const age = ageText(W.age, 'hace');
    let alts;
    if (!d) alts = [`${leg.line_code} · ${M.final ? 'sin datos recientes' : leg.status.level >= 2 ? 'sin circulación' : 'servicio finalizado'}`];
    else {
      const x = numA(d, a, 'w');
      const t = d.at_stop ? 'en andén' : x.kind === 'time' ? `sale ${x.n}` : numTextA(x, 'nu');
      // R10 también aquí: la probable nunca lleva «Vía» (P2-13).
      const v = isReal(d.via) ? `Vía ${d.via.num}` : d.via.kind === 'guess' ? `prob. ${d.via.num}` : '';
      alts = uniq([[leg.line_code, t, v, age].filter(Boolean).join(' · '), [leg.line_code, t, v].filter(Boolean).join(' · '), [leg.line_code, t].join(' · ')]);
    }
    return `<div class="lw lw-i A-lwi${W.off ? ' A-off' : ''}" data-link="${esc(W.url)}" data-fitrow>${sym ? `<span class="A-isym">${sym}</span>` : ''}<span class="fitr" data-alts="${esc(alts.join('|'))}" data-prio="1">${esc(alts[0])}</span></div>`;
  };

  // =================================================================== B · Tablero
  const B = {};
  B.tile = (d, sz, leg) => {
    if (!d) return `<span class="B-tile sz-${sz} is-empty">${ICON(leg && leg.status.level >= 2 ? 'x' : 'clock')}</span>`;
    if (d.at_stop) return `<span class="B-tile sz-${sz} is-stop"><b class="n w">andén</b></span>`;
    return `<span class="B-tile sz-${sz} k-${d.cd.kind}">${cdNum(d, 'n')}${cdUnit(d)}</span>`;
  };
  B.row = (d, leg, m, sz, { word = 'full', meta = true } = {}) => {
    const bits = meta ? metaBits(d, m, { tramo: false }) : [`<span class="mt-at">${esc(d.at)}</span>`];
    return `<div class="B-row sz-${sz}" aria-label="${esc(ariaDep(d, leg))}">${B.tile(d, sz, leg)}
      <span class="B-txt"><b class="fit" ${fitAttr(d.destination)}>${fitFirst(d.destination)}</b><small data-drop="end">${bits.join('')}</small></span>
      ${via(d.via, { sz: sz === 'l' ? 'm' : 's', word })}</div>`;
  };
  B.xferRow = (m, sz = 's') => {
    const n = m.next, d0 = n.deps[0];
    const alts = xferAlts(m);
    return `<div class="B-row B-xfer sz-${sz}"><span class="B-tile sz-${sz} is-line">${badge(n, sz === 's' ? 22 : 26)}</span>
      <span class="B-txt"><b class="fit" ${fitAlts(alts)}>${esc(alts[0])}</b><small>${esc(n.line_code)} · ${esc(nextTimes(n))}</small></span>
      ${d0 ? via(d0.via, { sz: 's', word: 'short' }) : ''}</div>`;
  };
  B.la = m => {
    if (m.ended) return ended('B', m);
    const { leg, head, second, next } = m;
    const rows = !head
      ? `<div class="B-row sz-l is-empty">${B.tile(null, 'l', leg)}<span class="B-txt"><b>${esc(emptyWord(leg))}</b><small>${esc(emptySub(leg))}</small></span></div>`
      : B.row(head, leg, m, 'l');
    const row2 = next ? B.xferRow(m) : second ? B.row(second, leg, m, 's', { word: 'short' }) : '';
    return `<div class="la B-la${m.laStale ? ' is-stale' : ''}">
      <div class="B-head">${badge(leg, 24)}<span class="B-where"><b class="fit" ${fitAttr(leg.from_name)}>${fitFirst(leg.from_name)}</b>${m.legCount > 1 ? `<small>tramo ${m.idx + 1} de ${m.legCount}</small>` : ''}</span>${head ? statusChip(leg.status) : ''}${ageLA(m)}${stopBtn()}</div>
      <div class="dim">${rows}${row2}</div>
    </div>`;
  };
  B.compact = m => {
    const { head, leg } = m;
    let t;
    if (!head) t = `<span class="di-x">${ICON('x')}</span>`;
    else if (head.at_stop) t = `<span class="B-dstack"><small>andén</small>${viaMini(head.via, 'sm') || ''}</span>`;
    else t = `<span class="B-dstack${hasVia(head.via) ? '' : ' is-solo'}"><span class="B-dn">${cdNum(head, hasVia(head.via) ? 'p' : 'n', 'di-n')}${hasVia(head.via) ? '' : cdUnit(head, 'di-u')}</span>${viaMini(head.via, 'sm')}</span>`;
    return { lead: `<span class="di-l">${badge(leg, 24)}${head ? statusMark(leg.status) : ''}</span>`, trail: `<span class="B-dtrail${m.laStale ? ' is-stale' : ''}">${t}</span>` };
  };
  B.minimal = m => {
    const { head, leg } = m; const c = line.color(leg.line_color);
    const inner = !head ? ICON('x') : head.at_stop ? '<small>andén</small>' : `${cdNum(head, 'n', 'mn')}${head.cd.u ? '<i>min</i>' : ''}`;
    return `<span class="B-min${m.laStale ? ' is-stale' : ''}" style="--lc:${c}">${inner}<span class="B-mbar"></span></span>`;
  };
  B.expanded = m => {
    const { leg, head, second, next } = m;
    const lead = `<span class="B-xl">${badge(leg, 26)}<small class="fit" ${fitAlts(['desde ' + abreviar(leg.from_name).pop(), abreviar(leg.from_name).pop()])}>desde ${esc(abreviar(leg.from_name).pop())}</small></span><b class="x-dest1 fit" ${fitAttr(head ? head.destination : leg.dir)}>${fitFirst(head ? head.destination : leg.dir)}</b>`;
    const trail = !head ? `<span class="x-empty">${esc(emptyWord(leg))}</span>` : head.at_stop ? `<span class="B-xt">${via(head.via, { sz: 's', word: 'short' })}<span class="x-stop">andén</span></span>`
      : `<span class="B-xt">${via(head.via, { sz: 's', word: 'short' })}<span class="x-num">${cdNum(head, 'n', 'xn')}${cdUnit(head, 'xu')}</span></span>`;
    const center = leg.status.level ? statusChip(leg.status, 'on-dark') : m.legCount > 1 ? `<span class="x-leg">tramo ${m.idx + 1} de ${m.legCount}</span>` : '';
    const r2 = next ? B.xferRow(m) : second ? B.row(second, leg, m, 's', { word: 'short', meta: false }) : !head ? `<div class="B-xr"><span class="x-sub">${esc(emptySub(leg))}</span></div>` : '';
    return { lead, trail, center, bottom: `${r2}<div class="B-xfoot">${ageLA(m)}${stopBtn('on-dark')}</div>` };
  };
  B.small = m => {
    const leg = m.legs[0], d = leg.deps[0], d2 = leg.deps[1];
    const off = m.wConn === 'offline';
    const top = off ? ageW(m) : d && leg.status.level ? statusChip(leg.status) : `<b class="fit" ${fitAttr(leg.from_name)}>${fitFirst(leg.from_name)}</b>`;
    return `<div class="wd B-ws${m.wStale ? ' is-stale' : ''}">
      <div class="B-wh">${badge(leg, 20)}${top}</div>
      <div class="dim">
        <div class="B-wr1">${B.tile(d, 'w', leg)}<span class="B-wv">${d ? (hasVia(d.via) ? via(d.via, { sz: 's', word: 'short' }) : `<small class="fit" ${fitAttr(d.destination, 2)}>${fitFirst(d.destination)}</small>`) : `<small>${emptyFit(leg, 2)}</small>`}</span></div>
        ${d2 ? `<div class="B-wr2" data-vdrop="1">${B.tile(d2, 'xs', leg)}<span class="B-w2t">${esc(d2.at)}</span>${viaMini(d2.via, 'sm')}</div>` : ''}
      </div>
      ${off ? '' : `<div class="B-wf">${ageW(m, 'hace')}</div>`}
    </div>`;
  };
  B.medium = m => {
    const leg = m.legs[0];
    const rows = leg.deps.slice(0, 3).map((d, i) => B.row(d, leg, null, i === 0 ? 'm' : 'r', { word: 'short', meta: i === 0 })).join('');
    return `<div class="wd B-wm${m.wStale ? ' is-stale' : ''}">
      <div class="B-mh">${badge(leg, 20)}<b class="fit" ${fitAlts([leg.from_name, abreviar(leg.from_name).pop()])}>${esc(leg.from_name)}</b>${statusChip(leg.status)}${ageW(m)}</div>
      <div class="dim">${rows || `<div class="B-row sz-m is-empty">${B.tile(null, 'm', leg)}<span class="B-txt"><b>${esc(emptyWord(leg))}</b><small>${esc(emptySub(leg))}</small></span></div>`}</div>
    </div>`;
  };
  B.large = m => {
    const legs = m.legs.slice(0, 3); const per = legs.length > 2 ? 2 : 3;
    const sec = leg => `<section class="B-ls">
      <div class="B-lh">${badge(leg, 20)}<b class="fit" ${fitAlts([`${leg.from_name} → ${leg.dir}`, `${abreviar(leg.from_name).pop()} → ${abreviar(leg.dir).pop()}`, abreviar(leg.from_name).pop()])}>${esc(leg.from_name)} → ${esc(leg.dir)}</b>${statusChip(leg.status)}</div>
      ${leg.deps.length ? leg.deps.slice(0, per).map((d, i) => B.row(d, leg, null, i === 0 ? 'm' : 'r', { word: 'short', meta: i === 0 })).join('')
        : `<div class="B-row sz-r is-empty">${B.tile(null, 'r', leg)}<span class="B-txt"><b>${esc(emptyWord(leg))}</b><small>${esc(emptySub(leg))}</small></span></div>`}
    </section>`;
    return `<div class="wd B-wl${legs.length > 2 ? ' is-dense' : ''}${m.wStale ? ' is-stale' : ''}">
      <div class="B-lt"><b class="fit" ${fitAlts([m.route.name])}>${esc(m.route.name)}</b>${ageW(m)}</div>
      <div class="dim">${legs.map(sec).join('')}</div>
    </div>`;
  };
  B.circ = m => {
    const leg = m.legs[0], d = leg.deps[0];
    const inner = !d ? `<span class="lwc-x">${ICON('x')}</span>` : d.at_stop ? `<span class="lwc-w">andén</span>` : `${cdNum(d, 'n', 'lwc-n')}${d.cd.u ? '<i class="lwc-u">min</i>' : ''}`;
    const lab = d && hasVia(d.via) ? `<span class="lwc-via ${isReal(d.via) ? 'via-r' : 'via-p'} ko">${esc(d.via.num)}</span>` : `<span class="lwc-lab">${esc(leg.line_code)}${d ? statusMark(leg.status, 'on-lw') : ''}</span>`;
    return `<div class="lw lw-c B-lwc">${gauge(d)}<span class="lwc-in">${inner}</span>${lab}</div>`;
  };
  B.rect = m => {
    const leg = m.legs[0], [d, d2] = leg.deps;
    const r = (x, big) => !x ? '' : `<div class="B-lr${big ? ' big' : ''}">${x.at_stop ? '<b class="lwr-n">andén</b>' : cdNum(x, 'n', 'lwr-n') + cdUnit(x, 'lwr-u')}${via(x.via, { sz: big ? 's' : 'xs', word: 'short', cls: 'ko' })}</div>`;
    return `<div class="lw lw-r B-lwr${m.wStale ? ' is-stale' : ''}">
      <div class="lwr-1">${badge(leg, 14, 'ko')}${d && leg.status.level ? statusMark(leg.status, 'on-lw') : ''}${m.wConn === 'offline' ? ICON('wifiOff') : ''}${ageEl('w', m.wAge)}</div>
      ${d ? r(d, true) + r(d2, false) : `<div class="B-lr big"><b class="lwr-big">${esc(emptyWord(leg))}</b></div>`}
    </div>`;
  };
  B.inline = m => {
    const leg = m.legs[0], [d, d2] = leg.deps;
    if (!d) return inlineWrap(`${leg.line_code} · ${emptyWord(leg).toLowerCase()}`);
    const t = d.at_stop ? 'en andén' : cdText(d.cd, 'nu');
    const t2 = d2 ? `luego ${cdText(d2.cd, 'nu')}` : '';
    const v = isReal(d.via) ? `vía ${d.via.num}` : d.via.kind === 'guess' ? `vía ${d.via.num} prob.` : '';
    if (m.wConn === 'offline') return inlineWrap('', [[leg.line_code + ' ' + t, v, 'sin conexión ' + ageText(m.wAge, 'hace')].filter(Boolean).join(' · '), [leg.line_code + ' ' + t, ageText(m.wAge, 'hace')].join(' · '), leg.line_code + ' ' + t]);
    return inlineWrap('', [
      [leg.line_code + ' ' + t, v, t2].filter(Boolean).join(' · '),
      [leg.line_code + ' ' + t, v].filter(Boolean).join(' · '),
      leg.line_code + ' ' + t
    ]);
  };

  // =================================================================== C · Fases
  const C = {};
  /** La fase manda en la baldosa de la derecha (y en la compacta). */
  function phaseC(m, leg = m.leg, d = m.head) {
    if (m.ended) return 'fin';
    if (!d) return 'sin';
    if (d.at_stop) return 'anden';
    if (d.cd.kind === 'now' || d.cd.min <= 3) return 'corre';
    if (hasVia(d.via) || d.cd.min <= 8) return 'cerca';
    return 'lejos';
  }
  /** Qué va en la baldosa de la derecha: vía > transbordo > hora de salida (largos) > siguiente tren. */
  function sideC(m, leg, d, second, next) {
    if (!d) return { kind: 'sin' };
    if (hasVia(d.via)) return { kind: isReal(d.via) ? 'via' : 'prob' };
    if (next) return { kind: 'xfer' };
    if (d.cd.kind === 'long') return { kind: 'sale' };
    if (second) return { kind: 'luego' };
    return { kind: 'nada' };
  }
  C.side = (sd, m, leg, d, second, next, { compact = false } = {}) => {
    switch (sd.kind) {
      case 'via': return `<div class="C-t C-side is-via via-r${d.via.kind === 'new' ? ' is-new' : ''}" role="img" aria-label="vía ${esc(d.via.num)}"><small>Vía</small><b>${esc(d.via.num)}</b></div>`;
      case 'prob': return `<div class="C-t C-side is-prob via-p" role="img" aria-label="vía ${esc(d.via.num)} probable"><small>probable</small><b>${esc(d.via.num)}</b>${compact ? '' : `<em>${Math.round(d.via.share * 100)} %</em>`}</div>`;
      case 'xfer': return `<div class="C-t C-side is-xfer"><small>${ICON('swap')}<span class="fit" ${fitAlts(['Transbordo en ' + abreviar(leg.to_name).pop(), abreviar(leg.to_name).pop()])}>Transbordo en ${esc(abreviar(leg.to_name).pop())}</span></small><span class="C-xl">${badge(next, 22)}<b>${esc(nextTimes(next) || '—')}</b></span></div>`;
      case 'sale': return `<div class="C-t C-side is-sale"><small>sale</small><b>${esc(d.at)}</b>${d.delayTxt ? `<em class="mt-late">${esc(d.delayTxt)}</em>` : ''}</div>`;
      case 'luego': return `<div class="C-t C-side is-luego"><small>luego</small><span class="C-ln">${cdNum(second, 'n')}${cdUnit(second)}</span><em>${esc(second.at)}</em></div>`;
      default: return '';
    }
  };
  C.minTile = (d, leg, ph) => {
    if (!d) return `<div class="C-t C-tmin is-empty${leg.status.level >= 2 ? ' is-cut' : ''}">${ICON(leg.status.level >= 2 ? 'x' : 'clock')}${emptyFit(leg, 2)}<small>${esc(emptySub(leg))}</small></div>`;
    if (d.at_stop) return `<div class="C-t C-tmin is-stop"><b class="n w">En andén</b><small>sale ${esc(d.at)}</small></div>`;
    const p = T.pace(d.cd.min);
    return `<div class="C-t C-tmin ph-${ph} k-${d.cd.kind}" aria-label="${esc(ariaDep(d, leg))}"><span class="C-num">${cdNum(d)}${cdUnit(d)}</span>
      <small data-drop="end" data-vdrop="1"><span class="pace p-${p.id}">${p.short}</span>${d.delayTxt && d.cd.kind !== 'long' ? `<span class="mt-late">${esc(d.delayTxt)}</span>` : d.lenTxt ? `<span class="mt-len">${esc(d.lenTxt)}</span>` : ''}</small></div>`;
  };
  C.foot = (m, sd) => {
    const bits = [];
    // Prioridad del pie: transbordo > siguiente tren > hora de salida; y, en
    // el último tramo de una ruta con varios, «tramo N de M» (se cae si no cabe).
    if (m.next && sd.kind !== 'xfer') bits.push(`<span class="xfer">${ICON('swap')}<span class="fit" ${fitAlts(xferAlts(m))}>${esc(xferAlts(m)[0])}</span>${badge(m.next, 18)}<span class="xt">${esc(nextTimes(m.next, 1))}</span></span>`);
    else if (m.second && sd.kind !== 'luego') bits.push(`<span class="C-fl"><span class="lbl">luego</span>${cdNum(m.second, 'n', 'sm')}${cdUnit(m.second, 'u sm')}${viaMini(m.second.via, 'sm')}</span>`);
    else if (m.head) bits.push(`<span class="C-fl"><span class="lbl">sale ${esc(m.head.at)}</span></span>`);
    if (m.legCount > 1 && !m.next) bits.push(`<span class="lbl C-leg">tramo ${m.idx + 1} de ${m.legCount}</span>`);
    return bits.join('') || '<span class="C-fl"></span>';
  };
  C.la = m => {
    if (m.ended) return ended('C', m);
    const { leg, head, second, next } = m;
    const ph = phaseC(m); const sd = sideC(m, leg, head, second, next);
    return `<div class="la C-la ph-${ph}${m.laStale ? ' is-stale' : ''}">
      <div class="C-head">${badge(leg, 24)}<span class="C-dest"><i>→</i><b class="fit" ${fitAttr(head ? head.destination : leg.dir)}>${fitFirst(head ? head.destination : leg.dir)}</b></span>${head ? statusChip(leg.status) : ''}${ageLA(m)}</div>
      <div class="dim"><div class="C-tiles${sd.kind === 'nada' || sd.kind === 'sin' ? ' is-one' : ''}">${C.minTile(head, leg, ph)}${C.side(sd, m, leg, head, second, next)}</div>
      <div class="C-foot" data-drop="end">${C.foot(m, sd)}${stopBtn()}</div></div>
    </div>`;
  };
  C.compact = m => {
    const { head, leg } = m; const ph = phaseC(m);
    let t;
    if (!head) t = `<span class="di-x">${ICON('x')}</span>`;
    else if (ph === 'anden') t = `<span class="A-dstop"><small>andén</small>${viaMini(head.via) || '<b>●</b>'}</span>`;
    else if (hasVia(head.via)) t = `<span class="C-dvia">${viaMini(head.via, 'lg')}${cdNum(head, 'p', 'di-n sm')}</span>`;
    else t = `<span class="C-dnum ph-${ph}">${cdNum(head, 'n', 'di-n')}${cdUnit(head, 'di-u')}</span>`;
    return { lead: `<span class="di-l">${badge(leg, 24)}${head ? statusMark(leg.status) : ''}</span>`, trail: `<span class="C-dtrail${m.laStale ? ' is-stale' : ''}">${t}</span>` };
  };
  C.minimal = m => {
    const { head } = m;
    const inner = !head ? ICON('x')
      : head.at_stop ? `<small>andén</small>${viaMini(head.via, 'xs')}`
      : hasVia(head.via) ? `${cdNum(head, 'p', 'mn')}${viaMini(head.via, 'xs')}`
      : `${cdNum(head, 'n', 'mn')}${head.cd.u ? '<i>min</i>' : ''}`;
    return `<span class="C-min ph-${phaseC(m)}${m.laStale ? ' is-stale' : ''}">${inner}</span>`;
  };
  C.expanded = m => {
    const { leg, head, second, next } = m; const ph = phaseC(m); const sd = sideC(m, leg, head, second, next);
    const lead = `${badge(leg, 26)}<b class="x-dest1 fit" ${fitAttr(head ? head.destination : leg.dir)}>${fitFirst(head ? head.destination : leg.dir)}</b>`;
    const p = head && !head.at_stop ? T.pace(head.cd.min) : null;
    const trail = !head ? `<span class="x-empty">${esc(emptyWord(leg))}</span>` : head.at_stop ? `<span class="x-stop">En andén</span>`
      : `<span class="x-num ph-${ph}">${cdNum(head, 'n', 'xn')}${cdUnit(head, 'xu')}</span>`;
    // center (debajo de la cámara): el estado de la línea si lo hay; si no, el ritmo «Anda / Corre».
    const center = leg.status.level ? statusChip(leg.status, 'on-dark') : p && head.cd.kind !== 'long' ? `<span class="pace p-${p.id}">${p.short}</span>` : '';
    const side = head ? C.side(sd, m, leg, head, second, next) : `<div class="C-t C-side is-sin"><small>${esc(emptySub(leg))}</small></div>`;
    return { lead, trail, center, bottom: `<div class="C-xside">${side}</div><div class="C-xfoot">${m.laStale ? '' : C.foot(m, sd)}${ageLA(m)}${stopBtn('on-dark')}</div>` };
  };
  C.small = m => {
    const leg = m.legs[0], d = leg.deps[0], d2 = leg.deps[1];
    const ph = d ? phaseC({ ended: false }, leg, d) : 'sin';
    const sd = sideC(m, leg, d, d2, null);
    return `<div class="wd C-ws${m.wStale ? ' is-stale' : ''}">
      <div class="C-wh">${badge(leg, 20)}${d && leg.status.level ? statusChip(leg.status) : `<b class="fit" ${fitAttr(d ? d.destination : leg.dir)}>${fitFirst(d ? d.destination : leg.dir)}</b>`}${ageW(m)}</div>
      <div class="dim C-wstack">${C.minTile(d, leg, ph)}${sd.kind !== 'nada' && sd.kind !== 'sin' ? C.side(sd, m, leg, d, d2, null, { compact: true }) : ''}</div>
    </div>`;
  };
  C.medium = m => {
    const leg = m.legs[0], [d, d2, d3, d4] = leg.deps;
    const ph = d ? phaseC({ ended: false }, leg, d) : 'sin';
    const sd = sideC(m, leg, d, d2, null);
    const later = [sd.kind === 'luego' ? null : d2, d3, d4].filter(Boolean).slice(0, 2);
    return `<div class="wd C-wm${m.wStale ? ' is-stale' : ''}">
      <div class="C-mh">${badge(leg, 20)}<b class="fit" ${fitAttr(d ? d.destination : leg.dir)}>${fitFirst(d ? d.destination : leg.dir)}</b>${statusChip(leg.status)}${ageW(m)}</div>
      <div class="dim"><div class="C-tiles${sd.kind === 'nada' || sd.kind === 'sin' ? ' is-one' : ''}">${C.minTile(d, leg, ph)}${C.side(sd, m, leg, d, d2, null)}</div>
      ${later.length ? `<div class="C-mlater"><span class="lbl">después</span>${later.map(x => `<span class="C-mc">${cdNum(x, 'n')}${cdUnit(x, 'u')}${viaMini(x.via, 'sm')}</span>`).join('')}</div>` : ''}</div>
    </div>`;
  };
  C.large = m => {
    const leg = m.legs[0], [d, d2] = leg.deps;
    const ph = d ? phaseC({ ended: false }, leg, d) : 'sin';
    const sd = sideC(m, leg, d, d2, null);
    const later = leg.deps.slice(sd.kind === 'luego' ? 2 : 1, 4);
    const status = m.legs.slice(0, 4).map(l => {
      const x = l.deps[0];
      return `<div class="C-lsr"><span class="C-lsb">${badge(l, 22)}</span><span class="C-lst"><b class="fit" ${fitAlts([`${l.from_name} → ${l.dir}`, `${abreviar(l.from_name).pop()} → ${abreviar(l.dir).pop()}`, abreviar(l.from_name).pop()])}>${esc(l.from_name)} → ${esc(l.dir)}</b><small class="st-${l.status.level}">${l.status.level ? ICON(l.status.level >= 2 ? 'x' : 'warn') + statusWord(l.status) : 'circula con normalidad'}</small></span>
        <span class="C-lsn">${x ? (x.at_stop ? '<b class="n">andén</b>' : cdNum(x, 'n') + cdUnit(x, 'u')) : `<small>${l.status.level >= 2 ? 'cortada' : '—'}</small>`}</span></div>`;
    }).join('');
    return `<div class="wd C-wl${m.wStale ? ' is-stale' : ''}">
      <div class="C-lt">${badge(leg, 22)}<b class="fit" ${fitAttr(d ? d.destination : leg.dir)}>${fitFirst(d ? d.destination : leg.dir)}</b>${ageW(m)}</div>
      <div class="dim">
        <div class="C-tiles big${sd.kind === 'nada' || sd.kind === 'sin' ? ' is-one' : ''}">${C.minTile(d, leg, ph)}${C.side(sd, m, leg, d, d2, null)}</div>
        ${later.length ? `<div class="C-mlater"><span class="lbl">después</span>${later.map(x => `<span class="C-mc">${cdNum(x, 'n')}${cdUnit(x, 'u')}${viaMini(x.via, 'sm')}</span>`).join('')}</div>` : ''}
        <div class="C-lsh">Tu ruta · ${esc(m.route.name)}</div>
        <div class="C-ls">${status}</div>
      </div>
    </div>`;
  };
  C.circ = m => {
    const leg = m.legs[0], d = leg.deps[0];
    const inner = !d ? `<span class="lwc-x">${ICON('x')}</span>` : d.at_stop ? `<span class="lwc-w">andén</span>` : `${cdNum(d, 'n', 'lwc-n')}${d.cd.u ? '<i class="lwc-u">min</i>' : ''}`;
    const v = d && hasVia(d.via) ? `<span class="lwc-top ${isReal(d.via) ? 'via-r' : 'via-p'} ko">${esc(d.via.num)}</span>` : '';
    return `<div class="lw lw-c C-lwc${v ? ' has-via' : ''}">${gauge(d)}${v}<span class="lwc-in">${inner}</span><span class="lwc-lab">${esc(leg.line_code)}${d ? statusMark(leg.status, 'on-lw') : ''}</span></div>`;
  };
  C.rect = m => {
    const leg = m.legs[0], d = leg.deps[0];
    const d2 = leg.deps[1];
    const right = d && hasVia(d.via) ? `<span class="C-lrv ${isReal(d.via) ? 'via-r' : 'via-p'} ko"><small>${isReal(d.via) ? 'Vía' : 'prob.'}</small><b>${esc(d.via.num)}</b></span>`
      : d2 ? `<span class="C-lrv is-next"><small>luego</small><b>${cdNum(d2, 'n')}</b></span>` : '';
    return `<div class="lw lw-r C-lwr${m.wStale ? ' is-stale' : ''}">
      <div class="C-lrm">${badge(leg, 14, 'ko')}${d ? statusMark(leg.status, 'on-lw') : ''}${!d ? `<b class="lwr-big">${esc(emptyWord(leg))}</b>` : d.at_stop ? '<b class="lwr-big">andén</b>' : cdNum(d, 'n', 'lwr-n') + cdUnit(d, 'lwr-u')}</div>
      ${right}
      <div class="lwr-3">${m.wConn === 'offline' ? ICON('wifiOff') : ''}${ageEl('w', m.wAge)}</div>
    </div>`;
  };
  C.inline = m => {
    const leg = m.legs[0], d = leg.deps[0];
    if (!d) return inlineWrap(`${leg.line_code} · ${emptyWord(leg).toLowerCase()}`);
    const t = d.at_stop ? 'en andén' : `en ${cdText(d.cd, 'nu')}`;
    if (m.wConn === 'offline') return inlineWrap('', [`${leg.line_code} ${t} · sin conexión ${ageText(m.wAge, 'hace')}`, `${leg.line_code} ${t} · ${ageText(m.wAge, 'hace')}`, `${leg.line_code} ${t}`]);
    if (hasVia(d.via)) {
      const v = isReal(d.via) ? `Vía ${d.via.num}` : `Vía ${d.via.num} probable`;
      return inlineWrap('', [`${v} · ${leg.line_code} ${t}`, `${isReal(d.via) ? 'Vía ' + d.via.num : 'Vía ' + d.via.num + ' prob.'} · ${leg.line_code} ${t}`, `${leg.line_code} ${t}`]);
    }
    return inlineWrap('', [`${leg.line_code} ${t} · ${ageText(m.wAge, 'hace')}`, `${leg.line_code} ${t}`]);
  };

  // =================================================================== piezas compartidas
  /** Medidor del circular: Gauge(value: minutos, in: 0...30), arco de 270° abierto abajo.
      En iOS: ProgressView(timerInterval: salida−30 min...salida, countsDown: true)
      en `.accessoryCircular`, que avanza solo entre entradas del timeline. */
  function gauge(d) {
    const p = d && !d.at_stop ? Math.max(0, Math.min(1, d.cd.secs / 1800)) : 0;
    return `<svg class="gauge" viewBox="0 0 72 72" aria-hidden="true"><circle class="g-tr" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="75 100" transform="rotate(135 36 36)"/><circle class="g-v" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="${(p * 75).toFixed(2)} 100"${d ? ` data-gauge="${d.jid}"` : ''} transform="rotate(135 36 36)"/></svg>`;
  }
  function inlineWrap(text, alts) {
    const list = alts || [text];
    return `<div class="lw lw-i"><span class="fit" ${fitAlts(list)}>${esc(list[0])}</span></div>`;
  }
  /** Estado final: el trayecto ha terminado. La Live Activity se queda con un
      resumen y se retira sola a los 15 min (end(_:dismissalPolicy: .after)). */
  function ended(V, m) {
    const t = fmt.hhmm(m.now), q = fmt.hhmm(m.now + 900);
    const route = `<b class="fit" ${fitAlts([m.route.name])}>${esc(m.route.name)}</b>`;
    // No se dice «has llegado»: el trayecto también termina al pararlo a mano o al pasar la duración máxima.
    const sub = `<small class="end-sub">Se quita sola a las ${esc(q)} · toca para abrir la ruta</small>`;
    if (V === 'A') return `<div class="la A-la is-ended">
      <div class="A-head">${badge(m.leg, 24)}<b class="end-t">Trayecto terminado</b><span class="age">${esc(t)}</span></div>
      <div class="A-tk is-end"><div class="A-num">${ICON('check', 'end-ico')}</div><div class="A-meta end-b">${route}${sub}</div></div>
    </div>`;
    if (V === 'B') return `<div class="la B-la is-ended">
      <div class="B-head">${badge(m.leg, 24)}<span class="B-where"><b>Trayecto terminado</b><small>a las ${esc(t)}</small></span></div>
      <div class="B-row"><span class="B-tile sz-l is-end">${ICON('check', 'end-ico')}</span><span class="B-txt">${route}${sub}</span></div>
    </div>`;
    return `<div class="la C-la is-ended">
      <div class="C-head">${badge(m.leg, 24)}<span class="C-dest"><b>Trayecto terminado</b></span><span class="age">${esc(t)}</span></div>
      <div class="C-tiles"><div class="C-t C-tmin is-end">${ICON('check', 'end-ico')}<b>Terminado</b></div><div class="C-t C-side is-end">${route}${sub}</div></div>
    </div>`;
  }

  const V = { A, B, C };

  // =================================================================== escenas (presets del panel)
  const SCENE_KEYS = { platform: 'real', busLong: false, cut: false, notice: 'none', offline: false, atStop: false, emptyLeg: false, transfer: false, legNow: 0, tripEnded: false, frozen: false,
    // 2B.4 (las ven las tres; solo A las trata):
    frozenAt: null, cancelled: false, platformChange: false, platformChangeAt: null, mixed: false, noKey: false, longNames: false, endReason: 'auto', wOldMin: 20 };
  // [id, rótulo, escenario, opciones]. Opciones: newVia (la vía aparece ahora),
  // t (pone el reloj), frozenAgo / frozenAt (la app dejó de escribir hace N s / a esa hora),
  // change (cambio de vía ahora), offlineAgo (sin red desde hace N s).
  const SCENES = [
    ['via-real', 'Vía real', { platform: 'real' }, { newVia: false }],
    ['via-probable', 'Vía probable', { platform: 'guess' }],
    ['sin-via', 'Sin vía', { platform: 'none' }],
    ['via-aparece', 'Aparece la vía', { platform: 'real' }, { newVia: true }],
    ['cambio-via', 'Cambio de vía', { platform: 'real', platformChange: true }, { change: true }],
    ['cancelado', 'Tren cancelado', { platform: 'real', cancelled: true }],
    ['bus-1h46', 'Bus a 1h46', { busLong: true }],
    ['linea-cortada', 'Línea cortada', { transfer: true, legNow: 0, cut: true }],
    ['servicio-finalizado', 'Servicio finalizado', { transfer: true, legNow: 0, emptyLeg: true }],
    ['aviso', 'Aviso (perturbada)', { notice: 'translated' }],
    ['destinos-mezclados', 'Destinos mezclados', { mixed: true }],
    ['en-anden', 'En el andén', { atStop: true }],
    ['transbordo', 'Transbordo · tramo 1', { transfer: true, legNow: 0 }],
    ['transbordo-2', 'Transbordo · tramo 2', { transfer: true, legNow: 1 }],
    ['dato-antiguo', 'Dato antiguo', { frozen: true }, { frozenAgo: 360 }],
    ['congelada-tren-salido', 'Congelada · el tren ya salió', { frozen: true }, { t: '12:57:30', frozenAt: '12:55:40' }],
    ['sin-conexion', 'Sin conexión', { offline: true }],
    ['sin-clave', 'Servidor sin clave PRIM', { offline: true, noKey: true }],
    ['sin-datos-recientes', 'Sin datos recientes (13:50)', { offline: true, wOldMin: 20 }, { t: '13:50:00', offlineAgo: 3600 }],
    ['nombres-largos', 'Nombres largos', { transfer: true, legNow: 1, longNames: true }],
    ['terminado', 'Terminado (llegada)', { tripEnded: true, endReason: 'auto' }],
    ['terminado-a-mano', 'Parado a mano', { tripEnded: true, endReason: 'manual' }]
  ];
  const hms = str => { const [h, mi, se] = String(str).split(':').map(Number); return h * 3600 + mi * 60 + (se || 0); };
  function setClock(str) { clock.base = hms(str); clock.epoch = Date.now(); clock.save(); }
  function applyScene(id) {
    const sc = SCENES.find(x => x[0] === id); if (!sc) return;
    const [, , patch, opt = {}] = sc;
    if (opt.t) setClock(opt.t);
    const base = Object.assign({}, SCENE_KEYS, patch);
    if (opt.frozenAgo) base.frozenAt = clock.now() - opt.frozenAgo;
    if (opt.frozenAt) base.frozenAt = hms(opt.frozenAt);
    if (opt.change) base.platformChangeAt = clock.now();
    if (opt.newVia) {          // sin vía y, al momento, la vía: el núcleo la marca como nueva (25 s)
      scenarios.set(Object.assign({}, base, { platform: 'none' }));
      scenarios.set({ platform: 'real' });
    } else {                   // todo lo demás, con la vía ya conocida (no «nueva»)
      scenarios.set(base);
      scenarios.set({ platformNewAt: null });
    }
    // Captura determinista: la red se perdió «ahora» (u offlineAgo segundos antes).
    if (base.offline) scenarios.set({ offlineSince: clock.now() - (opt.offlineAgo || 0) });
    lab.scene = id;
  }

  // =================================================================== pantallas del iPhone
  const WEEKDAY = 'jueves 24 de septiembre';
  const sbar = (dev, { time = true, dark = false, busy = false } = {}) => `<div class="ios-sb dev-${dev.id}${dev.island ? '' : ' is-se'}${dark ? ' on-dark' : ''}${busy ? ' is-busy' : ''}">${time ? `<span class="ios-t" data-clock>${fmt.hhmm(clock.now())}</span>` : '<span></span>'}<span class="ios-ic">${busy ? '' : '<i class="sb-signal"></i><i class="sb-wifi"></i>'}<i class="sb-batt"></i></span></div>`;
  const camera = dev => dev.island ? `<span class="cam" style="--cw:${(dev.island.total - dev.island.side * 2).toFixed(2)}px;--ch:${dev.island.h}px;--ct:${dev.island.top}px"></span>` : '';
  function lockScreen(v, m, dev) {
    const P = V[v];
    return `<div class="phone lock-ph dev-${dev.id}" id="ph-lock" style="--pw:${dev.w}px;--ph:${dev.h}px;--pr:${dev.radius}px">
      <div class="scr wall">
        ${camera(dev)}
        <div class="lock-sb"><span class="ios-ic"><i class="sb-signal"></i><i class="sb-wifi"></i><i class="sb-batt"></i></span></div>
        <div class="lock-top">
          <div class="lock-date"><span>jue 24</span><span class="pc lwi" id="p-lw-inline" style="width:${dev.lwI[0]}px;height:${dev.lwI[1]}px">${P.inline(m)}</span></div>
          <div class="lock-clock" data-clock>${fmt.hhmm(m.now)}</div>
          <div class="lock-wids">
            <span class="pc" id="p-lw-circ" style="--lw:${dev.lwC}px">${P.circ(m)}</span>
            <span class="pc" id="p-lw-rect" style="width:${dev.lwR[0]}px;height:${dev.lwR[1]}px">${P.rect(m)}</span>
            <span class="pc lw-other" style="--lw:${dev.lwC}px"><div class="lw lw-c other"><svg class="gauge" viewBox="0 0 72 72"><circle class="g-tr" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="75 100" transform="rotate(135 36 36)"/><circle class="g-v" cx="36" cy="36" r="31" pathLength="100" stroke-dasharray="52 100" transform="rotate(135 36 36)"/></svg><span class="lwc-in"><b class="lwc-n">18°</b></span><span class="lwc-lab">París</span></div></span>
          </div>
        </div>
        <div class="lock-la"><div class="pc" id="p-la" style="width:${dev.la}px">${P.la(m)}</div></div>
        ${dev.island ? `<div class="lock-btns"><span class="lb-btn">${ICON('sun')}</span><span class="lb-btn">${ICON('eye')}</span></div><span class="home-ind"></span>` : '<div class="lock-se">Pulsa el botón de inicio para abrir</div>'}
      </div>
    </div>`;
  }
  /* Piezas de la isla comunes a las tres variantes. La A (2B.4) recibe
     además el tamaño de la isla (para sus alternativas de ancho), su propio
     ancho de la mínima, una clase para el apagado y su enlace. */
  const endedOf = (v, m) => v === 'A' ? !!m.A.la.ended : m.ended;
  const minWOf = (v, m, I) => V[v].minW ? V[v].minW(m, I) : minW(m, I);
  function diCompact(v, m, I) {
    const c = V[v].compact(m, I), cw = I.total - I.side * 2;
    const link = v === 'A' ? ` data-link="${esc(m.A.la.url)}"` : '';
    return `<div class="di di-compact v-${v}" style="width:${I.total}px;height:${I.h}px"${link}><span class="di-lead" style="width:${I.side}px">${c.lead}</span><span class="di-cam" style="width:${cw}px"></span><span class="di-trail" style="width:${I.side}px">${c.trail}</span></div>`;
  }
  function diMinimal(v, m, I) {
    return `<div class="di di-minimal v-${v}" style="width:${minWOf(v, m, I)}px;height:${I.h}px">${V[v].minimal(m, I)}</div>`;
  }
  const xGrid = (x, cw) => `<div class="x-grid ${x.cls || ''}" style="--cw:${cw}px"><div class="x-lead">${x.lead}</div><div class="x-cam"></div><div class="x-trail">${x.trail}</div><div class="x-center">${x.center || ''}</div><div class="x-bottom">${x.bottom}</div></div>`;
  function diExpanded(v, m, I, cls = '') {
    const x = V[v].expanded(m, I), cw = I.total - I.side * 2;
    return `<div class="di di-expanded v-${v} ${cls}" style="width:${I.exp}px"${x.link ? ` data-link="${esc(x.link)}"` : ''}>${xGrid(x, cw)}</div>`;
  }
  /** La isla dentro de una franja de pantalla («en otra app»). */
  function islandTop(v, m, dev, state, id) {
    const I = dev.island;
    const cw = I.total - I.side * 2;
    const ended = endedOf(v, m);
    let di;
    if (ended) di = `<div class="di di-gone"><span class="di-cam"></span></div>`;
    else if (state === 'compact') di = diCompact(v, m, I);
    else if (state === 'minimal') di = `<div class="di-pair" style="--cw:${cw}px;--ih:${I.h}px"><div class="di di-other" style="height:${I.h}px"><span class="di-oth">${ICON('clock')}</span><span class="di-cam" style="width:${cw}px"></span></div>${diMinimal(v, m, I)}</div>`;
    else di = diExpanded(v, m, I, 'pc');
    return `<div class="ptop dev-${dev.id} st-${state}" id="${id}" style="--pw:${dev.w}px;--pr:${dev.radius}px;--dit:${I.top}px">
      <div class="scr app-bg">${sbar(dev, { busy: state !== 'expanded' && !ended })}<div class="app-fake">${fakeApp()}</div><div class="di-wrap${state === 'expanded' ? ' is-exp' : ''}">${di}</div></div>
    </div>`;
  }
  /** La mínima es circular (36,67) u ovalada hasta 45 pt: la ovalada para «1h46». */
  const minW = (m, I) => m.head && m.head.cd.kind === 'long' ? 45 : I.h;
  const fakeApp = () => `<div class="fa-title">Notas</div>${[92, 70, 84, 55, 78, 64].map(w => `<div class="fa-row"><i style="width:${w}%"></i><i style="width:${w - 30}%"></i></div>`).join('')}`;
  /** iPhone SE: sin isla. Una actualización con alerta sale como banner arriba. */
  function seBanner(v, m, dev) {
    return `<div class="ptop dev-se st-banner" id="ph-di-banner" style="--pw:${dev.w}px;--pr:0px">
      <div class="scr app-bg">${sbar(dev)}<div class="app-fake">${fakeApp()}</div><div class="se-banner"><div class="pc" id="p-di-banner" style="width:${dev.la}px">${V[v].la(m)}</div></div></div>
    </div>`;
  }
  const APPS = [['Mail', 'mail'], ['Fotos', 'photos'], ['Mapas', 'maps'], ['Música', 'music'], ['Cámara', 'camera'], ['Ajustes', 'settings'], ['Reloj', 'clock'], ['Notas', 'notes'], ['Tiempo', 'weather'], ['Wallet', 'wallet'], ['Calendario', 'cal'], ['Salud', 'health']];
  const appIcon = ([n, k]) => `<span class="happ"><i class="ai ai-${k}"></i><small>${n}</small></span>`;
  function homeScreen(v, m, dev, page) {
    const P = V[v]; const tint = m.s.widgetTint || 'full';
    const dock = `<div class="dock">${APPS.slice(0, 4).map(a => `<span class="happ"><i class="ai ai-${a[1]}"></i></span>`).join('')}</div>`;
    let body;
    if (page === 1) body = `
      <div class="hgrid">
        <div class="hrow"><span class="pc" id="p-w-s" style="width:${dev.wS}px;height:${dev.wS}px">${P.small(m)}</span><span class="h4" style="width:${dev.wS}px;height:${dev.wS}px">${APPS.slice(4, 8).map(appIcon).join('')}</span></div>
        <div class="hrow"><span class="pc" id="p-w-m" style="width:${dev.wM[0]}px;height:${dev.wM[1]}px">${P.medium(m)}</span></div>
        <div class="hrow icons">${APPS.slice(8, 12).map(appIcon).join('')}</div>
      </div>`;
    else body = `
      <div class="hgrid">
        <div class="hrow"><span class="pc" id="p-w-l" style="width:${dev.wL[0]}px;height:${dev.wL[1]}px">${P.large(m)}</span></div>
        <div class="hrow icons">${APPS.slice(4, 8).map(appIcon).join('')}</div>
      </div>`;
    return `<div class="phone home-ph dev-${dev.id} tint-${tint}" id="ph-home${page}" style="--pw:${dev.w}px;--ph:${dev.h}px;--pr:${dev.radius}px;--icon:${dev.icon}px;--wm:${dev.wM[0]}px">
      <div class="scr wall home-wall">${camera(dev)}${sbar(dev, { dark: true })}${body}<div class="dots"><i class="${page === 1 ? 'on' : ''}"></i><i class="${page === 2 ? 'on' : ''}"></i></div>${dock}${dev.island ? '<span class="home-ind"></span>' : ''}</div>
    </div>`;
  }

  // =================================================================== vistas del laboratorio
  function lamina(m) {
    const dev = DEVICES[lab.device] || DEVICES.i16; const v = lab.v;
    const islands = dev.island
      ? ['compact', 'minimal', 'expanded'].map(st => `<figure class="fig"><figcaption>${{ compact: 'Compacta', minimal: 'Mínima (con otra app)', expanded: 'Expandida' }[st]} <em class="mtag" data-measure=".di-${st}" data-max="${st === 'expanded' ? 160 : 0}"></em></figcaption>${islandTop(v, m, dev, st, 'ph-di-' + st)}</figure>`).join('')
        + `<figure class="fig"><figcaption>Morph (toca para cambiar)</figcaption>${islandDemo(v, m, dev)}</figure>`
      : `<figure class="fig"><figcaption>Sin Dynamic Island: banner al actualizar con alerta</figcaption>${seBanner(v, m, dev)}</figure>`;
    return `<div class="lam v-${v}">
      <section class="lcol"><h3>Pantalla de bloqueo <small>Live Activity <em class="mtag" data-measure="#p-la .la" data-max="160"></em> · widgets circular, rectangular y en línea</small></h3>${lockScreen(v, m, dev)}</section>
      <section class="lcol"><h3>Dynamic Island <small>${dev.island ? `${dev.island.side} × ${dev.island.h} pt por lado · expandida ${dev.island.exp} pt` : 'el SE no tiene isla'}</small></h3><div class="figs">${islands}</div></section>
      <section class="lcol"><h3>Inicio · 1 <small>pequeño ${dev.wS} · mediano ${dev.wM.join(' × ')}</small></h3>${homeScreen(v, m, dev, 1)}</section>
      <section class="lcol"><h3>Inicio · 2 <small>grande ${dev.wL.join(' × ')}</small></h3>${homeScreen(v, m, dev, 2)}</section>
    </div>`;
  }
  /** La isla que cambia de forma (compacta ↔ expandida ↔ mínima) con muelle. */
  function islandDemo(v, m, dev) {
    const I = dev.island, P = V[v]; const cw = I.total - I.side * 2;
    const c = P.compact(m, I), x = P.expanded(m, I);
    return `<div class="ptop dev-${dev.id} demo${endedOf(v, m) ? ' is-gone' : ''}" id="ph-di-demo" style="--pw:${dev.w}px;--pr:${dev.radius}px;--dit:${I.top}px">
      <div class="scr app-bg">${sbar(dev, { busy: true })}<div class="app-fake">${fakeApp()}</div>
        <div class="dmorph v-${v}" id="dmorph" style="--tot:${I.total}px;--side:${I.side}px;--cw:${cw}px;--ih:${I.h}px;--exp:${I.exp}px" role="button" tabindex="0" aria-label="Cambiar la forma de la isla">
          <div class="dm-c"><span class="di-lead" style="width:${I.side}px">${c.lead}</span><span class="di-cam" style="width:${cw}px"></span><span class="di-trail" style="width:${I.side}px">${c.trail}</span></div>
          <div class="dm-m" style="width:${minWOf(v, m, I)}px">${P.minimal(m, I)}</div>
          <div class="dm-x">${xGrid(x, cw)}</div>
        </div>
      </div>
    </div>`;
  }
  /** Comparar: la misma pieza en las tres variantes, una fila por pieza. */
  function comparar(m) {
    const dev = DEVICES[lab.device] || DEVICES.i16;
    const row = (title, sub, cell, sel = '', max = 0) => `<div class="crow"><div class="chead"><b>${title}</b><small>${sub}</small></div>${['A', 'B', 'C'].map(v => `<div class="ccell"><span class="ctag">${v} · ${VARIANTS[v].name}${sel ? ` <em class="mtag" data-measure="${sel}" data-max="${max}"></em>` : ''}</span>${cell(v)}</div>`).join('')}</div>`;
    const onWall = (inner, cls = '') => `<div class="cwall wall ${cls}">${inner}</div>`;
    const I = dev.island;
    const di = (v, st) => {
      if (!I) return '<p class="cnone">sin isla</p>';
      if (endedOf(v, m)) return '<p class="cnone">terminada: sale de la isla</p>';
      if (st === 'compact') return `<div class="cdi">${diCompact(v, m, I)}</div>`;
      if (st === 'minimal') return `<div class="cdi">${diMinimal(v, m, I)}</div>`;
      return `<div class="cdi">${diExpanded(v, m, I)}</div>`;
    };
    const tint = m.s.widgetTint || 'full';
    return `<div class="cmp">
      ${row('Live Activity', `bloqueo · ${dev.la} pt de ancho · 84–160 de alto`, v => onWall(`<div class="pc" style="width:${dev.la}px">${V[v].la(m)}</div>`, 'lockish'), '.la', 160)}
      ${row('Isla compacta', I ? `${I.side} pt por lado · ${I.total} en total` : '—', v => di(v, 'compact'), '.di-compact')}
      ${row('Isla mínima', I ? `${I.h}–45 × ${I.h} pt` : '—', v => di(v, 'minimal'), '.di-minimal')}
      ${row('Isla expandida', I ? `${I.exp} pt de ancho · 84–160 de alto` : '—', v => di(v, 'expanded'), '.di-expanded', 160)}
      ${row('Widget pequeño', `${dev.wS} pt`, v => onWall(`<div class="pc" style="width:${dev.wS}px;height:${dev.wS}px">${V[v].small(m)}</div>`, `homeish tint-${tint}`))}
      ${row('Widget mediano', dev.wM.join(' × '), v => onWall(`<div class="pc" style="width:${dev.wM[0]}px;height:${dev.wM[1]}px">${V[v].medium(m)}</div>`, `homeish tint-${tint}`))}
      ${row('Widget grande', dev.wL.join(' × '), v => onWall(`<div class="pc" style="width:${dev.wL[0]}px;height:${dev.wL[1]}px">${V[v].large(m)}</div>`, `homeish tint-${tint}`))}
      ${row('Bloqueo', `circular ${dev.lwC} · rectangular ${dev.lwR.join(' × ')} · en línea ${dev.lwI.join(' × ')}`, v => onWall(`<div class="clock-row"><span class="pc" style="width:${dev.lwI[0]}px;height:${dev.lwI[1]}px">${V[v].inline(m)}</span></div><div class="lock-wids"><span class="pc" style="--lw:${dev.lwC}px">${V[v].circ(m)}</span><span class="pc" style="width:${dev.lwR[0]}px;height:${dev.lwR[1]}px">${V[v].rect(m)}</span></div>`, 'lockish'))}
    </div>`;
  }
  /** «Viva y congelada» (solo A): la misma Live Activity cuando la app la
      reescribe (modo trayecto) y cuando dejó de escribir a una hora dada.
      Enseña lo único que iOS mueve solo (cifra por fecha si es del sistema,
      antigüedad) y el paso a «sin actualizar» al vencer staleDate. */
  const VC_KEYS = { frozen: false, offline: false, noKey: false, tripEnded: false, cancelled: false, platformChange: false };
  function vivaCongelada(m) {
    const dev = DEVICES[lab.device] || DEVICES.i16, I = dev.island || DEVICES.i16.island;
    const { viva, cong } = m.AX;
    const col = (a, title, sub) => {
      const mm = { A: a, s: m.s };
      const st = a.la.stale ? `staleDate vencida a las ${fmt.hhmm(a.la.staleAt)}:${String(Math.floor(a.la.staleAt) % 60).padStart(2, '0')}` : a.la.conn === 'frozen' ? `staleDate: ${fmt.hhmm(a.la.staleAt)}:${String(Math.floor(a.la.staleAt) % 60).padStart(2, '0')}` : 'la app reescribe cada minuto y cada refresco';
      return `<section class="vc-col"><h4>${title}</h4><p>${sub} · <b>${st}</b></p>
        <div class="cwall wall lockish"><div class="pc" style="width:${dev.la}px">${A.la(mm)}</div></div>
        <div class="cdi">${diCompact('A', mm, I)}</div>
      </section>`;
    };
    return `<div class="vc"><div class="vc-clock">Reloj <b data-clock>${fmt.hhmm(m.now)}</b> <span data-clock-s>${String(Math.floor(m.now) % 60).padStart(2, '0')}</span> s</div>
      ${col(viva, 'La app actualiza', 'modo trayecto: cada 30 s y en cada cambio de minuto')}
      ${col(cong, `La app dejó de escribir a las ${esc(lab.fz || '12:55:40')}`, 'ContentState fijo; solo el sistema mueve textos de fecha')}
    </div>`;
  }

  /** «Casos límite» (solo A): la compacta, la mínima y la expandida con las cifras
      que más ocupan (P1-5): «59′ + vía», «1h46», «ya», «andén», el texto del
      sistema y el de iOS 17, caducada y apagada. Salidas sintéticas con la forma
      de la API; cada pieza lleva su medida (la compacta no debe pasar de 230/250). */
  const LIMIT_CASES = [
    ['5 min + vía real', { min: 5, platform: '21' }],
    ['59 min + vía real', { min: 59, platform: '21' }],
    ['59 min + probable', { min: 59, guess: '21' }],
    ['12 min + vía «9»', { min: 12, platform: '9' }],
    ['1h46 (bus, sin vía)', { min: 106, bus: true }],
    ['ya + vía real', { secs: 20, platform: '21' }],
    ['en el andén + vía', { min: 3, platform: '21', atStop: true }],
    ['sistema: 59 min + vía', { min: 59, platform: '21', mode: 'sys' }],
    ['iOS 17: 59:59 + vía', { min: 59, platform: '21', mode: 'ios17' }],
    ['caducada: hora fija', { min: 21, guess: '21', stale: true }],
    ['sin conexión', { min: 6, platform: '21', conn: 'offline' }]
  ];
  function limitModel(c, i, now) {
    const secs = c.secs != null ? c.secs : c.min * 60 - 20;
    const at = fmt.hhmm(now + secs + 30);
    const dep = { jid: 'lim' + i, minutes: Math.max(0, Math.round(secs / 60)), at, aimed_at: '', destination: c.bus ? 'Pont de Bezons' : 'Ermont - Eaubonne',
      platform: c.platform || null, platform_new: false, delay: null, status: 'onTime', at_stop: !!c.atStop, train: null, length: null };
    if (c.guess) dep.guess = { platform: c.guess, share: 0.9, samples: 20, basis: 'mision', why: 'por el número de tren' };
    const raw = c.bus ? Object.assign({}, D0().busLeg, { departures: [dep] }) : Object.assign({}, D0().calmBoard.legs[0], { departures: [dep] });
    const leg = prepLeg(raw, now);
    const hero = leg.all[0];
    const a = { ns: 'lim' + i, now, mode: c.mode || 'app', s: scenarios.get(), route: { id: 1, name: 'Trabajo → Casa' },
      la: { conn: c.conn || 'live', stale: !!c.stale, staleAt: now - 30, writtenAt: now, age: 12, off: !!c.stale || !!c.conn, trip: [leg], idx: 0, leg, nextLeg: null, cs: [hero], hero, second: null, cancelled: null, link: null, legCount: 1, ended: null, url: 'trajet://ruta/1?tramo=0' } };
    a.dep = (ctx, jid) => leg.all.find(x => x.jid === jid) || null;
    return a;
  }
  const D0 = () => window.TrajetData;
  function limites(m) {
    const dev = DEVICES[lab.device] && DEVICES[lab.device].island ? DEVICES[lab.device] : DEVICES.i16, I = dev.island;
    const rows = LIMIT_CASES.map(([label], i) => {
      const mm = { A: m.AX['lim' + i], s: m.s };
      return `<div class="crow lim"><div class="chead"><b>${esc(label)}</b><small>${esc(LIMIT_CASES[i][1].mode === 'sys' ? 'texto del sistema, una talla' : LIMIT_CASES[i][1].mode === 'ios17' ? 'Text(timerInterval:)' : 'cifra escrita por la app')}</small></div>
        <div class="ccell"><span class="ctag">Compacta <em class="mtag" data-measure=".di-compact" data-max="0"></em></span><div class="cdi">${diCompact('A', mm, I)}</div></div>
        <div class="ccell"><span class="ctag">Mínima <em class="mtag" data-measure=".di-minimal" data-max="0"></em></span><div class="cdi">${diMinimal('A', mm, I)}</div></div>
        <div class="ccell"><span class="ctag">Expandida <em class="mtag" data-measure=".di-expanded" data-max="160"></em></span><div class="cdi">${diExpanded('A', mm, I)}</div></div></div>`;
    }).join('');
    return `<div class="cmp lims"><p class="lim-note">${dev.name} · la compacta mide ${I.side} pt por lado (${I.total} en total); si una etiqueta pasa de ${I.total}, la isla ha crecido.</p>${rows}</div>`;
  }

  // =================================================================== montaje
  const sheet = () => document.getElementById('sheet2');
  let lastMasked = '';
  const mask = h => h.replace(/data-fit="[^"]*"(?= data-agefit)/g, '')
    .replace(/(<[^>]+data-(?:cd|cdu|age|clock|acd|acu|aage)(?:="[^"]*")?[^>]*>)[^<]*/g, '$1#')
    .replace(/stroke-dasharray="[\d.]+ 100"( data-a?gauge)/g, 'sd$1');
  /** El modelo de B y C (el de la 2B.3, tal cual) y, para A, su «foto» (modelA). */
  function models() {
    const m = model();
    m.A = modelA();
    if (lab.view === 'limites') { m.AX = {}; LIMIT_CASES.forEach((c, i) => { m.AX['lim' + i] = limitModel(c[1], i, m.now); }); }
    if (lab.view === 'congelada') m.AX = { viva: modelA(Object.assign({}, VC_KEYS), 'viva'), cong: modelA(Object.assign({}, VC_KEYS, { frozen: true, frozenAt: hms(lab.fz || '12:55:40') }), 'cong') };
    return m;
  }
  /** Aspectos de iOS que el laboratorio simula en <html> (los lee style.css). */
  function applyAspect(s) {
    const h = document.documentElement;
    h.dataset.num = s.numMode || 'app';
    h.dataset.aod = s.aod ? '1' : '0';
    h.dataset.standby = s.standby ? '1' : '0';
    h.dataset.hc = s.hc ? '1' : '0';
    h.dataset.dt = s.dtA || 'L';
    h.dataset.acc = s.accentMode || 'calado';
    h.dataset.hits = s.showHits ? '1' : '0';
  }
  function render(force = false) {
    const m = models();
    applyAspect(m.s);
    const html = lab.view === 'comparar' ? comparar(m) : lab.view === 'congelada' ? vivaCongelada(m) : lab.view === 'limites' ? limites(m) : lamina(m);
    const masked = mask(html) + lab.view + lab.v + lab.device;
    if (!force && masked === lastMasked) { tick(m); return; }
    lastMasked = masked;
    sheet().innerHTML = html;
    const dm = document.getElementById('dmorph');
    if (dm) { const st = endedOf(lab.v, m) ? 'gone' : lab.island; dm.classList.add('st-' + st, 'no-anim'); dm.dataset.state = st; void dm.offsetWidth; dm.classList.remove('no-anim'); }
    layout(sheet());
    applyZoom();
    tick(m);
    updateToolbar();
  }
  function layout(root) {
    fitAll(root);
    fitAlternatives(root);
    fitRows(root);
    fitGroups(root);
    dropPrio(root);
    shrinkAll(root);
    postLayout(root);
  }
  /** «Lo que no cabe se cae entero»: quita hijos completos (desde el final o el
      principio) hasta que la fila cabe. En SwiftUI: ViewThatFits con las
      combinaciones de la fila, de la más completa a la más corta. */
  function dropOverflow(root) {
    root.querySelectorAll('[data-drop="age-up"]').forEach(row => {
      const age = row.querySelector(':scope > .age');
      if (!age || row.scrollWidth <= row.clientWidth + 0.5) return;
      const head = row.closest('.wd').querySelector('.A-wh');
      const dest = head && head.querySelector(':scope > .fit');
      if (dest) dest.remove();
      head && head.appendChild(age);
    });
    root.querySelectorAll('[data-drop="start"], [data-drop="end"]').forEach(row => {
      const kids = [...row.children].filter(k => !k.classList.contains('age') && !k.classList.contains('stop'));
      kids.forEach(k => { k.style.display = ''; });
      const order = row.dataset.drop === 'start' ? kids : kids.slice().reverse();
      for (const k of order) {
        if (row.scrollWidth <= row.clientWidth + 0.5) break;
        if (order.filter(x => x.style.display !== 'none').length <= 1 && row.dataset.drop === 'end') break;
        k.style.display = 'none';
      }
    });
  }
  /** Lo mismo en vertical: si una caja de alto fijo (widget, baldosa) no
      cabe, se quitan enteros sus elementos marcados con data-vdrop, del 1 al 9. */
  function dropVertical(root) {
    root.querySelectorAll('.wd, .wd .dim, .C-t').forEach(box => {
      const drops = [...box.querySelectorAll(':scope [data-vdrop]')].filter(d => d.closest('.wd, .dim, .C-t') === box)
        .sort((a, b) => Number(a.dataset.vdrop) - Number(b.dataset.vdrop));
      drops.forEach(d => { d.style.display = ''; });
      for (const d of drops) { if (box.scrollHeight <= box.clientHeight + 1) break; d.style.display = 'none'; }
    });
  }
  /* ---- Ajuste de A (2B.4): cuatro mecanismos, todos con su equivalente en SwiftUI.
     1. fitAlternatives · data-altset: ViewThatFits con alternativas enteras (compacta, expandida).
     2. fitRows · data-fitrow: una fila con piezas .fitr que se acortan por prioridad
        (data-prio: la más baja primero) hasta que la fila cabe; la última variante
        de cada pieza es «nada». En SwiftUI: ViewThatFits con las combinaciones.
     3. fitGroups · data-fitgroup: un solo nivel de abreviatura en todo el widget (P2-16).
     4. dropPrio · data-droprow: quita piezas enteras por prioridad (data-dp: la más
        baja primero) si la caja se desborda en ancho o en alto (Dynamic Type). */
  const overflows = el => el.scrollWidth > el.clientWidth + 0.5 || el.scrollHeight > el.clientHeight + 1;
  function fitAlternatives(root) {
    root.querySelectorAll('[data-altset]').forEach(set => {
      const alts = [...set.querySelectorAll(':scope > [data-alt]')];
      const cs = getComputedStyle(set);
      const max = set.dataset.altmax ? Number(set.dataset.altmax) : set.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      let chosen = alts[alts.length - 1];
      alts.forEach(a => { a.style.display = 'none'; });
      for (const a of alts) { a.style.display = ''; if (a.scrollWidth <= max + 0.5) { chosen = a; break; } a.style.display = 'none'; }
      alts.forEach(a => { a.style.display = a === chosen ? '' : 'none'; });
      set.dataset.altLevel = String(alts.indexOf(chosen));
    });
  }
  function fitRows(root) {
    root.querySelectorAll('[data-fitrow]').forEach(row => {
      const all = [...row.querySelectorAll('.fitr')].filter(e => e.closest('[data-fitrow]') === row);
      all.forEach(e => { e._alts = e.dataset.alts.split('|'); e._lvl = 0; e.textContent = e._alts[0]; e.classList.toggle('is-gone', !e._alts[0]); });
      const items = all.filter(e => e.offsetParent !== null);
      let guard = 0;
      while (row.scrollWidth > row.clientWidth + 0.5 && guard++ < 60) {
        const pr = e => { const st = String(e.dataset.prio || 5).split(' ').map(Number); return st[Math.min(e._lvl, st.length - 1)]; };
        const cands = items.filter(e => e._lvl < e._alts.length - 1).sort((p, q) => pr(p) - pr(q));
        if (!cands.length) break;
        const e = cands[0]; e._lvl++; e.textContent = e._alts[e._lvl]; e.classList.toggle('is-gone', !e._alts[e._lvl]);
      }
      items.forEach(e => { e.dataset.fitLevel = String(e._lvl); });
    });
  }
  let gidSeq = 0;
  function fitGroups(root) {
    const groups = {};
    root.querySelectorAll('[data-fitgroup]').forEach(e => {
      const host = e.closest('.wd, .la, .lw, .di') || root;
      if (!host.dataset.gid) host.dataset.gid = String(++gidSeq);
      const k = host.dataset.gid + ':' + e.dataset.fitgroup;
      (groups[k] = groups[k] || []).push(e);
    });
    Object.values(groups).forEach(list => {
      // Un solo nivel de abreviatura en el widget: el más corto que haya necesitado alguien.
      const shown = list.filter(e => e._alts && !e.classList.contains('is-gone'));
      if (!shown.length) return;
      const target = Math.max(...shown.map(e => Number(e.dataset.fitLevel || 0)));
      shown.forEach(e => {
        const lastText = e._alts.length - 1 - (e._alts[e._alts.length - 1] ? 0 : 1);
        const lv = Math.min(target, lastText);
        e.textContent = e._alts[lv]; e.dataset.fitLevel = String(lv);
      });
    });
  }
  function dropPrio(root) {
    root.querySelectorAll('[data-droprow]').forEach(box => {
      const owner = e => (e.hasAttribute('data-droprow') ? e.parentElement : e).closest('[data-droprow]');
      const items = [...box.querySelectorAll('[data-dp]')].filter(e => owner(e) === box);
      items.forEach(e => { e.style.display = ''; });
      const lines = [...box.children].filter(l => l.classList.contains('ln'));
      lines.forEach(l => { l.style.display = ''; });
      const onlyX = box.dataset.droprow === 'x';
      const wide = l => l.scrollWidth > l.clientWidth + 0.5;
      let guard = 0;
      while (guard++ < 20) {
        // Si una línea se sale a lo ancho, cae lo menos importante DE ESA línea; si la
        // caja se sale a lo alto (Dynamic Type), lo menos importante de todas.
        const bad = lines.filter(wide);
        const boxWide = box.scrollWidth > box.clientWidth + 0.5, boxTall = !onlyX && box.scrollHeight > box.clientHeight + 1;
        if (!bad.length && !boxWide && !boxTall) break;
        const pool = (bad.length ? items.filter(e => bad.some(l => l.contains(e))) : items).filter(e => e.style.display !== 'none');
        if (!pool.length) break;
        pool.sort((p, q) => Number(p.dataset.dp) - Number(q.dataset.dp))[0].style.display = 'none';
      }
      lines.forEach(l => { l.style.display = [...l.children].some(c => c.style.display !== 'none') ? '' : 'none'; });
    });
  }
  /** minimumScaleFactor solo en la cifra (≥ 0,7): el texto de fecha del sistema tiene una sola talla. */
  function shrinkAll(root) {
    root.querySelectorAll('[data-shrink]').forEach(box => {
      const n = box.querySelector('.n'); if (!n) return;
      n.style.fontSize = '';
      const base = parseFloat(getComputedStyle(n).fontSize); let f = base;
      while (box.scrollWidth > box.clientWidth + 0.5 && f > base * 0.7) { f -= 1; n.style.fontSize = f + 'px'; }
    });
  }
  function postLayout(root) {
    dropOverflow(root);
    dropVertical(root);
    root.querySelectorAll('.di-compact, .dm-c').forEach(di => {
      const L = di.querySelector('.di-lead'), R = di.querySelector('.di-trail'), cam = di.querySelector('.di-cam');
      if (!L || !R) return;
      const side = parseFloat(L.dataset.side || L.style.width); L.dataset.side = side;
      L.style.width = R.style.width = 'auto';
      const need = Math.max(side, L.offsetWidth, R.offsetWidth);
      L.style.width = R.style.width = need + 'px';
      const grown = need > side + 0.5;
      di.dataset.grown = grown ? '1' : '0';
      if (di.classList.contains('di-compact')) di.style.width = (need * 2 + cam.offsetWidth) + 'px';
      else if (grown) { const dm = di.closest('.dmorph'); dm.style.setProperty('--tot', (need * 2 + cam.offsetWidth) + 'px'); }
    });
    const dm = document.getElementById('dmorph');
    if (dm) { const x = dm.querySelector('.dm-x'); if (x) dm.style.setProperty('--xh', x.offsetHeight + 'px'); }
    // Medidas reales (pt) al lado de cada pieza; en rojo si pasan del límite de iOS (160 pt de alto).
    root.querySelectorAll('[data-measure]').forEach(tag => {
      const el = tag.closest('.ccell, .fig, .lcol').querySelector(tag.dataset.measure);
      if (!el) { tag.textContent = ''; return; }
      const w = el.offsetWidth, h = el.offsetHeight, max = Number(tag.dataset.max || 0);
      tag.textContent = `${Math.round(w)} × ${Math.round(h)} pt`;
      tag.classList.toggle('is-over', !!max && h > max + 0.5);
      if (max && h > max + 0.5) tag.textContent += ` · pasa de ${max}`;
    });
  }
  /** ViewThatFits: la primera variante que cabe; si ninguna, se quita (nunca «…»). */
  function fitAll(root) {
    root.querySelectorAll('.fit[data-fit]').forEach(el => {
      const opts = el.dataset.fit.split('|').filter(Boolean);
      const lines = Number(el.dataset.lines || 1);
      el.classList.remove('fit-none');
      for (const o of opts) {
        el.textContent = o;
        const okW = el.scrollWidth <= el.clientWidth + 0.5;
        const okH = lines > 1 ? el.scrollHeight <= el.clientHeight + 1 : true;
        if (okW && okH) { el.dataset.fitLevel = String(opts.indexOf(o)); return; }
      }
      el.textContent = ''; el.classList.add('fit-none'); el.dataset.fitLevel = 'none';
    });
  }
  /** Cada cuarto de segundo: cifras, antigüedad, medidores y reloj (lo que en iOS se mueve solo). */
  function tick(m = models()) {
    const deps = {};
    m.legs.forEach(l => l.deps.forEach(d => { deps[d.jid] = d; }));
    const root = sheet();
    const roll = e => { if (!m.s.reduceMotion) { e.classList.remove('swap'); void e.offsetWidth; e.classList.add('swap'); } };
    root.querySelectorAll('[data-cd]').forEach(e => {
      const d = deps[e.dataset.cd]; if (!d) return;
      const t = cdText(d.cd, e.dataset.cdf || 'n');
      if (e.textContent !== t) { e.textContent = t; roll(e); }
    });
    root.querySelectorAll('[data-cdu]').forEach(e => { const d = deps[e.dataset.cdu]; if (d && e.textContent !== d.cd.u) e.textContent = d.cd.u; });
    root.querySelectorAll('[data-age]').forEach(e => { const t = ageText(e.dataset.age === 'la' ? m.laAge : m.wAge, e.dataset.agef); if (e.textContent !== t) e.textContent = t; });
    root.querySelectorAll('[data-agefit]').forEach(e => {
      // antigüedad dentro de una frase ajustable: se recalcula la lista y se vuelve a ajustar
      const alts = m.laConn === 'offline' ? ['sin conexión · ' + ageText(m.laAge, 'hace'), 'sin red · ' + ageText(m.laAge, 'corto'), ageText(m.laAge, 'corto')]
        : ['sin actualizar · ' + ageText(m.laAge, 'hace'), 'dato de ' + ageText(m.laAge, 'hace'), ageText(m.laAge, 'corto')];
      const lvl = Number(e.dataset.fitLevel || 0);
      const t = alts[Math.min(lvl, alts.length - 1)] || alts[0];
      if (e.textContent !== t) e.textContent = t;
    });
    root.querySelectorAll('[data-gauge]').forEach(e => {
      const d = deps[e.dataset.gauge]; if (!d) return;
      const p = d.at_stop ? 0 : Math.max(0, Math.min(1, d.cd.secs / 1800));
      e.setAttribute('stroke-dasharray', `${(p * 75).toFixed(2)} 100`);
    });
    // A: la cifra la calcula quien la escribe (numA) y la antigüedad, el sistema por fecha.
    const mods = Object.assign({ m: m.A }, m.AX || {});
    const look = k => { const [ns, ctx, jid] = k.split('|'); const a = mods[ns]; const d = a && a.dep(ctx, jid); return d ? { a, ctx, d } : null; };
    root.querySelectorAll('[data-acd]').forEach(e => {
      const r = look(e.dataset.acd); if (!r) return;
      const t = numTextA(numA(r.d, r.a, r.ctx), e.dataset.acf);
      if (e.textContent !== t) { e.textContent = t; roll(e); }
    });
    root.querySelectorAll('[data-acu]').forEach(e => { const r = look(e.dataset.acu); if (!r) return; const u = numA(r.d, r.a, r.ctx).u; if (e.textContent !== u) e.textContent = u; });
    root.querySelectorAll('[data-aage]').forEach(e => {
      const [ns, which] = e.dataset.aage.split('|'); const a = mods[ns]; if (!a) return;
      const t = ageText(which === 'la' ? a.la.age : a.w.age, 'hace'); if (e.textContent !== t) e.textContent = t;
    });
    root.querySelectorAll('[data-agauge]').forEach(e => {
      const r = look(e.dataset.agauge); if (!r) return;
      e.setAttribute('stroke-dasharray', `${(Math.max(0, Math.min(1, (r.d.atAbs - r.a.now) / 1800)) * 75).toFixed(2)} 100`);
    });
    const hh = fmt.hhmm(m.now), ss = String(Math.floor(m.now) % 60).padStart(2, '0');
    root.querySelectorAll('[data-clock]').forEach(e => { if (e.textContent !== hh) e.textContent = hh; });
    root.querySelectorAll('[data-clock-s]').forEach(e => { if (e.textContent !== ss) e.textContent = ss; });
    const pc = document.querySelector('[data-clock-panel]');
    if (pc) pc.textContent = hh + ':' + ss;
  }
  function applyZoom() {
    const st = document.querySelector('.stage2');
    const z = lab.zoom || (qs.get('capture') ? 1 : Math.min(1, Math.max(0.5, (st ? st.clientWidth : 1400) / (lab.view === 'comparar' || lab.view === 'limites' ? 1520 : lab.view === 'congelada' ? 900 : ((DEVICES[lab.device] || DEVICES.i16).w * 4 + 300)))));
    sheet().style.zoom = z;
  }

  // =================================================================== barra de herramientas y panel
  function toolbar() {
    const t = document.getElementById('tool2');
    t.innerHTML = `
      <div class="tb-title"><b>Trajet · B v2</b><span>Live Activity y widgets · tamaño real en puntos</span></div>
      <div class="tb-grp" role="group" aria-label="Variante">${Object.values(VARIANTS).map(x => `<button class="tb-btn" data-lab="v=${x.id}" title="${esc(x.idea)}"><b>${x.id}</b> ${x.name}${x.id === 'A' ? ' ✓' : ''}</button>`).join('')}<button class="tb-btn" data-lab="view=comparar">Las tres</button><button class="tb-btn" data-lab="view=congelada" title="A: la Live Activity viva frente a la congelada">Viva / congelada</button><button class="tb-btn" data-lab="view=limites" title="A: la isla con las cifras que más ocupan">Casos límite</button></div>
      <div class="tb-grp" role="group" aria-label="Dispositivo">${Object.values(DEVICES).map(d => `<button class="tb-btn" data-lab="device=${d.id}">${d.name.replace('iPhone ', '')}<small>${d.w}</small></button>`).join('')}</div>
      <div class="tb-grp" role="group" aria-label="Isla">${['compact', 'expanded', 'minimal'].map(s => `<button class="tb-btn" data-lab="island=${s}">${{ compact: 'Compacta', expanded: 'Expandida', minimal: 'Mínima' }[s]}</button>`).join('')}<button class="tb-btn" data-demo>▶ Alerta</button></div>
      <p class="tb-idea" id="tb-idea"></p>`;
    t.addEventListener('click', ev => {
      const b = ev.target.closest('[data-lab]');
      if (b) {
        const [k, val] = b.dataset.lab.split('=');
        if (k === 'v') { lab.v = val; lab.view = 'lamina'; } else lab[k] = val;
        saveLab(); render(true);
      }
      if (ev.target.closest('[data-demo]')) alertDemo();
    });
  }
  function updateToolbar() {
    document.querySelectorAll('#tool2 [data-lab]').forEach(b => {
      const [k, val] = b.dataset.lab.split('=');
      const on = k === 'v' ? (lab.view === 'lamina' && lab.v === val) : k === 'view' ? lab.view === val : lab[k] === val;
      b.classList.toggle('is-on', on);
    });
    document.querySelectorAll('[data-scene]').forEach(b => b.classList.toggle('is-on', b.dataset.scene === lab.scene));
    const idea = document.getElementById('tb-idea');
    if (idea) idea.textContent = lab.view === 'comparar' ? 'Las tres variantes, la misma pieza en cada fila (A con las correcciones de la 2B.4; B y C como en la 2B.3).'
      : lab.view === 'limites' ? 'A · la isla con las cifras que más ocupan: la compacta no debe crecer.'
      : lab.view === 'congelada' ? 'A · la misma Live Activity con la app escribiendo y con la app parada: sin la app no cambia de tren ni inventa vías.'
      : `${lab.v} · ${VARIANTS[lab.v].name}: ${VARIANTS[lab.v].idea}${lab.v === 'A' ? ' (elegida, 2B.4)' : ' (descartada, se queda como en la 2B.3)'}`;
  }
  function panel() {
    const side = document.getElementById('side2');
    const extra = ({ btn, tog, s }) => `
      <section class="lp-sec">
        <h4>Escena (un toque)</h4>
        <div class="lp-grid">${SCENES.map(([id, label]) => `<button class="lp-btn" data-scene="${id}">${label}</button>`).join('')}</div>
      </section>
      <section class="lp-sec">
        <h4>Trayecto y Live Activity</h4>
        ${tog('transfer', 'Ruta con transbordo (14 → J)', s.transfer)}
        <div class="lp-row lp-sub"><span>Tramo actual</span>${btn('legNow', 0, '1.º', s.legNow)}${btn('legNow', 1, '2.º', s.legNow)}</div>
        ${tog('frozen', 'La app no actualiza (staleDate)', s.frozen)}
        ${tog('tripEnded', 'Trayecto terminado', s.tripEnded)}
      </section>
      <section class="lp-sec">
        <h4>Cifra (A)</h4>
        <div class="lp-row lp-sub">${btn('numMode', 'app', 'La escribe la app', s.numMode || 'app')}${btn('numMode', 'sys', 'Sistema · 1 talla', s.numMode)}${btn('numMode', 'ios17', 'iOS 17 · segundos', s.numMode)}</div>
      </section>
      <section class="lp-sec">
        <h4>Aspecto de iOS</h4>
        <div class="lp-row lp-sub"><span>Inicio</span>${btn('widgetTint', 'full', 'Color', s.widgetTint)}${btn('widgetTint', 'tinted', 'Tintado', s.widgetTint)}${btn('widgetTint', 'clear', 'Transparente', s.widgetTint)}</div>
        <div class="lp-row lp-sub"><span>Acentuado (A)</span>${btn('accentMode', 'calado', 'Calado', s.accentMode || 'calado')}${btn('accentMode', 'contorno', 'Contorno', s.accentMode)}</div>
        <div class="lp-row lp-sub"><span>Texto</span>${btn('dtA', 'L', 'Grande (def.)', s.dtA || 'L')}${btn('dtA', 'XL', 'xLarge', s.dtA)}${btn('dtA', 'AX3', 'AX3 (con topes)', s.dtA)}</div>
        ${tog('reduceTransparency', 'Reducir transparencia', s.reduceTransparency)}
        ${tog('hc', 'Aumentar contraste', s.hc)}
        ${tog('aod', 'Pantalla siempre activa (Always-On)', s.aod)}
        ${tog('standby', 'StandBy de noche (rojo)', s.standby)}
        ${tog('showHits', 'Ver enlaces y áreas táctiles (A)', s.showHits)}
      </section>`;
    T.gallery.mountPanelWith(side, { screens: false, sizes: false, links: 'min', extra, title: 'Escenarios · LA y widgets' });
    side.addEventListener('click', ev => {
      const b = ev.target.closest('[data-scene]');
      if (b) { applyScene(b.dataset.scene); render(true); updateToolbar(); }
      else if (ev.target.closest('[data-set], [data-reveal]')) { lab.scene = null; updateToolbar(); }   // un ajuste suelto ya no es la escena
    });
  }
  /** Vía que aparece: alerta → la isla se abre (expandida) ~4 s y vuelve a la compacta. */
  function alertDemo() {
    if (lab.view !== 'lamina') { lab.view = 'lamina'; saveLab(); }
    lab.island = 'compact'; render(true);
    setTimeout(() => { scenarios.revealPlatform(); }, 250);
    setTimeout(() => setIsland('expanded'), 800);
    setTimeout(() => setIsland('compact'), 4800);
  }
  function setIsland(st) {
    lab.island = st; saveLab();
    const dm = document.getElementById('dmorph');
    if (dm && dm.dataset.state !== 'gone') { ['compact', 'expanded', 'minimal'].forEach(x => dm.classList.remove('st-' + x)); dm.classList.add('st-' + st); dm.dataset.state = st; }
    updateToolbar();
  }

  // =================================================================== arranque
  /** Aspectos y cifra por URL o por lab.set (capturas deterministas). */
  function aspectPatch(o, get) {
    const p = {};
    const has = k => get(k) !== undefined && get(k) !== null;
    if (has('num')) p.numMode = get('num');
    if (has('aod')) p.aod = String(get('aod')) === '1' || get('aod') === true;
    if (has('sb')) p.standby = String(get('sb')) === '1' || get('sb') === true;
    if (has('hc')) p.hc = String(get('hc')) === '1' || get('hc') === true;
    if (has('dt')) p.dtA = get('dt');
    if (has('acc')) p.accentMode = get('acc');
    if (has('hits')) p.showHits = String(get('hits')) === '1' || get('hits') === true;
    return p;
  }
  function boot() {
    // Parámetros de la URL (capturas deterministas).
    if (qs.get('v')) lab.v = qs.get('v').toUpperCase();
    if (qs.get('view')) lab.view = qs.get('view');
    if (qs.get('device')) lab.device = qs.get('device');
    if (qs.get('island')) lab.island = qs.get('island');
    if (qs.get('zoom')) lab.zoom = Number(qs.get('zoom'));
    if (qs.get('fz')) lab.fz = qs.get('fz');
    if (qs.get('t')) setClock(qs.get('t'));
    const patch = aspectPatch(qs, k => qs.get(k));
    if (qs.get('theme')) patch.theme = qs.get('theme');
    if (qs.get('tint')) patch.widgetTint = qs.get('tint');
    if (qs.get('rt')) patch.reduceTransparency = qs.get('rt') === '1';
    if (qs.get('rm')) patch.reduceMotion = qs.get('rm') === '1';
    if (qs.get('speed')) patch.speed = Number(qs.get('speed'));
    if (qs.get('scene')) applyScene(qs.get('scene'));
    if (Object.keys(patch).length) scenarios.set(patch);
    if (qs.get('capture')) document.body.classList.add('is-capture');
    toolbar(); panel();
    render(true);
    scenarios.subscribe(() => render(true));
    setInterval(() => render(false), 250);
    window.addEventListener('resize', applyZoom);
    document.addEventListener('click', ev => {
      const dm = ev.target.closest('#dmorph');
      if (dm) { const order = ['compact', 'expanded', 'minimal']; setIsland(order[(order.indexOf(dm.dataset.state) + 1) % 3]); }
    });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { lastMasked = ''; render(true); });
  }

  // API para las capturas (capturar.mjs → «eval»).
  window.lab = {
    set(o = {}) {
      if (o.v) { lab.v = o.v; lab.view = 'lamina'; }
      if (o.view) lab.view = o.view;
      if (o.device) lab.device = o.device;
      if (o.island) lab.island = o.island;
      if (o.fz) lab.fz = o.fz;
      const p = aspectPatch(o, k => o[k]);
      if (o.theme) p.theme = o.theme;
      if (o.tint) p.widgetTint = o.tint;
      if ('rt' in o) p.reduceTransparency = !!o.rt;
      if ('rm' in o) p.reduceMotion = !!o.rm;
      if ('speed' in o) p.speed = o.speed;
      if (o.t) setClock(o.t);
      if (o.scene) applyScene(o.scene);
      if (o.patch) Object.assign(p, o.patch);
      if (Object.keys(p).length) scenarios.set(p);
      saveLab(); render(true);
      return true;
    },
    island: setIsland, alertDemo, abreviar, model, modelA, scenes: SCENES.map(s => s[0]),
    /** Auditoría de recortes: piezas .fitr/.fit que se han quedado en «nada» y cajas desbordadas. */
    audit() {
      const out = [];
      sheet().querySelectorAll('.fitr.is-gone, .fit.fit-none').forEach(e => {
        const piece = e.closest('[id^="p-"], .di, .pc'); out.push({ kind: 'sin texto', piece: piece ? (piece.id || piece.className) : '', alts: e.dataset.alts || e.dataset.fit });
      });
      sheet().querySelectorAll('.A-la, .wd, .lw, .di-expanded, .A-tk, .A-wtk, [data-fitrow], [data-droprow]').forEach(e => {
        if (e.offsetParent && (e.scrollWidth > e.clientWidth + 1 || e.scrollHeight > e.clientHeight + 1) && getComputedStyle(e).overflow !== 'visible')
          out.push({ kind: 'desborda', cls: e.className.slice(0, 60), w: [e.clientWidth, e.scrollWidth], h: [e.clientHeight, e.scrollHeight] });
      });
      return out;
    }
  };
  window.TrajetLA = { abreviar, countdown, secsUntil };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
