# Ajustes de B «Cristal» al pasarlo a nativo

Revisión de `design-lab/b-cristal/` (con `design-lab/shared/`) contra las
reglas R1–R13 y R14–R62 de `docs/reglas.md`, hecha leyendo el código y con
capturas del laboratorio (390 × 844, claro y oscuro, escenarios de vía real /
probable / sin vía, aviso traduciendo, línea cortada, sin conexión, tren en el
andén, bus a 1h46 y letra grande). Cada ajuste dice **qué regla**, **qué falla
en B** y **cómo se hace en SwiftUI**. Las piezas nativas están descritas en
`docs/diseno/sistema.md` (§ entre paréntesis).

Fuera de alcance: la Live Activity y los widgets de B (se rediseñan en la
FASE 2B) y el panel del servidor (web, FASE 1).

---

## 1. Ajustes (por orden de importancia)

| # | Regla | Qué falla en B | Cómo se hace en SwiftUI |
|---|---|---|---|
| A1 | R1 · encargo 3.1 | Las tarjetas de tramo (`.card`) son **translúcidas con desenfoque**: las fichas 2.ª–4.ª, con sus minutos y su vía, quedan encima de cristal. La píldora «en directo · hace 10 s» va sobre el mapa sin fondo. | Tarjetas **opacas** (`.cardBackground()`: `surface` + filete + sombra suave). El cristal solo en controles (`.cristal(...)`). La píldora de estado en una cápsula de cristal (opaca con «Reducir transparencia») (§6.1, §7.9). |
| A2 | R1 · 3.1 (AA/AAA) | Contrastes por debajo de AA medidos con el script: `--ink-3` 3,8:1 en claro y 3,0:1 sobre las fichas en oscuro; `--warn` como texto 2,0:1 en claro y **2,1:1 dentro del billete blanco** en oscuro («+2 min»); `--bad` como texto 3,9:1 y blanco sobre `--bad` 4,4:1; punto `--ok` 2,1:1 en claro; `--accent` como texto 3,3:1 y blanco sobre `--accent` 3,7:1. | Paleta corregida y comprobada en cada ejecución de `tokens.mjs`: `ink3` recalibrado; tokens de **texto** separados (`warnText`, `badText`, `okText`); `ticketWarn` para el billete; `accent`/`accentFill` más profundos; `bad` un punto más oscuro; canto `viaEdge` (§3.3, §3.4). |
| A3 | R2 · 3.2 | La vía nueva aparece y late, pero sin **háptica** (es web), y sigue latiendo con el tablero **sin conexión** (el escenario «offline» congela la hora y la vía conserva `is-new`). | `.transition(.scale(0.3).combined(with: .opacity))` + `.viaPulse(isActive:)` + `.haptic(.platformPublished, trigger:)`, solo con dato vivo y solo en la primera salida de cada tramo; nada de latidos con el tablero apagado (§7.4, §9.5). |
| A4 | R9 · R19 · paleta | «Sin conexión» es un banner **amarillo `--via`**: el amarillo deja de significar «vía confirmada». El tablero **no se apaga** con el dato viejo (R19 pide apagarlo entero). Solo hay un estado («Sin conexión»): no distingue dato viejo, red caída, error del servidor ni servidor sin clave. | Píldora con estados (en directo, degradado, dato viejo, sin conexión, error del servidor por `error.code`, servidor sin clave) en opaco con canto `warn`, nunca amarilla; el contenido se apaga con `.opacity(0.55).saturation(0.2)` animado 0,45 s (§7.1, §7.9). |
| A5 | R10 | En las fichas, la vía probable ocupa todo el ancho («probable 21 90 %»). En la isla compacta de B la probable es «¿21?» sin la palabra (eso lo resuelve 2B). | Ficha: «probable 21» sin porcentaje (va a VoiceOver y al detalle). Si no cabe, se quita el % antes que la palabra (`ViewThatFits`). Nunca «Vía» en la probable ni punteado en la real; el punteado queda reservado a «probable» (§7.4). |
| A6 | R3 | Decide si hay vía con una expresión sobre `line_mode` (`/rer\|transilien\|ter\|train/`), distinta de la de la app v1 y de la del servidor. | Usar `platform_expected` de `BoardLegV1`, que calcula el servidor. Si es `false`, ni vía ni hueco aunque llegue `guess` (§7.4). |
| A7 | R1 · 2B («nunca cortado a mitad de palabra») | El destino del billete va a una línea con puntos suspensivos: con la vía probable al lado sale «Ermont - …». | `lineLimit(2)` + `minimumScaleFactor(0.85)`; `ViewThatFits` en la columna de la vía; con tamaños AX, billete a dos filas con `AnyLayout` (§4.4, §7.2). |
| A8 | R15 | «En andén» sale **a tamaño completo** (la regla `.tk-num .num` pisa a `.num[data-word]` por especificidad) y parte el billete en dos líneas enormes; además los metadatos repiten «en el andén». | `DepartureMoment.numberScale` = 0,5 para «En andén» en una línea; billete verde (`ok` + `atStopInk`, 7,8:1); sin repetir en metadatos; sin ritmo (§4.2, §7.2). |
| A9 | R47 | No hay densidades: con 5–6 tramos el tablero es una lista muy larga y la cifra no se adapta. | `BoardDensity(legCount:)`: cifra 56/48/40 pt y fichas sin segunda línea en compacto (§4.3). |
| A10 | R24 | Las fichas nunca dicen el destino, aunque el tramo mezcle destinos; la cabecera pone `to_name` o el primer sentido y nunca «todos los sentidos». | Destino obligatorio en billete y fichas cuando `directions` está vacío y hay destinos distintos; cabecera «todos los sentidos» en ese caso (§7.3, §7.8). |
| A11 | R25 | Tramo sin salidas: «Sin próximos pasos / servicio interrumpido / nada anunciado ahora mismo». | «Sin circulación» (interrumpida, `nosign`) o «Servicio finalizado» (`moon.zzz`) + «no hay más salidas»; sin punteado (§7.8). |
| A12 | R26 · notas FASE 1 | No hay errores de estación en el pie ni tramo que conserve sus últimas salidas si su estación cae. | Pie con hasta 3 `errors`; tramo caído con sus últimas salidas buenas y su antigüedad (§7.1, §7.8). |
| A13 | R29 · R30 · R6 | Alternativas: botón **«Usar hoy» que no existe en la API**; sin «Buscar de todas formas» (`force`) cuando no hay opciones; minutos totales sin «1h02»; las horas vienen ya formateadas en los datos de prueba, pero la API las manda crudas de Navitia (`YYYYMMDDTHHMMSS`). | Quitar «Usar hoy»; estado sin opciones con «Buscar de todas formas»; `Fmt.minutes` en totales; convertir la hora de Navitia a «HH:MM» (R56) (§7.13). |
| A14 | R56 · datos | Estadísticas: «128 días con datos» (`overall.n` son consultas), «24 días como peor línea» (`by_line.n` son filas del historial, no días), «peor día» (`max_delay` es el retraso máximo); decimales con punto («3.4»); meses abreviados («sep 2026»); «84 %» se parte en dos líneas. | «consultas», «N veces la peor», «retraso máximo»; coma decimal con `FormatStyle` en `es_ES`; «septiembre 2026»; espacio no separable en el porcentaje (§7.16). |
| A15 | R52 | Áreas táctiles de menos de 44 pt: días del editor 38 px, segmentos ~30 px, botones pequeños 36 px, segmento pequeño de Ajustes. | Días de 44 pt; `Picker(.segmented)` del sistema; botones pequeños con `.hitTarget()` (§7.12, §7.15). |
| A16 | R35 · R36 | Etiquetas «Lunes a viernes» y «llegar a las 09:00» (las de la v1 y las reglas son «entre semana» y «llego 09:00»); en el editor, «Franja / Llegar a / Salir a». | Etiquetas de R35/R36 (`Routes.swift`); segmentado «Llego a / Salgo a / Franja» con «Llego a» por defecto (§7.15). |
| A17 | R34 | El planificador solo tiene «Salir ahora» + «Cambiar». | Segmentado «Llegar a / Salir a» (por defecto «Llegar a») + hora; la API solo entiende `arrival`/`departure` (§7.15). |
| A18 | R54 | No hay barra del próximo refresco. | `ProgressView(timerInterval:)` de 2 pt en la píldora de estado; quieta con «Reducir movimiento» (§7.9). |
| A19 | R7 · R46 | El pie dice siempre «se refresca cada 30 s»; en Ajustes la barra de cuota es «lo que queda» y falta «se reinicia a medianoche UTC». | El ritmo sale de `server.refresh_hint_s` (nunca < 30); cuota con `used`/`cap` y color por nivel, nombres «Tablero / Avisos / Buscador» y el aviso de medianoche UTC (§7.1, §7.15). |
| A20 | R61 | Las direcciones del servidor en Ajustes son texto fijo; no hay «Restablecer». | Campos editables que se guardan al escribir y «Restablecer direcciones» (además de «Emparejar de nuevo») (§7.15). |
| A21 | R37 · F8 | La cabecera dice «La que toca ahora» / «Ruta» y no deja cambiar de ruta. | El nombre es un `Menu` («La que toca ahora» + rutas guardadas); rótulo «La que toca ahora» si `auto_selected`, «Ruta elegida» si la fijó el usuario (§7.1). |
| A22 | R27 · R28 · R49 | El aviso de la tarjeta enseña todos los mensajes (hasta 3); no hay detalle del tramo, así que faltan el español y el francés juntos (R27), las obras con fecha futura (R28) y la explicación de la vía probable (R49). | 2 mensajes en la tarjeta; hoja de detalle del tramo (§7.7, §7.13). |
| A23 | R14 | Las fichas solo enseñan retrasos positivos; el adelanto («−1 min») desaparece. | Adelanto en `ink2` en fichas y billete (§7.2, §7.3). |
| A24 | R12 · R57 | `line.ink` usa el umbral 0,45 de la v1: 21 de 59 colores quedan por debajo de 4,5:1 (naranja de prueba a 2,5:1); no usa el texto oficial de IDFM. | `LineColor.badge(line:officialText:)`: oficial si ≥ 4,5:1; si no, el mayor contraste de negro/blanco (≥ 4,58:1). Anexo A de sistema.md (§3.6, §7.5). |
| A25 | R51 | Con «Reducir movimiento» se matan todas las animaciones CSS: bien para latidos y ondas, pero la vía nueva pierde su señal y no queda nada que diga «nueva». | Anillo fijo de 2 pt mientras la vía es nueva; el resto, fundidos de 0,2 s o nada (§9.6). |
| A26 | 3.1 (Dynamic Type) | Con «letra grande» desaparecen las etiquetas de las pestañas; las cifras escalan sin tope (rem). | Pestañas del sistema con etiqueta (y visor de contenido grande); cifras con `@ScaledMetric` y tope (§4.2, §7.11). |
| A27 | R53 · R44 · 1.5.1 | No hay estados de carga, vacío, error sin caché, ruta borrada (404) ni **servidor sin clave de PRIM** (el encargo lo pide «diseñado, no un error genérico»). | §7.18 y §7.9. |
| A28 | 3.2 (emparejar) | Emparejar solo tiene el camino feliz; «Escribir la dirección a mano» lleva a Ajustes. | Estados de error (código que no vale, demasiados intentos, sin servidor, sin cámara) y formulario manual (direcciones + código) (§7.17). |
| A29 | R55 | No hay avisos efímeros. | Cápsula de cristal 2,4 s + anuncio de VoiceOver (§7.18). |
| A30 | R32 · R33 | En el editor, un tramo sin sentido dice «cualquier sentido» en gris; al guardar desde el planificador no se avisa de los tramos sin sentido. | «todos los sentidos» en `warnText` con icono y el texto de R32; aviso de `without_direction` al guardar (§7.15). |
| A31 | R8 (VoiceOver) | El francés lleva `lang="fr"` (bien) y cursiva. | En nativo, `AttributedString` con `languageIdentifier = "fr"` para que VoiceOver lo lea en francés; el cambio a español con `.contentTransition(.opacity)` (§7.7). |
| A32 | R1 (mapa) | El mapa base se retiñe con MapLibre; MapKit no lo permite. | `MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)`; el color lo ponen los trazados (§3.7). |
| A33 | — (diseño) | Radios no concéntricos (tarjeta 28 / relleno 14 / billete 22 / fichas 16). | Tarjeta 30, relleno 12, hijos 18 (`Metrics.Radius.concentric`) (§5.2). |
| A34 | — (alcance) | Ajustes de B trae interruptores nuevos («Pantalla encendida en el tablero», «Vibrar cuando aparece la vía»), un selector «Claro / Oscuro» y una sección «Prototipos». | «Vibrar cuando aparece la vía» se queda (controla la háptica de A3). «Pantalla encendida» es una función nueva (`isIdleTimerDisabled` mientras se mira el tablero): decisión de la FASE 3. La app sigue el tema del sistema; el selector, opcional. «Prototipos» fuera. |
| A35 | — (navegación) | B oculta la barra de pestañas en el mapa, alternativas, editor y emparejar, y reimplementa push y hojas con CSS. | Pushes, hojas y barra de pestañas del sistema; el mapa es una pestaña (la barra se queda; en iOS 26 se minimiza al desplazar si se quiere). Zoom de iOS 18 de tarjeta a detalle y de tablero a mapa (§9.3). |

