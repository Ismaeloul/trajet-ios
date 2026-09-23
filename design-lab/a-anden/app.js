/* Dirección A · «Andén»
   El tablero de la estación en la mano: señalética SNCF/RATP, bloques de
   color de línea, cifras condensadas enormes, vía en caja amarilla. Todo
   son filas, como en el panel de salidas. Movimiento: paleta de aleta
   (split-flap): las cifras giran en vertical, los cambios son cortes secos. */
(() => {
  'use strict';
  const T = window.Trajet, { html, esc, parts, fmt, line } = T;
  const M = window.TrajetMap;

  // ---------------------------------------------------------------- piezas
  const badge = (code, color, cls = '') =>
    `<span class="badge ${cls}" style="--lc:${line.color(color)};--li:${line.ink(color)}">${esc(code || '?')}</span>`;

  const via = (dep, leg) => {
    if (!line.publishesPlatform(leg.line_mode)) return '';
    if (dep.platform) return `<span class="via via-real${dep._isNew ? ' is-new' : ''}"><small>VÍA</small><b>${esc(dep.platform)}</b></span>`;
    if (dep.guess) return `<span class="via via-guess" title="${esc(dep.guess.why)}"><small>probable</small><b>${esc(dep.guess.platform)}</b><i>${dep.guess.percent || Math.round(dep.guess.share * 100)} %</i></span>`;
    return '';
  };

  const extras = (dep, leg) => {
    const out = [];
    if (dep.delay != null && dep.aimed_at && dep.delay !== 0) out.push(`<span class="ex ex-delay${dep.delay > 0 ? ' is-late' : ''}">${fmt.delay(dep.delay)}</span>`);
    if (dep.length) out.push(`<span class="ex ex-len">${parts.icon(dep.length === 'short' ? 'lengthShort' : 'length')}${dep.length === 'short' ? 'corto' : 'largo'}</span>`);
    if (dep.at_stop) out.push(`<span class="ex ex-stop">en el andén</span>`);
    return out.join('');
  };

  const row = (dep, leg, i) => {
    const m = T.moment(dep);
    return html`<div class="row${i === 0 ? ' row-first' : ''}${dep.at_stop ? ' row-atstop' : ''}" data-jid="${dep.jid}">
      <div class="row-min"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></div>
      <div class="row-body">
        <div class="row-dest">${esc(dep.destination)}</div>
        <div class="row-meta"><span class="row-at" data-dep-at="${dep.jid}">${dep.at}</span>${extras(dep, leg)}</div>
      </div>
      <div class="row-via">${via(dep, leg)}${i === 0 && m.pace ? `<span class="pace" data-pace="${dep.jid}" data-value="${m.pace.id}">${parts.icon(m.pace.id === 'run' ? 'run' : m.pace.id === 'walk' ? 'walk' : 'cup')}</span>` : ''}</div>
    </div>`;
  };

  const notice = leg => {
    const st = leg.status;
    if (!st.level && !st.messages.length) return '';
    const msgs = T.visibleMessages(st);
    return html`<div class="notice lvl-${st.level}">
      <div class="notice-head">${parts.icon('warn')}<span>${esc(st.label).toUpperCase()}</span>${T.awaitingTranslation(st) ? '<em class="translating">traduciendo<i>.</i><i>.</i><i>.</i></em>' : ''}</div>
      ${msgs.map(m => `<p lang="${m.translated ? 'es' : 'fr'}" class="${m.translated ? 'is-es' : 'is-fr'}">${esc(m.text)}</p>`)}
    </div>`;
  };

  const legBlock = (leg, ctx) => html`<section class="leg" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
    <div class="leg-rail">${badge(leg.line_code, leg.line_color, 'badge-lg')}<span class="leg-mode">${esc(line.modeLabel(leg.line_mode))}</span></div>
    <div class="leg-main">
      <header class="leg-head">
        <h2>${esc(leg.from_name)} <span class="arrow">→</span> ${esc(leg.to_name || leg.directions[0] || '')}</h2>
        ${leg.directions.length ? `<p class="dir">dirección ${esc(leg.directions.join(' · '))}</p>` : ''}
      </header>
      ${notice(leg)}
      ${leg.departures.length
        ? `<div class="rows">${leg.departures.slice(0, 4).map((d, i) => row(d, leg, i)).join('')}</div>`
        : `<div class="empty"><b>SIN PRÓXIMOS PASOS</b><span>${leg.status.level >= 2 ? 'servicio interrumpido' : 'no hay nada anunciado ahora mismo'}</span></div>`}
    </div>
  </section>`;

  const topbar = (title, opts = {}) => html`<header class="topbar${opts.cls ? ' ' + opts.cls : ''}">
    ${opts.back ? `<button class="tb-btn" data-go="${opts.back}" data-back>${parts.icon('back')}</button>` : '<span class="tb-spacer"></span>'}
    <h1>${title}</h1>
    ${opts.right || '<span class="tb-spacer"></span>'}
  </header>`;

  const liveDot = () => `<span class="live"><i></i>EN DIRECTO</span>`;

  // ---------------------------------------------------------------- pantallas
  const S = {};

  S.pair = {
    render: () => html`<div class="pair">
      <div class="pair-cam"><div class="pair-frame"><i></i><i></i><i></i><i></i></div>${parts.qr(150, '#0b1a2b', '#fff')}<div class="pair-scan"></div></div>
      <div class="pair-body">
        <p class="kicker">EMPAREJAR</p>
        <h1>Apunta al QR del panel del servidor</h1>
        <p class="pair-state" data-state="scan"><span data-s="scan">Buscando el código…</span><span data-s="connecting">Conectando con umbrel:7796…</span><span data-s="ready">${parts.icon('check')} Listo · iPhone de Isma emparejado</span></p>
        <button class="btn btn-primary" data-pair>ESCANEAR</button>
        <button class="btn btn-ghost" data-go="settings">Introducir la dirección a mano</button>
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
        <header class="board-head">
          <div>
            <p class="kicker">${b.auto_selected ? 'LA QUE TOCA AHORA' : 'RUTA'} · <span data-clock>${fmt.hhmm(ctx.now)}</span></p>
            <h1>${esc(b.route.name)}</h1>
          </div>
          <button class="tb-btn" data-go="settings" aria-label="Ajustes">${parts.icon('gear')}</button>
        </header>
        <div class="board-status ${b.stale ? 'is-stale' : ''}">
          ${b.stale ? `${parts.icon('wifiOff')}<b>SIN CONEXIÓN</b><span>último tablero <span data-age>${fmt.age(b.data_age)}</span></span>` : `${liveDot()}<span>actualizado <span data-age>${fmt.age(b.data_age)}</span></span>`}
        </div>
        <div class="scroll">
          ${b.legs.map(l => legBlock(l, ctx))}
          <button class="btn btn-alt ${cut ? 'is-urgent' : ''}" data-go="alternatives" data-sheet>${parts.icon('swap')} BUSCAR ALTERNATIVA${cut ? ' · LÍNEA ' + esc(b.worst_line) + ' CORTADA' : ''}</button>
          <p class="foot">${fmt.quota(b.quota['stop-monitoring'])} · se refresca cada 30 s mientras miras</p>
        </div>
      </div>`;
    }
  };

  S.map = {
    render(ctx) {
      const h = T.headline(ctx.board); const s = ctx.s;
      const dep = h.dep, leg = h.leg;
      return html`<div class="mapscr">
        <div class="map" id="map-a"></div>
        <div class="map-top">
          <button class="tb-btn tb-solid" data-go="board" data-back>${parts.icon('back')}</button>
          <div class="map-route">${badge('J', 'CEC73D')}<span>SAINT-LAZARE → ARGENTEUIL</span></div>
          <span class="map-walk">${parts.icon('walk')} ${ctx.data.lineJ.walkMinutes} min a pie</span>
        </div>
        <div class="map-sheet">
          ${dep ? html`<div class="row row-first row-sheet">
            <div class="row-min"><b class="num" data-dep-min="${dep.jid}">${T.moment(dep).text}</b><small data-dep-unit="${dep.jid}">${T.moment(dep).unit}</small></div>
            <div class="row-body"><div class="row-dest">${esc(dep.destination)}</div><div class="row-meta"><span data-dep-at="${dep.jid}">${dep.at}</span>${extras(dep, leg)}</div></div>
            <div class="row-via">${via(dep, leg)}</div>
          </div>` : '<div class="empty"><b>SIN PRÓXIMOS PASOS</b></div>'}
          <div class="map-stops"><span>Saint-Lazare</span><span>Asnières</span><span>Bois-Colombes</span><span>Colombes</span><span>Le Stade</span><b>Argenteuil</b></div>
          ${s.trip
            ? `<button class="btn btn-stop" data-scenario="trip=false">${parts.icon('stop')} PARAR TRAYECTO</button><p class="foot">sigue en segundo plano · se apaga al llegar a Argenteuil</p>`
            : `<button class="btn btn-primary" data-scenario="trip=true">${parts.icon('play')} INICIAR TRAYECTO</button>`}
        </div>
      </div>`;
    },
    mount(el, ctx) {
      el._map = M.mount(el.querySelector('#map-a'), {
        theme: ctx.s.theme, labels: true, casing: true, routeWidth: 7, stopRadius: 5, labelSize: 12,
        tint: { light: { land: '#e8e8e2', water: '#bfc9d1', park: '#dcdfd3', building: '#dedcd5', road: '#f7f7f4', roadCasing: '#cfcfc8', rail: '#c7c7c0', text: '#1c2a3a', halo: '#f7f7f4' },
                dark:  { land: '#0f1c2b', water: '#0a121c', park: '#12202c', building: '#14233a', road: '#1e2f45', roadCasing: '#0b1522', rail: '#25364c', text: '#dbe3ee', halo: '#0f1c2b' } },
        stopFill: ctx.s.theme === 'dark' ? '#0f1c2b' : '#fff', meColor: '#e2231a', padding: { top: 120, bottom: 300, left: 40, right: 40 }
      });
    },
    update(el, ctx) {
      // Cambio de escenario: tema del mapa y hoja inferior, sin recrear el mapa.
      el._map && el._map.setTheme(ctx.s.theme);
      const sheet = el.querySelector('.map-sheet');
      const tmp = document.createElement('div'); tmp.innerHTML = S.map.render(ctx);
      sheet.innerHTML = tmp.querySelector('.map-sheet').innerHTML;
    },
    unmount(el) { el._map && el._map.destroy(); }
  };

  S.alternatives = {
    render(ctx) {
      const a = ctx.data.alternatives;
      return html`<div class="alts">
        ${topbar('ALTERNATIVAS', { back: 'board', cls: 'topbar-sheet' })}
        <div class="scroll">
          <div class="affected">${parts.icon('warn')}<div><b>LÍNEA ${a.affected.map(x => esc(x.line_code)).join(', ')} ${esc(a.affected[0].label).toUpperCase()}</b><span>tu ruta habitual tarda ${a.baseline_minutes} min cuando funciona</span></div></div>
          ${a.options.map((o, i) => html`<article class="alt ${o.usable ? '' : 'is-unusable'}">
            <header><b class="num-md">${o.total_minutes}<small>min</small></b><span class="delta">${o.delta_minutes != null ? '+' + o.delta_minutes + ' min' : ''}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
            <div class="chain">${o.legs.map((l, j) => `${j ? '<i class="chain-gap"></i>' : ''}${badge(l.code, l.color)}<span class="chain-leg"><b>${esc(l.direction)}</b><small>${l.minutes} min${l.status !== 'normal' ? ' · ' + esc(l.status) : ''}</small></span>`).join('')}</div>
            <footer>${o.usable ? `<span>${fmt.transfers(o.transfers)}</span><button class="btn btn-small" data-go="board" data-back>USAR HOY</button>` : `<span class="bad">${parts.icon('x')} pasa por la línea cortada</span>`}</footer>
          </article>`)}
        </div>
      </div>`;
    }
  };

  const routeCard = (r, active) => html`<article class="route ${active ? 'is-active' : ''}" data-go="route-edit">
    <div class="route-legs">${r.legs.map(l => badge(l.line_code, l.line_color)).join('<i class="chain-gap"></i>')}</div>
    <div class="route-body"><h3>${esc(r.name)}</h3><p>${esc(r.origin_name)} → ${esc(r.dest_name)}</p><small>${fmt.daysLabel(r.days)} · ${fmt.scheduleLabel(r)}</small></div>
    ${active ? '<span class="tag">AHORA</span>' : parts.icon('chev')}
  </article>`;

  S.routes = {
    render(ctx) {
      const rs = ctx.data.routes;
      return html`<div class="routes">
        ${topbar('RUTAS', { right: `<button class="tb-btn" data-go="route-edit">${parts.icon('plus')}</button>` })}
        <div class="scroll">
          <p class="kicker pad">SE ELIGE SOLA SEGÚN EL DÍA Y LA HORA</p>
          ${rs.routes.map(r => routeCard(r, r.id === rs.active_id))}
          <button class="btn btn-ghost" data-go="plan">${parts.icon('search')} CREAR DESDE EL PLANIFICADOR</button>
        </div>
      </div>`;
    }
  };

  S['route-edit'] = {
    render(ctx) {
      const r = ctx.data.routes.routes[1];
      const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      return html`<div class="editor">
        ${topbar('EDITAR RUTA', { back: 'routes', right: '<button class="tb-btn tb-text" data-go="routes" data-back>Guardar</button>' })}
        <div class="scroll">
          <label class="field"><span>NOMBRE</span><input value="${esc(r.name)}"></label>
          <label class="field"><span>ORIGEN</span><input value="${esc(r.origin_name)}"></label>
          <label class="field"><span>DESTINO</span><input value="${esc(r.dest_name)}"></label>
          <div class="field"><span>DÍAS</span><div class="days">${days.map((d, i) => `<button class="day ${r.days.includes(i) ? 'is-on' : ''}" data-toggle>${d}</button>`).join('')}</div></div>
          <div class="field"><span>CUÁNDO TOCA</span><div class="seg"><button class="${r.time_mode === 'window' ? 'is-on' : ''}">Franja</button><button class="${r.time_mode === 'arrival' ? 'is-on' : ''}">Llegar a</button><button class="${r.time_mode === 'departure' ? 'is-on' : ''}">Salir a</button></div><div class="times"><input value="${r.time_from}"> <span>→</span> <input value="${r.time_to}"></div></div>
          <p class="kicker pad">TRAMOS</p>
          ${r.legs.map((l, i) => html`<div class="leg-edit">${badge(l.line_code, l.line_color)}<div><b>${esc(l.from_name)} → ${esc(l.to_name)}</b><small>${l.directions.length ? 'dirección ' + esc(l.directions.join(' · ')) : 'cualquier sentido'}</small></div><button class="tb-btn" aria-label="quitar">${parts.icon('x')}</button></div>`)}
          <button class="btn btn-ghost">${parts.icon('plus')} AÑADIR TRAMO</button>
          <button class="btn btn-danger">ELIMINAR RUTA</button>
        </div>
      </div>`;
    },
    mount(el) { el.querySelectorAll('[data-toggle]').forEach(b => b.addEventListener('click', () => b.classList.toggle('is-on'))); el.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => { b.parentElement.querySelectorAll('button').forEach(x => x.classList.remove('is-on')); b.classList.add('is-on'); })); }
  };

  S.plan = {
    render(ctx) {
      const p = ctx.data.plan;
      const kind = { best: 'MÁS RÁPIDO', less_fallback: 'MENOS TRANSBORDOS', less_walk: 'MENOS A PIE' };
      return html`<div class="plan">
        ${topbar('BUSCAR')}
        <div class="scroll">
          <div class="plan-form">
            <label class="field"><span>DESDE</span><input value="Argenteuil"></label>
            <label class="field"><span>HASTA</span><input value="Montparnasse" placeholder="Dirección, parada o sitio"></label>
            <div class="plan-when"><span>Salir ahora</span><button class="btn btn-small">CAMBIAR</button></div>
          </div>
          <div class="results">
            <p class="kicker pad">RESULTADOS · <span data-age>hace 1 s</span></p>
            ${p.options.map(o => html`<article class="alt">
              <header><b class="num-md">${o.minutes}<small>min</small></b><span class="tag tag-kind">${kind[o.kind] || o.kind}</span><span class="times">${o.departure} → ${o.arrival}</span></header>
              <div class="chain">${o.legs.map((l, j) => `${j ? '<i class="chain-gap"></i>' : ''}${badge(l.line_code, l.line_color)}<span class="chain-leg"><b>${esc(l.direction)}</b><small>${l.minutes} min</small></span>`).join('')}</div>
              <footer><span>${fmt.transfers(o.transfers)} · ${o.walk_minutes} min a pie</span><button class="btn btn-small" data-go="routes">GUARDAR RUTA</button></footer>
            </article>`)}
          </div>
        </div>
      </div>`;
    }
  };

  S.stats = {
    render(ctx) {
      const st = ctx.data.stats, pm = ctx.data.platformModel;
      const maxShare = Math.max(...st.by_month.map(m => m.bad_days / m.total_days));
      return html`<div class="stats">
        ${topbar('HISTORIAL')}
        <div class="scroll">
          <div class="tiles">
            <div class="tile"><b class="num-md">${st.overall.n}</b><span>días con datos</span></div>
            <div class="tile"><b class="num-md">${st.overall.avg_delay.toFixed(1)}<small>min</small></b><span>retraso medio</span></div>
            <div class="tile"><b class="num-md">${Math.round(st.overall.max_delay)}<small>min</small></b><span>peor día</span></div>
          </div>
          <p class="kicker pad">DÍAS CON INCIDENCIAS</p>
          <div class="bars">${st.by_month.map(m => html`<div class="bar"><span class="bar-lbl">${fmt.monthLabel(m.month)}</span><span class="bar-track"><i style="width:${(m.bad_days / m.total_days / maxShare * 100).toFixed(0)}%"></i></span><b>${m.bad_days}<small>/${m.total_days}</small></b></div>`)}</div>
          <p class="kicker pad">QUÉ LÍNEA FALLA MÁS</p>
          <div class="lines">${st.by_line.map(l => { const r = ctx.data.routes.routes.flatMap(x => x.legs).find(x => x.line_code === l.worst_line); return html`<div class="line-stat">${badge(l.worst_line, r ? r.line_color : '')}<div><b>${l.n} días</b> como peor línea<small>retraso medio ${l.avg_delay.toFixed(1)} min</small></div></div>`; })}</div>
          <p class="kicker pad">PREVISIÓN DE VÍA</p>
          <div class="accuracy"><b class="num-lg">${fmt.percent(pm.accuracy.rate)}</b><div><span>${pm.accuracy.hits} aciertos de ${pm.accuracy.predictions} previsiones</span><small>${pm.accuracy.observations} trenes observados en ${pm.accuracy.days} días · el servidor se puntúa solo</small></div></div>
          ${pm.coverage.map(c => html`<div class="cov">${badge(c.line_code, c.line_code === 'J' ? 'CEC73D' : '640082')}<span>${c.observations ? `${c.observations} observaciones · ${c.platforms} vías distintas` : 'no publica vía'}</span></div>`)}
        </div>
      </div>`;
    }
  };

  S.settings = {
    render(ctx) {
      const h = ctx.data.health;
      const q = (k, max) => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${(h.quota[k] / max * 100).toFixed(0)}%"></i></span><b>${h.quota[k]}</b></div>`;
      return html`<div class="settings">
        ${topbar('AJUSTES', { back: 'board' })}
        <div class="scroll">
          <p class="kicker pad">SERVIDOR</p>
          <div class="list">
            <div class="li"><span>Red de casa</span><b class="mono">192.168.1.188:7796</b><i class="dot ok"></i></div>
            <div class="li"><span>Tailscale</span><b class="mono">100.99.38.76:7796</b><i class="dot ${ctx.s.offline ? 'bad' : 'ok'}"></i></div>
            <button class="li" data-go="pair"><span>${parts.icon('qr')} Emparejar de nuevo</span>${parts.icon('chev')}</button>
            <button class="li" data-go="panel"><span>${parts.icon('server')} Panel del servidor</span>${parts.icon('chev')}</button>
          </div>
          <p class="kicker pad">CUOTA PRIM · QUEDAN HOY</p>
          <div class="list pad-in">${q('stop-monitoring', 1000)}${q('general-message', 1000)}${q('navitia', 1000)}</div>
          <p class="kicker pad">TRADUCTOR (IA LOCAL)</p>
          <div class="list"><div class="li"><span>${h.translator.model}</span><b>${h.translator.ok ? 'listo' : 'parado'}</b><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div></div>
          <p class="kicker pad">PANTALLA</p>
          <div class="list">
            <div class="li"><span>Aspecto</span><div class="seg seg-sm"><button class="${ctx.s.theme === 'light' ? 'is-on' : ''}" data-scenario="theme=light">Claro</button><button class="${ctx.s.theme === 'dark' ? 'is-on' : ''}" data-scenario="theme=dark">Oscuro</button></div></div>
            <div class="li"><span>Mantener la pantalla encendida en el tablero</span><i class="sw is-on"></i></div>
            <div class="li"><span>Vibrar cuando aparece la vía</span><i class="sw is-on"></i></div>
          </div>
          <p class="kicker pad">PROTOTIPOS</p>
          <div class="list"><button class="li" data-go="live"><span>Live Activity</span>${parts.icon('chev')}</button><button class="li" data-go="widgets"><span>Widgets</span>${parts.icon('chev')}</button></div>
          <p class="foot">Trajet 2.0 · dirección A «Andén» · ${esc(h.now_paris)} París</p>
        </div>
      </div>`;
    }
  };

  const activity = (ctx, cls = '') => {
    const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; if (!dep) return '';
    const m = T.moment(dep);
    return html`<div class="la ${cls}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
      <div class="la-left">${badge(leg.line_code, leg.line_color, 'badge-lg')}<span class="la-dest">${esc(dep.destination)}</span><span class="la-sub">Saint-Lazare · <span data-dep-at="${dep.jid}">${dep.at}</span></span></div>
      <div class="la-right"><b class="num" data-dep-min="${dep.jid}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small>${via(dep, leg)}</div>
      <div class="la-bar" data-progress="${dep.jid}" data-total="900"><i></i></div>
      <span class="la-count" data-countdown="${dep.jid}">${fmt.mmss(dep._seconds)}</span>
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
          <p class="kicker">DYNAMIC ISLAND</p>
          <div class="di-row"><span>compacta</span><div class="di di-compact">${badge('J', 'CEC73D', 'badge-sm')}<b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b><em>${dep && dep.platform ? 'VÍA ' + esc(dep.platform) : (dep && dep.guess ? '¿' + esc(dep.guess.platform) + '?' : '')}</em></div></div>
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
        <p class="kicker">PANTALLA DE INICIO</p>
        <div class="hs-grid">
          <div class="widget w-small" style="--lc:#CEC73D;--li:#000">${badge('J', 'CEC73D')}<b class="num" data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small>${dep ? via(dep, leg) : ''}<span class="w-foot">Argenteuil</span></div>
          <div class="hs-apps">${app('Mail')}${app('Fotos')}${app('Notas')}${app('Mapas')}</div>
          <div class="widget w-medium">
            <div class="w-head">${badge('J', 'CEC73D')}<span>SAINT-LAZARE → ARGENTEUIL</span><span class="live"><i></i></span></div>
            <div class="w-rows">${(leg ? leg.departures.slice(0, 3) : []).map(d => `<div class="w-row"><b data-dep-min="${d.jid}">${T.moment(d).text}</b><small data-dep-unit="${d.jid}">${T.moment(d).unit}</small><span>${d.at}</span>${via(d, leg)}</div>`).join('')}</div>
          </div>
          <div class="hs-apps">${app('Cámara')}${app('Ajustes')}${app('Reloj')}${app('Música')}</div>
        </div>
        <p class="kicker">PANTALLA DE BLOQUEO</p>
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
      const a = ctx.data.admin, h = ctx.data.health;
      const max = Math.max(...a.quotaHistory);
      return html`<div class="panel">
        <div class="web-bar"><span>umbrel:7796/admin</span></div>
        <div class="scroll">
        <header class="panel-head"><div class="panel-logo">${badge('T', '0b1a2b')}<b>TRAJET · SERVIDOR</b></div><span class="live"><i></i>EN MARCHA</span></header>
        <div class="panel-grid">
          <section class="pcard pcard-qr"><h3>EMPAREJAR UN IPHONE</h3>${parts.qr(180, '#0b1a2b', '#fff')}<p>Escanea desde la app. El código caduca en <b data-pair-ttl>5:00</b>.</p><button class="btn btn-small">NUEVO CÓDIGO</button></section>
          <section class="pcard"><h3>DISPOSITIVOS</h3>${a.devices.map(d => html`<div class="dev ${d.active ? '' : 'is-off'}">${parts.icon('phone')}<div><b>${esc(d.name)}</b><small>${d.via} · ${d.last_seen}</small></div><button class="btn btn-small btn-ghost">QUITAR</button></div>`)}</section>
          <section class="pcard"><h3>CUOTA PRIM · HOY</h3>${Object.entries(h.quota).map(([k, v]) => html`<div class="quota"><span>${k}</span><span class="bar-track"><i style="width:${v / 10}%"></i></span><b>${v}</b></div>`)}<div class="spark">${a.quotaHistory.map(v => `<i style="height:${v / max * 100}%"></i>`).join('')}</div><small>llamadas usadas, últimos 7 días</small></section>
          <section class="pcard"><h3>IA LOCAL</h3><div class="dev">${parts.icon('brain')}<div><b>${h.translator.model}</b><small>${h.translator.reason}</small></div><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div><p>Traduce los avisos del francés. Si se para, la app enseña el francés y avisa.</p></section>
          <section class="pcard"><h3>APRENDIZAJE DE ANDENES</h3><div class="tiles"><div class="tile"><b class="num-md">${fmt.percent(a.learning.hits / a.learning.predictions)}</b><span>acierto</span></div><div class="tile"><b class="num-md">${a.learning.observations}</b><span>trenes vistos</span></div><div class="tile"><b class="num-md">${a.learning.days}</b><span>días</span></div></div></section>
          <section class="pcard"><h3>ESTADO</h3><div class="li"><span>Clave PRIM</span><b>${h.key_configured ? 'configurada' : 'falta'}</b></div><div class="li"><span>Hora en París</span><b data-clock>${fmt.hhmm(ctx.now)}</b></div><div class="li"><span>Último error</span><b>${h.last_error || 'ninguno'}</b></div></section>
        </div>
        <p class="foot">Panel solo accesible desde la red de casa o la tailnet.</p>
        </div>
      </div>`;
    }
  };

  // ---------------------------------------------------------------- registro
  T.app.register({
    id: 'a', name: 'Andén', home: 'board', screens: S,
    tabbar: () => html`<div class="tabs">
      <button data-go="board" data-go-group="alternatives settings" class="is-active">${parts.icon('clock')}<span>TABLERO</span></button>
      <button data-go="map">${parts.icon('map')}<span>TRAYECTO</span></button>
      <button data-go="routes" data-go-group="route-edit">${parts.icon('routes')}<span>RUTAS</span></button>
      <button data-go="plan">${parts.icon('search')}<span>BUSCAR</span></button>
      <button data-go="stats">${parts.icon('chart')}<span>HISTORIAL</span></button>
    </div>`
  });
})();
