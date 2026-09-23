# Servidor Trajet 0.3.0: cómo funciona hoy

Análisis técnico del servidor actual (`trajet-server`, repo aparte,
Python 3.12 + FastAPI, código de producción 0.3.0). Todas las referencias
`fichero:línea` son relativas a `trajet-server/` salvo que se indique otra
cosa. La API endpoint a endpoint está en [`api.md`](api.md) y el contrato en
[`openapi.yaml`](openapi.yaml).

Qué se ha hecho para escribir esto, además de leer todo el código:

- Ejecutar los tres tests sin red del repo (`tools/test_platform.py`,
  `tools/test_routes.py`, `tools/test_resilience.py`) en un venv con las
  versiones de `requirements.txt` y sin `PRIM_API_KEY`: los tres dan
  `TODO OK`.
- Ejecutar la app real con un cliente PRIM falso (sin red) y 49 peticiones
  (`scratchpad/servidor/arnes.py`); varias conclusiones de la sección de
  riesgos están **confirmadas** así y se marcan como tales.
- Sacar estadísticas de `probe/probe_observations.jsonl` con los propios
  scripts `probe/platform_report.py`, `probe/deep2.py` y `probe/deep3.py`, sin
  leer el fichero entero.
- No se ha llamado a producción ni a PRIM.

---

## 1. Qué es y dónde corre

- Un solo proceso `uvicorn app.main:app` (un worker) en el puerto 8000 del
  contenedor (`Dockerfile:28`), publicado como 7796.
- Consume la API PRIM de Île-de-France Mobilités (SIRI Lite y Navitia) con
  una clave gratuita limitada a 1000 llamadas/día por endpoint.
- Guarda todo en un SQLite en `/data/trajet.db` (volumen).
- Sirve además una PWA (`app/static/`) que es hoy la única interfaz.
- Opcionalmente usa un Ollama local para traducir avisos al español.
- En producción corre como app de Umbrel `ismaeloul-trajet` 0.3.0 con la
  imagen `localhost:5000/ismaeloul-trajet/trajet:0.3.0` del registro local
  del NAS (`umbrel-app-store/ismaeloul-trajet/docker-compose.yml:17`).

## 2. Arquitectura de módulos

| Módulo | Líneas | Responsabilidad |
|---|---|---|
| `app/main.py` | 479 | App FastAPI: `lifespan`, todos los endpoints, cálculo de alternativas (en el propio handler), rutas de la PWA. |
| `app/board.py` | 482 | Tablero: elegir ruta activa, franja horaria, avisos (`index_disruptions`, `line_status`), extraer salidas de SIRI, TTL por estación, historial. |
| `app/prim.py` | 228 | Cliente HTTP de PRIM con caché en memoria, lock por clave, cuota y degradación. |
| `app/collector.py` | 265 | Tarea de fondo que muestrea estaciones para aprender andenes, con ritmo según la cuota. |
| `app/platform.py` | 248 | Previsión de andén por frecuencias (registrar, predecir, puntuar, cobertura). |
| `app/planner.py` | 219 | Planificador puerta a puerta: traducir `journeys` de Navitia, resolver la dirección SIRI, montar la ruta. |
| `app/translate.py` | 172 | Traducción de avisos con Ollama, caché en SQLite, tareas en segundo plano. |
| `app/db.py` | 315 | Esquema SQLite, migraciones, CRUD de rutas, historial, estadísticas. |
| `app/idfm.py` | 147 | Conversión de ids Navitia↔SIRI, normalización de texto, andén "real", orden de líneas. |
| `app/frdate.py` | 79 | Heurística para saber si un aviso en francés empieza más adelante. |
| `app/config.py` | 34 | `Settings` (dataclass congelada) leída del entorno al importar. |
| `app/static/` | ~2 480 + binarios | PWA: `index.html`, `app.js`, `style.css`, `sw.js`, `manifest.webmanifest`, fuente e iconos. |

Dependencias entre módulos (imports):

```
main ──► board, db, planner, prim, translate, platform, collector, config, idfm
board ─► db, config, frdate, idfm, prim
collector ─► db, platform, prim, board.extract_departures, config, idfm
platform ─► db, config, idfm
planner ─► prim, board.observed_destinations, config, idfm
translate ─► db, config, httpx
prim ─► config, httpx
db ─► config  (+ board.derive_window importado dentro de save_route, app/db.py:193)
idfm, frdate ─► (nada)
```

Modelo de concurrencia: un bucle asyncio. Las llamadas a PRIM y a Ollama son
asíncronas (`httpx.AsyncClient`). SQLite es síncrono: algunas operaciones van
a un hilo con `run_in_threadpool` (aprender andenes, historial, `accuracy`,
`coverage`, `stats`: `app/main.py:57,195,209,418,427,433`) y el resto se
ejecuta directamente en el bucle (CRUD de rutas, `db.list_routes()` del
tablero, lecturas/escrituras de `translations`, escrituras del recolector).

Estado en memoria (se pierde al reiniciar):

| Variable | Dónde | Qué guarda | Límite |
|---|---|---|---|
| `PrimClient._cache` | `app/prim.py:62` | Última respuesta por clave | Sin límite, nunca se borra |
| `PrimClient._locks` | `app/prim.py:63` | Un `asyncio.Lock` por clave | Sin límite |
| `PrimClient.quota`, `last_error` | `app/prim.py:65-66` | Cuota por cubo, último error | 3 claves |
| `board._seen_platforms` | `app/board.py:46-55` | Andén visto por `jid` (para `platform_new`) | 4000 entradas |
| `board._next_in` | `app/board.py:329` | Minutos al próximo paso por estación (TTL) | Una por estación |
| `main._baseline` | `app/main.py:226-227` | Duración de referencia por ruta | Una por ruta, 12 h |
| `translate._en_curso` | `app/translate.py:131` | Traducciones en curso | Transitorio |
| `collector` | `app/collector.py:211-265` | Tarea, última pasada, total | — |

Arranque y parada (`app/main.py:28-40`): aviso en el log si no hay clave
(la app arranca igual), `db.init()`, crea `PrimClient` y su `httpx.AsyncClient`,
arranca el recolector (si `TRAJET_COLLECT`); al parar, cancela el recolector y
cierra el cliente HTTP. `logging.basicConfig(level=INFO)` (`app/main.py:20-22`).

---

## 3. Cliente PRIM (`app/prim.py`)

### 3.1 URLs exactas

Base `https://prim.iledefrance-mobilites.fr` (`app/prim.py:23-25`):
`SIRI = BASE + "/marketplace"`, `NAVITIA = BASE + "/marketplace/v2/navitia"`.

| Método del cliente | URL y parámetros | Cubo de cuota | TTL | Clave | Quién lo usa |
|---|---|---|---|---|---|
| `stop_monitoring(siri_sa, ttl)` (`:127-141`) | `GET /marketplace/stop-monitoring?MonitoringRef=STIF:StopArea:SP:<código>:` | `stop-monitoring` | `ttl` o 25 s | `sm:<MonitoringRef>` | tablero, `/directions`, `from-plan`, recolector |
| `general_message()` (`:143-151`) | `GET /marketplace/general-message?LineRef=ALL` | `general-message` | 150 s | `gm:ALL` | tablero, alternativas |
| `places(q, kinds, count)` (`:155-172`) | `GET /marketplace/v2/navitia/places?q=<q>&count=<count>&type[]=<k>…` | `navitia` | 86 400 s | `pl:<kinds con +>:<q.lower().strip()>` | `/search/stops` (stop_area, 12), `/search/places` (stop_area+address+poi, 10) |
| `lines_at_stop(sa)` (`:183-190`) | `GET /marketplace/v2/navitia/stop_areas/<sa>/lines?count=60` | `navitia` | 86 400 s (`ttl_line_info`) | `ls:<sa>` | `/stops/{id}/lines` |
| `journeys(frm, to, forbidden, datetime_str, count, represents)` (`:192-220`) | `GET /marketplace/v2/navitia/journeys?from=&to=&min_nb_journeys=<count>&max_nb_journeys=<count+2>&data_freshness=realtime` + `datetime=<YYYYMMDDTHHMMSS>&datetime_represents=<departure\|arrival>` solo si hay fecha + un `forbidden_uris[]=<line_id>` por línea excluida | `navitia` | 600 s | `jr:<from>><to>\|<forbidden ordenados>\|<datetime>\|<represents>\|<count>` | `/plan` (count 4), alternativas (count 3) |
| `line_info(line)` (`:174-181`) | `GET /marketplace/v2/navitia/lines/<line>` | `navitia` | 86 400 s | `ln:<line>` | **Nadie** (código muerto) |

Conversión de ids (`app/idfm.py:1-41`): en la BD se guarda siempre el id
Navitia (`stop_area:IDFM:71370`, `line:IDFM:C01739`); para SIRI se convierte
al vuelo a `STIF:StopArea:SP:71370:`. Las líneas se comparan solo por el
código `Cnnnnn` (`line_code`, `app/idfm.py:27-31`), que vale para ambos
formatos. Pedir el StopArea padre devuelve las salidas de todos sus andenes
hijos, así que basta **una llamada por estación** (`app/prim.py:9-10`).

### 3.2 Cabeceras, timeouts, conexiones, reintentos

- Cabeceras fijas (`app/prim.py:71`): `apikey: <PRIM_API_KEY>` y
  `Accept: application/json`. Según el docstring, `API Key` da 401
  (`app/prim.py:4`).
- Timeout total 20 s, conexión 8 s (`app/prim.py:70`).
- `httpx.Limits(max_connections=8)` (`app/prim.py:72`).
- **Reintentos: ninguno.** `httpx` no reintenta por defecto y el código no
  implementa reintentos ni espera exponencial. Un fallo no se cachea: la
  siguiente petición vuelve a intentarlo.
- La clave nunca va en la URL (va en cabecera), así que no aparece en los
  mensajes de error de httpx ni en los logs.

### 3.3 `_get`: caché, lock y degradación (`app/prim.py:84-123`)

1. Si hay entrada y su edad < `ttl` → se devuelve `(datos, edad)` sin tocar la
   red (`:92-94`).
2. Si no, se toma el lock de esa clave; dentro se vuelve a mirar por si otra
   petición la acaba de refrescar (`:96-100`). Así 5 peticiones simultáneas
   hacen 1 llamada (lo comprueba `tools/test_resilience.py:98-105`).
3. Llamada HTTP (`:104`). Se lee `x-ratelimit-remaining-day` **antes** de
   `raise_for_status`, así que también cuenta la cabecera de una respuesta de
   error (`:105-111`).
