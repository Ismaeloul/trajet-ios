# API del servidor Trajet 0.3.0 (estado actual)

Referencia de **cada endpoint que existe hoy** en `trajet-server` (código de
producción 0.3.0). Todo sale del código; cada afirmación lleva `fichero:línea`
(rutas relativas a `trajet-server/`). El contrato formal está en
[`openapi.yaml`](openapi.yaml) y el funcionamiento interno en
[`servidor.md`](servidor.md).

## Cómo se ha comprobado

- **Parámetros**: el conjunto (ruta, método, parámetros con `in`, `required`,
  tipo, valor por defecto y `minLength`) de `openapi.yaml` es idéntico al del
  `openapi.json` que sirve hoy producción: 16 operaciones y 17 parámetros, cero
  diferencias (script `scratchpad/servidor/comparar.py`).
- **Respuestas**: se ha ejecutado la app real (FastAPI 0.115.6, los mismos
  módulos `app/*.py`) con un cliente PRIM **falso** que responde con cargas
  SIRI/Navitia sintéticas, sin red, y se han hecho 49 peticiones que cubren
  todos los endpoints y todos los códigos de error alcanzables. Las 49
  respuestas cumplen los esquemas de `openapi.yaml`, que son estrictos
  (`additionalProperties: false` y todos los campos que el código emite
  siempre marcados como obligatorios). Script: `scratchpad/servidor/arnes.py`.
