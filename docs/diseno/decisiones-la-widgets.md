# Live Activity y widgets: la variante elegida y por qué

FASE 2B.4–2B.5 · 24 de septiembre de 2026 · cierra el rediseño de la Live
Activity y los widgets dentro de «Cristal».

- Referencias y límites de iOS: `docs/diseno/referencias-la-widgets.md` (los
  «principios» 1–15 que se citan aquí son los de su §6).
- Especificación de los componentes para la FASE 3 (tamaños, tokens, estados,
  animación, `ActivityAttributes`, `TimelineProvider`…): `docs/diseno/sistema.md` §12.
- Laboratorio: `design-lab/b-cristal-v2/` (cómo verlo, al final).
- Capturas: `design-lab/capturas/la-widgets/A/` (la elegida, rehechas en la
  2B.4), `B/` y `C/` (las de la 2B.3, sin tocar), `comparar/` y los GIF.
- Las reglas se citan por su id de `docs/reglas.md`; «[P0-1]» y similares son
  los puntos del informe del revisor de la 2B.3.

---

## 0. Resumen

1. **Gana A «Billete»** (7,6 de 10 para el revisor, frente a 6,1 de B y 5,9
   de C). Estoy de acuerdo: es la única con la misma anatomía en todas las
   piezas, la que mejor se lee en un segundo y la más fiel a «Cristal» (el
   dato en un billete opaco; el cristal lo pone el sistema).
2. Se han corregido **los 23 puntos** que el revisor le puso (4 P0, 6 P1, 9 P2
   y 4 P3), y se han traído de B y de C las cuatro cosas que él recomendaba.
3. **La Live Activity pinta solo lo que la app escribió** (su `ContentState`).
   Si la app deja de escribir, no cambia de tren ni «publica» vías: la cuenta
   atrás sigue por fecha y, al vencer `staleDate`, pasa a **horas de salida
   fijas**, en gris, con «sin actualizar · hace N min».
4. **La cifra tiene dos versiones** y el laboratorio enseña las dos (y una
   tercera para iOS 17): la que escribe la app (dos tallas, «′», «ya», «1h46»)
   mientras la Live Activity está viva, y el texto de fecha del sistema, de una
   sola talla, donde la app no puede escribir (widgets) o como alternativa.
5. **Una sola regla de apagado** (R19): billete gris opaco (cifra ≥ 8:1),
   vía sin amarillo pero con su forma, todo desaturado menos «Parar» y el aviso
   que explica por qué.
6. **Widgets = una foto con fecha**: cada entrada del timeline enseña el dato
   tal como llegó en la última recarga; al acabarse las salidas conocidas, una
   entrada final «Sin datos recientes · abre Trajet».
7. **Todos los estados diseñados**, también los que faltaban en las tres:
   cambio de vía, tren cancelado, servicio finalizado, destinos mezclados,
   servidor sin clave PRIM, tren que ya salió con la actividad congelada y
   parada a mano.
8. **Nada inventado**: todo sale de `/api/v1/board`; lo que calcula la app
   (fechas, variantes del destino, vía anterior de la misma `jid`, estado de la
   conexión) está marcado como derivado en `sistema.md` §12.4.

---

## 1. Qué variante y por qué

### 1.1 La puntuación del revisor

| Criterio | A · Billete | B · Tablero | C · Fases |
|---|---|---|---|
| Legibilidad en 1 s | 8 | 5 | 6 |
| Problemas del encargo resueltos | 8 | 6 | 6,5 |
| Estados cubiertos | 7 | 6,5 | 5,5 |
| Fidelidad a «Cristal» | 8,5 | 6 | 7 |
| Viabilidad técnica | 6,5 | 7 | 4,5 |
| **Media** | **7,6** | **6,1** | **5,9** |

### 1.2 Por qué A (y no discrepo del revisor)

- **Una anatomía para todo.** Cifra enorme en un billete opaco, la vía en la
  «matriz» del billete (a la derecha, como la matriz de un billete de tren) y
  una sola línea secundaria debajo. Se aprende una vez y vale para la de
  bloqueo, la isla y los tres widgets. Es lo que pide R1: mirar de reojo, dos
  o tres segundos, a contraluz.
- **La cifra manda de verdad** (R48): 44 pt en la de bloqueo, 54 pt en el
  widget pequeño, 38 pt en la expandida. En B el destino competía con la cifra
  y en el widget pequeño volvía a quedarse pequeña; en C la baldosa de la
  derecha cambiaba de significado («21» podía ser la vía o «luego 21 min»).
- **Es «Cristal» sin trampas**: el billete es la misma pieza que el de la app
  (`sistema.md` §7.2), el cristal lo pone el sistema (fondo de la actividad,
  widgets tintados) y nunca va debajo de minutos y vía.
- **Su punto flojo era técnico** (6,5 en viabilidad): congelada inventaba
  datos y la cifra de dos tallas no se puede hacer con un texto de fecha del
  sistema. Las dos cosas se han resuelto sin cambiar la idea (§3 y §5); B y C
  tienen los mismos problemas de fondo (su «dato antiguo» también reconstruía
  el tablero vivo) y además los suyos propios.

