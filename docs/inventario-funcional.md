# Inventario funcional de la app iOS actual (v1)

Lista exhaustiva de lo que hace hoy la app, para que los verificadores
comprueben que la v2 no pierde nada. Cada funcionalidad lleva un id estable
(**F1…**) para marcarla luego como «conservada», «cambiada (por qué)» o
«retirada (por qué)».

- Código analizado: `Trajet/` en la rama `rewrite-v2` (commit `942ffbe`).
  Rutas de fichero sin prefijo relativas a `Trajet/`; las del servidor llevan
  `trajet-server/app/` (código de producción 0.3.0).
- **La app nunca ha compilado** (ver `docs/ios-reutilizable.md`): todo lo que
  sigue sale de leer el código, no de usarla. Donde el código hace algo
  distinto de lo que dicen sus comentarios o el README, se marca como
  **Rareza** para que la v2 decida si lo conserva o lo corrige.
- Las reglas citadas (R…) están en `docs/reglas.md`.

---

## 1. Marco general

**F1 · Contenedor único.** Un `AppModel` con una sola `ServerConfig`, un solo
`TrajetAPI`, un `BoardStore` y un `RoutesStore`, creado en `TrajetApp` y
pasado por el entorno (`TrajetApp.swift:4-15`, `Store/RoutesStore.swift:67-85`).
Al crearse, el `BoardStore` carga el último tablero de disco
(`Store/BoardStore.swift:36-39`).

**F2 · Apariencia.** Tema oscuro forzado y tinte blanco
(`TrajetApp.swift:11-13`, `Info.plist:32-34`); pantalla de arranque con el
color `LaunchBackground` #0a0a0c (`Info.plist:26-30`,
`Assets.xcassets/LaunchBackground.colorset`); acento blanco
(`AccentColor.colorset`); icono único de 1024 px sin canal alfa
(`AppIcon.appiconset`).

**F3 · Dispositivo.** Solo iPhone (`project.yml:15`), solo vertical
(`Info.plist:36-39`), nombre visible «Trajet», región de desarrollo `es`
(`Info.plist:5-8`), versión 1.0 (1) (`project.yml:31-32`).

**F4 · Barra de pestañas propia.** Píldora flotante con cuatro pestañas:
Tablero (`clock.fill`), Rutas (`map.fill`), Buscar (`magnifyingglass`),
Historial (`chart.bar.fill`) (`Views/RootView.swift:4-26`). Solo la activa
lleva texto; cada botón mide al menos 48 × 48 pt; al cambiar, animación
`snappy` de 0,28 s y háptica ligera (`RootView.swift:74-127`). Arranca en
Tablero (`RootView.swift:32`) y no recuerda la última pestaña.

**F5 · Cambiar de pestaña destruye la anterior.** Las pantallas van en un
`switch` (`RootView.swift:39-46`): al cambiar de pestaña se pierde su estado
local (origen, destino y resultados del planificador, por ejemplo).

**F6 · Ajustes en hoja.** Se abren desde el botón de ajustes del tablero
(`Views/Board/BoardView.swift:100-108`) como hoja (`RootView.swift:52-54`).

---

## 2. Tablero

**F7 · Ruta automática o fijada.** Sin ruta fijada, el tablero pide
`/api/board` sin `route_id` y el servidor elige (F66). El rótulo dice «Ruta
activa» si la eligió el servidor (`auto_selected`) y «Ruta elegida» si la
fijó el usuario (`BoardView.swift:93`).

**F8 · Selector de ruta en el título.** El título es un menú
(`BoardView.swift:115-148`): «La que toque ahora» (vuelve a la automática) y
todas las rutas guardadas; la que se ve lleva una marca. Elegir una la fija y
refresca al momento (`Store/BoardStore.swift:88-94`). El título parte el
nombre por «→» y pinta la flecha en gris (`BoardView.swift:194-219`); sin
ruta, «Trajet». La lista sale de `RoutesStore`, que el tablero carga una vez
al aparecer (`BoardView.swift:35`).

**F9 · Píldora de antigüedad** (`BoardView.swift:221-255`). Texto
«hace N s/min/h» (F67). Tres estados:
- sin error y dato vivo: icono `dot.radiowaves.up.forward`, verde;
- dato viejo (F11): icono `clock.badge.exclamationmark`, rojo;
- con error en el último refresco: icono `wifi.slash`, rojo, y «· sin conexión».

VoiceOver: «Dato de hace …» o «Sin conexión. Dato de hace …».
**Rareza:** cualquier error pone «sin conexión», también un 404 o un 502 con
el servidor respondiendo (`lastError` no distingue, `BoardStore.swift:82-85`).

**F10 · Barra del próximo refresco** (`BoardView.swift:257-283`). Línea de
2 pt arriba del todo que se llena de forma lineal hasta `nextRefreshAt`; más
intensa mientras carga; con «Reducir movimiento» aparece llena. Oculta a
VoiceOver.

**F11 · Tablero viejo apagado.** Si `stale` del servidor o antigüedad > 90 s,
todo el tablero baja a opacidad 0,5 y gris 0,45 con animación de 0,45 s
(`BoardView.swift:83-86`, `Model/Board.swift:331-334`). La antigüedad se
recalcula con un reloj propio cada 5 s (`BoardView.swift:12-13`, `27-34`).

**F12 · Tirar para refrescar** (`BoardView.swift:82`): refresco inmediato, sin
límite mínimo entre tirones.

**F13 · Tramos encadenados.** Por cada tramo, el distintivo de línea fuera de
la tarjeta y, debajo, un hilo de 5 pt que degrada del color de ese tramo al
del siguiente (el último no lleva hilo) (`Views/Board/LegCardView.swift:7-49`).

**F14 · Cabecera del tramo** (`LegCardView.swift:71-100`): parada de subida
(1 línea); debajo «dirección X · Y» (sentidos guardados, o `to_name` si no
hay ninguno) o, si no hay nada de eso y el tramo mezcla destinos, «todos los
sentidos»; a la derecha, icono del modo (F68).
**Rareza:** si un tramo no tiene sentidos pero sí `to_name` (la parada de
bajada), la cabecera dice «dirección <parada de bajada>» y oculta «todos los
sentidos» aunque las salidas mezclen destinos (`Model/Board.swift:190-195`
frente a `197-201`).

