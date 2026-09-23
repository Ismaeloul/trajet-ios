/* Dirección B · «Cristal»
   El mapa es el contenido y el cristal (Liquid Glass) es la capa de
   controles. Los minutos y la vía NUNCA van sobre cristal: van en una
   cápsula opaca («billete») dentro de la tarjeta. Movimiento con muelle:
   las piezas rebotan, se funden y se estiran. */
(() => {
  'use strict';
  const T = window.Trajet, { html, esc, parts, fmt, line } = T;
  const M = window.TrajetMap;

  const TINT = {
    light: { land: '#eef0ee', water: '#bcd3ea', park: '#d9e8d3', building: '#e4e6e3', road: '#ffffff', roadCasing: '#d9dbd8', rail: '#cfd2cf', text: '#4a5058', halo: '#ffffff' },
    dark:  { land: '#131417', water: '#0f1a26', park: '#161c17', building: '#1a1b1f', road: '#25272c', roadCasing: '#0f1012', rail: '#2a2c31', text: '#a6aab3', halo: '#131417' }
  };
  const mapOpts = (ctx, extra = {}) => Object.assign({
    theme: ctx.s.theme, tint: TINT, labels: true, casing: true, routeWidth: 6, stopRadius: 5, labelSize: 12,
    stopFill: ctx.s.theme === 'dark' ? '#131417' : '#fff', meColor: '#0a84ff'
  }, extra);

  // ---------------------------------------------------------------- piezas
  const badge = (code, color, cls = '') =>
    `<span class="badge ${cls}" style="--lc:${line.color(color)};--li:${line.ink(color)}">${esc(code || '?')}</span>`;

  const via = (dep, leg) => {
    if (!line.publishesPlatform(leg.line_mode)) return '';
    if (dep.platform) return `<span class="via via-real${dep._isNew ? ' is-new' : ''}"><small>Vía</small><b>${esc(dep.platform)}</b></span>`;
    if (dep.guess) return `<span class="via via-guess"><small>probable</small><b>${esc(dep.guess.platform)}</b><i>${Math.round(dep.guess.share * 100)} %</i></span>`;
    return '';
  };

  const meta = (dep) => {
    const out = [];
    if (dep.delay != null && dep.aimed_at && dep.delay !== 0) out.push(`<span class="mt ${dep.delay > 0 ? 'is-late' : ''}">${fmt.delay(dep.delay)}</span>`);
    if (dep.length) out.push(`<span class="mt">${parts.icon(dep.length === 'short' ? 'lengthShort' : 'length')} ${dep.length === 'short' ? 'corto' : 'largo'}</span>`);
    return out.join('');
  };

  /** La primera salida: billete grande. Las demás: fichas pequeñas. */
  const ticket = (dep, leg) => {
    const m = T.moment(dep);
    return html`<div class="ticket${dep.at_stop ? ' is-atstop' : ''}" data-jid="${dep.jid}">
      <div class="tk-num"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></div>
      <div class="tk-body"><span class="tk-dest">${esc(dep.destination)}</span><span class="tk-meta"><span data-dep-at="${dep.jid}">${dep.at}</span>${meta(dep)}${dep.at_stop ? '<span class="mt is-ok">en el andén</span>' : ''}</span></div>
      <div class="tk-right">${via(dep, leg)}${m.pace ? `<span class="pace" data-pace="${dep.jid}" data-value="${m.pace.id}" data-pace-label="short">${m.pace.short}</span>` : ''}</div>
    </div>`;
  };
  const chip = (dep, leg) => {
    const m = T.moment(dep);
    return html`<div class="chip" data-jid="${dep.jid}">
      <b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small>
      <span class="chip-at" data-dep-at="${dep.jid}">${dep.at}</span>
      ${via(dep, leg)}${dep.length ? `<span class="chip-len">${dep.length === 'short' ? 'corto' : 'largo'}</span>` : ''}${dep.delay > 0 && dep.aimed_at ? `<span class="chip-late">${fmt.delay(dep.delay)}</span>` : ''}
    </div>`;
  };

  const notice = leg => {
    const st = leg.status; if (!st.level && !st.messages.length) return '';
    const msgs = T.visibleMessages(st);
    return html`<div class="notice lvl-${st.level}">
      <div class="notice-head">${parts.icon('warn')}<b>${esc(st.label)}</b>${T.awaitingTranslation(st) ? '<em class="translating"><i></i><i></i><i></i> traduciendo</em>' : ''}</div>
      ${msgs.map(m => `<p lang="${m.translated ? 'es' : 'fr'}" class="${m.translated ? 'is-es' : 'is-fr'}">${esc(m.text)}</p>`)}
    </div>`;
  };

  const legCard = leg => html`<section class="card leg" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
    <header class="leg-head">${badge(leg.line_code, leg.line_color, 'badge-lg')}<div><h2>${esc(leg.from_name)} <i>→</i> ${esc(leg.to_name || leg.directions[0] || '')}</h2>${leg.directions.length ? `<p>dirección ${esc(leg.directions.join(' · '))}</p>` : ''}</div></header>
    ${notice(leg)}
    ${leg.departures.length
      ? `${ticket(leg.departures[0], leg)}<div class="chips">${leg.departures.slice(1, 4).map(d => chip(d, leg)).join('')}</div>`
      : `<div class="empty">${parts.icon('clock')}<b>Sin próximos pasos</b><span>${leg.status.level >= 2 ? 'servicio interrumpido' : 'nada anunciado ahora mismo'}</span></div>`}
  </section>`;

  const navbar = (title, { back = null, right = '' } = {}) => html`<header class="navbar">
    ${back ? `<button class="glass-btn" data-go="${back}" data-back>${parts.icon('back')}</button>` : '<span class="nb-spacer"></span>'}
    <h1 class="glass-title">${title}</h1>
    ${right || '<span class="nb-spacer"></span>'}
  </header>`;

  // ---------------------------------------------------------------- pantallas
  const S = {};

  S.pair = {
    render: () => html`<div class="pair">
      <div class="pair-cam">${parts.qr(170, '#0a0a0c', '#fff')}<div class="pair-ring"></div></div>
      <div class="glass pair-sheet">
        <h1>Emparejar con el servidor</h1>
        <p class="pair-state" data-state="scan"><span data-s="scan">Enfoca el QR del panel del servidor.</span><span data-s="connecting">Conectando con umbrel:7796…</span><span data-s="ready">${parts.icon('check')} Listo. iPhone de Isma emparejado.</span></p>
        <button class="btn btn-primary" data-pair>Escanear</button>
        <button class="btn btn-glass" data-go="settings">Escribir la dirección a mano</button>
      </div>
    </div>`,
    mount(el) {
      const st = el.querySelector('.pair-state');
      el.querySelector('[data-pair]').addEventListener('click', ev => {
        ev.currentTarget.disabled = true; el.classList.add('is-scanning');
        setTimeout(() => { st.dataset.state = 'connecting'; el.classList.add('is-found'); }, 900);
        setTimeout(() => { st.dataset.state = 'ready'; el.classList.add('is-ready'); }, 2200);
        setTimeout(() => T.app.navigate('board'), 3400);
      });
    }
  };

  S.board = {
    render(ctx) {
      const b = ctx.board;
      const cut = b.legs.some(l => l.status.level >= 2);
      return html`<div class="board">
        <div class="board-map" id="map-b-board"></div>
        <div class="board-fade"></div>
        <header class="board-head glass">
          <div><p class="kicker">${b.auto_selected ? 'La que toca ahora' : 'Ruta'}</p><h1>${esc(b.route.name)}</h1></div>
          <button class="glass-btn" data-go="settings" aria-label="Ajustes">${parts.icon('gear')}</button>
        </header>
        <div class="scroll">
          <div class="board-spacer"></div>
          <div class="status ${b.stale ? 'is-stale' : ''}">${b.stale ? `${parts.icon('wifiOff')}<b>Sin conexión</b> · último tablero <span data-age>${fmt.age(b.data_age)}</span>` : `<span class="live"><i></i></span>en directo · <span data-age>${fmt.age(b.data_age)}</span>`}</div>
          ${b.legs.map(legCard)}
          <button class="btn ${cut ? 'btn-danger' : 'btn-glass'} btn-wide" data-go="alternatives" data-sheet>${parts.icon('swap')} Buscar alternativa${cut ? ' · línea ' + esc(b.worst_line) + ' cortada' : ''}</button>
          <p class="foot">${fmt.quota(b.quota['stop-monitoring'])} · se refresca cada 30 s mientras miras</p>
        </div>
      </div>`;
    },
    mount(el, ctx) {
      el._map = M.mount(el.querySelector('#map-b-board'), mapOpts(ctx, { interactive: false, labels: false, animate: false, showTransfer: true, padding: { top: 80, bottom: 520, left: 40, right: 40 } }));
    },
    update(el, ctx) {
      el._map && el._map.setTheme(ctx.s.theme);
      const tmp = document.createElement('div'); tmp.innerHTML = S.board.render(ctx);
      el.querySelector('.scroll').innerHTML = tmp.querySelector('.scroll').innerHTML;
      el.querySelector('.board-head').innerHTML = tmp.querySelector('.board-head').innerHTML;
    },
    unmount(el) { el._map && el._map.destroy(); }
  };

  S.map = {
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg, s = ctx.s;
      return html`<div class="mapscr">
        <div class="map" id="map-b"></div>
        <div class="map-top">
          <button class="glass-btn" data-go="board" data-back>${parts.icon('back')}</button>
          <div class="glass pill-route">${badge('J', 'CEC73D')}<span>Saint-Lazare → Argenteuil</span></div>
          <button class="glass-btn" aria-label="Centrar">${parts.icon('locate')}</button>
        </div>
        <div class="glass map-card">
          <div class="mc-walk">${parts.icon('walk')} <b>${ctx.data.lineJ.walkMinutes} min</b> a pie hasta Saint-Lazare</div>
          ${dep ? ticket(dep, leg) : '<div class="empty"><b>Sin próximos pasos</b></div>'}
          ${s.trip
            ? `<button class="btn btn-danger btn-wide" data-scenario="trip=false">${parts.icon('stop')} Parar trayecto</button><p class="foot">sigue en segundo plano · se apaga al llegar</p>`
            : `<button class="btn btn-primary btn-wide" data-scenario="trip=true">${parts.icon('play')} Iniciar trayecto</button>`}
        </div>
      </div>`;
    },
    mount(el, ctx) { el._map = M.mount(el.querySelector('#map-b'), mapOpts(ctx, { padding: { top: 120, bottom: 320, left: 40, right: 40 } })); },
    update(el, ctx) {
      el._map && el._map.setTheme(ctx.s.theme);
      const tmp = document.createElement('div'); tmp.innerHTML = S.map.render(ctx);
      el.querySelector('.map-card').innerHTML = tmp.querySelector('.map-card').innerHTML;
    },
    unmount(el) { el._map && el._map.destroy(); }
  };

  const chain = legs => `<div class="chain">${legs.map((l, j) => `${j ? '<i class="chain-gap"></i>' : ''}${badge(l.code || l.line_code, l.color || l.line_color)}<span class="chain-leg"><b>${esc(l.direction)}</b><small>${l.minutes} min${l.status && l.status !== 'normal' ? ' · ' + esc(l.status) : ''}</small></span>`).join('')}</div>`;

  S.alternatives = {
    render(ctx) {
      const a = ctx.data.alternatives;
      return html`<div class="sheet-scr">
        <div class="sheet-grab"></div>
        ${navbar('Alternativas', { back: 'board' })}
        <div class="scroll">
          <div class="card affected">${parts.icon('warn')}<div><b>Línea ${a.affected.map(x => esc(x.line_code)).join(', ')} ${esc(a.affected[0].label)}</b><span>tu ruta tarda ${a.baseline_minutes} min cuando funciona</span></div></div>
          ${a.options.map(o => html`<article class="card alt ${o.usable ? '' : 'is-unusable'}">
            <header><span class="solid-num">${o.total_minutes}<small>min</small></span><span class="delta">${o.delta_minutes != null ? '+' + o.delta_minutes + ' min' : ''}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
            ${chain(o.legs)}
            <footer>${o.usable ? `<span>${fmt.transfers(o.transfers)}</span><button class="btn btn-small btn-primary" data-go="board" data-back>Usar hoy</button>` : `<span class="bad">${parts.icon('x')} pasa por la línea cortada</span>`}</footer>
          </article>`)}
        </div>
      </div>`;
    }
  };

  S.routes = {
    render(ctx) {
      const rs = ctx.data.routes;
      return html`<div class="page">
        ${navbar('Rutas', { right: `<button class="glass-btn" data-go="route-edit">${parts.icon('plus')}</button>` })}
        <div class="scroll">
          <p class="kicker pad">Se elige sola según el día y la hora</p>
          ${rs.routes.map(r => html`<article class="card route ${r.id === rs.active_id ? 'is-active' : ''}" data-go="route-edit">
            <div class="route-legs">${r.legs.map(l => badge(l.line_code, l.line_color)).join('<i class="chain-gap"></i>')}${r.id === rs.active_id ? '<span class="tag">ahora</span>' : ''}</div>
            <h3>${esc(r.name)}</h3><p>${esc(r.origin_name)} → ${esc(r.dest_name)}</p><small>${fmt.daysLabel(r.days)} · ${fmt.scheduleLabel(r)}</small>
          </article>`)}
          <button class="btn btn-glass btn-wide" data-go="plan">${parts.icon('search')} Crear desde el planificador</button>
        </div>
      </div>`;
    }
  };

  S['route-edit'] = {
    render(ctx) {
      const r = ctx.data.routes.routes[1]; const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      return html`<div class="page">
        ${navbar('Editar ruta', { back: 'routes', right: '<button class="glass-btn glass-text" data-go="routes" data-back>Guardar</button>' })}
        <div class="scroll">
          <div class="card form">
            <label class="field"><span>Nombre</span><input value="${esc(r.name)}"></label>
            <label class="field"><span>Origen</span><input value="${esc(r.origin_name)}"></label>
            <label class="field"><span>Destino</span><input value="${esc(r.dest_name)}"></label>
          </div>
          <div class="card form">
            <div class="field"><span>Días</span><div class="days">${days.map((d, i) => `<button class="day ${r.days.includes(i) ? 'is-on' : ''}" data-toggle>${d}</button>`).join('')}</div></div>
            <div class="field"><span>Cuándo toca</span><div class="seg"><button class="${r.time_mode === 'window' ? 'is-on' : ''}">Franja</button><button class="${r.time_mode === 'arrival' ? 'is-on' : ''}">Llegar a</button><button class="${r.time_mode === 'departure' ? 'is-on' : ''}">Salir a</button></div><div class="times"><input value="${r.time_from}"><span>→</span><input value="${r.time_to}"></div></div>
          </div>
          <p class="kicker pad">Tramos</p>
          ${r.legs.map(l => html`<div class="card leg-edit">${badge(l.line_code, l.line_color)}<div><b>${esc(l.from_name)} → ${esc(l.to_name)}</b><small>${l.directions.length ? 'dirección ' + esc(l.directions.join(' · ')) : 'cualquier sentido'}</small></div><button class="glass-btn" aria-label="quitar">${parts.icon('x')}</button></div>`)}
          <button class="btn btn-glass btn-wide">${parts.icon('plus')} Añadir tramo</button>
          <button class="btn btn-danger-text btn-wide">Eliminar ruta</button>
        </div>
      </div>`;
    },
    mount(el) { el.querySelectorAll('[data-toggle]').forEach(b => b.addEventListener('click', () => b.classList.toggle('is-on'))); el.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => { b.parentElement.querySelectorAll('button').forEach(x => x.classList.remove('is-on')); b.classList.add('is-on'); })); }
  };

  S.plan = {
    render(ctx) {
      const p = ctx.data.plan; const kind = { best: 'Más rápido', less_fallback: 'Menos transbordos', less_walk: 'Menos a pie' };
      return html`<div class="page">
        ${navbar('Buscar')}
        <div class="scroll">
          <div class="card form">
            <label class="field"><span>Desde</span><input value="Argenteuil"></label>
            <label class="field"><span>Hasta</span><input value="Montparnasse" placeholder="Dirección, parada o sitio"></label>
            <div class="plan-when"><span>${parts.icon('clock')} Salir ahora</span><button class="btn btn-small btn-glass">Cambiar</button></div>
          </div>
          <p class="kicker pad">Resultados · <span data-age>hace 1 s</span></p>
          ${p.options.map(o => html`<article class="card alt">
            <header><span class="solid-num">${o.minutes}<small>min</small></span><span class="tag">${kind[o.kind] || o.kind}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
            ${chain(o.legs)}
            <footer><span>${fmt.transfers(o.transfers)} · ${o.walk_minutes} min a pie</span><button class="btn btn-small btn-primary" data-go="routes">Guardar ruta</button></footer>
          </article>`)}
        </div>
      </div>`;
    }
  };

  S.stats = {
    render(ctx) {
      const st = ctx.data.stats, pm = ctx.data.platformModel;
      const maxShare = Math.max(...st.by_month.map(m => m.bad_days / m.total_days));
      return html`<div class="page">
        ${navbar('Historial')}
        <div class="scroll">
          <div class="tiles">
            <div class="card tile"><span class="solid-num">${st.overall.n}</span><span>días con datos</span></div>
            <div class="card tile"><span class="solid-num">${st.overall.avg_delay.toFixed(1)}<small>min</small></span><span>retraso medio</span></div>
            <div class="card tile"><span class="solid-num">${Math.round(st.overall.max_delay)}<small>min</small></span><span>peor día</span></div>
          </div>
          <p class="kicker pad">Días con incidencias</p>
          <div class="card">${st.by_month.map(m => html`<div class="bar"><span class="bar-lbl">${fmt.monthLabel(m.month)}</span><span class="bar-track"><i style="width:${(m.bad_days / m.total_days / maxShare * 100).toFixed(0)}%"></i></span><b>${m.bad_days}<small>/${m.total_days}</small></b></div>`)}</div>
          <p class="kicker pad">Qué línea falla más</p>
          <div class="card">${st.by_line.map(l => { const r = ctx.data.routes.routes.flatMap(x => x.legs).find(x => x.line_code === l.worst_line); return html`<div class="line-stat">${badge(l.worst_line, r ? r.line_color : '')}<div><b>${l.n} días</b> como peor línea<small>retraso medio ${l.avg_delay.toFixed(1)} min</small></div></div>`; })}</div>
          <p class="kicker pad">Previsión de vía</p>
          <div class="card accuracy"><span class="solid-num big">${fmt.percent(pm.accuracy.rate)}</span><div><b>${pm.accuracy.hits} aciertos de ${pm.accuracy.predictions}</b><small>${pm.accuracy.observations} trenes en ${pm.accuracy.days} días · el servidor se puntúa solo</small>${pm.coverage.map(c => `<div class="cov">${badge(c.line_code, c.line_code === 'J' ? 'CEC73D' : '640082', 'badge-sm')}<span>${c.observations ? `${c.observations} observaciones · ${c.platforms} vías` : 'no publica vía'}</span></div>`).join('')}</div></div>
        </div>
      </div>`;
    }
  };

  S.settings = {
    render(ctx) {
      const h = ctx.data.health;
      const q = (k) => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${h.quota[k] / 10}%"></i></span><b>${h.quota[k]}</b></div>`;
      return html`<div class="page">
        ${navbar('Ajustes', { back: 'board' })}
        <div class="scroll">
          <p class="kicker pad">Servidor</p>
          <div class="card list">
            <div class="li"><span>Red de casa</span><b class="mono">192.168.1.188:7796</b><i class="dot ok"></i></div>
            <div class="li"><span>Tailscale</span><b class="mono">100.99.38.76:7796</b><i class="dot ${ctx.s.offline ? 'bad' : 'ok'}"></i></div>
            <button class="li" data-go="pair"><span>${parts.icon('qr')} Emparejar de nuevo</span>${parts.icon('chev')}</button>
            <button class="li" data-go="panel"><span>${parts.icon('server')} Panel del servidor</span>${parts.icon('chev')}</button>
          </div>
          <p class="kicker pad">Cuota PRIM · quedan hoy</p>
          <div class="card list pad-in">${q('stop-monitoring')}${q('general-message')}${q('navitia')}</div>
          <p class="kicker pad">Traductor (IA local)</p>
          <div class="card list"><div class="li"><span>${parts.icon('brain')} ${h.translator.model}</span><b>${h.translator.ok ? 'listo' : 'parado'}</b><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div></div>
          <p class="kicker pad">Pantalla</p>
          <div class="card list">
            <div class="li"><span>Aspecto</span><div class="seg seg-sm"><button class="${ctx.s.theme === 'light' ? 'is-on' : ''}" data-scenario="theme=light">Claro</button><button class="${ctx.s.theme === 'dark' ? 'is-on' : ''}" data-scenario="theme=dark">Oscuro</button></div></div>
            <div class="li"><span>Pantalla encendida en el tablero</span><i class="sw is-on"></i></div>
            <div class="li"><span>Vibrar cuando aparece la vía</span><i class="sw is-on"></i></div>
          </div>
          <p class="kicker pad">Prototipos</p>
          <div class="card list"><button class="li" data-go="live"><span>Live Activity</span>${parts.icon('chev')}</button><button class="li" data-go="widgets"><span>Widgets</span>${parts.icon('chev')}</button></div>
          <p class="foot">Trajet 2.0 · dirección B «Cristal»</p>
        </div>
      </div>`;
    }
  };

  const activity = (ctx, cls = '') => {
    const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; if (!dep) return '';
    const m = T.moment(dep);
    return html`<div class="la ${cls}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
      <div class="la-l">${badge(leg.line_code, leg.line_color, 'badge-lg')}<div><b class="la-dest">${esc(dep.destination)}</b><span class="la-sub">Saint-Lazare · <span data-dep-at="${dep.jid}">${dep.at}</span> · <span data-countdown="${dep.jid}">${fmt.mmss(dep._seconds)}</span></span></div></div>
      <div class="la-r"><span class="la-ticket"><b class="num" data-dep-min="${dep.jid}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></span>${via(dep, leg)}</div>
      <div class="la-bar" data-progress="${dep.jid}" data-total="900"><i></i></div>
    </div>`;
  };

  S.live = {
    hidesStatus: true,
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep; const m = dep ? T.moment(dep) : null;
      return html`<div class="lock">
        <div class="lock-top"><span class="lock-date">martes 23 de septiembre</span><b class="lock-time" data-clock>${fmt.hhmm(ctx.now)}</b></div>
        ${activity(ctx, 'la-lock glass')}
        <div class="lock-bottom"><span class="glass"></span><span class="glass"></span></div>
        <div class="di-show">
          <p class="kicker">Dynamic Island</p>
          <div class="di-row"><span>compacta</span><div class="di di-compact">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b><em class="${dep && dep.platform ? 'is-real' : ''}">${dep && dep.platform ? 'Vía ' + esc(dep.platform) : (dep && dep.guess ? '¿' + esc(dep.guess.platform) + '?' : 'J')}</em></div></div>
          <div class="di-row"><span>mínima</span><div class="di di-min">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b></div></div>
          <div class="di-row"><span>expandida</span><div class="di di-exp">${activity(ctx, 'la-di')}</div></div>
        </div>
      </div>`;
    }
  };

  S.widgets = {
    hidesStatus: true,
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; const m = dep ? T.moment(dep) : null;
      const app = n => `<span class="hs-app"><i></i><small>${n}</small></span>`;
      return html`<div class="home">
        <p class="kicker">Pantalla de inicio</p>
        <div class="hs-grid">
          <div class="widget glass w-small" style="--lc:#CEC73D;--li:#000">${badge('J', 'CEC73D')}<span class="w-ticket"><b class="num" data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small></span>${dep ? via(dep, leg) : ''}<span class="w-foot">Argenteuil</span></div>
          <div class="hs-apps">${app('Mail')}${app('Fotos')}${app('Notas')}${app('Mapas')}</div>
          <div class="widget glass w-medium">
            <div class="w-head">${badge('J', 'CEC73D')}<span>Saint-Lazare → Argenteuil</span><span class="live"><i></i></span></div>
            <div class="w-rows">${(leg ? leg.departures.slice(0, 3) : []).map(d => `<div class="w-row"><span class="w-ticket sm"><b data-dep-min="${d.jid}">${T.moment(d).text}</b><small data-dep-unit="${d.jid}">${T.moment(d).unit}</small></span><span>${d.at}</span>${via(d, leg)}</div>`).join('')}</div>
          </div>
          <div class="hs-apps">${app('Cámara')}${app('Ajustes')}${app('Reloj')}${app('Música')}</div>
        </div>
        <p class="kicker">Pantalla de bloqueo</p>
        <div class="ls-widgets">
          <div class="lsw lsw-circ"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small>J</small></div>
          <div class="lsw lsw-rect">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small><span>${dep && dep.platform ? 'Vía ' + esc(dep.platform) : 'Argenteuil'}</span></div>
          <div class="lsw lsw-inline">${badge('J', 'CEC73D', 'badge-sm')} <b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b> min · Argenteuil${dep && dep.platform ? ' · vía ' + esc(dep.platform) : ''}</div>
        </div>
      </div>`;
    }
  };

  S.panel = {
    hidesStatus: true,
    render(ctx) {
      const a = ctx.data.admin, h = ctx.data.health; const max = Math.max(...a.quotaHistory);
      return html`<div class="panel">
        <div class="web-bar"><span>umbrel:7796/admin</span></div>
        <div class="scroll">
          <header class="panel-head"><div class="panel-logo">${badge('T', '0a84ff')}<b>Trajet · servidor</b></div><span class="live"><i></i> en marcha</span></header>
          <div class="panel-grid">
            <section class="card pcard pcard-qr"><h3>Emparejar un iPhone</h3>${parts.qr(180, '#0a0a0c', '#fff')}<p>Escanea desde la app. Caduca en <b>5:00</b>.</p><button class="btn btn-small btn-primary">Nuevo código</button></section>
            <section class="card pcard"><h3>Dispositivos</h3>${a.devices.map(d => html`<div class="dev ${d.active ? '' : 'is-off'}">${parts.icon('phone')}<div><b>${esc(d.name)}</b><small>${d.via} · ${d.last_seen}</small></div><button class="btn btn-small btn-glass">Quitar</button></div>`)}</section>
            <section class="card pcard"><h3>Cuota PRIM · hoy</h3>${Object.entries(h.quota).map(([k, v]) => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${v / 10}%"></i></span><b>${v}</b></div>`)}<div class="spark">${a.quotaHistory.map(v => `<i style="height:${v / max * 100}%"></i>`).join('')}</div><small>llamadas usadas, últimos 7 días</small></section>
            <section class="card pcard"><h3>IA local</h3><div class="dev">${parts.icon('brain')}<div><b>${h.translator.model}</b><small>${h.translator.reason}</small></div><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div><p>Traduce los avisos del francés. Si se para, la app enseña el francés y avisa.</p></section>
            <section class="card pcard"><h3>Aprendizaje de andenes</h3><div class="tiles"><div class="tile"><span class="solid-num">${fmt.percent(a.learning.hits / a.learning.predictions)}</span><span>acierto</span></div><div class="tile"><span class="solid-num">${a.learning.observations}</span><span>trenes</span></div><div class="tile"><span class="solid-num">${a.learning.days}</span><span>días</span></div></div></section>
            <section class="card pcard"><h3>Estado</h3><div class="li"><span>Clave PRIM</span><b>${h.key_configured ? 'configurada' : 'falta'}</b></div><div class="li"><span>Hora en París</span><b data-clock>${fmt.hhmm(ctx.now)}</b></div><div class="li"><span>Último error</span><b>${h.last_error || 'ninguno'}</b></div></section>
          </div>
          <p class="foot">Panel solo accesible desde la red de casa o la tailnet.</p>
        </div>
      </div>`;
    }
  };

  T.app.register({
    id: 'b', name: 'Cristal', home: 'board', screens: S,
    tabbar: () => html`<div class="tabs glass">
      <button data-go="board" data-go-group="alternatives settings" class="is-active">${parts.icon('clock')}<span>Tablero</span></button>
      <button data-go="map">${parts.icon('map')}<span>Trayecto</span></button>
      <button data-go="routes" data-go-group="route-edit">${parts.icon('routes')}<span>Rutas</span></button>
      <button data-go="stats">${parts.icon('chart')}<span>Historial</span></button>
    </div><button class="tab-search glass" data-go="plan">${parts.icon('search')}</button>`
  });
})();