### 1.3 Lo que se ha llevado de B y de C

| De | Qué | Dónde está en A |
|---|---|---|
| B | Destino por fila cuando se mezclan destinos (R24) | pie «luego 21 min · Mantes», fichas del grande, filas del mediano |
| B | La fila de transbordo con la vía del tren de enlace | pie de la de bloqueo y de la expandida: «⇅ en St-Lazare [J] 12:56 [Vía 21]» |
| B | «Parar» nunca apagado | en todas las presentaciones y estados |
| C | La franja de vía a lo ancho para la alerta | fila de abajo de la expandida cuando la vía aparece o cambia |
| C | El «90 %» de la vía probable donde quepa | matriz del billete del widget grande |

Lo que **no** se ha traído: el ritmo «Anda / Corre» de C (es estático, se queda
viejo en cuanto la actividad se congela y siempre en los widgets) y el rojo en
el billete para «Corre» (el rojo ya significa «Sin circulación»).

---

## 2. El encargo, problema por problema

### 2.1 Live Activity en la pantalla de bloqueo

| Problema del prototipo B | Cómo lo resuelve A |
|---|---|
| El destino se corta («Ermont - Eaub…») | `abreviar()` da variantes enteras («Ermont - Eaubonne» → «Ermont-Eaubonne» → «Ermont») y la vista se queda con la primera que cabe (`ViewThatFits`); si no cabe ninguna, se quita. Nunca «…» dentro de una palabra (§7). |
| El texto secundario se apelotona en varias líneas | Dentro del billete, dos líneas cortas con prioridad fija: retraso > hora > longitud > tramo. Lo que no cabe **se cae entero** (con texto grande cae primero «tramo 1 de 2», luego «tren largo», luego «sale 12:56»). Debajo del billete, **una** línea: «luego …» o el transbordo. |
| La cuenta atrás está duplicada («6 min» y «05:58») | Una sola cifra, de minuto en minuto. Sin segundos (el dato es «HH:MM»). |
| Falta la antigüedad del dato | Siempre arriba a la derecha: «hace 9 s», que envejece sola por fecha (R17, R18). Si algo va mal, se convierte en una píldora con símbolo y palabra: «sin conexión · hace 4 min», «servidor sin clave · hace 4 min», «sin actualizar · hace 6 min». |
| La barra de progreso no se entiende | Fuera. El único arco que queda es el del widget circular y solo con 30 min o menos (§2.4). |
| No hay siguiente tren, tramo ni transbordo | Pie: «luego 21 min [prob. 21]»; en rutas con transbordo, «⇅ en St-Lazare [J] 12:56 [Vía 21]» con la vía del tren de enlace; en el billete, «tramo 1 de 2». |
| No hay acción para parar | «Parar» con `Button(intent:)` (`LiveActivityIntent`), píldora de 32 pt con 44 pt de área táctil, nunca apagada. Con el iPhone bloqueado pide Face ID (lo pone el sistema). |

La actividad mide **371 × 150 pt** en el iPhone 16 (tope de iOS: 160), y
**153 pt** con el texto al tope (xLarge): hay margen para Dynamic Type.

### 2.2 Dynamic Island

| Problema | Cómo lo resuelve A |
|---|---|
| La expandida es una copia apretada de la de bloqueo | Usa las cuatro regiones: **leading** = distintivo y destino en una línea; **trailing** = cifra + la vía en su matriz pequeña (igual que en la compacta); **center** = estado de la línea, «tramo 1 de 2» o «sale 12:56»; **bottom** = «luego …» o el transbordo, y la antigüedad con «Parar». Cuando la alerta la abre porque la vía se acaba de anunciar o ha cambiado, la primera fila de abajo es **la franja de vía a lo ancho**. 151–154 pt. |
| La compacta pone los minutos en un hueco raro | Leading = distintivo de línea (con su color) y, si hace falta, un símbolo (⚠, reloj, sin red). Trailing = cifra + vía como forma (caja llena = real, punteada = probable). Nunca pasa de 52,33 pt por lado: con «59 min + vía» cae el «′» («59 [21]») antes de ensanchar la isla (vista «Casos límite»). |
| La mínima tiene que entenderse sola | Un aro del color de la línea con la cifra y «min»; ovalada (45 pt) para «1h46» o la hora fija; en el andén, aro **verde** con «andén» sobre la vía; apagada, aro gris. |

### 2.3 Widgets de la pantalla de inicio

| Problema | Cómo lo resuelve A |
|---|---|
| El pequeño deja un hueco y los minutos quedan pequeños | El billete ocupa todo el centro: la cifra a **54 pt**. Anatomía fija: arriba línea + destino (o el aviso); en medio el billete; abajo la vía (o «luego …») y la antigüedad. Si no cabe todo abajo, cae «luego» antes que la antigüedad. |
| El mediano descoloca la vía probable y no da destino por fila | Columna izquierda = el pequeño (línea, billete, vía con palabra). Derecha = «desde Gare Saint-Lazare» como una sola pieza que cae entera, dos filas con cifra, vía (o retraso u hora) y **destino por fila**, todas con **el mismo nivel de abreviatura**; abajo la antigüedad. |
| Ningún widget enseña la antigüedad | Todos la enseñan, y es contenido, no pie de página: casi siempre dice «hace 5–60 min». Si la recarga falló, lleva el símbolo (sin red, sin clave). |
| Valorar un widget grande | Sí: el tablero de la ruta que toca, un bloque por tramo (billete + fichas), con el estado de cada línea y el «90 %» de la vía probable. No es el pequeño estirado. |

