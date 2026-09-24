# Sistema de diseño «Cristal»

Sistema de diseño de la app iOS de Trajet v2, sacado de la dirección **B
«Cristal»** del laboratorio (`design-lab/b-cristal/` + `design-lab/shared/`).
Es la referencia visual y de movimiento de **toda la app**. La Live
Activity y los widgets se rediseñaron aparte (FASE 2B) con estos mismos
tokens: sus componentes están en **§12** y el porqué, en
`docs/diseno/decisiones-la-widgets.md` (variante elegida: A «Billete»).

- Lo que B hace mal contra las reglas y cómo se corrige al pasarlo a nativo:
  `docs/diseno/ajustes-b.md`.
- Tokens en formato máquina: `design-lab/tokens.json`.
- Muestrario visual de tokens y componentes (lee `tokens.json`):
  `design-lab/sistema/` (`?theme=light|dark&hc=1&rt=1&rm=1`); capturas en
  `design-lab/capturas/sistema/`.
- Capa de código: `Trajet/Design/` (Tokens, Typography, Metrics, Motion,
  Glass, LineColor; Theme.swift queda como fachada temporal y Format.swift
  sigue siendo el formato).
- Las reglas citadas (R1…R62) están en `docs/reglas.md`.

---

## 1. Principios

1. **El cristal es la capa de controles; los datos van en opaco.** Barras,
   botones y paneles flotan en Liquid Glass sobre el mapa. Los minutos y la
   vía van siempre en una cápsula **opaca** (el «billete») o en una caja
   sólida: se leen de pie, con una mano, en 2–3 s y a contraluz (R1). Las
   tarjetas de tramo también son opacas (en B eran translúcidas: ajuste A1).
2. **El color significa.** Neutros casi grises; el azul solo para lo que se
   toca; el amarillo solo para la vía confirmada; los colores oficiales de
   línea (los únicos saturados, R12) y tres estados con cuentagotas (aviso,
   error, bien). Nada decorativo compite con el amarillo de la J o el morado
   de la 14.
3. **Forma y palabra antes que color.** Vía real = caja sólida con «Vía»;
   vía probable = recuadro punteado con «probable» (R10). El guion punteado
   queda reservado para «probable»: no se usa en ningún otro sitio.
4. **Las cifras mandan.** SF Pro Rounded heavy con dígitos tabulares; la
   primera salida es un billete grande, las demás fichas pequeñas (R48). Lo
   último que se encoge es la cifra (R47).
5. **Movimiento con muelle y morph**, siempre con su alternativa sin
   movimiento (R51). Hápticas en los momentos clave.
6. **Accesible por construcción.** Cada pareja texto/fondo pasa AA (AAA en
   minutos y vía) en claro, oscuro y con «Aumentar contraste»; Dynamic Type
   con topes donde la maqueta lo necesita; «Reducir transparencia» da opaco;
   44 pt de área táctil (R52); VoiceOver lee cada salida como una frase (R50).

---

## 2. Cómo se mantiene

Una sola fuente: **`design-lab/tools/tokens.mjs`** (Node, sin dependencias).

```
node design-lab/tools/tokens.mjs            # genera y comprueba
node design-lab/tools/tokens.mjs --check    # solo comprueba (CI)
node design-lab/tools/tokens.mjs --check --list   # y lista los hex
```

El script:

1. Parte de los valores **OKLCH** de B y los convierte a sRGB con las
   matrices de Björn Ottosson (las de CSS Color 4). Los que caen fuera de la
   gama sRGB los lleva dentro con el **mapeo de gama de CSS Color 4**
   (reduce el croma en OKLCH hasta ΔEok < 0,02; tono y luminosidad intactos).
   Nada se convierte a ojo.
2. Calcula los compuestos (color con alfa sobre su fondo) para «Reducir
   transparencia» y para medir contrastes reales.
3. Comprueba **147 parejas** texto/fondo contra WCAG 2.x en las cuatro
   variantes, y el distintivo de **59 colores de línea**. Si alguna falla,
   sale con código 1 y no escribe nada.
4. Traduce la curva de muelle de B a SwiftUI.
5. Escribe `design-lab/tokens.json`, los bloques generados de
   `Trajet/Design/Tokens.swift`, los colorsets `AccentColor` y
   `LaunchBackground` (claro, oscuro y contraste alto) y los bloques
   `<!-- generado:… -->` de este documento.

Para cambiar un color: se toca `COLORS` en el script y se ejecuta. Nunca a
mano en Swift ni aquí.

---

## 3. Color

### 3.1 Paleta

Cuatro variantes por token: claro, oscuro y las dos con «Aumentar contraste»
(HC). `=` significa que con contraste alto no cambia.

<!-- generado:colores -->
| Token | Uso | Claro (OKLCH → sRGB) | Oscuro (OKLCH → sRGB) | Aumentar contraste (claro / oscuro) |
|---|---|---|---|---|
| `bg` | Fondo de pantalla (debajo del mapa y de las listas) | `oklch(96% 0.003 260)` → `#F0F2F4` | `oklch(12% 0.005 260)` → `#050607` | = |
| `surface` | Tarjeta OPACA (tramo, ruta, opción) | `oklch(99.2% 0.001 260)` → `#FCFCFD` | `oklch(18.5% 0.005 260)` → `#111315` | = |
| `surfaceHi` | Ficha dentro de una tarjeta (salidas 2.ª–4.ª), campos, segmentos | `oklch(93.5% 0.004 260)` → `#E8E9EC` | `oklch(27% 0.005 260)` → `#252629` | = |
| `rule` | Filetes y separadores (con alfa) | `oklch(0% 0 0 / 0.08)` → `#00000014` | `oklch(100% 0 0 / 0.1)` → `#FFFFFF1A` | `#00000038` / `#FFFFFF47` |
| `ink` | Texto principal | `oklch(15% 0.01 260)` → `#090B0F` | `oklch(97% 0 0)` → `#F5F5F5` | `#000000` / `#FFFFFF` |
| `ink2` | Texto secundario (dirección, destino de fichas, metadatos) | `oklch(40% 0.01 260)` → `#45484D` | `oklch(78% 0.01 260)` → `#B4B8BE` | `#24272B` / `#D5D7DB` |
| `ink3` | Texto terciario (rótulos de sección, pie, «min» de las fichas) | `oklch(48% 0.01 260)` → `#5A5E63` | `oklch(71% 0.01 260)` → `#9EA2A8` | `#303338` / `#C9CBCE` |
| `glass` | Relleno del cristal en iOS 17–25 (encima del material) | `oklch(100% 0 0 / 0.58)` → `#FFFFFF94` | `oklch(20% 0.005 260 / 0.55)` → `#1516188C` | `#FFFFFFD9` / `#151618D9` |
| `glassHighlight` | Brillo del canto superior del cristal (iOS 17–25) | `oklch(100% 0 0 / 0.8)` → `#FFFFFFCC` | `oklch(100% 0 0 / 0.12)` → `#FFFFFF1F` | = |
| `glassEdge` | Canto del cristal (1 pt) | `oklch(100% 0 0 / 0.6)` → `#FFFFFF99` | `oklch(100% 0 0 / 0.14)` → `#FFFFFF24` | `#00000073` / `#FFFFFF73` |
| `glassOpaque` | Cristal con «Reducir transparencia»: compuesto opaco de --glass sobre el fondo | `oklch(98.3% 0.001 260)` → `#F9F9FA` | `oklch(16.8% 0.005 260)` → `#0E0F11` | = |
| `ticket` | Fondo del billete: invierte el tema para que los minutos salten a contraluz | `oklch(15% 0.01 260)` → `#090B0F` | `oklch(98% 0 0)` → `#F8F8F8` | `#000000` / `#FFFFFF` |
| `ticketInk` | Minutos y destino en el billete (AAA) | `oklch(100% 0 0)` → `#FFFFFF` | `oklch(12% 0 0)` → `#060606` | `#FFFFFF` / `#000000` |
| `ticketInk2` | Unidad «min», hora y longitud en el billete | `oklch(80% 0.005 260)` → `#BCBEC1` | `oklch(38% 0.005 260)` → `#414245` | `#DEDEDE` / `#222222` |
| `ticketWarn` | Retraso dentro del billete | `oklch(82% 0.14 72)` → `#FCB452` | `oklch(50% 0.13 55)` → `#994A00` ⁽ᵍ⁾ | `#FFCE78` / `#7B3702` |
| `pace` | Fondo de la etiqueta de ritmo «Anda» / «Con calma» (con alfa, sobre el billete) | `oklch(50% 0 0 / 0.35)` → `#63636359` | `oklch(50% 0 0 / 0.25)` → `#63636340` | = |
| `via` | Caja sólida de la vía CONFIRMADA | `oklch(88% 0.17 92)` → `#FFD32E` ⁽ᵍ⁾ | `oklch(88% 0.17 92)` → `#FFD32E` ⁽ᵍ⁾ | = |
| `viaInk` | Texto dentro de la caja de vía (AAA) | `oklch(18% 0.02 80)` → `#161107` | `oklch(18% 0.02 80)` → `#161107` | = |
| `viaEdge` | Canto de 1 pt de la caja de vía, siempre | `oklch(58% 0.12 85)` → `#9B7300` ⁽ᵍ⁾ | `oklch(58% 0.12 85)` → `#9B7300` ⁽ᵍ⁾ | `#634800` / `#634800` |
| `accent` | Azul para texto e iconos interactivos (enlaces, pestaña activa, «Guardar») | `oklch(52% 0.2 258)` → `#0061D8` ⁽ᵍ⁾ | `oklch(68% 0.16 252)` → `#439BF7` | `#0643B5` / `#7ABDFF` |
| `accentFill` | Relleno del botón principal con texto blanco (B daba 3,7:1) | `oklch(53% 0.21 258)` → `#0063E1` ⁽ᵍ⁾ | `oklch(53% 0.21 258)` → `#0063E1` ⁽ᵍ⁾ | `#0244BE` / `#0A4AC5` |
| `onAccent` | Texto sobre accentFill y sobre bad | `oklch(100% 0 0)` → `#FFFFFF` | `oklch(100% 0 0)` → `#FFFFFF` | = |
| `warn` | Perturbada: icono y fondo del aviso (con alfa) | `oklch(76% 0.16 65)` → `#F59926` | `oklch(76% 0.16 65)` → `#F59926` | = |
| `warnText` | Texto de aviso: «Perturbada», «+2 min», «cualquier sentido» | `oklch(50% 0.13 55)` → `#994A00` ⁽ᵍ⁾ | `oklch(80% 0.15 72)` → `#F8AC3D` | `#773400` / `#FFCA75` |
| `noticeWarn` | Fondo del aviso de línea perturbada (sobre la tarjeta) | `oklch(76% 0.16 65 / 0.18)` → `#F599262E` | `oklch(76% 0.16 65 / 0.16)` → `#F5992629` | = |
| `bad` | Interrumpida / peligro: relleno de «Corre», del botón rojo y del banner de línea cortada (texto blanco encima) | `oklch(55% 0.2 25)` → `#CC272E` | `oklch(55% 0.2 25)` → `#CC272E` | `#A9131F` / `#A9131F` |
| `badText` | Texto de error: «Interrumpida», «pasa por la línea cortada», «Eliminar ruta» | `oklch(50% 0.19 25)` → `#B71824` | `oklch(72% 0.16 22)` → `#F97676` | `#8D0A17` / `#FFA7A7` |
| `noticeBad` | Fondo del aviso de línea interrumpida | `oklch(60% 0.21 25 / 0.14)` → `#E2343924` | `oklch(60% 0.21 25 / 0.2)` → `#E2343933` | = |
| `ok` | Relleno verde: billete «En andén», interruptores, punto «en directo» en oscuro | `oklch(72% 0.17 155)` → `#22C373` | `oklch(72% 0.17 155)` → `#22C373` | = |
| `okText` | Texto e iconos verdes (punto «en directo» y «listo» en claro; B daba 2,1:1) | `oklch(50% 0.13 155)` → `#007840` ⁽ᵍ⁾ | `oklch(76% 0.16 155)` → `#46CE83` | `#00572E` / `#83E7A8` |
| `atStopInk` | Texto sobre el billete verde «En andén» (AAA) | `oklch(19% 0.03 155)` → `#08180E` | `oklch(19% 0.03 155)` → `#08180E` | = |
| `shadow` | Color base de las sombras (la opacidad va en cada sombra) | `oklch(0% 0 0)` → `#000000` | `oklch(0% 0 0)` → `#000000` | = |
| `mapCasing` | Contorno del trazado de la línea en el mapa | `oklch(100% 0 0)` → `#FFFFFF` | `oklch(0% 0 0)` → `#000000` | = |
| `mapStopFill` | Relleno de las paradas servidas | `oklch(100% 0 0)` → `#FFFFFF` | `oklch(19.1% 0.006 271.1)` → `#131417` | = |
| `mapWalk` | Punteado del camino a pie | `oklch(28.7% 0.007 285.9)` → `#2A2A2E` | `oklch(92.6% 0.005 286.3)` → `#E6E6EA` | = |
| `lineFallback` | Gris de reserva cuando la API no manda color de línea (R57) | `oklch(55.3% 0.022 260.2)` → `#6B7380` | `oklch(55.3% 0.022 260.2)` → `#6B7380` | = |

⁽ᵍ⁾ fuera de la gama sRGB: llevado dentro con el mapeo de gama de CSS Color 4 (croma reducido hasta ΔEok < 0,02; el tono y la luminosidad no se tocan).
<!-- /generado:colores -->

### 3.2 Reglas de uso

| Qué | Token | Nunca |
|---|---|---|
| Fondo de pantalla, debajo del mapa | `bg` | — |
| Tarjeta de tramo, ruta, opción, alternativa | `surface` (opaca) + filete `rule` | cristal debajo de minutos |
| Ficha de salida 2.ª–4.ª, campos, segmentos | `surfaceHi` | — |
| Texto principal / secundario / terciario | `ink` / `ink2` / `ink3` | `ink3` para algo que haya que leer a contraluz |
| El billete (primera salida) | `ticket` + `ticketInk`, `ticketInk2`, `ticketWarn` | opacidad sobre el billete (B usaba .7/.75: aquí son colores opacos) |
| Vía confirmada | `via` + `viaInk` + canto `viaEdge` | amarillo para cualquier otra cosa (B lo usaba en «Sin conexión») |
| Enlaces, pestaña activa, «Guardar» | `accent` (es el `AccentColor` de la app) | azul para texto no interactivo |
| Botón principal | `accentFill` + `onAccent` | — |
| Perturbada | icono `warn`, texto `warnText`, fondo `noticeWarn` | `warn` como color de texto en claro (2,0:1) |
| Interrumpida, «Corre», peligro | relleno `bad` + `onAccent`; texto `badText`; fondo `noticeBad` | `bad` como color de texto |
| En andén, «listo», en directo | relleno `ok` + `atStopInk`; texto/icono `okText` | `ok` como texto en claro (2,1:1) |
| Colores de línea | `LineColor.badge(line:officialText:)` | calcular la tinta con un umbral fijo |

