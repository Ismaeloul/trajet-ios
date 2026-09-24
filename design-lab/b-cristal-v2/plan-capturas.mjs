// Genera el plan de capturas de la Live Activity y los widgets.
//
//   node design-lab/b-cristal-v2/plan-capturas.mjs            → solo A (la elegida, 2B.4) + comparar + GIF
//   node design-lab/b-cristal-v2/plan-capturas.mjs --todas    → además B y C (como en la 2B.3)
//   node design-lab/tools/capturar.mjs design-lab/b-cristal-v2/plan-capturas.json
//
// Se ejecuta desde la raíz del repo, con el laboratorio servido
// (PORT=7797 por defecto: `node design-lab/shared/servidor.js`; con otro
// puerto, PORT=7798 también aquí).
// Nombres: <variante>-<pieza>-<escenario>-<modo>.png, en capturas/la-widgets/<variante>/.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = process.env.PORT || 7797;
const OUT = 'design-lab/capturas/la-widgets';
const T0 = '12:50:00';
const TODAS = process.argv.includes('--todas');

// Piezas: nombre en el fichero → selector en la vista «lámina».
const LA_PIECES = {
  'actividad-bloqueo': '#p-la .la',
  'isla-compacta': '#ph-di-compact',
  'isla-minima': '#ph-di-minimal',
  'isla-expandida': '#ph-di-expanded'
};
const WIDGET_PIECES = {
  'widget-pequeno': '#p-w-s .wd',
  'widget-mediano': '#p-w-m .wd',
  'widget-grande': '#p-w-l .wd',
  'bloqueo-circular': '#p-lw-circ',
  'bloqueo-rectangular': '#p-lw-rect',
  'bloqueo-en-linea': '#p-lw-inline'
};
const LOCK_PIECES = { 'actividad-bloqueo': LA_PIECES['actividad-bloqueo'], 'bloqueo-circular': WIDGET_PIECES['bloqueo-circular'], 'bloqueo-rectangular': WIDGET_PIECES['bloqueo-rectangular'], 'bloqueo-en-linea': WIDGET_PIECES['bloqueo-en-linea'] };
const HOME = { 'widget-pequeno': WIDGET_PIECES['widget-pequeno'], 'widget-mediano': WIDGET_PIECES['widget-mediano'], 'widget-grande': WIDGET_PIECES['widget-grande'] };

// Escenas de la 2B.3 (las tres variantes) y las que añade la 2B.4 (solo A las trata).
const LA_SCENES_OLD = ['via-real', 'via-probable', 'sin-via', 'bus-1h46', 'linea-cortada', 'aviso', 'en-anden',
  'transbordo', 'transbordo-2', 'dato-antiguo', 'sin-conexion', 'terminado'];
const WIDGET_SCENES_OLD = ['via-real', 'via-probable', 'sin-via', 'bus-1h46', 'linea-cortada', 'aviso', 'en-anden',
  'transbordo', 'sin-conexion'];
const LA_SCENES_A = [...LA_SCENES_OLD, 'via-aparece', 'cambio-via', 'cancelado', 'servicio-finalizado', 'destinos-mezclados',
  'congelada-tren-salido', 'sin-clave', 'nombres-largos', 'terminado-a-mano'];
const WIDGET_SCENES_A = [...WIDGET_SCENES_OLD, 'cambio-via', 'cancelado', 'servicio-finalizado', 'destinos-mezclados',
  'congelada-tren-salido', 'sin-clave', 'sin-datos-recientes', 'nombres-largos'];
const MODES = { claro: { theme: 'light' }, oscuro: { theme: 'dark' } };
// Aspecto neutro: se fija en cada grupo para que una captura no herede el anterior.
const NEUTRAL = { tint: 'full', rt: false, num: 'app', aod: 0, sb: 0, hc: 0, dt: 'L', acc: 'calado', hits: 0, device: 'i16' };

const shots = [];
const W = 1860, H = 1000;
const set = o => `lab.set(${JSON.stringify(Object.assign({ t: T0 }, o))})`;
function group(v, look, scene, pieces, suffix, { dpr = 2, t } = {}) {
  let first = true;
  for (const [name, sel] of Object.entries(pieces)) {
    const o = Object.assign({ v }, NEUTRAL, look, { scene });
    if (t) o.t = t;
    shots.push({
      url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr,
      eval: first ? set(o) : undefined,
      waitMs: first ? 700 : 120, selector: sel,
      out: `${OUT}/${v}/${v}-${name}-${scene}-${suffix}.png`
    });
    first = false;
  }
}
const laPiecesFor = sc => sc === 'terminado' ? { 'actividad-bloqueo': LA_PIECES['actividad-bloqueo'] }
  : sc === 'terminado-a-mano' ? { 'actividad-bloqueo': '#p-la' } : LA_PIECES;