**F15 · Aviso de perturbación dentro del tramo** (nivel ≥ 1)
(`Views/Board/DisruptionNotice.swift`): color de aviso (perturbada) o rojo
(interrumpida) y su icono; rótulo del estado en versales; hasta 2 mensajes,
en español si ya está la traducción y si no en francés (`Board.swift:128-133`);
botón «Buscar alternativa» (abre F25); chip «Traduciendo» con latido suave
mientras falte alguna traducción o `translating` sea cierto
(`Board.swift:136-140`).

**F16 · Tramo sin salidas** (`LegCardView.swift:104-127`): recuadro punteado
con «Sin circulación» (línea interrumpida, icono `nosign` rojo) o «Servicio
finalizado» (icono de luna), y «no hay más salidas». Los demás tramos siguen.

**F17 · Tira horizontal de salidas** (`LegCardView.swift:128-142`): tantas
salidas como mande el servidor (hoy hasta 4, `board.py:219`, `298`), con
desplazamiento que encaja en cada chip y sin indicadores.

**F18 · Chip de salida** (`Views/Board/DepartureChip.swift:51-186`):
- Momento: «En andén» si `at_stop`, «ya» si minutos ≤ 0, si no los minutos
  con formato (F67), con transición numérica; «min» detrás si < 60.
- Icono de ritmo (correr / andar / con calma, F68); en modo compacto solo en
  la primera salida.
- Segunda línea (no en modo compacto), en este orden: destino si el tramo
  mezcla destinos, retraso si existe y ≠ 0 (juntos con « · »); si no hay nada
  de eso, la longitud del tren; si tampoco, la hora prevista «HH:MM».
- Vía (F19) a la derecha tras un filete, solo en modos que la publican.
- La primera salida va destacada; las demás, atenuadas (opacidad 0,82).
- Densidad según el número de tramos (F20).

**F19 · Vía real, nueva y probable** (`Views/Board/PlatformBadge.swift`):
- Real: caja blanca sólida con «VÍA» y el número en negro.
- Recién aparecida (`platform_new`): caja amarilla con halo y latido (escala
  1,06, 0,65 s, 5 repeticiones) al aparecer, salvo «Reducir movimiento».
- Probable (`guess`, solo si no hay real): número + «PROBABLE» en gris, fondo
  casi transparente y borde punteado.
- VoiceOver: «Vía 11», «Acaba de salir la vía 11», «Vía 11 probable, 82 por
  ciento sobre 17 observaciones, por el número de tren».

**F20 · Densidad** (`DepartureChip.swift:8-44`): 1–2 tramos holgado (34 pt),
3–4 normal (30 pt), 5–6 o más compacto (26 pt, sin segunda línea, relleno
menor, vía compacta).

**F21 · VoiceOver del chip** (`DepartureChip.swift:164-185`): una frase con
momento, «hacia <destino>» si hay mezcla, «N minutos de retraso/adelanto»,
vía o vía probable con porcentaje, y longitud.

**F22 · Pie del tablero** (`BoardView.swift:166-191`): hasta 3 errores de
estación del servidor (`errors`) con icono, y «N llamadas hoy» si viene la
cuota de `stop-monitoring`.

**F23 · Estados de la pantalla** (`BoardView.swift:47-60`), en este orden:
1. Hay tablero y `empty: true` → «Todavía no hay ninguna ruta» y
   «Ve a **Buscar**, di de dónde a dónde vas y guarda el trayecto que uses de
   verdad…» (`BoardView.swift:318-337`).
2. Hay tablero con tramos → el tablero.
3. Está cargando → esqueleto de 3 tarjetas que parpadea
   (`BoardView.swift:287-316`).
4. Si no → «No se llega al servidor» + el error (o «Ni por la red de casa ni
   por Tailscale.») + botón «Reintentar» (`BoardView.swift:339-373`).

**Rareza:** una ruta con cero tramos cae en el caso 4 con el texto de «no se
llega» aunque el servidor haya respondido bien.

**F24 · Detalle del tramo** (tocar la tarjeta) (`Views/Board/LegDetailSheet.swift`):
hoja media/grande con «Cerrar». Cabecera con distintivo de 50 pt, parada y
«<modo> · dirección <sentido>». Si la línea está tocada: rótulo, cada aviso en
español (si lo hay) y en francés en cursiva, y «Además hay N aviso(s) de obras
con fecha futura, que no afectan a hoy.». Lista de salidas: momento, ritmo con
texto («corriendo», «andando», «con calma»), vía, explicación de la vía
probable («Sale por la 11 el 82 % de las veces (17 observaciones, por el
número de tren).») y etiquetas: destino, «sale HH:MM», retraso, longitud,
«tren N», «parado en el andén». Sin salidas: «La línea no está circulando.» o
«No quedan más salidas hoy.».
**Rareza:** la nota de obras futuras solo se ve si la línea ya está
perturbada (`LegDetailSheet.swift:18-20` envuelve `:95-100`), así que un
tramo normal con `planned > 0` nunca la enseña.

**F25 · Alternativas** (`Views/Board/AlternativesSheet.swift`). Se abre con
«Buscar alternativa» usando el id de la ruta del tablero
(`BoardView.swift:39-44`, `159`). Hoja «Alternativas» con «Cerrar»:
- cargando: indicador;
- error: pantalla «No se llega al servidor» con el mensaje y «Reintentar»;
- «Líneas tocadas»: código y estado de cada línea afectada, en rojo o ámbar;
- sin opciones: «El calculador no encuentra otro camino ahora mismo.» (si
  `needed`) o «Ninguna línea de esta ruta está tocada.», y el botón «Buscar de
  todas formas» (`force=true`);
- con opciones: «Tu ruta suele durar N min» y tarjetas con minutos totales,
  diferencia («+12 min», «igual de rápido»), transbordos, cadena de
  distintivos, «sale HH:MM · llega HH:MM» y, si no sirve, «No sirve: también
  pasa por una línea cortada» con la tarjeta atenuada.

