/* Mapa compartido: MapLibre GL JS con teselas de OpenFreeMap (sin clave) y,
   si algo no carga, la misma escena en SVG. Cada dirección le pasa su
   paleta y decide etiquetas, grosor y animación. */
window.TrajetMap = (() => {
  'use strict';
  const G = window.TrajetData.lineJ;
  const STYLE = { light: 'https://tiles.openfreemap.org/styles/positron', dark: 'https://tiles.openfreemap.org/styles/dark' };

  const DEFAULT_TINT = {
    light: { land: '#f2f1ec', water: '#c9dbe9', park: '#e2ebd9', building: '#e6e4de', road: '#ffffff', roadCasing: '#dcdad4', rail: '#d3d0c8', text: '#5f6368', halo: '#ffffff' },
    dark:  { land: '#141416', water: '#1d2430', park: '#191d19', building: '#1b1b1e', road: '#26262b', roadCasing: '#111113', rail: '#2c2c31', text: '#9a9aa2', halo: '#141416' }
  };

  function mount(container, opts = {}) {
    const o = Object.assign({
      theme: 'dark', tint: DEFAULT_TINT, labels: true, interactive: true, animate: true,
      routeWidth: 6, casing: true, glow: false, stopRadius: 5, padding: { top: 90, bottom: 260, left: 40, right: 40 },
      stopFill: '#fff', stopStroke: null, meColor: '#0a84ff', walkColor: null, font: ['Noto Sans Regular'], labelSize: 12,
      showTransfer: true, onReady: null
    }, opts);
    container.classList.add('map-box');
    container.innerHTML = '';
    let handle = { destroy() {}, setTheme() {}, setProgress() {}, fit() {}, kind: 'none' };

    if (!window.maplibregl || opts.forceSVG) return svgMap(container, o);

    let map, ready = false, dead = false, progress = o.animate ? 0 : 1;
    const timeout = setTimeout(() => { if (!ready && !dead) { dead = true; try { map.remove(); } catch {} svgMap(container, o, handle); } }, 8000);
    try {
      map = new maplibregl.Map({
        container, style: STYLE[o.theme] || STYLE.dark, center: G.center, zoom: 11.2, attributionControl: { compact: true },
        interactive: o.interactive, pitchWithRotate: false, dragRotate: false, touchPitch: false, fadeDuration: 0
      });
    } catch (e) { clearTimeout(timeout); return svgMap(container, o); }
    map.on('error', ev => {
      // Un error de estilo o de teselas antes de estar listo: alternativa SVG.
      if (!ready && !dead && ev && ev.error && /style|fetch|network|Failed/i.test(String(ev.error.message || ev.error))) {
        dead = true; clearTimeout(timeout); try { map.remove(); } catch {} svgMap(container, o, handle);
      }
    });

    const addScene = () => {
      const t = (o.tint[o.theme] || DEFAULT_TINT[o.theme]);
      tint(map, t, o.labels);
      const routeColor = '#' + G.color;
      if (!map.getSource('route')) {
        map.addSource('route', { type: 'geojson', lineMetrics: true, data: { type: 'Feature', geometry: { type: 'LineString', coordinates: G.path } } });
        map.addSource('walk', { type: 'geojson', data: { type: 'Feature', geometry: { type: 'LineString', coordinates: G.walk } } });
        map.addSource('transfer', { type: 'geojson', data: { type: 'Feature', geometry: { type: 'LineString', coordinates: G.transfer.path } } });
        map.addSource('stops', { type: 'geojson', data: { type: 'FeatureCollection', features: G.stops.map(s => ({ type: 'Feature', properties: { name: s.name, served: s.served ? 1 : 0, end: (s.origin || s.dest) ? 1 : 0 }, geometry: { type: 'Point', coordinates: s.lonlat } })) } });
      }
      const gradient = p => ['step', ['line-progress'], routeColor, Math.min(1, Math.max(0.0001, p)), 'rgba(0,0,0,0)'];
      if (o.glow) map.addLayer({ id: 'route-glow', type: 'line', source: 'route', layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': routeColor, 'line-width': o.routeWidth * 3, 'line-opacity': .22, 'line-blur': 6 } });
      if (o.casing) map.addLayer({ id: 'route-casing', type: 'line', source: 'route', layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': o.theme === 'dark' ? '#000' : '#fff', 'line-width': o.routeWidth + 4, 'line-opacity': .9 } });
      map.addLayer({ id: 'route', type: 'line', source: 'route', layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': routeColor, 'line-width': o.routeWidth, 'line-gradient': gradient(progress || 0.0001) } });
      if (o.showTransfer) map.addLayer({ id: 'transfer', type: 'line', source: 'transfer', layout: { 'line-cap': 'round' }, paint: { 'line-color': '#' + G.transfer.color, 'line-width': o.routeWidth - 1, 'line-opacity': .95 } });
      map.addLayer({ id: 'walk', type: 'line', source: 'walk', layout: { 'line-cap': 'round' }, paint: { 'line-color': o.walkColor || (o.theme === 'dark' ? '#e6e6ea' : '#2a2a2e'), 'line-width': 3, 'line-dasharray': [0.2, 2] } });
      map.addLayer({ id: 'stops-served', type: 'circle', source: 'stops', filter: ['==', ['get', 'served'], 1], paint: { 'circle-radius': ['case', ['==', ['get', 'end'], 1], o.stopRadius + 2, o.stopRadius], 'circle-color': o.stopFill, 'circle-stroke-color': o.stopStroke || routeColor, 'circle-stroke-width': 2.5 } });
      map.addLayer({ id: 'stops-pass', type: 'circle', source: 'stops', filter: ['==', ['get', 'served'], 0], paint: { 'circle-radius': 2.5, 'circle-color': routeColor, 'circle-opacity': .9 } });
      if (o.labels) map.addLayer({ id: 'stops-label', type: 'symbol', source: 'stops', filter: ['==', ['get', 'served'], 1], layout: { 'text-field': ['get', 'name'], 'text-font': o.font, 'text-size': o.labelSize, 'text-offset': [0.9, 0], 'text-anchor': 'left', 'text-allow-overlap': false }, paint: { 'text-color': t.text, 'text-halo-color': t.halo, 'text-halo-width': 1.4 } });
      if (!handle.meMarker) {
        const me = document.createElement('div'); me.className = 'map-me'; me.style.setProperty('--me', o.meColor);
        handle.meMarker = new maplibregl.Marker({ element: me }).setLngLat(G.me).addTo(map);
      }
      if (o.animate && progress < 1) animateRoute(p => { progress = p; try { map.setPaintProperty('route', 'line-gradient', gradient(p)); } catch {} });
      else map.setPaintProperty('route', 'line-gradient', gradient(1));
    };

    map.on('load', () => {
      if (dead) return;
      ready = true; clearTimeout(timeout);
      addScene();
      map.fitBounds(G.bounds, { padding: o.padding, duration: 0 });
      o.onReady && o.onReady(handle);
    });
    map.on('style.load', () => { if (ready) addScene(); });

    handle = Object.assign(handle, {
      kind: 'maplibre', map,
      setTheme(theme) { if (theme === o.theme || dead) return; o.theme = theme; progress = 1; handle.meMarker = null; map.setStyle(STYLE[theme]); },
      fit(padding) { if (!dead) map.fitBounds(G.bounds, { padding: padding || o.padding, duration: 600 }); },
      destroy() { dead = true; clearTimeout(timeout); try { map.remove(); } catch {} }
    });
    return handle;
  }

  /** Retiñe las capas del estilo base para que hable el idioma de la dirección. */
  function tint(map, t, labels) {
    const layers = (map.getStyle() || {}).layers || [];
    layers.forEach(l => {
      const id = l.id.toLowerCase();
      try {
        if (l.type === 'background') map.setPaintProperty(l.id, 'background-color', t.land);
        else if (l.type === 'fill') {
          if (id.includes('water')) map.setPaintProperty(l.id, 'fill-color', t.water);
          else if (id.includes('park') || id.includes('wood') || id.includes('grass') || id.includes('landcover') || id.includes('cemetery') || id.includes('pitch')) map.setPaintProperty(l.id, 'fill-color', t.park);
          else if (id.includes('building')) { map.setPaintProperty(l.id, 'fill-color', t.building); map.setPaintProperty(l.id, 'fill-opacity', .8); }
          else if (id.includes('landuse') || id.includes('residential') || id.includes('industrial') || id.includes('school') || id.includes('hospital')) map.setPaintProperty(l.id, 'fill-color', t.land);
          else map.setPaintProperty(l.id, 'fill-color', t.land);
        }
        else if (l.type === 'fill-extrusion') map.setLayoutProperty(l.id, 'visibility', 'none');
        else if (l.type === 'line') {
          if (id.includes('waterway')) map.setPaintProperty(l.id, 'line-color', t.water);
          else if (id.includes('rail') || id.includes('transit')) map.setPaintProperty(l.id, 'line-color', t.rail);
          else if (id.includes('casing') || id.includes('outline')) map.setPaintProperty(l.id, 'line-color', t.roadCasing);
          else if (id.includes('boundary') || id.includes('admin')) map.setLayoutProperty(l.id, 'visibility', 'none');
          else map.setPaintProperty(l.id, 'line-color', t.road);
        }
        else if (l.type === 'symbol') {
          if (!labels || id.includes('poi') || id.includes('housenum') || id.includes('airport') || id.includes('transit')) map.setLayoutProperty(l.id, 'visibility', 'none');
          else { map.setPaintProperty(l.id, 'text-color', t.text); map.setPaintProperty(l.id, 'text-halo-color', t.halo); }
        }
      } catch { /* la propiedad no existe en esa capa: da igual */ }
    });
  }

  function animateRoute(step) {
    const reduce = document.documentElement.dataset.reduceMotion === '1';
    if (reduce) { step(1); return; }
    const t0 = performance.now(), dur = 1500;
    const ease = x => 1 - Math.pow(1 - x, 3);
    const frame = now => { const p = Math.min(1, (now - t0) / dur); step(Math.max(0.0001, ease(p))); if (p < 1) requestAnimationFrame(frame); };
    requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------ alternativa SVG
  // Misma escena: suelo, el Sena, la J con sus paradas, el transbordo, mi
  // posición y el camino a pie. Proyección equirectangular sobre la caja.
  const SEINE = [[2.345, 48.848], [2.315, 48.858], [2.29, 48.868], [2.268, 48.882], [2.262, 48.897], [2.278, 48.905], [2.296, 48.908], [2.29, 48.92], [2.27, 48.93], [2.25, 48.936], [2.232, 48.948], [2.222, 48.962]];
  function svgMap(container, o, handle) {
    const t = (o.tint[o.theme] || DEFAULT_TINT[o.theme]);
    const W = container.clientWidth || 390, H = container.clientHeight || 600;
    const pad = o.padding;
    const [[x0, y0], [x1, y1]] = G.bounds;
    const innerW = Math.max(60, W - pad.left - pad.right), innerH = Math.max(60, H - pad.top - pad.bottom);
    const kx = innerW / (x1 - x0), ky = innerH / (y1 - y0);
    const k = Math.min(kx, ky * 1) ; // misma escala en los dos ejes (aprox. Mercator local)
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    const P = ([lon, lat]) => [pad.left + innerW / 2 + (lon - cx) * k * 1.0, pad.top + innerH / 2 - (lat - cy) * k * 1.52];
    const d = pts => pts.map((p, i) => (i ? 'L' : 'M') + P(p).map(v => v.toFixed(1)).join(' ')).join(' ');
    const routeColor = '#' + G.color;
    const stops = G.stops.map(s => { const [x, y] = P(s.lonlat); return s.served
      ? `<circle cx="${x}" cy="${y}" r="${o.stopRadius + ((s.origin || s.dest) ? 2 : 0)}" fill="${o.stopFill}" stroke="${o.stopStroke || routeColor}" stroke-width="2.5"/>${o.labels ? `<text x="${x + 12}" y="${y + 4}" font-size="${o.labelSize}" fill="${t.text}" stroke="${t.halo}" stroke-width="3" paint-order="stroke" font-family="system-ui, sans-serif" font-weight="600">${s.name}</text>` : ''}`
      : `<circle cx="${x}" cy="${y}" r="2.5" fill="${routeColor}"/>`; }).join('');
    const [mx, my] = P(G.me);
    const streets = [];
    for (let i = 0; i < 14; i++) { streets.push(`<line x1="${(i * 61) % W}" y1="0" x2="${(i * 61 + 140) % W}" y2="${H}" />`); streets.push(`<line x1="0" y1="${(i * 53) % H}" x2="${W}" y2="${(i * 53 + 90) % H}" />`); }
    const svg = `<svg class="map-svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice">
      <rect width="${W}" height="${H}" fill="${t.land}"/>
      <g stroke="${t.road}" stroke-width="1.2" opacity=".7">${streets.join('')}</g>
      <path d="${d(SEINE)}" fill="none" stroke="${t.water}" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/>
      ${o.glow ? `<path d="${d(G.path)}" fill="none" stroke="${routeColor}" stroke-width="${o.routeWidth * 3}" opacity=".22" stroke-linecap="round" stroke-linejoin="round"/>` : ''}
      ${o.casing ? `<path d="${d(G.path)}" fill="none" stroke="${o.theme === 'dark' ? '#000' : '#fff'}" stroke-width="${o.routeWidth + 4}" stroke-linecap="round" stroke-linejoin="round"/>` : ''}
      <path class="svg-route${o.animate ? ' is-drawing' : ''}" d="${d(G.path)}" pathLength="1" fill="none" stroke="${routeColor}" stroke-width="${o.routeWidth}" stroke-linecap="round" stroke-linejoin="round"/>
      ${o.showTransfer ? `<path d="${d(G.transfer.path)}" fill="none" stroke="#${G.transfer.color}" stroke-width="${o.routeWidth - 1}" stroke-linecap="round"/>` : ''}
      <path d="${d(G.walk)}" fill="none" stroke="${o.walkColor || (o.theme === 'dark' ? '#e6e6ea' : '#2a2a2e')}" stroke-width="3" stroke-dasharray="1 6" stroke-linecap="round"/>
      ${stops}
      ${o.forceSVG ? '' : `<text x="${W - 8}" y="${H - 6}" text-anchor="end" font-size="9" fill="${t.text}" font-family="system-ui">mapa sin conexión · trazado esquemático</text>`}
    </svg>
    <div class="map-me" style="--me:${o.meColor};position:absolute;left:${mx - 9}px;top:${my - 9}px"></div>`;
    container.innerHTML = svg;
    if (!document.getElementById('svg-route-style')) {
      const st = document.createElement('style'); st.id = 'svg-route-style';
      st.textContent = `.svg-route.is-drawing{stroke-dasharray:1;stroke-dashoffset:1;animation:svg-draw 1.5s cubic-bezier(.2,.7,.2,1) forwards}@keyframes svg-draw{to{stroke-dashoffset:0}}`;
      document.head.appendChild(st);
    }
    const h = Object.assign(handle || {}, { kind: 'svg', setTheme(theme) { o.theme = theme; o.animate = false; svgMap(container, o, h); }, destroy() { container.innerHTML = ''; }, fit() {}, setProgress() {} });
    o.onReady && o.onReady(h);
    return h;
  }

  return { mount, STYLE, DEFAULT_TINT };
})();
