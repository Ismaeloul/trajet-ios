// Tokens del sistema de diseño «Cristal» (dirección B), en una sola fuente.
//
//   node design-lab/tools/tokens.mjs            genera y comprueba
//   node design-lab/tools/tokens.mjs --check    solo comprueba (no escribe nada)
//   node design-lab/tools/tokens.mjs --check --list   ... y lista los hex
//
// Qué hace:
//   1. Convierte cada color OKLCH a sRGB con las matrices de Björn Ottosson
//      (las mismas que usa CSS Color 4). Si un color cae fuera de la gama
//      sRGB, lo lleva dentro con el algoritmo de mapeo de gama de CSS Color 4
//      (reducir croma en OKLCH hasta ΔEok < 0,02) y lo avisa.
//   2. Calcula los compuestos (un color con alfa encima de su fondo) para el
//      modo «Reducir transparencia» y para medir contrastes reales.
//   3. Comprueba contra WCAG 2.x todas las parejas texto/fondo que usa la app,
//      en claro, oscuro y con «Aumentar contraste». Si alguna falla, sale con
//      código 1 y no escribe nada.
//   4. Traduce las curvas de B (cubic-bezier) a muelles de SwiftUI.
//   5. Escribe:
//        design-lab/tokens.json                          (formato máquina)
//        Trajet/Design/Tokens.swift                      (solo el bloque generado)
//        Trajet/Assets.xcassets/AccentColor.colorset     (tinte del sistema)
//        Trajet/Assets.xcassets/LaunchBackground.colorset
//        docs/diseno/sistema.md                          (solo los bloques generados)
//
// Sin dependencias: Node 18+.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const P = (...p) => resolve(ROOT, ...p);
const CHECK_ONLY = process.argv.includes('--check');

// =====================================================================
// 1. Color: OKLCH <-> sRGB
// =====================================================================
const toLinear = x => (x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4);
const toGamma = x => { const s = Math.sign(x), a = Math.abs(x); return s * (a <= 0.0031308 ? 12.92 * a : 1.055 * a ** (1 / 2.4) - 0.055); };

function oklabToLinear([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3;
  return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
}
function linearToOklab([r, g, b]) {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
}
const lchToLab = ([L, C, h]) => [L, C * Math.cos(h * Math.PI / 180), C * Math.sin(h * Math.PI / 180)];
const labToLch = ([L, a, b]) => { const C = Math.hypot(a, b); let h = Math.atan2(b, a) * 180 / Math.PI; if (h < 0) h += 360; return [L, C, C < 1e-4 ? 0 : h]; };
const lchToSrgb = lch => oklabToLinear(lchToLab(lch)).map(toGamma);
const srgbToLch = rgb => labToLch(linearToOklab(rgb.map(toLinear)));
const inGamut = rgb => rgb.every(v => v >= -1e-5 && v <= 1 + 1e-5);
const clip = rgb => rgb.map(v => Math.min(1, Math.max(0, v)));
const deltaEOK = (x, y) => { const a = linearToOklab(x.map(toLinear)), b = linearToOklab(y.map(toLinear)); return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]); };

/** Mapeo de gama de CSS Color 4 (§13.2), destino sRGB. */
function gamutMap([L, C, h]) {
  if (L >= 1) return { rgb: [1, 1, 1], mapped: false };
  if (L <= 0) return { rgb: [0, 0, 0], mapped: false };
  const origin = lchToSrgb([L, C, h]);
  if (inGamut(origin)) return { rgb: clip(origin), mapped: false };
  const JND = 0.02, EPS = 0.0001;
  let clipped = clip(origin);
  if (deltaEOK(clipped, origin) < JND) return { rgb: clipped, mapped: true };
  let min = 0, max = C, minInGamut = true;
  while (max - min > EPS) {
    const chroma = (min + max) / 2;
    const current = lchToSrgb([L, chroma, h]);
    if (minInGamut && inGamut(current)) { min = chroma; continue; }
    clipped = clip(current);
    const E = deltaEOK(clipped, current);
    if (E < JND) { if (JND - E < EPS) return { rgb: clipped, mapped: true }; minInGamut = false; min = chroma; }
    else max = chroma;
  }
  return { rgb: clipped, mapped: true };
}

/** "oklch(62% 0.2 255 / .5)" o "#RRGGBB" -> { rgb:[0..1], a, lch, mapped } */
function parseColor(str) {
  str = str.trim();
  if (str.startsWith('#')) {
    const v = parseInt(str.slice(1, 7), 16);
    const rgb = [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
    return { rgb, a: 1, lch: srgbToLch(rgb), mapped: false, src: str };
  }
  const m = str.match(/^oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+))?\s*\)$/);
  if (!m) throw new Error('Color ilegible: ' + str);
  const lch = [Number(m[1]) / 100, Number(m[2]), Number(m[3])];
  const { rgb, mapped } = gamutMap(lch);
  return { rgb, a: m[4] != null ? Number(m[4]) : 1, lch, mapped, src: str };
}
const hex = rgb => '#' + clip(rgb).map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
const hexA = (rgb, a) => hex(rgb) + (a < 1 ? Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase() : '');
const fmtLch = ([L, C, h], a = 1) => `oklch(${+(L * 100).toFixed(1)}% ${+C.toFixed(3)} ${+h.toFixed(1)}${a < 1 ? ' / ' + +a.toFixed(2) : ''})`;
/** Compuesto en sRGB con gamma, como lo pintan el navegador y Core Animation. */
const over = (fg, a, bg) => fg.map((v, i) => v * a + bg[i] * (1 - a));