---

## 2. Regla por regla

✅ = B lo cumple y se conserva · ⚠️ = hay ajuste (A…) · — = no depende del
diseño (modelo, red, servidor o empaquetado).

### R1–R13 (encargo)

| Regla | Estado | Nota |
|---|---|---|
| R1 · uso real, contraluz | ⚠️ A1, A2, A7, A26, A32 | La jerarquía de B es buena (cifra primero, billete opaco); fallan las tarjetas translúcidas y algunos contrastes. |
| R2 · vía en el 17 %, destacada | ⚠️ A3 | Sin hueco si no hay vía (bien); falta la háptica y no debe latir con el dato viejo. |
| R3 · metro/bus/tranvía sin vía | ⚠️ A6 | — |
| R4 · sin hora teórica no hay retraso | ✅ | El billete exige `aimed_at` y `delay ≠ 0`. |
| R5 · longitud sí, ocupación no | ✅ | «corto/largo» con icono; ningún dato de ocupación. |
| R6 · «1h46» | ⚠️ A13 | Bien en billete y fichas; mal en totales de alternativas y planes. |
| R7 · cuota y bucle de 30 s | ⚠️ A19 | El texto del pie tiene que salir de `refresh_hint_s`. |
| R8 · avisos en francés, «traduciendo» | ✅ · A31 | Francés en cursiva con «traduciendo» y sustitución. |
| R9 · nunca se borra la pantalla | ⚠️ A4, A12, A27 | — |
| R10 · probable ≠ real | ✅ · A5 | Caja sólida «Vía» frente a punteado «probable» en el tablero. |
| R11 · acierto solo del servidor | ✅ | «el servidor se puntúa solo»; nadie pregunta. |
| R12 · colores de línea con contraste | ⚠️ A24 | — |
| R13 · PreviewData como banco | ✅ | `data.js` calca `PreviewData`; los escenarios que faltan en `PreviewData` están en `inventario-funcional.md` F79. |