**Rareza:** los minutos totales de alternativas y planes no usan el formato
«1h46» (`AlternativesSheet.swift:136`, `Views/Plan/PlanView.swift:227`).

---

## 3. Rutas

**F26 · Lista** (`Views/Routes/RoutesView.swift:12-71`, `130-196`): título
«Mis rutas»; cada tarjeta con nombre (2 líneas), insignia «ahora» si es la
`active_id` del servidor, «<días> · <horario>» (F69) y la cadena de
distintivos (o «sin tramos»).

**F27 · Carga.** Una vez al entrar (`loadIfNeeded`, `RoutesView.swift:46`) y
al tirar para recargar (`:45`). La lista es la misma que usa el selector del
tablero (R41).
**Rareza:** si la carga falla, `hasLoadedOnce` queda a `true`
(`RoutesStore.swift:25`), la lista vacía se pinta como «Aún no hay ninguna
ruta» y el error (`RoutesStore.lastError`) no se enseña en ningún sitio; el
selector del tablero se queda vacío hasta recargar a mano.

**F28 · Estado vacío** (`RoutesView.swift:96-109`): «Aún no hay ninguna ruta»
y «Empieza por **Buscar trayecto**…».

**F29 · Nueva ruta** (`RoutesView.swift:52-60`, `79-91`): botón «Nueva» →
diálogo «¿Cómo quieres crearla?» con «Buscar trayecto» (F47), «Montar a mano»
(F33) y «Cancelar», y el texto «Buscar va de una dirección a otra. A mano es
para cuando ya sabes el camino exacto.».

**F30 · Editar** tocando la tarjeta (`RoutesView.swift:23`).

**F31 · Menú contextual** (pulsación larga) (`RoutesView.swift:24-35`):
- «Ver en el tablero»: fija la ruta en el tablero (y lo refresca), **sin**
  cambiar de pestaña.
- «Borrar» (destructivo, sin confirmación): `DELETE`, la quita de la lista,
  aviso «Ruta borrada» e invalida el tablero; si falla, «No se ha podido
  borrar» (`RoutesView.swift:111-119`).

**F32 · Avisos efímeros** de 2,4 s abajo (`RoutesView.swift:121-127`,
`198-213`): «Ruta guardada», «Ruta actualizada», «Ruta borrada», «No se ha
podido borrar».

---

## 4. Editor de ruta a mano

**F33 · Campos** (`Views/Routes/RouteEditorView.swift:64-211`), título «Nueva
ruta» o «Editar ruta», «Cancelar» y «Guardar»:
- Nombre (ejemplo «Casa → Trabajo»).
- Días de uso: siete botones L M X J V S D de 46 pt, lunes a viernes por
  defecto; VoiceOver con el nombre del día y estado seleccionado
  (`RouteEditorView.swift:270-303`).
- Horario: segmentado «Llego a» / «Salgo a» / «Franja» (por defecto «Llego a»
  09:00). En franja, «Desde» y «Hasta» (07:00 y 10:00); si no, una hora y el
  texto de ayuda («La franja se calcula hacia atrás…» / «La franja va desde
  45 min antes hasta que llegas.»). Las horas se eligen con el selector
  nativo y se guardan «HH:MM» (`RouteEditorView.swift:305-335`).
- Itinerario: cada tramo con su distintivo, parada y «dirección …» o «todos
  los sentidos» en ámbar; botón para quitarlo (44 pt, «Quitar el tramo X»);
  botón punteado «Añadir el primer tramo» / «Añadir transbordo» (F36).

**F34 · Relleno al editar** (`RouteEditorView.swift:215-229`): al aparecer, si
es edición y aún no hay tramos, copia nombre, días, horario y tramos.

**F35 · Guardar** (`RouteEditorView.swift:231-267`). Activo solo con nombre no
vacío, al menos un tramo y un día. Cuerpo enviado (snake_case):
`name` (recortado), `origin_id`/`origin_name` = parada del primer tramo,
`dest_id` = parada del último tramo, `dest_name` = primer sentido del último
tramo o su parada, `days` ordenados, `time_from`, `time_to`, `time_mode`,
`time_at` (vacío en franja), `duration_min` (el de la ruta editada o 0) y
`legs` con los datos de línea, `from_id`/`from_name` = parada, `to_id` y
`to_name` vacíos y `directions`. `POST /api/routes` o `PUT /api/routes/{id}`;
después recarga la lista, aviso, invalida el tablero y cierra. El error se
enseña debajo.
**Rareza:** no se manda `position`, y el servidor la pone a 0 al crear y al
editar (`trajet-server/app/db.py:216`).

---

## 5. Montar un tramo (tres pasos)

**F36 · Paso 1, parada** (`Views/Routes/LegBuilderView.swift:58-123`): «¿Desde
qué parada?», buscador «Gare Saint-Lazare…» con espera de 350 ms y mínimo 2
caracteres; filas con nombre y ciudad; «Ninguna parada con ese nombre»; error
debajo.

**F37 · Paso 2, línea** (`LegBuilderView.swift:125-170`): título = parada;
líneas de `/api/stops/{id}/lines` en el orden del servidor, con distintivo,
nombre (o código) y modo. Si la llamada falla o viene vacía, usa las líneas que
trajo el buscador.

**F38 · Paso 3, sentido** (`LegBuilderView.swift:172-238`): título «Línea X»;
sentidos de `/api/stops/{id}/directions` con selección múltiple; cabecera
«Sentidos que circulan ahora» o «Ahora mismo no circula nada por aquí»; pie
«Si no eliges ninguno se enseñan todos los pasos de la línea, en los dos
sentidos.»; botón «Añadir el tramo». Un error aquí se traga y se ve como «no
circula nada».

**F39 · Navegación** (`LegBuilderView.swift:43-56`): «Cancelar» en el paso 1,
«Atrás» en los otros (deshace el paso).

---

## 6. Buscar (planificador)

**F40 · Formulario** (`Views/Plan/PlanView.swift:108-164`): «Origen» (punto
verde) y «Destino» (punto rojo) con «Sin elegir»; segmentado «Llegar a» /
«Salir a» (por defecto «Llegar a»); hora (por defecto 09:00); botón «Buscar
itinerarios» (52 pt), desactivado hasta tener origen y destino, con indicador
mientras busca.