// WCAG 2.x
const lum = rgb => { const [r, g, b] = clip(rgb).map(toLinear); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const contrast = (x, y) => { const [a, b] = [lum(x), lum(y)].sort((p, q) => q - p); return (a + 0.05) / (b + 0.05); };

// =====================================================================
// 2. La paleta. «b» = el valor que traía B cuando se ha corregido.
//    light/dark obligatorios; lightHC/darkHC = «Aumentar contraste»
//    (si faltan, se usa el normal).
// =====================================================================
const NEUTRAL = '0.005 260';
const COLORS = [
  // ---------------- neutros de fondo ----------------
  { name: 'bg', css: '--bg', group: 'fondo', rol: 'Fondo de pantalla (debajo del mapa y de las listas).',
    light: 'oklch(96% 0.003 260)', dark: `oklch(12% ${NEUTRAL})` },
  { name: 'surface', css: '--card (opaca)', group: 'fondo', rol: 'Tarjeta OPACA (tramo, ruta, opción). B la hacía translúcida; aquí es el compuesto de B sobre el fondo, sin transparencia (regla 1: ningún minuto sobre cristal).',
    light: 'oklch(99.2% 0.001 260)', dark: `oklch(18.5% ${NEUTRAL})`,
    b: { light: 'oklch(100% 0 0 / .78)', dark: `oklch(20% ${NEUTRAL} / .72)` } },
  { name: 'surfaceHi', css: '--rule sobre --card', group: 'fondo', rol: 'Ficha dentro de una tarjeta (salidas 2.ª–4.ª), campos, segmentos. Opaca.',
    light: 'oklch(93.5% 0.004 260)', dark: `oklch(27% ${NEUTRAL})` },
  { name: 'rule', css: '--rule', group: 'fondo', rol: 'Filetes y separadores (con alfa).',
    light: 'oklch(0% 0 0 / .08)', dark: 'oklch(100% 0 0 / .1)', lightHC: 'oklch(0% 0 0 / .22)', darkHC: 'oklch(100% 0 0 / .28)' },
  // ---------------- tinta ----------------
  { name: 'ink', css: '--ink', group: 'tinta', rol: 'Texto principal.',
    light: 'oklch(15% 0.01 260)', dark: 'oklch(97% 0 0)', lightHC: 'oklch(5% 0 0)', darkHC: 'oklch(100% 0 0)' },
  { name: 'ink2', css: '--ink-2', group: 'tinta', rol: 'Texto secundario (dirección, destino de fichas, metadatos).',
    light: 'oklch(40% 0.01 260)', dark: 'oklch(78% 0.01 260)', lightHC: 'oklch(27% 0.01 260)', darkHC: 'oklch(88% 0.005 260)',
    b: { light: 'oklch(42% 0.01 260)', dark: 'oklch(72% 0.01 260)' } },
  { name: 'ink3', css: '--ink-3', group: 'tinta', rol: 'Texto terciario (rótulos de sección, pie, «min» de las fichas). En B no llegaba a AA: 3,8:1 en claro y 3,0:1 sobre las fichas en oscuro.',
    light: 'oklch(48% 0.01 260)', dark: 'oklch(71% 0.01 260)', lightHC: 'oklch(32% 0.01 260)', darkHC: 'oklch(84% 0.005 260)',
    b: { light: 'oklch(58% 0.01 260)', dark: 'oklch(55% 0.01 260)' } },
  // ---------------- cristal (capa de controles) ----------------
  { name: 'glass', css: '--glass', group: 'cristal', rol: 'Relleno del cristal en iOS 17–25 (encima del material). En iOS 26 lo pone el sistema.',
    light: 'oklch(100% 0 0 / .58)', dark: `oklch(20% ${NEUTRAL} / .55)`, lightHC: 'oklch(100% 0 0 / .85)', darkHC: `oklch(20% ${NEUTRAL} / .85)` },
  { name: 'glassHighlight', css: '--glass-hi', group: 'cristal', rol: 'Brillo del canto superior del cristal (iOS 17–25).',
    light: 'oklch(100% 0 0 / .8)', dark: 'oklch(100% 0 0 / .12)' },
  { name: 'glassEdge', css: '--glass-edge', group: 'cristal', rol: 'Canto del cristal (1 pt). Con «Aumentar contraste», visible de verdad.',
    light: 'oklch(100% 0 0 / .6)', dark: 'oklch(100% 0 0 / .14)', lightHC: 'oklch(0% 0 0 / .45)', darkHC: 'oklch(100% 0 0 / .45)' },
  { name: 'glassOpaque', css: '(nuevo)', group: 'cristal', rol: 'Cristal con «Reducir transparencia»: compuesto opaco de --glass sobre el fondo.',
    light: 'oklch(98.3% 0.001 260)', dark: `oklch(16.8% ${NEUTRAL})` },
  // ---------------- el billete (cápsula opaca de minutos) ----------------
  { name: 'ticket', css: '--solid', group: 'billete', rol: 'Fondo del billete: invierte el tema para que los minutos salten a contraluz.',
    light: 'oklch(15% 0.01 260)', dark: 'oklch(98% 0 0)', lightHC: 'oklch(5% 0 0)', darkHC: 'oklch(100% 0 0)' },
  { name: 'ticketInk', css: '--solid-ink', group: 'billete', rol: 'Minutos y destino en el billete (AAA).',
    light: 'oklch(100% 0 0)', dark: 'oklch(12% 0 0)', lightHC: 'oklch(100% 0 0)', darkHC: 'oklch(0% 0 0)' },
  { name: 'ticketInk2', css: '--solid-ink × .7/.75', group: 'billete', rol: 'Unidad «min», hora y longitud en el billete. Opaco (B usaba opacidad .7–.75).',
    light: 'oklch(80% 0.005 260)', dark: 'oklch(38% 0.005 260)', lightHC: 'oklch(90% 0 0)', darkHC: 'oklch(25% 0 0)' },
  { name: 'ticketWarn', css: '(nuevo)', group: 'billete', rol: 'Retraso dentro del billete. B usaba --warn, que sobre el billete blanco del modo oscuro daba 2,1:1.',
    light: 'oklch(82% 0.14 72)', dark: 'oklch(50% 0.13 55)', lightHC: 'oklch(88% 0.12 78)', darkHC: 'oklch(42% 0.11 50)' },
  { name: 'pace', css: 'oklch(50% 0 0 / .25)', group: 'billete', rol: 'Fondo de la etiqueta de ritmo «Anda» / «Con calma» (con alfa, sobre el billete).',
    light: 'oklch(50% 0 0 / .35)', dark: 'oklch(50% 0 0 / .25)' },
  // ---------------- la vía ----------------
  { name: 'via', css: '--via', group: 'vía', rol: 'Caja sólida de la vía CONFIRMADA. Único uso del amarillo (B lo usaba también para «sin conexión»: se quita).',
    light: 'oklch(88% 0.17 92)', dark: 'oklch(88% 0.17 92)' },
  { name: 'viaInk', css: '--via-ink', group: 'vía', rol: 'Texto dentro de la caja de vía (AAA).',
    light: 'oklch(18% 0.02 80)', dark: 'oklch(18% 0.02 80)' },
  { name: 'viaEdge', css: '(nuevo)', group: 'vía', rol: 'Canto de 1 pt de la caja de vía, siempre. Hace falta sobre lo claro (tarjetas en modo claro y billete blanco en modo oscuro), donde el amarillo solo da 1,3:1 y la caja se desdibuja.',
    light: 'oklch(58% 0.12 85)', dark: 'oklch(58% 0.12 85)', lightHC: 'oklch(42% 0.09 85)', darkHC: 'oklch(42% 0.09 85)' },
  // ---------------- interacción ----------------
  { name: 'accent', css: '--accent', group: 'interacción', rol: 'Azul para texto e iconos interactivos (enlaces, pestaña activa, «Guardar»). Es el tinte de la app (AccentColor).',
    light: 'oklch(52% 0.2 258)', dark: 'oklch(68% 0.16 252)', lightHC: 'oklch(43% 0.19 262)', darkHC: 'oklch(78% 0.12 250)',
    b: { light: 'oklch(62% 0.2 255)', dark: 'oklch(62% 0.2 255)' } },
  { name: 'accentFill', css: '--accent (relleno)', group: 'interacción', rol: 'Relleno del botón principal con texto blanco (B daba 3,7:1).',
    light: 'oklch(53% 0.21 258)', dark: 'oklch(53% 0.21 258)', lightHC: 'oklch(44% 0.2 262)', darkHC: 'oklch(46% 0.2 262)',
    b: { light: 'oklch(62% 0.2 255)', dark: 'oklch(62% 0.2 255)' } },
  { name: 'onAccent', css: '#fff', group: 'interacción', rol: 'Texto sobre accentFill y sobre bad.', light: 'oklch(100% 0 0)', dark: 'oklch(100% 0 0)' },
  // ---------------- estados (con cuentagotas) ----------------
  { name: 'warn', css: '--warn', group: 'estado', rol: 'Perturbada: icono y fondo del aviso (con alfa). No es color de texto en claro.',
    light: 'oklch(76% 0.16 65)', dark: 'oklch(76% 0.16 65)' },
  { name: 'warnText', css: '(nuevo)', group: 'estado', rol: 'Texto de aviso: «Perturbada», «+2 min», «cualquier sentido». B usaba --warn: 2,0:1 en claro.',
    light: 'oklch(50% 0.13 55)', dark: 'oklch(80% 0.15 72)', lightHC: 'oklch(41% 0.11 50)', darkHC: 'oklch(87% 0.12 78)' },
  { name: 'noticeWarn', css: 'oklch(76% .16 65 / .16)', group: 'estado', rol: 'Fondo del aviso de línea perturbada (sobre la tarjeta).',
    light: 'oklch(76% 0.16 65 / .18)', dark: 'oklch(76% 0.16 65 / .16)' },
  { name: 'bad', css: '--bad', group: 'estado', rol: 'Interrumpida / peligro: relleno de «Corre», del botón rojo y del banner de línea cortada (texto blanco encima).',
    light: 'oklch(55% 0.2 25)', dark: 'oklch(55% 0.2 25)', lightHC: 'oklch(47% 0.18 25)', darkHC: 'oklch(47% 0.18 25)',
    b: { light: 'oklch(60% 0.21 25)', dark: 'oklch(60% 0.21 25)' } },
  { name: 'badText', css: '(nuevo)', group: 'estado', rol: 'Texto de error: «Interrumpida», «pasa por la línea cortada», «Eliminar ruta».',
    light: 'oklch(50% 0.19 25)', dark: 'oklch(72% 0.16 22)', lightHC: 'oklch(41% 0.16 25)', darkHC: 'oklch(82% 0.11 20)' },
  { name: 'noticeBad', css: 'oklch(60% .21 25 / .18)', group: 'estado', rol: 'Fondo del aviso de línea interrumpida.',
    light: 'oklch(60% 0.21 25 / .14)', dark: 'oklch(60% 0.21 25 / .2)' },
  { name: 'ok', css: '--ok', group: 'estado', rol: 'Relleno verde: billete «En andén», interruptores, punto «en directo» en oscuro.',
    light: 'oklch(72% 0.17 155)', dark: 'oklch(72% 0.17 155)' },
  { name: 'okText', css: '(nuevo)', group: 'estado', rol: 'Texto e iconos verdes (punto «en directo» y «listo» en claro; B daba 2,1:1).',
    light: 'oklch(50% 0.13 155)', dark: 'oklch(76% 0.16 155)', lightHC: 'oklch(40% 0.1 155)', darkHC: 'oklch(85% 0.13 155)' },
  { name: 'atStopInk', css: '#0a1a10', group: 'estado', rol: 'Texto sobre el billete verde «En andén» (AAA).',
    light: 'oklch(19% 0.03 155)', dark: 'oklch(19% 0.03 155)' },
  // ---------------- sombra y mapa ----------------
  { name: 'shadow', css: 'oklch(0% 0 0 / …)', group: 'sombra', rol: 'Color base de las sombras (la opacidad va en cada sombra).', light: 'oklch(0% 0 0)', dark: 'oklch(0% 0 0)' },
  { name: 'mapCasing', css: 'casing (map.js)', group: 'mapa', rol: 'Contorno del trazado de la línea en el mapa.', light: 'oklch(100% 0 0)', dark: 'oklch(0% 0 0)' },
  { name: 'mapStopFill', css: 'stopFill (app.js)', group: 'mapa', rol: 'Relleno de las paradas servidas.', light: 'oklch(100% 0 0)', dark: '#131417' },
  { name: 'mapWalk', css: 'walkColor (map.js)', group: 'mapa', rol: 'Punteado del camino a pie.', light: '#2A2A2E', dark: '#E6E6EA' },
  { name: 'lineFallback', css: 'line.fallback', group: 'línea', rol: 'Gris de reserva cuando la API no manda color de línea (R57).', light: '#6B7380', dark: '#6B7380' },
];

// Colores con alfa: sobre qué se componen para «Reducir transparencia».
const OPAQUE_OVER = { glass: 'bg', rule: 'surface', noticeWarn: 'surface', noticeBad: 'surface', pace: 'ticket' };

const VARIANTS = ['light', 'dark', 'lightHC', 'darkHC'];
const RES = {};
for (const c of COLORS) {
  RES[c.name] = {};
  for (const v of VARIANTS) {
    const src = c[v] || c[v.replace('HC', '')];
    RES[c.name][v] = parseColor(src);
  }
}
const col = (name, v) => { const r = RES[name]; if (!r) throw new Error('Token desconocido: ' + name); return r[v]; };
/** Color opaco de un token sobre un fondo (compuesto si tiene alfa). */
function solidOf(name, v, onName) {
  const c = col(name, v);
  if (c.a >= 1) return c.rgb;
  const base = onName ? solidOf(onName, v) : solidOf(OPAQUE_OVER[name] || 'bg', v);
  return over(c.rgb, c.a, base);
}

// =====================================================================
// 3. Contrastes que se garantizan. [texto, fondo, mínimo, mínimo con HC, qué es]
//    Fondo «a>b» = el token a compuesto sobre b.
// =====================================================================
const AA = 4.5, AAA = 7, UI = 3;
const CHECKS = [
  ['ink', 'bg', AAA, AAA, 'texto principal'],
  ['ink', 'surface', AAA, AAA, 'texto en tarjeta'],
  ['ink2', 'bg', AA, AAA, 'secundario'],
  ['ink2', 'surface', AA, AAA, 'secundario en tarjeta'],
  ['ink2', 'surfaceHi', AA, AAA, 'secundario en ficha'],
  ['ink3', 'bg', AA, AAA, 'terciario (rótulos, pie)'],
  ['ink3', 'surface', AA, AAA, 'terciario en tarjeta'],
  ['ink3', 'surfaceHi', AA, AAA, 'terciario en ficha («min», hora)'],
  ['ink', 'surfaceHi', AAA, AAA, 'minutos de las fichas'],
  ['ink', 'glassOpaque', AAA, AAA, 'texto en cristal opaco'],
  ['ink2', 'glassOpaque', AA, AAA, 'secundario en cristal opaco'],
  ['ticketInk', 'ticket', AAA, AAA, 'MINUTOS en el billete'],
  ['ticketInk2', 'ticket', AA, AAA, '«min», hora y longitud en el billete'],
  ['ticketWarn', 'ticket', AA, AAA, 'retraso en el billete'],
  ['ticketInk', 'pace>ticket', AA, AAA, 'etiqueta de ritmo'],
  ['viaInk', 'via', AAA, AAA, 'VÍA confirmada'],
  ['accent', 'bg', AA, AAA, 'enlace sobre fondo'],
  ['accent', 'surface', AA, AAA, 'enlace en tarjeta'],
  ['accent', 'glassOpaque', AA, AAA, 'enlace en cristal opaco'],
  ['onAccent', 'accentFill', AA, AAA, 'botón principal'],
  ['warnText', 'bg', AA, AAA, 'aviso sobre fondo'],
  ['warnText', 'surface', AA, AAA, 'aviso en tarjeta'],
  ['warnText', 'surfaceHi', AA, AAA, 'retraso en ficha'],
  ['warnText', 'noticeWarn>surface', AA, AAA, 'rótulo del aviso'],
  ['ink', 'noticeWarn>surface', AAA, AAA, 'texto del aviso'],
  ['badText', 'bg', AA, AAA, 'error sobre fondo'],
  ['badText', 'surface', AA, AAA, 'error en tarjeta'],
  ['badText', 'noticeBad>surface', AA, AAA, 'rótulo del aviso interrumpido'],
  ['ink', 'noticeBad>surface', AAA, AAA, 'texto del aviso interrumpido'],
  ['onAccent', 'bad', AA, AAA, '«Corre», botón rojo'],
  ['okText', 'bg', AA, AAA, '«listo», en directo'],
  ['okText', 'surface', AA, AAA, '«listo» en tarjeta'],
  ['atStopInk', 'ok', AAA, AAA, 'billete «En andén»'],
  ['via', 'ticket', UI, UI, 'caja de vía sobre el billete oscuro (forma)', ['light', 'lightHC']],
  ['viaEdge', 'ticket', UI, UI, 'canto de la caja de vía sobre el billete blanco (forma)', ['dark', 'darkHC']],
  ['viaEdge', 'surface', UI, UI, 'canto de la caja de vía en tarjeta clara (forma)', ['light', 'lightHC']],
  ['viaEdge', 'surfaceHi', UI, UI, 'canto de la caja de vía en ficha clara (forma)', ['light', 'lightHC']],
  ['via', 'surfaceHi', UI, UI, 'caja de vía en ficha oscura (forma)', ['dark', 'darkHC']],
  // En oscuro con HC el relleno baja a 46 % para dar 7:1 al texto blanco y contra el fondo queda en ~2,7:1;
  // la etiqueta identifica el botón (WCAG 1.4.11 no pide el borde), así que esa variante no se exige.
  ['accentFill', 'bg', UI, UI, 'botón principal contra el fondo (forma)', ['light', 'dark', 'lightHC']],
  ['glassEdge', 'bg', 1, UI, 'canto del cristal con Aumentar contraste (forma)', ['lightHC', 'darkHC']],
];
function bgOf(spec, v) {
  if (spec.includes('>')) { const [a, b] = spec.split('>'); return over(col(a, v).rgb, col(a, v).a, solidOf(b, v)); }
  return solidOf(spec, v);
}
const checkRows = [];
let failures = 0;
for (const [fg, bgSpec, min, minHC, what, only] of CHECKS) {
  for (const v of (only || VARIANTS)) {
    const need = v.endsWith('HC') ? minHC : min;
    const bg = bgOf(bgSpec, v);
    const f = col(fg, v);
    const fgRgb = f.a < 1 ? over(f.rgb, f.a, bg) : f.rgb;
    const r = contrast(fgRgb, bg);
    const ok = r + 1e-9 >= need;
    if (!ok) failures++;
    checkRows.push({ fg, bg: bgSpec, variant: v, ratio: +r.toFixed(2), min: need, ok, what });
  }
}

// Lo que traía B, para el documento (antes → después).
const B_RAW = {
  light: { bg: 'oklch(96% 0.003 260)', card: 'oklch(100% 0 0 / .78)', rule: 'oklch(0% 0 0 / .08)', ink: 'oklch(15% 0.01 260)', ink2: 'oklch(42% 0.01 260)', ink3: 'oklch(58% 0.01 260)', solid: 'oklch(15% 0.01 260)', solidInk: '#FFFFFF', warn: 'oklch(76% 0.16 65)', bad: 'oklch(60% 0.21 25)', ok: 'oklch(72% 0.17 155)', accent: 'oklch(62% 0.2 255)' },
  dark: { bg: `oklch(12% ${NEUTRAL})`, card: `oklch(20% ${NEUTRAL} / .72)`, rule: 'oklch(100% 0 0 / .1)', ink: 'oklch(97% 0 0)', ink2: 'oklch(72% 0.01 260)', ink3: 'oklch(55% 0.01 260)', solid: 'oklch(98% 0 0)', solidInk: 'oklch(12% 0 0)', warn: 'oklch(76% 0.16 65)', bad: 'oklch(60% 0.21 25)', ok: 'oklch(72% 0.17 155)', accent: 'oklch(62% 0.2 255)' }
};
const bRows = [];
for (const t of ['light', 'dark']) {
  const g = k => parseColor(B_RAW[t][k]);
  const bg = g('bg').rgb, card = over(g('card').rgb, g('card').a, bg), chip = over(g('rule').rgb, g('rule').a, card);
  const W = [1, 1, 1];
  const rows = [
    ['--ink-3 sobre --bg', g('ink3').rgb, bg], ['--ink-3 sobre ficha', g('ink3').rgb, chip],
    ['--warn (texto) sobre --bg', g('warn').rgb, bg], ['--warn sobre el billete', g('warn').rgb, g('solid').rgb],
    ['--bad (texto) sobre --bg', g('bad').rgb, bg], ['blanco sobre --bad', W, g('bad').rgb],
    ['--ok (punto) sobre --bg', g('ok').rgb, bg], ['--accent (texto) sobre --bg', g('accent').rgb, bg], ['blanco sobre --accent', W, g('accent').rgb],
  ];
  for (const [n, a, b] of rows) bRows.push({ theme: t, what: n, ratio: +contrast(a, b).toFixed(2) });
}

// =====================================================================
// 4. Colores de línea: tinta del distintivo (R12)
// =====================================================================
const hexRgb = h => { const v = parseInt(h.replace('#', ''), 16); return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255]; };
const BLACK = [0, 0, 0], WHITE = [1, 1, 1];
function badgeInk(color, official) {
  const c = hexRgb(color);
  const cb = contrast(c, BLACK), cw = contrast(c, WHITE);
  const best = cb >= cw ? { ink: '#000000', r: cb } : { ink: '#FFFFFF', r: cw };
  if (official) {
    const ro = contrast(c, hexRgb(official));
    if (ro >= AA) return { ink: '#' + official.replace('#', '').toUpperCase(), r: ro, source: 'oficial' };
    return { ...best, source: 'calculada', officialRatio: ro };
  }
  return { ...best, source: 'calculada' };
}
const oldInk = color => (lum(hexRgb(color)) > 0.45 ? '#000000' : '#FFFFFF');
const lineData = JSON.parse(readFileSync(P('design-lab/tools/lineas-idfm.json'), 'utf8'));
const LAB_LINES = [ // colores de PreviewData.swift y del laboratorio (valores antiguos del referencial)
  ['E (lab)', 'B94E9A'], ['13 (lab)', '82C8E6'], ['A (lab)', 'E3051C'], ['T2 (lab)', 'C4318E'], ['4 (lab)', 'BE418D'],
  ['6 (lab)', '6ECA97'], ['147 (lab)', 'E4022D'], ['6424 (lab)', 'A50034'], ['naranja de prueba', 'FF7E2E'], ['reserva (R57)', '6B7380']];
