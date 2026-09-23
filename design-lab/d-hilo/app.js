/* Dirección D · «Hilo»
   La línea del trayecto es el hilo gráfico de toda la app, como en el icono:
   origen, transbordo, destino cosidos por un raíl con el color de cada línea.
   Los tramos cuelgan del hilo; el mapa es el hilo puesto sobre la ciudad.
   Movimiento: el hilo se dibuja, una cuenta recorre el raíl, las cifras
   ruedan como cuentas de un ábaco. */
(() => {
  'use strict';
  const T = window.Trajet, { html, esc, parts, fmt, line } = T;
  const M = window.TrajetMap;

  const TINT = {
    light: { land: '#f4f3ef', water: '#d6e2ea', park: '#e6ecdf', building: '#ebeae5', road: '#ffffff', roadCasing: '#dcdbd5', rail: '#d3d2cc', text: '#3b4252', halo: '#f4f3ef' },
    dark:  { land: '#0e1119', water: '#0a1220', park: '#11161b', building: '#141823', road: '#1e2431', roadCasing: '#0b0e15', rail: '#242a38', text: '#c7cbd6', halo: '#0e1119' }
  };
  const mapOpts = (ctx, extra = {}) => Object.assign({
    theme: ctx.s.theme, tint: TINT, labels: true, casing: false, glow: true, routeWidth: 7, stopRadius: 6, labelSize: 12,
    stopFill: ctx.s.theme === 'dark' ? '#0e1119' : '#fff', meColor: '#ff6b3d'
  }, extra);

  // ---------------------------------------------------------------- piezas
  const badge = (code, color, cls = '') => `<span class="badge ${cls}" style="--lc:${line.color(color)};--li:${line.ink(color)}">${esc(code || '?')}</span>`;
  const via = (dep, leg) => {
    if (!line.publishesPlatform(leg.line_mode)) return '';
    if (dep.platform) return `<span class="via via-real${dep._isNew ? ' is-new' : ''}"><small>Vía</small><b>${esc(dep.platform)}</b></span>`;
    if (dep.guess) return `<span class="via via-guess"><small>probable</small><b>${esc(dep.guess.platform)}</b><i>${Math.round(dep.guess.share * 100)} %</i></span>`;
    return '';
  };
  const meta = dep => {
    const out = [];
    if (dep.at_stop) out.push('<em class="ok">en el andén</em>');
    if (dep.delay != null && dep.aimed_at && dep.delay !== 0) out.push(`<em class="${dep.delay > 0 ? 'late' : ''}">${fmt.delay(dep.delay)}</em>`);
    if (dep.length) out.push(`<em>${parts.icon(dep.length === 'short' ? 'lengthShort' : 'length')}${dep.length === 'short' ? 'corto' : 'largo'}</em>`);
    return out.join('');
  };
  /** La cuenta grande (primera salida) y las pequeñas. */
  const bead = (dep, leg, first) => {
    const m = T.moment(dep);
    return html`<div class="bead${first ? ' bead-first' : ''}${dep.at_stop ? ' is-atstop' : ''}" data-jid="${dep.jid}">
      <span class="bead-num"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></span>
      ${first ? `<span class="bead-dest">${esc(dep.destination)}</span>` : ''}
      <span class="bead-meta"><span data-dep-at="${dep.jid}">${dep.at}</span>${meta(dep)}</span>
      ${via(dep, leg)}
      ${first && m.pace ? `<span class="pace" data-pace="${dep.jid}" data-value="${m.pace.id}" data-pace-label="label">${m.pace.label}</span>` : ''}
    </div>`;
  };
  const notice = leg => {
    const st = leg.status; if (!st.level && !st.messages.length) return '';
    return html`<div class="notice lvl-${st.level}"><span class="notice-lbl">${parts.icon('warn')}${esc(st.label)}${T.awaitingTranslation(st) ? '<em class="translating">traduciendo<i></i><i></i><i></i></em>' : ''}</span>
      ${T.visibleMessages(st).map(m => `<p lang="${m.translated ? 'es' : 'fr'}" class="${m.translated ? '' : 'is-fr'}">${esc(m.text)}</p>`)}</div>`;
  };

  /** Un tramo colgado del hilo: nodo (distintivo) + raíl del color + cuentas. */
  const legOnThread = (leg, i) => html`<section class="tl-leg" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)};--i:${i}">
    <div class="tl-node">${badge(leg.line_code, leg.line_color, 'badge-lg')}</div>
    <div class="tl-rail"><i></i></div>
    <div class="tl-body">
      <header><h2>${esc(leg.from_name)}</h2><p>${leg.to_name ? 'hasta ' + esc(leg.to_name) : ''}${leg.directions.length ? ' · dir. ' + esc(leg.directions.join(' · ')) : ''}</p></header>
      ${notice(leg)}
      ${leg.departures.length ? `<div class="beads">${leg.departures.slice(0, 4).map((d, j) => bead(d, leg, j === 0)).join('')}</div>` : `<div class="empty"><b>Sin próximos pasos</b><span>${leg.status.level >= 2 ? 'servicio interrumpido' : 'nada anunciado ahora mismo'}</span></div>`}
    </div>
  </section>`;

  const top = (title, { back = null, right = '' } = {}) => html`<header class="top">${back ? `<button class="tb" data-go="${back}" data-back>${parts.icon('back')}</button>` : ''}<h1>${title}</h1>${right}</header>`;

  // ---------------------------------------------------------------- pantallas
  const S = {};
  S.pair = {
    render: () => html`<div class="pair">
      <div class="pair-thread"><i class="pn pn-phone">${parts.icon('phone')}</i><i class="pl"></i><i class="pn pn-srv">${parts.icon('server')}</i></div>
      <div class="pair-cam">${parts.qr(160, '#0b0d14', '#fff')}<div class="pair-frame"></div></div>
      <div class="pair-body">
        <h1>Emparejar con el servidor</h1>
        <p class="pair-state" data-state="scan"><span data-s="scan">Enfoca el QR del panel del servidor.</span><span data-s="connecting">Conectando con umbrel:7796…</span><span data-s="ready">${parts.icon('check')} Listo. iPhone de Isma emparejado.</span></p>
        <button class="btn btn-primary" data-pair>Escanear</button>
        <button class="btn btn-ghost" data-go="settings">Escribir la dirección a mano</button>
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
      const b = ctx.board; const cut = b.legs.some(l => l.status.level >= 2);
      return html`<div class="board">
        <header class="board-head">
          <div><p class="kicker">${b.auto_selected ? 'La que toca ahora' : 'Ruta'} · <span data-clock>${fmt.hhmm(ctx.now)}</span></p><h1>${esc(b.route.name)}</h1></div>
          <button class="tb" data-go="settings" aria-label="Ajustes">${parts.icon('gear')}</button>
        </header>
        <div class="scroll">
          <div class="thread">
            <section class="tl-leg tl-me" style="--i:0">
              <div class="tl-node"><i class="me-dot"></i></div>
              <div class="tl-rail tl-walk"><i></i></div>
              <div class="tl-body tl-body-me"><b>Estás aquí</b><span>${ctx.data.lineJ.walkMinutes} min a pie hasta ${esc(b.legs[0] ? b.legs[0].from_name : 'la estación')}</span>
                <span class="state ${b.stale ? 'is-stale' : ''}">${b.stale ? `${parts.icon('wifiOff')} sin conexión · último tablero <span data-age>${fmt.age(b.data_age)}</span>` : `<span class="live"><i></i></span>en directo · <span data-age>${fmt.age(b.data_age)}</span>`}</span></div>
            </section>
            ${b.legs.map((l, i) => legOnThread(l, i + 1))}
            <section class="tl-leg tl-end" style="--i:${b.legs.length + 1}">
              <div class="tl-node"><i class="end-dot">${parts.icon('flag')}</i></div>
              <div class="tl-body tl-body-end"><b>${esc(b.route.dest_name)}</b><span>${esc(b.route.name.split('→')[1] || 'destino')}</span></div>
            </section>
          </div>
          <button class="btn ${cut ? 'btn-danger' : 'btn-ghost'} btn-wide" data-go="alternatives" data-sheet>${parts.icon('swap')} Buscar alternativa${cut ? ' · línea ' + esc(b.worst_line) + ' cortada' : ''}</button>
          <p class="foot">${fmt.quota(b.quota['stop-monitoring'])} · cada 30 s mientras miras</p>
        </div>
      </div>`;
    }
  };

  S.map = {
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg, s = ctx.s;
      const stops = ctx.data.lineJ.stops.filter(x => x.served);
      return html`<div class="mapscr">
        <div class="map" id="map-d"></div>
        <div class="map-top"><button class="tb tb-solid" data-go="board" data-back>${parts.icon('back')}</button>
          <div class="mini-thread"><i class="mt-dot mt-me"></i><i class="mt-line mt-walk"></i>${badge('J', 'CEC73D', 'badge-sm')}<i class="mt-line" style="--lc:#CEC73D"><b class="mt-bead"></b></i><i class="mt-dot mt-end"></i></div>
        </div>
        <div class="map-card">
          <div class="stops-strip">${stops.map(x => `<span class="${x.dest ? 'is-dest' : ''}"><i></i>${esc(x.name.replace('Paris ', '').replace('-sur-Seine', ''))}</span>`).join('')}</div>
          ${dep ? bead(dep, leg, true) : '<div class="empty"><b>Sin próximos pasos</b></div>'}
          ${s.trip ? `<button class="btn btn-danger btn-wide" data-scenario="trip=false">${parts.icon('stop')} Parar trayecto</button><p class="foot">sigue en segundo plano · se apaga al llegar</p>` : `<button class="btn btn-primary btn-wide" data-scenario="trip=true">${parts.icon('play')} Iniciar trayecto</button>`}
        </div>
      </div>`;
    },
    mount(el, ctx) { el._map = M.mount(el.querySelector('#map-d'), mapOpts(ctx, { padding: { top: 120, bottom: 330, left: 40, right: 40 } })); },
    update(el, ctx) { el._map && el._map.setTheme(ctx.s.theme); const tmp = document.createElement('div'); tmp.innerHTML = S.map.render(ctx); el.querySelector('.map-card').innerHTML = tmp.querySelector('.map-card').innerHTML; },
    unmount(el) { el._map && el._map.destroy(); }
  };

  const chain = legs => `<div class="chain">${legs.map((l, j) => `${j ? '<i class="chain-gap"></i>' : ''}${badge(l.code || l.line_code, l.color || l.line_color)}<span class="chain-leg"><b>${esc(l.direction)}</b><small>${l.minutes} min${l.status && l.status !== 'normal' ? ' · ' + esc(l.status) : ''}</small></span>`).join('')}</div>`;

  S.alternatives = {
    render(ctx) {
      const a = ctx.data.alternatives;
      return html`<div class="page sheet">
        <div class="grab"></div>
        ${top('Alternativas', { back: 'board' })}
        <div class="scroll">
          <div class="card affected">${parts.icon('warn')}<div><b>Línea ${a.affected.map(x => esc(x.line_code)).join(', ')} ${esc(a.affected[0].label)}</b><span>tu ruta tarda ${a.baseline_minutes} min cuando funciona</span></div></div>
          ${a.options.map(o => html`<article class="card alt ${o.usable ? '' : 'is-unusable'}">
            <header><span class="num-md">${o.total_minutes}<small>min</small></span><span class="delta">${o.delta_minutes != null ? '+' + o.delta_minutes + ' min' : ''}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
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
        ${top('Rutas', { right: `<button class="tb" data-go="route-edit">${parts.icon('plus')}</button>` })}
        <div class="scroll">
          <p class="kicker pad">Se elige sola según el día y la hora</p>
          ${rs.routes.map(r => html`<article class="card route ${r.id === rs.active_id ? 'is-active' : ''}" data-go="route-edit">
            <div class="route-thread"><i class="rt-dot"></i>${r.legs.map(l => `<i class="rt-line" style="--lc:${line.color(l.line_color)}"></i>${badge(l.line_code, l.line_color, 'badge-sm')}`).join('')}<i class="rt-line" style="--lc:${line.color(r.legs[r.legs.length - 1].line_color)}"></i><i class="rt-dot rt-end"></i>${r.id === rs.active_id ? '<span class="tag">ahora</span>' : ''}</div>
            <h3>${esc(r.name)}</h3><p>${esc(r.origin_name)} → ${esc(r.dest_name)}</p><small>${fmt.daysLabel(r.days)} · ${fmt.scheduleLabel(r)}</small>
          </article>`)}
          <button class="btn btn-ghost btn-wide" data-go="plan">${parts.icon('search')} Crear desde el planificador</button>
        </div>
      </div>`;
    }
  };

  S['route-edit'] = {
    render(ctx) {
      const r = ctx.data.routes.routes[1]; const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      return html`<div class="page">
        ${top('Editar ruta', { back: 'routes', right: '<button class="tb tb-text" data-go="routes" data-back>Guardar</button>' })}
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
          <p class="kicker pad">Tramos, en orden</p>
          <div class="thread thread-edit">
            ${r.legs.map((l, i) => html`<section class="tl-leg" style="--lc:${line.color(l.line_color)};--li:${line.ink(l.line_color)};--i:${i}"><div class="tl-node">${badge(l.line_code, l.line_color, 'badge-lg')}</div><div class="tl-rail"><i></i></div><div class="tl-body leg-edit"><div><b>${esc(l.from_name)} → ${esc(l.to_name)}</b><small>${l.directions.length ? 'dirección ' + esc(l.directions.join(' · ')) : 'cualquier sentido'}</small></div><button class="tb" aria-label="quitar">${parts.icon('x')}</button></div></section>`)}
            <section class="tl-leg tl-end" style="--i:${r.legs.length}"><div class="tl-node"><i class="end-dot end-add">${parts.icon('plus')}</i></div><div class="tl-body tl-body-end"><button class="btn btn-ghost">Añadir tramo</button></div></section>
          </div>
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
        ${top('Buscar')}
        <div class="scroll">
          <div class="card form plan-form">
            <div class="plan-thread"><i class="rt-dot"></i><i class="rt-line" style="--lc:var(--ink-3)"></i><i class="rt-dot rt-end"></i></div>
            <div><label class="field"><span>Desde</span><input value="Argenteuil"></label><label class="field"><span>Hasta</span><input value="Montparnasse" placeholder="Dirección, parada o sitio"></label></div>
          </div>
          <div class="plan-when"><span>${parts.icon('clock')} Salir ahora</span><button class="btn btn-small btn-ghost">Cambiar</button></div>
          <p class="kicker pad">Resultados · <span data-age>hace 1 s</span></p>
          ${p.options.map(o => html`<article class="card alt">
            <header><span class="num-md">${o.minutes}<small>min</small></span><span class="tag">${kind[o.kind] || o.kind}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
            ${chain(o.legs)}
            <footer><span>${fmt.transfers(o.transfers)} · ${o.walk_minutes} min a pie</span><button class="btn btn-small btn-primary" data-go="routes">Guardar ruta</button></footer>
          </article>`)}
        </div>
      </div>`;
    }
  };

  S.stats = {
    render(ctx) {
      const st = ctx.data.stats, pm = ctx.data.platformModel; const maxShare = Math.max(...st.by_month.map(m => m.bad_days / m.total_days));
      return html`<div class="page">
        ${top('Historial')}
        <div class="scroll">
          <div class="tiles">
            <div class="card tile"><span class="num-md">${st.overall.n}</span><span>días con datos</span></div>
            <div class="card tile"><span class="num-md">${st.overall.avg_delay.toFixed(1)}<small>min</small></span><span>retraso medio</span></div>
            <div class="card tile"><span class="num-md">${Math.round(st.overall.max_delay)}<small>min</small></span><span>peor día</span></div>
          </div>
          <p class="kicker pad">Días con incidencias</p>
          <div class="card">${st.by_month.map(m => html`<div class="bar"><span class="bar-lbl">${fmt.monthLabel(m.month)}</span><span class="bar-track"><i style="width:${(m.bad_days / m.total_days / maxShare * 100).toFixed(0)}%"></i></span><b>${m.bad_days}<small>/${m.total_days}</small></b></div>`)}</div>
          <p class="kicker pad">Qué línea falla más</p>
          <div class="card">${st.by_line.map(l => { const r = ctx.data.routes.routes.flatMap(x => x.legs).find(x => x.line_code === l.worst_line); return html`<div class="line-stat">${badge(l.worst_line, r ? r.line_color : '')}<div><b>${l.n} días</b> como peor línea<small>retraso medio ${l.avg_delay.toFixed(1)} min</small></div></div>`; })}</div>
          <p class="kicker pad">Previsión de vía</p>
          <div class="card accuracy"><span class="num-lg">${fmt.percent(pm.accuracy.rate)}</span><div><b>${pm.accuracy.hits} aciertos de ${pm.accuracy.predictions}</b><small>${pm.accuracy.observations} trenes en ${pm.accuracy.days} días · el servidor se puntúa solo</small>${pm.coverage.map(c => `<div class="cov">${badge(c.line_code, c.line_code === 'J' ? 'CEC73D' : '640082', 'badge-sm')}<span>${c.observations ? `${c.observations} observaciones · ${c.platforms} vías` : 'no publica vía'}</span></div>`).join('')}</div></div>
        </div>
      </div>`;
    }
  };

  S.settings = {
    render(ctx) {
      const h = ctx.data.health;
      const q = k => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${h.quota[k] / 10}%"></i></span><b>${h.quota[k]}</b></div>`;
      return html`<div class="page">
        ${top('Ajustes', { back: 'board' })}
        <div class="scroll">
          <p class="kicker pad">Servidor</p>
          <div class="card list">
            <div class="li"><span>Red de casa</span><b>192.168.1.188:7796</b><i class="dot ok"></i></div>
            <div class="li"><span>Tailscale</span><b>100.99.38.76:7796</b><i class="dot ${ctx.s.offline ? 'bad' : 'ok'}"></i></div>
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
          <p class="foot">Trajet 2.0 · dirección D «Hilo»</p>
        </div>
      </div>`;
    }
  };

  const activity = (ctx, cls = '') => {
    const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; if (!dep) return '';
    const m = T.moment(dep);
    return html`<div class="la ${cls}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
      <div class="la-thread"><i class="la-dot"></i><i class="la-line" data-progress="${dep.jid}" data-total="900"><b></b></i>${badge(leg.line_code, leg.line_color, 'badge-sm')}</div>
      <div class="la-body"><b>${esc(dep.destination)}</b><span><span data-dep-at="${dep.jid}">${dep.at}</span> · <span data-countdown="${dep.jid}">${fmt.mmss(dep._seconds)}</span></span></div>
      <div class="la-right"><span class="la-num"><b class="num" data-dep-min="${dep.jid}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></span>${via(dep, leg)}</div>
    </div>`;
  };
  S.live = {
    hidesStatus: true,
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep; const m = dep ? T.moment(dep) : null;
      return html`<div class="lock">
        <div class="lock-top"><span class="lock-date">martes 23 de septiembre</span><b class="lock-time" data-clock>${fmt.hhmm(ctx.now)}</b></div>
        ${activity(ctx, 'la-lock')}
        <div class="lock-bottom"><span></span><span></span></div>
        <div class="di-show">
          <p class="kicker">Dynamic Island</p>
          <div class="di-row"><span>compacta</span><div class="di di-compact">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b><em class="${dep && dep.platform ? 'is-real' : ''}">${dep && dep.platform ? 'Vía ' + esc(dep.platform) : (dep && dep.guess ? '¿' + esc(dep.guess.platform) + '?' : '')}</em></div></div>
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
          <div class="widget w-small" style="--lc:#CEC73D;--li:#000"><div class="w-thread"><i class="rt-dot"></i><i class="rt-line" style="--lc:#CEC73D"></i>${badge('J', 'CEC73D', 'badge-sm')}</div><b class="num" data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small>${dep ? via(dep, leg) : ''}<span class="w-foot">Argenteuil</span></div>
          <div class="hs-apps">${app('Mail')}${app('Fotos')}${app('Notas')}${app('Mapas')}</div>
          <div class="widget w-medium">
            <div class="w-head"><div class="w-thread"><i class="rt-dot"></i><i class="rt-line" style="--lc:#CEC73D"></i>${badge('J', 'CEC73D', 'badge-sm')}<i class="rt-line" style="--lc:#CEC73D"></i><i class="rt-dot rt-end"></i></div><span>Saint-Lazare → Argenteuil</span><span class="live"><i></i></span></div>
            <div class="w-rows">${(leg ? leg.departures.slice(0, 3) : []).map(d => `<div class="w-row"><b data-dep-min="${d.jid}">${T.moment(d).text}</b><small data-dep-unit="${d.jid}">${T.moment(d).unit}</small><span>${d.at}</span>${via(d, leg)}</div>`).join('')}</div>
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
          <header class="panel-head"><div class="panel-logo"><span class="logo-thread"><i style="--lc:#CEC73D"></i><i style="--lc:#82C8E6"></i></span><b>Trajet · servidor</b></div><span class="live"><i></i> en marcha</span></header>
          <div class="panel-grid">
            <section class="card pcard pcard-qr"><h3>Emparejar un iPhone</h3>${parts.qr(180, '#0b0d14', '#fff')}<p>Escanea desde la app. Caduca en <b>5:00</b>.</p><button class="btn btn-small btn-primary">Nuevo código</button></section>
            <section class="card pcard"><h3>Dispositivos</h3>${a.devices.map(d => html`<div class="dev ${d.active ? '' : 'is-off'}">${parts.icon('phone')}<div><b>${esc(d.name)}</b><small>${d.via} · ${d.last_seen}</small></div><button class="btn btn-small btn-ghost">Quitar</button></div>`)}</section>
            <section class="card pcard"><h3>Cuota PRIM · hoy</h3>${Object.entries(h.quota).map(([k, v]) => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${v / 10}%"></i></span><b>${v}</b></div>`)}<div class="spark">${a.quotaHistory.map(v => `<i style="height:${v / max * 100}%"></i>`).join('')}</div><small>llamadas usadas, últimos 7 días</small></section>
            <section class="card pcard"><h3>IA local</h3><div class="dev">${parts.icon('brain')}<div><b>${h.translator.model}</b><small>${h.translator.reason}</small></div><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div><p>Traduce los avisos del francés. Si se para, la app enseña el francés y avisa.</p></section>
            <section class="card pcard"><h3>Aprendizaje de andenes</h3><div class="tiles"><div class="tile"><span class="num-md">${fmt.percent(a.learning.hits / a.learning.predictions)}</span><span>acierto</span></div><div class="tile"><span class="num-md">${a.learning.observations}</span><span>trenes</span></div><div class="tile"><span class="num-md">${a.learning.days}</span><span>días</span></div></div></section>
            <section class="card pcard"><h3>Estado</h3><div class="li"><span>Clave PRIM</span><b>${h.key_configured ? 'configurada' : 'falta'}</b></div><div class="li"><span>Hora en París</span><b data-clock>${fmt.hhmm(ctx.now)}</b></div><div class="li"><span>Último error</span><b>${h.last_error || 'ninguno'}</b></div></section>
          </div>
          <p class="foot">Panel solo accesible desde la red de casa o la tailnet.</p>
        </div>
      </div>`;
    }
  };

  T.app.register({
    id: 'd', name: 'Hilo', home: 'board', screens: S,
    tabbar: () => html`<div class="tabs"><i class="tabs-bead"></i>
      <button data-go="board" data-go-group="alternatives settings" class="is-active">${parts.icon('clock')}<span>Tablero</span></button>
      <button data-go="map">${parts.icon('map')}<span>Trayecto</span></button>
      <button data-go="routes" data-go-group="route-edit">${parts.icon('routes')}<span>Rutas</span></button>
      <button data-go="plan">${parts.icon('search')}<span>Buscar</span></button>
      <button data-go="stats">${parts.icon('chart')}<span>Historial</span></button>
    </div>`,
    onNavigate(id) {
      // la cuenta del tab bar se desliza hasta la pestaña activa
      const tb = T.app.tabbarEl; if (!tb) return;
      const btns = [...tb.querySelectorAll('button')];
      const idx = btns.findIndex(b => b.classList.contains('is-active'));
      tb.querySelector('.tabs-bead').style.setProperty('--idx', Math.max(0, idx));
    }
  });
})();