**F41 · Buscador de sitios** (`Views/Plan/PlaceSearchView.swift:4-98`): hoja
«¿Desde dónde?» / «¿Hasta dónde?», buscador «Calle, parada o sitio…» (350 ms,
mínimo 2 caracteres), filas con icono por tipo (parada, dirección, sitio),
nombre y «tipo · ciudad»; «Nada con ese nombre»; error; «Cancelar».

**F42 · Resultados** (`PlanView.swift:55-69`, `220-264`): rótulo «Para llegar
a las HH:MM» o «Saliendo a las HH:MM»; tarjetas con minutos, «salida →
llegada», cadena de distintivos unidos por degradados y «<transbordos> · N min
andando»; texto «Toca el itinerario que uses de verdad para guardarlo como
ruta vigilada.». Sin opciones: «No hay ningún trayecto en transporte público
entre esos dos puntos a esa hora.». Error: texto rojo y resultados vaciados.
**Rareza:** el rótulo usa el criterio y la hora actuales del formulario, no
los de la búsqueda hecha.

**F43 · Guardar un itinerario** (`PlaceSearchView.swift:100-243`): tocar una
tarjeta abre «Guardar ruta» con la tarjeta, «Nombre» (por defecto «<origen> →
<destino>»), «Días de uso» (lunes a viernes) y la explicación («Se guardará
como «llego a las 09:00», y la franja se calculará con los 47 min que dura.»).
«Guardar» manda `POST /api/routes/from-plan` con `option` (la opción tal cual
vino) y `meta` (`name`, `origin_id`, `origin_name`, `dest_id`, `dest_name`,
`days`, `time_mode` arrival/departure, `time_at` = la hora, `time_from`
«07:00», `time_to` «10:00»); luego recarga las rutas.
- Sin tramos sin sentido: aviso «Ruta guardada», invalida el tablero y cierra.
- Con `without_direction`: se queda abierta con «Guardada, pero con un aviso»
  y la lista de líneas afectadas.

**Rareza:** en el segundo caso no se avisa al tablero ni se enseña el aviso
efímero, y «Guardar» sigue activo: pulsarlo otra vez crea otra ruta igual.

**F44 · Planificador dentro de Rutas** (`RoutesView.swift:67-70`,
`PlanView.swift:10`, `77-85`, `96-104`): misma pantalla sin título grande,
con «Buscar trayecto» en la barra y «Cerrar»; tras guardar, aviso y cierre
automático a los 2,4 s.

---

## 7. Historial

**F45 · Cifras grandes** (`Views/Stats/StatsView.swift:50-56`): «Consultas»
(`overall.n`) y «Retraso medio» (con coma decimal y «min»).

**F46 · Días con incidencia** (`StatsView.swift:58-90`): por mes, «agosto
2026», «11 de 21» y barra proporcional (mínimo 3 pt).

**F47 · La que más me falla** (`StatsView.swift:92-123`): código de línea,
«N incidencias» y retraso medio si > 0.

**F48 · Previsión del andén** (`StatsView.swift:127-179`): «Acierto» (o «—»),
«Andenes vistos», «Días aprendiendo»; si aún no hay previsiones, el texto «La
vía solo aparece en el 17 % de los trenes, así que hacen falta unos cuantos
días.»; «Cobertura en <ruta>» con, por tramo, «esta línea no publica vía» o
«N andenes · D días · P vías». La app no pregunta nunca si acertó (R11).

**F49 · Carga** (`StatsView.swift:44-45`, `183-195`): cada vez que se entra en
la pestaña y al tirar: `/api/stats?days=90` y después
`/api/platform-model` con el `route_id` que se ve en el tablero (si hay). Un
error de estadísticas se enseña; uno de la previsión se calla y oculta el
bloque.

---

## 8. Ajustes

**F50 · Direcciones** (`Views/Settings/SettingsView.swift:17-36`): «Red de
casa» y «Tailscale», con el valor de fábrica como ejemplo, teclado URL, sin
autocorrección ni mayúsculas. Se guardan al escribir (`:92-95`). Pie: «Se
prueban las dos, en este orden, y se recuerda la que responde…».

**F51 · Estado** (`SettingsView.swift:38-71`, `109-120`): al abrir y con
«Comprobar ahora» llama a `/api/health` y enseña «Conectado por» (red de casa
/ Tailscale / la dirección), «Servidor» (responde / con problemas), «Hora en
París», «Traductor» (modelo o «no disponible»), la cuota «N / 1000» de cada
endpoint con nombre («Tablero», «Avisos», «Buscador» o la clave) y «Último
error». Si falla, el error en rojo.
**Rareza:** el servidor devuelve siempre `ok: true` (`main.py:51`), así que
«con problemas» no sale nunca; `key_configured` se decodifica pero no se
enseña.

**F52 · Restablecer direcciones** (`SettingsView.swift:73-79`): destructivo,
sin confirmación; vuelve a los valores de fábrica y olvida la preferida. Pie:
«La cuota es de 1000 llamadas al día por endpoint y se reinicia a medianoche
UTC. El tablero se refresca cada 30 s y solo mientras lo estás mirando.».
**Rareza:** editar una dirección no olvida la preferida
(`Net/ServerConfig.swift:34`, `61-65`): la dirección antigua se sigue probando
la primera mientras responda.

---

## 9. Red

**F53 · Endpoints y cuándo se llaman.**