const lineRows = [
  ...lineData.lineas.map(l => ({ code: l.code, modo: l.modo, color: '#' + l.color, official: '#' + l.texto })),
  ...LAB_LINES.map(([code, color]) => ({ code, modo: 'lab', color: '#' + color, official: null }))
].map(l => {
  const b = badgeInk(l.color, l.official);
  const old = oldInk(l.color);
  return { ...l, ink: b.ink, ratio: +b.r.toFixed(2), source: b.source, officialRatio: l.official ? +contrast(hexRgb(l.color), hexRgb(l.official)).toFixed(2) : null,
    oldInk: old, oldRatio: +contrast(hexRgb(l.color), hexRgb(old)).toFixed(2) };
});
const lineFails = lineRows.filter(l => l.ratio < AA);
if (lineFails.length) { failures += lineFails.length; }

// =====================================================================
// 5. Movimiento: curvas de B -> muelles de SwiftUI
// =====================================================================
/** Pico de una cubic-bezier CSS (el sobrepaso). */
function bezierPeak(x1, y1, x2, y2) {
  let peak = 0;
  for (let i = 0; i <= 10000; i++) { const s = i / 10000; const y = 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s * s * y2 + s ** 3; peak = Math.max(peak, y); }
  return peak;
}
const peak = bezierPeak(0.34, 1.45, 0.64, 1);
const overshoot = peak - 1;
const lnO = Math.log(overshoot);
const zeta = -lnO / Math.sqrt(Math.PI ** 2 + lnO ** 2);   // sobrepaso de un oscilador subamortiguado
const damping = +zeta.toFixed(2), bounce = +(1 - zeta).toFixed(2);
const MOTION = {
  fuente: { spring: 'cubic-bezier(.34, 1.45, .64, 1)', ease: 'cubic-bezier(.2, .8, .2, 1)' },
  springB: { peak: +peak.toFixed(3), overshootPercent: +(overshoot * 100).toFixed(1), dampingFraction: damping, bounce,
    nota: 'La curva «spring» de B sobrepasa un ' + (overshoot * 100).toFixed(1) + ' %; un muelle con ese sobrepaso tiene ζ = ' + damping + ' (bounce ' + bounce + '). Es casi .bouncy (bounce 0,3).' },
  animaciones: [
    { id: 'press', b: 'glass-btn:active scale .88 · .35s spring', swiftui: `.spring(response: 0.35, dampingFraction: ${damping})`, ios17: `.bouncy(duration: 0.35, extraBounce: ${+(bounce - 0.3).toFixed(2)})`, reducir: 'sin escala: .easeOut(duration: 0.15) de opacidad 0,7' },
    { id: 'pressButton', b: 'btn:active scale .95 · .4s spring', swiftui: `.spring(response: 0.4, dampingFraction: ${damping})`, ios17: `.bouncy(duration: 0.4, extraBounce: ${+(bounce - 0.3).toFixed(2)})`, reducir: 'opacidad 0,7, sin escala' },
    { id: 'numberSwap', b: 'num-swap pop .5s spring (escala .6→1)', swiftui: `.contentTransition(.numericText(countsDown: true)) + .spring(response: 0.5, dampingFraction: ${damping})`, ios17: 'igual', reducir: '.contentTransition(.opacity) + .easeInOut(duration: 0.2)' },
    { id: 'viaAppear', b: 'via-pop .7s spring (escala .3→1)', swiftui: `.transition(.scale(scale: 0.3).combined(with: .opacity)) + .spring(response: 0.7, dampingFraction: ${damping})`, ios17: 'igual', reducir: '.transition(.opacity) 0,2 s' },
    { id: 'viaPulse', b: 'via-glow 1.6s ease-in-out ×5, retraso .5s', swiftui: 'halo (sombra amarilla + anillo 6 pt) que late 5 veces: .easeInOut(duration: 0.8) ida y vuelta, desde 0,5 s', ios17: 'igual', reducir: 'anillo estático de 2 pt mientras dure «nueva» (25 s); sin latido' },
    { id: 'screenPush', b: 'b-in .5s spring / b-out .5s ease', swiftui: 'NavigationStack nativo (no se reimplementa); zoom de iOS 18: .navigationTransition(.zoom(sourceID:in:))', ios17: 'push nativo', reducir: 'lo decide el sistema (fundido)' },
    { id: 'sheet', b: 'b-sheet .55s spring, fondo b-shrink', swiftui: '.sheet con .presentationDetents; el sistema anima y encoge el fondo', ios17: 'igual', reducir: 'sistema' },
    { id: 'morph', b: 'botón «Iniciar trayecto» → hoja del mapa', swiftui: 'GlassEffectContainer + .glassEffectID (iOS 26); iOS 17–25: matchedGeometryEffect', ios17: 'matchedGeometryEffect(id:in:) con .spring(response: 0.5, dampingFraction: ' + damping + ')', reducir: 'fundido .easeInOut(duration: 0.2)' },
    { id: 'live', b: 'ripple 2s ease infinito', swiftui: 'punto verde + onda que crece (escala 1→2,1, opacidad .6→0) en 2 s, repetida', ios17: 'phaseAnimator o .repeatForever(autoreverses: false)', reducir: 'punto fijo, sin onda' },
    { id: 'translating', b: 'bounce 1s spring infinito (3 puntos con retraso .15s)', swiftui: 'Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative)', ios17: 'igual (iOS 17)', reducir: 'puntos quietos (isActive: false)' },
    { id: 'barGrow', b: 'grow .8s spring (scaleX 0→1)', swiftui: `.spring(response: 0.8, dampingFraction: ${damping}) sobre el ancho al aparecer`, ios17: 'igual', reducir: 'sin animación' },
    { id: 'routeDraw', b: 'dibujo de la línea 1.5s ease-out cúbica', swiftui: '.timingCurve(0.33, 1, 0.68, 1, duration: 1.5) sobre el progreso del trazado', ios17: 'MapPolyline con los puntos hasta el progreso, en TimelineView(.animation)', reducir: 'trazado entero de golpe' },
    { id: 'refreshBar', b: '(no está en B; R54)', swiftui: 'barra de 2 pt que se llena lineal hasta el siguiente refresco: TimelineView(.periodic(from:by: 1)) o .linear(duration: resto)', ios17: 'igual', reducir: 'se enseña el resto en texto («próximo en 12 s»), sin barra que se mueve' },
    { id: 'pairScan', b: 'breathe 1.2s alternate; encontrado: escala .85 en .6s spring', swiftui: '.easeInOut(duration: 1.2).repeatForever(autoreverses: true) sobre la escala del marco; al encontrar .spring(response: 0.6, dampingFraction: ' + damping + ')', ios17: 'igual', reducir: 'marco quieto; al encontrar, cambio de color sin escala' },
    { id: 'staleDim', b: '(no está en B; R19)', swiftui: '.easeInOut(duration: 0.45) sobre opacidad y saturación del tablero', ios17: 'igual', reducir: 'sin animación' },
    { id: 'ease', b: 'cubic-bezier(.2,.8,.2,1)', swiftui: '.timingCurve(0.2, 0.8, 0.2, 1, duration: d) — traducción exacta', ios17: 'igual (iOS 13+)', reducir: '—' },
  ],
  duraciones: { press: 0.35, pressButton: 0.4, numberSwap: 0.5, screen: 0.5, sheet: 0.55, pairFound: 0.6, viaAppear: 0.7, barGrow: 0.8, routeDraw: 1.5, viaPulseHalf: 0.8, viaPulseCount: 5, viaPulseDelay: 0.5, viaNewWindow: 25, live: 2.0, translating: 1.0, breathe: 1.2, staleDim: 0.45, toast: 2.4, reduced: 0.2, nowGrace: 45, refresh: 30 },
};