### R14–R62 (app)

| Regla | Estado | Nota |
|---|---|---|
| R14 · retraso solo si ≠ 0, con signo | ⚠️ A23 | — |
| R15 · «En andén» ≠ «ya» | ⚠️ A8 | La lógica está bien (`moment`); falla la maqueta. |
| R16 · ritmo | ✅ | «Corre / Anda / Con calma», solo en el billete. `Pace.color` pasa a tokens (§7.6). |
| R17 · antigüedad desde el teléfono | — | Modelo. B la simula. |
| R18 · «hace N s/min/h» | ✅ | `fmt.age`. |
| R19 · dato viejo apaga el tablero | ⚠️ A4 | — |
| R20–R23 · caché, decodificación, identidad | — | Modelo (B usa `jid` como identidad, bien). |
| R24 · destinos mezclados | ⚠️ A10 | — |
| R25 · tramo vacío | ⚠️ A11 | — |
| R26 · fallo parcial al pie | ⚠️ A12 | — |
| R27 · aviso en su tramo, bilingüe en detalle | ⚠️ A22 | En su tramo: bien. |
| R28 · obras futuras aparte | ⚠️ A22 | — |
| R29 · alternativas solo al pedirlas | ✅ | Solo al tocar el botón. |
| R30 · alternativa que no sirve | ✅ · A13 | Atenuada con «pasa por la línea cortada»; falta `force`. |
| R31 · buscadores 2 caracteres / 350 ms | — | Lógica. |
| R32 · el sentido se elige | ⚠️ A30 | — |
| R33 · tramos sin sentido al guardar | ⚠️ A30 | — |
| R34 · llegar a ≠ salir a | ⚠️ A17 | — |
| R35 · horario como se definió | ⚠️ A16 | — |
| R36 · días | ⚠️ A16 | — |
| R37 · la ruta que toca la decide el servidor | ⚠️ A21 | — |
| R38 · franja derivada | — | Servidor. |
| R39–R43 · refresco, historial, rutas, direcciones, timeouts | — | Red y stores. |
| R44 · 404 de ruta borrada | ⚠️ A27 | Estado diseñado. |
| R45 · permiso de red local | — | `Info.plist`. |
| R46 · cuota visible | ⚠️ A19 | Pie bien; Ajustes a corregir. |
| R47 · densidad por tramos | ⚠️ A9 | — |
| R48 · minutos primero, tabulares, transición | ✅ | Cifras tabulares y billete primero; en nativo `contentTransition(.numericText())`. |
| R49 · la probable se explica | ⚠️ A22 | — |
| R50 · VoiceOver: una frase por salida | — | No aplica a la web; frases en §7.2 y §7.4. |
| R51 · reducir movimiento | ⚠️ A25 | — |
| R52 · 44 pt | ⚠️ A15 | — |
| R53 · estados no felices | ⚠️ A27 | — |
| R54 · barra del próximo refresco | ⚠️ A18 | — |
| R55 · avisos efímeros | ⚠️ A29 | — |
| R56 · formatos en español | ⚠️ A13, A14 | — |
| R57 · hex tolerante y gris de reserva | ✅ · A24 | `hexRGB` tolera «#» y 3 dígitos; el nativo acepta además «0x», 4 y 8 dígitos. |
| R58–R60 · bundle id, XcodeGen, IPA lite | — | Empaquetado. |
| R61 · direcciones editables | ⚠️ A20 | — |
| R62 · líneas ordenadas por el servidor | — | Lógica. |

---

## 3. Lo que se conserva tal cual de B

- El concepto: mapa arriba que se funde con el fondo, cabecera de cristal,
  tarjetas por tramo con el billete opaco y las fichas en tira horizontal,
  barra de pestañas flotante con la búsqueda aparte.
- La paleta neutra en OKLCH (fondo, tintas, cristal), el amarillo de la vía,
  los estados y el azul (con las correcciones de A2).
- El billete que **invierte el tema** (blanco en oscuro, negro en claro) y el
  verde de «En andén».
- La vía: caja sólida «Vía 21» con aparición de muelle y 5 latidos; recuadro
  punteado «probable 21 · 90 %».
- La tipografía: cifras redondeadas muy gruesas con dígitos tabulares; texto
  en SF Pro; rótulos en minúscula.
- El muelle (`cubic-bezier(.34, 1.45, .64, 1)` → `dampingFraction` 0,65), la
  curva «ease» y los tiempos (0,35 / 0,4 / 0,5 / 0,55 / 0,7 / 0,8 s).
- El distintivo: radio al 30 %, letra al 50 %, filete inferior, crece a lo
  ancho con códigos largos.
- El billete a dos filas con letra grande.