| Endpoint | Parámetros / cuerpo | Cuándo | Dónde | ¿Gasta PRIM? (servidor) |
|---|---|---|---|---|
| `GET /api/board` | `route_id` solo si hay ruta fijada; `log_history` nunca se manda | bucle de 30 s, tirar, «Reintentar», elegir ruta, tras crear/editar/borrar | `BoardStore.swift:71-105`; `TrajetAPI.swift:50-55` | sí: una llamada `stop-monitoring` por estación distinta y una `general-message` (`board.py:372-374`), con caché por cercanía |
| `GET /api/routes` | — | primera vez en Tablero o Rutas; tirar en Rutas; tras crear, editar o guardar desde el planificador | `RoutesStore.swift:23-59`; `PlaceSearchView.swift:230` | no |
| `POST /api/routes` | `RouteDraft` (F35) | «Guardar» en el editor, ruta nueva | `RouteEditorView.swift:259`; `TrajetAPI.swift:63-68` | no |
| `PUT /api/routes/{id}` | `RouteDraft` | «Guardar» editando | `RouteEditorView.swift:257`; `TrajetAPI.swift:70-73` | no |
| `DELETE /api/routes/{id}` | sin cuerpo; respuesta `{deleted}` | «Borrar» | `RoutesView.swift:111-119`; `TrajetAPI.swift:75-79` | no |
| `GET /api/search/places?q=` | texto | buscador de sitios | `PlaceSearchView.swift:71-97`; `TrajetAPI.swift:84-89` | sí (`main.py:349`) |
| `GET /api/search/stops?q=` | texto | paso 1 del tramo | `LegBuilderView.swift:99-123`; `TrajetAPI.swift:92-97` | sí (`main.py:111`) |
| `GET /api/stops/{id}/lines` | id escapado | al elegir parada | `LegBuilderView.swift:161-170` | sí (`main.py:140`) |
| `GET /api/stops/{id}/directions?line_id=` | línea | al elegir línea | `LegBuilderView.swift:233-238` | sí, `stop-monitoring` (`main.py:161`) |
| `GET /api/plan?from=&to=&when=&mode=` | ids, `when` = «HH:MM», `mode` = `arrival`/`departure` | «Buscar itinerarios» | `PlanView.swift:166-183`; `TrajetAPI.swift:118-128` | sí (`main.py:385`) |
| `POST /api/routes/from-plan` | `{option, meta}` (F43) | «Guardar» un itinerario | `PlaceSearchView.swift:208-242` | no comprobado |
| `GET /api/alternatives/{id}` | `force=true` opcional | abrir la hoja, «Reintentar», «Buscar de todas formas» | `AlternativesSheet.swift:25`, `43`, `64` | sí (`main.py:242`) |
| `GET /api/stats?days=90` | días | cada entrada en Historial y al tirar | `StatsView.swift:187`; `TrajetAPI.swift:142-144` | no |
| `GET /api/platform-model?route_id=` | ruta vista, si hay | justo después de `/api/stats` | `StatsView.swift:188-189` | no |
| `GET /api/health` | — | abrir Ajustes y «Comprobar ahora» | `SettingsView.swift:62-64`, `91` | no (lee contadores, `main.py:48-60`) |

**F54 · Dos direcciones, en orden** (`Net/ServerConfig.swift:50-65`,
`Net/TrajetAPI.swift:179-224`). Candidatas: la preferida (última que
respondió), después «casa» y después «Tailscale», sin vacías ni repetidas. Se
prueba cada una:
- fallo de transporte (sin ruta, timeout, conexión rechazada, URL inválida
  que no se puede construir) → siguiente dirección;
- cualquier respuesta HTTP → esa dirección pasa a ser la preferida (se guarda
  en disco) aunque sea un error;
- 2xx con JSON válido → resultado; 2xx ilegible → `badPayload`; 4xx/5xx →
  `http(código, detalle)`, **sin** probar la otra;
- si ninguna responde → `unreachable`.

No hay más reintentos que ese salto: el siguiente intento es el siguiente
ciclo de 30 s o un «Reintentar».
**Rareza:** una cancelación (al parar el bucle con una petición en vuelo) se
trata como fallo de transporte, salta a la otra dirección y acaba en
«unreachable», que deja «sin conexión» en la píldora hasta el siguiente
refresco bueno.

**F55 · Errores y textos** (`TrajetAPI.swift:3-24`, `226-230`):
`unreachable` → «No se llega al servidor. Ni por la red de casa ni por
Tailscale.»; `http` → el `detail` de FastAPI (`{"detail": "…"}`) o «El
servidor ha respondido N.»; `badPayload` → «El servidor ha contestado algo que
no se entiende.». `isNotFound` existe pero no se usa (R44).

**F56 · Sesión y tiempos** (`TrajetAPI.swift:34-44`): sesión efímera, 6 s de
tiempo máximo entre datos de una petición, 12 s por petición completa, sin
esperar a tener red, sin caché. Peor caso con las dos direcciones caídas:
unos 24 s (2 × 12 s); lo normal es descartar la de casa en ≤ 6 s.

**F57 · Formato de las peticiones** (`TrajetAPI.swift:158-200`,
`Model/Decoding.swift:27-42`): `Accept: application/json`; con cuerpo,
`Content-Type: application/json`; JSON en snake_case en los dos sentidos;
identificadores de parada escapados en la ruta (`urlPathAllowed`). Sin
autenticación.

---

## 10. Bucle de refresco de 30 s

**F58 · Cuándo arranca y cuándo se para** (`Views/RootView.swift:55-71`,
`Store/BoardStore.swift:41-65`):
- `RootView` escucha `scenePhase` (también en la primera aparición,
  `initial: true`) y la pestaña. Si la escena está **activa** y la pestaña es
  **Tablero** → `start()`; en cualquier otro caso (inactiva, segundo plano u
  otra pestaña) → `stop()`.
- `start()` es idempotente (no crea dos bucles). El bucle: refresca → espera
  `max(1, nextRefreshAt − ahora)` segundos, donde `nextRefreshAt` = fin del
  último refresco + 30 s → vuelve a empezar hasta que se cancela.
- `stop()` cancela la tarea.
- Cada arranque refresca en el acto: volver a primer plano o a la pestaña
  Tablero cuesta una llamada inmediata, sin límite mínimo.
- Otros refrescos sueltos, fuera del bucle: tirar (F12), «Reintentar» (F23),
  elegir ruta (F8, también desde Rutas con «Ver en el tablero»), tras crear,
  editar o borrar rutas y tras guardar desde el planificador
  (`invalidate()`, `BoardStore.swift:99-105`), aunque el tablero no esté a la
  vista.
- Un refresco que falla solo apunta el error; el tablero anterior se queda
  (`BoardStore.swift:71-86`).