// =====================================================================
// 6. Tipografía, espaciado, radios, sombras (fuente única)
// =====================================================================
const TYPE = {
  familia: { texto: 'SF Pro (sistema)', cifras: 'SF Pro Rounded (design: .rounded)', web: 'Inter / Nunito (solo el laboratorio)' },
  niveles: [
    // id, estilo Dynamic Type, peso, diseño, dígitos tabulares, B (rem·peso), límite
    { id: 'screenTitle', style: 'largeTitle', weight: 'bold', design: 'default', b: '— (título grande nativo)', max: null },
    { id: 'navTitle', style: 'headline', weight: 'semibold', design: 'default', b: '.glass-title 1.05rem·700', max: null },
    { id: 'routeTitle', style: 'title3', weight: 'heavy', design: 'default', b: '.board-head h1 1.15rem·800', max: 'accessibility2' },
    { id: 'legTitle', style: 'headline', weight: 'bold', design: 'default', b: '.leg-head h2 1rem·700', max: null },
    { id: 'legSubtitle', style: 'footnote', weight: 'regular', design: 'default', b: '.leg-head p .8rem', max: null },
    { id: 'kicker', style: 'caption', weight: 'semibold', design: 'default', b: '.kicker .78rem·600', max: null },
    { id: 'body', style: 'body', weight: 'regular', design: 'default', b: '.li .95rem', max: null },
    { id: 'bodyStrong', style: 'body', weight: 'semibold', design: 'default', b: '.field input 1rem·600', max: null },
    { id: 'callout', style: 'subheadline', weight: 'regular', design: 'default', b: '.notice p .86rem · .route p .85rem', max: null },
    { id: 'meta', style: 'footnote', weight: 'regular', design: 'default', digits: true, b: '.tk-meta .78rem (tabular)', max: null },
    { id: 'status', style: 'footnote', weight: 'semibold', design: 'default', digits: true, b: '.status .8rem·600', max: null },
    { id: 'noticeTitle', style: 'footnote', weight: 'bold', design: 'default', b: '.notice-head .8rem·700', max: null },
    { id: 'destination', style: 'headline', weight: 'bold', design: 'default', b: '.tk-dest 1rem·700', max: 'accessibility3' },
    { id: 'unit', style: 'footnote', weight: 'bold', design: 'rounded', b: '.tk-num small .85rem·700', max: 'accessibility2' },
    { id: 'chipCaption', style: 'caption', weight: 'regular', design: 'default', digits: true, b: '.chip-at .72rem', max: 'accessibility1' },
    { id: 'label', style: 'caption2', weight: 'bold', design: 'default', b: '.pace .7rem·700 · .tag · .via small', max: 'accessibility1' },
    { id: 'button', style: 'body', weight: 'semibold', design: 'default', b: '.btn .98rem·700', max: null },
    { id: 'buttonSmall', style: 'subheadline', weight: 'semibold', design: 'default', b: '.btn-small .85rem', max: null },
    { id: 'footnote', style: 'caption', weight: 'regular', design: 'default', digits: true, b: '.foot .78rem', max: null },
  ],
  // Cifras: tamaño fijo a Dynamic Type «Large» que escala con @ScaledMetric y se topa.
  cifras: [
    { id: 'ticket', base: 56, relativeTo: 'largeTitle', max: 80, b: '.tk-num .num 3.6rem·900', nota: 'holgado (1–2 tramos, R47)' },
    { id: 'ticketNormal', base: 48, relativeTo: 'largeTitle', max: 72, b: '—', nota: 'normal (3–4 tramos)' },
    { id: 'ticketCompact', base: 40, relativeTo: 'largeTitle', max: 60, b: '—', nota: 'compacto (5–6 tramos); nunca menos: «lo que no se encoge es la cifra»' },
    { id: 'chip', base: 24, relativeTo: 'title2', max: 40, b: '.chip .num 1.5rem·900' },
    { id: 'via', base: 20, relativeTo: 'title3', max: 32, b: '.via b 1.2rem·900' },
    { id: 'stat', base: 30, relativeTo: 'title', max: 48, b: '.solid-num 1.9rem·900' },
    { id: 'statBig', base: 48, relativeTo: 'largeTitle', max: 72, b: '.solid-num.big 3rem·900' },
    { id: 'badge', base: 15, relativeTo: 'subheadline', max: 22, b: '.badge .95rem·900 (caja 2em)' },
  ],
  reglas: [
    'Cifras: .system(size:weight: .heavy, design: .rounded).monospacedDigit(); B pinta 900 porque Nunito heavy es más fino que SF Rounded heavy.',
    '≥ 60 min («1h46»): la cifra baja a 0,75× (un bus a casi dos horas no es urgente y así «1h46» cabe en un iPhone SE).',
    '«ya» se pinta a tamaño completo (2 letras, lo más urgente); «En andén» a 0,5× en una línea con minimumScaleFactor 0,7.',
    'Tracking de las cifras: −0,02 × tamaño (B: letter-spacing −.02em).',
    'Con tamaños de accesibilidad (AX1+), el billete pasa a dos filas (B ya lo hace con «letra grande»): cifra+destino arriba, vía y ritmo debajo.',
  ]
};
const SPACE = { hair: 2, xs: 4, s: 6, sm: 8, m: 10, ml: 12, gutter: 14, l: 16, xl: 20, xxl: 28 };
const RADIUS = { via: 10, inner: 18, tile: 22, card: 30, bar: 30, sheet: 36, badgeRatio: 0.3 };
const SIZE = { hit: 44, glassButton: 44, primaryButton: 50, row: 48, tabBar: 60, badgeSmall: 25, badge: 30, badgeLarge: 42, chipMinWidth: 92, refreshBar: 2, liveDot: 9, stroke: 1, dashed: [4, 3], dashedWidth: 1.5, cardPadding: 12, ticketPadding: 14, staleOpacity: 0.55, staleSaturation: 0.2, unusableOpacity: 0.55 };
const SHADOWS = [
  { id: 'glass', b: '0 10px 30px oklch(0% 0 0 / .18) + inset 0 1px 0 --glass-hi', color: 'shadow', opacity: 0.18, radius: 15, y: 10, nota: 'solo iOS 17–25; en iOS 26 la sombra la pone glassEffect' },
  { id: 'glassButton', b: '0 4px 14px oklch(0% 0 0 / .15)', color: 'shadow', opacity: 0.15, radius: 7, y: 4, nota: 'ídem' },
  { id: 'card', b: '0 6px 24px oklch(0% 0 0 / .12)', color: 'shadow', opacity: 0.12, radius: 12, y: 6, nota: 'tarjetas opacas; en oscuro apenas se ve y no pasa nada' },
  { id: 'primary', b: '0 8px 20px accent / .35', color: 'accentFill', opacity: 0.35, radius: 10, y: 8, nota: 'botón principal' },
  { id: 'danger', b: '0 8px 20px bad / .35', color: 'bad', opacity: 0.35, radius: 10, y: 8, nota: 'botón rojo' },
  { id: 'viaGlow', b: '0 0 0 6px via/.45, 0 0 24px via/.8', color: 'via', opacity: 0.8, radius: 12, y: 0, nota: 'halo del latido de la vía nueva (más anillo de 6 pt a .45)' },
  { id: 'badgeInset', b: 'inset 0 -2px 0 oklch(0% 0 0 / .15)', color: 'shadow', opacity: 0.15, radius: 0, y: -2, nota: 'filete inferior del distintivo (overlay de 2 pt, no sombra)' },
];