const view = (o, sel, out, { width = W, height = H, waitMs = 800 } = {}) =>
  shots.push({ url: '/b-cristal-v2/', sameUrl: true, width, height, dpr: 1, eval: set(Object.assign({}, NEUTRAL, o)), waitMs, selector: sel, out });

for (const v of TODAS ? ['A', 'B', 'C'] : ['A']) {
  const isA = v === 'A';
  // carga la variante (lámina, iPhone 16, sin panel, zoom 1)
  shots.push({ url: `/b-cristal-v2/?capture=1&v=${v}&view=lamina&device=i16&scene=via-real&theme=dark&tint=full&rt=0&rm=0&num=app&dt=L&hc=0&aod=0&sb=0&hits=0&t=${T0}`,
    width: W, height: H, dpr: 1, waitMs: 1800, out: `${OUT}/${v}/${v}-lamina-via-real-oscuro.png` });
  for (const [mode, look] of Object.entries(MODES)) {
    for (const sc of isA ? LA_SCENES_A : LA_SCENES_OLD) group(v, look, sc, laPiecesFor(sc), mode);
    for (const sc of isA ? WIDGET_SCENES_A : WIDGET_SCENES_OLD) group(v, look, sc, WIDGET_PIECES, mode);
    // teléfonos enteros, para ver las piezas en su sitio
    shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr: 1, eval: set(Object.assign({ v }, NEUTRAL, look, { scene: 'via-real' })), waitMs: 700, selector: '#ph-lock', out: `${OUT}/${v}/${v}-pantalla-bloqueo-via-real-${mode}.png` });
    shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr: 1, waitMs: 120, selector: '#ph-home1', out: `${OUT}/${v}/${v}-pantalla-inicio-1-via-real-${mode}.png` });
    shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr: 1, waitMs: 120, selector: '#ph-home2', out: `${OUT}/${v}/${v}-pantalla-inicio-2-via-real-${mode}.png` });
  }
  // iOS 26: inicio «tintado» y «transparente» (modo acentuado)
  for (const tint of ['tinted', 'clear']) for (const sc of isA ? ['via-real', 'via-probable', 'sin-conexion'] : ['via-real', 'via-probable'])
    group(v, { theme: 'dark', tint }, sc, HOME, tint === 'tinted' ? 'tintado' : 'transparente');
  // «Reducir transparencia»
  group(v, { theme: 'dark', tint: 'tinted', rt: true }, 'via-real', Object.assign({ 'actividad-bloqueo': LA_PIECES['actividad-bloqueo'] }, HOME, {
    'bloqueo-circular': WIDGET_PIECES['bloqueo-circular'], 'bloqueo-rectangular': WIDGET_PIECES['bloqueo-rectangular'] }), 'tintado-reducir-transparencia');
  group(v, { theme: 'light', rt: true }, 'via-real', { 'actividad-bloqueo': LA_PIECES['actividad-bloqueo'] }, 'claro-reducir-transparencia');
  // SE y Pro Max (el SE no tiene isla: banner)
  view({ v, device: 'se', scene: 'via-real', theme: 'dark' }, '.lam', `${OUT}/${v}/${v}-lamina-se-via-real-oscuro.png`);
  view({ v, device: 'max', scene: 'transbordo', theme: 'dark' }, '.lam', `${OUT}/${v}/${v}-lamina-promax-transbordo-oscuro.png`, { width: 1960, height: 1080 });

  if (!isA) continue;
  // ---- Solo A (2B.4): lo que el revisor pidió ver
  // Cifra: las otras dos versiones (P0-2)
  for (const [num, name] of [['sys', 'sistema'], ['ios17', 'ios17']]) for (const sc of ['via-real', 'via-probable', 'bus-1h46', 'dato-antiguo'])
    group(v, { theme: 'dark', num }, sc, Object.assign({}, LA_PIECES, WIDGET_PIECES), `${name}-oscuro`);
  // Acentuado con contorno (alternativa al calado, P3-23)
  for (const sc of ['via-real', 'via-probable']) group(v, { theme: 'dark', tint: 'tinted', acc: 'contorno' }, sc, HOME, 'tintado-contorno');
  // Pantalla siempre activa, StandBy de noche, Aumentar contraste (P3-20)
  for (const sc of ['via-real', 'dato-antiguo']) {
    group(v, { theme: 'dark', aod: 1 }, sc, LOCK_PIECES, 'siempre-activa');
    group(v, { theme: 'dark', sb: 1 }, sc, LOCK_PIECES, 'standby-noche');
  }
  for (const [mode, look] of Object.entries(MODES)) for (const sc of ['via-probable', 'dato-antiguo'])
    group(v, Object.assign({ hc: 1 }, look), sc, Object.assign({}, LOCK_PIECES, HOME, { 'isla-expandida': LA_PIECES['isla-expandida'] }), `aumentar-contraste-${mode}`);
  // Dynamic Type: xLarge (el tope de la Live Activity) y AX3 (con los topes)
  for (const dt of ['XL', 'AX3']) for (const sc of ['via-real', 'transbordo', 'dato-antiguo'])
    group(v, { theme: 'dark', dt }, sc, Object.assign({}, LA_PIECES, WIDGET_PIECES), `texto-${dt.toLowerCase()}-oscuro`);
  // El tren ya salió y no hay dato nuevo: congelada (la app paró a las 12:55:40) y sin conexión (desde las 12:50)
  group(v, { theme: 'dark' }, 'congelada-tren-salido', LA_PIECES, 'oscuro-1257-30');
  shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr: 2, eval: `${set(Object.assign({ v }, NEUTRAL, { theme: 'dark', scene: 'sin-conexion' }))}; lab.set({t:'12:58:00'})`, waitMs: 800, selector: '#p-la .la', out: `${OUT}/${v}/${v}-actividad-bloqueo-sin-conexion-oscuro-1258.png` });
  shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: W, height: H, dpr: 2, waitMs: 120, selector: '#ph-di-compact', out: `${OUT}/${v}/${v}-isla-compacta-sin-conexion-oscuro-1258.png` });
  group(v, { theme: 'dark' }, 'via-real', { 'actividad-bloqueo': LA_PIECES['actividad-bloqueo'], 'isla-compacta': LA_PIECES['isla-compacta'], 'isla-minima': LA_PIECES['isla-minima'] }, 'oscuro-ya-1256-20', { t: '12:56:20' });
  // Láminas enteras de casos que el revisor marcó
  view({ v, device: 'se', scene: 'aviso', theme: 'dark' }, '.lam', `${OUT}/${v}/${v}-lamina-se-aviso-oscuro.png`);
  view({ v, device: 'se', scene: 'nombres-largos', theme: 'dark' }, '.lam', `${OUT}/${v}/${v}-lamina-se-nombres-largos-oscuro.png`);
  view({ v, scene: 'dato-antiguo', theme: 'light' }, '.lam', `${OUT}/${v}/${v}-lamina-dato-antiguo-claro.png`);
  view({ v, scene: 'congelada-tren-salido', theme: 'dark' }, '.lam', `${OUT}/${v}/${v}-lamina-congelada-tren-salido-oscuro.png`);
  view({ v, scene: 'via-real', theme: 'dark', hits: 1 }, '.lam', `${OUT}/${v}/${v}-lamina-enlaces-y-areas-oscuro.png`);
  view({ v, scene: 'transbordo', theme: 'dark', dt: 'AX3' }, '.lam', `${OUT}/${v}/${v}-lamina-texto-ax3-oscuro.png`);
  // Vistas propias de A: casos límite de la isla y la actividad viva frente a la congelada
  view({ view: 'limites', scene: 'via-real', theme: 'dark' }, '.cmp', `${OUT}/${v}/${v}-casos-limite-isla-i16-oscuro.png`, { width: 1500, height: 2600 });
  view({ view: 'limites', device: 'max', scene: 'via-real', theme: 'dark' }, '.cmp', `${OUT}/${v}/${v}-casos-limite-isla-promax-oscuro.png`, { width: 1500, height: 2600 });
  view({ view: 'congelada', scene: 'via-real', theme: 'dark', t: '12:56:40', fz: '12:55:40' }, '.vc', `${OUT}/${v}/${v}-viva-y-congelada-1256-40-oscuro.png`, { width: 1400, height: 900 });
  view({ view: 'congelada', scene: 'via-real', theme: 'dark', t: '12:58:10', fz: '12:55:40' }, '.vc', `${OUT}/${v}/${v}-viva-y-congelada-1258-10-oscuro.png`, { width: 1400, height: 900 });
}