### 2.4 Widgets de la pantalla de bloqueo

| Problema | Cómo lo resuelve A |
|---|---|
| No pueden depender del color | En vibrante no hay color de línea ni amarillo: la vía real es una **caja llena con el número calado** + «Vía» y la probable un **recuadro punteado** + «prob.» (R10). Lo apagado es gris y lleva símbolo. |
| El rectangular se desborda | Tres líneas fijas en 160 × 72: línea + destino (ajustable); cifra + vía; antigüedad (con símbolo si la recarga falló). Nada se sale: cada línea cae por prioridad. |
| El circular debería usar un `Gauge` | `ProgressView(timerInterval: salida − 30 min … salida, countsDown: true)` con la cifra dentro y la línea debajo. **El arco solo aparece con 30 min o menos**; con más (o «1h46»), la hora fija sin arco, para que el arco lleno no diga nada falso. |
| El de línea | «J · 6 min · Vía 21 · hace 5 min», que cae por el final; la probable dice «prob. 21», nunca «vía 21 prob.» (R10); el aviso y la falta de red van como símbolo al principio. |

### 2.5 Requisitos del rediseño

| Requisito | Cómo se cumple |
|---|---|
| Legible en 1 s, a contraluz | Cifra heavy redondeada de 38–54 pt sobre opaco (≥ 19:1 vivo, ≥ 8:1 apagado); vía amarilla con canto; destino entero o bien abreviado. |
| Cuenta atrás que corre sola | Viva: la app escribe la cifra cada minuto y `staleDate` la protege. Widgets y congelada: texto de fecha del sistema (§5.2). |
| Antigüedad siempre visible, «sin conexión» diseñado | §2.1 y §4. |
| Todos los estados | §4 (y escenas del laboratorio). |
| Claro, oscuro, tintado de iOS 26, «Reducir transparencia» | Capturas `claro`, `oscuro`, `tintado`, `transparente`, `tintado-contorno`, `*-reducir-transparencia`. Los datos van en piezas opacas: «Reducir transparencia» solo cambia fondos. |
| Límites reales de ActivityKit y WidgetKit | §5. |
| Transición de contenido, botón con App Intent, deep link | `numericText(countsDown: true)`, transición de ≤ 2 s para la vía, `LiveActivityIntent` para «Parar» y `widgetURL`/`Link` por pieza (§6). |

---

## 3. La lista del revisor, punto por punto