if (failures) {
  console.log('\nFALLAN ' + failures + ' comprobaciones de contraste:');
  checkRows.filter(r => !r.ok).forEach(r => console.log(`  ${r.fg} / ${r.bg} [${r.variant}] = ${r.ratio} < ${r.min}  (${r.what})`));
  lineFails.forEach(l => console.log(`  línea ${l.code} ${l.color}: ${l.ratio}`));
  process.exit(1);
}

// =====================================================================
// 7. Salidas
// =====================================================================
// Si el color se ha llevado dentro de la gama, «oklchEnGama» es el OKLCH del sRGB final.
const out = v => ({ oklch: fmtLch(v.lch, v.a), hex: hexA(v.rgb, v.a), srgb: v.rgb.map(x => +x.toFixed(4)), alpha: +v.a.toFixed(3), ...(v.mapped ? { gamutMapped: true, oklchEnGama: fmtLch(srgbToLch(v.rgb), v.a) } : {}) });
const tokensJson = {
  $schema: 'Trajet · tokens de diseño «Cristal» (dirección B). Generado por design-lab/tools/tokens.mjs: no editar a mano.',
  version: 1,
  generado: new Date().toISOString().slice(0, 10),
  notas: {
    color: 'Fuente en OKLCH. hex/srgb = sRGB de 8 bits / coma flotante tras el mapeo de gama de CSS Color 4. «HC» = Aumentar contraste. Los colores con alfa se componen en sRGB con gamma.',
    contraste: 'Todas las parejas de «contrastes» pasan su mínimo WCAG 2.x; el script falla si alguna no.',
    lineas: 'La tinta del distintivo usa textcolourweb_hexa de IDFM si da ≥ 4,5:1; si no, negro o blanco, el que más contraste dé (siempre ≥ 4,58:1).'
  },
  color: Object.fromEntries(COLORS.map(c => [c.name, {
    css: c.css, grupo: c.group, rol: c.rol,
    ...Object.fromEntries(VARIANTS.map(v => [v, out(RES[c.name][v])])),
    ...(c.b ? { b: c.b } : {}),
    ...(RES[c.name].light.a < 1 || RES[c.name].dark.a < 1 ? { opacoSobre: OPAQUE_OVER[c.name] || 'bg' } : {})
  }])),
  contrastes: checkRows,
  contrastesB: bRows,
  tipografia: TYPE,
  espaciado: SPACE,
  radio: RADIUS,
  tamano: SIZE,
  sombra: SHADOWS,
  movimiento: MOTION,
  lineas: { regla: 'oficial si ≥ 4,5:1; si no, el mayor de negro/blanco', filas: lineRows },
  mapa: {
    ios: 'MapKit: .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)); el retintado de B no existe en MapKit.',
    tintesB: {
      light: { land: '#eef0ee', water: '#bcd3ea', park: '#d9e8d3', building: '#e4e6e3', road: '#ffffff', roadCasing: '#d9dbd8', rail: '#cfd2cf', text: '#4a5058', halo: '#ffffff' },
      dark: { land: '#131417', water: '#0f1a26', park: '#161c17', building: '#1a1b1f', road: '#25272c', roadCasing: '#0f1012', rail: '#2a2c31', text: '#a6aab3', halo: '#131417' }
    },
    trazo: { linea: 6, contorno: 10, paradaRadio: 5, paradaExtremoRadio: 7, paradaPasoRadio: 2.5, paradaTrazo: 2.5, pie: 3, pieGuion: [0.2, 2] }
  }
};

