# B v2 · Live Activity y widgets (FASE 2B)

Laboratorio del rediseño de la Live Activity y los widgets dentro del lenguaje
«Cristal». Tres variantes (A, B, C) de **todas** las piezas, a tamaño real de
iOS en puntos (1 px = 1 pt), sobre fondos de bloqueo e inicio creíbles y
conectadas al panel de escenarios de `../shared`.

**Elegida: A «Billete»** (2B.4). Por qué, estados, límites de iOS y enlaces:
`docs/diseno/decisiones-la-widgets.md`. Especificación para la FASE 3:
`docs/diseno/sistema.md` §12. B y C se quedan como estaban en la 2B.3, por si
se prefiere cambiar.

- Referencias, límites de iOS y principios: `docs/diseno/referencias-la-widgets.md`.
- Tokens: `design-lab/tokens.json` (los OKLCH de `docs/diseno/sistema.md`).
- Capturas: `design-lab/capturas/la-widgets/` (ver «Capturas»).

## Abrirlo

```powershell
node design-lab/shared/servidor.js          # PORT=7797 por defecto
$env:PORT=7798; node design-lab/shared/servidor.js   # si el 7797 está ocupado
```

<http://localhost:7797/b-cristal-v2/> (también desde la galería, sección «B v2»).

Arriba:

- **A ✓ / B / C**: la lámina de una variante (bloqueo, isla, inicio 1 y 2).
- **Las tres**: la misma pieza de las tres en cada fila, con su medida en pt
  (en rojo si pasa de 160 pt de alto). A con la 2B.4; B y C, como en la 2B.3.
- **Viva / congelada** (solo A): la misma Live Activity con la app
  escribiendo y con la app parada a una hora (`fz=12:55:40`). Enseña que,
  sin la app, no cambia de tren ni inventa vías y que al vencer `staleDate`
  pasa a horas fijas.
- **Casos límite** (solo A): la compacta, la mínima y la expandida con
  «59 min + vía», «1h46», «ya», «andén», el texto del sistema, iOS 17,
  caducada y sin conexión, cada una con su medida (la compacta no pasa de
  230/250).
- Dispositivo **SE / 16 / 16 Pro Max**, estado de la isla y «▶ Alerta» (la
  vía aparece y la isla se abre unos segundos). La isla de la columna «Morph»
  cambia de forma al tocarla.

Panel de la derecha:

- **Escenas de un toque**: vía real, probable, sin vía, aparece la vía,
  cambio de vía, tren cancelado, bus a 1h46, línea cortada, servicio
  finalizado, aviso, destinos mezclados, en el andén, transbordo tramo 1 y 2,
  dato antiguo, congelada con el tren ya salido (12:57:30), sin conexión,
  servidor sin clave PRIM, sin datos recientes (13:50), nombres largos,
  terminado (llegada) y parado a mano.
- **Trayecto**: ruta con transbordo, tramo actual, «la app no actualiza»,
  terminado.
- **Cifra (A)**: la escribe la app (dos tallas) · sistema, una talla · iOS 17
  con segundos.
- **Aspecto de iOS**: inicio en color / tintado / transparente; acentuado
  calado / contorno; texto grande / xLarge / AX3 (con los topes); reducir
  transparencia; aumentar contraste; pantalla siempre activa; StandBy de noche;
  ver enlaces y áreas táctiles.
- Los de siempre: claro / oscuro, reducir movimiento, reloj ×1 / ×10 / ×60.

Parámetros de URL (capturas deterministas): `v=A|B|C`,
`view=lamina|comparar|congelada|limites`, `device=se|i16|max`, `scene=<id>`,
`theme=light|dark`, `tint=full|tinted|clear`, `rt=1`, `rm=1`,
`num=app|sys|ios17`, `dt=L|XL|AX3`, `hc=1`, `aod=1`, `sb=1`,
`acc=calado|contorno`, `hits=1`, `fz=HH:MM:SS`, `t=12:50:00`, `speed=60`,
`island=compact|expanded|minimal`, `capture=1` (sin panel ni barra, zoom 1).
En la consola: `lab.set({...})` (mismas claves; `patch` para cualquier clave
de escenario), `lab.island('expanded')`, `lab.alertDemo()`, `lab.audit()`
(lo que se ha quedado sin texto o desborda), `lab.modelA()` (la foto de A),
`TrajetLA.abreviar('…')`.

## Las tres variantes

| | A · Billete ✓ | B · Tablero | C · Fases |
|---|---|---|---|
| Idea | Un billete opaco por superficie: la cifra a la izquierda, la vía en la «matriz». Siempre la misma anatomía. | Un tablero de salidas en miniatura: filas con la cifra en una baldosa, destino y vía por fila. | Dos baldosas: la izquierda siempre es el tiempo; la derecha cambia con el momento. |
| Estado | elegida; corregida en la 2B.4 (23 puntos del revisor) | descartada; tal cual | descartada; tal cual |
| Bloqueo | cabecera (línea, destino, estado, antigüedad) · billete (cifra, línea secundaria, matriz de vía) · pie (luego / transbordo con la vía del enlace / cancelado + Parar) | cabecera con la parada · fila grande · fila pequeña o transbordo | cabecera · baldosa de tiempo con ritmo + baldosa de fase · pie |
| Compacta | cifra 16 pt + caja de vía de 12 pt (cae el «′» antes que ensanchar) | cifra encima de la vía | vía primero y cifra pequeña |
| Mínima | aro del color de la línea (verde en el andén, gris apagada) | cifra + barra | cifra + vía debajo |
| Expandida | leading: línea y destino · trailing: cifra + vía · center: estado, tramo u hora · bottom: luego / transbordo / franja de vía, antigüedad y Parar | leading: línea, «desde», destino · trailing: vía + cifra · bottom: fila | trailing: cifra · center: ritmo · bottom: baldosa a lo ancho |
| Widgets | pequeño con anatomía fija (54 pt); mediano con destino por fila y un nivel de abreviatura; grande por tramos | tablero de filas | baldosas gemelas |
| Acentuado | billete blanco con la cifra calada (o contorno) | todo a contorno | baldosas translúcidas |