| # | Qué fallaba | Qué se ha hecho |
|---|---|---|
| **P0-1** | Congelada, la actividad pasaba sola al tren siguiente con «Vía 21» real | Modelo nuevo (`modelA` en `app.js`): la actividad pinta la foto que la app escribió. Congelada no cambia de tren; al vencer `staleDate` pasa a la hora fija del primer tren que sale más de 60 s después de `staleDate`, con su vía **tal como llegó** («probable 21»), en gris y con «sin actualizar · hace N min». Widgets: entradas con el dato de la última recarga y entrada final «Sin datos recientes». Capturas `A-*-congelada-tren-salido-*`, `A-viva-y-congelada-*`, `gif-cuenta-atras-A.gif`. |
| **P0-2** | Cifra grande + «min» pequeño no se puede con un texto del sistema | Tres versiones con su interruptor («Cifra» en el panel) y sus capturas: la de la app (viva), la del sistema de una talla (`*-sistema-oscuro`) e iOS 17 con segundos (`*-ios17-oscuro`). En los widgets, la hipótesis H1 (número suelto del sistema) o una talla. Primera prueba de la FASE 3: §10. |
| **P0-3** | «Parar» se apagaba con el dato viejo | Fuera del apagado: siempre a pleno contraste. |
| **P0-4** | R19 a trozos | Una regla (`.A-off`): billete gris opaco, vía gris con su forma, distintivo y estado desaturados; la expandida, la compacta, la mínima, los widgets (también la caja de la vía) y los de bloqueo; el circular y el de línea añaden el símbolo. Contrastes en `sistema.md` §12.2 (el peor texto, 6,3:1; cifras ≥ 8:1). |
| **P1-5** | La compacta crecía a 249–253 pt | Cifra a 16 pt, caja de vía de 12 pt, `ViewThatFits` que quita el «′» y luego la vía; tope de 52,33 por lado. Probado «59′ + 21», «59 + prob. 21», «1h46», «ya», «andén», texto del sistema, iOS 17, caducada y sin red: todas a 230 pt (vista «Casos límite»; con el texto del sistema «59 min» encoge un poco (`minimumScaleFactor`, 0,7 como mucho) antes que ensanchar). |
| **P1-6** | La expandida no aprovechaba la vía | Trailing = cifra + vía; franja de vía con la alerta; center con estado/tramo/hora; destino en una línea abreviada. |
| **P1-7** | La palabra de R10 a 9–10 pt | 12 pt en la Live Activity (billete, pie, expandida) y 11 pt en los widgets («prob.» cuando no cabe «probable»). En la compacta y la mínima solo la forma (la palabra va a VoiceOver). |
| **P1-8** | «Parar» de 28–30 pt | Píldora de 32 pt y 44 pt de área (`contentShape`); se ve con «Ver enlaces y áreas táctiles». |
| **P1-9** | SE: «⚠ perturbada h…» | Anatomía fija: la antigüedad no sube a la cabecera; en la cabecera cae la palabra «perturbada» y queda el ⚠. `A-lamina-se-aviso-oscuro.png`. |
| **P1-10** | 158 de 160 pt | 150 pt; tope `.dynamicTypeSize(...(.xLarge))` (153 pt al tope) y orden de caída definido. Capturas `texto-xl` y `texto-ax3`. |
| **P2-11** | El transbordo no decía la vía del enlace | «⇅ en St-Lazare [J] 12:56 [Vía 21]»; la vía se queda antes que la hora. |
| **P2-12** | Destinos mezclados sin probar | Escena «Destinos mezclados»: destino corto en el pie, las fichas y cada fila. |
| **P2-13** | La de línea decía «vía 21 prob.» y perdía el aviso | «prob. 21»; ⚠ y sin red como símbolo. |
| **P2-14** | La mínima en el andén solo enseñaba «21» | Aro verde + «andén» sobre la vía. |
| **P2-15** | El pequeño cambiaba de anatomía | Anatomía fija (§2.3). |
| **P2-16** | «desde» huérfano y abreviaturas distintas | «desde X» es una sola pieza que cae entera; un nivel de abreviatura por widget (el más corto que necesite alguien). |
| **P2-17** | Línea cortada redundante | «Sin circulación» + lo útil: «toca para ver alternativas» (enlace a las alternativas) y el transbordo; la expandida también lo dice; fuera «× interrumpida» cuando el billete ya dice «Sin circulación». |
| **P2-18** | El arco del circular no se explicaba | Solo con ≤ 30 min; `ProgressView(timerInterval:countsDown:)` (el fallo del 100 % se prueba en la FASE 3). |
| **P2-19** | «Terminado» siempre se quitaba a los 15 min | Llegada o duración máxima: resumen «Trayecto terminado · se quita sola a las 13:05». Parado a mano: `.immediate`, sin resumen (escena «Parado a mano»). |
| **P3-20** | Escenas y aspectos que faltaban | Escenas: cambio de vía, cancelado, servicio finalizado, destinos mezclados, servidor sin clave, congelada con el tren ya salido, widget sin datos recientes, nombres largos, parado a mano. Aspectos: siempre activa, StandBy de noche, aumentar contraste, texto xLarge y AX3, iOS 17. |
| **P3-21** | Enlaces, `staleDate`, actualización local | §5.3, §5.4 y §6. |
| **P3-22** | El GIF daba a entender que pasaba sola al siguiente | `gif-cuenta-atras-A.gif`: la misma actividad con la app escribiendo y con la app parada, lado a lado y rotulado. El de la 2B.3 (`gif-cuenta-atras-las-tres.gif`) se queda como estaba, pero está superado. |
| **P3-23** | El calado, sin verificar | Interruptor «Acentuado: calado / contorno»: la alternativa sin `blendMode(.destinationOut)` está diseñada y capturada (`*-tintado-contorno`). Se decide en la FASE 3 (§10). |

---

## 4. Estados

Cada estado dice lo que pasa con **palabra + símbolo**, nunca solo con color
(principio 12). «Foto» = lo que hay en el `ContentState` o en la entrada del
timeline.