// Las tres variantes lado a lado, por escenario (vista «comparar»: A con la 2B.4, B y C como en la 2B.3)
shots.push({ url: `/b-cristal-v2/?capture=1&view=comparar&device=i16&scene=via-real&theme=dark&tint=full&rt=0&num=app&dt=L&hc=0&aod=0&sb=0&hits=0&t=${T0}`, width: 1500, height: 2000, dpr: 1, waitMs: 1600, selector: '.cmp', out: `${OUT}/comparar/comparar-via-real-oscuro.png` });
for (const sc of [...LA_SCENES_OLD.slice(1), 'cambio-via', 'cancelado', 'destinos-mezclados', 'congelada-tren-salido', 'sin-clave'])
  view({ view: 'comparar', scene: sc, theme: 'dark' }, '.cmp', `${OUT}/comparar/comparar-${sc}-oscuro.png`, { width: 1500, height: 2000 });
for (const sc of ['via-real', 'via-probable', 'sin-conexion', 'dato-antiguo'])
  view({ view: 'comparar', scene: sc, theme: 'light' }, '.cmp', `${OUT}/comparar/comparar-${sc}-claro.png`, { width: 1500, height: 2000 });
view({ view: 'comparar', scene: 'via-probable', theme: 'dark', tint: 'tinted' }, '.cmp', `${OUT}/comparar/comparar-via-probable-tintado.png`, { width: 1500, height: 2000 });
view({ view: 'comparar', scene: 'via-real', theme: 'dark', tint: 'clear', rt: true }, '.cmp', `${OUT}/comparar/comparar-via-real-transparente-reducir-transparencia.png`, { width: 1500, height: 2000 });
view({ view: 'comparar', device: 'se', scene: 'via-real', theme: 'dark' }, '.cmp', `${OUT}/comparar/comparar-se-via-real-oscuro.png`, { width: 1500, height: 2000 });
view({ view: 'comparar', device: 'max', scene: 'via-real', theme: 'dark' }, '.cmp', `${OUT}/comparar/comparar-promax-via-real-oscuro.png`, { width: 1500, height: 2000 });