// ---- Swift (bloque generado de Tokens.swift)
const sw = v => `RGBA(${v.rgb.map(x => x.toFixed(4)).join(', ')}${v.a < 1 ? ', ' + v.a.toFixed(3) : ''})`;
const swiftLines = [];
swiftLines.push('    // Generado por design-lab/tools/tokens.mjs a partir de OKLCH. No editar a mano:');
swiftLines.push('    // se cambia el script y se vuelve a ejecutar. Orden: claro, oscuro,');
swiftLines.push('    // claro con «Aumentar contraste», oscuro con «Aumentar contraste».');
let lastGroup = '';
for (const c of COLORS) {
  if (c.group !== lastGroup) { swiftLines.push('', `    // MARK: ${c.group}`); lastGroup = c.group; }
  const r = RES[c.name];
  const rol = c.rol.split('. ')[0].replace(/\.$/, '');
  swiftLines.push(`    /// ${rol}.`);
  swiftLines.push(`    /// \`${c.css}\` · claro ${fmtLch(r.light.lch, r.light.a)} = ${hexA(r.light.rgb, r.light.a)} · oscuro ${fmtLch(r.dark.lch, r.dark.a)} = ${hexA(r.dark.rgb, r.dark.a)}${r.light.mapped || r.dark.mapped ? ' (mapeado a sRGB)' : ''}`);
  swiftLines.push(`    static let ${c.name} = DynamicColor(`);
  swiftLines.push(`        light: ${sw(r.light)},`);
  swiftLines.push(`        dark: ${sw(r.dark)},`);
  swiftLines.push(`        lightHC: ${sw(r.lightHC)},`);
  swiftLines.push(`        darkHC: ${sw(r.darkHC)})`);
}
const SWIFT_BEGIN = '    // <generado:tokens>', SWIFT_END = '    // </generado:tokens>';
// Palette: un Color dinámico por token, con el mismo nombre.
const paletteLines = ['    // Generado por design-lab/tools/tokens.mjs: un Color dinámico por token.'];
lastGroup = '';
for (const c of COLORS) {
  if (c.group !== lastGroup) { paletteLines.push('', `    // MARK: ${c.group}`); lastGroup = c.group; }
  paletteLines.push(`    /// ${c.rol.split('. ')[0].replace(/\.$/, '')}.`);
  paletteLines.push(`    static let ${c.name}: Color = Tokens.${c.name}.color`);
}
const PAL_BEGIN = '    // <generado:paleta>', PAL_END = '    // </generado:paleta>';