4. Éxito: se guarda `Entry(data)` con `fetched_at = ahora`, `last_error = None`,
   se devuelve edad 0.0 (`:112-115`).
5. Cualquier excepción (red, HTTP 4xx/5xx, JSON inválido): `last_error =
   "<Tipo>: <mensaje>"`, aviso en el log con la clave de caché, y si había
   entrada vieja se devuelve **con su edad real**; si no, `PrimError`
   (`:116-123`).

`Entry` no tiene TTL propio: la frescura la decide quien pregunta
(`app/prim.py:28-38`). Así el tablero (20 s si el tren sale ya) y el
recolector (120 s) comparten la misma entrada sin pisarse el TTL.

### 3.4 Cuota: cómo se cuenta y dónde

- PRIM devuelve en cada respuesta `x-ratelimit-remaining-day`. El cliente guarda
  el último valor por cubo en `quota` (`app/prim.py:65,105-110`). El servidor
  **no cuenta** llamadas por su cuenta: solo refleja la cabecera.
- Cubos: `stop-monitoring`, `general-message` y un único `navitia` para
  places, lines y journeys.
- Límite: 1000 llamadas/día por endpoint, reinicio a medianoche UTC
  (`app/prim.py:6-8`, `app/config.py:12-14`, `app/collector.py:118-123`). El
  `probe/probe.log` lo corrobora: la cuota restante baja de 999 a 820 en 180
  llamadas al mismo endpoint `stop-monitoring` repartidas entre dos
  estaciones, o sea que el contador es por endpoint, no por estación.
- Contradicción en el propio código: `app/prim.py:6-7` dice que "cada endpoint
  tiene su propio contador" y `app/main.py:235-236` que el calculador
  "comparte la bolsa de 1000 llamadas/día con el buscador de paradas". El
  código agrupa ambos en un cubo `navitia`; no se ha podido comprobar cuál de
  las dos frases es cierta sin llamar a PRIM.
- Dónde se usa la cuota: se enseña en `/api/health`, `/api/board` y
  `/api/alternatives` (`quota`); la PWA pinta "quedan N llamadas hoy" con
  `quota["stop-monitoring"]` (`app/static/app.js:490-494`); el recolector
  decide su ritmo con ella (sección 6).
- `quota` no se pone a cero a medianoche ni caduca: muestra el último valor
  recibido, aunque sea de ayer.

---

## 4. Caché (resumen)

| Qué | Dónde vive | TTL | Clave | Notas |
|---|---|---|---|---|
| stop-monitoring | `PrimClient._cache` | 25 s (`config.py:15`); en el tablero adaptativo 20/30/90/300/600 s (`board.py:337-354`); 120 s en el recolector (`collector.py:183-184`) | `sm:STIF:StopArea:SP:<código>:` | Compartida por tablero, `/directions`, `from-plan` y recolector. |
| general-message | ídem | 150 s (`config.py:16`) | `gm:ALL` | Una llamada cubre toda la red. |
| journeys | ídem | 600 s (`config.py:17`) | ver 3.1 | Sin `datetime` la clave es la misma todo el rato: el "ahora" se reutiliza 10 min. |
| places | ídem | 86 400 s (`config.py:18`) | ver 3.1 | Una entrada por texto buscado. |
| lines de una parada | ídem | 86 400 s (`config.py:19`) | `ls:<id>` | |
| Duración de referencia de alternativas | `main._baseline` | 12 h (`main.py:227`) | `route_id` | No se invalida al editar la ruta. |
| Traducciones | tabla `translations` | Para siempre | `sha256(texto)[:32]` | Ver sección 9. |
| Copia vieja si PRIM falla | `PrimClient._cache` | Sin límite de edad | igual | Se sirve con su edad; el tablero la marca `stale` si > 90 s. |

Ninguna caché tiene expulsión ni tamaño máximo.

---

## 5. Construcción del tablero (`app/board.py`), paso a paso

### 5.1 Qué ruta se enseña (`pick_active_route`, `:125-151`)

1. Día de la semana y `HH:MM` de París (`settings.tz`).
2. `today` = rutas cuyo `days` contiene el día.
3. `encajan` = de `today`, las que cumplen `time_from <= HH:MM <= time_to`
   (**comparación de cadenas**: no admite franjas que crucen medianoche).
4. Si encajan varias, gana la franja más estrecha; a igualdad, menor
   `position` y menor `id` (`:139-146`). El comentario explica por qué: una
   franja genérica 07:00–22:00 tapaba a la de "llego a las 09:00".
5. Si ninguna encaja: la primera de `today` (en orden de lista, no la más
   próxima) con `time_from >= ahora`; si no hay, la última de `today`
   (`:147-150`).
6. Si hoy no hay ninguna: `routes[0]`. Nunca deja la pantalla vacía.

### 5.2 Franja horaria (`derive_window`, `:103-122`)

Se calcula **al guardar** y se guarda en `time_from`/`time_to`
(`app/db.py:202-208`). Constantes: `DEFAULT_TRIP = 60` min si no se conoce la
duración, `ANTES = 45`, `DESPUES = 30` (`:83-87`). Recortado a 00:00–23:59.

| `time_mode` | Franja |
|---|---|
| `window` o sin `time_at` | `time_from`–`time_to` tal cual (por defecto 07:00–10:00) |
| `departure` a las T | `T − 45` → `T + duración + 30` |
| `arrival` a las T | `T − duración − 45` → `T + 15` |

Casos verificados por `tools/test_routes.py:65-80`: salgo 08:00 (45 min) →
07:15–09:15; llego 09:00 (45 min) → 07:30–09:15; llego 09:00 sin duración →
07:15–09:15. La PWA repite este cálculo en `app/static/app.js:851-867` con
el aviso "si se cambia allí, hay que cambiarlo aquí".

### 5.3 `build_board(route)` (`:367-450`)

1. **Estaciones únicas**: `dict.fromkeys(leg.from_id ...)` (`:372`).
2. **Peticiones en paralelo** (`:373-375`): un `stop_monitoring` por estación
   con `ttl = station_ttl(estación)` y un `general_message`, con
   `asyncio.gather(..., return_exceptions=True)`: una estación caída no
   tumba las demás.
3. **Avisos**: si `general-message` respondió, `index_disruptions` (5.5). Si
   falló sin copia, `disruptions = {}` y **todas las líneas salen "normal"**,
   sin ningún error visible (ver riesgos).
4. **Por cada tramo** (`:395-433`):
   - Si su estación falló sin copia: `errors.append("<from_name>: <error>")`,
     `departures = []`, `age = null`.
   - Si no: `extract_departures(payload, leg)` (5.4) y
     `remember_next(from_id, deps)` para el TTL de la próxima vez.
   - `status = line_status(código, disruptions)` (5.5).
   - Peor estado: si el nivel del tramo supera al peor visto, se apunta su
     línea en `worst_line` (`:409-411`).
   - Retraso máximo: por cada salida con `delay` distinto de 0 y mayor que
     el máximo, se actualiza `max_delay`; y si hasta ese momento todo es
     normal, `worst_line` pasa a ser esa línea (`:413-418`). Solo cuentan
     retrasos positivos.
5. **Salida** (`:435-450`): `route` resumida, `legs`, `worst_level`,
   `worst_line`, `max_delay`, `updated_at` (UTC), `data_age` = máximo de las
   edades de estaciones y avisos (1 decimal), `stale = data_age > 90`
   (`refresh_seconds * 3`), `errors`, `quota`, `last_error`.

### 5.4 Salidas de un tramo (`extract_departures`, `:219-298`)

Para cada `MonitoredStopVisit` de la respuesta SIRI:

1. **Filtro de línea**: `line_code(LineRef)` igual al del tramo (`:234-235`).
2. **Destino**: `DestinationName`, si no `MonitoredCall.DestinationDisplay`
   (`:238-239`).
3. **Filtro de dirección**: si el tramo tiene `directions`, el destino
   normalizado (`norm_text`: sin tildes, guiones unificados, espacios
   colapsados, `casefold`, `app/idfm.py:89-106`) tiene que estar entre ellas
   (`:222,240-241`). Sin `directions` no se filtra.
4. **Hora prevista** = `ExpectedDepartureTime` o, si no, `ExpectedArrivalTime`;
   sin ella la visita se descarta (`:243-248`).
5. **Minutos** = `(prevista − ahora UTC)/60`; si es < −1 ("ya se ha ido") se
   descarta (`:249-251`); se publica `int(max(0, round(min)))` (`:276`).
6. **Retraso** = `round((prevista − teórica)/60)` solo si hay hora teórica
   (`AimedDepartureTime` o `AimedArrivalTime`); si no, `null` (`:253-257`).
   El comentario dice que en bus casi nunca viene; el sondeo lo confirma: 26
   de 36 líneas observadas no traen hora teórica nunca (`probe/deep3.py`).
7. **Identidad del viaje** `jid` = `DatedVehicleJourneyRef` o
   `ItemIdentifier` (`:259-261`).
8. **Andén** = `real_platform(DeparturePlatformName)` (`:262`): `null` si no
   viene, si es `unknown`/`none`/`null` o si es el nombre de una estación de
   París (`PARIS NORD`, `PARIS SAINT-LAZARE`, `PARIS EST`, `PARIS LYON`,
   `PARIS MONTPARNASSE`, `PARIS AUSTERLITZ`, `PARIS BERCY`,
   `app/idfm.py:69-86`). No se mira `ArrivalPlatformName`.
9. **Andén nuevo** (`:264-272`): memoria global `jid → andén`. Si ahora hay
   andén y antes no había (o nunca se había visto el `jid`), `platform_new =
   true`. La memoria se limita a 4000 viajes (`:37-55`).
10. **Resto de campos**: `at` (prevista, `HH:MM` París), `aimed_at` (teórica o
    `""`), `status` (`DepartureStatus` o `ArrivalStatus` o `""`), `at_stop`
    (`VehicleAtStop`), `train` (`TrainNumbers.TrainNumberRef`), `length`
    (`VehicleFeatureRef` con `shortTrain`/`longTrain` → `short`/`long`,
    `:58-65`). El comentario de `:289-293` dice que la API no da ocupación
    (211 salidas comprobadas) y que la longitud viene en el 61 % de las
    salidas; el sondeo del repo no guarda `VehicleFeatureRef`, así que esas
    cifras no se pueden recalcular con lo que hay.
11. **Orden y corte**: por `minutes` ascendente y los 4 primeros (`:297-298`).