| Estado | Dato | Live Activity (bloqueo · expandida) | Compacta · mínima | Widgets | Bloqueo (circular · rectangular · línea) |
|---|---|---|---|---|---|
| Vía real | `platform` | matriz amarilla «Vía 21» | caja llena «21» | matriz o chip «Vía 21» | caja llena calada «Vía 21» |
| Vía probable | `guess` | matriz punteada «probable 21» | caja punteada | «prob. 21» · el grande «probable 21 · 90 %» | punteada «prob. 21» |
| Sin vía | nada | sin hueco (R2, R3) | sin hueco | sin hueco; abajo «luego …» | nada |
| Aparece la vía | `platform_new` | la matriz entra con muelle (≤ 2 s) y la **alerta** abre la expandida con la franja «Vía 21 · anunciada ahora» | la caja entra | (recarga desde la app) | — |
| Cambio de vía | misma `jid`, otra vía | «cambio de vía · antes 21» en el billete («antes vía 21» si no cabe); alerta con franja «Vía 23 · cambio de vía · antes 21» | caja nueva | la vía nueva | la vía nueva |
| Tren cancelado | `status: "cancelled"` | el billete es el **siguiente** tren; el pie dice «✕ el de las 12:56, cancelado»; alerta | la cifra del siguiente | cabecera «✕ 12:56 cancelado»; fila tachada en el mediano, ficha en el grande | «12:56 cancelado» / ✕ |
| Bus a 1h46 | `minutes` ≥ 60 | «1h46» (R6) + «sale 14:36 +11 min» | «1h46»; mínima ovalada | **hora fija** «sale a las 14:36» (el sistema no sabe decir «1h46») | «sale 14:36», sin arco |
| Aviso (perturbada) | `status.level` 1 | «⚠ perturbada» en la cabecera (la palabra cae antes que el destino) y en el center | ⚠ junto al distintivo | ⚠ en la cabecera / chip | ⚠ |
| Línea cortada | `level` 2 sin salidas | billete rojo «Sin circulación · toca para ver alternativas» + el transbordo | ✕ | billete rojo | ✕ «Sin circulación» |
| Servicio finalizado | tramo vacío, línea normal | billete neutro «Servicio finalizado · no hay más salidas» (R25) | luna | igual | luna |
| En el andén | `at_stop` | billete **verde** «En andén» (≠ «ya», R15) | «andén» sobre la vía · aro verde | billete verde | «andén» |
| Ya | contador a 0 (solo la app) | «ya» | «ya» | (el sistema dice «0 min» hasta la siguiente entrada) | — |
| Destinos mezclados | `directions: []` y destinos distintos | destino de cada tren (pie y fichas) | — | destino por fila | — |
| Transbordo · tramo 1 | ruta con varios tramos | «tramo 1 de 2»; pie con el enlace y su vía | — | el grande, un bloque por tramo | — |
| Transbordo · tramo 2 | idem | «tramo 2 de 2» | — | — | — |
| Sin conexión | la app no llega al servidor | **apagada**; «sin conexión · hace 4 min»; la cifra sigue (la escribe la app desde su último tablero) | símbolo sin red; gris | apagado; en el pequeño, el símbolo junto al distintivo y «hace 20 min» en rojo; en el mediano y el grande, «sin conexión · hace 20 min» | gris + símbolo |
| Servidor sin clave PRIM | `prim_key_missing` (503) | apagada; «servidor sin clave · hace 4 min»; toca → Ajustes | símbolo servidor | apagado; símbolo | símbolo |
| Dato antiguo (congelada) | `context.isStale` | apagada; **hora fija** «sale a las 12:56» y «luego 13:11», vía tal como llegó; «sin actualizar · hace 6 min» | reloj + «12:56»; mínima ovalada | — (independientes) | — |
| Congelada y el tren ya salió | `staleDate` = salida + 60 s | la hora fija del **siguiente** de la foto («13:11 · probable 21») | «13:11» | la entrada siguiente del timeline | idem |
| Sin datos recientes | se acabaron las salidas de la foto | lo mismo si a la app, sin red, se le acaba su último tablero (nunca «Servicio finalizado») | reloj | billete «Sin datos recientes · abre Trajet» (entrada final del timeline) | «sin datos recientes» |
| Terminado (llegada o duración máxima) | fin del modo trayecto | resumen 15 min: «Trayecto terminado · se quita sola a las 13:05» | sale de la isla | — | — |
| Parado a mano | «Parar» | se quita al momento (`.immediate`) | sale de la isla | — | — |

---

## 5. Límites de iOS que condicionan el diseño y cómo se respetan

### 5.1 Tamaños

| Pieza | SE (375) | 16 (393) | 16 Pro Max (440) | En A |
|---|---|---|---|---|
| Live Activity de bloqueo | 353 × 84–160 [estim.] | 371 × 84–160 | 408 × 84–160 | 150 pt; 153 con xLarge |
| Compacta (por lado · total) | — | 52,33 · 230 | 62,33 · 250 | 230 / 250 en todos los casos límite |
| Mínima | — | 36,67–45 | igual | 36,67; 45 para «1h46», hora fija y texto del sistema |
| Expandida | — (banner) | 371 × 84–160 | 408 × 84–160 | 151–154 |
| Pequeño / mediano / grande | 148 / 321×148 / 321×324 | 158 / 338×158 / 338×354 | 170 / 364×170 / 364×382 | márgenes de 14 pt (11–16 de la HIG) |
| Circular / rectangular / en línea | 68 / 153×68 / 225×26 | 72 / 160×72 / 234×26 | 76 / 172×76 / 257×26 | — |

### 5.2 Texto que se actualiza solo: la cifra

Lo único que iOS mueve sin la app son los textos de fecha (y
`ProgressView(timerInterval:)`). El sistema pone las palabras y **una sola
talla**: no puede dar «6» grande y «min» pequeño, ni «6′», ni «1h46», ni «ya».
Decisión:

| Dónde | Quién escribe la cifra | Aspecto | Por qué |
|---|---|---|---|
| Live Activity **viva** (modo trayecto) | **la app**, al refrescar y en cada cambio de minuto, sin red (tiene el tablero) | dos tallas; «6′» en la compacta; «ya»; «1h46» | es la mejor lectura y la app está viva; `staleDate` la protege si deja de escribir |
| Live Activity **caducada** (`isStale`) | nadie: **hora fija** «sale a las 12:56» | una talla, siempre cierta | la vista no sabe qué hora es |
| **Widgets** | el sistema. **H1**: `.timer(countingDownIn:maxFieldCount: 1, maxPrecision: .seconds(60))` da el número suelto → «6» + «min» fijo (dos tallas). Si no: `durationOffset` con `.units` → «6 min» de una talla, que encoge hasta 0,7 | como la viva si H1; si no, una talla | las entradas del timeline van a ≥ 5 min |
| Widgets con ≥ 60 min | hora fija «sale a las 14:36» + una entrada a `salida − 60 min` para pasar a cuenta atrás | — | «1 h 46 min» no cabe y no es R6 |
| iOS 17 | `Text(timerInterval:countsDown: true)` con marco fijo: «5:59» | segundos | alternativa aceptada (principio 2) |

En el laboratorio: «Cifra» → «La escribe la app» / «Sistema · 1 talla» /
«iOS 17 · segundos». Las capturas `*-sistema-oscuro` y `*-ios17-oscuro` son
las alternativas de cada pieza.

### 5.3 `staleDate`: cuándo la Live Activity dice «sin actualizar»

Cada vez que la app escribe el `ContentState` pasa
`ActivityContent(state:staleDate:)` con:

```
staleDate = el primero de
  · llegada del tablero + max(90 s, 2 × server.refresh_hint_s)   ← el dato es viejo (R19)
  · salida del tren enseñado + 60 s                                ← el tren ya salió
  · siguiente cambio de minuto + 30 s   (solo con la cifra escrita por la app) ← la cifra ya no vale
```

Si la app sigue viva, cada escritura corre la fecha; si deja de escribir, el
sistema pone `context.isStale` y la vista pasa a horas fijas **sin la app**.
La vista no sabe qué hora es, así que el tren que enseña caducada lo decide
la foto: el primero que sale **más de 60 s después de `staleDate`** (si
caducó por la salida, es el siguiente; si caducó porque el dato era viejo, el
que venía). Esa hora es cierta para siempre; si luego ese tren también sale,
el reloj de la pantalla de bloqueo, justo encima, lo dice.

«Sin conexión» y «servidor sin clave» **no** esperan a `staleDate`: la app
está viva, lo sabe y escribe ese estado ella misma (apagada, con la cifra al
día desde su último tablero y la antigüedad real). En esas escrituras el
primer término no cuenta (el dato ya se sabe viejo y ya se dice); los otros
dos siguen protegiendo por si, además, la app deja de escribir.

### 5.4 Actualizar sin push

- La Live Activity no tiene red ni ubicación: todo lo trae la app.
- **La app sí la reescribe cada minuto en local** mientras dura el modo
  trayecto (ubicación en segundo plano, el proceso sigue vivo), y en cada
  refresco del tablero (`refresh_hint_s`, 30 s normalmente). Apple no lo
  garantiza sin push: por eso el diseño aguanta congelado (§5.3) y la FASE 3
  mide cuántas escrituras se pierden con el iPhone bloqueado
  (`docs/pruebas-iphone.md`).
- Las geocercas despiertan la app unos segundos: refresca y escribe una vez.
- Las alertas (`AlertConfiguration`) solo para: vía publicada, cambio de vía,
  tren cancelado y línea cortada. Nunca por un cambio de minuto.

### 5.5 Widgets: presupuesto y timeline

- 40–70 recargas al día y entradas a ≥ 5 min: el widget es una foto con fecha.
- Entradas: la de ahora, **cada salida** del tramo principal (fusionadas si
  distan < 5 min), `salida − 60 min` para los trenes lejanos y una **entrada
  final** «Sin datos recientes · abre Trajet» al acabarse las salidas.
- Cada entrada enseña las salidas que quedan **tal como llegaron** (una vía
  probable sigue probable, aunque la de bloqueo, viva, ya diga «Vía 21»).
- Política `.after(mín(última salida, ahora + 15 min))`; la app pide
  `reloadTimelines` al volver a primer plano, al cambiar de ruta y, con
  cuentagotas, en modo trayecto cuando cambia algo que merece alerta.
- Límite aceptado: con paso < 5 min (metro), entre dos entradas la cifra se
  queda en «0 min» hasta la siguiente (como mucho unos minutos). Se ve en
  `A-widget-grande-congelada-tren-salido-*` (la 14 a las 12:57:30).

### 5.6 Color: acentuado, vibrante, StandBy y siempre activa

- Acentuado (inicio tintado o transparente, iOS 26): todo blanco. El billete
  es una forma blanca con la cifra **calada**; la vía real, una caja calada
  dentro del billete; la probable, punteada. Alternativa sin calado
  («contorno»): billete y vía real en trazo continuo, probable punteada.
- Vibrante (bloqueo): grises; vía real caja llena calada, probable punteada.
- StandBy de noche (todo rojo) y siempre activa (luminancia reducida, sin
  animación): la jerarquía funciona en un solo color por tamaño, peso y forma.
- «Reducir transparencia» y «Aumentar contraste»: el dato ya va en opaco; con
  contraste alto, tokens HC, punteado de 2 pt y canto de la vía más oscuro.

