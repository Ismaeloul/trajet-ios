/* Núcleo compartido del laboratorio de diseño de Trajet.
   Aquí vive todo lo que NO es diseño: formato («1h46», «hace 4 min»),
   escenarios, reloj simulado, construcción del tablero a partir de los
   datos, enrutado entre pantallas, el marco de iPhone y el panel de
   escenarios. Cada dirección solo pinta. */
window.Trajet = (() => {
  'use strict';

  const D = window.TrajetData;
  const qs = new URLSearchParams(location.search);
  // frame: iPhone con marco + panel (escritorio) · full: pantalla real del móvil · embed: dentro de la galería
  const MODE = qs.get('full') ? 'full' : (qs.get('embed') ? 'embed' : 'frame');

  // ------------------------------------------------------------ formato
  const fmt = {
    /** Minutos como se leen: 6 · 51 · 1h46. A partir de una hora, en horas. */
    minutes(m) {
      m = Math.max(0, Math.round(m));
      if (m >= 60) {
        const h = Math.floor(m / 60), r = m % 60;
        return r === 0 ? `${h}h` : `${h}h${String(r).padStart(2, '0')}`;
      }
      return String(m);
    },
    minutesUnit(m) { return m >= 60 ? '' : 'min'; },
    /** Retraso con signo; un +0 no se enseña nunca (el que llama lo filtra). */
    delay(d) { return d > 0 ? `+${d} min` : `${d} min`; },
    /** Antigüedad del dato, como se dice en voz alta. */
    age(seconds) {
      const s = Math.max(0, Math.round(seconds));
      if (s < 60) return `hace ${s} s`;
      const m = Math.floor(s / 60);
      if (m < 60) return `hace ${m} min`;
      return `hace ${Math.floor(m / 60)} h`;
    },
    hhmm(sec) {
      sec = ((sec % 86400) + 86400) % 86400;
      return `${String(Math.floor(sec / 3600)).padStart(2, '0')}:${String(Math.floor(sec / 60) % 60).padStart(2, '0')}`;
    },
    mmss(sec) {
      sec = Math.max(0, Math.round(sec));
      return `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`;
    },
    quota(n) { return `${n} llamadas hoy`; },
    monthLabel(ym) {
      const [y, m] = ym.split('-').map(Number);
      return ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'][m - 1] + ' ' + y;
    },
    daysLabel(days) {
      const n = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      if (days.length === 5 && days.every((d, i) => d === i)) return 'Lunes a viernes';
      if (days.length === 7) return 'Todos los días';
      return days.map(d => n[d]).join(' ');
    },
    scheduleLabel(r) {
      if (r.time_mode === 'arrival') return `llegar a las ${r.time_at}`;
      if (r.time_mode === 'departure') return `salir a las ${r.time_at}`;
      return `${r.time_from} – ${r.time_to}`;
    },
    transfers(n) { return n === 0 ? 'directo' : n === 1 ? '1 transbordo' : `${n} transbordos`; },
    percent(x) { return x == null ? '—' : `${Math.round(x * 100)} %`; }
  };

  // ------------------------------------------------------------ colores de línea
  function hexRGB(hex) {
    let s = (hex || '').trim().replace('#', '');
    if (s.length === 3) s = s.split('').map(c => c + c).join('');
    if (s.length !== 6) return null;
    const v = parseInt(s, 16);
    return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  }
  function luminance([r, g, b]) {
    const ch = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
  }
  const line = {
    fallback: '#6b7380',
    color(hex) { return hexRGB(hex) ? '#' + hex.replace('#', '') : line.fallback; },
    /** Negro o blanco encima del color de línea, según el contraste real (umbral 0,45 como en LineColor.swift). */
    ink(hex) { const c = hexRGB(hex); return c && luminance(c) > 0.45 ? '#000000' : '#ffffff'; },
    isLight(hex) { const c = hexRGB(hex); return !!c && luminance(c) > 0.45; },
    rgba(hex, a) { const c = hexRGB(hex) || [107, 115, 128]; return `rgba(${c[0]},${c[1]},${c[2]},${a})`; },
    /** Metro, bus y tranvía no publican vía jamás. */
    publishesPlatform(mode) { return /rer|transilien|ter|train/i.test(mode || ''); },
    modeKind(mode) {
      const m = (mode || '').toLowerCase();
      if (m.includes('tro')) return 'metro';
      if (m.includes('rer')) return 'rer';
      if (m.includes('tram')) return 'tram';
      if (m.includes('bus')) return 'bus';
      if (m.includes('train') || m.includes('transilien')) return 'train';
      return 'other';
    },
    modeLabel(mode) {
      return { metro: 'Metro', rer: 'RER', tram: 'Tranvía', bus: 'Bus', train: 'Tren', other: 'Línea' }[line.modeKind(mode)];
    }
  };

  /** ¿Corro o no corro? (Format.swift · Pace) */
  function pace(minutes) {
    if (minutes <= 3) return { id: 'run', label: 'corriendo', short: 'Corre' };
    if (minutes <= 8) return { id: 'walk', label: 'andando', short: 'Anda' };
    return { id: 'easy', label: 'con calma', short: 'Con calma' };
  }

  // ------------------------------------------------------------ escenarios
  const DEFAULTS = {
    platform: 'real',      // real | guess | none
    busLong: false,        // bus a 1h46
    cut: false,            // línea 14 cortada
    notice: 'none',        // none | translating | translated
    offline: false,        // sin conexión: tablero antiguo
    atStop: false,         // tren parado en el andén
    emptyLeg: false,       // tramo vacío
    theme: 'dark',         // dark | light
    reduceMotion: false,
    largeText: false,
    speed: 1,              // velocidad del reloj simulado
    trip: false,           // modo trayecto activo
    platformNewAt: null,   // segundos de reloj en que apareció la vía (para el latido)
    offlineSince: null     // segundos de reloj en que se perdió la conexión
  };
  const KEY = 'trajet-lab.scenarios';
  let state = Object.assign({}, DEFAULTS, readJSON(KEY) || {});
  const listeners = new Set();
  const channel = ('BroadcastChannel' in window) ? new BroadcastChannel('trajet-lab') : null;

  function readJSON(k) { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } }
  function writeJSON(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* modo privado */ } }

  const scenarios = {
    get() { return state; },
    set(patch, { silent = false } = {}) {
      const prev = state;
      state = Object.assign({}, state, patch);
      // Derivados que dependen del reloj.
      if (patch.offline === true && !prev.offline) state.offlineSince = clock.now();
      if (patch.offline === false) state.offlineSince = null;
      if (patch.platform === 'real' && prev.platform !== 'real') state.platformNewAt = clock.now();
      if (patch.platform && patch.platform !== 'real') state.platformNewAt = null;
      if ('speed' in patch) clock.setSpeed(state.speed);
      writeJSON(KEY, state);
      applyDocumentFlags();
      if (!silent) channel && channel.postMessage({ type: 'scenario', state });
      listeners.forEach(fn => fn(state, prev));
    },
    reset() { scenarios.set(Object.assign({}, DEFAULTS)); },
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    /** Escenario compuesto: la vía aparece ahora mismo, con su latido. */
    revealPlatform() { scenarios.set({ platform: 'none' }); setTimeout(() => scenarios.set({ platform: 'real' }), 350); }
  };

  channel && channel.addEventListener('message', ev => {
    const m = ev.data || {};
    if (m.type === 'scenario') { const prev = state; state = m.state; clock.setSpeed(state.speed); applyDocumentFlags(); listeners.forEach(fn => fn(state, prev)); }
    if (m.type === 'navigate' && app.current !== null) app.navigate(m.screen, { replace: true });
    if (m.type === 'clock') clock.load();
  });

  function applyDocumentFlags() {
    const h = document.documentElement;
    h.dataset.theme = state.theme;
    h.dataset.reduceMotion = state.reduceMotion ? '1' : '0';
    h.dataset.largeText = state.largeText ? '1' : '0';
    h.dataset.mode = MODE;
    h.style.colorScheme = state.theme;
  }

  // ------------------------------------------------------------ reloj simulado
  // Arranca a las 12:50:00 (la hora de los datos) y corre con el tiempo real
  // multiplicado por `speed`. Compartido entre pestañas por localStorage.
  const CLOCK_KEY = 'trajet-lab.clock';
  const clock = {
    base: 12 * 3600 + 50 * 60, epoch: Date.now(), speed: 1,
    load() {
      const c = readJSON(CLOCK_KEY);
      if (c && typeof c.base === 'number') Object.assign(clock, c);
      clock.speed = state.speed || 1;
    },
    save() { writeJSON(CLOCK_KEY, { base: clock.base, epoch: clock.epoch }); },
    now() { return clock.base + (Date.now() - clock.epoch) / 1000 * clock.speed; },
    setSpeed(s) { const n = clock.now(); clock.base = n; clock.epoch = Date.now(); clock.speed = s || 1; clock.save(); },
    reset() { clock.base = 12 * 3600 + 50 * 60; clock.epoch = Date.now(); clock.save(); channel && channel.postMessage({ type: 'clock' }); }
  };
  clock.load();

  // ------------------------------------------------------------ tablero
  const toSec = hhmm => { const [h, m] = hhmm.split(':').map(Number); return h * 3600 + m * 60; };
  const INTERVAL = { J: 15 * 60, '14': 3 * 60, '6424': 59 * 60 };
  const GRACE = 45;           // segundos que un «ya» sigue en pantalla
  const NEW_PLATFORM_FOR = 25; // segundos que dura el latido de la vía nueva

  /** Construye el tablero que toca según los escenarios y el reloj.
      Devuelve la forma de la API; los campos derivados van con «_». */
  function buildBoard(s = state) {
    const now = s.offline && s.offlineSince != null ? s.offlineSince : clock.now();
    const src = JSON.parse(JSON.stringify(D.calmBoard));
    if (s.busLong) src.legs.push(JSON.parse(JSON.stringify(D.busLeg)));

    src.legs.forEach(leg => {
      const interval = INTERVAL[leg.line_code] || 600;
      const tpl = leg.departures;
      const firstBase = toSec(tpl[0].at);
      let k = 0;
      while (firstBase + k * interval + GRACE < now) k++;
      leg.departures = tpl.map((t, i) => {
        const d = Object.assign({}, t);
        const at = firstBase + k * interval + i * interval;
        d.at = fmt.hhmm(at);
        if (d.aimed_at) d.aimed_at = fmt.hhmm(at - (d.delay || 0) * 60);
        if (d.train) d.train = String(Number(t.train) + k * 4);
        d._seconds = at - now;
        d.minutes = Math.max(0, Math.ceil(d._seconds / 60));
        d._isNew = false;
        return d;
      });

      if (leg.line_code === 'J') {
        const [a, b] = leg.departures;
        if (s.platform === 'none') {
          a.platform = null; a.platform_new = false; delete a.guess;
          b.platform = null; delete b.guess;
        } else if (s.platform === 'guess') {
          a.platform = null; a.platform_new = false;
          a.guess = { platform: '21', share: 0.9, samples: 20, basis: 'mision', why: 'por el número de tren' };
        } else {
          a.platform = '21';
          const since = s.platformNewAt != null ? now - s.platformNewAt : 999;
          a.platform_new = since >= 0 && since < NEW_PLATFORM_FOR;
          a._isNew = a.platform_new;
          if (s.platformNewAt == null) a.platform_new = false;
        }
        if (s.atStop) { a.at_stop = true; a.minutes = 0; a._seconds = 0; a.status = 'onTime'; a.delay = 0; }
        if (s.notice !== 'none') {
          leg.status = { level: 1, label: 'perturbada', messages: [D.notices.slow.fr],
            messages_es: [s.notice === 'translated' ? D.notices.slow.es : null],
            translating: s.notice === 'translating', planned: 0 };
        }
      }
      if (leg.line_code === '14') {
        if (s.cut) {
          leg.status = { level: 2, label: 'interrumpida', messages: [D.notices.cut14.fr],
            messages_es: [s.notice === 'translating' ? null : D.notices.cut14.es],
            translating: s.notice === 'translating', planned: 0 };
          leg.departures = [];
        }
        if (s.emptyLeg) leg.departures = [];
      }
      // Antigüedad por tramo: la del dato más el tiempo pasado.
      leg.age = (leg.age || 0) + (clock.now() - now);
    });

    src.worst_level = Math.max(0, ...src.legs.map(l => l.status.level));
    src.worst_line = (src.legs.find(l => l.status.level === src.worst_level && src.worst_level > 0) || {}).line_code || '';
    src.max_delay = Math.max(0, ...src.legs.flatMap(l => l.departures.map(d => d.delay || 0)));
    src.stale = !!s.offline;
    // La antigüedad que se enseña: 6 s de base; sin conexión, 4 min y subiendo.
    src.data_age = s.offline ? 240 + (clock.now() - now) : 6 + (clock.now() % 30);
    src.last_error = s.offline ? 'sin conexión con el servidor' : null;
    src._now = clock.now();
    src._signature = src.legs.map(l => l.line_code + ':' + l.departures.map(d => d.at).join(',') + ':' + l.status.level + ':' + (l.departures[0] || {}).platform).join('|')
      + '|' + s.notice + s.emptyLeg + s.busLong + s.atStop + s.platform + s.offline;
    return src;
  }

  /** «En andén» y «ya» son cosas distintas (Format.swift · DepartureMoment). */
  function moment(dep) {
    if (dep.at_stop) return { kind: 'atStop', text: 'En andén', unit: '', word: true, pace: null };
    if (dep.minutes <= 0) return { kind: 'now', text: 'ya', unit: '', word: true, pace: pace(0) };
    return { kind: 'min', text: fmt.minutes(dep.minutes), unit: fmt.minutesUnit(dep.minutes), word: false, pace: pace(dep.minutes) };
  }

  /** Mensajes visibles de un tramo: el español si ya está, si no el francés. */
  function visibleMessages(status) {
    return (status.messages || []).map((fr, i) => {
      const es = (status.messages_es || [])[i];
      return { text: es || fr, translated: !!es, fr };
    });
  }
  function awaitingTranslation(status) {
    return !!status.translating || (status.messages || []).some((_, i) => !(status.messages_es || [])[i]);
  }

  /** La próxima salida del primer tramo: lo que va a la Live Activity y los widgets. */
  function headline(board) {
    const leg = board.legs[0];
    const dep = leg && leg.departures[0];
    return { leg, dep, moment: dep ? moment(dep) : null };
  }

  // ------------------------------------------------------------ utilidades DOM
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const html = (strings, ...vals) => strings.reduce((acc, s, i) => acc + s + (i < vals.length ? (Array.isArray(vals[i]) ? vals[i].join('') : vals[i]) : ''), '');
  const el = (tag, cls, inner) => { const e = document.createElement(tag); if (cls) e.className = cls; if (inner != null) e.innerHTML = inner; return e; };

  // ------------------------------------------------------------ la app (router + ciclo de vida)
  const app = {
    def: null, root: null, current: null, stack: [], _els: {}, _sig: '', _tickTimer: null,

    /** Cada dirección se registra con sus pantallas. */
    register(def) {
      app.def = def;
      document.addEventListener('DOMContentLoaded', () => app.boot());
      if (document.readyState !== 'loading') app.boot();
    },

    boot() {
      applyDocumentFlags();
      buildChrome();
      app.root = document.getElementById('screens');
      if (app.def.tabbar) {
        const tb = el('nav', 'tabbar', app.def.tabbar(app.ctx()));
        document.getElementById('app').appendChild(tb);
        app.tabbarEl = tb;
      }
      const first = (location.hash || '').replace('#', '') || qs.get('screen') || app.def.home || 'board';
      app.navigate(app.def.screens[first] ? first : 'board', { replace: true, instant: true });
      window.addEventListener('hashchange', () => {
        const id = (location.hash || '').replace('#', '');
        if (id && id !== app.current && app.def.screens[id]) app.navigate(id, { replace: true });
      });
      scenarios.subscribe(() => app.refresh());
      app._tickTimer = setInterval(() => app.tick(), 1000);
      document.addEventListener('click', ev => {
        const a = ev.target.closest('[data-go]');
        if (a) { ev.preventDefault(); app.navigate(a.dataset.go, { back: a.hasAttribute('data-back'), sheet: a.hasAttribute('data-sheet') }); }
        const s = ev.target.closest('[data-scenario]');
        if (s) { const [k, v] = s.dataset.scenario.split('='); scenarios.set({ [k]: parseVal(v) }); }
      });
    },

    ctx() {
      const board = buildBoard();
      return { board, s: state, now: clock.now(), data: D, fmt, line, pace, moment, headline, visibleMessages, awaitingTranslation, html, esc, mode: MODE, app };
    },

    navigate(id, { back = false, replace = false, instant = false, sheet = false } = {}) {
      const scr = app.def.screens[id];
      if (!scr) return;
      const prevId = app.current;
      if (prevId === id) return;
      const ctx = app.ctx();
      const old = app._els[prevId];
      const node = el('section', 'screen', scr.render(ctx));
      node.dataset.screen = id;
      if (scr.hidesStatus) node.dataset.hidesStatus = '1';
      app.root.appendChild(node);
      app._els[id] = node;
      app.current = id;
      app._sig = ctx.board._signature;
      document.body.dataset.screen = id;
      if (app.tabbarEl) app.tabbarEl.querySelectorAll('[data-go]').forEach(b => b.classList.toggle('is-active', b.dataset.go === id || (b.dataset.goGroup || '').split(' ').includes(id)));
      if (app.def.onNavigate) app.def.onNavigate(id, prevId, ctx);
      if (!replace) history.replaceState(null, '', '#' + id); else history.replaceState(null, '', '#' + id);
      scr.mount && scr.mount(node, ctx);
      app.tick(node, ctx);
      const kind = sheet ? 'sheet' : back ? 'back' : 'push';
      if (instant || !old || state.reduceMotion) {
        if (old) app._remove(prevId, old);
        node.classList.add('is-current');
        return;
      }
      node.classList.add('is-entering', 'enter-' + kind);
      old.classList.add('is-leaving', 'leave-' + kind);
      old.classList.remove('is-current');
      const dur = 520;
      setTimeout(() => {
        node.classList.remove('is-entering', 'enter-' + kind);
        node.classList.add('is-current');
        app._remove(prevId, old);
      }, dur);
    },

    _remove(id, node) {
      const scr = app.def.screens[id];
      scr && scr.unmount && scr.unmount(node);
      node.remove();
      if (app._els[id] === node) delete app._els[id];
    },

    back() { history.length > 1 ? app.navigate(app.def.home || 'board', { back: true }) : null; },

    /** Vuelve a pintar la pantalla actual (cambio de escenario) sin transición. */
    refresh() {
      const id = app.current; if (!id) return;
      const scr = app.def.screens[id];
      const ctx = app.ctx();
      const node = app._els[id];
      if (scr.update) { scr.update(node, ctx); app._sig = ctx.board._signature; app.tick(node, ctx); return; }
      scr.unmount && scr.unmount(node);
      node.innerHTML = scr.render(ctx);
      scr.mount && scr.mount(node, ctx);
      app._sig = ctx.board._signature;
      app.tick(node, ctx);
    },

    /** Cada segundo: minutos, cuentas atrás, antigüedad, reloj. */
    tick(node = app._els[app.current], ctx = app.ctx()) {
      if (!node) return;
      // Si una salida ha pasado (o ha cambiado el orden), se repinta entero.
      if (ctx.board._signature !== app._sig) { app.refresh(); return; }
      const deps = {};
      ctx.board.legs.forEach(l => l.departures.forEach(d => { deps[d.jid] = d; }));
      node.querySelectorAll('[data-dep-min]').forEach(e => {
        const d = deps[e.dataset.depMin]; if (!d) return;
        const m = moment(d);
        if (e.textContent !== m.text) app.swapText(e, m.text, m.word);
        e.dataset.word = m.word ? '1' : '0';
      });
      node.querySelectorAll('[data-dep-unit]').forEach(e => {
        const d = deps[e.dataset.depUnit]; if (!d) return;
        const m = moment(d); if (e.textContent !== m.unit) e.textContent = m.unit;
      });
      node.querySelectorAll('[data-dep-at]').forEach(e => { const d = deps[e.dataset.depAt]; if (d && e.textContent !== d.at) e.textContent = d.at; });
      node.querySelectorAll('[data-pace]').forEach(e => {
        const d = deps[e.dataset.pace]; if (!d) return;
        const m = moment(d); const p = m.pace ? m.pace.id : 'none';
        if (e.dataset.value !== p) { e.dataset.value = p; if (e.dataset.paceLabel != null) e.textContent = m.pace ? m.pace[e.dataset.paceLabel] : ''; }
      });
      node.querySelectorAll('[data-countdown]').forEach(e => {
        const d = deps[e.dataset.countdown]; if (!d) return;
        const t = fmt.mmss(d._seconds); if (e.textContent !== t) e.textContent = t;
      });
      node.querySelectorAll('[data-progress]').forEach(e => {
        const d = deps[e.dataset.progress]; if (!d) return;
        const total = Number(e.dataset.total || 900);
        e.style.setProperty('--p', Math.max(0, Math.min(1, 1 - d._seconds / total)).toFixed(3));
      });
      node.querySelectorAll('[data-age]').forEach(e => { const t = fmt.age(ctx.board.data_age); if (e.textContent !== t) e.textContent = t; });
      node.querySelectorAll('[data-clock]').forEach(e => { const t = fmt.hhmm(ctx.now); if (e.textContent !== t) e.textContent = t; });
      node.querySelectorAll('[data-clock-sec]').forEach(e => { const t = fmt.hhmm(ctx.now) + ':' + String(Math.floor(ctx.now) % 60).padStart(2, '0'); if (e.textContent !== t) e.textContent = t; });
      document.querySelectorAll('.statusbar [data-clock]').forEach(e => { e.textContent = fmt.hhmm(ctx.now); });
      const scr = app.def.screens[app.current];
      scr && scr.tick && scr.tick(node, ctx);
    },

    /** Cambio de cifra con animación; la dirección puede sustituirlo. */
    swapText(e, text, word) {
      if (app.def.swapText) return app.def.swapText(e, text, word);
      e.classList.remove('num-swap'); void e.offsetWidth;
      e.textContent = text; e.classList.add('num-swap');
      e.addEventListener('animationend', () => e.classList.remove('num-swap'), { once: true });
    }
  };

  function parseVal(v) { if (v === 'true') return true; if (v === 'false') return false; if (v === 'null') return null; if (!isNaN(v) && v !== '') return Number(v); return v; }

  // ------------------------------------------------------------ marco, barra de estado, panel
  const SIZES = { '390': [390, 844], '430': [430, 932], '375': [375, 667] };
  const SCREENS = [
    ['pair', 'Emparejar'], ['board', 'Tablero'], ['map', 'Mapa / trayecto'], ['alternatives', 'Alternativas'],
    ['routes', 'Rutas'], ['route-edit', 'Editor de ruta'], ['plan', 'Planificador'], ['stats', 'Estadísticas'],
    ['settings', 'Ajustes'], ['live', 'Live Activity'], ['widgets', 'Widgets'], ['panel', 'Panel del servidor']
  ];

  function buildChrome() {
    const body = document.body;
    body.classList.add('mode-' + MODE);
    const appEl = el('div', 'app'); appEl.id = 'app';
    if (MODE !== 'full') {
      appEl.appendChild(el('div', 'statusbar', `<span class="sb-time" data-clock>12:50</span><span class="di" aria-hidden="true"></span><span class="sb-right"><i class="sb-signal"></i><i class="sb-wifi"></i><i class="sb-batt"></i></span>`));
    }
    const screens = el('div', 'screens'); screens.id = 'screens';
    appEl.appendChild(screens);

    if (MODE === 'frame') {
      const lab = el('div', 'lab');
      const stage = el('div', 'lab-stage');
      const phone = el('div', 'iphone'); phone.id = 'iphone';
      const size = readJSON('trajet-lab.size') || '390';
      setPhoneSize(phone, size);
      phone.appendChild(appEl);
      stage.appendChild(phone);
      lab.appendChild(stage);
      lab.appendChild(buildPanel({ size }));
      body.appendChild(lab);
      const fit = () => { const h = parseInt(getComputedStyle(phone).getPropertyValue('--ph')) + 24; phone.style.setProperty('--zoom', Math.min(1, (window.innerHeight - 56) / h).toFixed(3)); };
      fit(); window.addEventListener('resize', fit); phone._fit = fit;
    } else if (MODE === 'full') {
      body.appendChild(appEl);
      const fab = el('button', 'lab-fab', '<span></span>');
      fab.title = 'Escenarios';
      fab.addEventListener('click', () => document.body.classList.toggle('panel-open'));
      body.appendChild(fab);
      const overlay = el('div', 'lab-overlay');
      overlay.addEventListener('click', ev => { if (ev.target === overlay) document.body.classList.remove('panel-open'); });
      overlay.appendChild(buildPanel({ full: true }));
      body.appendChild(overlay);
    } else {
      body.appendChild(appEl);
    }
  }

  function setPhoneSize(phone, size) {
    const [w, h] = SIZES[size] || SIZES['390'];
    phone.style.setProperty('--pw', w + 'px'); phone.style.setProperty('--ph', h + 'px');
    phone.dataset.size = size;
    writeJSON('trajet-lab.size', size);
    phone._fit && phone._fit();
  }

  /** El panel de escenarios. Mismo panel en las cinco direcciones y en la galería. */
  function buildPanel({ size = '390', full = false, gallery = false } = {}) {
    const p = el('aside', 'lab-panel');
    const s = state;
    const btn = (k, v, label, cur) => `<button class="lp-btn${cur === v ? ' is-on' : ''}" data-set="${k}" data-val="${v}">${label}</button>`;
    const tog = (k, label, cur) => `<button class="lp-tog${cur ? ' is-on' : ''}" data-set="${k}" data-val="${!cur}"><span class="lp-sw"></span>${label}</button>`;
    p.innerHTML = `
      <header class="lp-head">
        <strong>${gallery ? 'Escenarios (las 5 a la vez)' : 'Escenarios'}</strong>
        ${full ? '<button class="lp-close" data-close>Cerrar</button>' : ''}
      </header>
      <section class="lp-sec">
        <h4>Pantalla</h4>
        <div class="lp-grid lp-screens">${SCREENS.map(([id, label]) => `<button class="lp-btn" data-nav="${id}">${label}</button>`).join('')}</div>
      </section>
      <section class="lp-sec">
        <h4>Vía</h4>
        <div class="lp-row">${btn('platform', 'real', 'Real', s.platform)}${btn('platform', 'guess', 'Probable', s.platform)}${btn('platform', 'none', 'Sin vía', s.platform)}</div>
        <button class="lp-btn lp-wide" data-reveal>⚡ Que aparezca la vía ahora</button>
      </section>
      <section class="lp-sec">
        <h4>Casos difíciles</h4>
        ${tog('busLong', 'Bus a 1h46', s.busLong)}
        ${tog('cut', 'Línea 14 cortada', s.cut)}
        <div class="lp-row lp-sub"><span>Aviso</span>${btn('notice', 'none', 'Ninguno', s.notice)}${btn('notice', 'translating', 'Traduciendo', s.notice)}${btn('notice', 'translated', 'Traducido', s.notice)}</div>
        ${tog('offline', 'Sin conexión (tablero antiguo)', s.offline)}
        ${tog('atStop', 'Tren parado en el andén', s.atStop)}
        ${tog('emptyLeg', 'Tramo vacío (la 14)', s.emptyLeg)}
        ${tog('trip', 'Modo trayecto activo', s.trip)}
      </section>
      <section class="lp-sec">
        <h4>Sistema</h4>
        <div class="lp-row">${btn('theme', 'light', '☀ Claro', s.theme)}${btn('theme', 'dark', '☾ Oscuro', s.theme)}</div>
        ${tog('reduceMotion', 'Reducir movimiento', s.reduceMotion)}
        ${tog('largeText', 'Letra grande (Dynamic Type)', s.largeText)}
      </section>
      <section class="lp-sec">
        <h4>Reloj <span class="lp-clock" data-clock-panel>12:50:00</span></h4>
        <div class="lp-row">${btn('speed', 1, '×1', s.speed)}${btn('speed', 10, '×10', s.speed)}${btn('speed', 60, '×60', s.speed)}<button class="lp-btn" data-reset-clock>Reiniciar</button></div>
      </section>
      ${!full && !gallery ? `
      <section class="lp-sec">
        <h4>Tamaño</h4>
        <div class="lp-row">${['390', '430', '375'].map(k => `<button class="lp-btn${size === k ? ' is-on' : ''}" data-size="${k}">${SIZES[k].join('×')}</button>`).join('')}</div>
      </section>` : ''}
      <section class="lp-sec lp-links">
        ${!full ? `<a class="lp-btn lp-wide" href="?full=1#${gallery ? 'board' : (app.current || 'board')}" target="_blank" data-full-link>📱 Abrir a pantalla completa (móvil)</a>` : ''}
        <a class="lp-btn lp-wide" href="?full=1#panel" data-desktop-panel>🖥 Panel del servidor en escritorio (1440×900)</a>
        <button class="lp-btn lp-wide" data-reset-all>Restablecer escenarios</button>
        ${gallery ? '' : '<a class="lp-btn lp-wide" href="../index.html">← Galería</a>'}
      </section>`;

    p.addEventListener('click', ev => {
      const t = ev.target.closest('button, a'); if (!t) return;
      if (t.dataset.set) { scenarios.set({ [t.dataset.set]: parseVal(t.dataset.val) }); }
      else if (t.dataset.nav) { if (gallery) { channel && channel.postMessage({ type: 'navigate', screen: t.dataset.nav }); } else app.navigate(t.dataset.nav); if (full) document.body.classList.remove('panel-open'); }
      else if (t.hasAttribute('data-reveal')) scenarios.revealPlatform();
      else if (t.hasAttribute('data-reset-clock')) { clock.reset(); app.refresh && app.current && app.refresh(); }
      else if (t.hasAttribute('data-reset-all')) { scenarios.reset(); clock.reset(); }
      else if (t.dataset.size) { setPhoneSize(document.getElementById('iphone'), t.dataset.size); p.querySelectorAll('[data-size]').forEach(b => b.classList.toggle('is-on', b.dataset.size === t.dataset.size)); }
      else if (t.hasAttribute('data-close')) document.body.classList.remove('panel-open');
      else if (t.hasAttribute('data-desktop-panel')) { ev.preventDefault(); window.open(t.getAttribute('href'), 'trajet-panel', 'width=1440,height=900'); }
    });
    // Refleja el estado (también cuando cambia desde otra pestaña).
    const sync = st => {
      p.querySelectorAll('[data-set]').forEach(b => {
        const k = b.dataset.set, v = parseVal(b.dataset.val);
        if (b.classList.contains('lp-tog')) { const on = !!st[k]; b.classList.toggle('is-on', on); b.dataset.val = String(!on); }
        else b.classList.toggle('is-on', st[k] === v);
      });
      const link = p.querySelector('[data-full-link]');
      if (link && !gallery) link.href = '?full=1#' + (app.current || 'board');
    };
    scenarios.subscribe(sync);
    setInterval(() => { const c = p.querySelector('[data-clock-panel]'); if (c) c.textContent = fmt.hhmm(clock.now()) + ':' + String(Math.floor(clock.now()) % 60).padStart(2, '0'); }, 250);
    return p;
  }

  // ------------------------------------------------------------ piezas comunes de HTML
  const parts = {
    /** El QR de emparejamiento, en SVG (patrón fijo, determinista). */
    qr(size = 160, ink = '#000', paper = '#fff') {
      const n = 25; const cell = size / n; let rects = '';
      let seed = 7;
      const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
      const finder = (x, y) => `<rect x="${x * cell}" y="${y * cell}" width="${7 * cell}" height="${7 * cell}" fill="${ink}"/><rect x="${(x + 1) * cell}" y="${(y + 1) * cell}" width="${5 * cell}" height="${5 * cell}" fill="${paper}"/><rect x="${(x + 2) * cell}" y="${(y + 2) * cell}" width="${3 * cell}" height="${3 * cell}" fill="${ink}"/>`;
      for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
        const inF = (x < 8 && y < 8) || (x >= n - 8 && y < 8) || (x < 8 && y >= n - 8);
        if (!inF && rnd() > 0.55) rects += `<rect x="${x * cell}" y="${y * cell}" width="${cell}" height="${cell}"/>`;
      }
      return `<svg class="qr" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" shape-rendering="crispEdges"><rect width="${size}" height="${size}" fill="${paper}"/><g fill="${ink}">${rects}</g>${finder(0, 0)}${finder(n - 7, 0)}${finder(0, n - 7)}</svg>`;
    },
    /** Iconos SF-like en SVG (trazo), para no depender de fuentes de iconos. */
    icon(name, cls = '') {
      const I = {
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        map: '<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z"/><path d="M9 4v14M15 6v14"/>',
        routes: '<circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M6 8.5V13a3 3 0 0 0 3 3h6a3 3 0 0 1 3 3"/>',
        search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
        chart: '<path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/>',
        gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
        run: '<circle cx="14" cy="4" r="2"/><path d="m5 21 4-7 3 2 2-5-4-2-3 3M12 11l2 4h4M9 14l-2 5"/>',
        walk: '<circle cx="13" cy="4" r="2"/><path d="m8 22 2.5-7M13 9l-2 6 3 2v5M13 9l3 3h3M13 9l-4 1-2 4"/>',
        cup: '<path d="M4 8h13a3 3 0 0 1 0 6h-1"/><path d="M4 8v6a6 6 0 0 0 12 0V8zM3 21h14"/>',
        back: '<path d="m15 5-7 7 7 7"/>',
        chev: '<path d="m9 5 7 7-7 7"/>',
        x: '<path d="M6 6l12 12M18 6 6 18"/>',
        plus: '<path d="M12 5v14M5 12h14"/>',
        warn: '<path d="M12 3 2 20h20L12 3z"/><path d="M12 10v4M12 17h.01"/>',
        locate: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/><circle cx="12" cy="12" r="8"/>',
        stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
        play: '<path d="M7 5v14l12-7z"/>',
        train: '<rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 10h14M8 21l2-4M16 21l-2-4"/><circle cx="9" cy="14" r="1"/><circle cx="15" cy="14" r="1"/>',
        bus: '<rect x="4" y="4" width="16" height="14" rx="3"/><path d="M4 11h16M7 21v-3M17 21v-3"/><circle cx="8" cy="15" r="1"/><circle cx="16" cy="15" r="1"/>',
        metro: '<circle cx="12" cy="12" r="9"/><path d="M7 15V9l2.5 4L12 9l2.5 4L17 9v6"/>',
        tram: '<rect x="6" y="6" width="12" height="11" rx="3"/><path d="M6 12h12M9 20l1-3M15 20l-1-3M9 3h6"/>',
        qr: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM20 14v3M17 20h4M14 20h1"/>',
        wifi: '<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/>',
        wifiOff: '<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M3 3l18 18"/>',
        check: '<path d="m5 12 5 5L20 7"/>',
        flag: '<path d="M5 21V4h11l-2 4 2 4H5"/>',
        pin: '<path d="M12 22s7-7 7-12a7 7 0 1 0-14 0c0 5 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/>',
        sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
        moon: '<path d="M21 13a8 8 0 1 1-10-10 7 7 0 0 0 10 10z"/>',
        swap: '<path d="M7 4v16M7 20l-3-3M7 20l3-3M17 20V4M17 4l3 3M17 4l-3 3"/>',
        server: '<rect x="3" y="4" width="18" height="6" rx="2"/><rect x="3" y="14" width="18" height="6" rx="2"/><path d="M7 7h.01M7 17h.01"/>',
        brain: '<path d="M9 4a3 3 0 0 0-3 3v1a3 3 0 0 0-2 3 3 3 0 0 0 2 3v1a3 3 0 0 0 3 3h3V4zM15 4a3 3 0 0 1 3 3v1a3 3 0 0 1 2 3 3 3 0 0 1-2 3v1a3 3 0 0 1-3 3h-3V4z"/>',
        phone: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
        length: '<rect x="2" y="9" width="9" height="6" rx="1"/><rect x="13" y="9" width="9" height="6" rx="1"/>',
        lengthShort: '<rect x="7" y="9" width="10" height="6" rx="1"/>',
        arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
        dots: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
        refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>',
        eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'
      };
      return `<svg class="ico ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${I[name] || ''}</svg>`;
    },
    modeIcon(mode) { return parts.icon({ metro: 'metro', rer: 'train', train: 'train', tram: 'tram', bus: 'bus', other: 'train' }[line.modeKind(mode)]); }
  };

  // ------------------------------------------------------------ galería
  const gallery = {
    mountPanel(container) { const p = buildPanel({ gallery: true }); container.appendChild(p); return p; },
    navigateAll(screen) { channel && channel.postMessage({ type: 'navigate', screen }); },
    channel
  };

  applyDocumentFlags();
  return { MODE, fmt, line, pace, scenarios, clock, buildBoard, moment, headline, visibleMessages, awaitingTranslation, app, parts, html, esc, el, gallery, SCREENS, data: D };
})();
