/* Dirección C · «Cifra»
   Un número llena la pantalla. Casi monocromo: papel e tinta; el color de
   línea solo en una franja fina y en el distintivo. Sin tarjetas: filetes.
   Movimiento lento y asentado: las cifras se deslizan y se desenfocan al
   cambiar; las pantallas se funden. */
(() => {
  'use strict';
  const T = window.Trajet, { html, esc, parts, fmt, line } = T;
  const M = window.TrajetMap;

  const TINT = {
    light: { land: '#fafaf8', water: '#e6e8ea', park: '#f2f3ef', building: '#f3f3f1', road: '#e4e4e1', roadCasing: '#fafaf8', rail: '#d8d8d5', text: '#111', halo: '#fafaf8' },
    dark:  { land: '#0c0c0c', water: '#161719', park: '#101110', building: '#111', road: '#232323', roadCasing: '#0c0c0c', rail: '#2a2a2a', text: '#eee', halo: '#0c0c0c' }
  };
  const mapOpts = (ctx, extra = {}) => Object.assign({
    theme: ctx.s.theme, tint: TINT, labels: false, casing: false, routeWidth: 5, stopRadius: 4, labelSize: 11,
    stopFill: ctx.s.theme === 'dark' ? '#0c0c0c' : '#fafaf8', meColor: ctx.s.theme === 'dark' ? '#fff' : '#111', walkColor: ctx.s.theme === 'dark' ? '#fff' : '#111'
  }, extra);

  // ---------------------------------------------------------------- piezas
  const badge = (code, color, cls = '') => `<span class="badge ${cls}" style="--lc:${line.color(color)};--li:${line.ink(color)}">${esc(code || '?')}</span>`;

  const via = (dep, leg, big = false) => {
    if (!line.publishesPlatform(leg.line_mode)) return '';
    if (dep.platform) return `<span class="via via-real${dep._isNew ? ' is-new' : ''}${big ? ' via-big' : ''}"><small>Vía</small><b>${esc(dep.platform)}</b></span>`;
    if (dep.guess) return `<span class="via via-guess${big ? ' via-big' : ''}"><small>probable</small><b>${esc(dep.guess.platform)}</b><i>${Math.round(dep.guess.share * 100)} %</i></span>`;
    return '';
  };
  const meta = dep => {
    const out = [];
    if (dep.at_stop) out.push('<em class="ok">en el andén</em>');
    if (dep.delay != null && dep.aimed_at && dep.delay !== 0) out.push(`<em class="${dep.delay > 0 ? 'late' : ''}">${fmt.delay(dep.delay)}</em>`);
    if (dep.length) out.push(`<em>tren ${dep.length === 'short' ? 'corto' : 'largo'}</em>`);
    return out.join('<i>·</i>');
  };

  /** La cifra grande: la primera salida del tramo. */
  const hero = (dep, leg) => {
    const m = T.moment(dep);
    return html`<div class="hero${dep.at_stop ? ' is-atstop' : ''}" data-jid="${dep.jid}">
      <div class="hero-num"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></div>
      <div class="hero-line">
        <span class="hero-dest">${esc(dep.destination)}<i>·</i><span data-dep-at="${dep.jid}">${dep.at}</span></span>
        <span class="hero-meta">${meta(dep)}</span>
      </div>
      <div class="hero-side">${via(dep, leg, true)}${m.pace ? `<span class="pace" data-pace="${dep.jid}" data-value="${m.pace.id}" data-pace-label="label">${m.pace.label}</span>` : ''}</div>
    </div>`;
  };
  const rowSmall = (dep, leg) => {
    const m = T.moment(dep);
    return html`<div class="row" data-jid="${dep.jid}">
      <span class="row-num"><b class="num" data-dep-min="${dep.jid}" data-word="${m.word ? 1 : 0}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></span>
      <span class="row-at" data-dep-at="${dep.jid}">${dep.at}</span>
      <span class="row-meta">${meta(dep)}</span>
      <span class="row-via">${via(dep, leg)}</span>
    </div>`;
  };
  const notice = leg => {
    const st = leg.status; if (!st.level && !st.messages.length) return '';
    return html`<div class="notice lvl-${st.level}"><span class="notice-lbl">${esc(st.label)}${T.awaitingTranslation(st) ? ' · <em class="translating">traduciendo<i></i></em>' : ''}</span>
      ${T.visibleMessages(st).map(m => `<p lang="${m.translated ? 'es' : 'fr'}" class="${m.translated ? '' : 'is-fr'}">${esc(m.text)}</p>`)}</div>`;
  };
  const legBlock = (leg, i) => html`<section class="leg ${i ? 'leg-next' : 'leg-first'}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
    <div class="leg-band"></div>
    <header class="leg-head">${badge(leg.line_code, leg.line_color)}<span>${esc(leg.from_name)} → ${esc(leg.to_name || leg.directions[0] || '')}</span>${leg.directions.length ? `<em>dir. ${esc(leg.directions.join(' · '))}</em>` : ''}</header>
    ${notice(leg)}
    ${leg.departures.length ? `${i ? rowSmall(leg.departures[0], leg).replace('class="row"', 'class="row row-lead"') : hero(leg.departures[0], leg)}<div class="rows">${leg.departures.slice(1, 4).map(d => rowSmall(d, leg)).join('')}</div>`
      : `<div class="empty"><b>—</b><span>sin próximos pasos${leg.status.level >= 2 ? ' · servicio interrumpido' : ''}</span></div>`}
  </section>`;

  const top = (title, { back = null, right = '' } = {}) => html`<header class="top">${back ? `<button class="tb" data-go="${back}" data-back>${parts.icon('back')}</button>` : ''}<h1>${title}</h1>${right}</header>`;

  // ---------------------------------------------------------------- pantallas
  const S = {};
  S.pair = {
    render: () => html`<div class="pair">
      ${top('Emparejar')}
      <div class="pair-cam">${parts.qr(160, '#111', '#fafaf8')}<div class="pair-frame"></div></div>
      <div class="pair-body">
        <p class="pair-state" data-state="scan"><span data-s="scan">Enfoca el código del panel del servidor.</span><span data-s="connecting">Conectando con umbrel:7796…</span><span data-s="ready">Listo. iPhone de Isma emparejado.</span></p>
        <button class="btn" data-pair>Escanear</button>
        <button class="btn btn-text" data-go="settings">Escribir la dirección a mano</button>
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
          <div><span class="kicker">${b.auto_selected ? 'ahora' : 'ruta'}</span><h1>${esc(b.route.name)}</h1></div>
          <div class="board-state ${b.stale ? 'is-stale' : ''}">${b.stale ? `<b>sin conexión</b><span>último dato <span data-age>${fmt.age(b.data_age)}</span></span>` : `<span class="live"><i></i>en directo</span><span data-age>${fmt.age(b.data_age)}</span>`}</div>
          <button class="tb" data-go="settings" aria-label="Ajustes">${parts.icon('gear')}</button>
        </header>
        <div class="scroll">
          ${b.legs.map(legBlock)}
          <button class="btn ${cut ? 'btn-solid' : 'btn-text'} btn-alt" data-go="alternatives" data-sheet>Buscar alternativa${cut ? ' — línea ' + esc(b.worst_line) + ' cortada' : ''} ${parts.icon('arrow')}</button>
          <p class="foot">${fmt.quota(b.quota['stop-monitoring'])} · cada 30 s mientras miras</p>
        </div>
      </div>`;
    }
  };

  S.map = {
    render(ctx) {
      const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg, s = ctx.s;
      return html`<div class="mapscr">
        <div class="map" id="map-c"></div>
        <header class="top top-over"><button class="tb" data-go="board" data-back>${parts.icon('back')}</button><h1>Saint-Lazare → Argenteuil</h1><span class="walk">${ctx.data.lineJ.walkMinutes} min a pie</span></header>
        <div class="map-sheet">
          ${dep ? hero(dep, leg) : '<div class="empty"><b>—</b><span>sin próximos pasos</span></div>'}
          ${s.trip ? `<button class="btn btn-solid" data-scenario="trip=false">Parar trayecto</button><p class="foot">en segundo plano · se apaga al llegar</p>` : `<button class="btn" data-scenario="trip=true">Iniciar trayecto</button>`}
        </div>
      </div>`;
    },
    mount(el, ctx) { el._map = M.mount(el.querySelector('#map-c'), mapOpts(ctx, { labels: true, padding: { top: 110, bottom: 300, left: 40, right: 40 } })); },
    update(el, ctx) { el._map && el._map.setTheme(ctx.s.theme); const tmp = document.createElement('div'); tmp.innerHTML = S.map.render(ctx); el.querySelector('.map-sheet').innerHTML = tmp.querySelector('.map-sheet').innerHTML; },
    unmount(el) { el._map && el._map.destroy(); }
  };

  const chain = legs => `<div class="chain">${legs.map((l, j) => `${j ? '<i>→</i>' : ''}${badge(l.code || l.line_code, l.color || l.line_color, 'badge-sm')}<span>${esc(l.direction)} <em>${l.minutes} min${l.status && l.status !== 'normal' ? ' · ' + esc(l.status) : ''}</em></span>`).join('')}</div>`;

  S.alternatives = {
    render(ctx) {
      const a = ctx.data.alternatives;
      return html`<div class="page">
        ${top('Alternativas', { back: 'board' })}
        <div class="scroll">
          <p class="affected">Línea ${a.affected.map(x => esc(x.line_code)).join(', ')} ${esc(a.affected[0].label)}. Tu ruta tarda ${a.baseline_minutes} min cuando funciona.</p>
          ${a.options.map(o => html`<article class="alt ${o.usable ? '' : 'is-unusable'}">
            <div class="alt-num"><b class="num-md">${o.total_minutes}</b><small>min</small><em>${o.delta_minutes != null ? '+' + o.delta_minutes : ''}</em></div>
            <div class="alt-body">${chain(o.legs)}<footer>${o.departure} → ${o.arrival} · ${fmt.transfers(o.transfers)}${o.usable ? '' : ' · <b>pasa por la línea cortada</b>'}</footer></div>
            ${o.usable ? `<button class="tb" data-go="board" data-back>${parts.icon('arrow')}</button>` : ''}
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
          ${rs.routes.map(r => html`<article class="route ${r.id === rs.active_id ? 'is-active' : ''}" data-go="route-edit">
            <div class="route-legs">${r.legs.map(l => badge(l.line_code, l.line_color, 'badge-sm')).join('')}</div>
            <h3>${esc(r.name)}${r.id === rs.active_id ? '<em>ahora</em>' : ''}</h3>
            <p>${esc(r.origin_name)} → ${esc(r.dest_name)}</p><small>${fmt.daysLabel(r.days)} · ${fmt.scheduleLabel(r)}</small>
          </article>`)}
          <button class="btn btn-text" data-go="plan">Crear desde el planificador ${parts.icon('arrow')}</button>
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
          <label class="field"><span>nombre</span><input value="${esc(r.name)}"></label>
          <label class="field"><span>origen</span><input value="${esc(r.origin_name)}"></label>
          <label class="field"><span>destino</span><input value="${esc(r.dest_name)}"></label>
          <div class="field"><span>días</span><div class="days">${days.map((d, i) => `<button class="day ${r.days.includes(i) ? 'is-on' : ''}" data-toggle>${d}</button>`).join('')}</div></div>
          <div class="field"><span>cuándo toca</span><div class="seg"><button class="${r.time_mode === 'window' ? 'is-on' : ''}">franja</button><button class="${r.time_mode === 'arrival' ? 'is-on' : ''}">llegar a</button><button class="${r.time_mode === 'departure' ? 'is-on' : ''}">salir a</button></div><div class="times"><input value="${r.time_from}"><span>→</span><input value="${r.time_to}"></div></div>
          <p class="kicker pad">tramos</p>
          ${r.legs.map(l => html`<div class="leg-edit">${badge(l.line_code, l.line_color, 'badge-sm')}<div><b>${esc(l.from_name)} → ${esc(l.to_name)}</b><small>${l.directions.length ? 'dirección ' + esc(l.directions.join(' · ')) : 'cualquier sentido'}</small></div><button class="tb" aria-label="quitar">${parts.icon('x')}</button></div>`)}
          <button class="btn btn-text">Añadir tramo ${parts.icon('plus')}</button>
          <button class="btn btn-text btn-danger">Eliminar ruta</button>
        </div>
      </div>`;
    },
    mount(el) { el.querySelectorAll('[data-toggle]').forEach(b => b.addEventListener('click', () => b.classList.toggle('is-on'))); el.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => { b.parentElement.querySelectorAll('button').forEach(x => x.classList.remove('is-on')); b.classList.add('is-on'); })); }
  };

  S.plan = {
    render(ctx) {
      const p = ctx.data.plan; const kind = { best: 'más rápido', less_fallback: 'menos transbordos', less_walk: 'menos a pie' };
      return html`<div class="page">
        ${top('Buscar')}
        <div class="scroll">
          <label class="field"><span>desde</span><input value="Argenteuil"></label>
          <label class="field"><span>hasta</span><input value="Montparnasse"></label>
          <div class="field row-between"><span>salir ahora</span><button class="tb tb-text">cambiar</button></div>
          <p class="kicker pad">resultados · <span data-age>hace 1 s</span></p>
          ${p.options.map(o => html`<article class="alt">
            <div class="alt-num"><b class="num-md">${o.minutes}</b><small>min</small><em>${kind[o.kind] || o.kind}</em></div>
            <div class="alt-body">${chain(o.legs)}<footer>${o.departure} → ${o.arrival} · ${fmt.transfers(o.transfers)} · ${o.walk_minutes} min a pie</footer></div>
            <button class="tb" data-go="routes" aria-label="guardar">${parts.icon('plus')}</button>
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
          <div class="big-stats">
            <div><b class="num-lg">${st.overall.avg_delay.toFixed(1)}</b><span>min de retraso medio en ${st.overall.n} días</span></div>
            <div><b class="num-lg">${fmt.percent(pm.accuracy.rate)}</b><span>acierto de la vía prevista · ${pm.accuracy.hits} de ${pm.accuracy.predictions}</span></div>
          </div>
          <p class="kicker pad">días con incidencias</p>
          ${st.by_month.map(m => html`<div class="bar"><span>${fmt.monthLabel(m.month)}</span><span class="bar-track"><i style="width:${(m.bad_days / m.total_days / maxShare * 100).toFixed(0)}%"></i></span><b>${m.bad_days}<small>/${m.total_days}</small></b></div>`)}
          <p class="kicker pad">qué línea falla más</p>
          ${st.by_line.map(l => { const r = ctx.data.routes.routes.flatMap(x => x.legs).find(x => x.line_code === l.worst_line); return html`<div class="line-stat">${badge(l.worst_line, r ? r.line_color : '', 'badge-sm')}<span><b>${l.n}</b> días · retraso medio ${l.avg_delay.toFixed(1)} min</span></div>`; })}
          <p class="kicker pad">cobertura de andenes</p>
          ${pm.coverage.map(c => html`<div class="line-stat">${badge(c.line_code, c.line_code === 'J' ? 'CEC73D' : '640082', 'badge-sm')}<span>${c.observations ? `${c.observations} trenes observados · ${c.platforms} vías · ${c.days} días` : 'no publica vía'}</span></div>`)}
          <p class="foot">el servidor se puntúa solo; la app no pregunta nunca</p>
        </div>
      </div>`;
    }
  };

  S.settings = {
    render(ctx) {
      const h = ctx.data.health;
      const q = k => html`<div class="bar"><span>${k}</span><span class="bar-track"><i style="width:${h.quota[k] / 10}%"></i></span><b>${h.quota[k]}</b></div>`;
      return html`<div class="page">
        ${top('Ajustes', { back: 'board' })}
        <div class="scroll">
          <p class="kicker pad">servidor</p>
          <div class="li"><span>red de casa</span><b>192.168.1.188:7796</b><i class="dot ok"></i></div>
          <div class="li"><span>tailscale</span><b>100.99.38.76:7796</b><i class="dot ${ctx.s.offline ? 'bad' : 'ok'}"></i></div>
          <button class="li" data-go="pair"><span>emparejar de nuevo</span>${parts.icon('arrow')}</button>
          <button class="li" data-go="panel"><span>panel del servidor</span>${parts.icon('arrow')}</button>
          <p class="kicker pad">cuota PRIM · quedan hoy</p>
          ${q('stop-monitoring')}${q('general-message')}${q('navitia')}
          <p class="kicker pad">traductor</p>
          <div class="li"><span>${h.translator.model}</span><b>${h.translator.ok ? 'listo' : 'parado'}</b><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div>
          <p class="kicker pad">pantalla</p>
          <div class="li"><span>aspecto</span><div class="seg seg-sm"><button class="${ctx.s.theme === 'light' ? 'is-on' : ''}" data-scenario="theme=light">claro</button><button class="${ctx.s.theme === 'dark' ? 'is-on' : ''}" data-scenario="theme=dark">oscuro</button></div></div>
          <div class="li"><span>pantalla encendida en el tablero</span><i class="sw is-on"></i></div>
          <div class="li"><span>vibrar cuando aparece la vía</span><i class="sw is-on"></i></div>
          <p class="kicker pad">prototipos</p>
          <button class="li" data-go="live"><span>Live Activity</span>${parts.icon('arrow')}</button>
          <button class="li" data-go="widgets"><span>Widgets</span>${parts.icon('arrow')}</button>
          <p class="foot">Trajet 2.0 · dirección C «Cifra»</p>
        </div>
      </div>`;
    }
  };

  const activity = (ctx, cls = '') => {
    const h = T.headline(ctx.board); const dep = h.dep, leg = h.leg; if (!dep) return '';
    const m = T.moment(dep);
    return html`<div class="la ${cls}" style="--lc:${line.color(leg.line_color)};--li:${line.ink(leg.line_color)}">
      <div class="la-num"><b class="num" data-dep-min="${dep.jid}">${m.text}</b><small data-dep-unit="${dep.jid}">${m.unit}</small></div>
      <div class="la-body">${badge(leg.line_code, leg.line_color, 'badge-sm')}<b>${esc(dep.destination)}</b><span><span data-dep-at="${dep.jid}">${dep.at}</span> · <span data-countdown="${dep.jid}">${fmt.mmss(dep._seconds)}</span></span></div>
      <div class="la-via">${via(dep, leg)}</div>
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
          <p class="kicker">Dynamic Island</p>
          <div class="di-row"><span>compacta</span><div class="di di-compact"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b><em class="${dep && dep.platform ? 'is-real' : ''}">${dep && dep.platform ? 'vía ' + esc(dep.platform) : (dep && dep.guess ? '¿' + esc(dep.guess.platform) + '?' : 'J')}</em></div></div>
          <div class="di-row"><span>mínima</span><div class="di di-min"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : ''}</b></div></div>
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
          <div class="widget w-small" style="--lc:#CEC73D"><span class="w-band"></span><b class="num" data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small><span class="w-foot">${dep && dep.platform ? 'vía ' + esc(dep.platform) : 'Argenteuil'}</span></div>
          <div class="hs-apps">${app('Mail')}${app('Fotos')}${app('Notas')}${app('Mapas')}</div>
          <div class="widget w-medium" style="--lc:#CEC73D"><span class="w-band"></span>
            <div class="w-head">${badge('J', 'CEC73D', 'badge-sm')} Saint-Lazare → Argenteuil</div>
            <div class="w-rows">${(leg ? leg.departures.slice(0, 3) : []).map(d => `<div class="w-row"><b data-dep-min="${d.jid}">${T.moment(d).text}</b><small data-dep-unit="${d.jid}">${T.moment(d).unit}</small><span>${d.at}</span>${via(d, leg)}</div>`).join('')}</div>
          </div>
          <div class="hs-apps">${app('Cámara')}${app('Ajustes')}${app('Reloj')}${app('Música')}</div>
        </div>
        <p class="kicker">Pantalla de bloqueo</p>
        <div class="ls-widgets">
          <div class="lsw lsw-circ"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small>J</small></div>
          <div class="lsw lsw-rect"><b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b><small data-dep-unit="${dep ? dep.jid : ''}">${m ? m.unit : ''}</small><span>J · ${dep && dep.platform ? 'vía ' + esc(dep.platform) : 'Argenteuil'}</span></div>
          <div class="lsw lsw-inline">J · <b data-dep-min="${dep ? dep.jid : ''}">${m ? m.text : '—'}</b> min · Argenteuil${dep && dep.platform ? ' · vía ' + esc(dep.platform) : ''}</div>
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
          <header class="panel-head"><h1>Trajet <em>servidor</em></h1><span class="live"><i></i>en marcha · <span data-clock>${fmt.hhmm(ctx.now)}</span> París</span></header>
          <div class="panel-grid">
            <section class="pcard pcard-qr"><h3>emparejar un iPhone</h3>${parts.qr(180, ctx.s.theme === 'dark' ? '#fafaf8' : '#111', ctx.s.theme === 'dark' ? '#0c0c0c' : '#fafaf8')}<p>Escanea desde la app. Caduca en <b>5:00</b>.</p><button class="btn btn-text">nuevo código</button></section>
            <section class="pcard"><h3>dispositivos</h3>${a.devices.map(d => html`<div class="dev ${d.active ? '' : 'is-off'}"><div><b>${esc(d.name)}</b><small>${d.via} · ${d.last_seen}</small></div><button class="tb tb-text">quitar</button></div>`)}</section>
            <section class="pcard"><h3>cuota PRIM · hoy</h3>${Object.entries(h.quota).map(([k, v]) => html`<div class="bar"><span>${k}</span><span class="bar-track"><i style="width:${v / 10}%"></i></span><b>${v}</b></div>`)}<div class="spark">${a.quotaHistory.map(v => `<i style="height:${v / max * 100}%"></i>`).join('')}</div><small>llamadas usadas, últimos 7 días</small></section>
            <section class="pcard"><h3>IA local</h3><div class="dev"><div><b>${h.translator.model}</b><small>${h.translator.reason}</small></div><i class="dot ${h.translator.ok ? 'ok' : 'bad'}"></i></div><p>Traduce los avisos del francés. Si se para, la app enseña el francés y avisa.</p></section>
            <section class="pcard"><h3>aprendizaje de andenes</h3><div class="big-stats"><div><b class="num-lg">${fmt.percent(a.learning.hits / a.learning.predictions)}</b><span>acierto</span></div><div><b class="num-lg">${a.learning.observations}</b><span>trenes en ${a.learning.days} días</span></div></div></section>
            <section class="pcard"><h3>estado</h3><div class="li"><span>clave PRIM</span><b>${h.key_configured ? 'configurada' : 'falta'}</b></div><div class="li"><span>último error</span><b>${h.last_error || 'ninguno'}</b></div></section>
          </div>
          <p class="foot">solo desde la red de casa o la tailnet</p>
        </div>
      </div>`;
    }
  };

  T.app.register({
    id: 'c', name: 'Cifra', home: 'board', screens: S,
    tabbar: () => html`<div class="tabs">
      <button data-go="board" data-go-group="alternatives settings" class="is-active">Tablero</button>
      <button data-go="map">Trayecto</button>
      <button data-go="routes" data-go-group="route-edit">Rutas</button>
      <button data-go="plan">Buscar</button>
      <button data-go="stats">Historial</button>
    </div>`
  });
})();