**Rarezas:** el refresco por elegir ruta corre en paralelo con el del bucle y
la respuesta más lenta gana (`BoardStore.swift:89-94`); elegir ruta vacía el
tablero (`:92`) en contra de R9; los refrescos automáticos no mandan
`log_history=false` (R40).

---

## 11. Persistencia

**F59 · Preferencias** (`UserDefaults.standard`, `Net/ServerConfig.swift:23-48`):

| Clave | Contenido | Cuándo se escribe |
|---|---|---|
| `server.lan` | dirección de casa (por defecto `http://192.168.1.188:7796`) | al escribir en Ajustes, al restablecer |
| `server.tailscale` | dirección Tailscale (por defecto `http://100.99.38.76:7796`) | ídem |
| `server.preferred` | la última dirección que respondió | tras cada respuesta HTTP de una dirección distinta; se borra al restablecer |

**F60 · Último tablero en disco** (`Store/BoardStore.swift:108-145`): fichero
`Application Support/last-board.json` (se crea la carpeta si falta). Contenido
JSON snake_case `{"board": {…todos los campos del servidor…}, "received_at":
<fecha>}` (fecha con la estrategia por defecto de `JSONEncoder`: segundos
desde el 1-1-2001). Se escribe de forma atómica tras cada tablero bueno
(también el `empty`); se lee una sola vez al arrancar y se le devuelve su hora
real de llegada. Los errores de disco se ignoran.

**F61 · Lo que no se guarda:** la ruta fijada (al reabrir vuelve la
automática), la pestaña, el estado del planificador y del editor, la salud del
servidor, las rutas (se piden cada vez).

---

## 12. La ruta que toca según día y hora

**F62 · Quién decide.** La app no lo calcula: sin ruta fijada no manda
`route_id` y el servidor elige con `pick_active_route`
(`trajet-server/app/board.py:125-151`); la misma función marca `active_id` en
`/api/routes` (insignia «ahora», F26) y elige la ruta de
`/api/platform-model` si no se pasa ninguna (`main.py:64-68`, `420-422`).

**F63 · Algoritmo exacto** (hora de París, `settings.tz`; rutas en el orden de
la base de datos: `position` y luego `id`, `db.py:173`):
1. Sin rutas → el tablero responde `{"empty": true, …}` (`main.py:171-173`).
2. `hoy` = rutas cuyo `days` contiene el día de la semana actual (0 = lunes).
3. `encajan` = las de `hoy` con `time_from ≤ HH:MM ≤ time_to` (comparación de
   texto «HH:MM», ambos extremos incluidos).
4. Si hay alguna que encaja: la de **franja más estrecha** (`time_to −
   time_from` en minutos); empate → menor `position`; empate → menor `id`.
5. Si no encaja ninguna pero hay rutas hoy: la **primera, en el orden de la
   base de datos**, cuya franja empieza a esta hora o más tarde (no
   necesariamente la que empieza antes); si no queda ninguna por empezar, la
   **última** de hoy en ese orden.
6. Si hoy no hay ninguna: la primera de todas.

**F64 · De dónde sale la franja** (`board.py:103-122`; se calcula y guarda al
salvar la ruta, `db.py:202-208`):
- «Franja»: `time_from`/`time_to` tal cual (por defecto 07:00–10:00).
- «Salgo a H»: de H − 45 min a H + duración + 30 min.
- «Llego a H»: de H − duración − 45 min a H + 15 min.
- Duración = `duration_min`, o 60 si es 0 (rutas hechas a mano). Los extremos
  se recortan a 00:00–23:59: no hay franjas que crucen la medianoche.
- Ejemplos: «Llego a las 09:00» con 62 min → 07:13–09:15. «Salgo a las
  08:00» sin duración → 07:15–09:30.

---

## 13. Formato

**F65 · Minutos** (`Design/Format.swift:11-23`): < 60 → el número (negativos
→ «0») con «min» aparte; ≥ 60 → «1h», «1h46», «2h45», sin unidad.

**F66 · Momento de una salida** (`Format.swift:91-140`): «En andén» (si
`at_stop`), «ya» (minutos ≤ 0) o los minutos. VoiceOver: «parado en el
andén», «sale ya», «en N minutos», «en H horas y M minutos».

**F67 · Antigüedad** (`Format.swift:30-38`): «hace N s» (< 60 s), «hace N
min» (< 60 min), «hace N h». Retraso: «+N min» / «-N min» (`:25-28`). Cuota:
«N llamadas hoy» (`:40-43`).

**F68 · Ritmo e iconos** (`Format.swift:46-84`; `Model/Board.swift:228-236`):
≤ 3 min correr (`figure.run`, rojo), ≤ 8 andar (`figure.walk`), si no con
calma (`cup.and.saucer.fill`). Modos: metro `tram.fill.tunnel`; RER,
Transilien y TER `train.side.front.car`; tranvía `tram.fill`; bus `bus.fill`;
otro `arrow.triangle.turn.up.right.diamond.fill`. Longitud: «Tren corto»
(`rectangle`) / «Tren largo» (`rectangle.split.2x1`) (`Board.swift:29-35`).

**F69 · Etiquetas de rutas, planes y estadísticas:** horario «llego 09:00» /
«salgo 08:00» / «07:00–10:00» (`Model/Routes.swift:99-107`); días «todos los
días» / «entre semana» / «fin de semana» / «L M X» (`Routes.swift:109-117`);
«directo» / «1 transbordo» / «N transbordos» (`Model/Plan.swift:73-79`);
«+12 min» / «-3 min» / «igual de rápido» (`Plan.swift:186-191`); mes
«agosto 2026» (`Model/Stats.swift:29-39`); acierto «84 %» o «—»
(`Stats.swift:115-118`); decimales con coma (`StatsView.swift:197-199`); hora
de Navitia `20260831T083100` → «08:31» (`AlternativesSheet.swift:198-206`).

---

## 14. Colores de línea y contraste

**F70 · `LineColor`** (`Design/LineColor.swift`):
- `parse`: hex con o sin «#», de 3 o 6 dígitos; si no vale, gris de reserva
  `rgb(0,42; 0,45; 0,50)` (`:7-14`, `35-45`).
- `ink(on:)`: texto negro si la luminancia relativa W3C del fondo es > 0,45,
  si no blanco; sin color válido, blanco (`:16-26`, `47-53`).