### 3.3 Lo que se ha corregido de B (contraste)

B se diseñó con buen ojo, pero varias parejas no llegaban a AA. Medido con el
mismo script (compuestos incluidos):

<!-- generado:contrastesB -->
| Pareja en B | Claro | Oscuro |
|---|---|---|
| --ink-3 sobre --bg | **3,81** ✗ | **4,18** ✗ |
| --ink-3 sobre ficha | **3,49** ✗ | **2,99** ✗ |
| --warn (texto) sobre --bg | **1,98** ✗ | 9,13 |
| --warn sobre el billete | 8,84 | **2,1** ✗ |
| --bad (texto) sobre --bg | **3,9** ✗ | 4,63 |
| blanco sobre --bad | **4,38** ✗ | **4,38** ✗ |
| --ok (punto) sobre --bg | **2,06** ✗ | 8,78 |
| --accent (texto) sobre --bg | **3,3** ✗ | 5,48 |
| blanco sobre --accent | **3,7** ✗ | **3,7** ✗ |
<!-- /generado:contrastesB -->

Correcciones (el detalle, en `ajustes-b.md` A2): `ink3` más oscuro en claro y
más claro en oscuro; tokens de **texto** separados para los estados
(`warnText`, `badText`, `okText`) porque los rellenos de B sirven como
relleno pero no como letra; `ticketWarn` para el retraso dentro del billete
(el billete invierte el tema, así que necesita el aviso del tema contrario);
`accent` más profundo en claro y algo más luminoso en oscuro, y `accentFill` más oscuro para que el blanco
encima dé 4,5:1; `bad` un punto más oscuro por lo mismo; canto `viaEdge`
para que la caja amarilla no se desdibuje sobre blanco (1,3:1 sin él).

El azul ya no es exactamente `systemBlue`: `systemBlue` da 4,0:1 sobre
blanco y 3,7:1 con blanco encima, por debajo de AA. `accent` conserva el tono
de B (255–258°) y es el `AccentColor` del catálogo, así que los controles del
sistema (interruptores, pestañas, enlaces) usan el mismo.

### 3.4 Contrastes garantizados

Todas estas parejas se comprueban en cada ejecución del script. Mínimos:
4,5:1 (AA) para texto; 7:1 (AAA) para minutos, vía y todo el texto con
«Aumentar contraste»; 3:1 para formas que identifican algo (WCAG 1.4.11).

<!-- generado:contrastes -->
| Texto | Fondo | Claro | Oscuro | Claro HC | Oscuro HC | Mínimo | Para qué |
|---|---|---|---|---|---|---|---|
| `ink` | `bg` | 17,51 | 18,61 | 18,65 | 20,3 | 7:1 | texto principal |
| `ink` | `surface` | 19,23 | 17,09 | 20,47 | 18,64 | 7:1 | texto en tarjeta |
| `ink2` | `bg` | 8,2 | 10,14 | 13,41 | 14,14 | 4,5 / 7:1 | secundario |
| `ink2` | `surface` | 9 | 9,31 | 14,72 | 12,99 | 4,5 / 7:1 | secundario en tarjeta |
| `ink2` | `surfaceHi` | 7,61 | 7,53 | 12,45 | 10,5 | 4,5 / 7:1 | secundario en ficha |
| `ink3` | `bg` | 5,82 | 7,89 | 11,29 | 12,43 | 4,5 / 7:1 | terciario (rótulos, pie) |
| `ink3` | `surface` | 6,39 | 7,24 | 12,4 | 11,41 | 4,5 / 7:1 | terciario en tarjeta |
| `ink3` | `surfaceHi` | 5,4 | 5,85 | 10,48 | 9,22 | 4,5 / 7:1 | terciario en ficha («min», hora) |
| `ink` | `surfaceHi` | 16,25 | 13,81 | 17,31 | 15,07 | 7:1 | minutos de las fichas |
| `ink` | `glassOpaque` | 18,73 | 17,58 | 19,95 | 19,18 | 7:1 | texto en cristal opaco |
| `ink2` | `glassOpaque` | 8,77 | 9,58 | 14,35 | 13,36 | 4,5 / 7:1 | secundario en cristal opaco |
| `ticketInk` | `ticket` | 19,67 | 19,16 | 20,95 | 21 | 7:1 | MINUTOS en el billete |
| `ticketInk2` | `ticket` | 10,53 | 9,45 | 15,54 | 16 | 4,5 / 7:1 | «min», hora y longitud en el billete |
| `ticketWarn` | `ticket` | 11,03 | 5,92 | 14,28 | 8,83 | 4,5 / 7:1 | retraso en el billete |
| `ticketInk` | `pace` sobre `ticket` | 14,38 | 13,56 | 15,73 | 14,74 | 4,5 / 7:1 | etiqueta de ritmo |
| `viaInk` | `via` | 13,06 | 13,06 | 13,06 | 13,06 | 7:1 | VÍA confirmada |
| `accent` | `bg` | 5,04 | 7,04 | 7,56 | 10,17 | 4,5 / 7:1 | enlace sobre fondo |
| `accent` | `surface` | 5,54 | 6,47 | 8,3 | 9,34 | 4,5 / 7:1 | enlace en tarjeta |
| `accent` | `glassOpaque` | 5,39 | 6,65 | 8,09 | 9,61 | 4,5 / 7:1 | enlace en cristal opaco |
| `onAccent` | `accentFill` | 5,43 | 5,43 | 8,18 | 7,48 | 4,5 / 7:1 | botón principal |
| `warnText` | `bg` | 5,59 | 10,61 | 8,2 | 13,52 | 4,5 / 7:1 | aviso sobre fondo |
| `warnText` | `surface` | 6,13 | 9,74 | 9 | 12,42 | 4,5 / 7:1 | aviso en tarjeta |
| `warnText` | `surfaceHi` | 5,18 | 7,88 | 7,61 | 10,04 | 4,5 / 7:1 | retraso en ficha |
| `warnText` | `noticeWarn` sobre `surface` | 5,34 | 7,45 | 7,84 | 9,49 | 4,5 / 7:1 | rótulo del aviso |
| `ink` | `noticeWarn` sobre `surface` | 16,75 | 13,06 | 17,83 | 14,25 | 7:1 | texto del aviso |
| `badText` | `bg` | 5,9 | 7,62 | 8,54 | 10,95 | 4,5 / 7:1 | error sobre fondo |
| `badText` | `surface` | 6,48 | 7 | 9,37 | 10,06 | 4,5 / 7:1 | error en tarjeta |
| `badText` | `noticeBad` sobre `surface` | 5,3 | 5,86 | 7,67 | 8,42 | 4,5 / 7:1 | rótulo del aviso interrumpido |
| `ink` | `noticeBad` sobre `surface` | 15,73 | 14,3 | 16,75 | 15,6 | 7:1 | texto del aviso interrumpido |
| `onAccent` | `bad` | 5,38 | 5,38 | 7,51 | 7,51 | 4,5 / 7:1 | «Corre», botón rojo |
| `okText` | `bg` | 4,98 | 10,09 | 7,8 | 13,49 | 4,5 / 7:1 | «listo», en directo |
| `okText` | `surface` | 5,47 | 9,26 | 8,57 | 12,38 | 4,5 / 7:1 | «listo» en tarjeta |
| `atStopInk` | `ok` | 7,94 | 7,94 | 7,94 | 7,94 | 7:1 | billete «En andén» |
| `via` | `ticket` | 13,65 | — | 14,54 | — | 3:1 | caja de vía sobre el billete oscuro (forma) |
| `viaEdge` | `ticket` | — | 4,08 | — | 8,52 | 3:1 | canto de la caja de vía sobre el billete blanco (forma) |
| `viaEdge` | `surface` | 4,23 | — | 8,33 | — | 3:1 | canto de la caja de vía en tarjeta clara (forma) |
| `viaEdge` | `surfaceHi` | 3,57 | — | 7,04 | — | 3:1 | canto de la caja de vía en ficha clara (forma) |
| `via` | `surfaceHi` | — | 10,46 | — | 10,46 | 3:1 | caja de vía en ficha oscura (forma) |
| `accentFill` | `bg` | 4,83 | 3,74 | 7,28 | — | 3:1 | botón principal contra el fondo (forma) |
| `glassEdge` | `bg` | — | — | 3,29 | 4,46 | 3:1 | canto del cristal con Aumentar contraste (forma) |
<!-- /generado:contrastes -->

La única variante que no se exige es `accentFill` contra el fondo en oscuro
con contraste alto (≈ 2,7:1): ahí el relleno baja para que el texto blanco
dé 7:1, y el botón se identifica por su etiqueta (1.4.11 no pide el borde).

### 3.5 «Aumentar contraste» y «Reducir transparencia»

- **Aumentar contraste** (`UITraitCollection.accessibilityContrast == .high`,
  en SwiftUI `\.colorSchemeContrast == .increased`): los tokens cambian solos
  (columna HC). Además: canto de 1,5 pt en tarjetas y cristal
  (`glassEdge` pasa de casi invisible a 3:1), canto en el distintivo de línea,
  `rule` más marcado. En iOS 26 el cristal del sistema también se endurece.
- **Reducir transparencia** (`\.accessibilityReduceTransparency`): el
  cristal pasa a **opaco** (`glassOpaque`, que es el compuesto de B sobre el
  fondo) con canto. Lo hace `.cristal(...)` en todas las versiones, antes de
  mirar si hay `glassEffect`. Las hojas y barras del sistema lo hacen solas.
- **Diferenciar sin color** (`\.accessibilityDifferentiateWithoutColor`):
  el sistema ya distingue por forma y palabra (vía, ritmo, estado de línea
  con icono y rótulo), así que no cambia nada.

### 3.6 Colores de línea (R12, R57)