## Qué hace A que la distingue (2B.4)

- **La foto** (`modelA` en `app.js`): la Live Activity pinta solo lo que la
  app escribió; los widgets, la entrada del timeline que toca con el dato de
  la última recarga. Nada se reconstruye con el tablero vivo.
- **La cifra según quién la escribe** (`numA`): la app (dos tallas, «′», «ya»,
  «1h46»), el sistema (una talla) o iOS 17 (segundos); caducada, hora fija.
- **Apagado** (`.A-off`): billete gris opaco, vía sin amarillo pero con su
  forma, todo desaturado menos «Parar» y el aviso del estado.
- **Ajuste por prioridad** (en `layout()`): `data-altset` (alternativas
  enteras, la compacta y la expandida), `data-fitrow` + `.fitr` (piezas que se
  acortan por escalones con `data-prio`), `data-fitgroup` (un nivel de
  abreviatura por widget) y `data-droprow` + `data-dp` (lo que cae entero, en
  ancho o en alto). En SwiftUI, `ViewThatFits`.

## `abreviar()`: el destino nunca se corta a mitad de palabra

Devuelve las variantes de la más completa a la más corta; la vista se queda
con la primera que cabe (en SwiftUI, `ViewThatFits` con un `Text` por variante
y `lineLimit(1)`); si no cabe ninguna, el destino se quita entero.

1. Completo, normalizado.
2. Compactar sin perder nada: « - » → «-», fuera paréntesis, fuera «Paris »
   delante de otro nombre y «Gare » delante de un nombre propio.
3. Diccionario en palabras enteras: Saint → St, Sainte → Ste, Porte → Pte,
   Place → Pl., Pont → Pt, Château → Chât., Université → Univ., Aéroport →
   Aérop., Charles de Gaulle → CDG, Avenue → Av., Boulevard → Bd, Faubourg →
   Fg, Terminal → T.
4. Parte principal de un nombre doble SNCF («A - B» → «A»).
5. Alias corto conocido (`NOMBRES_CORTOS`): Saint-Denis Pleyel → Pleyel,
   Pont de Bezons → Bezons…
6. Nada.

## Lo que se ha añadido a `../shared` (sin romper las otras direcciones)

- `data.js`: `transferBoard`, una ruta encadenada de verdad (14 Olympiades →
  Saint-Lazare, J Gare Saint-Lazare → Argenteuil).
- `core.js`: escenarios `transfer`, `legNow`, `tripEnded`, `frozen`,
  `widgetTint`, `reduceTransparency`; `buildBoard` usa `transferBoard` con
  `transfer`; el panel acepta opciones (`Trajet.gallery.mountPanelWith`).
- Las escenas nuevas de la 2B.4 (cancelado, cambio de vía, destinos
  mezclados, nombres largos) **no** tocan `../shared`: se aplican en `app.js`
  encima del tablero (`tweakBoard`), con la misma forma de la API.

## Capturas

```powershell
node design-lab/b-cristal-v2/plan-capturas.mjs            # solo A + comparar + GIF (PORT del servidor)
node design-lab/b-cristal-v2/plan-capturas.mjs --todas    # además B y C
node design-lab/tools/capturar.mjs design-lab/b-cristal-v2/plan-capturas.json
```

En `design-lab/capturas/la-widgets/`:

- `A/`: `A-<pieza>-<escenario>-<modo>.png` a 2× (piezas: `actividad-bloqueo`,
  `isla-compacta`, `isla-minima`, `isla-expandida`, `widget-pequeno`,
  `widget-mediano`, `widget-grande`, `bloqueo-circular`,
  `bloqueo-rectangular`, `bloqueo-en-linea`). Modos: `claro`, `oscuro`,
  `tintado`, `transparente`, `tintado-contorno`,
  `tintado-reducir-transparencia`, `claro-reducir-transparencia`,
  `sistema-oscuro` e `ios17-oscuro` (las otras versiones de la cifra),
  `siempre-activa`, `standby-noche`, `aumentar-contraste-claro|oscuro`,
  `texto-xl-oscuro`, `texto-ax3-oscuro`. Además: teléfonos enteros, láminas
  (SE, Pro Max, SE con aviso y con nombres largos, dato antiguo en claro,
  congelada, enlaces y áreas, AX3), `A-casos-limite-isla-*`,
  `A-viva-y-congelada-*`, y el tren que ya salió (`*-oscuro-1257-30`,
  `*-sin-conexion-oscuro-1258`, `*-oscuro-ya-1256-20`).
- `B/`, `C/`: las de la 2B.3, sin tocar.
- `comparar/`: las tres lado a lado por escenario (A ya corregida).
- `gif-cuenta-atras-A.gif` (viva frente a congelada), `gif-aparece-la-via-A.gif`
  (la franja de vía de la expandida), `gif-isla-morph-A.gif`. Los GIF
  `*-las-tres.gif` son de la 2B.3; el de la cuenta atrás está superado (daba a
  entender que la actividad pasa sola al tren siguiente).
- `revision-2B3/`: las capturas del revisor, sin tocar.

Los widgets no dependen del modo trayecto: no hay capturas suyas en «dato
antiguo», «terminado» ni «transbordo · tramo 2». En «terminado» la actividad
sale de la isla y en «parado a mano» ni siquiera deja resumen: solo hay
captura de la de bloqueo.