- `wash`: el color al 14 % para fondos tenues (`:28-31`; no se usa en las
  vistas).
- Distintivo `LineBadge` (`:60-88`): 42 pt por defecto (30–50 según sitio),
  esquina 29 %, letra black redondeada al 46 % (1–2 caracteres), 36 % (3) o
  29 % (4 o más), «?» si no hay código, VoiceOver «Línea X».
- **Hallazgo:** el umbral 0,45 no garantiza contraste AA (ver R12 en
  `docs/reglas.md`).

**F71 · Paleta neutra** (`Design/Theme.swift:8-23`): fondo #0a0a0c, superficies
#131316 y #1c1c20, filetes blancos al 9 % y 16 %, tinta blanca al 100/62/38 %,
y solo tres estados: aviso ámbar, error rojo y bien verde.

---

## 15. Accesibilidad

**F72 · VoiceOver:** etiquetas propias en pestañas (con estado seleccionado),
ajustes, selector de ruta («Ruta X, tocar para cambiar»), píldora de
antigüedad, chips de salida (F21), vías (F19), «Traduciendo el aviso»,
distintivos, días del editor, «Quitar el tramo X», esqueleto («Cargando el
tablero»); elementos decorativos ocultos (hilo, iconos de modo y ritmo, barra
de refresco).

**F73 · Reducir movimiento:** respetado en latido de vía, «Traduciendo» y
barra de refresco; no en el esqueleto ni en la barra de pestañas (R51).

**F74 · Áreas táctiles** de 44–52 pt en los controles (R52).

**F75 · Sin Dynamic Type:** todos los cuerpos son fijos (`.system(size:)`);
solo algunos textos encogen con `minimumScaleFactor`.

---

## 16. Datos que la app recibe y hoy no enseña

**F76 · Campos decodificados sin uso en pantalla** (útiles para widgets y Live
Activity de la v2): `Board.worst_level`, `worst_line`, `max_delay`,
`updated_at`, `last_error` (el del servidor), `message`; `Leg.age`,
`line_name`; `Departure.aimed_at`, `status`; `PlatformGuess.basis`;
`PlanOption.kind`; `PlanLeg.direction`, `minutes`, `at`;
`AlternativeLeg.mode`, `direction`, `minutes`, `status`;
`AlternativeOption.worst_level`; `MonthStat.avg_delay`;
`OverallStat.max_delay`; `PlatformAccuracy.hits`; `HealthResponse.key_configured`;
`TranslatorStatus.reason`; `SavedRoute.origin_*`, `dest_*`, `position`.
El servidor manda además campos que la app ni decodifica: `collector` y
`platform_model` en `/api/health` (`main.py:55-56`), `route` en la respuesta de
`from-plan` (`main.py:411`), `age` en `/directions` (`main.py:164`) y
`route_id` en cada tramo guardado.

---

## 17. PreviewData: casos y qué cubre cada uno

**F77 · Bancos de prueba** (`Resources/PreviewData.swift`, solo en DEBUG).
Decodifican con el mismo `JSONDecoder.trajet` que la app (`:14-17`).