### 5.7 Animación

≤ 2 s y solo al actualizarse: `numericText(countsDown: true)` en la cifra, la
vía que aparece (escala 0,3 → 1 con muelle de 0,7 s + un halo que se apaga) y
la franja de la expandida; nada en bucle, nada en siempre activa, fundido con
«Reducir movimiento».

### 5.8 Botones, enlaces y tamaño del estado

- «Parar»: `Button(intent: StopTripIntent())`, solo en la de bloqueo y la
  expandida (iOS no deja botones en la compacta ni en la mínima). Bloqueado,
  pide Face ID; en CarPlay no hay botones.
- Un `widgetURL` por jerarquía y `Link` por fila en el mediano y por tramo en
  el grande (§6).
- `ContentState` < 1,5 KB con 3 salidas y las variantes del destino (tope de
  4 KB): nada de avisos enteros, solo nivel.
- Dynamic Type: `.xLarge` como tope en la actividad y la isla, `.xxLarge` en
  los widgets (tamaño fijo); lo demás cae por prioridad.

---

## 6. A dónde lleva tocar cada pieza

La app los recibe en `onOpenURL` (esquema `trajet://`, el mismo del QR).

| Pieza | Enlace |
|---|---|
| Live Activity (bloqueo, compacta, mínima, expandida) | `trajet://ruta/{route_id}?tramo={seq}` (la ruta y el tramo que toca, arriba) |
| · con la línea cortada y sin salidas | `trajet://ruta/{route_id}/alternativas` |
| · servidor sin clave | `trajet://ajustes/servidor` |
| · terminada | `trajet://ruta/{route_id}` |
| Widget pequeño | `widgetURL` como la actividad; entrada final → `trajet://tablero` (abre y refresca) |
| Widget mediano | `widgetURL` del tramo; `Link` por fila → `trajet://ruta/{route_id}?tramo={seq}&salida={jid}` |
| Widget grande | `widgetURL` de la ruta; `Link` por tramo → `trajet://ruta/{route_id}?tramo={seq}` |
| Circular, rectangular, en línea | un solo destino: `trajet://ruta/{route_id}?tramo={seq}` |

En el laboratorio, «Ver enlaces y áreas táctiles» pinta el enlace de cada
pieza y los 44 pt de «Parar».

---

## 7. La función de abreviado de destinos

`abreviar(nombre)` (`app.js`, también `TrajetLA.abreviar`) devuelve las
variantes **de la más completa a la más corta, sin cortar nunca una
palabra**. La app las calcula y las mete en el `ContentState` y en la caché;
la vista se queda con la primera que cabe (`ViewThatFits` con un `Text` por
variante y `lineLimit(1)`) y, si no cabe ninguna, quita el destino (en un
tramo con un solo sentido ya lo dice la ruta; con destinos mezclados, R24, el
destino corto va en cada fila).

1. Completo, normalizado (espacios, guiones largos).
2. Compactar sin perder nada: « - » → «-», fuera paréntesis, fuera «Paris »
   delante de otro nombre y «Gare » delante de un nombre propio («Gare de
   Lyon» y «Gare du Nord» se quedan: «Lyon» o «Nord» solos confunden).
3. Diccionario de la señalética, en palabras enteras (también dentro de un
   compuesto): Saint → St, Sainte → Ste, Porte → Pte, Place → Pl., Pont → Pt,
   Château → Chât., Université → Univ., Aéroport → Aérop., Charles de Gaulle →
   CDG, Avenue → Av., Boulevard → Bd, Faubourg → Fg, Terminal → T.
4. La parte principal de un nombre doble SNCF («A - B» → «A»).
5. Alias corto conocido (cómo se dice en el andén): Saint-Denis Pleyel →
   Pleyel, Aéroport Charles de Gaulle 2 TGV → CDG 2, Saint-Rémy-lès-Chevreuse →
   St-Rémy, Mantes-la-Jolie → Mantes, Pont de Bezons → Bezons…
6. Nada.

| Nombre | Variantes |
|---|---|
| Ermont - Eaubonne | Ermont - Eaubonne · Ermont-Eaubonne · Ermont |
| Gare Saint-Lazare | Gare Saint-Lazare · Saint-Lazare · St-Lazare |
| Saint-Denis Pleyel | Saint-Denis Pleyel · St-Denis Pleyel · Pleyel |
| Aéroport Charles de Gaulle 2 TGV | … · Aérop. CDG 2 TGV · CDG 2 |
| Pont de Bezons | Pont de Bezons · Pt de Bezons · Bezons |
| Gare de Lyon | Gare de Lyon (sin variantes) |

Cómo se usa en A:

- **Prioridad por escalón** en las filas con varias piezas (`fitRows`): el
  destino se abrevia pronto pero **desaparece tarde**; antes cae la palabra
  «perturbada» (queda ⚠) y se acorta «servidor sin clave ·» → «sin clave ·».
- **Un solo nivel por widget** (`fitGroups`): si la cabecera necesita
  «Ermont», las filas del mediano dicen «Ermont» aunque cupiera más (nada de
  «CDG 2» junto a «Aérop. CDG 2 TGV»).