// ---- Markdown (bloques generados de sistema.md)
const md = {};
{
  const L = [];
  L.push('| Token | Uso | Claro (OKLCH → sRGB) | Oscuro (OKLCH → sRGB) | Aumentar contraste (claro / oscuro) |');
  L.push('|---|---|---|---|---|');
  for (const c of COLORS) {
    const r = RES[c.name];
    const cell = v => `\`${fmtLch(v.lch, v.a)}\` → \`${hexA(v.rgb, v.a)}\`${v.mapped ? ' ⁽ᵍ⁾' : ''}`;
    const hc = (c.lightHC || c.darkHC) ? `\`${hexA(r.lightHC.rgb, r.lightHC.a)}\` / \`${hexA(r.darkHC.rgb, r.darkHC.a)}\`` : '=';
    L.push(`| \`${c.name}\` | ${c.rol.split('. ')[0].replace(/\.$/, '')} | ${cell(r.light)} | ${cell(r.dark)} | ${hc} |`);
  }
  L.push('', '⁽ᵍ⁾ fuera de la gama sRGB: llevado dentro con el mapeo de gama de CSS Color 4 (croma reducido hasta ΔEok < 0,02; el tono y la luminosidad no se tocan).');
  md.colores = L.join('\n');
}
{
  const L = [];
  L.push('| Texto | Fondo | Claro | Oscuro | Claro HC | Oscuro HC | Mínimo | Para qué |');
  L.push('|---|---|---|---|---|---|---|---|');
  const groups = new Map();
  for (const r of checkRows) { const k = r.fg + '|' + r.bg + '|' + r.what; if (!groups.has(k)) groups.set(k, {}); groups.get(k)[r.variant] = r; }
  for (const [k, g] of groups) {
    const [fg, bg, what] = k.split('|');
    const any = Object.values(g)[0];
    const cell = v => g[v] ? `${String(g[v].ratio).replace('.', ',')}` : '—';
    const mins = [...new Set(Object.values(g).map(x => x.min))].map(x => String(x).replace('.', ',')).join(' / ');
    L.push(`| \`${fg}\` | \`${bg.replace('>', '` sobre `')}\` | ${cell('light')} | ${cell('dark')} | ${cell('lightHC')} | ${cell('darkHC')} | ${mins}:1 | ${what} |`);
  }
  md.contrastes = L.join('\n');
}
{
  const L = ['| Pareja en B | Claro | Oscuro |', '|---|---|---|'];
  const whats = [...new Set(bRows.map(r => r.what))];
  for (const w of whats) {
    const c = t => { const r = bRows.find(x => x.what === w && x.theme === t); const s = String(r.ratio).replace('.', ','); return r.ratio < AA ? `**${s}** ✗` : s; };
    L.push(`| ${w} | ${c('light')} | ${c('dark')} |`);
  }
  md.contrastesB = L.join('\n');
}
{
  const L = ['| Línea | Modo | Color | Texto oficial (contraste) | Tinta elegida | Contraste | Umbral 0,45 de la v1 |', '|---|---|---|---|---|---|---|'];
  for (const l of lineRows) {
    const off = l.official ? `\`${l.official}\` (${String(l.officialRatio).replace('.', ',')}${l.officialRatio < AA ? ' ✗' : ''})` : '—';
    const old = l.oldRatio < AA ? `\`${l.oldInk}\` **${String(l.oldRatio).replace('.', ',')}** ✗` : `\`${l.oldInk}\` ${String(l.oldRatio).replace('.', ',')}`;
    L.push(`| ${l.code} | ${l.modo} | \`${l.color}\` | ${off} | \`${l.ink}\` ${l.source === 'oficial' ? '(oficial)' : '(calculada)'} | ${String(l.ratio).replace('.', ',')} | ${old} |`);
  }
  const offBad = lineRows.filter(l => l.official && l.officialRatio < AA);
  const oldBad = lineRows.filter(l => l.oldRatio < AA);
  L.push('', `Resumen: ${lineRows.length} colores. El texto oficial de IDFM no llega a 4,5:1 en ${offBad.length} (${offBad.map(l => l.code).join(', ') || 'ninguno'}); ahí se usa la tinta calculada. El umbral 0,45 de la v1 fallaba en ${oldBad.length} (${oldBad.map(l => l.code).join(', ') || 'ninguno'}). Con la regla nueva, el peor caso es ${String(Math.min(...lineRows.map(l => l.ratio))).replace('.', ',')}:1.`);
  md.lineas = L.join('\n');
}
{
  const L = ['| Id | En B | SwiftUI | iOS 17 | Con «Reducir movimiento» |', '|---|---|---|---|---|'];
  for (const a of MOTION.animaciones) L.push(`| \`${a.id}\` | ${a.b} | \`${a.swiftui}\` | ${a.ios17} | ${a.reducir} |`);
  const c = x => String(x).replace('.', ',');
  L.push('', `Curva «spring» de B \`${MOTION.fuente.spring}\`: pico ${c(MOTION.springB.peak)} → sobrepaso ${c(MOTION.springB.overshootPercent)} % → **dampingFraction ${c(damping)}** (bounce ${c(bounce)}). Sale de ζ = −ln(s) / √(π² + ln²(s)), con s el sobrepaso: la fórmula del oscilador subamortiguado. La duración CSS se toma como \`response\` (la «duración perceptiva» de Apple).`);
  md.movimiento = L.join('\n');
}