// GIF 1 · la cuenta atrás de A con la app escribiendo y con la app parada a las 12:55:40
// (reloj ×60: un minuto por segundo). Sin la app, la actividad NO pasa al tren siguiente:
// al vencer staleDate enseña la hora fija del tren que toca y «sin actualizar».
shots.push({ url: `/b-cristal-v2/?capture=1&view=congelada&fz=12:55:40&device=i16&scene=via-real&theme=dark&tint=full&rt=0&num=app&dt=L&hc=0&aod=0&sb=0&hits=0&t=12:54:40`, width: 1400, height: 900, dpr: 1,
  eval: "lab.set({view:'congelada', fz:'12:55:40', t:'12:54:40', speed:60})", waitMs: 400, selector: '.vc',
  gif: { frames: 36, intervalMs: 200, width: 1000 }, out: `${OUT}/gif-cuenta-atras-A.gif` });
// GIF 2 · la vía aparece: la actividad de bloqueo y la isla expandida con la franja de vía
shots.push({ url: '/b-cristal-v2/', sameUrl: true, width: 1500, height: 2000, dpr: 1,
  eval: "lab.set({view:'comparar', t:'12:50:00', speed:1, scene:'sin-via', theme:'dark'}); setTimeout(() => Trajet.scenarios.set({ platform: 'real' }), 900)", waitMs: 150, selector: '.crow:nth-child(4) .ccell:nth-child(2)',
  gif: { frames: 26, intervalMs: 110, width: 420 }, out: `${OUT}/gif-aparece-la-via-A.gif` });
// GIF 3 · el morph de la isla: compacta → expandida (la alerta) → compacta → mínima → compacta
shots.push({ url: `/b-cristal-v2/?capture=1&v=A&view=lamina&device=i16&scene=via-real&theme=dark&tint=full&rt=0&num=app&dt=L&hc=0&aod=0&sb=0&hits=0&island=compact&t=${T0}`, width: W, height: H, dpr: 2,
  eval: "lab.set({speed:1}); lab.island('compact'); setTimeout(() => lab.island('expanded'), 500); setTimeout(() => lab.island('compact'), 2600); setTimeout(() => lab.island('minimal'), 3700); setTimeout(() => lab.island('compact'), 4900)",
  waitMs: 100, selector: '#ph-di-demo', gif: { frames: 56, intervalMs: 95, width: 560 }, out: `${OUT}/gif-isla-morph-A.gif` });

const here = dirname(fileURLToPath(import.meta.url));
const plan = { base: `http://localhost:${PORT}`, shots: shots.map(s => { const o = Object.assign({}, s); if (o.eval === undefined) delete o.eval; return o; }) };
writeFileSync(join(here, 'plan-capturas.json'), JSON.stringify(plan, null, 1));
console.log(`${plan.shots.length} capturas en ${join(here, 'plan-capturas.json')}`);