### 5.5 Avisos (`index_disruptions` `:156-192`, `line_status` `:195-214`, `app/frdate.py`)

1. Se recorren `GeneralMessageDelivery[].InfoMessage[]`.
2. Se descartan los que tienen `ValidUntilTime` pasado (`:167-169`).
3. Textos = `Content.Message[].MessageText.value` sin repetir; se muestra el
   **más corto** ("el SHORT_MESSAGE suele ser el más legible", `:177-178`).
4. **¿Empieza más adelante?** `starts_later(todos los textos, hoy UTC)`
   (`:180-182`, `app/frdate.py:53-79`):
   - Si el texto habla en presente (`actuellement`, `en cours`,
     `reprise estim…`, `trafic interrompu`, `est/sont interrompu`,
     `trafic/est perturb…`, `ce soir`, `aujourd'hui`, `ce matin`,
     `en raison de/du la grève`, `temps d'attente`, `retard`) → activo.
   - Busca fechas `D [er] <mes en francés>`; a cada una le pone el año más
     cercano que no quede más de 60 días atrás (`app/frdate.py:40-50`).
   - Si `jusqu'au/à/a` aparece antes de la primera fecha → activo
     ("jusqu'au 15 septembre" = ya empezó).
   - Si la primera fecha es posterior a hoy → `planned_from = esa fecha`.
   - Ante la duda, activo (`app/frdate.py:8-9`).
5. **Gravedad**: `INTERRUPTED (2)` si el texto casa con `_INTERRUPTED`
   (`:26-33`: `trafic [est|sera|reste|sont|seront] interrompu`,
   `interruption [de|du] trafic`, `ligne [est] interrompue`,
   `interrompu… sur [toute] la ligne`, `ne circule(nt) plus/pas`,
   `aucun train`, `service [est] interrompu`); si no, `DISRUPTED (1)`.