- **Documento**: `openapi.yaml` pasa `openapi-spec-validator` (OpenAPI 3.1).
- **Fixtures**: ver el [anexo](#anexo-fixtures-frente-al-código-actual).

## Convenciones generales

| Aspecto | Valor |
|---|---|
| Base | `http://<host>:7796` (el contenedor escucha en 8000; `docker-compose.yml:21`, `umbrel-app.yml:54`) |
| Autenticación | **Ninguna**. Ni cabeceras, ni cookies, ni token. |
| CORS | No hay `CORSMiddleware`: solo mismo origen. |
| Formato | JSON UTF-8. Las funciones devuelven `dict`; FastAPI no valida la salida. |
| Error de `HTTPException` | `{"detail": "<texto en español>"}` |
| Error de validación (422) | `{"detail": [{"type", "loc", "msg", "input", "ctx"?}]}` (Pydantic v2) |
| Excepción no controlada | HTTP 500, `text/plain`, cuerpo `Internal Server Error` |
| Documentación automática | `/docs` y `/redoc` apagados (`app/main.py:43`); **`/openapi.json` sí se sirve** |
| Versión que anuncia FastAPI | `0.1.0` (no se pasa `version=` en `app/main.py:43`) |

### Cuota de PRIM y caché, en una tabla

Cada respuesta de PRIM trae `x-ratelimit-remaining-day`; el cliente lo guarda
por "cubo" (`app/prim.py:105-110`) y lo enseña en `quota`. Los cubos son
`stop-monitoring`, `general-message` y `navitia` (este último agrupa places,
lines y journeys). La caché es en memoria, por clave, y **cada llamante decide
el TTL** (`app/prim.py:28-51`). Si PRIM falla y hay copia (aunque caducada), se
sirve la copia con su edad real; solo sin copia se lanza `PrimError`
(`app/prim.py:116-123`), que los endpoints traducen a 502.

| Llamada a PRIM (URL completa) | Cubo | TTL | Clave de caché |
|---|---|---|---|
| `GET https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring?MonitoringRef=STIF:StopArea:SP:<código>:` | stop-monitoring | 25 s por defecto; adaptativo en el tablero; 120 s en el recolector | `sm:STIF:StopArea:SP:<código>:` |
| `GET https://prim.iledefrance-mobilites.fr/marketplace/general-message?LineRef=ALL` | general-message | 150 s | `gm:ALL` |
| `GET https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/places?q=…&count=N&type[]=…` | navitia | 24 h | `pl:<tipos unidos por +>:<q.lower().strip()>` |
| `GET https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/stop_areas/<id>/lines?count=60` | navitia | 24 h | `ls:<id>` |
| `GET https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/journeys?from=…&to=…&min_nb_journeys=N&max_nb_journeys=N+2&data_freshness=realtime[&datetime=…&datetime_represents=…][&forbidden_uris[]=…]` | navitia | 600 s | `jr:<from>><to>\|<forbidden ordenados, por comas>\|<datetime>\|<represents>\|<count>` |

"0 o 1 llamada" en lo que sigue significa: 0 si la caché tiene un dato más
joven que el TTL, 1 si no.

## Resumen de endpoints

| Método | Ruta | Para qué | Llamadas a PRIM (máx.) | Escribe en BD |
|---|---|---|---|---|
| GET | `/api/health` | Estado | 0 (sí llama a Ollama) | No |
| GET | `/api/routes` | Listar rutas | 0 | No |
| POST | `/api/routes` | Crear ruta a mano | 0 | `routes`, `legs` |
| PUT | `/api/routes/{route_id}` | Reemplazar ruta | 0 | `routes`, `legs` |
| DELETE | `/api/routes/{route_id}` | Borrar ruta | 0 | borra `routes`, `legs`, `history` |
| GET | `/api/search/stops` | Buscar paradas (editor) | 1 navitia | No |
| GET | `/api/stops/{stop_id}/lines` | Líneas de una parada | 1 navitia | No |
| GET | `/api/stops/{stop_id}/directions` | Destinos que circulan ahora | 1 stop-monitoring | No |
| GET | `/api/board` | Tablero | 1 stop-monitoring por estación + 1 general-message | `platform_obs`, `platform_score`, `history`, `translations` (diferido) |
| GET | `/api/alternatives/{route_id}` | Alternativas | 1 general-message + 2 navitia | No |
| GET | `/api/search/places` | Buscar paradas/direcciones/sitios | 1 navitia | No |
| GET | `/api/plan` | Planificar puerta a puerta | 1 navitia | No |
| POST | `/api/routes/from-plan` | Guardar opción del planificador | 1 stop-monitoring por estación de los tramos | `routes`, `legs` |
| GET | `/api/platform-model` | Qué sabe la previsión de andén | 0 | No |
| GET | `/api/stats` | Historial | 0 | No |
| GET | `/` | PWA (index.html) | 0 | No |

Fuera del esquema (`include_in_schema=False`) se sirven además
`/manifest.webmanifest`, `/sw.js` (con `Cache-Control: no-cache`),
`/apple-touch-icon.png`, `/apple-touch-icon-precomposed.png`, `/favicon.ico`
y todo `/static/*` (`app/main.py:438-479`). Son la PWA.

---

## GET /api/health

Estado del servidor. Lo usa el `HEALTHCHECK` del Dockerfile cada 30 s
(`Dockerfile:25-26`) y `pasar-al-store.sh:80`.

- **Parámetros**: ninguno.
- **PRIM**: 0 llamadas. Lee `prim.client.quota` y `last_error` de memoria.
- **Otras llamadas**: `GET {OLLAMA_URL}/api/tags` con timeout 5 s si
  `OLLAMA_URL` no está vacía (`app/translate.py:64-84`).
- **BD**: 3 lecturas (`SELECT COUNT(*) … platform_score`,
  `SELECT COUNT(*) FROM platform_obs`, `SELECT COUNT(DISTINCT day) FROM platform_obs`,
  `app/platform.py:215-231`) en un hilo aparte.
- **Errores**: ninguno controlado.

Respuesta (`app/main.py:48-59`):

| Campo | Tipo | Contenido |
|---|---|---|
| `ok` | `true` | Siempre `true`. |
| `key_configured` | bool | `PRIM_API_KEY` no vacía (`app/main.py:52`). |
| `quota` | objeto `Quota` | `{"stop-monitoring"?: int, "general-message"?: int, "navitia"?: int}`; solo los cubos que ya han respondido desde el arranque. |
| `last_error` | string \| null | `"<Excepción>: <mensaje>"` del último fallo de PRIM; `null` tras cualquier llamada buena (`app/prim.py:114,117-118`). |
| `now_paris` | string | `YYYY-MM-DD HH:MM:SS` hora de París (`app/main.py:55`). |
| `collector` | objeto `CollectorStatus` | `enabled`, `running`, `last_at` (`HH:MM:SS` o `""`), `session_total`, y lo de la última pasada: `stations`, `recorded`, `reason`, `interval` (s, 0 = no muestrea), `remaining` (int \| null), `priority` (`app/collector.py:260-262`, `171-173`). |
| `platform_model` | objeto `PlatformAccuracy` | `predictions`, `hits`, `rate` (number \| null), `observations`, `days` (`app/platform.py:225-231`). |
| `translator` | objeto `TranslatorStatus` | Una de tres formas, ver abajo. |

`translator` (`app/translate.py:64-84`):

| Caso | Cuerpo |
|---|---|
| `OLLAMA_URL` vacía | `{"ok": false, "reason": "sin configurar"}` (sin `models`) |
| Ollama no responde | `{"ok": false, "reason": "no responde: <error>", "models": []}` |
| Responde | `{"ok": <tiene el modelo>, "reason": "" \| "falta el modelo <m>", "model": "<m>", "models": ["…"]}`. El modelo casa por nombre exacto o por la parte antes de `:`. |

No hay fixture de este endpoint.

---

## GET /api/routes

Todas las rutas con sus tramos y la que el tablero elegiría ahora.

- **Parámetros**: ninguno. **PRIM**: 0. **BD**: 2 lecturas
  (`SELECT * FROM routes ORDER BY position, id` y
  `SELECT * FROM legs ORDER BY route_id, seq`, `app/db.py:171-178`).
- **Errores**: ninguno controlado.

Respuesta (`app/main.py:64-68`):

| Campo | Tipo | Contenido |
|---|---|---|
| `routes` | `Route[]` | Ver [objeto Route](#objeto-route). |
| `active_id` | int \| null | `pick_active_route(routes)` (`app/board.py:125-151`); `null` si no hay rutas. |

### Objeto Route

Es la fila de `routes` tal cual (`SELECT *`, `app/db.py:164-168`) con `days`
convertido a lista y `legs` añadido.

| Campo | Tipo | Origen / notas |
|---|---|---|
| `id` | int | PK autoincremental. |
| `name` | string | |
| `origin_id`, `dest_id` | string | Id Navitia: `stop_area:IDFM:NNNNN` o `lon;lat` si viene del planificador con una dirección. |
| `origin_name`, `dest_name` | string | |
| `days` | int[] | Se guarda como `"0,1,2,3,4"`; 0 = lunes. Sin validar rango. |
| `time_from`, `time_to` | string | `HH:MM`. Si `time_mode` ≠ `window` se calculan al guardar (`app/db.py:202-208`). |
| `time_mode` | `window` \| `departure` \| `arrival` | Cualquier otro valor se guarda como `window` (`app/db.py:196-198`). |
| `time_at` | string | `HH:MM` o `""`. |
| `duration_min` | int | Duración conocida (planificador) o 0. |
| `position` | int | Orden manual; ningún endpoint lo cambia salvo PUT. |
| `created_at` | string | `datetime('now')` de SQLite en **UTC**: `YYYY-MM-DD HH:MM:SS`. |
| `legs` | `RouteLeg[]` | Filas de `legs` (`SELECT *`) ordenadas por `seq`. |

`RouteLeg`: `id`, `route_id`, `seq` (0..n-1), `line_id` (`line:IDFM:Cnnnnn`),
`line_code`, `line_name`, `line_mode` (texto de IDFM, p. ej. `Métro`),
`line_color` (hex sin `#`), `from_id`, `from_name`, `to_id`, `to_name`,
`directions` (lista de destinos SIRI; vacía = sin filtro; se decodifica del
JSON guardado sin comprobar el tipo, `app/db.py:155-161`).

Ejemplo real recortado (`tools/fixtures/routes.json`; es anterior a la
migración y **no** trae `time_mode`, `time_at` ni `duration_min`, que hoy
siempre vienen):

```json
{
 "routes": [
  {
   "id": 1,
   "name": "Demo · Saint-Lazare (bórrala)",
   "origin_id": "stop_area:IDFM:71370",
   "origin_name": "Gare Saint-Lazare",
   "dest_id": "stop_area:IDFM:71264",
   "dest_name": "Gallieni",
   "days": [0, 1, 2, 3, 4, 5, 6],
   "time_from": "00:00",
   "time_to": "23:59",
   "position": 0,
   "created_at": "2026-08-29 23:40:56",
   "legs": [
    {
     "id": 1, "route_id": 1, "seq": 0,
     "line_id": "line:IDFM:C01383", "line_code": "13", "line_name": "13",
     "line_mode": "Métro", "line_color": "82C8E6",
     "from_id": "stop_area:IDFM:71370", "from_name": "Gare Saint-Lazare",
     "to_id": "", "to_name": "",
     "directions": ["Châtillon Montrouge"]
    }
   ]
  }
 ],
 "active_id": 1
}
```

---

## POST /api/routes

Crea una ruta montada a mano (editor de la PWA).

- **Parámetros**: ninguno.
- **Cuerpo** (`application/json`, obligatorio). FastAPI solo exige que sea un
  objeto JSON (`payload: dict`, `app/main.py:72`). Se aceptan campos extra (la
  PWA manda la ruta entera tal como la recibió, con `id`, `created_at`, etc.).

| Campo | Tipo | Obligatorio | Por defecto | Qué se hace con él |
|---|---|---|---|---|
| `name` | string | sí (no vacío tras `strip`) | — | `strip()` y se guarda (`app/db.py:211`). |
| `origin_id` | string | sí (no vacío) | — | |
| `origin_name` | string | **sí de hecho** (si falta: KeyError → 500) | — | Puede ser `""`. |
| `dest_id` | string | sí (no vacío) | — | |
| `dest_name` | string | **sí de hecho** (KeyError → 500) | — | |
| `days` | int[] | no | `[0,1,2,3,4]` | `int()` de cada uno; `null` o no enteros → 500. |
| `time_mode` | string | no | `window` | Fuera de `window/departure/arrival` → `window`. |
| `time_at` | string | no | `""` | `strip()`. |
| `time_from`, `time_to` | string | no | `07:00`, `10:00` | Solo cuentan en modo `window` o sin `time_at`. |
| `duration_min` | int | no | 0 | `int()`; no numérico → 500. |
| `position` | int | no | 0 | `int()`; `null` → 500. |
| `legs` | objeto[] | sí (≥1) | — | Cada tramo: `line_id` y `from_id` obligatorios y no vacíos; `line_code`, `line_name`, `line_mode`, `line_color`, `from_name`, `to_id`, `to_name` (texto, `""` por defecto) y `directions` (lista, `[]` por defecto, se guarda como JSON sin validar). `seq` se reasigna 0..n-1. |

- **Validación** (`_validate_route`, `app/main.py:94-103`), en este orden:
  `falta el campo 'name'` / `'origin_id'` / `'dest_id'`;
  `la ruta necesita al menos un tramo`; `tramo N: falta 'line_id'` /
  `'from_id'`. Todas con 400.
- **Respuesta 200**: `{"id": int, "route": Route}` (`app/main.py:74-75`).
- **Errores**: 400 (arriba); 422 si el cuerpo no es un objeto JSON
  (`dict_type`); 500 si falta `origin_name`/`dest_name` u otro fallo de tipos
  en `db.save_route` (comprobado con el arnés).
- **PRIM**: 0. **BD**: 1 `INSERT` en `routes` + 1 por tramo en `legs`, en una
  transacción (`app/db.py:218-248`).

Ejemplo de cuerpo tal como lo arma la PWA (`app/static/app.js:870-878` y
`1310-1314`, sin valores inventados: son los de `blankRoute()` y
`add-leg`):

```json
{
 "id": null, "name": "", "origin_id": "", "origin_name": "",
 "dest_id": "", "dest_name": "", "days": [0, 1, 2, 3, 4],
 "time_from": "07:00", "time_to": "10:00",
 "time_mode": "arrival", "time_at": "09:00", "duration_min": 0,
 "legs": [{"line_id": "", "line_code": "", "line_name": "", "line_mode": "",
           "line_color": "", "from_id": "", "from_name": "", "to_id": "",
           "to_name": "", "directions": []}]
}
```

(la PWA rellena nombre, origen, destino y tramos antes de enviarlo; con los
valores vacíos de arriba el servidor contestaría 400 `falta el campo 'name'`).

---

## PUT /api/routes/{route_id}

Reemplaza una ruta entera.

- **Parámetros**: `route_id` (path, int, obligatorio).
- **Cuerpo**: igual que POST.
- **Orden de comprobaciones**: primero existencia (404
  `ruta no encontrada`), luego `_validate_route` (400) (`app/main.py:78-84`).
- **Respuesta 200**: `{"id": route_id, "route": Route}`.
- **Errores**: 404, 400, 422 (`route_id` no entero o cuerpo no objeto), 500
  (igual que POST).
- **BD**: `UPDATE routes`, `DELETE FROM legs WHERE route_id=?` y se reinsertan
  todos los tramos (**sus `id` cambian**) (`app/db.py:227-247`). El historial
  y los andenes aprendidos no se tocan. La duración de referencia de
  alternativas (`_baseline`, en memoria) **no** se invalida.
- **PRIM**: 0.

---

## DELETE /api/routes/{route_id}

- **Parámetros**: `route_id` (path, int).
- **Respuesta 200**: `{"deleted": route_id}` (`app/main.py:87-91`).
- **Errores**: 404 `ruta no encontrada` (si `DELETE` no borra filas); 422.
- **BD**: `DELETE FROM routes`; `ON DELETE CASCADE` (con
  `PRAGMA foreign_keys = ON` en cada conexión, `app/db.py:122`) borra sus
  `legs` y su `history`. `platform_obs`, `platform_score` y `translations` no
  dependen de rutas y se quedan.
- **PRIM**: 0.

---

## GET /api/search/stops

Buscador de zonas de parada del editor de rutas.

- **Parámetros**:

| Nombre | En | Tipo | Obligatorio | Defecto | Notas |
|---|---|---|---|---|---|
| `q` | query | string | sí | — | `minLength: 2` (422 si más corto). Sin longitud máxima. |

- **PRIM**: 0 o 1 `GET …/v2/navitia/places?q=<q>&count=12&type[]=stop_area`
  (`app/prim.py:155-172`), cubo `navitia`, caché 24 h, clave
  `pl:stop_area:<q en minúsculas, sin espacios extremos>` (la petición usa `q`
  tal cual).
- **Respuesta 200** (`app/main.py:114-133`):

| Campo | Tipo | Contenido |
|---|---|---|
| `stops` | `Stop[]` | Un elemento por `place` con `stop_area.id` (los demás se saltan). |
| `stops[].id` | string | `stop_area.id`. |
| `stops[].name` | string \| null | `place.name` o `stop_area.name`. |
| `stops[].city` | string | Primera `administrative_regions[].name` o `""`. |
| `stops[].lines` | objeto[] | De `stop_area.lines` si Navitia las trae: `id` (string \| null), `code` (`code` o `name`; string \| null), `mode` (`commercial_mode.name` o `""`), `color` (o `""`). Sin ordenar. |
| `age` | number | Segundos de antigüedad del dato de Navitia. |

- **Errores**: 422; 502 `la API de IDFM no responde: <error>` si PRIM falla y
  no hay copia en caché.
- **BD**: nada. No hay fixture.

---

## GET /api/stops/{stop_id}/lines

Líneas de una zona de parada, para elegir el tramo.

- **Parámetros**: `stop_id` (path, string, obligatorio; normalmente
  `stop_area:IDFM:NNNNN`). FastAPI declara 422 pero con un texto en la ruta no
  puede darse.
- **PRIM**: 0 o 1 `GET …/v2/navitia/stop_areas/<stop_id>/lines?count=60`
  (`app/prim.py:183-190`), cubo `navitia`, caché 24 h (usa `ttl_line_info`),
  clave `ls:<stop_id>`.
- **Respuesta 200** (`app/main.py:143-151`): `{"lines": Line[]}` con
  `id` (string \| null), `code` (`code` o `name`), `name` (string \| null),
  `mode` (`commercial_mode.name` o `""`), `color` (o `""`).
  Orden (`app/idfm.py:113-147`): primero las que no son de sustitución (el
  nombre no contiene `remplacement` ni `substitution`), luego por modo
  (metro, RER, train/transilien, TER, tram, funicular/funiculaire,
  navette/cable, resto incluido el bus) y por código ("3" antes que "12").
- **Errores**: 502 como en el buscador.
- **BD**: nada. No hay fixture.

---

## GET /api/stops/{stop_id}/directions

Destinos que circulan **ahora** para una línea en una parada; el editor los
ofrece como botones para no escribir la dirección a mano.

- **Parámetros**:

| Nombre | En | Tipo | Obligatorio | Notas |
|---|---|---|---|---|
| `stop_id` | path | string | sí | Id Navitia; se convierte a `STIF:StopArea:SP:<código>:` (`app/idfm.py:15-24`). |
| `line_id` | query | string | sí (422 si falta) | Id Navitia de la línea; se compara solo el código `Cnnnnn`. |

- **PRIM**: 0 o 1 `stop-monitoring`, TTL 25 s, clave
  `sm:STIF:StopArea:SP:<código>:` (la misma que usan el tablero y el
  recolector, así que se reaprovecha).
- **Respuesta 200** (`app/main.py:160-164`, `app/board.py:301-322`):
  `{"directions": string[], "age": number}`. `directions` son los
  `DestinationName` (o `MonitoredCall.DestinationDisplay`) de las visitas de
  esa línea, sin repetir, **ordenados de más a menos pasos**.
- **Errores**: 422, 502. **BD**: nada. No hay fixture.

---

## GET /api/board

El tablero de una ruta: por cada tramo, estado de la línea y próximos 4
pasos. Es lo que la PWA pide cada 30 s con la pantalla visible
(`app/static/app.js:498-518`).

- **Parámetros**:

| Nombre | En | Tipo | Obligatorio | Defecto | Notas |
|---|---|---|---|---|---|
| `route_id` | query | int \| null | no | — | Sin él, la ruta activa (`pick_active_route`). |
| `log_history` | query | bool | no | `true` | Si es `true` se intenta guardar una fila de historial. |

- **Orden de proceso** (`app/main.py:169-214`):
  1. Si no hay **ninguna** ruta: 200 `{"empty": true, "message": "todavia no hay rutas guardadas"}`
     (aunque se pase `route_id`).
  2. `route_id` dado y no existe: 404 `ruta no encontrada`.
  3. `build_board(route)` (`app/board.py:367-450`).
  4. `_learn_platforms` en un hilo: registra los andenes vistos y rellena
     `guess` (`app/main.py:194-197`, `217-219`). Si falla, solo un aviso en
     el log.
  5. `translate_board`: añade `messages_es` / `translating` y lanza en segundo
     plano las traducciones que falten (`app/main.py:202-205`).
  6. Si `log_history`: `record_history` en un hilo (`app/main.py:207-211`).
  7. `auto_selected = route_id is None`.
- **PRIM**: 0 o 1 `stop-monitoring` **por estación distinta** de la ruta
  (dos tramos desde la misma parada = una llamada; `app/board.py:371-373`),
  con TTL adaptativo (`station_ttl`, `app/board.py:337-354`: 25 s la primera
  vez; luego 20/30/90/300/600 s según el próximo paso esté a ≤3, ≤8, ≤20, ≤45
  o más minutos) + 0 o 1 `general-message` (TTL 150 s). Todo en paralelo con
  `asyncio.gather(..., return_exceptions=True)`.
- **BD**: `platform_obs` (un `INSERT OR IGNORE` por salida con andén),
  `platform_score` (si el andén era nuevo hoy y había previsión), hasta 3
  `SELECT` por salida sin andén (previsión), `history` (como mucho una fila
  cada 600 s por ruta, `app/board.py:453-460`), `translations` (cuando acabe
  la traducción en segundo plano).
- **Errores**: 404; 422 (`route_id` no entero, `log_history` no booleano).
  El 502 de `app/main.py:185-186` es **inalcanzable**: `build_board` nunca
  propaga `PrimError`, los fallos acaban en `errors`.

Respuesta 200 (`Board`, `app/board.py:435-450` + `app/main.py:213`):

| Campo | Tipo | Contenido |
|---|---|---|
| `route` | objeto | `{id, name, origin_name, dest_name}`. |
| `legs` | `BoardLeg[]` | Uno por tramo, en orden. |
| `worst_level` | 0 \| 1 \| 2 | Peor estado entre los tramos. |
| `worst_line` | string | `line_code` (o código `Cnnnnn`) de la línea con peor estado; si todas normales, la del mayor retraso positivo; si no, `""` (`app/board.py:407-418`). |
| `max_delay` | number | Mayor retraso **positivo** de las salidas mostradas, `0.0` si ninguno. |
| `updated_at` | string | ISO UTC con segundos, `…+00:00`. |
| `data_age` | number | Máximo entre la edad de cada `stop-monitoring` y la de `general-message`, 1 decimal. |
| `stale` | bool | `data_age > 90` (3 × `refresh_seconds`, `app/board.py:446`). |
| `errors` | string[] | `"<from_name>: <error>"` por cada **tramo** cuya estación falló sin copia (se repite si dos tramos comparten estación). |
| `quota` | `Quota` | Igual que en `/api/health`. |
| `last_error` | string \| null | Igual que en `/api/health`. |
| `auto_selected` | bool | `true` si no se pasó `route_id`. |

`BoardLeg` (`app/board.py:420-433`): `seq`, `line_id`, `line_code`,
`line_name`, `line_mode`, `line_color`, `from_name`, `to_name`, `directions`
(copiados de la ruta), `status` (`LineStatus`), `departures` (≤ 4
`Departure`), `age` (number \| null; `null` si la estación falló sin copia).

`LineStatus` (`app/board.py:195-214`, `app/translate.py:141-172`):

| Campo | Tipo | Cuándo | Contenido |
|---|---|---|---|
| `level` | 0 \| 1 \| 2 | siempre | 0 normal, 1 perturbada, 2 interrumpida. |
| `label` | string | siempre | `normal`, `perturbada`, `interrumpida`. |
| `messages` | string[] (≤3) | siempre | Texto más corto de cada aviso **activo hoy**, en francés. |
| `planned` | int | siempre | Nº de avisos con fecha de inicio futura (no cuentan para `level`). |
| `messages_es` | (string \| null)[] | solo si `messages` no está vacío | Traducción ya cacheada de cada mensaje, o `null`. |
| `translating` | bool | solo si `messages` no está vacío | `OLLAMA_URL` configurada y falta alguna traducción. |

`Departure` (`app/board.py:274-295`, `guess` de `app/platform.py:185-198`):

| Campo | Tipo | Contenido |
|---|---|---|
| `jid` | string | `FramedVehicleJourneyRef.DatedVehicleJourneyRef`, si no `ItemIdentifier`, si no `""`. |
| `minutes` | int ≥ 0 | `round((prevista − ahora)/60)`, nunca negativo. Las de más de 1 min en el pasado se descartan. |
| `at` | `HH:MM` | Hora prevista (Expected Departure, si no Expected Arrival) en París. |
| `aimed_at` | `HH:MM` \| `""` | Hora teórica (Aimed Departure, si no Aimed Arrival). |
| `destination` | string | `DestinationName`, si no `DestinationDisplay`. |
| `platform` | string \| null | `DeparturePlatformName` si es una vía real (`app/idfm.py:69-86`). |
| `platform_new` | bool | La vía acaba de aparecer para este `jid` (antes no tenía). |
| `delay` | int \| null | `round((prevista − teórica)/60)`, puede ser negativo; `null` sin teórica. |
| `status` | string | `DepartureStatus` o `ArrivalStatus` de SIRI, o `""`. |
| `at_stop` | bool | `VehicleAtStop`. |
| `train` | string \| null | `TrainNumbers.TrainNumberRef` (número de misión). |
| `length` | `short` \| `long` \| null | De `VehicleFeatureRef` (`shortTrain` / `longTrain`). |
| `guess` | objeto (opcional) | Solo si no hay `platform` y la previsión se atreve: `{platform, share (0,5–1), samples (≥3), basis: mision\|hora\|linea, why}`. |

Ejemplo real recortado (`tools/fixtures/board.json`, un tramo y dos
salidas; es de antes de añadir `aimed_at` y `length`, que hoy siempre vienen):

```json
{
 "route": {"id": 1, "name": "Demo · Saint-Lazare (bórrala)",
           "origin_name": "Gare Saint-Lazare", "dest_name": "Gallieni"},
 "legs": [
  {
   "seq": 1, "line_id": "line:IDFM:C01739", "line_code": "J", "line_name": "J",
   "line_mode": "Train", "line_color": "CEC73D",
   "from_name": "Gare Saint-Lazare", "to_name": "",
   "directions": ["Mantes-la-Jolie"],
   "status": {"level": 0, "label": "normal", "messages": [], "planned": 0},
   "departures": [
    {"jid": "IDFM:C01739:1", "minutes": 6, "at": "10:08",
     "destination": "Mantes-la-Jolie", "platform": "17", "platform_new": true,
     "delay": 0, "status": "onTime", "at_stop": false, "train": "135711"},
    {"jid": "IDFM:C01739:2", "minutes": 21, "at": "10:23",
     "destination": "Nanterre Université", "platform": null,
     "platform_new": false, "delay": 3, "status": "delayed",
     "at_stop": false, "train": "135713"}
   ],
   "age": 0.0
  }
 ],
 "worst_level": 1, "worst_line": "13", "max_delay": 0.0,
 "updated_at": "2026-08-30T08:03:13+00:00", "data_age": 0.0, "stale": false,
 "errors": [], "quota": {"stop-monitoring": 819, "general-message": 999},
 "last_error": null, "auto_selected": true
}
```

Otro recorte real (`tools/fixtures5/board.json`) con `guess`, `length`,
`messages_es` y `translating`:

```json
{"jid": "j22Chelles - Gournay", "minutes": 22, "at": "10:50",
 "destination": "Chelles - Gournay", "platform": null, "platform_new": false,
 "delay": null, "status": "", "at_stop": false, "train": null,
 "guess": {"platform": "11", "share": 0.82, "samples": 17,
           "basis": "mision", "why": "por el número de tren"},
 "length": "short"}
```

```json
"status": {"level": 1, "label": "perturbada", "planned": 0,
           "messages": ["Trafic perturbé en raison d'un incident technique."],
           "messages_es": [null], "translating": true}
```

Respuesta sin rutas (`BoardEmpty`, `app/main.py:172-173`):

```json
{"empty": true, "message": "todavia no hay rutas guardadas"}
```

---

## GET /api/alternatives/{route_id}

Itinerarios alternativos que evitan las líneas tocadas de la ruta. La PWA lo
llama solo al pulsar "Buscar alternativa" (`app/static/app.js:408-422`); no
entra en el refresco periódico (`app/main.py:232-236`).

- **Parámetros**:

| Nombre | En | Tipo | Obligatorio | Defecto |
|---|---|---|---|---|
| `route_id` | path | int | sí | — |
| `force` | query | bool | no | `false` |

- **Proceso** (`app/main.py:230-336`):
  1. 404 si la ruta no existe.
  2. `general-message` (TTL 150 s). Si falla sin copia, se sigue como si no
     hubiera avisos (`disruptions = {}`), sin error.
  3. `affected` = tramos cuya línea tiene `level > 0` hoy.
  4. Sin `affected` y sin `force`: respuesta corta
     `{"needed": false, "affected": [], "options": []}`.
  5. `journeys(origin_id, dest_id, forbidden=[line_id de las tocadas])` con
     `count=3` → `min_nb_journeys=3`, `max_nb_journeys=5`,
     `data_freshness=realtime`, sin `datetime` (ahora), un
     `forbidden_uris[]` por línea. Si falla sin copia: 502
     `el calculador no responde: <error>`.
  6. Duración de referencia: `_baseline[route_id]` en memoria, válida 12 h;
     si no hay, otra `journeys` sin exclusiones y se toma la duración mínima.
     Si falla, `baseline = null` (sin error).
  7. De las 6 primeras `journeys`, por cada sección `public_transport`: estado
     de su línea (sacada de `links[type=line]`) con los mismos avisos. Una
     línea `interrumpida` hace la opción `usable: false`.
  8. Orden: usables primero, luego menor `worst_level`, luego menor duración.
     Se devuelven **2**.
- **PRIM**: hasta 3 (1 general-message + 2 journeys en el cubo `navitia`).
  Con `force=true` y sin líneas tocadas las dos `journeys` tienen la misma
  clave de caché, así que la segunda sale de caché.
- **BD**: nada.

Respuesta completa (`Alternatives`):

| Campo | Tipo | Contenido |
|---|---|---|
| `needed` | bool | Hay alguna línea tocada (`false` si se llegó por `force`). |
| `affected` | objeto[] | `{line_id, line_code, level (1\|2), label (perturbada\|interrumpida)}`. |
| `options` | objeto[] (≤2) | Ver abajo. |
| `baseline_minutes` | int \| null | Duración de referencia redondeada. |
| `age` | number | Edad de la respuesta `journeys` con exclusiones (sin redondear). |
| `quota` | `Quota` | |

`options[]`: `total_minutes` (int), `transfers` (int), `delta_minutes`
(int \| null, frente a la referencia), `legs[]` = `{code, mode, direction,
color, minutes, status}` (solo secciones de transporte público; `status` es la
etiqueta), `usable` (bool), `worst_level` (0–2), `departure` y `arrival`
(**crudos de Navitia**, `YYYYMMDDTHHMMSS`). Las `journeys` sin ninguna sección
de transporte público se descartan.

- **Errores**: 404, 422, 502.

No hay fixture en `tools/fixtures*`. El único ejemplo del repo es el objeto
escrito a mano para la prueba de render de la PWA
(`tools/render_test.js:74-85`), que coincide con esta forma salvo que no trae
`age`, `quota`, `departure` ni `arrival`:

```json
{
 "needed": true,
 "affected": [{"line_id": "line:IDFM:C01383", "line_code": "13", "level": 1, "label": "perturbada"}],
 "baseline_minutes": 22,
 "options": [
  {"total_minutes": 28, "transfers": 1, "delta_minutes": 6, "usable": true, "worst_level": 0,
   "legs": [{"code": "14", "mode": "Métro", "direction": "Orly", "color": "62259D", "minutes": 12, "status": "normal"},
            {"code": "A", "mode": "RER", "direction": "Cergy", "color": "E3051C", "minutes": 9, "status": "normal"}]}
 ]
}
```

---

## GET /api/search/places

Buscador del planificador: paradas, direcciones postales y sitios.

- **Parámetros**: `q` (query, string, obligatorio, `minLength: 2`; la PWA no
  pregunta hasta 3 caracteres, `app/static/app.js:637`).
- **PRIM**: 0 o 1
  `GET …/v2/navitia/places?q=<q>&count=10&type[]=stop_area&type[]=address&type[]=poi`
  (`app/main.py:349-350`), cubo `navitia`, caché 24 h, clave
  `pl:stop_area+address+poi:<q normalizada>`.
- **Respuesta 200** (`app/main.py:354-369`): `{"places": Place[]}` (sin
  `age`). Cada `Place`:

| Campo | Tipo | Contenido |
|---|---|---|
| `id` | string | Id del cuerpo embebido o del `place`; para una dirección es `lon;lat` y sirve tal cual como `from`/`to` de `/api/plan`. Los `place` sin id se saltan. |
| `name` | string | `place.name`, si no el del cuerpo, si no `""`. |
| `city` | string | Primera región administrativa o `""`. |
| `kind` | string | `parada` (stop_area), `dirección` (address), `sitio` (poi) o el `embedded_type` crudo. |

- **Errores**: 422, 502. **BD**: nada. No hay fixture. Ejemplos de uso en
  `tools/test_plan.py:40-51` (`q=12 rue de Rivoli`, `q=Saint-Lazare`).

---

## GET /api/plan

Opciones de trayecto entre dos sitios para elegir una y guardarla.

- **Parámetros**:

| Nombre | En | Tipo | Obligatorio | Defecto | Notas |
|---|---|---|---|---|---|
| `from` | query | string | sí | — | `minLength: 3`. Alias de `frm` en el código. |
| `to` | query | string | sí | — | `minLength: 3`. |
| `when` | query | string \| null | no | — | `HH:MM` en hora de París. |
| `mode` | query | string | no | `departure` | `departure` o `arrival`; otro valor → 400. |

- **`when`** (`app/planner.py:202-219`): se parte por `:` en dos enteros; si
  no se puede (p. ej. `9`, `09:00:00`) se ignora y se planifica "ahora".
  Si la hora ya ha pasado hoy se usa mañana. Se envía como
  `datetime=YYYYMMDDTHHMMSS` y `datetime_represents=<mode>`; sin `when` no se
  envía ninguno de los dos (y `mode` no tiene efecto en Navitia, solo en el
  orden). **Una hora o un minuto fuera de rango (`25:00`) da 500**: el
  `now.replace()` está fuera del `try` (`app/planner.py:216`).
- **PRIM**: 0 o 1 `journeys` con `count=4` → `min_nb_journeys=4`,
  `max_nb_journeys=6`, `data_freshness=realtime` (`app/main.py:385-387`),
  cubo `navitia`, caché 600 s.
- **Respuesta 200** (`app/main.py:391-396`, `app/planner.py:53-118`):
  `{"options": PlanOption[], "age": number (1 decimal)}`.

`PlanOption`:

| Campo | Tipo | Contenido |
|---|---|---|
| `kind` | string | `type` de la journey de Navitia. |
| `minutes` | int | Duración total redondeada. |
| `walk_minutes` | int | Suma de secciones `street_network`, `crow_fly` y `transfer`. |
| `transfers` | int | `nb_transfers`. |
| `departure`, `arrival` | `HH:MM` \| `""` | De `YYYYMMDDTHHMMSS`. |
| `legs` | `PlanLeg[]` (≥1) | Solo secciones `public_transport`. |

`PlanLeg`: `line_id` (de `links[type=line]`), `line_code` (`code` o
`label`), `line_name` (`name` o `label`), `line_mode` (`commercial_mode` o
`physical_mode`), `line_color`, `from_id`/`from_name` y `to_id`/`to_name`
(zona de parada del `stop_point`, o el propio extremo), `direction`
(`direction` o `headsign` de Navitia, **no** es el texto SIRI), `minutes`,
`at` (`HH:MM` de salida de la sección o `""`).

Orden: `mode=departure` → más rápida primero y, a igualdad, menos
transbordos; `mode=arrival` → la que sale más tarde primero. Luego se deja
una opción por combinación de `line_id` (`app/planner.py:102-117`). Las
journeys sin transporte público se descartan.

- **Errores**: 400 (`mode tiene que ser 'departure' o 'arrival'`); 404
  (`no hay ningún trayecto en transporte público entre esos dos puntos a esa hora`);
  422 (`from`/`to` ausentes o cortos); 500 (`when` fuera de rango); 502.
- **BD**: nada. No hay fixture; peticiones de ejemplo en
  `tools/test_arrival.py:35-50` (`from=2.35995;48.855602`,
  `to=stop_area:IDFM:71370`, `when=09:00`, `mode=departure|arrival`).

---

## POST /api/routes/from-plan

Guarda como ruta vigilada la opción elegida en el planificador.

- **Parámetros**: ninguno.
- **Cuerpo** (`application/json`):

| Campo | Tipo | Obligatorio | Uso |
|---|---|---|---|
| `option` | `PlanOption` | sí, con `legs` no vacío (si no, 400 `falta el itinerario elegido`) | Se leen `legs[]` (todos los campos de `PlanLeg`) y `minutes`. |
| `meta` | objeto | no | `name`, `origin_id`, `origin_name`, `dest_id`, `dest_name`, `days`, `time_from`, `time_to`, `time_mode`, `time_at`. |

- **Proceso** (`app/main.py:399-412`, `app/planner.py:121-199`):
  1. Por cada tramo, `resolve_direction(from_id, line_id, direction)`: pide
     `stop-monitoring` de su estación (TTL 25 s; en paralelo, una llamada por
     estación gracias al lock) y busca entre los destinos que circulan ahora
     uno que sea igual (normalizado), que contenga o esté contenido, o que
     empiece por el prefijo `max(6, len/2)` del texto antes de ` (`. Si no
     encuentra, lista vacía (= sin filtro). Cualquier error se traga.
  2. Monta la ruta: `name` = `meta.name` o `"<origen> → <destino>"`;
     `origin_*`/`dest_*` = `meta` o primer/último tramo; `days` = `meta.days`
     o L–V; `time_from/to` = `meta` o `07:00`/`10:00`; `time_mode` =
     `meta` o `window`; `time_at` = `meta` o `""`; `duration_min` =
     `int(option.minutes)`.
  3. `db.save_route` **sin** `_validate_route`.
- **Respuesta 200**: `{"id": int, "route": Route, "without_direction": string[]}`
  (`line_code` de los tramos que quedaron sin dirección).
- **Errores**: 400; 422 (cuerpo no objeto); 500 (`option`/`meta` no objetos,
  tipos malos).
- **PRIM**: 0–N `stop-monitoring` (N = estaciones distintas con `from_id`,
  `line_id` y `direction` no vacíos). **BD**: `routes` + `legs`.

Cuerpos de ejemplo usados por las pruebas contra la API real:
`tools/test_plan.py:71-76` y `tools/test_arrival.py:70-75`, p. ej.:

```json
{"option": "<una de las opciones de /api/plan>",
 "meta": {"name": "PRUEBA llegada", "origin_name": "12 Rue de Rivoli",
          "dest_name": "Gare Saint-Lazare", "days": [0, 1, 2, 3, 4],
          "time_mode": "arrival", "time_at": "09:00"}}
```

---

## GET /api/platform-model

Qué sabe la previsión de andén y si acierta (pantalla de historial de la PWA).

- **Parámetros**: `route_id` (query, int \| null, opcional). Sin él, la ruta
  activa. Un `route_id` inexistente **o 0** no da error: simplemente faltan
  `route` y `coverage` (`app/main.py:421-427`).
- **PRIM**: 0. **BD**: lecturas de `platform_score` y `platform_obs`.
- **Respuesta 200** (`app/main.py:415-428`):

| Campo | Tipo | Cuándo | Contenido |
|---|---|---|---|
| `accuracy` | `PlatformAccuracy` | siempre | Igual que `platform_model` de `/api/health`. |
| `collector` | `CollectorStatus` | siempre | Igual que en `/api/health`. |
| `route` | `{id, name}` | si hay ruta | |
| `coverage` | objeto[] | si hay ruta | Por tramo: `{seq, line_code, observations, days, platforms}` contando `platform_obs` de `(from_id, line_id)` (`app/platform.py:234-248`). |

- **Errores**: 422. No hay fixture.

---

## GET /api/stats

Resumen del historial de consultas.

- **Parámetros**: `days` (query, int, opcional, defecto 90). No se valida:
  un negativo produce el modificador SQLite `--N days`, que no es válido, y
  la respuesta sale vacía.
- **PRIM**: 0. **BD**: 3 `SELECT` sobre `history` con
  `day >= date('now', '-<days> days')` (`app/db.py:289-315`). `date('now')`
  es UTC y `day` es fecha de París.
- **Respuesta 200**:

| Campo | Tipo | Contenido |
|---|---|---|
| `by_month[]` | objeto[] | `{month: "YYYY-MM", bad_days, total_days, avg_delay}`, de más reciente a más antiguo. `bad_days` = días con alguna fila `disrupted > 0`. |
| `by_line[]` | objeto[] (≤10) | `{worst_line, n, avg_delay}` de filas con `disrupted > 0`, por `n` descendente. **`n` son filas de historial, no días** (la PWA lo pinta como "días", `app/static/app.js:1212`). |
| `overall` | objeto | `{n, avg_delay, max_delay}`; con historial vacío `n = 0` y los otros `null`. |

- **Errores**: 422 (`days` no entero). No hay fixture.

---

## GET /

Devuelve `app/static/index.html` (`app/main.py:438-440`), la portada de la
PWA. 200 `text/html`. Es la única ruta de la interfaz que aparece en el
`openapi.json`.

---

## Anexo: fixtures frente al código actual

Los fixtures de `tools/fixtures*/` son entradas de `tools/render_test.js`
(prueba de las plantillas de la PWA, `tools/render_test.js:9-12`), no
capturas completas de la API actual. Validados contra `openapi.yaml`:

| Fichero | Esquema | Resultado estricto | Qué falta o sobra |
|---|---|---|---|
| `tools/fixtures/board.json` | `Board` | 16 discrepancias | Todas las salidas sin `aimed_at` ni `length` (campos posteriores al fixture). |
| `tools/fixtures/routes.json` | `RouteList` | 3 | Sin `time_mode`, `time_at`, `duration_min` (anteriores a la migración de `app/db.py:139-143`). |
| `tools/fixtures5/board.json` | `Board` | 34 | Recortado a mano: sin `worst_level`, `worst_line`, `max_delay`, `updated_at`, `data_age`, `quota`, `last_error`; `route` sin `origin_name`/`dest_name`; salidas sin `aimed_at` (y algunas sin `length`); y un campo raíz `age` que el código actual **no** emite. |
| `tools/fixtures5/routes.json` | `RouteList` | 7 | Rutas recortadas: sin `origin_id`, `dest_id`, `time_mode`, `time_at`, `duration_min`, `position`, `created_at`. |

Validando sin `required` (solo tipos de los campos que sí vienen), los cuatro
cumplen salvo el `age` raíz de `fixtures5/board.json`. Además
`tools/fixtures/board.json` marca la línea 13 con
`"trafic est interrompu sur toute la ligne"` como `level: 1` (perturbada): es
el error que corrigió la regex de `app/board.py:23-33`; hoy saldría
`level: 2`.