| Caso | Dónde (`PreviewData.swift`) | Qué cubre |
|---|---|---|
| Tablero de 5 tramos «Casa → Trabajo» | `:40-133` | caso difícil; `auto_selected: true`; cuota de 3 endpoints; un error de estación («Victor Basch: tiempo de espera agotado») → R26, F22; densidad compacta (5 tramos) → R47 |
| · tramo 0, bus 6424 | `:50-65` | bus con hora teórica y retraso +11 (`delayed`) → R4, R14; **bus a 106 min** → R6 |
| · tramo 1, tranvía T2 sin salidas | `:67-71` | **tramo vacío** con línea normal → «Servicio finalizado», R25 |
| · tramo 2, RER E | `:73-94` | **vía que aparece** (11, `platform_new`) → R2; **vía solo probable** (82 % por misión y 55 % por hora) → R10, R49; retraso 0 que no se pinta → R14; `delay: null`; longitudes `long`/`short`/`null` → R5; tren como cadena; `planned: 1` → R28 |
| · tramo 3, metro 13 | `:96-113` | **línea cortada** (nivel 2) → R25; **aviso sin traducir** (`messages_es: [null]`, `translating: true`) → R8; **tren parado en el andén** (`at_stop`, 0 min) → R15; **destinos mezclados** (sin sentido, Place d'Italie / Bobigny) → R24; metro sin hora teórica → R4; `to_name` vacío |
| · tramo 4, bus 147 | `:115-130` | línea perturbada con aviso ya traducido → R8, R27; bus sin hora teórica → R4 |
| Tablero tranquilo «Trabajo → Casa» | `:135-181` | 2 tramos, densidad holgada; `auto_selected: false` («Ruta elegida»); vía real no nueva (21); vía probable al 90 %; metro 14 a 1, 3 y 6 min (ritmos); **sin `messages_es` ni `translating`** → tolerancia R21; cuota de un solo endpoint |
| Tablero vacío | `:26` | `{"empty": true, "message": …}` → instalación limpia, F23 |
| Vía probable suelta | `:28-30`, `:277-279` | `PlatformGuess.preview` para `PlatformBadge` |
| Rutas | `:183-212` | `active_id`; «llego a» con 3 tramos (uno de metro sin sentido) y «franja» con uno; campo `route_id` que la app ignora |
| Estadísticas | `:214-223` | 2 meses, 3 líneas, totales |
| Previsión del andén | `:225-233` | acierto 0,84; cobertura con tramos sin vía (0 observaciones) → R3, R11 |
| Planificador | `:235-254` | directo y con 1 transbordo; `kind` |
| Alternativas | `:256-274` | `needed`, `baseline_minutes`, línea afectada, una opción válida (+12) y una que no sirve (+4) → R30 |

Dónde se usan hoy en las vistas previas: `BoardView` (5 tramos y tranquilo),
`LegCardView` (5 tramos), `DepartureChip` (tramos 2, 3 y 0),
`PlatformBadge` (vía probable), `DisruptionNotice` (tramos 3 y 4),
`LegDetailSheet` (tramo 2), `AlternativesSheet`, `PlanView`, `RoutesView`.
Sin usar: el tablero vacío, las estadísticas y la previsión (la vista previa de
`StatsView` pinta cifras a mano).

**F78 · Casos que faltan** (para ampliar, R13): tablero viejo o sin conexión
(`stale: true`, `data_age` alto, `receivedAt` antiguo); `route: null`;
`line_color` vacío, inválido, de 3 dígitos o con «#»; tren como número;
adelanto (retraso negativo); 60 min («1h») y 165 min («2h45»); minutos
negativos; traducción parcial (2 avisos, 1 traducido); solo obras futuras
(`level 0`, `planned > 0`); más de 3 errores de estación; 1 tramo y 6 tramos;
sin sentido pero un solo destino; `rate: null`; `/api/health` (con y sin
clave, traductor caído); plan vacío; `from-plan` con `without_direction`;
alternativas sin opciones (`needed` true y false) y con `delta_minutes` 0,
negativo o nulo; `time_mode` desconocido; días de fin de semana y de toda la
semana; respuestas de buscadores, líneas y sentidos; 404, 502 con `detail` y
JSON ilegible; campos con el tipo cambiado.

**F79 · Escenarios del laboratorio que aún no están en `PreviewData`**
(`design-lab/shared/data.js`, `core.js`): 4 salidas por tramo; J con retraso
+2 `delayed`; bus a 106 y **165** min; la 14 cortada entera con reanudación
prevista (`cut14`); vía real / probable / sin vía conmutables y «que aparezca
la vía ahora»; tren en el andén; sin conexión con 4 min de antigüedad; ruta
«Vuelta de clase» (salida 21:00, martes y jueves, RER A con dos sentidos); plan
con 2 transbordos (`less_walk`); alternativa usable pero perturbada
(`worst_level 1`); salud (`/api/health`); dispositivos y QR del panel; trazado
de la J con paradas, transbordo y camino a pie (mapa). Diferencias de texto
entre el laboratorio y la app que hay que unificar: días («Lunes a viernes»
frente a «entre semana»), horario («llegar a las 09:00» frente a «llego
09:00»), meses abreviados («ago 2026» frente a «agosto 2026») y la lista de
modos con vía (el laboratorio incluye «train», R3). `design-lab/LEEME.md:18`
cita un `revision.md` que no está en la carpeta.

---

## 18. Empaquetado, permisos y CI

**F80 · Proyecto generado** con XcodeGen desde `project.yml` (R59). Un solo
objetivo, `Trajet`; sin objetivos de tests ni esquemas declarados.

**F81 · Compilación en CI** (`.github/workflows/ios.yml`): en `push` a `main` o
`rewrite-v2` (salvo cambios solo en `README.md` o `docs/**`) y a mano; runner
`macos-latest`; elige el Xcode más nuevo de la imagen; `xcodegen generate`;
`xcodebuild` Release para `generic/platform=iOS` sin firma; empaqueta
`Payload/Trajet.app` en `Trajet.ipa` y lo sube como artefacto
`Trajet-ipa-<nº>` 30 días. Firma fuera, con IPA Station (`README.md:10-31`).
El README dice «cada push a main» (`README.md:12`), pero el flujo también
corre en `rewrite-v2` (`ios.yml:8`).

**F82 · Permisos y red** (`Info.plist:41-56`): HTTP sin restricciones
(`NSAllowsArbitraryLoads` y `NSAllowsLocalNetworking`) y texto de permiso de
red local «Trajet consulta el servidor de tu NAS para enseñarte los próximos
pasos de tus trayectos.». No pide cámara, ubicación ni notificaciones.

---

## 19. Resumen de rarezas (para decidir en la v2)

| Rareza | Dónde | Regla |
|---|---|---|
| `DepartureChip.swift:64` no compila (vía en el chip) | ver `docs/ios-reutilizable.md` | R2, R3 |
| Elegir ruta vacía la pantalla | `BoardStore.swift:92` | R9 |
| Refrescos de «elegir ruta» y del bucle en carrera | `BoardStore.swift:45-54`, `89-94` | R9 |
| Cancelar el bucle con petición en vuelo acaba en «sin conexión» | `TrajetAPI.swift:214-219` | R9 |
| «Sin conexión» con cualquier error, aunque el servidor responda | `BoardView.swift:232-243` | R9 |
| Refrescos automáticos sin `log_history=false` | `BoardStore.swift:78` | R40 |
| Ruta fijada borrada → 404 cada 30 s | `BoardStore.swift:100-103`; `TrajetAPI.swift:20` | R44 |
| Error al cargar rutas se ve como «no hay rutas» y no se reintenta | `RoutesStore.swift:25`; `RoutesView.swift:17` | R53 |
| Ruta con 0 tramos se ve como «No se llega al servidor» | `BoardView.swift:49-59` | R53 |
| «dirección <parada de bajada>» tapa «todos los sentidos» | `Board.swift:190-195` | R24 |
| Nota de obras futuras invisible si la línea está normal | `LegDetailSheet.swift:18-20` | R28 |
| Duraciones de planes y alternativas sin «1h46» | `AlternativesSheet.swift:136`; `PlanView.swift:227` | R6 |
| Guardar desde el planificador con aviso permite duplicar | `PlaceSearchView.swift:231-237` | R33 |
| Editar dirección no olvida la preferida antigua | `ServerConfig.swift:61-65` | R42 |
| `position` se pone a 0 al guardar desde la app | `db.py:216` | — |
| Texto de franja de «Salgo a» no coincide con el servidor | `RouteEditorView.swift:150`; `board.py:120` | R38 |
| Contraste del distintivo no garantizado | `LineColor.swift:23-26` | R12 |
| Esqueleto ignora «Reducir movimiento» | `BoardView.swift:311-313` | R51 |
| VoiceOver «1 horas» | `Format.swift:137-138` | R6 |
| Tres criterios distintos de «modo con vía» (app, servidor, laboratorio) | `Board.swift:208-226`; `collector.py:53`; `core.js` | R3 |
| «Con problemas» no sale nunca en Ajustes | `SettingsView.swift:45-46`; `main.py:51` | — |