- El color viene de `line_color` (sin «#») en el tablero y de `color`
  (con «#») en el mapa. `LineRGB(hex:)` acepta los dos y además «0x», 3, 4,
  6 u 8 dígitos y espacios; lo que no entiende da el gris de reserva
  `#6B7380` (R57).
- **Tinta del distintivo**: el texto oficial de IDFM (`textcolourweb_hexa`,
  que el servidor manda como `text_color` en `/api/v1/routes/{id}/map`) si
  da **≥ 4,5:1**; si no, negro o blanco, **el que más contraste dé**. Negro
  y blanco empatan a luminancia ≈ 0,18 con 4,58:1, así que la tinta
  calculada nunca baja de 4,58:1 y la oficial, cuando se usa, de 4,5:1.
- **Consecuencia que se ve**: el texto oficial de IDFM (casi siempre blanco)
  no llega a 4,5:1 en 11 de las 49 líneas (RER A, B y D, Transilien K, N y
  V, T6, T9, T14 y los VAL). Ahí el código va en **negro** sobre el color
  oficial. El color de fondo, que es lo que el ojo reconoce, no se toca.
  Alternativa descartada (y fácil de activar si se prefiere la señalética):
  aceptar la oficial desde 3:1 cuando el distintivo es «texto grande» (caja
  ≥ 37 pt, letra ≥ 18,5 pt black); se descartó porque la misma línea
  saldría con texto blanco en la cabecera y negro en las cadenas.
- El tablero (`BoardLegV1`) no trae
  `text_color`: ahí se calcula siempre, y la app puede reutilizar el del mapa
  si ya lo tiene en caché.
- La v1 elegía negro por encima de luminancia 0,45: los colores entre 0,18 y
  0,45 recibían blanco con menos de 4,5:1 (naranja de prueba: 2,5:1). Tabla
  completa, con las 49 líneas ferroviarias, de metro y tranvía del
  referencial de IDFM, en el **anexo A**.
- El servidor, cuando falta el texto oficial, calcula uno con la fórmula YIQ
  (`mapdata.py:_contrast`), que tampoco garantiza AA: la app no se fía y
  vuelve a comprobarlo.

### 3.7 Mapa

MapKit no deja retintar el mapa base como hacía B con MapLibre. Se usa
`.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest:
.excludingAll))` (iOS 17), que da un mapa apagado en claro y oscuro, y todo
el color lo ponen los trazados:

| Pieza | Cómo | Tokens |
|---|---|---|
| Trazado de la línea | `MapPolyline(coordinates:)` con `.stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))` encima de un contorno de 10 pt | color de línea; contorno `mapCasing` |
| Paradas servidas | `Annotation` con círculo de 5 pt (7 en origen y destino), relleno `mapStopFill`, trazo 2,5 pt del color de línea | `mapStopFill` |
| Paradas de paso | círculo de 2,5 pt del color de línea | — |
| Camino a pie | `MapPolyline` con `StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 6])` (puntos) | `mapWalk` |
| Mi posición | `UserAnnotation()` del sistema (su pulso ya respeta «Reducir movimiento») | — |
| Transbordo | el trazado de la otra línea; el tiempo mínimo de `min_transfer_s` en una etiqueta; **no hay camino entre andenes en los datos abiertos** (decisiones D1.7): no se dibuja | — |

Los tintes de MapLibre de B quedan en `tokens.json` (`mapa.tintesB`) por si
algún día se usa MapLibre Native.

---

## 4. Tipografía

### 4.1 Texto: estilos de Dynamic Type

SF Pro (el del sistema). **Nada de tamaños fijos**: cada nivel es un estilo de
Dynamic Type con su peso (`Font.system(_:design:weight:)`, iOS 16+). Tamaño
entre paréntesis = el de fábrica («Grande»). Correspondencia con B (base web
16 px).

| Nivel (`TextLevel`) | Estilo | Peso | Dígitos | Tope Dynamic Type | En B |
|---|---|---|---|---|---|
| `screenTitle` | `.largeTitle` (34) | bold | — | — | título grande nativo |
| `navTitle` | `.headline` (17) | semibold | — | — | `.glass-title` 1.05rem·700 |
| `routeTitle` | `.title3` (20) | heavy | — | AX2 | `.board-head h1` 1.15rem·800 |
| `legTitle` | `.headline` (17) | bold | — | — | `.leg-head h2` 1rem·700 |
| `legSubtitle` | `.footnote` (13) | regular | — | — | `.leg-head p` .8rem |
| `kicker` | `.caption` (12) | semibold | — | — | `.kicker` .78rem·600 |
| `body` | `.body` (17) | regular | — | — | `.li` .95rem |
| `bodyStrong` | `.body` (17) | semibold | — | — | `.field input` 1rem·600 |
| `callout` | `.subheadline` (15) | regular | — | — | `.notice p` .86rem |
| `meta` | `.footnote` (13) | regular | tabulares | — | `.tk-meta` .78rem |
| `status` | `.footnote` (13) | semibold | tabulares | — | `.status` .8rem·600 |
| `noticeTitle` | `.footnote` (13) | bold | — | — | `.notice-head` .8rem·700 |
| `destination` | `.headline` (17) | bold | — | AX3 | `.tk-dest` 1rem·700 |
| `unit` («min») | `.footnote` (13) | bold, rounded | tabulares | AX2 | `.tk-num small` .85rem·700 |
| `chipCaption` | `.caption` (12) | regular | tabulares | AX1 | `.chip-at` .72rem |
| `label` | `.caption2` (11) | bold | — | AX1 | `.pace`, `.tag`, `.via small` |
| `button` | `.body` (17) | semibold | — | — | `.btn` .98rem·700 |
| `buttonSmall` | `.subheadline` (15) | semibold | — | — | `.btn-small` .85rem |
| `footnote` | `.caption` (12) | regular | tabulares | — | `.foot` .78rem |

En código: `.textLevel(.legTitle)`. Los rótulos van en minúscula normal (B);
nada de versales espaciadas de la v1.

### 4.2 Cifras: SF Pro Rounded heavy, tabulares, con tope

`.system(size:weight: .heavy, design: .rounded).monospacedDigit()`, tamaño con
`@ScaledMetric(relativeTo:)` y **tope** para que los minutos no rompan la
maqueta con los tamaños de accesibilidad. Tracking −0,02 × tamaño (B:
`letter-spacing: −.02em`). En código: `.numberFont(.ticket)`.

| Nivel (`NumberLevel`) | Base (pt) | Escala con | Tope (pt) | Uso | En B |
|---|---|---|---|---|---|
| `ticket` | 56 | `.largeTitle` | 80 | billete, 1–2 tramos | `.tk-num .num` 3.6rem·900 |
| `ticketNormal` | 48 | `.largeTitle` | 72 | billete, 3–4 tramos | — |
| `ticketCompact` | 40 | `.largeTitle` | 60 | billete, 5–6 tramos (mínimo absoluto) | — |
| `chip` | 24 | `.title2` | 40 | fichas 2.ª–4.ª | `.chip .num` 1.5rem·900 |
| `via` | 20 | `.title3` | 32 | número de vía | `.via b` 1.2rem·900 |
| `stat` | 30 | `.title` | 48 | fichas de estadísticas, minutos de planes | `.solid-num` 1.9rem·900 |
| `statBig` | 48 | `.largeTitle` | 72 | acierto de la vía | `.solid-num.big` 3rem·900 |
| `badge` | 15 | `.subheadline` | 22 | código de línea (el distintivo escala su caja) | `.badge` .95rem·900 |

B pinta las cifras a 900 porque Nunito heavy es más fina que SF Rounded heavy;
en iOS, **heavy** (el concepto) ya da ese peso. El distintivo usa black.

Escala según lo que se dice (`DepartureMoment.numberScale`):

| Momento | Texto | Escala | Por qué |
|---|---|---|---|
| minutos < 60 | «6» + «min» | 1 | — |
| minutos ≥ 60 | «1h46», sin unidad (R6) | 0,75 | no es urgente, y «1h46» a 56 pt no cabe en un SE junto al destino |
| contador a cero | «ya» | 1 | dos letras y lo más urgente (R15) |
| `at_stop` | «En andén» | 0,5, una línea, `minimumScaleFactor(0.7)` | en B salía a tamaño completo y partía el billete en dos líneas enormes |

### 4.3 Densidad (R47)

`BoardDensity(legCount:)`: 1–2 tramos **holgado** (`ticket`), 3–4 **normal**
(`ticketNormal`), 5–6 **compacto** (`ticketCompact`, las fichas pierden la
segunda línea). B no tenía densidades: con cinco tramos el tablero era una
lista larguísima (ajuste A9).

### 4.4 Dynamic Type grande

- Hasta XXXL el billete conserva su fila: cifra · destino · vía/ritmo.
- Con tamaños de accesibilidad (`dynamicTypeSize.isAccessibilitySize`), el
  billete pasa a dos filas con `AnyLayout` (B ya lo hacía con «letra
  grande»): arriba cifra y destino, debajo vía, ritmo y metadatos.
- El destino admite dos líneas (`lineLimit(2)`, `minimumScaleFactor(0.85)`)
  antes de truncar; B lo cortaba a una con puntos suspensivos (ajuste A7).
- Las pestañas nunca pierden la etiqueta (B las quitaba con letra grande): la
  barra del sistema ya ofrece el visor de contenido grande al mantener
  pulsado.
- Estadísticas: 3 fichas por fila hasta XXXL; 1 por fila en AX (con
  `ViewThatFits` o `Grid` que cambia de columnas).

---

## 5. Espaciado, radios y tamaños

### 5.1 Espaciado (`Metrics.Space`)

Rejilla de 2 pt con los pasos de B.

| Token | pt | Uso |
|---|---|---|
| `hair` | 2 | entre destino y metadatos |
| `xs` | 4 | cifra–unidad, dentro de la vía |
| `s` | 6 | vía–ritmo en el billete, entre distintivos de una cadena |
| `sm` | 8 | entre fichas, icono–texto |
| `m` | 10 | entre aviso y billete, entre filas de una cadena |
| `ml` | 12 | columnas del billete, relleno de tarjeta (`Size.cardPadding`) |
| `gutter` | 14 | **margen lateral de pantalla** y separación entre tarjetas (B) |
| `l` | 16 | relleno de botones, entre secciones |
| `xl` | 20 | relleno del botón principal, hojas |
| `xxl` | 28 | rótulo de sección alineado con el contenido de la tarjeta |

### 5.2 Radios y concentricidad (`Metrics.Radius`)

Todos `RoundedRectangle(cornerRadius:style: .continuous)`.

| Token | pt | Uso |
|---|---|---|
| `via` | 10 | caja de vía, real o probable |
| `inner` | 18 | billete, fichas, aviso, banner de estado dentro de tarjeta |
| `tile` | 22 | fichas de estadísticas |
| `card` | 30 | tarjeta opaca |
| `bar` | 30 | cabecera de cristal, tarjeta del mapa, píldora |
| `sheet` | 36 | hojas propias (las del sistema traen el suyo) |
| `badgeRatio` | 0,3 | distintivo: radio = 30 % del lado |
| cápsula | — | botones, ritmo, etiquetas, pestañas |

**Concentricidad**: un elemento que toca una esquina de su contenedor lleva
radio = radio del contenedor − margen (`Metrics.Radius.concentric(outer:
padding:)`). Tarjeta 30 con 12 de relleno → hijos a 18. En B no casaba
(tarjeta 28, relleno 14, billete 22, fichas 16): se ve en la esquina inferior
izquierda de cada tarjeta. En iOS 26 el sistema tiene formas concéntricas que
lo calculan solas; aquí se calcula a mano para que sea igual desde iOS 17. El
panel inferior del mapa, pegado a las esquinas de la pantalla, sí conviene
delegarlo al sistema en iOS 26 (radio de la pantalla − margen).

### 5.3 Tamaños (`Metrics.Size`)

| Token | pt | Uso |
|---|---|---|
| `hit` | 44 | área táctil mínima (R52); `.hitTarget()` |
| `glassButton` | 44 | botón redondo de cristal |
| `primaryButton` | 50 | alto del botón principal y de peligro |
| `row` | 48 | fila de lista |
| `badgeSmall` / `badge` / `badgeLarge` | 25 / 30 / 42 | distintivo en cadenas / listas / cabecera de tramo |
| `chipMinWidth` | 92 | ficha de salida |
| `refreshBar` | 2 | barra del próximo refresco (R54) |
| `liveDot` | 9 | punto «en directo» |
| `dashWidth`, `dash` | 1,5 · [4, 3] | recuadro punteado de la vía probable |
| `viaRing` | 6 | anillo del latido |
| `cardPadding` / `ticketPadding` | 12 / 14 | rellenos |

Opacidades con significado (`Metrics.Opacity`): tablero viejo 0,55 y
saturación 0,2 (R19); alternativa que no sirve 0,55 (R30); pulsado con
«Reducir movimiento» 0,7.

---

## 6. Cristal y materiales

### 6.1 Dónde hay cristal y dónde no

| Sí (capa de controles) | No (contenido) |
|---|---|
| cabecera del tablero (selector de ruta + ajustes) | tarjetas de tramo (opacas) |
| píldora de estado «en directo · hace 6 s» | el billete (opaco) |
| barra superior del mapa: atrás, píldora de ruta, centrar | la vía (caja sólida o recuadro) |
| tarjeta inferior del modo trayecto | fichas de salidas |
| hoja de emparejar, aviso efímero (toast) | listas de rutas, planes, estadísticas |
| botones redondos de cristal | avisos de línea |
| **del sistema, sin hacer nada**: barra de pestañas, barras de navegación y herramientas, hojas, menús, `MapUserLocationButton` | |

### 6.2 Cómo se pinta: `.cristal(_:in:tint:)` (Glass.swift)

Tres caminos, en este orden:

1. **«Reducir transparencia»** → opaco: `glassOpaque` + canto `glassEdge`.
   Se comprueba primero, en todas las versiones.
2. **iOS 26** (`if #available(iOS 26.0, *)`) → `glassEffect(_:in:)` con
   `Glass.regular` (+ `.tint(_:)` si hay tinte, + `.interactive()` en los
   controles). Sin sombra propia: la pone el sistema. Con «Aumentar
   contraste», canto de 1,5 pt.
3. **iOS 17–25** → la receta de B: material (`.ultraThinMaterial` en barras
   y controles, `.regularMaterial` en paneles con texto) + tinte `glass`
   (58 % blanco / 55 % negro, como B) + canto con brillo arriba
   (`glassHighlight` → `glassEdge`, B: `inset 0 1px 0`) + sombra `glass` o
   `glassButton`.

Papeles (`CristalRole`): `.bar` (barras), `.control` (se toca: interactivo en
iOS 26), `.panel` (lleva texto: material más opaco).

Otros:

- `CristalGroup(spacing:) { … }` → `GlassEffectContainer` en iOS 26 (las
  piezas cercanas se funden y hacen morph); nada en iOS 17–25.
- `.cristalID(id, in: ns)` → `glassEffectID` en iOS 26;
  `matchedGeometryEffect` antes. Es el morph «Iniciar trayecto» → tarjeta del
  modo trayecto.
- `.cristalButton(prominent:circle:)` → `.buttonStyle(.glass)` /
  `.glassProminent` en iOS 26; `CristalFallbackButtonStyle` antes y con
  «Reducir transparencia».
- `.filledButton(.primary / .danger)` → botón opaco (no es cristal).
- Tinte: con cuentagotas (p. ej. rojo en «Parar trayecto» si fuese de
  cristal). Nunca un color de línea como tinte de cristal.

### 6.3 Sombras (`Metrics.Shadow`)

CSS `blur` ≈ 2σ; SwiftUI `radius` ≈ blur / 2.

| Token | En B | SwiftUI | Dónde |
|---|---|---|---|
| `glass` | `0 10px 30px / .18` | `shadow(.black.opacity(0.18), radius: 15, y: 10)` | barras de cristal, solo iOS 17–25 |
| `glassButton` | `0 4px 14px / .15` | radius 7, y 4 | botones de cristal, solo iOS 17–25 |
| `card` | `0 6px 24px / .12` | radius 12, y 6 | tarjeta opaca (`cardBackground()`) |
| `filled` | `0 8px 20px color / .35` | radius 10, y 8, del color del botón | botón principal y de peligro |
| `viaGlow` | `0 0 24px via/.8` + anillo `0 0 0 6px via/.45` | radius 12 + anillo de 6 pt | latido de la vía nueva |
| filete del distintivo | `inset 0 -2px 0 / .15` | overlay de 2 pt abajo, no sombra | distintivo |

En oscuro las sombras apenas se ven; no se compensan.

---

## 7. Componentes y sus estados

Cada componente: anatomía, tokens, estados, VoiceOver y cómo se hace en
SwiftUI. Los datos son **solo los que da la API** (`docs/openapi.yaml`,
`BoardV1`/`BoardLegV1`/`Departure`); nada de ocupación, nada de posición de
trenes.

### 7.1 Tablero (la pantalla)

Anatomía de B, de arriba abajo:

1. **Mapa** no interactivo en el 46 % superior (`Map` con
   `.allowsHitTesting(false)`, sin etiquetas, trazado de la ruta), con un
   degradado `bg` que lo funde con el fondo entre el 30 % y el 50 %.
2. **Cabecera de cristal** (`.cristal(.bar)`, radio 30, relleno 10/18) fija
   arriba: rótulo (`kicker`) + nombre de la ruta (`routeTitle`), y a la
   derecha el botón redondo de ajustes (`.cristalButton(circle: true)`,
   `gearshape`). El nombre es un **`Menu`**: «La que toca ahora» + las rutas
   guardadas (F8). Rótulo: «La que toca ahora» si `auto_selected`, «Ruta
   elegida» si la fijó el usuario (R37).
3. **Píldora de estado** (7.9) sobre el borde del degradado.
4. **Tarjetas de tramo** (7.8), separadas 14 pt, dentro de un `ScrollView`
   con `.refreshable` (tirar para refrescar, F12).
5. Botón **«Buscar alternativa»**: de cristal si todo va bien; de peligro
   (`.filledButton(.danger)`) con «· línea 14 cortada» si `worst_level` = 2.
6. **Pie**: errores de estación (hasta 3, R26) y «640 llamadas hoy · se
   refresca cada 30 s mientras miras» (el número de segundos sale de
   `server.refresh_hint_s`, nunca menos de 30; R46, R7).
7. **Barra de pestañas** del sistema (7.11).

Estados de la pantalla (7.18): cargando sin nada guardado, vacío (sin rutas),
error sin caché, servidor sin clave, ruta borrada (404). **Nunca pantalla en
blanco** (R9): con cualquier error, si hay tablero guardado se enseña ese.

**Dato viejo** (R19: `stale` del servidor o > 90 s sin tablero nuevo; nunca
por `data_age`): todo el contenido de debajo de la cabecera se apaga con
`.opacity(0.55).saturation(0.2)` animado 0,45 s (`Motion.Kind.staleDim`), y
la píldora de estado lo explica sin apagarse. Nada de latidos ni hápticas con
el dato viejo.

### 7.2 El billete de minutos (primera salida de cada tramo)

Cápsula **opaca** `ticket`, radio 18, relleno 12 × 14. Tres columnas
(`HStack(alignment: .center, spacing: 12)`):

| Columna | Contenido | Tokens |
|---|---|---|
| Cifra | minutos + «min» alineados por la base (`.firstTextBaseline`), ancho mínimo 3,4 cifras para que no baile | `.numberFont(density.ticketNumber, scale: moment.numberScale)`, `ticketInk`; unidad `.textLevel(.unit)` `ticketInk2` |
| Cuerpo | destino (`destination`, 2 líneas máx.); debajo, metadatos (`meta`): hora prevista «12:56», retraso, longitud | `ticketInk`; metadatos `ticketInk2`; retraso `ticketWarn` |
| Derecha | vía (7.4) y debajo el ritmo (7.6) | — |

Estados:

| Estado | Dato | Qué se ve |
|---|---|---|
| Normal | `minutes` 1–59 | «6» «min», destino, «12:56», ritmo |
| Largo | `minutes` ≥ 60 | «1h46» a 0,75×, sin «min» (R6) |
| Ya | `minutes` 0 y no `at_stop` | «ya» a tamaño completo, ritmo «Corre» |
| En andén | `at_stop` | billete **verde** (`ok` + `atStopInk`), «En andén» a 0,5×; sin ritmo (R15, R16); los metadatos NO repiten «en el andén» (B lo duplicaba) |
| Retraso | `delay` ≠ 0 y hay `aimed_at` | «+2 min» en `ticketWarn` negrita; adelanto «−1 min» en `ticketInk2` (R14). `delay` null → nada (R4) |
| Longitud | `length` short/long | icono `rectangle` / `rectangle.split.2x1` + «corto» / «largo» (R5) |
| Destinos mezclados | tramo sin `directions` y destinos distintos | el destino es obligatorio en cada billete y ficha (R24) |
| Vía | ver 7.4 | — |
| Dato viejo | tablero apagado | igual, apagado con el resto |
| Accesibilidad AX | `isAccessibilitySize` | dos filas (4.4) |

Movimiento: la cifra cambia con `.minutesTransition(value: minutes)`
(`contentTransition(.numericText(countsDown: true))` + muelle 0,5 s; con
«Reducir movimiento», fundido). Cuando la salida pasa, el billete de la
siguiente sube a su sitio: identidad estable por `jid` (R23) y
`.transition(.push(from: .trailing))` con `Motion.Kind.morph`. Háptica
`.trainSoon` una vez cuando la primera salida del primer tramo baja a ≤ 2 min.

VoiceOver (R50): un solo elemento, frase completa:
«Tren a Ermont - Eaubonne, en 6 minutos, a las 12:56, vía 21, tren largo.»,
«… sale ya», «… parado en el andén», «… en 1 hora y 46 minutos» (concordancia
correcta; la v1 decía «1 horas»), «… 2 minutos de retraso», «… vía 21
probable, 90 por ciento, por el número de tren».

### 7.3 Fichas de las salidas 2.ª–4.ª

`ScrollView(.horizontal)` con `LazyHStack(spacing: 8)`,
`.scrollTargetBehavior(.viewAligned)` (iOS 17) para que encaje en cada ficha,
sin indicadores (F17). Ficha: `surfaceHi`, radio 18, relleno 8 × 12, ancho
mínimo 92.

- Fila 1: cifra `.numberFont(.chip)` en `ink` + «min» `label` en `ink3`.
- Fila 2 (no en compacto): destino si hay mezcla (R24), si no la hora
  (`chipCaption`, `ink3`); vía compacta (7.4); longitud; retraso (`warnText`
  si es positivo, `ink2` si es adelanto: B solo enseñaba los positivos).
- Sin ritmo (R16: solo la primera salida).
- VoiceOver: frase completa, igual que el billete.

### 7.4 La vía: real, nueva, probable, ninguna (R2, R3, R10, R49)

**Cuándo hay hueco**: solo si el tramo tiene `platform_expected` (lo decide
el servidor, `BoardLegV1`); nunca por una expresión sobre `line_mode` como B
(ajuste A6). Sin vía ni previsión → **nada, ni hueco** (R2).

| Estado | Forma | Palabra | Tokens | Movimiento |
|---|---|---|---|---|
| **Real** | caja **sólida** amarilla, radio 10, relleno 4 × 9, canto 1 pt | «Vía» (`label`) + número (`.numberFont(.via)`) | `via`, `viaInk`, `viaEdge` | — |
| **Real nueva** (`platform_new`, 25 s) | igual | igual | igual + halo `viaGlow` | aparece con `.transition(.scale(scale: 0.3).combined(with: .opacity))` y muelle 0,7 s; late 5 veces (`.viaPulse(isActive:)`); háptica `.platformPublished`. Con «Reducir movimiento»: aparece con fundido y queda un **anillo fijo** de 2 pt mientras sea nueva |
| **Probable** (`guess`, solo sin real) | **recuadro punteado** (1,5 pt, guion [4, 3]), sin relleno | «probable» + número + «90 %» | color del texto de donde esté (`ticketInk` en el billete, `ink2` en fichas) | — |
| **Probable compacta** (fichas) | recuadro punteado | «probable» + número (el % se va a VoiceOver y al detalle) | ídem | — |
| **Ninguna** | nada | — | — | — |

- La probable **nunca** lleva «Vía» ni relleno, y la real nunca va punteada:
  se distinguen en gris y en los widgets monocromos (R10).
- Si el ancho no da (billete con destino largo), `ViewThatFits` quita primero
  el porcentaje de la probable; nunca la palabra.
- La explicación (R49) va en el detalle del tramo: «Sale por la 21 el 90 %
  de las veces (20 observaciones, por el número de tren).»
- VoiceOver: «Vía 21» / «Acaba de salir la vía 21» / «Vía 21 probable, 90 por
  ciento sobre 20 observaciones, por el número de tren».

### 7.5 Distintivo de línea (R12)

`LineBadge(code:color:textColor:size:)` (LineColor.swift):

- Caja de lado `size` (42 cabecera, 30 listas, 25 cadenas), radio 30 % del
  lado, **crece a lo ancho** con códigos largos («6424») en vez de encoger la
  letra (B).
- Código en SF Pro Rounded **black** al 50 % del lado (44 % con 3
  caracteres, 38 % con 4+), `lineLimit(1)`.
- Fondo = color de línea; tinta = `LineColor.badge(line:officialText:)`
  (oficial si ≥ 4,5:1, si no negro/blanco con más contraste).
- Filete oscuro de 2 pt abajo (B: `inset 0 -2px 0 / .15`).
- Escala con Dynamic Type hasta 1,4× (`@ScaledMetric`).
- «Aumentar contraste»: canto `rule` de 1 pt.
- Sin código: «?». Sin color válido: gris `#6B7380` con tinta calculada.
- VoiceOver: «Línea J» (un elemento).

### 7.6 Ritmo «¿corro o no corro?» (R16)

Cápsula pequeña (`label`), solo en el billete:

| Minutos | Texto | Fondo | Texto |
|---|---|---|---|
| ≤ 3 o «ya» | «Corre» | `bad` | `onAccent` |
| ≤ 8 | «Anda» | `pace` (gris con alfa) | `ticketInk` |
| > 8 | «Con calma» | `pace` | `ticketInk` |
| En andén | — | — | — |

B no lleva icono; se puede añadir `figure.run` / `figure.walk` /
`cup.and.saucer` (los de `Pace.symbol`) si cabe. `Pace.color` de
Format.swift pasa a estos tokens en la FASE 3.

### 7.7 Aviso de línea (R8, R27, R28)

Dentro de la tarjeta de su tramo, encima del billete. Radio 18, relleno
10 × 12.

| Estado | Fondo | Cabecera | Mensajes |
|---|---|---|---|
| Perturbada (nivel 1) | `noticeWarn` | `exclamationmark.triangle.fill` en `warn` + «Perturbada» (`noticeTitle`, `warnText`) | `callout` en `ink` |
| Interrumpida (nivel 2) | `noticeBad` | `xmark.octagon.fill` en `badText` + «Interrumpida» en `badText` | ídem |
| Traduciendo | igual | + a la derecha «traduciendo» (`label`, `ink3`) con `Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative)` (quieto con «Reducir movimiento») | el **francés**, en cursiva `ink2`, con `languageIdentifier = "fr"` para que VoiceOver lo lea en francés |
| Traducido | igual | sin «traduciendo» | el español; el cambio con `.contentTransition(.opacity)` |
| Avisos sin leer (`disruptions_ok` = false) | `surfaceHi` | `exclamationmark.bubble` en `ink2` | «No se han podido leer los avisos: el «normal» de las líneas no es seguro.» |

- En la tarjeta caben **2 mensajes** (R27); el resto y los dos idiomas, en
  el detalle.
- Obras con fecha futura (`planned` > 0) no encienden el aviso (R28); se
  dicen en el detalle **aunque la línea esté normal** (en la v1 no salía).
- Nunca se espera a la traducción (R8).
- Háptica `.disruption` / `.interruption` cuando el nivel **sube** (no en
  cada refresco).

### 7.8 Tarjeta de tramo

`cardBackground()` (opaca, radio 30, relleno 12). Cabecera: distintivo 42 +
«Gare Saint-Lazare → Argenteuil» (`legTitle`, la flecha en `ink3`) + debajo
«dirección Ermont - Eaubonne» (`legSubtitle`, `ink3`), o «todos los
sentidos» si no hay `directions` y se mezclan destinos (R24). Luego aviso,
billete y fichas. Tocarla abre el detalle (7.13).

| Estado | Qué se ve |
|---|---|
| Normal | cabecera + aviso (si hay) + billete + fichas |
| Sin salidas, línea interrumpida | recuadro `surfaceHi` radio 18 con `nosign` (`badText`) + «Sin circulación» + «no hay más salidas» (R25) |
| Sin salidas, línea normal | `moon.zzz` (`ink3`) + «Servicio finalizado» + «no hay más salidas» (R25) |
| Estación caída, había salidas | se **conservan** las últimas salidas buenas del tramo con su antigüedad («salidas de hace 3 min», `ink3`) y el estado nuevo de la línea (decisiones, notas FASE 1) |
| Estación caída, sin nada | «No llega el dato de esta estación» + el error; los demás tramos siguen (R26) |

B enseñaba «Sin próximos pasos / nada anunciado ahora mismo»: se cambia a
los textos de R25. El vacío **no** va punteado: el punteado es de «probable».

### 7.9 Píldora de estado y barra de refresco (R9, R17–R19, R46, R54)

Cápsula de cristal (`.cristal(.bar, in: Capsule())`), `status` en `ink2`,
encima del borde del degradado. B la dejaba sin fondo sobre el mapa.

| Estado | Icono | Texto | Estilo |
|---|---|---|---|
| En directo | punto `okText` 9 pt con onda (2 s, sutil) | «en directo · hace 6 s» | cristal |
| Degradado (`server.degraded`) | `tortoise` `ink3` | «ahorrando cuota · cada 2 min · hace 40 s» | cristal |
| Dato viejo (R19) | `clock.badge.exclamationmark` `warnText` | «dato viejo · hace 4 min» | **opaco** `surface` con canto `warn` |
| Sin conexión (fallo de red) | `wifi.slash` `badText` | «sin conexión · último tablero hace 4 min» | opaco |
| Servidor responde con error | `exclamationmark.icloud` `badText` | según `error.code`: «PRIM no responde», «la clave de PRIM no vale», «se acabó la cuota de hoy · vuelve a las 02:00» | opaco |
| Servidor sin clave (`prim_key_missing`) | `key.fill` `badText` | «el servidor no tiene clave de PRIM · ponla en el panel» | opaco |

- La antigüedad cuenta desde que llegó al teléfono + `data_age` (R17) y se
  dice «hace N s / min / h» (R18, `Fmt.age`). Se recalcula cada 5 s con
  `TimelineView(.periodic(from: .now, by: 5))`.
- **Barra del próximo refresco** (R54): 2 pt en el borde inferior de la
  píldora, `ProgressView(timerInterval: ultimo...siguiente, countsDown:
  false)` con estilo lineal y tinte `ink3` (la anima el sistema, sin latir a
  60 fps). Con «Reducir movimiento», llena y quieta.
- El **amarillo no se usa aquí** (B lo usaba para «Sin conexión»: ajuste A4).
- VoiceOver: «Dato de hace 10 segundos, en directo» / «Sin conexión. Último
  tablero de hace 4 minutos».

### 7.10 Barras y botones de cristal

- **Cabecera del tablero**: 7.1. Alto mínimo 64, radio 30.
- **Barra superior del mapa**: botón atrás (`chevron.backward`), píldora de
  ruta (cápsula de cristal de 44 de alto: distintivo 25 + «Saint-Lazare →
  Argenteuil» en `bodyStrong`), y a la derecha `MapUserLocationButton()`.
  Todo dentro de un `CristalGroup`.
- **Botón redondo de cristal**: `.cristalButton(circle: true)`, 44 × 44,
  icono SF de 22 pt, `accessibilityLabel` siempre (los iconos solos no
  hablan). Pulsado: 0,88 con muelle (B), o atenuado con «Reducir movimiento».
- **Botón de texto de cristal** («Guardar» en la barra de B): en nativo es un
  `ToolbarItem` con `Button("Guardar")` y el sistema lo pinta de cristal
  (iOS 26) en `accent`.

### 7.11 Barra de pestañas

La del sistema (`TabView`); en iOS 26 flota en cristal sola.

| Pestaña | Símbolo | Pantalla |
|---|---|---|
| Tablero | `clock` | tablero |
| Trayecto | `map` | mapa / modo trayecto |
| Rutas | `point.topleft.down.to.point.bottomright.curvepath` | rutas |
| Historial | `chart.bar` | estadísticas |
| Buscar | `magnifyingglass` | planificador |

- iOS 18+: `Tab(value:)` y la de Buscar con `Tab(role: .search)`, que iOS 26
  separa en su círculo (como B). iOS 17: cinco `.tabItem`.
- Etiquetas siempre (B las quitaba con letra grande).
- Háptica `.selection` al cambiar; el bucle de 30 s se para fuera de Tablero
  y Trayecto (R7).

### 7.12 Botones

| Tipo | Cómo | Estados |
|---|---|---|
| Principal | `.filledButton(.primary)`: cápsula `accentFill`, 50 pt, texto `onAccent` `button`, sombra `filled` | normal, pulsado (0,95 con muelle / 0,7 de opacidad), desactivado (0,45), cargando (`ProgressView` en lugar del icono, etiqueta igual) |
| Peligro | `.filledButton(.danger)`: relleno `bad` | ídem |
| Cristal | `.cristalButton()` | ídem |
| Texto | `Button` normal con `.tint(Palette.accent)`; destructivo con `role: .destructive` (`badText`) | — |
| Pequeño | `buttonSmall`, alto visual 36, **área táctil 44** con `.hitTarget()` (B: 36 sin más) | — |

### 7.13 Hojas

Del sistema: `.sheet` + `.presentationDetents([.medium, .large])` +
`.presentationDragIndicator(.visible)`. En iOS 26 son de cristal solas; el
contenido que lleva minutos va en billetes opacos igualmente.

- **Detalle del tramo** (no está en B; F24): distintivo 50, parada, «modo ·
  dirección»; avisos en español y francés (R27) y nota de obras (R28); lista
  de salidas con momento, ritmo con texto («corriendo», «andando», «con
  calma»), vía con su explicación si es probable (R49) y etiquetas (destino,
  «sale 12:56», retraso, longitud, «tren 137412», «parado en el andén»).
- **Alternativas** (R29, R30): banner `bad` con «Línea 14 interrumpida · tu
  ruta tarda 47 min cuando funciona»; opciones en tarjetas opacas con minutos
  totales (`stat`, «1h02» si ≥ 60), diferencia «+12 min» (`warnText`) o
  «igual de rápido», «12:55 → 13:54» (de la hora cruda de Navitia), cadena de
  distintivos con el estado de cada tramo, «1 transbordo»; la que no sirve,
  a 0,55 con «No sirve: pasa por la línea cortada» (`badText`). Sin opciones:
  «El calculador no encuentra otro camino ahora mismo» y **«Buscar de todas
  formas»** (`force`). **Sin «Usar hoy»**: no hay API para eso (ajuste A13).
- **Ajustes**, **guardar ruta desde el planificador**, **buscar sitio**:
  hojas grandes con `NavigationStack` dentro.

### 7.14 Tarjeta del modo trayecto (mapa)

Panel de cristal abajo (`.cristal(.panel)`, radio 30, relleno 12), dentro de
un `CristalGroup`:

- «4 min a pie hasta Saint-Lazare» (`figure.walk` + `callout` `ink2`; los
  minutos de `MKDirections`, no de la API).
- El billete del tramo que toca (opaco, 7.2).
- «Iniciar trayecto» (`.filledButton(.primary)`, `play.fill`) ↔ «Parar
  trayecto» (`.filledButton(.danger)`, `stop.fill`), con morph
  (`.cristalID`) y háptica `.tripStart` / `.tripStop`.
- Pie en trayecto: «sigue en segundo plano · se apaga al llegar» (`footnote`
  `ink3`).

### 7.15 Listas y formularios

- **Rutas** (tarjetas opacas): cadena de distintivos unidos por un filete de
  12 × 2 (`ink3`), etiqueta «ahora» (cápsula `accentFill`, `label` blanco)
  en la `active_id`, nombre (`legTitle`), «origen → destino» (`callout`
  `ink2`, dos líneas), «entre semana · llego 09:00» (`footnote` `ink3`; las
  etiquetas de R35 y R36, no las de B). La activa, con canto interior de 2 pt
  `accent`. Menú contextual «Ver en el tablero» / «Borrar».
- **Editor**: `Form` con `.scrollContentBackground(.hidden)` sobre `bg` y
  filas en `surface`. Días: siete botones redondos **de 44 pt** (B: 38),
  `accentFill` si están, con el nombre del día para VoiceOver. «Cuándo
  toca»: `Picker(.segmented)` con «Llego a / Salgo a / Franja» y
  `DatePicker(.hourAndMinute)`. Tramo sin sentido: «todos los sentidos» en
  `warnText` con `exclamationmark.triangle` (R32). «Añadir tramo» de cristal;
  «Eliminar ruta» destructivo.
- **Ajustes**: `List` agrupada sobre `bg`: servidor (direcciones editables
  que se guardan al escribir, R61, «Restablecer», «Emparejar de nuevo»),
  estado (conectado por, versión, clave PRIM: «configurada / falta / no
  vale» con su color), cuota por endpoint («Tablero», «Avisos», «Buscador»:
  `ProgressView(value: used, total: cap)` con tinte por nivel ok/warn/critical
  → `okText`/`warnText`/`badText`; pie «se reinicia a medianoche UTC», R46),
  traductor, modo trayecto, permisos, versión.
- **Planificador**: campos «Desde / Hasta» que abren la búsqueda
  (350 ms, 2 caracteres, R31); «Llegar a / Salir a» + hora (R34);
  resultados en tarjetas como las alternativas, con «Guardar ruta».

### 7.16 Estadísticas

- Tres fichas (`tile`, radio 22) con cifra `stat` y rótulo `footnote`:
  «consultas» (`overall.n`), «retraso medio» con **coma decimal** («3,4
  min», R56), «retraso máximo» (`overall.max_delay`). B ponía «días con
  datos» y «peor día»: los datos no dicen eso (ajuste A14).
- Días con incidencias por mes: barras (Swift Charts `BarMark` o barras
  propias de 10 pt, radio 5, `accent`) con «agosto 2026» (mes completo, R56)
  y «11/21»; crecen con muelle 0,8 s al aparecer (nada con «Reducir
  movimiento»).
- La línea que más falla: distintivo + «N veces la peor» (`by_line.n` son
  filas del historial, no días) + retraso medio.
- Previsión de vía: «84 %» (`statBig`, **espacio fino no separable**: en B se
  partía en dos líneas), «179 aciertos de 214», «4820 trenes en 26 días · el
  servidor se puntúa solo» (R11), cobertura por tramo («no publica vía» en
  metro/bus/tranvía).

### 7.17 Emparejamiento

Pantalla siempre oscura (fondo radial de B: `oklch(30% 0.03 255)` →
`oklch(10% 0.01 255)`), cámara a pantalla completa y marco de 240 pt radio
40, trazo 3 pt blanco al 50 %.

| Estado | Marco | Panel de cristal (`.panel`) |
|---|---|---|
| Buscando | respira (escala 1 ↔ 1,05, 1,2 s) | «Enfoca el QR del panel del servidor.» + «Escribir la dirección a mano» |
| Encontrado / conectando | escala 0,85 con muelle, trazo `okText` | «Conectando con el servidor…» + `ProgressView` |
| Listo | — | `checkmark` + «Listo. iPhone de Isma emparejado.» + háptica `.paired`; pasa al tablero |
| Código caducado / usado / malo | vuelve a buscar | «Ese código ya no vale: genera otro en el panel.» (el servidor no distingue los tres, R86) |
| Demasiados intentos | — | «Demasiados intentos. Prueba dentro de N min.» (`retry_after`) |
| No llega al servidor | — | «No encuentro el servidor en esas direcciones.» + «Escribir a mano» |
| Sin permiso de cámara | sin cámara | «Trajet necesita la cámara para leer el QR.» + «Abrir Ajustes» + «Escribir a mano» |

Con «Reducir movimiento»: el marco no respira ni se encoge; cambia de color.

### 7.18 Estados vacío, carga, error y avisos efímeros (R53, R55)

| Estado | Cuándo | Qué se ve |
|---|---|---|
| Carga | primera vez, sin nada en disco | esqueleto: la forma de 2 tarjetas en `surfaceHi` con `.redacted(reason: .placeholder)`; **sin parpadeo** con «Reducir movimiento» (la v1 parpadeaba siempre) |
| Vacío | `empty: true` | icono + «Todavía no hay ninguna ruta» + «Ve a Buscar, di de dónde a dónde vas y guarda el trayecto que uses de verdad» + botón principal «Buscar un trayecto» |
| Error sin caché | falla y no hay nada guardado | «No se llega al servidor» + «Ni por la red de casa ni por Tailscale.» + «Reintentar». Es el **único** caso de pantalla sin tablero |
| Servidor sin clave, sin caché | `prim_key_missing` | `key.fill` + «El servidor no tiene clave de PRIM» + «Ábrela en el panel del servidor (Ajustes › Panel)». Con caché: el tablero guardado + la píldora de 7.9 |
| Ruta borrada | 404 de la ruta fijada (R44) | aviso efímero «Esa ruta ya no existe» y vuelta a la que toca |
| Sin emparejar | no hay token | la pantalla de emparejar |
| Aviso efímero | «Ruta guardada», «Ruta borrada»… | cápsula de cristal encima de la barra de pestañas, 2,4 s, entra con muelle desde abajo (fundido con «Reducir movimiento»), se anuncia a VoiceOver con `AccessibilityNotification.Announcement`. Nunca un diálogo (R55) |

---

## 8. Iconos (SF Symbols)

Los iconos de B son trazos SVG que imitan SF Symbols. Equivalencias: reloj
`clock`, mapa `map`, rutas
`point.topleft.down.to.point.bottomright.curvepath`, buscar
`magnifyingglass`, historial `chart.bar`, ajustes `gearshape`, atrás
`chevron.backward`, entrar `chevron.forward`, quitar `xmark`, añadir `plus`,
aviso `exclamationmark.triangle.fill`, centrar `location`, parar `stop.fill`,
empezar `play.fill`, tren `train.side.front.car`, bus `bus.fill`, metro
`tram.fill.tunnel`, tranvía `tram.fill`, QR `qrcode.viewfinder`, sin red
`wifi.slash`, hecho `checkmark`, alternativa `arrow.triangle.swap`, servidor
`server.rack`, traductor `brain`, iPhone `iphone`, longitud
`rectangle.split.2x1` / `rectangle`, a pie `figure.walk`, correr
`figure.run`, calma `cup.and.saucer`.

Tamaño con la letra de al lado (`.imageScale` o la fuente del nivel); con
`symbolRenderingMode(.hierarchical)` en los de estado. Efectos: ver §9.

---

## 9. Movimiento

### 9.1 Curvas

- **Muelle de B** `cubic-bezier(.34, 1.45, .64, 1)` → sobrepasa un 6,6 % →
  `Animation.spring(response: d, dampingFraction: 0.65)` (≈ `.bouncy`, que es
  bounce 0,3; con `extraBounce: 0.05` queda igual). `Motion.spring(_:)`.
- **Ease de B** `cubic-bezier(.2, .8, .2, 1)` →
  `Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: d)`, exacta.
  `Motion.ease(_:)`.
- **Dibujo del trazado**: ease-out cúbica → `timingCurve(0.33, 1, 0.68, 1,
  duration: 1.5)`.

### 9.2 Catálogo

<!-- generado:movimiento -->
| Id | En B | SwiftUI | iOS 17 | Con «Reducir movimiento» |
|---|---|---|---|---|
| `press` | glass-btn:active scale .88 · .35s spring | `.spring(response: 0.35, dampingFraction: 0.65)` | .bouncy(duration: 0.35, extraBounce: 0.05) | sin escala: .easeOut(duration: 0.15) de opacidad 0,7 |
| `pressButton` | btn:active scale .95 · .4s spring | `.spring(response: 0.4, dampingFraction: 0.65)` | .bouncy(duration: 0.4, extraBounce: 0.05) | opacidad 0,7, sin escala |
| `numberSwap` | num-swap pop .5s spring (escala .6→1) | `.contentTransition(.numericText(countsDown: true)) + .spring(response: 0.5, dampingFraction: 0.65)` | igual | .contentTransition(.opacity) + .easeInOut(duration: 0.2) |
| `viaAppear` | via-pop .7s spring (escala .3→1) | `.transition(.scale(scale: 0.3).combined(with: .opacity)) + .spring(response: 0.7, dampingFraction: 0.65)` | igual | .transition(.opacity) 0,2 s |
| `viaPulse` | via-glow 1.6s ease-in-out ×5, retraso .5s | `halo (sombra amarilla + anillo 6 pt) que late 5 veces: .easeInOut(duration: 0.8) ida y vuelta, desde 0,5 s` | igual | anillo estático de 2 pt mientras dure «nueva» (25 s); sin latido |
| `screenPush` | b-in .5s spring / b-out .5s ease | `NavigationStack nativo (no se reimplementa); zoom de iOS 18: .navigationTransition(.zoom(sourceID:in:))` | push nativo | lo decide el sistema (fundido) |
| `sheet` | b-sheet .55s spring, fondo b-shrink | `.sheet con .presentationDetents; el sistema anima y encoge el fondo` | igual | sistema |
| `morph` | botón «Iniciar trayecto» → hoja del mapa | `GlassEffectContainer + .glassEffectID (iOS 26); iOS 17–25: matchedGeometryEffect` | matchedGeometryEffect(id:in:) con .spring(response: 0.5, dampingFraction: 0.65) | fundido .easeInOut(duration: 0.2) |
| `live` | ripple 2s ease infinito | `punto verde + onda que crece (escala 1→2,1, opacidad .6→0) en 2 s, repetida` | phaseAnimator o .repeatForever(autoreverses: false) | punto fijo, sin onda |
| `translating` | bounce 1s spring infinito (3 puntos con retraso .15s) | `Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative)` | igual (iOS 17) | puntos quietos (isActive: false) |
| `barGrow` | grow .8s spring (scaleX 0→1) | `.spring(response: 0.8, dampingFraction: 0.65) sobre el ancho al aparecer` | igual | sin animación |
| `routeDraw` | dibujo de la línea 1.5s ease-out cúbica | `.timingCurve(0.33, 1, 0.68, 1, duration: 1.5) sobre el progreso del trazado` | MapPolyline con los puntos hasta el progreso, en TimelineView(.animation) | trazado entero de golpe |
| `refreshBar` | (no está en B; R54) | `barra de 2 pt que se llena lineal hasta el siguiente refresco: TimelineView(.periodic(from:by: 1)) o .linear(duration: resto)` | igual | se enseña el resto en texto («próximo en 12 s»), sin barra que se mueve |
| `pairScan` | breathe 1.2s alternate; encontrado: escala .85 en .6s spring | `.easeInOut(duration: 1.2).repeatForever(autoreverses: true) sobre la escala del marco; al encontrar .spring(response: 0.6, dampingFraction: 0.65)` | igual | marco quieto; al encontrar, cambio de color sin escala |
| `staleDim` | (no está en B; R19) | `.easeInOut(duration: 0.45) sobre opacidad y saturación del tablero` | igual | sin animación |
| `ease` | cubic-bezier(.2,.8,.2,1) | `.timingCurve(0.2, 0.8, 0.2, 1, duration: d) — traducción exacta` | igual (iOS 13+) | — |

Curva «spring» de B `cubic-bezier(.34, 1.45, .64, 1)`: pico 1,066 → sobrepaso 6,6 % → **dampingFraction 0,65** (bounce 0,35). Sale de ζ = −ln(s) / √(π² + ln²(s)), con s el sobrepaso: la fórmula del oscilador subamortiguado. La duración CSS se toma como `response` (la «duración perceptiva» de Apple).
<!-- /generado:movimiento -->

Tiempos en `Motion.Timing` (y en `tokens.json`, `movimiento.duraciones`):
vía nueva «nueva» durante 25 s; latido 0,8 s ida + 0,8 vuelta × 5 tras 0,5 s;
un «ya» sigue en pantalla 45 s; aviso efímero 2,4 s; tablero apagado 0,45 s.

### 9.3 Transiciones nativas

- **`contentTransition(.numericText(countsDown: true))`** en minutos, cuentas
  y cifras de estadísticas (`.minutesTransition(value:)`).
- **Morph de cristal**: `CristalGroup` + `.cristalID(_:in:)` (iOS 26:
  `GlassEffectContainer` + `glassEffectID`; antes `matchedGeometryEffect`).
- **Tarjeta de ruta → detalle** y **tablero → mapa**: en iOS 18+
  `.matchedTransitionSource(id:in:)` en el origen y
  `.navigationTransition(.zoom(sourceID:in:))` en el destino (el zoom del
  sistema, que respeta «Reducir movimiento» solo); en iOS 17, el push normal.
  `matchedGeometryEffect` no cruza un `NavigationStack`: no se usa para eso.
- **Salidas que pasan**: identidad por `jid` y `.transition(.push(from:
  .trailing))` (iOS 17) con muelle; el resto de la tira se desplaza sola.
- **Pestañas, pushes y hojas**: los del sistema. B imitaba el push con
  escala 0,96 y desplazamiento de 60 px; no se reimplementa.

### 9.4 `symbolEffect`

| Dónde | Efecto | Con «Reducir movimiento» |
|---|---|---|
| «traduciendo» | `Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, isActive: !reduceMotion)` | quieto |
| icono de aviso al subir de nivel | `.symbolEffect(.bounce, value: level)` | sin efecto |
| «Iniciar / Parar trayecto» | `.contentTransition(.symbolEffect(.replace))` entre `play.fill` y `stop.fill` | fundido |
| sin conexión | `wifi.slash` fijo (nada de latidos con un problema) | — |

### 9.5 Hápticas (`Haptic`, `.haptic(_:trigger:)`)

| Momento | `SensoryFeedback` | Cuándo exactamente |
|---|---|---|
| Vía publicada | `.impact(weight: .heavy)` | `platform_new` pasa a cierto en la primera salida de un tramo (una vez por viaje; ajuste de Ajustes «Vibrar cuando aparece la vía») |
| Tren a 2 min | `.warning` | la primera salida del primer tramo cruza 2 min hacia abajo |
| Perturbación / interrupción | `.warning` / `.error` | el nivel de la línea **sube** |
| Cambio de pestaña o selección | `.selection` | — |
| Empieza / termina el trayecto | `.start` / `.stop` | — |
| Emparejado | `.success` | — |

Nunca con el dato viejo ni en cada refresco. «Reducir movimiento» no las
quita.

### 9.6 «Reducir movimiento» (R51)

Regla general: lo que se mueve para llamar la atención se sustituye por una
**forma** fija (anillo de la vía nueva) o desaparece (ondas, latidos,
respiraciones); lo que se mueve para explicar un cambio se sustituye por un
**fundido** de 0,2 s. `Motion.animation(_:reduceMotion:)`,
`.motion(_:value:)`, `.minutesTransition(value:)`, `.viaPulse(isActive:)` y
`withMotion(_:reduceMotion:_:)` ya lo hacen; las vistas no tienen que mirar
la preferencia salvo para quitar efectos de símbolo (`isActive:`).

---

## 10. De B a SwiftUI, pieza a pieza

| Pieza de B | SwiftUI | Disponibilidad |
|---|---|---|
| `.glass` (barras) | `.cristal(.bar)` → `glassEffect(_:in:)` / `.ultraThinMaterial` / opaco | `#available(iOS 26.0, *)` dentro |
| `.card` translúcida | `.cardBackground()` **opaca** | iOS 17 |
| `.glass-btn` | `Button { } label: { Image(systemName:) }.cristalButton(circle: true)` | iOS 26 `.glass`; antes estilo propio |
| `.btn-primary` / `.btn-danger` | `.filledButton(.primary / .danger)` | iOS 17 |
| `.tabbar` flotante + `.tab-search` | `TabView` + `Tab(role: .search)` | iOS 18 (`Tab`); iOS 17 `.tabItem` |
| `.navbar` + `.glass-title` | `NavigationStack` + `.navigationTitle` + `ToolbarItem` | sistema |
| `.sheet-scr` | `.sheet` + `.presentationDetents` | iOS 16 |
| `.ticket` | vista `Ticket` (FASE 3): `HStack` + `AnyLayout` para AX | iOS 16 (`AnyLayout`) |
| `.num` + `num-swap` | `.numberFont(_:)` + `.minutesTransition(value:)` | iOS 17 |
| `.chips` | `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)` | iOS 17 |
| `.via-real` + `is-new` | caja + `.transition(.scale(0.3).combined(with: .opacity))` + `.viaPulse(isActive:)` + `.haptic(.platformPublished, trigger:)` | iOS 17 |
| `.via-guess` | `RoundedRectangle(...).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))` | iOS 13 |
| `.badge` | `LineBadge` | iOS 17 |
| `.live` (onda) | `Circle` + `phaseAnimator` o `.repeatForever(autoreverses: false)` de escala y opacidad | iOS 17 |
| `.translating` | `Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative)` | iOS 17 |
| `.status.is-stale` (amarillo) | píldora opaca con canto `warn` (7.9) + tablero `.opacity(0.55).saturation(0.2)` | iOS 17 |
| `.notice` | vista `Notice` (FASE 3), 7.7 | iOS 17 |
| `.board-map` + `.board-fade` | `Map` no interactivo + `LinearGradient(colors: [.clear, Palette.bg])` | iOS 17 (`Map` con `MapContentBuilder`) |
| trazado animado (map.js) | `MapPolyline` con los puntos hasta el progreso, `TimelineView(.animation)` durante 1,5 s | iOS 17 |
| `.map-me` | `UserAnnotation()` | iOS 17 |
| `.pill-route` | `HStack { LineBadge; Text }.cristal(.bar, in: Capsule())` | iOS 17 |
| `.map-card` | `.cristal(.panel)` en `CristalGroup` | iOS 26 dentro |
| `.affected` | tarjeta con relleno `bad`, texto `onAccent` | iOS 17 |
| `.bar-track` (estadísticas) | Swift Charts `BarMark` o `Capsule` con ancho animado | iOS 16 (Charts) |
| `.quota` | `ProgressView(value:total:)` con tinte por nivel | iOS 14 |
| `.sw` (interruptor) | `Toggle` (tinte `accent`; B lo pintaba verde, el sistema usa el tinte) | sistema |
| `.seg` | `Picker(...).pickerStyle(.segmented)` | sistema |
| `.days` | 7 `Button` redondos de 44 pt | iOS 17 |
| `.pair-ring` | `RoundedRectangle(cornerRadius: 40).stroke` con escala animada | iOS 17 |
| `.pair-sheet` | `.cristal(.panel)` | iOS 26 dentro |
| `html[data-large-text]` | `@Environment(\.dynamicTypeSize)` + `isAccessibilitySize` | iOS 15 |
| `html[data-reduce-motion]` | `@Environment(\.accessibilityReduceMotion)` (y las ayudas de Motion.swift) | iOS 13 |
| `html[data-theme]` | `@Environment(\.colorScheme)`; la app sigue al sistema (la v1 forzaba oscuro) | — |

### 10.1 La capa `Trajet/Design/`

| Fichero | Qué tiene |
|---|---|
| `Tokens.swift` | `RGBA`, `DynamicColor` (claro/oscuro/HC con `UIColor(dynamicProvider:)`), `Tokens` (crudos, generados) y `Palette` (un `Color` por token, generado) |
| `Typography.swift` | `TextLevel`, `NumberLevel`, `BoardDensity`, `DepartureMoment.numberScale`, `.textLevel(_:)`, `.numberFont(_:scale:)` |
| `Metrics.swift` | `Metrics.Space`, `.Radius` (con `concentric`), `.Size`, `.Opacity`, `.Shadow`; `.hitTarget()`, `.trajetShadow(_:)`, `.cardBackground()` |
| `Motion.swift` | `Motion` (muelles, curvas, `Timing`, `Kind`, alternativas), `.motion(_:value:)`, `.minutesTransition(value:)`, `.viaPulse(isActive:)`, `withMotion`, `Haptic` + `.haptic(_:trigger:)` |
| `Glass.swift` | `CristalRole`, `.cristal(...)`, `CristalGroup`, `.cristalID`, `.cristalButton(prominent:circle:)`, `CristalFallbackButtonStyle`, `FilledButtonStyle` + `.filledButton(_:)` |
| `LineColor.swift` | `LineColor` (parseo tolerante, `badge(line:officialText:)`, `ink(on:official:)`), `LineRGB`, `BadgeColors`, `LineBadge` |
| `Format.swift` | se conserva tal cual: `Fmt`, `Pace`, `DepartureMoment` (reglas de formato) |
| `Theme.swift` | **fachada temporal**: los nombres de la v1 (`Palette.background`, `inkMuted`, `TypeScale`, `cardSurface`…) redirigidos a los tokens y marcados `deprecated`. **Se borra en la FASE 3** cuando no quede ninguna vista vieja y `Pace.color` use los tokens nuevos |

Requisitos que cumple: Swift 6 con concurrencia estricta (tipos `Sendable`,
nada de estado global mutable: solo `static let` de tipos `Sendable` y
propiedades calculadas), iOS 17 mínimo, todo lo de iOS 26 tras
`if #available(iOS 26.0, *)`, sin dependencias. **Ojo**: `project.yml` sigue
con `deploymentTarget` 26.0, `SWIFT_VERSION` 5.0 y concurrencia `minimal`;
la FASE 3 tiene que ponerlo a 17.0, 6.0 y `complete`.

Para la extensión de widgets y la Live Activity (FASE 3): compartir
`Tokens.swift`, `Typography.swift`, `Metrics.swift`, `LineColor.swift` y
`Format.swift`; no `Glass.swift` ni `Motion.swift` (WidgetKit tiene su
propio fondo y sus propias animaciones).

### 10.2 Puntos que no se han podido compilar (TODO-COMPILAR)

No hay Mac en este PC. El código se ha escrito con APIs conocidas y
conservadoras; donde la firma exacta de una API de iOS 26 es una suposición,
hay un comentario `TODO-COMPILAR` con la alternativa segura:

1. `glassEffect(_:in:)`, `Glass.regular.tint(_:).interactive()` (Glass.swift).
2. `GlassEffectContainer(spacing:content:)` (Glass.swift, `CristalGroup`).
3. `glassEffectID(_:in:)` (Glass.swift, `cristalID`): si falla, queda solo
   `matchedGeometryEffect`.
4. `.buttonStyle(.glass)` / `.glassProminent` (Glass.swift).
5. Aislamiento de `UIColor(dynamicProvider:)` y `UITraitCollection` en Swift
   6 (Tokens.swift): si el compilador se queja, alternativa: colorsets en el
   catálogo (el script ya los sabe escribir).

---

## 11. Accesibilidad (lista de comprobación)

- [ ] Contraste: el script pasa (`--check` en CI); capturas en gris para R10.
- [ ] Dynamic Type: capturas con XXXL y AX3; billete a dos filas en AX; nada
      cortado a mitad de palabra en destinos.
- [ ] VoiceOver: cada salida es una frase (R50); distintivo «Línea J»;
      botones de icono con etiqueta; avisos en francés con idioma francés.
- [ ] 44 pt en todo lo que se toca (R52), también botones pequeños y días.
- [ ] «Reducir movimiento»: sin latidos, ondas, respiraciones ni barras que
      corren; la vía nueva con anillo fijo (R51).
- [ ] «Reducir transparencia»: cristal opaco en todas partes.
- [ ] «Aumentar contraste»: tokens HC, cantos visibles.
- [ ] Negrita (`legibilityWeight == .bold`): las cifras ya son heavy; el
      texto lo engorda el sistema.
- [ ] Modo claro y oscuro siguiendo al sistema.

---

## 12. Live Activity y widgets

Componentes de la variante elegida en la FASE 2B, **A «Billete»**
(`docs/diseno/decisiones-la-widgets.md`: por qué, estados, límites de iOS y
enlaces). Laboratorio: `design-lab/b-cristal-v2/` (`?v=A`); capturas:
`design-lab/capturas/la-widgets/A/`. Usa los tokens de este documento; lo
propio de la extensión está en §12.2. Las medidas son pt de iOS (1 px del
laboratorio = 1 pt).

### 12.1 Idea y piezas

Una sola anatomía en todas las superficies: **la cifra** a la izquierda en un
**billete opaco** (`ticket`, el de §7.2), **la vía en la «matriz»** del billete
a la derecha, y **una** línea secundaria debajo. El cristal lo pone el sistema
(fondo de la actividad, widgets tintados); los datos nunca van sobre cristal.

| Pieza | Tamaño (iPhone 16) | Contenido |
|---|---|---|
| Live Activity de bloqueo | 371 × **150** (tope 160; 153 con Dynamic Type al tope) | cabecera (distintivo 22, destino, estado de la línea, antigüedad) · billete 56 pt · pie 32 pt (luego / transbordo / cancelado + «Parar») |
| Compacta | 52,33 + 52,33 (isla de 230) | leading: distintivo 22 (+ símbolo) · trailing: cifra 16 pt + caja de vía de 12 pt |
| Mínima | 36,67 (45 ovalada) | aro de 2,5 pt del color de la línea con la cifra y «min» |
| Expandida | 371 × 151–154 | leading: distintivo 24 y destino en una línea · trailing: cifra 38 + matriz de vía 38 × 38 · center: estado, tramo u hora · bottom: luego / transbordo / franja de vía + antigüedad y «Parar» |
| Widget pequeño | 158 × 158 | cabecera · billete (cifra 54) · vía o «luego» + antigüedad |
| Widget mediano | 338 × 158 | columna del pequeño (128) · «desde …», 2 filas con destino, antigüedad |
| Widget grande | 338 × 354 | ruta + antigüedad · un bloque por tramo (billete 56/50/42 + fichas) |
| Circular | 72 | arco (solo ≤ 30 min) · cifra 24 + «min» · línea y símbolo |
| Rectangular | 160 × 72 | línea + destino · cifra 27 + vía · antigüedad |
| En línea | 234 × 26 | «J · 6 min · Vía 21 · hace 5 min» (cae por el final) |

SE (375): actividad 353 de ancho [estimación], sin isla (la alerta sale como
banner); widgets 148 / 321 × 148 / 321 × 324. Pro Max (440): actividad y
expandida de 408, compacta de 62,33 por lado, widgets 170 / 364 × 170 / 364 × 382.

### 12.2 Tokens propios de la extensión

Los de §3.1 más el **apagado** (R19). No es opacidad: el billete pasa a un
gris **opaco** para que cifra y vía conserven el contraste; la caja de la vía
real sigue llena (forma, R10) pero sin amarillo.

| Token | Uso | Claro | Oscuro | Isla (siempre negra) |
|---|---|---|---|---|
| `ticketOff` | billete apagado | `oklch(42% 0.005 260)` → `#4B4D50` | `oklch(72% 0.004 260)` → `#A3A5A7` | — (la cifra va sin billete) |
| `ticketOffInk` | cifra apagada | `#FFFFFF` (**8,5:1**) | `oklch(12% 0 0)` → `#060606` (**8,2:1**) | `oklch(76% 0.003 260)` → `#B0B1B3` sobre negro (**9,8:1**) |
| `ticketOffInk2` | «min», hora, longitud apagadas | `oklch(90% 0.004 260)` → `#DCDEE1` (6,3:1) | `oklch(26% 0.005 260)` → `#232426` (6,3:1) | `ink2` de la isla |
| `viaOff` | caja de la vía real apagada | `oklch(84% 0.004 260)` → `#C9CACD` (5,2:1 contra el billete) | `oklch(36% 0.005 260)` → `#3C3D40` (4,4:1 contra el billete) | `#B0B1B3` |
| `viaOffInk` | número de la vía apagada | `#090B0F` (**12:1**) | `#FFFFFF` (**10,9:1**) | `#060606` (9,5:1) |
| `ringOff` | aro de la mínima apagada | — | — | `oklch(58% 0 0)` → `#7A7A7A` |
| con «Aumentar contraste» | billete apagado | `oklch(36% 0.005 260)` (10,9:1) | `oklch(78% 0.004 260)` (10,1:1) | = |

Contrastes medidos con las fórmulas de `design-lab/tools/tokens.mjs`. Vivo, la
cifra sobre el billete da 19,7:1 (claro) y 19,2:1 (oscuro); «En andén»,
`atStopInk` sobre `ok`, 7,9:1. Pasar estos tokens a `tokens.mjs` es trabajo de
la FASE 3 (van a `Trajet/Design/Tokens.swift`, que comparte la extensión).

### 12.3 Tipografía

| Texto | Talla (pt) | Estilo | Dynamic Type |
|---|---|---|---|
| Cifra del billete (actividad) | 44 («ya» 38, «1h46» 34, «En andén» 22) | SF Pro Rounded heavy, dígitos tabulares | fija |
| Cifra del widget pequeño / mediano | 54 / 50 | ídem | fija; con el texto del sistema, `minimumScaleFactor(0.7)` |
| Cifra de la expandida / compacta / mínima | 38 / 16 / 15 | ídem | fija (la isla tiene alto fijo) |
| «min» junto a la cifra | 15 (actividad), 16 (widget), 14 (expandida) | rounded heavy, `ticketInk2` | fija |
| Hora fija (caducada o ≥ 60 min en widgets) | 28 con «sale a las» a 11 | rounded heavy | fija |
| Vía: número | 26 matriz · 19 expandida · 20/16/14 chips m/s/xs · 12 mini | rounded black | fija |
| Vía: palabra («Vía», «probable», «prob.») | **12** en la Live Activity, **11** en widgets (R10, P1-7) | SF Pro 800 | fija |
| Destino de la cabecera | 16 (actividad), 15 (expandida), 14 (widgets) | 700 | `.dynamicTypeSize(...(.xLarge))` en la actividad y la isla; `...(.xxLarge)` en widgets |
| Línea secundaria, pie, antigüedad | 13 / 12 (11 la antigüedad del widget pequeño) | 600–700 | ídem |
| «Parar» | 14 | 700 | ídem |

### 12.4 El estado de la Live Activity (`ActivityAttributes`)

Solo campos de `/api/v1/board` (`BoardV1`, `BoardLegV1`, `Departure`,
`PlatformGuess`, `LineStatus`, `ServerState`) y lo que la app **deriva** de
ellos sin inventar (marcado «derivado»). ≈ 1,3 KB con 3 salidas [estimación];
tope de iOS, 4 KB.

```swift
struct TrajetActivityAttributes: ActivityAttributes {
    // Fijo durante todo el trayecto
    var routeID: Int                  // BoardRoute.id → widgetURL
    var routeName: String             // BoardRoute.name (estado final)

    struct ContentState: Codable, Hashable {
        var leg: Leg                  // el tramo que toca (lo decide la app: hora y geocercas)
        var next: Link?               // el tramo siguiente, si hay transbordo
        var legIndex: Int             // posición de `leg` en BoardV1.legs (derivado)
        var legCount: Int             // BoardV1.legs.count (derivado)
        var receivedAt: Date          // llegada del tablero al teléfono (R17, derivado)
        var dataAge: Double           // BoardV1.data_age
        var refreshHint: Int          // BoardV1.server.refresh_hint_s
        var connection: Connection    // .ok · .offline (fallo de red) · .noKey (ErrorV1 prim_key_missing) — derivado
        var ended: EndReason?         // .arrived · .maxDuration (solo en el estado final; derivado del modo trayecto)
        var endedAt: Date?            // cuándo terminó (solo en el estado final): «se quita sola a las …» (derivado)
    }
    struct Leg: Codable, Hashable {
        var seq: Int                  // BoardLegV1.seq
        var lineCode: String          // line_code
        var lineColor: String         // line_color (hex)
        var platformExpected: Bool    // platform_expected (R3)
        var toName: String            // to_name («Transbordo en …»)
        var direction: [String]       // abreviar(directions[0] o destination): variantes (derivado)
        var mixed: Bool               // directions vacío y destinos distintos (R24, derivado)
        var statusLevel: Int          // status.level
        var departures: [Dep]         // ≤ 3, en orden
    }
    struct Dep: Codable, Hashable {
        var jid: String               // Departure.jid (identidad, R23)
        var at: Date                  // Departure.at «HH:MM» en Europe/Paris → fecha (derivado)
        var minutes: Int              // Departure.minutes (control del redondeo)
        var destination: [String]     // abreviar(Departure.destination) (derivado)
        var platform: String?         // Departure.platform
        var platformNew: Bool         // Departure.platform_new
        var platformBefore: String?   // vía de la misma jid en el tablero anterior: cambio de vía (derivado)
        var guessPlatform: String?    // Departure.guess.platform
        var guessShare: Double?       // Departure.guess.share
        var delay: Int?               // Departure.delay, solo si aimed_at ≠ "" (R4, R14)
        var atStop: Bool              // Departure.at_stop (R15)
        var length: String?           // Departure.length (R5)
        var cancelled: Bool           // Departure.status == "cancelled" (derivado)
    }
    struct Link: Codable, Hashable {  // el tramo siguiente
        var lineCode: String, lineColor: String, statusLevel: Int
        var first: Dep?               // su primera salida (hora y vía del enlace)
    }
}
```

Al escribir: `activity.update(ActivityContent(state:staleDate:), alertConfiguration:)`
con `staleDate` = el primero de (`receivedAt + max(90 s, 2 × refreshHint)`,
salida del tren enseñado + 60 s, siguiente cambio de minuto + 30 s) y alerta
solo si la vía aparece o cambia, el tren se cancela o la línea se corta
(decisiones §5.3–5.4).

### 12.5 Componentes y estados

**Billete** (`TicketView(dep:, context:)`): `ticket` radio 16, alto 56 (50 y
42 en el widget grande), `HStack`: cifra (mín. 78 de ancho) · dos líneas
secundarias que caen por prioridad (cambio de vía 7 > retraso 5 > hora 4 >
longitud 3 > tramo 2; `ViewThatFits`; con cambio de vía cae antes «sale 12:56» y luego se acorta a «antes vía 21») · matriz de vía (62 × 46, margen 5,
radio 11).

| Estado | Billete |
|---|---|
| vivo | `ticket` + `ticketInk`; la cifra la escribe la app (dos tallas) |
| en el andén | `ok` + `atStopInk`, «En andén» |
| apagado (`connection ≠ .ok` o `isStale`) | `ticketOff` + `ticketOffInk`; caducado, **hora fija** «sale a las 12:56» |
| sin salida | `surfaceHi`: «Servicio finalizado · no hay más salidas» (R25) · `bad`: «Sin circulación · toca para ver alternativas» · widgets: «Sin datos recientes · abre Trajet» |

**Vía** (`PlatformMark`): real = caja llena `via` + canto `viaEdge` + «Vía»;
probable = recuadro punteado (1,5–2 pt, guion [4, 3]) + «probable» / «prob.»;
nueva = entra con `.transition(.scale(0.3).combined(with: .opacity))` y muelle
0,7 s; cambiada = igual + «cambio de vía · antes 21». Tallas: matriz (billete),
`xv` 38 × 38 (expandida), chips m/s/xs, mini 20 × 18 (compacta y mínima, solo
forma). Apagada: `viaOff`.

**Cabecera** (`HeaderRow`): distintivo (`LineBadge`, §7.5) · destino
(`ViewThatFits` con las variantes; cae el último) · estado de la línea (⚠ +
«perturbada»; la palabra cae primero) · antigüedad `Text(fecha, style:
.relative)` o, en iOS 18, `.reference` — «hace 9 s»; con problema, píldora
`noticeWarn`/`noticeBad` + símbolo: `clock` (sin actualizar), `wifi.slash`
(sin conexión), `server.rack` (sin clave).

**Pie** (`FootRow`): «luego» + cifra 19 + vía xs (destino corto si
`mixed`) · o transbordo `arrow.up.arrow.down` + «en St-Lazare» + distintivo 18
+ hora + vía del enlace · o «✕ el de las 12:56, cancelado» · y «Parar».

**«Parar»**: `Button(intent: StopTripIntent())` con `Label("Parar",
systemImage: "stop.fill")`; píldora de 32 pt (relleno neutro translúcido: `rule` sobre el fondo del sistema; cuadrado `bad` de 10
pt), `.frame(minHeight: 44).contentShape(Capsule())`. **Nunca se apaga.**

```swift
struct StopTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Parar el trayecto"
    func perform() async throws -> some IntentResult {
        await TripController.shared.stop(reason: .manual)   // end(…, dismissalPolicy: .immediate)
        return .result()
    }
}
```

Fin automático (llegada o duración máxima): `end(ActivityContent(state: final),
dismissalPolicy: .after(.now + 15 * 60))` con «Trayecto terminado».

### 12.6 Dynamic Island

```swift
ActivityConfiguration(for: TrajetActivityAttributes.self) { context in
    LockScreenActivity(context: context)                  // 12.5
        .activityBackgroundTint(nil)                       // el del sistema
        .widgetURL(TrajetLink.leg(context))                // §12.9
} dynamicIsland: { context in
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { BadgeAndDestination(context) }      // una línea
        DynamicIslandExpandedRegion(.trailing) { NumberAndPlatform(context) }       // como la compacta
        DynamicIslandExpandedRegion(.center) { StatusOrLegOrTime(context) }
        DynamicIslandExpandedRegion(.bottom) {
            if context.state.showsPlatformBand { PlatformBand(context) }            // alerta: vía nueva o cambiada (platformNew / platformBefore)
            else { FootRow(context) }
            HStack { AgeView(context); Spacer(); StopButton() }
        }
    } compactLeading: {
        LineBadge(context.state.leg, size: 22)                // + símbolo si apagada o perturbada
    } compactTrailing: {
        ViewThatFits { CompactNumber(prime: true); CompactNumber(prime: false); CompactNumber(platform: false) }
    } minimal: {
        MinimalRing(context)                                  // 36,67 u ovalada hasta 45
    }
    .keylineTint(Color(hex: context.state.leg.lineColor))
    .widgetURL(TrajetLink.leg(context))
}
```

- `.dynamicTypeSize(...(.xLarge))` en todo lo de la actividad.
- `context.isStale` → horas fijas y apagado (§12.5). La vista no calcula la
  hora: el tren caducado lo elige la foto (decisiones §5.3).
- Con el texto del sistema (alternativa), la vía de la compacta pasa a la
  izquierda y la cifra encoge (`minimumScaleFactor`, 0,7 como mucho) antes que ensanchar la isla.

### 12.7 Widgets

```swift
struct TrajetEntry: TimelineEntry {
    let date: Date
    let board: CachedBoard       // BoardV1 + receivedAt, de la caché del App Group
    let failure: Failure?        // nil · .offline · .noKey (la última recarga falló)
    let isFinal: Bool            // «Sin datos recientes · abre Trajet»
}

struct TrajetProvider: TimelineProvider {
    func getTimeline(in context: Context, completion: @escaping (Timeline<TrajetEntry>) -> Void) {
        // 1. La caché del App Group (la escribe la app en cada refresco).
        // 2. Si tiene más de 15 min, un /api/v1/board con timeout corto (token del llavero
        //    compartido); 503 prim_key_missing → .noKey; sin red → .offline; nunca se borra la caché.
        // 3. Entradas: ahora · cada salida del tramo principal (fusionadas a ≥ 5 min) ·
        //    salida − 60 min de los trenes lejanos · entrada final al acabarse las salidas.
        // 4. .after(min(última salida, ahora + 15 min)).
    }
}
```

- Cada entrada pinta las salidas que quedan **tal como llegaron**.
- La cifra: número suelto del sistema + «min» fijo si se confirma la
  hipótesis H1 (`.timer(countingDownIn:maxFieldCount: 1, maxPrecision:
  .seconds(60))`); si no, `durationOffset` con `.units` de una talla; ≥ 60 min,
  hora fija. iOS 17: `Text(timerInterval:countsDown: true)` con `.frame` fijo.
- `containerBackground(for: .widget) { Color.surface }` (removible en
  StandBy y CarPlay); márgenes 14.
- Anatomía fija del pequeño; «desde X» como una sola pieza; un nivel de
  abreviatura por widget (`ViewThatFits` sobre todo el bloque de filas).
- Circular: `ProgressView(timerInterval: salida.addingTimeInterval(-1800)...salida,
  countsDown: true)` con `.progressViewStyle(.circular)` **solo si faltan ≤ 30
  min**; si no, la hora fija sin arco. `AccessoryWidgetBackground()` detrás.
- La app llama a `WidgetCenter.shared.reloadTimelines(ofKind:)` al volver a
  primer plano, al cambiar de ruta y, en modo trayecto y con cuentagotas,
  cuando cambia algo que merece alerta.

### 12.8 Modos de pintado

```swift
@Environment(\.widgetRenderingMode) private var mode
@Environment(\.isLuminanceReduced) private var alwaysOn
```

| Modo | Billete | Vía real | Vía probable | Distintivo |
|---|---|---|---|---|
| `.fullColor` | opaco `ticket` | caja `via` | punteada | color de la línea |
| `.accented` (inicio tintado o transparente) | forma blanca `.widgetAccentable()` con la cifra **calada** (`compositingGroup()` + `blendMode(.destinationOut)`) | caja calada dentro del billete | punteada | blanco con el código calado |
| `.accented`, alternativa «contorno» | trazo de 2 pt | trazo continuo de 2,5 pt | punteada | trazo de 1,5 pt |
| `.vibrant` (bloqueo) | — | caja llena, número calado | punteada | blanco, código calado |
| siempre activa (`alwaysOn`) | igual, sin animación | igual | igual | igual |

El calado está por verificar en la extensión (FASE 3); si no se pinta, se
usa el contorno (`widgetRenderingMode != .fullColor`).

### 12.9 Enlaces

`TrajetLink` construye las URL de decisiones §6: `trajet://ruta/{id}?tramo={seq}`
para la actividad y los widgets (`&salida={jid}` en las filas del mediano),
`trajet://ruta/{id}/alternativas` con la línea cortada, `trajet://tablero` en la
entrada final y `trajet://ajustes/servidor` sin clave. Un `widgetURL` por
jerarquía; `Link` por fila (mediano) y por tramo (grande). La app los recibe
en `onOpenURL`.

### 12.10 Movimiento

| Qué | SwiftUI | Con «Reducir movimiento» o siempre activa |
|---|---|---|
| La cifra cambia | `.contentTransition(.numericText(countsDown: true))` + `Motion.spring(0.5)` | `.contentTransition(.opacity)` |
| Aparece o cambia la vía | `.id(platform)` + `.transition(.scale(scale: 0.3).combined(with: .opacity))`, muelle 0,7 s, halo que se apaga en 1,2 s | fundido 0,2 s y anillo fijo |
| Franja de vía (expandida) | `.transition(.push(from: .bottom))` | fundido |
| Se apaga (R19) | `.animation(.easeInOut(duration: 0.45), value: isOff)` | sin animación |
| La isla cambia de forma | la pone el sistema | el sistema |

Todo ≤ 2 s y solo al actualizarse; nada en bucle (§3.7 de las referencias).

### 12.11 Lista de comprobación de la extensión

- [ ] Cifra ≥ 8:1 también apagada; palabra de R10 ≥ 11 pt (12 en la actividad).
- [ ] La actividad ≤ 160 pt con `.xLarge`; la compacta ≤ 52,33 pt por lado.
- [ ] «Parar» con 44 pt de área y nunca apagado.
- [ ] Congelada: ni cambia de tren ni publica vías; caducada, horas fijas.
- [ ] Widgets: la entrada final existe; la probable sigue probable.
- [ ] Acentuado y vibrante: real llena y probable punteada, sin color.
- [ ] VoiceOver: una frase por salida (R50), con «dato sin actualizar» si toca.

---

## Anexo A. Tinta de los distintivos de línea

Colores del referencial de IDFM (`referentiel-des-lignes`, campos
`colourweb_hexa` y `textcolourweb_hexa`, licencia ODbL; muestra en
`design-lab/tools/lineas-idfm.json`: metro, RER, Transilien, TER, tranvía y
funicular activos) más los colores antiguos que usan `PreviewData` y el
laboratorio. Sirve de banco para `LineColorTests.testTodasLasLineasIDFM`
(R12).

<!-- generado:lineas -->
| Línea | Modo | Color | Texto oficial (contraste) | Tinta elegida | Contraste | Umbral 0,45 de la v1 |
|---|---|---|---|---|---|---|
| 1 | metro | `#FFBE00` | `#000000` (12,62) | `#000000` (oficial) | 12,62 | `#000000` 12,62 |
| 2 | metro | `#0055C8` | `#FFFFFF` (6,7) | `#FFFFFF` (oficial) | 6,7 | `#FFFFFF` 6,7 |
| 3 | metro | `#6E6E00` | `#FFFFFF` (5,39) | `#FFFFFF` (oficial) | 5,39 | `#FFFFFF` 5,39 |
| 3B | metro | `#82C8E6` | `#000000` (11,35) | `#000000` (oficial) | 11,35 | `#000000` 11,35 |
| 4 | metro | `#A0006E` | `#FFFFFF` (7,72) | `#FFFFFF` (oficial) | 7,72 | `#FFFFFF` 7,72 |
| 5 | metro | `#FF5A00` | `#000000` (6,71) | `#000000` (oficial) | 6,71 | `#FFFFFF` **3,13** ✗ |
| 6 | metro | `#82DC73` | `#000000` (12,43) | `#000000` (oficial) | 12,43 | `#000000` 12,43 |
| 7 | metro | `#FF82B4` | `#000000` (9,1) | `#000000` (oficial) | 9,1 | `#FFFFFF` **2,31** ✗ |
| 7B | metro | `#82DC73` | `#000000` (12,43) | `#000000` (oficial) | 12,43 | `#000000` 12,43 |
| 8 | metro | `#D282BE` | `#000000` (7,68) | `#000000` (oficial) | 7,68 | `#FFFFFF` **2,74** ✗ |
| 9 | metro | `#D2D200` | `#000000` (12,96) | `#000000` (oficial) | 12,96 | `#000000` 12,96 |
| 10 | metro | `#DC9600` | `#000000` (8,41) | `#000000` (oficial) | 8,41 | `#FFFFFF` **2,5** ✗ |
| 11 | metro | `#6E491E` | `#FFFFFF` (7,97) | `#FFFFFF` (oficial) | 7,97 | `#FFFFFF` 7,97 |
| 12 | metro | `#00643C` | `#FFFFFF` (7,27) | `#FFFFFF` (oficial) | 7,27 | `#FFFFFF` 7,27 |
| 13 | metro | `#82C8E6` | `#000000` (11,35) | `#000000` (oficial) | 11,35 | `#000000` 11,35 |
| 14 | metro | `#640082` | `#FFFFFF` (11,26) | `#FFFFFF` (oficial) | 11,26 | `#FFFFFF` 11,26 |
| A | rail | `#EB2132` | `#FFFFFF` (4,38 ✗) | `#000000` (calculada) | 4,8 | `#FFFFFF` **4,38** ✗ |
| B | rail | `#5091CB` | `#FFFFFF` (3,36 ✗) | `#000000` (calculada) | 6,25 | `#FFFFFF` **3,36** ✗ |
| C | rail | `#FFCC30` | `#000000` (13,93) | `#000000` (oficial) | 13,93 | `#000000` 13,93 |
| D | rail | `#008B5B` | `#FFFFFF` (4,34 ✗) | `#000000` (calculada) | 4,84 | `#FFFFFF` **4,34** ✗ |
| E | rail | `#B94E9A` | `#FFFFFF` (4,55) | `#FFFFFF` (oficial) | 4,55 | `#FFFFFF` 4,55 |
| CDG VAL | rail | `#5CC5ED` | `#FFFFFF` (1,97 ✗) | `#000000` (calculada) | 10,66 | `#000000` 10,66 |
| ORLYVAL | rail | `#5EC5ED` | `#FFFFFF` (1,97 ✗) | `#000000` (calculada) | 10,69 | `#000000` 10,69 |
| TER | rail | `#AAAAAA` | `#000000` (9,04) | `#000000` (oficial) | 9,04 | `#FFFFFF` **2,32** ✗ |
| H | rail | `#84653D` | `#FFFFFF` (5,37) | `#FFFFFF` (oficial) | 5,37 | `#FFFFFF` 5,37 |
| J | rail | `#CEC73D` | `#000000` (11,86) | `#000000` (oficial) | 11,86 | `#000000` 11,86 |
| K | rail | `#9B9842` | `#FFFFFF` (3,02 ✗) | `#000000` (calculada) | 6,96 | `#FFFFFF` **3,02** ✗ |
| L | rail | `#C4A4CC` | `#000000` (9,53) | `#000000` (oficial) | 9,53 | `#FFFFFF` **2,2** ✗ |
| N | rail | `#00B297` | `#FFFFFF` (2,69 ✗) | `#000000` (calculada) | 7,82 | `#FFFFFF` **2,69** ✗ |
| P | rail | `#F58F53` | `#000000` (8,94) | `#000000` (oficial) | 8,94 | `#FFFFFF` **2,35** ✗ |
| R | rail | `#F49FB3` | `#000000` (10,46) | `#000000` (oficial) | 10,46 | `#000000` 10,46 |
| U | rail | `#B6134C` | `#FFFFFF` (6,59) | `#FFFFFF` (oficial) | 6,59 | `#FFFFFF` 6,59 |
| V | rail | `#9F9825` | `#FFFFFF` (3 ✗) | `#000000` (calculada) | 6,99 | `#FFFFFF` **3** ✗ |
| T1 | tram | `#0055C8` | `#FFFFFF` (6,7) | `#FFFFFF` (oficial) | 6,7 | `#FFFFFF` 6,7 |
| T2 | tram | `#A0006E` | `#FFFFFF` (7,72) | `#FFFFFF` (oficial) | 7,72 | `#FFFFFF` 7,72 |
| T3a | tram | `#FF5A00` | `#000000` (6,71) | `#000000` (oficial) | 6,71 | `#FFFFFF` **3,13** ✗ |
| T3b | tram | `#00643C` | `#FFFFFF` (7,27) | `#FFFFFF` (oficial) | 7,27 | `#FFFFFF` 7,27 |
| T4 | tram | `#DC9600` | `#000000` (8,41) | `#000000` (oficial) | 8,41 | `#FFFFFF` **2,5** ✗ |
| T5 | tram | `#640082` | `#FFFFFF` (11,26) | `#FFFFFF` (oficial) | 11,26 | `#FFFFFF` 11,26 |
| T6 | tram | `#FF0000` | `#FFFFFF` (4 ✗) | `#000000` (calculada) | 5,25 | `#FFFFFF` **4** ✗ |
| T7 | tram | `#6E491E` | `#FFFFFF` (7,97) | `#FFFFFF` (oficial) | 7,97 | `#FFFFFF` 7,97 |
| T8 | tram | `#6E6E00` | `#FFFFFF` (5,39) | `#FFFFFF` (oficial) | 5,39 | `#FFFFFF` 5,39 |
| T9 | tram | `#3C91DC` | `#FFFFFF` (3,35 ✗) | `#000000` (calculada) | 6,28 | `#FFFFFF` **3,35** ✗ |
| T10 | tram | `#6E6E00` | `#FFFFFF` (5,39) | `#FFFFFF` (oficial) | 5,39 | `#FFFFFF` 5,39 |
| T11 | tram | `#FF5A00` | `#000000` (6,71) | `#000000` (oficial) | 6,71 | `#FFFFFF` **3,13** ✗ |
| T12 | tram | `#A50034` | `#FFFFFF` (7,93) | `#FFFFFF` (oficial) | 7,93 | `#FFFFFF` 7,93 |
| T13 | tram | `#8D653D` | `#FFFFFF` (5,17) | `#FFFFFF` (oficial) | 5,17 | `#FFFFFF` 5,17 |
| T14 | tram | `#00A092` | `#FFFFFF` (3,26 ✗) | `#000000` (calculada) | 6,44 | `#FFFFFF` **3,26** ✗ |
| FUN | funicular | `#AFAFAF` | `#000000` (9,57) | `#000000` (oficial) | 9,57 | `#FFFFFF` **2,19** ✗ |
| E (lab) | lab | `#B94E9A` | — | `#000000` (calculada) | 4,62 | `#FFFFFF` 4,55 |
| 13 (lab) | lab | `#82C8E6` | — | `#000000` (calculada) | 11,35 | `#000000` 11,35 |
| A (lab) | lab | `#E3051C` | — | `#FFFFFF` (calculada) | 4,88 | `#FFFFFF` 4,88 |
| T2 (lab) | lab | `#C4318E` | — | `#FFFFFF` (calculada) | 5,03 | `#FFFFFF` 5,03 |
| 4 (lab) | lab | `#BE418D` | — | `#FFFFFF` (calculada) | 4,85 | `#FFFFFF` 4,85 |
| 6 (lab) | lab | `#6ECA97` | — | `#000000` (calculada) | 10,56 | `#000000` 10,56 |
| 147 (lab) | lab | `#E4022D` | — | `#FFFFFF` (calculada) | 4,83 | `#FFFFFF` 4,83 |
| 6424 (lab) | lab | `#A50034` | — | `#FFFFFF` (calculada) | 7,93 | `#FFFFFF` 7,93 |
| naranja de prueba | lab | `#FF7E2E` | — | `#000000` (calculada) | 8,28 | `#FFFFFF` **2,54** ✗ |
| reserva (R57) | lab | `#6B7380` | — | `#FFFFFF` (calculada) | 4,78 | `#FFFFFF` 4,78 |

Resumen: 59 colores. El texto oficial de IDFM no llega a 4,5:1 en 11 (A, B, D, CDG VAL, ORLYVAL, K, N, V, T6, T9, T14); ahí se usa la tinta calculada. El umbral 0,45 de la v1 fallaba en 21 (5, 7, 8, 10, A, B, D, TER, K, L, N, P, V, T3a, T4, T6, T9, T11, T14, FUN, naranja de prueba). Con la regla nueva, el peor caso es 4,55:1.
<!-- /generado:lineas -->