- La auditoría del laboratorio (`lab.audit()`) recorre **264 casos** (22
  escenas × 3 iPhone × texto normal y AX3 × cifra de la app y del sistema) y
  lista lo que se ha quedado sin texto o desborda. Resultado: **ningún recorte
  ni desborde**; solo las caídas previstas (palabras de estado que dejan su
  símbolo, «sale 12:56» que cae antes que el retraso). Incluye los nombres
  largos del revisor (RER B a «Aéroport Charles de Gaulle 2 TGV» desde
  «Châtelet - Les Halles», N145 a «Saint-Rémy-lès-Chevreuse»).

---

## 8. Qué se descartó de B y de C

**B · Tablero** (se queda en el laboratorio tal cual):

- La cifra en baldosas pequeñas: el widget pequeño volvía a tener los minutos
  a unos 30 pt y la compacta apilaba cifra y vía a 10–12 pt.
- La cabecera con la parada de subida («Gare Saint-Lazare»), que se lee como
  destino.
- El destino casi del tamaño de la cifra.
- Todo a contorno en el modo acentuado (la vía real deja de ser una caja llena).
- Se tomó: destino por fila con mezcla, fila de transbordo con la vía del
  enlace, «Parar» siempre activo.

**C · Fases** (se queda tal cual):

- La baldosa derecha que cambia de significado (vía, luego, sale, transbordo).
- El mismo rojo para «Corre» y para «Sin circulación».
- El ritmo «Anda / Corre», estático (se queda viejo congelado y en widgets) y
  con «Anda» a 1,4:1 en la expandida.
- Recortes reales («hace 5 min» en el pequeño con aviso; «21» → «2»).
- Se tomó: la franja de vía a lo ancho para la alerta y el «90 %».

B y C **no** tratan las escenas nuevas de la 2B.4 (cancelado, cambio de vía,
sin clave…): las ven con los mismos datos, pero su diseño es el de la 2B.3.

---

## 9. Cómo verlo en el laboratorio

```powershell
node design-lab/shared/servidor.js          # PORT=7797 (o $env:PORT=7798 si está ocupado)
```

- <http://localhost:7797/b-cristal-v2/>: arriba **A ✓ / B / C**, «Las tres»
  (la misma pieza de las tres en cada fila), **«Viva / congelada»** (solo A) y
  **«Casos límite»** (solo A); dispositivo SE / 16 / 16 Pro Max; estado de la
  isla y «▶ Alerta».
- Panel de la derecha: **escenas de un toque** (las de la tabla del §4),
  trayecto, **Cifra** (app / sistema / iOS 17), aspecto de iOS (inicio en
  color / tintado / transparente, acentuado calado / contorno, texto grande /
  xLarge / AX3, reducir transparencia, aumentar contraste, siempre activa,
  StandBy de noche, ver enlaces y áreas táctiles), claro / oscuro, reloj.
- Por URL (capturas): `v=A|B|C`, `view=lamina|comparar|congelada|limites`,
  `device=se|i16|max`, `scene=<id>`, `theme`, `tint=full|tinted|clear`,
  `rt=1`, `num=app|sys|ios17`, `dt=L|XL|AX3`, `hc=1`, `aod=1`, `sb=1`,
  `acc=calado|contorno`, `hits=1`, `fz=12:55:40` (hora a la que la app dejó
  de escribir en «Viva / congelada»), `t=12:50:00`, `speed=60`,
  `island=compact|expanded|minimal`, `capture=1`.
- En la consola: `lab.set({...})`, `lab.audit()`, `lab.modelA()`,
  `TrajetLA.abreviar('…')`.
- Capturas: `node design-lab/b-cristal-v2/plan-capturas.mjs` (solo A +
  comparar + GIF; `--todas` para rehacer también B y C) y
  `node design-lab/tools/capturar.mjs design-lab/b-cristal-v2/plan-capturas.json`.
  Cero errores de consola.

---

## 10. Lo que la FASE 3 tiene que comprobar primero

1. **Las cadenas exactas en español** en el simulador: `Text(timerInterval:)`,
   `.timer(countingDownIn:maxFieldCount:1, maxPrecision: .seconds(60))`
   (hipótesis H1: el número suelto), `TimeDataSource.durationOffset(to:)` con
   `.units(allowed: [.hours, .minutes], width: .narrow)`, y el redondeo frente
   a `minutes` del servidor. Con eso se fija la versión de la cifra de los
   widgets (H1 o una talla) y se ajusta la talla de la de una talla.
2. **El calado** (`compositingGroup` + `blendMode(.destinationOut)`) en el
   modo acentuado y en vibrante; si no se pinta en la extensión, el contorno.
3. **La escritura local cada minuto** con el iPhone bloqueado en modo
   trayecto: cuántas se pierden y cuánto tarda en saltar `staleDate`.
4. `ProgressView(timerInterval:)` en el circular y en siempre activa (el fallo
   del 100 %).
5. Medir en el simulador los tamaños marcados como estimación (SE, 16 Pro Max)
   y la actividad con Dynamic Type al tope.
