/* Dirección E · «Bento»
   Rejilla densa: cada celda responde a una pregunta («¿cuánto?», «¿corro?»,
   «¿qué vía?», «¿qué falla?», «¿dónde?»). Cifras en monoespaciada, etiquetas
   en versalitas, celdas con borde fino y sin sombras. Movimiento: las celdas
   entran escalonadas, las cifras cambian con un giro de rueda y el LED de
   «en directo» parpadea. */
(() => {
  'use strict';
  const T = window.Trajet, { html, esc, parts, fmt, line } = T;
  const M = window.TrajetMap;

  const TINT = {
    light: { land: '#f1f2f4', water: '#c8d8e6', park: '#dfe8dc', building: '#e6e8ea', road: '#ffffff', roadCasing: '#d5d8dc', rail: '#c9ccd1', text: '#2b2f36', halo: '#ffffff' },
    dark:  { land: '#131316', water: '#101820', park: '#141a15', building: '#1a1a1e', road: '#27272c', roadCasing: '#0e0e10', rail: '#2f2f35', text: '#c0c2c8', halo: '#131316' }
  };
  const mapOpts = (ctx, extra = {}) => Object.assign({
    theme: ctx.s.theme, tint: TINT, labels: true, casing: true, routeWidth: 6, stopRadius: 5, labelSize: 11,
    stopFill: ctx.s.theme === 'dark' ? '#131316' : '#fff', meColor: '#ff453a'
  }, extra);

  // ---------------------------------------------------------------- piezas
  const badge = (code, color, cls = '') => `<span class="badge ${cls}" style="--lc:${line.color(color)};--li:${line.ink(color)}">${esc(code || '?')}</span>`;
  const via = (dep, leg) => {
    if (!line.publishesPlatform(leg.line_mode)) return '';
    if (dep.platform) return `<span class="via via-real${dep._isNew ? ' is-new' : ''}"><small>VÍA</small><b>${esc(dep.platform)}</b></span>`;
    if (dep.guess) return `<span class="via via-guess"><small>PROB.</small><b>${esc(dep.guess.platform)}</b><i>${Math.round(dep.guess.share * 100)}%</i></span>`;
    return '';
  };
  const mono = (dep, cls = '') => { const m = T.moment(dep); return `<span class="mono ${cls}"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></span>`; };
  const tile = (cls, inner, i = 0, attrs = '') => `<div class="tile ${cls}" style="--i:${i}" ${attrs}>${inner}</div>`;
  const lbl = t => `<span class="lbl">${t}</span>`;

  const notice = leg => {
    const st = leg.status; if (!st.level && !st.messages.length) return '';
    return html`<div class="notice lvl-${st.level}">${lbl(`${parts.icon('warn')} ${esc(st.label)}${T.awaitingTranslation(st) ? ' · <em class="translating">TRADUCIENDO<i>_</i></em>' : ''}`)}
      ${T.visibleMessages(st).map(m => `<p lang="${m.translated ? 'es' : 'fr'}" class="${m.translated ? '' : 'is-fr'}">${esc(m.text)}</p>`)}</div>`;
  };

  /** El tramo principal ocupa varias celdas; los siguientes, una fila compacta. */
  const heroTiles = (leg, i0) => {
    const d = leg.departures[0]; if (!d) return tile('span2 tile-empty', `${lbl(`${badge(leg.line_code, leg.line_color, 'badge-sm')} ${esc(leg.from_name)} → ${esc(leg.to_name || '')}`)}<b class="empty-b">SIN PRÓXIMOS PASOS</b><span class="sub">${leg.status.level >= 2 ? 'servicio interrumpido' : 'nada anunciado ahora mismo'}</span>${notice(leg)}`, i0);
    const m = T.moment(d);
    const hero = tile(`span2 tile-hero${d.at_stop ? ' is-atstop' : ''}`, html`
      ${lbl(`${badge(leg.line_code, leg.line_color, 'badge-sm')} ${esc(leg.from_name)} → ${esc(leg.to_name || leg.directions[0] || '')}`)}
      <div class="hero-row">
        ${mono(d, 'mono-xl')}
        <div class="hero-side">${via(d, leg)}<span class="hero-dest">${esc(d.destination)}</span><span class="sub"><span data-dep-at="${d.jid}">${d.at}</span>${d.length ? ' · tren ' + (d.length === 'short' ? 'corto' : 'largo') : ''}${d.delay > 0 && d.aimed_at ? ` · <em class="late">${fmt.delay(d.delay)}</em>` : ''}${d.at_stop ? ' · <em class="ok">EN EL ANDÉN</em>' : ''}</span></div>
      </div>`, i0, `style="--i:${i0};--lc:${line.color(leg.line_color)}"`);
    const pace = tile('tile-pace', `${lbl('¿CORRO?')}<b class="pace-word" data-pace="${d.jid}" data-value="${m.pace ? m.pace.id : 'none'}" data-pace-label="short">${m.pace ? m.pace.short : '—'}</b><span class="pace-ico" data-pace="${d.jid}" data-value="${m.pace ? m.pace.id : 'none'}">${parts.icon('run')}${parts.icon('walk')}${parts.icon('cup')}</span>`, i0 + 1);
    const next = tile('tile-next', `${lbl('SIGUIENTES')}<div class="next-rows">${leg.departures.slice(1, 4).map(x => `<div class="next-row">${mono(x)}<span class="sub" data-dep-at="${x.jid}">${x.at}</span>${via(x, leg)}${x.delay > 0 && x.aimed_at ? `<em class="late">${fmt.delay(x.delay)}</em>` : ''}</div>`).join('') || '<span class="sub">—</span>'}</div>`, i0 + 2);
    const nt = leg.status.level || leg.status.messages.length ? tile('span2 tile-notice', notice(leg), i0 + 3) : '';
    return hero + pace + next + nt;
  };
  const legRowTile = (leg, i) => tile(`span2 tile-leg`, html`${lbl(`${badge(leg.line_code, leg.line_color, 'badge-sm')} ${esc(leg.from_name)} → ${esc(leg.to_name || leg.directions[0] || '')}`)}
    ${leg.departures.length ? `<div class="leg-row">${leg.departures.slice(0, 4).map((d, j) => `<span class="leg-dep${j ? '' : ' is-first'}">${mono(d, j ? 'mono-sm' : 'mono-md')}<span class="sub" data-dep-at="${d.jid}">${d.at}</span>${via(d, leg)}</span>`).join('')}</div>` : `<b class="empty-b">SIN PRÓXIMOS PASOS</b><span class="sub">${leg.status.level >= 2 ? 'servicio interrumpido' : 'nada anunciado'}</span>`}
    ${notice(leg)}`, i, `style="--i:${i};--lc:${line.color(leg.line_color)}"`);

  const top = (title, { back = null, right = '' } = {}) => html`<header class="top">${back ? `<button class="tb" data-go="${back}" data-back>${parts.icon('back')}</button>` : ''}<h1>${title}</h1>${right}</header>`;

  // ---------------------------------------------------------------- pantallas
  const S = {};
  S.pair = {
    render: () => html`<div class="page pair">
      ${top('EMPAREJAR')}
      <div class="grid">
        ${tile('span2 tile-cam', `<div class="cam">${parts.qr(150, '#101012', '#fff')}<div class="cam-frame"></div><div class="cam-scan"></div></div>`, 0)}
        ${tile('span2', `${lbl('ESTADO')}<p class="pair-state" data-state="scan"><span data-s="scan">Buscando el código…</span><span data-s="connecting">Conectando con umbrel:7796…</span><span data-s="ready">${parts.icon('check')} Listo · iPhone de Isma emparejado</span></p>`, 1)}
        ${tile('span2 tile-btn', `<button class="btn btn-primary" data-pair>ESCANEAR</button>`, 2)}
        ${tile('span2 tile-btn', `<button class="btn" data-go="settings">DIRECCIÓN A MANO</button>`, 3)}
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
      let i = 0; let tiles = '';
      b.legs.forEach((leg, k) => { if (k === 0) { tiles += heroTiles(leg, i); i += 4; } else { tiles += legRowTile(leg, i); i += 1; } });
      return html`<div class="page board">
        <header class="top top-board"><div><span class="lbl">${b.auto_selected ? 'LA QUE TOCA AHORA' : 'RUTA'} · <span data-clock>${fmt.hhmm(ctx.now)}</span></span><h1>${esc(b.route.name)}</h1></div><button class="tb" data-go="settings" aria-label="Ajustes">${parts.icon('gear')}</button></header>
        <div class="scroll"><div class="grid">
          ${tiles}
          ${tile('tile-map', `<div class="mini-map" id="map-e-mini"></div>${lbl('TRAYECTO')}`, i, 'data-go="map"')}
          ${tile(`tile-state ${b.stale ? 'is-stale' : ''}`, b.stale ? `${lbl('SIN CONEXIÓN')}<b class="state-b">${parts.icon('wifiOff')}</b><span class="sub">último tablero <b data-age>${fmt.age(b.data_age)}</b></span>` : `${lbl('<i class="led"></i> EN DIRECTO')}<b class="state-b" data-age>${fmt.age(b.data_age)}</b><span class="sub">${fmt.quota(b.quota['stop-monitoring'])}</span><span class="qbar"><i style="width:${b.quota['stop-monitoring'] / 10}%"></i></span>`, i + 1)}
          ${tile(`span2 tile-btn ${cut ? 'is-urgent' : ''}`, `<button class="btn ${cut ? 'btn-danger' : ''}" data-go="alternatives" data-sheet>${parts.icon('swap')} BUSCAR ALTERNATIVA${cut ? ' · LÍNEA ' + esc(b.worst_line) + ' CORTADA' : ''}</button>`, i + 2)}
        </div><p class="foot">se refresca cada 30 s mientras miras</p></div>
      </div>`;
    },
    mount(el, ctx) { const mm = el.querySelector('#map-e-mini'); if (mm) el._mini = M.mount(mm, mapOpts(ctx, { forceSVG: true, labels: false, animate: false, routeWidth: 3, stopRadius: 2.5, showTransfer: false, padding: { top: 14, bottom: 34, left: 14, right: 14 } })); },
    unmount(el) { el._mini && el._mini.destroy(); }
  };

  S.map = {
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg, s = ctx.s;
      return html`<div class="mapscr">
        <div class="map" id="map-e"></div>
        <div class="map-top"><button class="tb tb-solid" data-go="board" data-back>${parts.icon('back')}</button><div class="tile tile-inline">${badge('J', 'CEC73D', 'badge-sm')}<span>SAINT-LAZARE → ARGENTEUIL</span></div><div class="tile tile-inline">${parts.icon('walk')} ${ctx.data.lineJ.walkMinutes} min</div></div>
        <div class="map-grid grid">
          ${dep ? tile('tile-hero', `${lbl('PRÓXIMO')}<div class="hero-row">${mono(dep, 'mono-lg')}<div class="hero-side">${via(dep, leg)}<span class="sub" data-dep-at="${dep.jid}">${dep.at}</span></div></div>`, 0, `style="--i:0;--lc:#CEC73D"`) : tile('', '<b class="empty-b">SIN PASOS</b>', 0)}
          ${tile('tile-stops', `${lbl('PARADAS')}<div class="stops">${ctx.data.lineJ.stops.filter(x => x.served).map(x => `<span class="${x.dest ? 'is-dest' : ''}">${esc(x.name.replace('Paris ', '').replace('-sur-Seine', ''))}</span>`).join('')}</div>`, 1)}
          ${tile('span2 tile-btn', s.trip ? `<button class="btn btn-danger" data-scenario="trip=false">${parts.icon('stop')} PARAR TRAYECTO · se apaga al llegar</button>` : `<button class="btn btn-primary" data-scenario="trip=true">${parts.icon('play')} INICIAR TRAYECTO</button>`, 2)}
        </div>
      </div>`;
    },
    mount(el, ctx) { el._map = M.mount(el.querySelector('#map-e'), mapOpts(ctx, { padding: { top: 120, bottom: 290, left: 40, right: 40 } })); },
    update(el, ctx) { el._map && el._map.setTheme(ctx.s.theme); const tmp = document.createElement('div'); tmp.innerHTML = S.map.render(ctx); el.querySelector('.map-grid').innerHTML = tmp.querySelector('.map-grid').innerHTML; },
    unmount(el) { el._map && el._map.destroy(); }
  };

  const chain = legs => `<div class="chain">${legs.map((l, j) => `${j ? '<i>›</i>' : ''}${badge(l.code || l.line_code, l.color || l.line_color, 'badge-sm')}<span>${esc(l.direction)}<small>${l.minutes} min${l.status && l.status !== 'normal' ? ' · ' + esc(l.status) : ''}</small></span>`).join('')}</div>`;

  S.alternatives = {
    render(ctx) {
      const a = ctx.data.alternatives;
      return html`<div class="page">
        ${top('ALTERNATIVAS', { back: 'board' })}
        <div class="scroll"><div class="grid">
          ${tile('span2 tile-bad', `${lbl(`${parts.icon('warn')} LÍNEA ${a.affected.map(x => esc(x.line_code)).join(', ')} ${esc(a.affected[0].label).toUpperCase()}`)}<span class="sub">tu ruta tarda ${a.baseline_minutes} min cuando funciona</span>`, 0)}
          ${a.options.map((o, i) => tile(`span2 tile-alt ${o.usable ? '' : 'is-unusable'}`, html`
            <div class="alt-head"><span class="mono mono-md"><b>${o.total_minutes}</b><small>min</small></span><em class="delta">${o.delta_minutes != null ? '+' + o.delta_minutes : ''}</em><span class="sub">${o.departure} → ${o.arrival} · ${fmt.transfers(o.transfers)}</span>${o.usable ? `<button class="btn btn-small btn-primary" data-go="board" data-back>USAR</button>` : `<span class="lbl bad">PASA POR LA CORTADA</span>`}</div>
            ${chain(o.legs)}`, i + 1)).join('')}
        </div></div>
      </div>`;
    }
  };

  S.routes = {
    render(ctx) {
      const rs = ctx.data.routes;
      return html`<div class="page">
        ${top('RUTAS', { right: `<button class="tb" data-go="route-edit">${parts.icon('plus')}</button>` })}
        <div class="scroll"><div class="grid">
          ${rs.routes.map((r, i) => tile(`span2 tile-route ${r.id === rs.active_id ? 'is-active' : ''}`, html`
            ${lbl(`${r.legs.map(l => badge(l.line_code, l.line_color, 'badge-sm')).join(' ')} ${r.id === rs.active_id ? '<em class="tag">AHORA</em>' : ''}`)}
            <h3>${esc(r.name)}</h3><span class="sub">${esc(r.origin_name)} → ${esc(r.dest_name)}</span><span class="sub mono-lbl">${fmt.daysLabel(r.days).toUpperCase()} · ${fmt.scheduleLabel(r).toUpperCase()}</span>`, i, 'data-go="route-edit"')).join('')}
          ${tile('span2 tile-btn', `<button class="btn" data-go="plan">${parts.icon('search')} CREAR DESDE EL PLANIFICADOR</button>`, 4)}
        </div></div>
      </div>`;
    }
  };

  S['route-edit'] = {
    render(ctx) {
      const r = ctx.data.routes.routes[1]; const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      return html`<div class="page">
        ${top('EDITAR RUTA', { back: 'routes', right: '<button class="tb tb-text" data-go="routes" data-back>GUARDAR</button>' })}
        <div class="scroll"><div class="grid">
          ${tile('span2', `<label class="field">${lbl('NOMBRE')}<input value="${esc(r.name)}"></label>`, 0)}
          ${tile('', `<label class="field">${lbl('ORIGEN')}<input value="${esc(r.origin_name)}"></label>`, 1)}
          ${tile('', `<label class="field">${lbl('DESTINO')}<input value="${esc(r.dest_name)}"></label>`, 2)}
          ${tile('span2', `${lbl('DÍAS')}<div class="days">${days.map((d, i) => `<button class="day ${r.days.includes(i) ? 'is-on' : ''}" data-toggle>${d}</button>`).join('')}</div>`, 3)}
          ${tile('span2', `${lbl('CUÁNDO TOCA')}<div class="seg"><button class="${r.time_mode === 'window' ? 'is-on' : ''}">FRANJA</button><button class="${r.time_mode === 'arrival' ? 'is-on' : ''}">LLEGAR A</button><button class="${r.time_mode === 'departure' ? 'is-on' : ''}">SALIR A</button></div><div class="times"><input value="${r.time_from}"><span>→</span><input value="${r.time_to}"></div>`, 4)}
          ${r.legs.map((l, i) => tile('span2 tile-legedit', `${badge(l.line_code, l.line_color)}<div><b>${esc(l.from_name)} → ${esc(l.to_name)}</b><span class="sub">${l.directions.length ? 'dirección ' + esc(l.directions.join(' · ')) : 'cualquier sentido'}</span></div><button class="tb" aria-label="quitar">${parts.icon('x')}</button>`, 5 + i)).join('')}
          ${tile('tile-btn', `<button class="btn">${parts.icon('plus')} TRAMO</button>`, 8)}
          ${tile('tile-btn', `<button class="btn btn-danger-text">ELIMINAR</button>`, 9)}
        </div></div>
      </div>`;
    },
    mount(el) { el.querySelectorAll('[data-toggle]').forEach(b => b.addEventListener('click', () => b.classList.toggle('is-on'))); el.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => { b.parentElement.querySelectorAll('button').forEach(x => x.classList.remove('is-on')); b.classList.add('is-on'); })); }
  };

  S.plan = {
    render(ctx) {
      const p = ctx.data.plan; const kind = { best: 'MÁS RÁPIDO', less_fallback: 'MENOS TRANSBORDOS', less_walk: 'MENOS A PIE' };
      return html`<div class="page">
        ${top('BUSCAR')}
        <div class="scroll"><div class="grid">
          ${tile('', `<label class="field">${lbl('DESDE')}<input value="Argenteuil"></label>`, 0)}
          ${tile('', `<label class="field">${lbl('HASTA')}<input value="Montparnasse"></label>`, 1)}
          ${tile('span2 tile-inline-row', `${lbl('CUÁNDO')}<span>Salir ahora</span><button class="btn btn-small">CAMBIAR</button>`, 2)}
          ${p.options.map((o, i) => tile('span2 tile-alt', html`
            <div class="alt-head"><span class="mono mono-md"><b>${o.minutes}</b><small>min</small></span><em class="tag">${kind[o.kind] || o.kind}</em><span class="sub">${o.departure} → ${o.arrival} · ${fmt.transfers(o.transfers)} · ${o.walk_minutes} min a pie</span><button class="btn btn-small btn-primary" data-go="routes">GUARDAR</button></div>
            ${chain(o.legs)}`, 3 + i)).join('')}
        </div></div>
      </div>`;
    }
  };

  S.stats = {
    render(ctx) {
      const st = ctx.data.stats, pm = ctx.data.platformModel; const maxShare = Math.max(...st.by_month.map(m => m.bad_days / m.total_days));
      return html`<div class="page">
        ${top('HISTORIAL')}
        <div class="scroll"><div class="grid">
          ${tile('', `${lbl('DÍAS CON DATOS')}<span class="mono mono-lg"><b>${st.overall.n}</b></span>`, 0)}
          ${tile('', `${lbl('RETRASO MEDIO')}<span class="mono mono-lg"><b>${st.overall.avg_delay.toFixed(1)}</b><small>min</small></span>`, 1)}
          ${tile('span2', `${lbl('DÍAS CON INCIDENCIAS')}<div class="bars">${st.by_month.map(m => `<div class="bar"><span class="sub">${fmt.monthLabel(m.month)}</span><span class="bar-track"><i style="width:${(m.bad_days / m.total_days / maxShare * 100).toFixed(0)}%"></i></span><span class="mono mono-sm"><b>${m.bad_days}</b><small>/${m.total_days}</small></span></div>`).join('')}</div>`, 2)}
          ${tile('span2', `${lbl('QUÉ LÍNEA FALLA MÁS')}${st.by_line.map(l => { const r = ctx.data.routes.routes.flatMap(x => x.legs).find(x => x.line_code === l.worst_line); return `<div class="line-stat">${badge(l.worst_line, r ? r.line_color : '', 'badge-sm')}<span class="mono mono-sm"><b>${l.n}</b><small>días</small></span><span class="sub">retraso medio ${l.avg_delay.toFixed(1)} min</span></div>`; }).join('')}`, 3)}
          ${tile('', `${lbl('ACIERTO DE VÍA')}<span class="mono mono-lg"><b>${fmt.percent(pm.accuracy.rate).replace(' ', '')}</b></span><span class="sub">${pm.accuracy.hits} de ${pm.accuracy.predictions}</span>`, 4)}
          ${tile('', `${lbl('OBSERVADOS')}<span class="mono mono-lg"><b>${pm.accuracy.observations}</b></span><span class="sub">en ${pm.accuracy.days} días · ${pm.coverage.find(c => c.line_code === 'J').platforms} vías</span>`, 5)}
          ${tile('span2', `<span class="sub">El servidor se puntúa solo con /api/platform-model; la app no pregunta nunca si acertó.</span>`, 6)}
        </div></div>
      </div>`;
    }
  };

  S.settings = {
    render(ctx) {
      const h = ctx.data.health;
      const q = k => `<div class="bar"><span class="sub">${k}</span><span class="bar-track"><i style="width:${h.quota[k] / 10}%"></i></span><span class="mono mono-sm"><b>${h.quota[k]}</b></span></div>`;
      return html`<div class="page">
        ${top('AJUSTES', { back: 'board' })}
        <div class="scroll"><div class="grid">
          ${tile('', `${lbl('RED DE CASA')}<span class="mono mono-sm addr"><b>192.168.1.188</b><small>:7796</small></span><i class="dot ok"></i>`, 0)}
          ${tile('', `${lbl('TAILSCALE')}<span class="mono mono-sm addr"><b>100.99.38.76</b><small>:7796</small></span><i class="dot ${ctx.s.offline ? 'bad' : 'ok'}"></i>`, 1)}
          ${tile('tile-btn', `<button class="btn" data-go="pair">${parts.icon('qr')} EMPAREJAR</button>`, 2)}
          ${tile('tile-btn', `<button class="btn" data-go="panel">${parts.icon('server')} PANEL</button>`, 3)}
          ${tile('span2', `${lbl('CUOTA PRIM · QUEDAN HOY')}<div class="bars">${q('stop-monitoring')}${q('general-message')}${q('navitia')}</div>`, 4)}
          ${tile('span2 tile-inline-row', `${lbl('TRADUCTOR')}<span>${h.translator.model} · ${h.translator.ok ? 'listo' : 'parado'}</span><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i>`, 5)}
          ${tile('span2 tile-inline-row', `${lbl('ASPECTO')}<div class="seg seg-sm"><button class="${ctx.s.theme === 'light' ? 'is-on' : ''}" data-scenario="theme=light">CLARO</button><button class="${ctx.s.theme === 'dark' ? 'is-on' : ''}" data-scenario="theme=dark">OSCURO</button></div>`, 6)}
          ${tile('span2 tile-inline-row', `${lbl('PANTALLA ENCENDIDA EN EL TABLERO')}<i class="sw is-on"></i>`, 7)}
          ${tile('span2 tile-inline-row', `${lbl('VIBRAR CUANDO APARECE LA VÍA')}<i class="sw is-on"></i>`, 8)}
          ${tile('tile-btn', `<button class="btn" data-go="live">LIVE ACTIVITY</button>`, 9)}
          ${tile('tile-btn', `<button class="btn" data-go="widgets">WIDGETS</button>`, 10)}
        </div><p class="foot">Trajet 2.0 · dirección E «Bento»</p></div>
      </div>`;
    }
  };

  const activity = (ctx, cls = '') => {
    const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; if (!dep) return '';
    return html`<div class="la ${cls}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
      <div class="la-cell la-main">${lbl(`${badge(leg.line_code, leg.line_color, 'badge-sm')} ${esc(dep.destination)}`)}${mono(dep, 'mono-lg')}</div>
      <div class="la-cell la-via">${lbl('VÍA')}${via(dep, leg) || '<span class="sub">—</span>'}</div>
      <div class="la-cell la-time">${lbl('SALE')}<span class="mono mono-sm"><b data-dep-at="${dep.jid}">${dep.at}</b></span><span class="sub" data-countdown="${dep.jid}">${fmt.mmss(dep._seconds)}</span></div>
      <div class="la-bar" data-progress="${dep.jid}" data-total="900"><i></i></div>
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
          <p class="lbl">DYNAMIC ISLAND</p>
          <div class="di-row"><span>compacta</span><div class="di di-compact">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b><em class="${dep && dep.platform ? 'is-real' : ''}">${dep && dep.platform ? 'VÍA ' + esc(dep.platform) : (dep && dep.guess ? '?' + esc(dep.guess.platform) : '')}</em></div></div>
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
        <p class="lbl">PANTALLA DE INICIO</p>
        <div class="hs-grid">
          <div class="widget w-small" style="--lc:#CEC73D">${lbl(`${badge('J', 'CEC73D', 'badge-sm')} ARGENTEUIL`)}<span class="mono mono-xl"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small></span>${dep ? via(dep, leg) : ''}</div>
          <div class="hs-apps">${app('Mail')}${app('Fotos')}${app('Notas')}${app('Mapas')}</div>
          <div class="widget w-medium">
            ${lbl(`${badge('J', 'CEC73D', 'badge-sm')} SAINT-LAZARE → ARGENTEUIL <i class="led"></i>`)}
            <div class="w-grid">${(leg ? leg.departures.slice(0, 3) : []).map(d => `<div class="w-cell">${mono(d, 'mono-md')}<span class="sub">${d.at}</span>${via(d, leg)}</div>`).join('')}</div>
          </div>
          <div class="hs-apps">${app('Cámara')}${app('Ajustes')}${app('Reloj')}${app('Música')}</div>
        </div>
        <p class="lbl">PANTALLA DE BLOQUEO</p>
        <div class="ls-widgets">
          <div class="lsw lsw-circ"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small>J</small></div>
          <div class="lsw lsw-rect">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small><span>${dep && dep.platform ? 'VÍA ' + esc(dep.platform) : 'ARGENTEUIL'}</span></div>
          <div class="lsw lsw-inline">${badge('J', 'CEC73D', 'badge-sm')} <b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b> min · Argenteuil${dep && dep.platform ? ' · vía ' + esc(dep.platform) : ''}</div>
        </div>
      </div>`;
    }
  };

  S.panel = {
    hidesStatus: true,
    render(ctx) {
      const a = ctx.data.admin, h = ctx.data.health; const max = Math.max(...a.quotaHistory);
      return html`<div class="panel page">
        <div class="web-bar"><span>umbrel:7796/admin</span></div>
        <div class="scroll">
          <header class="panel-head"><div>${lbl('SERVIDOR')}<h1>TRAJET</h1></div><span class="lbl"><i class="led"></i> EN MARCHA · <span data-clock>${fmt.hhmm(ctx.now)}</span></span></header>
          <div class="grid panel-grid">
            ${tile('tile-qr', `${lbl('EMPAREJAR UN IPHONE')}${parts.qr(170, '#101012', '#fff')}<span class="sub">caduca en <b>5:00</b></span><button class="btn btn-small btn-primary">NUEVO CÓDIGO</button>`, 0)}
            ${tile('', `${lbl('DISPOSITIVOS')}${a.devices.map(d => `<div class="dev ${d.active ? '' : 'is-off'}">${parts.icon('phone')}<div><b>${esc(d.name)}</b><span class="sub">${d.via} · ${d.last_seen}</span></div><button class="btn btn-small">QUITAR</button></div>`).join('')}`, 1)}
            ${tile('', `${lbl('CUOTA PRIM · HOY')}<div class="bars">${Object.entries(h.quota).map(([k, v]) => `<div class="bar"><span class="sub">${k}</span><span class="bar-track"><i style="width:${v / 10}%"></i></span><span class="mono mono-sm"><b>${v}</b></span></div>`).join('')}</div><div class="spark">${a.quotaHistory.map(v => `<i style="height:${v / max * 100}%"></i>`).join('')}</div><span class="sub">llamadas usadas · 7 días</span>`, 2)}
            ${tile('', `${lbl('IA LOCAL')}<div class="dev">${parts.icon('brain')}<div><b>${h.translator.model}</b><span class="sub">${h.translator.reason}</span></div><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div><span class="sub">Traduce los avisos del francés. Si se para, la app enseña el francés y avisa.</span>`, 3)}
            ${tile('', `${lbl('ACIERTO DE ANDÉN')}<span class="mono mono-lg"><b>${fmt.percent(a.learning.hits / a.learning.predictions).replace(' ', '')}</b></span><span class="sub">${a.learning.observations} trenes en ${a.learning.days} días</span>`, 4)}
            ${tile('', `${lbl('ESTADO')}<div class="kv"><span>clave PRIM</span><b>${h.key_configured ? 'configurada' : 'falta'}</b></div><div class="kv"><span>último error</span><b>${h.last_error || 'ninguno'}</b></div><div class="kv"><span>hora París</span><b data-clock>${fmt.hhmm(ctx.now)}</b></div>`, 5)}
          </div>
          <p class="foot">solo desde la red de casa o la tailnet</p>
        </div>
      </div>`;
    }
  };

  T.app.register({
    id: 'e', name: 'Bento', home: 'board', screens: S,
    tabbar: () => html`<div class="tabs">
      <button data-go="board" data-go-group="alternatives settings" class="is-active">${parts.icon('clock')}<span>TABLERO</span></button>
      <button data-go="map">${parts.icon('map')}<span>MAPA</span></button>
      <button data-go="routes" data-go-group="route-edit">${parts.icon('routes')}<span>RUTAS</span></button>
      <button data-go="plan">${parts.icon('search')}<span>BUSCAR</span></button>
      <button data-go="stats">${parts.icon('chart')}<span>DATOS</span></button>
    </div>`
  });
})();