console.log(`Contrastes: ${checkRows.length} comprobaciones, todas bien. Líneas: ${lineRows.length}, peor ${Math.min(...lineRows.map(l => l.ratio)).toFixed(2)}:1.`);
console.log(`Muelle de B: pico ${peak.toFixed(3)} → sobrepaso ${(overshoot * 100).toFixed(1)} % → dampingFraction ${damping} (bounce ${bounce}).`);
const mappedList = COLORS.filter(c => VARIANTS.some(v => RES[c.name][v].mapped)).map(c => c.name);
if (mappedList.length) console.log('Mapeados a sRGB: ' + mappedList.join(', '));

if (process.argv.includes('--list')) {
  for (const c of COLORS) console.log(c.name.padEnd(15), VARIANTS.map(v => hexA(RES[c.name][v].rgb, RES[c.name][v].a).padEnd(10)).join(' '));
  for (const r of bRows) console.log('B', r.theme, r.what, r.ratio);
}
if (CHECK_ONLY) process.exit(0);

function replaceBlock(file, begin, end, body) {
  if (!existsSync(file)) { console.log('  (no existe, no toco) ' + file); return; }
  const src = readFileSync(file, 'utf8');
  const i = src.indexOf(begin), j = src.indexOf(end);
  if (i < 0 || j < 0 || j < i) { console.log('  (sin marcas) ' + file + ' ' + begin); return; }
  const next = src.slice(0, i + begin.length) + '\n' + body + '\n' + src.slice(j);
  if (next !== src) { writeFileSync(file, next); console.log('  escrito ' + file + ' [' + begin.trim() + ']'); }
}

writeFileSync(P('design-lab/tokens.json'), JSON.stringify(tokensJson, null, 2) + '\n');
console.log('  escrito design-lab/tokens.json');
replaceBlock(P('Trajet/Design/Tokens.swift'), SWIFT_BEGIN, SWIFT_END, swiftLines.join('\n'));
replaceBlock(P('Trajet/Design/Tokens.swift'), PAL_BEGIN, PAL_END, paletteLines.join('\n'));
for (const k of Object.keys(md)) replaceBlock(P('docs/diseno/sistema.md'), `<!-- generado:${k} -->`, `<!-- /generado:${k} -->`, md[k]);

// Asset catalog: tinte del sistema y fondo de arranque, con claro/oscuro/HC.
function colorset(name) {
  const r = RES[name];
  const comp = v => ({ 'color-space': 'srgb', components: { red: v.rgb[0].toFixed(3), green: v.rgb[1].toFixed(3), blue: v.rgb[2].toFixed(3), alpha: v.a.toFixed(3) } });
  const colors = [
    { idiom: 'universal', color: comp(r.light) },
    { idiom: 'universal', appearances: [{ appearance: 'luminosity', value: 'dark' }], color: comp(r.dark) },
    { idiom: 'universal', appearances: [{ appearance: 'contrast', value: 'high' }], color: comp(r.lightHC) },
    { idiom: 'universal', appearances: [{ appearance: 'luminosity', value: 'dark' }, { appearance: 'contrast', value: 'high' }], color: comp(r.darkHC) },
  ];
  return JSON.stringify({ colors, info: { author: 'xcode', version: 1 } }, null, 2) + '\n';
}
const assets = [['AccentColor', 'accent'], ['LaunchBackground', 'bg']];
for (const [set, token] of assets) {
  const f = P(`Trajet/Assets.xcassets/${set}.colorset/Contents.json`);
  if (existsSync(f)) { writeFileSync(f, colorset(token)); console.log('  escrito ' + f.replace(ROOT, '').slice(1)); }
}