6. **A qué líneas afecta** (`app/idfm.py:44-57`): `Content.LineRef[]` y el
   patrón `IDFM[.:](Cnnnnn)` dentro de `ItemIdentifier` ("solo 22 de 328
   mensajes traen LineRef… combinando ambos se identifica el 99,7 %"). Un
   aviso sin línea identificable se pierde.
7. `line_status`: los avisos con `planned_from` se cuentan en `planned` y no
   encienden el semáforo; con los activos, `level` = máxima gravedad,
   `label` = `interrumpida`/`perturbada`, `messages` = primeros 3 textos.

### 5.6 TTL por estación (`station_ttl`, `:327-362`)

Motivo (`:331-336`): una ruta de 5 tramos a 30 s serían 600 llamadas/hora y
la cuota diaria entera es de 1000. Cada estación se refresca según lo cerca
que esté **su** próximo paso:

| Próximo paso visto la última vez | TTL |
|---|---|
| (primera vez) | 25 s |
| ≤ 3 min | 20 s |
| ≤ 8 min | 30 s |
| ≤ 20 min | 90 s |
| ≤ 45 min | 300 s |
| > 45 min | 600 s |

`remember_next` guarda el mínimo de `minutes` de las salidas **del tramo**
(ya filtradas por dirección) o borra la entrada si no hay salidas, con lo
que la siguiente vez esa estación vuelve a 25 s.

### 5.7 Lo que hace `api_board` después (`app/main.py:188-214`)

1. `_learn_platforms` en un hilo: `platform.record_board` (apunta los andenes
   reales vistos y puntúa la previsión, sección 7) y `platform.annotate`
   (añade `guess` a las salidas sin andén). Hasta 3 consultas SQLite por
   salida. Un fallo solo deja un aviso en el log.
2. `translate.translate_board` (en el bucle, sección 9).
3. Si `log_history`, `record_history` en un hilo (`app/board.py:453-482`): si
   la última fila de `history` de esa ruta tiene menos de 600 s, no hace nada;
   si no, inserta `ts` (UTC ISO), `day` (fecha de París), `disrupted =
   worst_level`, `delay_min = max_delay`, `worst_line` y `detail` =
   `{"legs": [{"line", "status" (etiqueta), "next" (minutos de las 3 primeras
   salidas), "platforms" (sus andenes)}]}`.
4. `auto_selected = route_id is None`.

---

## 6. Recolector de andenes (`app/collector.py`)

Objetivo (`:1-17`): aprender de **todo el día de servicio**, no solo de la
franja del viaje, ajustando el ritmo a la cuota que queda.

### 6.1 Qué consulta

- `targets(routes)` (`:91-115`): estaciones de salida (`from_id`) de los
  tramos de las rutas guardadas, **saltando** los tramos cuyo modo
  normalizado es `metro`, `bus`, `tram`, `tramway`, `funicular` o
  `funiculaire` (`SIN_ANDEN`, `:50-53`; comparación exacta tras quitar
  tildes). Las rutas se ordenan por uso (filas de `history` de los últimos 14
  días, `app/db.py:268-279`) y se toman como mucho **4 estaciones**
  (`MAX_ESTACIONES`, `:83-88`).
- Por estación: `stop_monitoring(estación, ttl=120)`, es decir, **acepta lo
  que haya en caché de los últimos 2 min** (si la pantalla acaba de pedir esa
  estación, aprender sale gratis, `:180-184`).
- Por cada línea distinta de esa estación: `extract_departures` **sin filtro
  de dirección** y con límite 60 (`:195-198`); por cada salida con andén,
  `platform.record(...)` con la hora teórica o, si no hay, la prevista.

### 6.2 Cada cuánto (`plan_interval`, `:126-156`)

```
si no hay estaciones            → 0  ("ninguna ruta con tren o RER")
si 01:00 ≤ hora París < 05:00   → 0  ("horas muertas")
si la cuota es desconocida      → 300 s ("cuota desconocida, ritmo prudente")
utilizables = restante(stop-monitoring) − 320
si utilizables ≤ 0              → 0  ("cuota agotada (N), reservado para la pantalla")
ideal   = segundos_hasta_medianoche_UTC × estaciones / utilizables
intervalo = recortar(ideal, 120, 1800)
si alguna ruta está en su franja ±30 min: intervalo = max(120, intervalo / 3)
```

Constantes: `MIN_INTERVAL = 120` (la vía aparece con 7,7 min de mediana, así
que cada 2 min no se escapa ninguna, `:31-33`), `MAX_INTERVAL = 1800`
(`:34-35`), `RESERVA = 320` llamadas para la pantalla (`:37-40`),
`PRIORIDAD = 3`, `MARGIN = 30 min` (`:42-44`), horas muertas 01:00–05:00
(`:46-48`). Un intervalo 0 significa "no muestrear ahora" y el bucle espera
`IDLE = 600` s (`:214-216, 234`).

Ejemplos con la fórmula tal cual: a medianoche UTC con 1000 restantes y 1
estación, `86 400 × 1 / 680 ≈ 127 s`; con 4 estaciones ≈ 508 s, y ≈ 169 s en
franja. Es un lazo cerrado: si la pantalla gasta cuota, la cabecera baja y el
recolector se separa solo.

### 6.3 Ciclo de vida (`Collector`, `:211-262`)

- `start()` solo si `settings.collect` (`TRAJET_COLLECT` distinto de `0`,
  `false`, `no`; `app/config.py:24-26`).
- `_loop`: espera 15 s al arrancar; luego `sample_once()` → espera el
  intervalo (o 600 s); cualquier excepción se registra y se sigue.
- `status()` alimenta `/api/health` y `/api/platform-model`.
- Guarda en `platform_obs` (sección 7); **no** puntúa aciertos.

---

## 7. Previsión de vía (`app/platform.py`)

Por qué no un LLM (`:1-6`): es contar frecuencias, cabe en el SQLite, es
exacto y no se inventa vías.

### 7.1 Registrar (`record`, `:62-76`)

`INSERT OR IGNORE INTO platform_obs (day, seen_at, stop_id, line_id, dest,
train, aimed, weekday, platform)` con `day`/`weekday` de París, `dest`
normalizado, `aimed` = `HH:MM`. El índice único `(day, stop_id, line_id,
train, aimed, dest)` hace que un mismo tren cuente **una vez al día** aunque
la pantalla refresque 40 veces (`app/db.py:70-72, 85-86`). Devuelve si la
fila era nueva.

Fuentes: el tablero (`record_board`, `:79-106`, con lo que ya se ha pedido,
sin gastar cuota), el recolector y `tools/seed_platforms.py` (siembra desde el
sondeo).

### 7.2 Predecir (`predict`, `:144-182`)

Tres niveles, del más fiable al más vago:

| Nivel (`basis`) | Filtro SQL | Tipo de día |
|---|---|---|
| `mision` | `stop_id, line_id, train` (número de misión) | **no** filtra |
| `hora` | `stop_id, line_id, dest, aimed` | laborable o fin de semana, según `weekday >= 5` |
| `linea` | `stop_id, line_id, dest` | ídem |

Para cada nivel, `_best` (`:123-141`):

- Si hay menos de `MIN_SAMPLES = 3` observaciones → "no sé todavía": se baja
  al siguiente nivel.
- Si hay ≥3 pero el andén mayoritario no supera **estrictamente**
  `MIN_SHARE = 0.5` → "lo sé, y no hay vía clara": se devuelve `null` sin
  bajar de nivel (`:29-33, 126-138`). Con 4 y 4 no se pinta nada.
- Si no, `{platform, share (2 decimales), samples, basis, why}` con `why` =
  `por el número de tren` / `por la hora habitual` / `por la línea`.

`annotate` (`:185-198`) rellena `guess` solo en salidas sin andén real.

### 7.3 Puntuar el acierto (`record_board` `:79-106`, `score` `:203-212`, `accuracy` `:215-231`)

Cuando el **tablero** registra un andén nuevo para hoy, pregunta a la
previsión qué habría dicho **excluyendo los datos de hoy** (`exclude_day`,
`:111-120`, "sin hacer trampa") y guarda en `platform_score` si acertó.
`accuracy()` = filas de `platform_score`, suma de aciertos, tasa (2
decimales), filas y días distintos de `platform_obs`. `coverage(route)` cuenta
por tramo observaciones, días y vías distintas (`:234-248`).

Contexto de datos (`app/platform.py:17-19`, `app/collector.py:31-32`): el
sondeo del 30/08/2026 midió que la vía aparece en el 17 % de los trenes y con
7,7 min de mediana de antelación. Recalculado ahora con los scripts del repo:
de los 421 trenes con salida dentro de la ventana, 16,2 % en Saint-Lazare y
17,6 % en Gare du Nord (`probe/deep2.py`); de los 914 trenes vistos, 98 (10,7 %)
tuvieron vía real en algún momento; antelación mediana 7,7 min (n = 91, de
−0,2 a 21,2 min) (`probe/platform_report.py`). El 30/08/2026 fue **domingo**.

---

## 8. Alternativas (`app/main.py:222-336`)

1. Se piden los avisos (`general-message`). Si fallan sin copia, se sigue sin
   avisos.
2. `affected` = tramos de la ruta con `level > 0` hoy.
3. Si no hay y no se pidió `force`: `{"needed": false, "affected": [], "options": []}`.
   No se gasta Navitia. Es deliberado (`:232-236`): no está en el refresco
   periódico.
4. `journeys(origin_id, dest_id, forbidden=[line_id afectadas])` → Navitia
   calcula evitando esas líneas (`forbidden_uris[]`). Salida "ahora", 3–5
   itinerarios.
5. Duración de referencia: la menor duración de un `journeys` sin
   exclusiones, guardada 12 h por ruta en memoria.
6. **Comprobación de que la alternativa no esté caída** (`:289-309`): para
   cada sección de transporte público de las 6 primeras journeys se saca la
   línea de `links[type=line]` y se evalúa con **los mismos avisos**
   (`line_status`). Una línea interrumpida marca la opción `usable: false`;
   una perturbada solo sube su `worst_level`.
7. Orden `(no usable, worst_level, total_minutes)` y se devuelven 2, con
   `delta_minutes` frente a la referencia.

---

## 9. Traducción con Ollama (`app/translate.py`)

- **Qué**: los textos de `status.messages` del tablero (avisos activos, ≤3
  por línea), del francés al español. El original nunca se pierde: la
  traducción va al lado en `messages_es` (`:9-10`).
- **Prompt** (`:32-38`), literal:
  > Traduce al español este aviso del transporte público de París. Tradúcelo
  > ENTERO y con todo el detalle: no resumas, no omitas causas, horas, nombres
  > de estaciones ni de líneas. Los nombres propios de estaciones y líneas se
  > dejan en francés tal cual. Responde SOLO con la traducción, sin comillas
  > ni comentarios.
  seguido de dos saltos de línea y el texto.
- **Llamada** (`:99-114`): `POST {OLLAMA_URL}/api/generate` con
  `{"model": OLLAMA_MODEL, "prompt": …, "stream": false, "keep_alive": "30s",
  "options": {"temperature": 0.1, "num_predict": 600}}`, timeout 45 s.
  `keep_alive` corto porque el NAS tiene menos de 1 GB libre (`:106-109`).
- **Caché**: tabla `translations`, clave `sha256(texto)[:32]`, con el francés,
  el español, el modelo y la fecha (`:45-61`, `app/db.py:103-111`).
  `INSERT OR REPLACE`. Sin caducidad.
- **Sin esperar al modelo** (`translate_board`, `:141-172`): pone las
  traducciones ya cacheadas y lanza las que faltan como tareas en segundo
  plano (guardadas en `_en_curso` para no duplicar y para tener referencia
  fuerte, `:127-138`); aparecen en el siguiente refresco. El docstring estima
  unos 17 s por aviso nuevo con `gemma3:4b` incluida la carga.
  `translating = OLLAMA_URL configurada y falta alguna`.
- **Fallback**: sin `OLLAMA_URL`, sin modelo, error o respuesta vacía →
  `None`, el aviso sigue en francés. Los fallos no se recuerdan: cada refresco
  vuelve a lanzar la traducción pendiente.
- **Disponibilidad** (`available`, `:64-84`): `GET /api/tags` con timeout 5 s;
  el modelo vale si coincide el nombre o la parte antes de `:`.
- **URL por defecto**: vacía en el código (`app/config.py:30`); los compose la
  rellenan (sección 13).

---

## 10. Planificador (`app/planner.py`)

1. `GET /api/search/places` busca paradas, direcciones y sitios; el id de una
   dirección es `lon;lat` y vale directamente para `journeys`
   (`app/prim.py:157-162`).
2. `GET /api/plan` → `journeys` con `count=4`; `when_param` convierte `HH:MM`
   a `YYYYMMDDTHHMMSS` en hora de París y, si ya pasó hoy, mañana
   (`:202-219`).
3. `parse_journeys` (`:53-118`): suma a pie `street_network`, `crow_fly` y
   `transfer`; toma solo `public_transport`; descarta itinerarios solo a pie;
   ordena (por salida: más rápido y menos transbordos; por llegada: el que
   sale más tarde) y deja uno por combinación de `line_id`.
4. `POST /api/routes/from-plan` → `route_from_option` (`:155-199`):
   `resolve_direction` por tramo traduce la dirección de Navitia ("La Défense
   (Puteaux)") al destino SIRI que circula ahora ("La Défense"): igualdad
   normalizada, contención, o prefijo de `max(6, len/2)` caracteres de lo que
   hay antes de ` (` (`:121-152`). Sin coincidencia, lista vacía (sin filtro)
   y el endpoint lo avisa en `without_direction`. La duración real del
   itinerario va a `duration_min` para que la franja salga exacta.

---

## 11. Estadísticas y salud

- `db.stats(days)` (`app/db.py:289-315`): por mes (`bad_days`, `total_days`,
  `avg_delay`), por línea (top 10 de `worst_line` con `disrupted > 0`) y
  global (`n`, `avg_delay`, `max_delay`), filtrando `day >= date('now',
  '-N days')`.
- `/api/platform-model`: `accuracy()`, estado del recolector y cobertura de
  la ruta.
- `/api/health`: clave configurada, cuota, último error, hora de París,
  recolector, `accuracy()` y `available()` de Ollama.

---

## 12. Esquema SQLite completo (`app/db.py:9-112`)

Fichero: `TRAJET_DB` (por defecto `./data/trajet.db`; en Docker
`/data/trajet.db`). `PRAGMA journal_mode = WAL` (persistente) y
`PRAGMA foreign_keys = ON` en cada conexión (`:10-11, 122`). Cada operación
abre una conexión nueva con `timeout=10`, `row_factory=Row`, hace commit al
salir y cierra (`:115-133`). Crea el directorio si no existe.

### 12.1 Tablas

**`routes`** — rutas del usuario.

| Columna | Tipo | Restricciones / defecto | Notas |
|---|---|---|---|
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| `name` | TEXT | NOT NULL | |
| `origin_id` | TEXT | NOT NULL | Id Navitia o `lon;lat` |
| `origin_name` | TEXT | NOT NULL | |
| `dest_id` | TEXT | NOT NULL | |
| `dest_name` | TEXT | NOT NULL | |
| `days` | TEXT | NOT NULL DEFAULT `'0,1,2,3,4'` | 0 = lunes |
| `time_from` | TEXT | NOT NULL DEFAULT `'07:00'` | `HH:MM` París |
| `time_to` | TEXT | NOT NULL DEFAULT `'10:00'` | |
| `time_mode` | TEXT | NOT NULL DEFAULT `'window'` | Migración |
| `time_at` | TEXT | NOT NULL DEFAULT `''` | Migración |
| `duration_min` | INTEGER | NOT NULL DEFAULT 0 | Migración |
| `position` | INTEGER | NOT NULL DEFAULT 0 | |
| `created_at` | TEXT | NOT NULL DEFAULT `(datetime('now'))` | UTC |

**`legs`** — tramos de cada ruta.

| Columna | Tipo | Restricciones / defecto | Notas |
|---|---|---|---|
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Cambia en cada PUT |
| `route_id` | INTEGER | NOT NULL, `REFERENCES routes(id) ON DELETE CASCADE` | |
| `seq` | INTEGER | NOT NULL | 0..n-1 |
| `line_id` | TEXT | NOT NULL | `line:IDFM:Cnnnnn` |
| `line_code` | TEXT | NOT NULL | |
| `line_name` | TEXT | NOT NULL DEFAULT `''` | |
| `line_mode` | TEXT | NOT NULL DEFAULT `''` | |
| `line_color` | TEXT | NOT NULL DEFAULT `''` | |
| `from_id` | TEXT | NOT NULL | `stop_area:IDFM:…` |
| `from_name` | TEXT | NOT NULL | |
| `to_id` | TEXT | NOT NULL DEFAULT `''` | |
| `to_name` | TEXT | NOT NULL DEFAULT `''` | |
| `directions` | TEXT | NOT NULL DEFAULT `'[]'` | JSON |

**`history`** — una observación por consulta del tablero (como mucho cada 10 min por ruta).

| Columna | Tipo | Restricciones / defecto | Notas |
|---|---|---|---|
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| `route_id` | INTEGER | NOT NULL, `REFERENCES routes(id) ON DELETE CASCADE` | |
| `ts` | TEXT | NOT NULL | ISO UTC con segundos |
| `day` | TEXT | NOT NULL | `YYYY-MM-DD` París |
| `disrupted` | INTEGER | NOT NULL DEFAULT 0 | `worst_level` 0/1/2 |
| `delay_min` | REAL | NOT NULL DEFAULT 0 | `max_delay` |
| `worst_line` | TEXT | NOT NULL DEFAULT `''` | |
| `detail` | TEXT | NOT NULL DEFAULT `'{}'` | JSON, ver 5.7 |

**`platform_obs`** — andenes observados.

| Columna | Tipo | Restricciones / defecto | Notas |
|---|---|---|---|
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| `day` | TEXT | NOT NULL | `YYYY-MM-DD` París |
| `seen_at` | TEXT | NOT NULL | ISO París con desfase |
| `stop_id` | TEXT | NOT NULL | Navitia |
| `line_id` | TEXT | NOT NULL | Navitia |
| `dest` | TEXT | NOT NULL | Normalizado (`norm_text`) |
| `train` | TEXT | NOT NULL DEFAULT `''` | Número de misión |
| `aimed` | TEXT | NOT NULL DEFAULT `''` | `HH:MM` (teórica o, si falta, prevista) |
| `weekday` | INTEGER | NOT NULL | 0 = lunes |
| `platform` | TEXT | NOT NULL | |

**`platform_score`** — aciertos de la previsión.

| Columna | Tipo | Restricciones | Notas |
|---|---|---|---|
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | |
| `day` | TEXT | NOT NULL | París |
| `stop_id` | TEXT | NOT NULL | |
| `line_id` | TEXT | NOT NULL | |
| `predicted` | TEXT | NOT NULL | |
| `actual` | TEXT | NOT NULL | |
| `hit` | INTEGER | NOT NULL | 0/1 |

**`translations`** — caché de traducciones.

| Columna | Tipo | Restricciones / defecto | Notas |
|---|---|---|---|
| `k` | TEXT | PRIMARY KEY | `sha256(fr)[:32]` |
| `fr` | TEXT | NOT NULL | Original |
| `es` | TEXT | NOT NULL | |
| `model` | TEXT | NOT NULL DEFAULT `''` | `OLLAMA_MODEL` |
| `ts` | TEXT | NOT NULL | `datetime('now')` UTC |

(`sqlite_sequence` existe además por los `AUTOINCREMENT`.)

### 12.2 Índices

| Índice | Tabla | Columnas | Único |
|---|---|---|---|
| `idx_legs_route` | legs | `(route_id, seq)` | no |
| `idx_hist_route_day` | history | `(route_id, day)` | no |
| `idx_hist_ts` | history | `(ts)` | no |
| `idx_obs_unico` | platform_obs | `(day, stop_id, line_id, train, aimed, dest)` | **sí** |
| `idx_obs_tren` | platform_obs | `(stop_id, line_id, train)` | no |
| `idx_obs_hora` | platform_obs | `(stop_id, line_id, dest, aimed)` | no |
| `idx_score_unico` | platform_score | `(day, stop_id, line_id, predicted, actual)` | **sí** |

Claves foráneas: solo `legs.route_id` y `history.route_id` → `routes.id` con
`ON DELETE CASCADE`. `platform_obs`, `platform_score` y `translations` no
están ligadas a rutas.

### 12.3 Creación y migración

`db.init()` en el arranque (`app/main.py:33`): `executescript(SCHEMA)` con
`CREATE TABLE/INDEX IF NOT EXISTS` y luego `MIGRACIONES` (`app/db.py:136-152`):
para `routes.time_mode`, `routes.time_at`, `routes.duration_min`, si la
columna no está en `PRAGMA table_info` se hace `ALTER TABLE ADD COLUMN`. Es
idempotente (`tools/test_routes.py:55-62` lo prueba desde el esquema v1). No
hay número de versión (`PRAGMA user_version`) ni migraciones de índices o de
otras tablas.

### 12.4 Qué datos son del usuario

| Tabla | Naturaleza | ¿Se puede regenerar? |
|---|---|---|
| `routes`, `legs` | Configuración del usuario (sus trayectos) | No |
| `history` | Uso e incidencias vividas | No |
| `platform_obs` | Andenes aprendidos (302 filas al migrar a la app del store, según `pasar-al-store.sh:14`) | No (solo reaprendiendo durante días) |
| `platform_score` | Métrica de acierto | No |
| `translations` | Caché | Sí (volviendo a traducir) |

Ninguna tabla tiene retención ni limpieza: todo crece indefinidamente.

---

## 13. Variables de entorno

| Variable | Defecto en código | Dónde | Efecto |
|---|---|---|---|
| `PRIM_API_KEY` | `""` | `app/config.py:9` | Cabecera `apikey`. Vacía: la app arranca y avisa en el log (`app/main.py:30-32`). |
| `TRAJET_DB` | `./data/trajet.db` | `app/config.py:10` | Ruta del SQLite. El Dockerfile pone `/data/trajet.db`. |
| `TRAJET_COLLECT` | `1` | `app/config.py:26` | Apaga el recolector con `0`, `false` o `no` (sensible a mayúsculas: `False` lo deja encendido). |
| `OLLAMA_URL` | `""` | `app/config.py:30` | Sin barra final. Vacía = sin traducción. |
| `OLLAMA_MODEL` | `gemma3:4b` | `app/config.py:31` | |
| `TZ` | — | `Dockerfile:5`, compose | Solo afecta a los logs: el código usa `ZoneInfo("Europe/Paris")` fijo (`app/config.py:22`). |

No configurables (constantes en `Settings`): TTL (25/150/600/86 400/86 400 s,
`app/config.py:15-19`), `refresh_seconds = 30` (`:21`), zona horaria.
`Settings` se evalúa **al importar** el módulo (`app/config.py:34`).

---

## 14. Docker y despliegue actual

### 14.1 Imagen (`Dockerfile`)

`python:3.12-slim`; `PYTHONUNBUFFERED=1`, `PYTHONDONTWRITEBYTECODE=1`,
`TZ=Europe/Paris`; instala `tzdata` y `curl`; `pip install` de
`requirements.txt` (`fastapi==0.115.6`, `uvicorn[standard]==0.34.0`,
`httpx==0.28.1`, `tzdata==2024.2`); copia `app/` **y `tools/`** (con las
pruebas y los scripts de sondeo); `VOLUME /data`; `TRAJET_DB=/data/trajet.db`;
`EXPOSE 8000`; `HEALTHCHECK` cada 30 s, timeout 5 s, arranque 10 s, 3
reintentos, con `curl -fsS http://127.0.0.1:8000/api/health`; `CMD uvicorn
app.main:app --host 0.0.0.0 --port 8000`. Corre como root (no hay `USER`).

### 14.2 Stack de pruebas (`docker-compose.yml` del repo, `~/trajet` en el NAS)

Servicio `trajet`, `build: .`, imagen `trajet:latest`, `restart:
unless-stopped`; `PRIM_API_KEY: ${PRIM_API_KEY:?…}` (obligatoria, del `.env`
de al lado), `OLLAMA_URL` por defecto `http://172.18.0.1:11434` (puerta de
enlace del bridge), volumen `./data:/data`, puerto `7796:8000` (en todas las
interfaces del host; el comentario dice "solo red local / Tailscale").

### 14.3 App de Umbrel (`C:\Users\Isma\umbrel-app-store\ismaeloul-trajet\`)

- `umbrel-app.yml`: id `ismaeloul-trajet`, versión `0.3.0`, categoría
  `automation`, `port: 7796`, sin dependencias; la descripción pide la clave
  PRIM en `PRIM_API_KEY`.
- `docker-compose.yml`: `app_proxy` con `APP_HOST: ismaeloul-trajet_web_1`,
  `APP_PORT: "8000"` y **`PROXY_AUTH_ADD: "false"`** (sin login de Umbrel
  delante, `:13-14`); servicio `web` con imagen
  `localhost:5000/ismaeloul-trajet/trajet:0.3.0` (registro local del NAS
  porque umbreld ignora `pull_policy`, `:3-6`), `init: true`,
  `PRIM_API_KEY: "${PRIM_API_KEY:-}"`, `OLLAMA_URL` por defecto
  `http://ollama_ollama_1:11434` (red `umbrel_main_network`),
  `TRAJET_COLLECT: "${TRAJET_COLLECT:-1}"`, volumen
  `${APP_DATA_DIR}/data:/data`, `mem_limit: 384m`, `pids_limit: 128`.
- El comentario remite a `scripts/publish.sh` "del repo de Trajet" para
  publicar la imagen; **ese script no está en `trajet-server`**.

### 14.4 Paso del stack de pruebas a la app del store (`pasar-al-store.sh`)

1. `git pull` del store cacheado y comprueba que ve la versión 0.3.0.
2. `docker compose down` del stack de pruebas (libera el 7796).
3. `umbreld client apps.install/update.mutate`.
4. Para la app, copia `~/trajet/.env` a `$APP/.env` con `chmod 600`, guarda
   una copia de la BD existente y copia `~/trajet/data/trajet.db`; imprime
   cuántas filas hay en `routes`, `platform_obs` y `translations`.
5. Arranca y consulta `/api/health` hasta 45 veces; si `key_configured` no
   es `True`, explica el plan B: poner la clave a mano en la línea
   `PRIM_API_KEY` del `docker-compose.yml` de la app (se pierde al
   actualizar).

---

## 15. La PWA de `app/static` (lo que desaparece con la app iOS)

Qué hace hoy:

- **Tablero** (`app/static/app.js:151-518`): pide `/api/board` al arrancar y
  cada 30 s solo con la pestaña visible; al volver a primer plano refresca si
  el dato tiene más de 15 s; tirar hacia abajo refresca con un mínimo de 3 s
  entre tirones (`:1241-1289`). Pinta cada tramo con su color, las salidas en
  tira horizontal, "en andén"/"ya"/minutos, icono de ritmo (≤3 min corre, ≤8
  anda, más: café), vía real o "probable" (`guess`), tren corto/largo, aviso
  pegado a su línea con la traducción y el original desplegable, botón
  "Buscar alternativa" (`/api/alternatives`), frescura del dato y "quedan N
  llamadas hoy". Oscurece todo el tablero si `stale` (`:237`). No pinta vía
  en metro, bus, tranvía ni funicular (`NO_PLATFORM_MODES`, `:9`).
- **Rutas**: lista y selector de ruta activa; editor manual (buscador de
  paradas `/api/search/stops`, líneas `/api/stops/{id}/lines` cacheadas en la
  sesión, direcciones `/api/stops/{id}/directions`, días, modo horario con
  vista previa de la franja, POST/PUT/DELETE).
- **Buscar**: planificador (`/api/search/places` desde 3 caracteres con
  espera de 350 ms, `/api/plan`, guardar con `/api/routes/from-plan`).
- **Historial**: `/api/stats` y `/api/platform-model`.
- **Instalable**: `manifest.webmanifest` (standalone, vertical, iconos) y
  `sw.js`: caché `trajet-shell` del armazón (HTML, CSS, JS, iconos, fuente),
  red primero con 2,5 s de espera, **nunca toca `/api/`**; solo se registra en
  contexto seguro (`app.js:1361-1364`).

La PWA no usa `/api/health`, ni `force`, `log_history`, `days` o el
`route_id` de `/api/platform-model`.

Qué se elimina con ella:

| Pieza | Dónde |
|---|---|
| Ficheros | `app/static/index.html` (225 líneas), `app.js` (1374), `style.css` (751), `sw.js` (97), `manifest.webmanifest` (35), `fonts/archivo.woff2`, `icons/{apple-touch-icon,favicon-32,icon-192,icon-512,icon-maskable-512}.png` |
| Rutas del servidor | `GET /`, `/manifest.webmanifest`, `/sw.js`, `/apple-touch-icon.png`, `/apple-touch-icon-precomposed.png`, `/favicon.ico` y el `mount("/static")` (`app/main.py:436-479`), con `STATIC` (`:25`) y los imports de `FileResponse`/`StaticFiles` |
| Herramientas | `tools/make_icons.py`, `tools/render_test.js`, `tools/test_sw.js`, `tools/fixtures/`, `tools/fixtures5/` (solo los usa `render_test.js`) |
| Lógica duplicada que habrá que llevar a iOS | `previewWindow` = `derive_window` (`app.js:851-867`); `NO_PLATFORM_MODES` ≈ `SIN_ANDEN` (`app.js:9`, sin `funiculaire`); `emptyLeg` decide "servicio finalizado" si la hora local es ≥23 o <5 (`app.js:344-354`) |

**Ojo**: lo que sirve hoy producción en 7796 no es exactamente
`app/static` del repo. Los ficheros `index.html`, `app.js`, `style.css` y
`sw.js` guardados en `scratchpad/live/` junto al `openapi.json` de producción
difieren del repo: producción usa las fuentes
`geist.woff2` y `geist-mono.woff2` y un tema solo oscuro
(`color-scheme: dark`), y el repo usa `archivo.woff2` y tema claro/oscuro. El
backend Python sí es idéntico (los `.py` coinciden con la copia del NAS en
`scratchpad/nas-trajet/` y el `openapi.json` coincide).

---

## 16. Herramientas, sondeo y pruebas del repo

| Fichero | Qué hace | ¿Gasta cuota PRIM? |
|---|---|---|
| `tools/platform_probe.py` = `probe/platform_probe.py` (idénticos) | Sondeo con stdlib: `stop-monitoring` de 71370 cada 60 s y 71410 cada 120 s entre 2026-08-30 05:00 y 07:00 UTC; lee la clave de un `.env` junto al script o del entorno; escribe `probe_observations.jsonl` y `probe.log` | **Sí** (180 llamadas en su día) |
| `tools/platform_report.py` = `probe/platform_report.py` | Analiza el JSONL: valores de andén, trenes con vía, antelación, frescura | No |
| `probe/deep.py` | Andén por línea y frescura por cercanía; la segunda parte lee `sample_at`/`station`, que no existen en el JSONL (`t`/`st`), así que no imprime nada | No |
| `probe/deep2.py` | Cobertura "honesta" (trenes dentro de la ventana), frescura, retrasos | No |
| `probe/deep3.py` | Qué líneas traen hora teórica | No |
| `probe/probe.log` | 183 líneas: espera 5,64 h, 180 llamadas, cuota 999 → 820 | — |
| `probe/stdout.log` | Vacío | — |
| `probe/probe_observations.jsonl` | 32 122 filas (21 697 Saint-Lazare, 10 425 Gare du Nord), 130 muestras, campos `t, st, jid, ref, line, dest, train, aimed, exp, pdep, parr, dstat, atstop, rec` | — |
| `tools/seed_platforms.py` | Siembra `platform_obs` desde el JSONL (usa `pdep` o, si no, `parr`; `aimed` o, si no, `exp`) | No |
| `tools/test_platform.py` | Previsión y recolector sobre BD temporal | No (pasa) |
| `tools/test_routes.py` | Franjas, ruta activa y migración | No (pasa) |
| `tools/test_resilience.py` | Caché, cuota, degradación, lock, tablero con fallo | No (pasa) |
| `tools/test_plan.py`, `tools/test_arrival.py` | Extremo a extremo contra una instancia (`TRAJET_URL`, por defecto `http://localhost:7796`); crean y borran una ruta de prueba | **Sí**, 3–4 llamadas Navitia |
| `test_plan.py`, `test_arrival.py` (raíz) | Versiones anteriores de las de `tools/`, con `localhost:7796` fijo | Sí |
| `diag.py`, `show.py` (raíz) | Scripts manuales contra `localhost:7796` (buscador y tablero) | Sí (vía la app) |
| `tools/make_icons.py`, `tools/render_test.js`, `tools/test_sw.js` | PWA (ver 15) | No |

Datos del sondeo recalculados con esos scripts: `DeparturePlatformName`
vale `unknown` 12 320 veces en Saint-Lazare y 7 371 en Gare du Nord, falta
9 039 y 2 734 veces; `AimedDepartureTime` viene en el 30,3 % de las filas; el
retraso observado tiene mediana 0 y máximo 14 min; `PARIS NORD` no aparece
como andén en este JSONL.

---

## 17. Reglas y decisiones encontradas en el código

| Id | Fichero:línea | Qué dice | Por qué (según el código) |
|---|---|---|---|
| PRIM-CABECERA | `app/prim.py:4, 71` | Autenticación con cabecera `apikey` | `API Key` devuelve 401 |
| PRIM-BASE | `app/prim.py:5, 23-25` | Navitia en `/marketplace/v2/navitia/` | No es `/v2/navitia/` |
| PRIM-CUOTA | `app/prim.py:6-8`; `app/config.py:12-14` | 1000 llamadas/día por endpoint, reinicio medianoche UTC; el limitante es stop-monitoring | Se refresca cada 30 s |
| PRIM-ESTACION | `app/prim.py:9-10`; `app/board.py:371-372`; `app/collector.py:93-96` | Una llamada por StopArea padre, no por línea | Devuelve todos los andenes hijos |
| PRIM-TIMEOUT | `app/prim.py:70-72` | 20 s total, 8 s conexión, 8 conexiones | — |
| PRIM-SIN-REINTENTO | `app/prim.py:102-123` | Ningún reintento; fallo → copia vieja o `PrimError` | "más vale un dato de hace 2 minutos que una pantalla en blanco" (`:88-90`) |
| CACHE-TTL-LLAMANTE | `app/prim.py:28-38` | La entrada no guarda TTL; lo decide quien pregunta | Tablero y recolector no se pisan el TTL |
| CACHE-LOCK | `app/prim.py:96-100` | Lock por clave y doble comprobación | Peticiones simultáneas = 1 llamada |
| TTL-SM | `app/config.py:15` | 25 s | El front refresca cada 30 s |
| TTL-GM | `app/config.py:16` | 150 s | Una llamada cubre todas las líneas |
| TTL-JOURNEYS | `app/config.py:17` | 600 s | Caro |
| TTL-PLACES / TTL-LINES | `app/config.py:18-19` | 24 h | No cambian |
| TTL-CERCANIA | `app/board.py:337-354` | 20/30/90/300/600 s según próximo paso ≤3/≤8/≤20/≤45/más min | 5 tramos a 30 s = 600 llamadas/h (`:331-336`) |
| TABLERO-STALE | `app/board.py:446`; `app/config.py:21` | `stale` si el dato tiene > 90 s | 3 × refresco de 30 s |
| JOURNEYS-N | `app/prim.py:202-208`; `app/main.py:386` | `min_nb = count`, `max_nb = count + 2`, `data_freshness=realtime`; 4 en el planificador, 3 en alternativas | — |
| JOURNEYS-ARRIVAL | `app/prim.py:209-213` | `datetime_represents` solo si hay `datetime` | "arrival planifica hacia atrás" |
| FORBIDDEN | `app/prim.py:197-200, 214-215` | Un `forbidden_uris[]` por línea | Clave del PASO 2 |
| PLACES-N | `app/prim.py:156`; `app/main.py:350` | 12 resultados (paradas), 10 (planificador) | — |
| LINES-N | `app/prim.py:186` | `count=60` | — |
| IDS | `app/idfm.py:1-9` | Se guarda el id Navitia; SIRI al vuelo | El buscador devuelve Navitia |
| AVISO-INTERRUMPIDO | `app/board.py:21-33` | Regex de "tráfico cortado" admite `est/sera/reste/sont/seront` | "la línea 13 cortada de verdad el 30/08 salía solo como perturbada" |
| NIVELES | `app/board.py:35` | 0 normal, 1 perturbada, 2 interrumpida | — |
| AVISO-CADUCADO | `app/board.py:167-169` | Se ignora si `ValidUntilTime` ya pasó | — |
| AVISO-TEXTO | `app/board.py:177-178` | Se muestra el texto más corto | SHORT_MESSAGE suele ser el más legible |
| AVISO-FUTURO | `app/board.py:180-182, 195-214` | Aviso con inicio futuro no enciende el semáforo (va a `planned`) | "Sin este filtro casi todas las líneas salían en rojo" |
| AVISO-MAX-3 | `app/board.py:212` | Como mucho 3 mensajes por línea | — |
| AVISO-LINEAS | `app/idfm.py:44-57` | Línea por `LineRef` o por `IDFM.Cnnnnn` en `ItemIdentifier` | Solo 22/328 traen LineRef; con ambos, 99,7 % |
| FECHA-PRESENTE | `app/frdate.py:27-34` | Si el texto habla en presente, es activo aunque cite fechas | "reprise estimée le 3 septembre" pasa ahora |
| FECHA-DUDA | `app/frdate.py:8-9` | Ante la duda, activo | Mejor un aviso de más que callar una interrupción |
| FECHA-AÑO | `app/frdate.py:40-50` | Año más cercano; nunca más de 60 días atrás | Los avisos no llevan año |
| FECHA-JUSQUA | `app/frdate.py:36-37, 75-77` | `jusqu'au X` antes de la primera fecha ⇒ ya empezó | — |
| SALIDA-PASADA | `app/board.py:249-251` | Se descarta si salió hace más de 1 min | "ya se ha ido" |
| SALIDA-MINUTOS | `app/board.py:276` | Minutos redondeados, nunca negativos | — |
| SALIDA-PREVISTA | `app/board.py:243-248` | Prevista de salida, si no de llegada; sin prevista, fuera | — |
| RETRASO-TEORICA | `app/board.py:253-257` | Retraso solo con hora teórica | En bus casi nunca viene |
| SALIDAS-4 | `app/board.py:219, 297-298` | 4 salidas por tramo | — |
| DIRECCION-NORMALIZADA | `app/board.py:222, 240-241`; `app/idfm.py:89-106` | Comparación sin tildes, guiones unificados, espacios colapsados | Espacios finos/duros dejaban el tablero vacío |
| ANDEN-REAL | `app/idfm.py:69-86` | Fuera `unknown`, vacío y nombres de estación de París | Observado en la API |
| ANDEN-NUEVO | `app/board.py:37-56, 264-272` | `platform_new` al aparecer vía; memoria de 4000 viajes | Hay que "cantarlo"; 198 salidas por estación como mucho |
| TREN-LONGITUD | `app/board.py:58-65, 289-294` | `shortTrain`/`longTrain` → short/long | No hay ocupación; en un tren corto vas más apretado |
| PEOR-LINEA | `app/board.py:407-418` | Peor estado manda; si todo normal, la del mayor retraso | — |
| HISTORIAL-10MIN | `app/board.py:453-460` | Una fila de historial cada ≥600 s por ruta | No duplicar |
| RUTA-CONCRETA | `app/board.py:139-146` | Entre las que encajan, la franja más estrecha | La genérica tapaba a la buena |
| RUTA-NUNCA-VACIA | `app/board.py:128-151` | Siempre devuelve alguna ruta | Nunca dejar la pantalla vacía |
| FRANJA | `app/board.py:81-122` | 60 min por defecto, 45 antes, 30 después (15 en llegada) | Traducir hora de salida/llegada a franja |
| FRANJA-GUARDADA | `app/db.py:202-208` | La franja se guarda siempre | Es lo que consulta todo lo demás |
| FRANJA-DEFECTO | `app/db.py:21, 24-25`; `app/planner.py:189-191` | L–V, 07:00–10:00 | — |
| MODO-COERCION | `app/db.py:196-198` | `time_mode` desconocido → `window` | — |
| RECOLECTOR-MIN | `app/collector.py:31-33` | ≥120 s entre pasadas | Vía con 7,7 min de mediana |
| RECOLECTOR-MAX | `app/collector.py:34-35` | ≤1800 s mientras haya cuota | Si no, no aprende |
| RECOLECTOR-RESERVA | `app/collector.py:37-40` | 320 llamadas reservadas a la pantalla | Una ruta de 5 tramos cuesta 5 por refresco |
| RECOLECTOR-PRIORIDAD | `app/collector.py:42-44, 64-75` | En franja (±30 min) muestrea 3× más | Ahí importa pillar el momento |
| RECOLECTOR-NOCHE | `app/collector.py:46-48, 78-80` | Nada entre 01:00 y 05:00 París | No circula casi nada |
| RECOLECTOR-MODOS | `app/collector.py:50-53` | No sondea metro, bus, tranvía, funicular | No publican andén nunca |
| RECOLECTOR-4 | `app/collector.py:83-115`; `app/db.py:268-279` | Máx. 4 estaciones, por uso en 14 días | Con 6 rutas salían 9 estaciones |
| RECOLECTOR-FORMULA | `app/collector.py:13, 145-151` | `intervalo = s_hasta_reset × estaciones / (restante − 320)` | Lazo cerrado con la cuota |
| RECOLECTOR-DESCONOCIDA | `app/collector.py:136-139` | Sin cuota conocida: 300 s | La aprende de la cabecera |
| RECOLECTOR-CACHE | `app/collector.py:180-184` | Acepta caché ≤120 s | Aprender de lo que pidió la pantalla es gratis |
| RECOLECTOR-SIN-DIRECCION | `app/collector.py:195-198` | Aprende todos los sentidos, hasta 60 salidas | Interesan todos los trenes |
| RECOLECTOR-ESPERAS | `app/collector.py:214-216, 226-227` | 15 s al arrancar; 600 s si no toca | — |
| PREVISION-UMBRAL | `app/platform.py:29-33, 133-138` | ≥3 observaciones y cuota > 50 % estricta | "con 4 y 4 no hay mayoría, hay una moneda al aire" |
| PREVISION-NIVELES | `app/platform.py:9-17, 155-182` | Misión > hora teórica > línea | Orden de fiabilidad |
| PREVISION-CONCLUYENTE | `app/platform.py:123-131, 162-164` | Con datos pero sin mayoría no baja de nivel | Un promedio de línea "seguro" sería mentira |
| PREVISION-TIPO-DIA | `app/platform.py:45-47, 166-182` | Laborable y fin de semana separados (niveles 2 y 3) | Horarios distintos |
| PREVISION-HORA-TEORICA | `app/board.py:278-281` | Se aprende con la teórica | La prevista se mueve con el retraso |
| PREVISION-1-POR-DIA | `app/db.py:70-72, 85-86` | Una fila por tren y día | Si no, un tren contaría 40 veces |
| PREVISION-SIN-TRAMPA | `app/platform.py:96-105, 111-120` | Se puntúa excluyendo el día de hoy | Los datos de hoy son la respuesta |
| PREVISION-SOLO-MIS-RUTAS | `app/platform.py:17-19`; `app/db.py:67-69` | Solo estaciones de las rutas guardadas | No estudiar toda la red |
| PREVISION-NO-LLM | `app/platform.py:1-6` | Tabla de frecuencias, no LLM | Exacto, rápido, no inventa vías |
| ALT-BAJO-DEMANDA | `app/main.py:230-236, 261-262` | Solo con línea tocada o `force` | Comparte cuota con el buscador |
| ALT-EXCLUIR | `app/main.py:264-267` | Excluye las líneas tocadas | — |
| ALT-REFERENCIA | `app/main.py:224-227, 271-282` | Duración de referencia 12 h | "no cambia de un día para otro" |
| ALT-CAIDA | `app/main.py:295-301` | Alternativa con línea interrumpida → no usable | "no sirve mandarme por otra línea que también está caída" |
| ALT-ORDEN | `app/main.py:285, 327-332` | Mira 6, ordena por usable/peor nivel/duración, devuelve 2 | — |
| TRAD-ORIGINAL | `app/translate.py:9-10` | El francés nunca se pierde | Poder comprobar la traducción |
| TRAD-ENTERO | `app/translate.py:11, 32-38` | Traducir entero, sin resumir | Lo interesante es el detalle |
| TRAD-TIMEOUT | `app/translate.py:40-42, 69` | 45 s generar, 5 s comprobar | No hacer esperar |
| TRAD-MEMORIA | `app/translate.py:106-110` | `keep_alive: 30s` | NAS con < 1 GB libre |
| TRAD-FIEL | `app/translate.py:111-113` | `temperature 0.1`, `num_predict 600` | Fiel, no bonita |
| TRAD-SIN-ESPERA | `app/translate.py:141-148` | Segundo plano; aparece en el refresco siguiente | ~17 s por aviso nuevo |
| TRAD-CACHE | `app/translate.py:12-13, 45-61` | Una vez por texto, para siempre | Los avisos duran horas o días |
| TRAD-TAREA | `app/translate.py:127-131` | Se guarda la tarea, no solo el hash | Referencias débiles del bucle |
| PLAN-A-PIE | `app/planner.py:22-24, 88-90` | `street_network`, `crow_fly`, `transfer` = andar; itinerario solo a pie se descarta | No se puede vigilar |
| PLAN-ORDEN | `app/planner.py:102-107` | Por salida: rápido; por llegada: el que sale más tarde | "salir lo más tarde posible" |
| PLAN-DEDUP | `app/planner.py:108-117` | Una opción por combinación de líneas | Navitia repite casi iguales |
| PLAN-DIRECCION | `app/planner.py:121-152` | Navitia→SIRI: igual, contención, prefijo `max(6, len/2)` | "La Défense (Puteaux)" vs "La Défense" |
| PLAN-MANANA | `app/planner.py:202-219` | Hora ya pasada → mañana | A las 23:00 "para las 08:00" es mañana |
| PLAN-DURACION | `app/planner.py:194-197` | `duration_min` = duración del itinerario elegido | Franja exacta |
| LINEAS-ORDEN | `app/idfm.py:109-147` | Metro, RER, tren… bus al final; sustitución la última; orden numérico | Saint-Lazare: 38 líneas, 30 buses |
| BUSQUEDA-MIN | `app/main.py:109, 342, 373-374` | `q` ≥2; `from`/`to` ≥3 | — |
| BD-WAL-FK | `app/db.py:10-11, 122` | WAL y claves foráneas | — |
| BD-MIGRACION | `app/db.py:136-152` | `ALTER TABLE ADD COLUMN` idempotente | `CREATE IF NOT EXISTS` no toca tablas existentes |
| SW-SIN-CACHE | `app/main.py:452-461` | `/sw.js` desde la raíz y `no-cache` | Alcance y no quedarse con uno viejo |
| SW-API | `app/static/sw.js:10-12, 61` | `/api/*` nunca pasa por el service worker | Datos de segundos y cuota |
| PWA-VISIBLE | `app/static/app.js:496-518` | Refresco solo con la pantalla delante | Si no, se come la cuota en el bolsillo |
| PWA-TIRON | `app/static/app.js:1238-1240, 1276` | Mínimo 3 s entre tirones | Cada tirón cuesta cuota |
| HEALTHCHECK | `Dockerfile:25-26` | `/api/health` cada 30 s | — |
| ZONA-HORARIA | `app/config.py:22` | Europe/Paris fija | — |

---

## 18. Riesgos y deudas

### 18.1 Seguridad

1. **Sin autenticación** en ninguna ruta (`app/main.py` entero). Cualquiera que
   llegue al puerto 7796 lee, crea, cambia y borra rutas, ve el historial y
   gasta la cuota. En Umbrel el proxy va con `PROXY_AUTH_ADD: "false"`
   (`umbrel-app-store/ismaeloul-trajet/docker-compose.yml:13-14`) y el
   stack de pruebas publica `7796:8000` en todas las interfaces
   (`docker-compose.yml:19-21`). La única barrera es la red (LAN/Tailscale).
2. **Sin límite de uso**: cada `q` distinto de `/api/search/*` es una llamada
   Navitia nueva; cada `route_id`/estación distinta, una de stop-monitoring.
   Agotar la cuota diaria es trivial desde la red.
3. **Sin CORS configurado**: el navegador bloquea las lecturas desde otros
   orígenes y el *preflight* de PUT/DELETE/POST JSON, pero las **GET con
   efectos** (`/api/board` gasta cuota y escribe `history`/`platform_obs`;
   `/api/alternatives`, los buscadores) se pueden disparar desde cualquier
   página que visite un navegador con acceso a la LAN.
4. **Clave en el entorno**: `PRIM_API_KEY` vive en `.env` (fuera de git,
   `.gitignore:2-4`) y en el entorno del contenedor (visible con
   `docker inspect`). No se imprime en logs ni en `/api/health` (solo
   `key_configured`). `pasar-al-store.sh:57-58` la copia con `chmod 600`; su
   plan B es escribirla en el `docker-compose.yml` de la app
   (`pasar-al-store.sh:97-102`). `probe/platform_probe.py:45-54` la lee de un
   `.env` junto al script.
5. **`/openapi.json` expuesto** aunque `/docs` y `/redoc` están apagados.
6. El contenedor corre como **root** y la imagen incluye `tools/` (pruebas y
   scripts de sondeo que gastan cuota).
7. **Entradas sin validar**: cuerpos `dict` sin modelo; varios tipos malos
   dan 500 (confirmado: POST sin `origin_name`, `/api/plan?when=25:00`);
   `from-plan` guarda sin `_validate_route`; `q` sin longitud máxima.

### 18.2 Privacidad y logs

1. El log de acceso de uvicorn guarda la URL completa: `/api/plan?from=<lon;lat de casa>`
   o `/api/search/places?q=<dirección>`.
2. `app/prim.py:119` registra la clave de caché en cada fallo, que incluye el
   texto buscado o las coordenadas (`pl:…`, `jr:<from>><to>…`).
3. `last_error` (con el mensaje de httpx, que incluye la URL de PRIM y sus
   parámetros en errores HTTP) se publica en `/api/health` y en cada tablero.
4. `history`, `routes` y `translations` no se purgan nunca.

### 18.3 Fallos y errores de lógica

Confirmados ejecutando la app con PRIM simulado:

1. **Si `general-message` falla sin copia, todas las líneas salen "normal"** y
   no hay nada en `errors` (`app/board.py:381-386`); el aviso de una línea
   cortada desaparece en silencio.
2. **Con todo caído y sin copia, `data_age = 0.0` y `stale = false`**
   (`app/board.py:392, 445-446`): el tablero vacío se presenta como fresco.
3. **`errors` repite** la misma estación una vez por tramo (`app/board.py:399-400`).
4. `/api/plan?when=25:00` → 500 (`app/planner.py:216`, fuera del `try`).
5. `POST /api/routes` sin `origin_name`/`dest_name` → 500 (`app/db.py:212-213`).

Deducidos leyendo el código (no reproducidos):

6. **`stale` por diseño**: con el TTL adaptativo de 300 o 600 s
   (`app/board.py:337-343`) la copia servida puede tener hasta 300/600 s,
   pero `stale` salta a los 90 s (`:446`) y la PWA oscurece el tablero
   (`app/static/app.js:237`). Basta con que **una** estación de la ruta tenga
   su próximo paso a más de 20 min para que el tablero entero parezca viejo
   durante buena parte de cada ciclo.
7. **TTL de estación pisado por tramo**: `remember_next` se llama por tramo
   (`app/board.py:403-404`); si dos tramos salen de la misma estación, manda
   el último (con su filtro de dirección), no el paso más cercano. Un tramo
   con tren en 2 min puede quedarse con el TTL de 300 s del otro.
8. **El recolector no se despierta tras agotar la cuota**: `remaining` solo
   se actualiza al hacer una llamada (`app/prim.py:105-110`); si la cuota
   quedó por debajo de 320, `plan_interval` devuelve 0 (`app/collector.py:141-143`)
   y no hace ninguna llamada, así que tras la medianoche UTC sigue viendo el
   valor de ayer hasta que alguien abre el tablero.
9. **La tasa de acierto no cuenta trenes**: el índice único de
   `platform_score` es `(day, stop_id, line_id, predicted, actual)`
   (`app/db.py:100-101`); diez aciertos "21→21" de la misma línea y día son
   una fila, mientras que los fallos (combinaciones variadas) se cuentan más.
   La tasa no es "trenes acertados / trenes previstos" (probablemente queda
   sesgada a la baja) y `predictions` no es el número de previsiones.
10. **El recolector le quita al tablero la puntuación**: si el recolector
    registra primero el andén de un tren, el `record()` del tablero devuelve
    `False` (fila ya existente) y no se puntúa (`app/platform.py:90-93`); el
    recolector nunca puntúa (`app/collector.py:201-205`).
11. **El recolector le quita al tablero el aviso de "vía nueva"**: usa
    `extract_departures`, que actualiza la memoria global `_seen_platforms`
    (`app/board.py:264-272`, `app/collector.py:198`).
12. **Varias filas por tren y día cuando falta la hora teórica**: se usa la
    prevista (`d.get("aimed_at") or d.get("at")`, `app/platform.py:92`,
    `app/collector.py:203`), que cambia con el retraso y entra en el índice
    único. Según el sondeo, en las líneas de tren que sí la publican solo
    entre el 44,9 % y el 51,5 % de las filas traen hora teórica
    (`probe/deep3.py`). Infla los conteos.
    `tools/seed_platforms.py:74` hace lo mismo con `exp`.
13. `pick_active_route` sin franja coincidente elige la primera de la lista
    con `time_from >= ahora`, no la más próxima (`app/board.py:149-150`); y no
    admite franjas que crucen medianoche (`:142`).
14. `stats` compara `day` (París) con `date('now')` (UTC) (`app/db.py:297`);
    `days` negativo produce un modificador inválido y respuesta vacía.
15. La PWA etiqueta `by_line[].n` como "días" (`app/static/app.js:1212`) y son
    filas de historial.
16. `_baseline` no se invalida al editar una ruta (`app/main.py:272-273`).
17. `delta_minutes` usa `j["duration"]` sin `get` (`app/main.py:315`): una
    journey sin `duration` daría 500.
18. `mvj.get("TrainNumbers", {}).get(...)` (`app/board.py:288`) lanzaría
    AttributeError si SIRI mandase `TrainNumbers: null`, y esa excepción no
    está dentro del `gather`: 500 en el tablero.
19. `index_disruptions` usa la fecha UTC como "hoy" (`app/board.py:164, 182`):
    entre 00:00 y 02:00 de París un aviso "de hoy" se evalúa con la fecha de
    ayer.
20. `quota` y `last_error` son globales y nunca se reinician: tras la
    medianoche UTC se sigue mostrando la cuota de ayer hasta la siguiente
    llamada; `last_error` se borra con cualquier llamada buena a otro
    endpoint.
21. Sin reintentos ni espera tras fallos: con PRIM caído, cada refresco
    vuelve a intentar todas las estaciones (cada una hasta 20 s).
22. `TRAJET_COLLECT=False` (con mayúscula) deja el recolector encendido
    (`app/config.py:26`).

### 18.4 Rendimiento

1. SQLite abre y cierra una conexión por operación (`app/db.py:115-133`);
   hasta 3 consultas por salida sin andén en cada tablero.
2. Parte del SQLite corre en el bucle de eventos: CRUD de rutas,
   `db.list_routes()` del tablero (`app/main.py:171`), `translate_board`
   (`app/main.py:203`, `app/translate.py:155`) y todas las escrituras del
   recolector (`app/collector.py:201`), a pesar del comentario de
   `app/main.py:191-193` sobre no bloquear el bucle.
3. `sample_once` hace `get_route` por ruta después de `list_routes`, que ya
   trae los tramos (`app/collector.py:162`).
4. `/api/health` hace un `COUNT(*)` completo de `platform_obs` y
   `platform_score` y llama a Ollama (5 s) en cada llamada; el HEALTHCHECK lo
   dispara cada 30 s con un timeout de 5 s igual al de Ollama: un Ollama lento
   puede marcar el contenedor como *unhealthy*.
5. El tablero espera a la estación más lenta: hasta 20 s (8 de conexión) si
   PRIM va lento; no hay plazo global por petición.
6. Obligado a un solo worker: caché, cuota, `_seen_platforms`, `_baseline` y
   el recolector viven en memoria del proceso.

### 18.5 Memoria

1. `PrimClient._cache` y `_locks` crecen sin límite: una entrada por texto
   buscado, por par origen/destino/hora de `journeys` y por estación, con la
   respuesta JSON completa (una respuesta de stop-monitoring de Saint-Lazare
   trae 154–204 visitas según `probe/probe.log`). Nunca se expulsan.
2. `_baseline` guarda rutas borradas; `_next_in` no se limpia (pequeño).
3. Límite del contenedor en Umbrel: 384 MB (`mem_limit`). Ollama se descarga a
   los 30 s por falta de memoria del NAS.

### 18.6 Deuda técnica

1. Código muerto: `PrimClient.line_info` (`app/prim.py:174-181`),
   `idfm.line_to_siri`/`line_to_navitia` (`app/idfm.py:34-41`),
   `platform.BASIS_RANK` (`app/platform.py:37`), `platform._daytype`
   (`app/platform.py:45-47`); el 502 de `/api/board` es inalcanzable.
2. Lógica duplicada entre servidor y PWA (`derive_window`/`previewWindow`,
   `SIN_ANDEN`/`NO_PLATFORM_MODES`) y entre scripts (`real_platform` frente a
   `is_real` de `platform_report.py` y `real` de `deep*.py`, con listas
   distintas).
3. Scripts duplicados: `probe/platform_probe.py` = `tools/platform_probe.py`,
   `probe/platform_report.py` = `tools/platform_report.py`; `test_*.py` de la
   raíz son versiones viejas de los de `tools/`. `probe/deep.py` está roto en
   su segunda mitad.
4. Pruebas como scripts sueltos, sin pytest ni CI; dos gastan cuota real.
5. Sin versión de esquema de BD ni retención de datos.
6. FastAPI sin `version` ni modelos de respuesta (el `openapi.json` no
   describe ninguna respuesta).
7. Referencias a ficheros que no están en el repo: el README de
   `app/prim.py:3` y `app/config.py:14`, y `scripts/publish.sh` del compose
   de Umbrel.
8. La PWA servida en producción no coincide con `app/static` del repo
   (sección 15).
9. Cifras de comentarios no verificables con los datos del repo (211
   salidas sin ocupación, 61 % con longitud, 22/328 avisos con LineRef): el
   sondeo guardado no incluye esos campos.

---

## 19. Hallazgos sorprendentes

- La métrica de acierto de andén que se enseña ("acierta el N %") está doble
  y silenciosamente sesgada: deduplica por combinación y no por tren, y el
  recolector impide puntuar los trenes que ve primero (18.3 puntos 9 y 10).
- El TTL adaptativo que ahorra cuota choca con `stale`: el propio servidor
  hace que el tablero se vea "viejo" cuando el próximo tren está lejos
  (18.3 punto 6).
- Un fallo de `general-message` borra los avisos sin decir nada; el usuario
  vería "normal" en una línea cortada (confirmado).
- El recolector puede quedarse dormido tras un día de mucho uso hasta que
  alguien abra la app (18.3 punto 8).
- La estadística "7,7 min de mediana" y "17 %" que justifican varias
  constantes salen de **dos horas de un domingo** (30/08/2026, 07:00–09:00
  París) en dos estaciones.
- Las frases "cada endpoint tiene su propio contador" (`app/prim.py:6-7`)
  y "el calculador comparte la bolsa con el buscador" (`app/main.py:235-236`)
  se contradicen, y el código mezcla todo Navitia en un único cubo.
- Producción sirve otra versión de la PWA que la del repo, aunque el backend
  sea idéntico.
- FastAPI anuncia la versión `0.1.0` en `/openapi.json`.
