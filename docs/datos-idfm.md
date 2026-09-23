# Datos abiertos de IDFM para el mapa

Qué datos abiertos de Île-de-France Mobilités (IDFM) sirven para el mapa de la
v2, con qué licencia, cómo se descargan, cómo se cruzan con los identificadores
que ya usa el servidor y cómo debería funcionar el módulo de mapa.

- Investigación hecha el **24/09/2026** (entre las 00:20 y las 00:40, hora de París).
- **Todas las pruebas, sin clave** y con muestras pequeñas (`limit`, `where`,
  `select`, peticiones HTTP `Range`). No se ha llamado a PRIM ni al servidor de
  producción.
- Las muestras reales guardadas para los tests están en
  `trajet-server/tests/fixtures/idfm/` (unos 184 KB con su `README.md`, que
  dice de dónde sale cada fichero).
- Las cifras de tamaños, puntos y memoria son **medidas** en este PC salvo
  cuando se dice «estimado».

---

## 0. Resumen

| lo que pide el mapa | de dónde sale | licencia | ¿hace falta clave? |
|---|---|---|---|
| Trazado de las líneas de una ruta (tren, RER, metro, tranvía, bus) | `traces-des-lignes-de-transport-en-commun-idfm` (trazados del GTFS, todas las líneas, 3 veces al día). Para tren/RER/metro/tranvía, alternativa de más calidad: `traces-du-reseau-ferre-idf` + `emplacement-des-gares-idf` | ODbL / Licence Ouverte 2.0 | No |
| Color oficial y color del texto de cada línea | `referentiel-des-lignes` (`colourweb_hexa`, `textcolourweb_hexa`) | ODbL | No |
| Paradas y andenes con coordenadas | Référentiel des arrêts: `zones-de-correspondance`, `zones-d-arrets`, `arrets`, `relations`, `arrets-transporteur`; paradas por línea en `arrets-lignes` | Licence Ouverte 2.0 (`arrets-lignes`: ODbL) | No |
| Accesos a las estaciones (para ir andando al más cercano) | `acces` + `relations-acces` (los mismos accesos que `IDFM:StopPlaceEntrance:*` del GTFS) | Licence Ouverte 2.0 | No |
| Distancia y tiempo de cada acceso a cada andén | `pathways.txt` del GTFS (`length`, `traversal_time`) | Licence Mobilités | No en el fichero directo; **sí** (cuenta) en el portal |
| Transbordos a pie entre andenes | **No hay geometría abierta.** Solo tiempos mínimos (`transfers.txt`) y la posición en el tren para el metro (`positionnement-dans-la-rame`) | Licence Mobilités / Licence Ouverte 2.0 | — |

Propuesta del módulo (sección 8), en una frase: **bajar bajo demanda solo las
líneas y estaciones de las rutas guardadas**, recortar el trazado entre la
parada de subida y la de bajada, simplificarlo con Douglas-Peucker en metros
(2 m y 20 m), mandarlo como polilínea codificada dentro de un JSON pequeño con
ETag, guardarlo en SQLite y refrescarlo con una comprobación diaria de una sola
llamada al catálogo. Nunca se descarga un dataset entero: el de trazados pesa
unos 100 MB y no cabe en 384 MB de memoria una vez parseado.

---

## 1. Portales y API

### 1.1 `data.iledefrance-mobilites.fr` (Opendatasoft)

Es el portal que sirve los datos. API **Explore v2.1** de Opendatasoft:

| uso | URL |
|---|---|
| Registros paginados | `https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets/<id>/records?where=…&select=…&limit=…` |
| Exportación completa o filtrada | `…/catalog/datasets/<id>/exports/<formato>?where=…&select=…` (`json`, `geojson`, `csv`, `parquet`, `fgb`, `shp`, …) |
| Catálogo (metadatos, frescura) | `…/catalog/datasets?where=dataset_id in (…)&select=dataset_id,modified,data_processed,records_count,license` |
| Página humana del dataset | `https://data.iledefrance-mobilites.fr/explore/dataset/<id>/information/` |

Comportamiento **observado** (no supuesto):

- `records` admite `limit` de -1 a 100 y `offset + limit ≤ 10000`; con 101 o
  con `offset=9995&limit=10` responde `InvalidRESTParameterError`. Para más
  filas hay que usar `exports`, que no tiene ese tope.
- ODSQL funciona con `where` de igualdad, `in (…)`, `like`, `and`/`or`, y con
  funciones geográficas: `intersects(geo_shape, geom'POLYGON((…))')`,
  `in_bbox(geo_point_2d, lat1, lon1, lat2, lon2)` y
  `within_distance(accgeopoint, geom'POINT(lon lat)', 350m)` (las tres
  probadas). `select` con agregados y `group_by` también funciona.
- En las exportaciones GeoJSON la geometría se incluye aunque el campo
  geográfico no esté en `select`.
- Cabeceras de respuesta: `Cache-Control: public, max-age=60`, compresión
  `gzip` si se pide, `X-RateLimit-Limit: 1000000` y `X-RateLimit-Reset` a
  medianoche UTC. **No hay `ETag` ni `Last-Modified`** en `records`, `exports`
  ni en la ficha del dataset. La frescura se mira con `data_processed` del
  catálogo (sección 8.7).
- Los datasets con **Licence Mobilités** (`offre-horaires-tc-gtfs-idfm`,
  `perimetre-des-donnees-tr-disponibles-plateforme-idfm`, `etat-des-ascenseurs`)
  responden `{"error_code": "ForbiddenAccess"}` sin sesión. La ficha de PRIM
  del GTFS lo dice: «Connexion requise — Connectez-vous ou créez un compte pour
  exporter ou visualiser ce jeu de données soumis à la Licence Mobilité».

### 1.2 `prim.iledefrance-mobilites.fr`

PRIM tiene una ficha por dataset (`https://prim.iledefrance-mobilites.fr/fr/jeux-de-donnees/<id>`)
cuyas descargas apuntan a la misma API de `data.iledefrance-mobilites.fr`
(comprobado en la ficha de `acces`: enlaces a
`…/api/explore/v2.1/catalog/datasets/acces/exports/{csv,geojson,json,parquet,…}`).
La clave de PRIM (`apikey`) es para las API de tiempo real y Navitia; **no
hace falta para ningún dataset estático de este documento**. Algunas fichas de
PRIM devuelven 403 a clientes sin JavaScript (protección anti-bots); la API de
datos no.

### 1.3 Fichero GTFS

`https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip` (es el recurso GTFS
que enlaza también transport.data.gouv.fr). Probado sin credenciales:

- `HEAD` → 200, 131 966 412 bytes, `ETag: "6ab3e0e9-7dda5cc"`,
  `Last-Modified: Wed, 23 Sep 2026 14:23:37 GMT`, `Accept-Ranges: bytes`.
- `If-None-Match` con ese ETag → **304**; `If-Modified-Since` → **304**.
- `Range` → 206. Con eso se puede leer el directorio central del zip y bajar
  **solo** los miembros pequeños (`pathways.txt` son 74 912 bytes comprimidos,
  `transfers.txt` 1,66 MB, `stops.txt` 1,70 MB) sin bajar los 132 MB.

Contenido del zip (leído del directorio central):

| fichero | descomprimido | comprimido | ¿sirve al mapa? |
|---|---|---|---|
| `stops.txt` | 5,03 MB | 1,70 MB | sí (paradas, zonas y accesos con coordenadas) |
| `pathways.txt` | 0,55 MB | 0,07 MB | sí (acceso ↔ andén: metros y segundos) |
| `transfers.txt` | 5,55 MB | 1,66 MB | sí (tiempo mínimo de transbordo entre dos paradas) |
| `shapes.txt` | 131,22 MB | 28,42 MB | ya viene agregado por línea en el dataset de trazados; no hace falta |
| `stop_times.txt` | 890,62 MB | 87,50 MB | no |
| `trips.txt` | 54,71 MB | 4,20 MB | no |
| `object_codes_extension.txt` | 97,31 MB | 8,36 MB | no (equivalencias con NeTEx) |
| `routes.txt`, `agency.txt`, `attributions.txt`, `calendar*.txt`, `booking_rules.txt`, `ticketing_deep_links.txt` | < 0,2 MB | — | `routes.txt` repite colores; el resto no |

La documentación oficial del GTFS (`https://eu.ftp.opendatasoft.com/stif/GTFS/opendata_gtfs.pdf`)
fija el calendario de actualización: **08 h** datos SNCF del día (a diario),
**13 h** resto de operadores (laborables), **17 h** SNCF de última hora (si hay
incidencias). Y avisa de que `shapes.txt` se genera automáticamente con un
calculador basado en OpenStreetMap, «en conséquence, ce fichier est soumis à la
licence Open Database License (ODbL)».

---

## 2. Identificadores: cómo se cruza todo con lo que ya usa el servidor

### 2.1 Lo que guarda y usa hoy el servidor

- Cada tramo de una ruta guarda `line_id`, `from_id` y `to_id`
  (`trajet-server/app/db.py:36-50`). Salen de Navitia: `line_id` del enlace de
  tipo `line` de la sección (`app/planner.py:75`) y `from_id`/`to_id` del
  `stop_area` de la sección (`app/planner.py:34-41`). Es decir, **Navitia**:
  `line:IDFM:C01739` y `stop_area:IDFM:71370`.
- La conversión a SIRI está en `app/idfm.py`: `sa_code` (`:15-19`),
  `sa_to_siri` → `STIF:StopArea:SP:71370:` (`:22-24`), `line_code` (`:27-31`),
  `line_to_siri` → `STIF:Line::C01739:` (`:34-36`).
- El tablero pide `stop-monitoring` con el `StopArea` padre
  (`app/prim.py:9-10`, `:127-141`). La sonda de andenes pidió
  `MonitoringRef=STIF:StopArea:SP:71370:` (`probe/platform_probe.py:26`, `:67`)
  y guardó el `MonitoringRef` de cada paso (`probe/platform_probe.py:88`). En
  `probe/probe_observations.jsonl` los trenes SNCF vuelven con
  `STIF:StopArea:SP:58566:` y metro y bus con `STIF:StopPoint:Q:<n>:`
  (p. ej. `Q:462972` para el metro 14, `Q:478615` para un bus).
- La documentación de PRIM («Identification des objets», actualizada el
  05/05/2025) dice que `STIF:StopArea:SP:XXXXX:` lleva el id de **zona de
  paradas (ZdA)** y que desde el 13/03/2025 los próximos pasos SNCF solo se dan
  por ZdA. El servidor le pasa el de la **zona de correspondencia (ZdC)** y
  funciona (lo dice el comentario de `app/prim.py:9-10` y lo confirma la
  sonda). Para el mapa no cambia nada, pero conviene saberlo.

### 2.2 La jerarquía del Référentiel des arrêts

`Arrêt transporteur (ArT) > Arrêt de référence (ArR) > Zone d'arrêts (ZdA) > Zone de correspondance (ZdC) > Pôle d'échange`

- **ZdC**: zona multimodal («Gare Saint-Lazare», `71370`). Es lo que Navitia
  llama `stop_area` y lo que el GTFS pone como `parent_station`
  (`location_type=1`).
- **ZdA**: zona monomodal («Gare Saint-Lazare» de los trenes, `58566`; «Saint-Lazare»
  del metro, `462374`).
- **ArR** (`arrid`): el punto donde se sube (un andén del metro, un poste de
  bus, una vía del tren).
- **ArT**: el objeto del operador; en SNCF trae el número de vía en `publiccode`.

### 2.3 Tabla de equivalencias (todas comprobadas con datos reales)

| objeto | referencial IDFM | GTFS IDFM | Navitia (PRIM) | SIRI (PRIM) |
|---|---|---|---|---|
| Línea J | `id_line = C01739` (`referentiel-des-lignes`), `idrefligc = C01739` (trazados ferroviarios, gares), `id_ilico = C01739` (trazados GTFS) | `route_id = IDFM:C01739` | `line:IDFM:C01739` | `STIF:Line::C01739:` |
| Gare Saint-Lazare (multimodal) | `zdcid = 71370` | `stop_id = IDFM:71370`, `location_type = 1` | `stop_area:IDFM:71370` | el servidor usa `STIF:StopArea:SP:71370:` |
| Saint-Lazare, zona de los trenes | `zdaid = 58566` | `IDFM:monomodalStopPlace:58566` (es la parada de los RER/Transilien) | `stop_point:IDFM:monomodalStopPlace:58566` (visto en `accessibilite-en-gare`) | `STIF:StopArea:SP:58566:` |
| Andén del metro 14 en Saint-Lazare | `arrid = 462972` (ZdA `462374`) | `IDFM:462972` (metro, tranvía y bus usan el ArR) | — | `STIF:StopPoint:Q:462972:` |
| Poste de bus «Pasquier - Anjou» | `arrid = 478615` (ZdA `427068`) | `IDFM:478615` | — | `STIF:StopPoint:Q:478615:` |
| Acceso «r. Saint-Lazare» nº 11 | `accid = 50148706`, `accshortname = 11` | `IDFM:StopPlaceEntrance:50148706`, `stop_code = 11`, `parent_station = IDFM:71370` | — | — |
| Argenteuil | ZdC `65063`, ZdA de los trenes `47875` | `IDFM:65063`, `IDFM:monomodalStopPlace:47875` | `stop_area:IDFM:65063` (mismo patrón; no observado) | `STIF:StopArea:SP:47875:` (patrón de PRIM; no observado) |
| Metro 14 / bus 272 | `C01384` / `C01254` | `IDFM:C01384` / `IDFM:C01254` | `line:IDFM:…` | `STIF:Line::C01384:` / `…C01254:` |

Reglas prácticas:

1. `line_code(leg["line_id"])` (`app/idfm.py:27-31`) da `C01739`, que sirve
   tal cual en todos los datasets.
2. `sa_code(leg["from_id"])` (`app/idfm.py:15-19`) da la ZdC (`71370`).
3. Para saber **en qué parada** de esa ZdC se sube a esa línea: cruzar las
   paradas de la línea (`arrets-lignes`, `stop_id` = `IDFM:<arrid>` o
   `IDFM:monomodalStopPlace:<zdaid>`) con la jerarquía de la ZdC
   (`relations` o `zones-d-arrets`). Para tren/RER/metro/tranvía también sirve
   `emplacement-des-gares-idf` (`idrefligc` + `id_ref_zdc` → punto e `id_ref_zda`).
4. Si en la FASE 1 se guarda además el `stop_point` de Navitia de cada tramo
   (`app/planner.py:36` ya lo lee pero lo descarta), el paso 3 deja de ser una
   búsqueda y pasa a ser directo.
5. El `MonitoringRef` de cada paso del tablero (`SP:<zdaid>` o `Q:<arrid>`)
   señala la ZdA o el andén exacto: con `arrets` se puede pintar en el mapa el
   punto preciso del que sale el próximo tren o bus.

---

## 3. Fichas de los datasets útiles

Base de todas las URL de la API:
`https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets/`.
Tamaños «estimado»: exportando una muestra (40 a 1000 registros) y
extrapolando al número total de registros; son órdenes de magnitud.

### 3.1 Trazados de las líneas (fuente GTFS) — `traces-des-lignes-de-transport-en-commun-idfm`

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/traces-des-lignes-de-transport-en-commun-idfm/information/ · PRIM: https://prim.iledefrance-mobilites.fr/fr/jeux-de-donnees/traces-des-lignes-de-transport-en-commun-idfm
- **Export probado**: `traces-des-lignes-de-transport-en-commun-idfm/exports/geojson?where=id_ilico='C01739'&select=route_id,id_ilico,route_short_name,route_type,route_color,operatorname,networkname,shape` → 200. J: 229 706 bytes, 1 MultiLineString de 23 partes y 11 019 puntos. Metro 14 (`C01384`): 72 215 bytes, 19 partes. Bus 272 (`C01254`): 53 567 bytes, 13 partes.
- **Clave**: no.
- **Licencia**: ODbL (versión francesa). Los trazados se calculan sobre OpenStreetMap (ver 1.3).
- **Formato**: GeoJSON (`LineString`/`MultiLineString`), WGS84.
- **Tamaño**: 2 027 líneas; volcado completo **estimado ~100 MB** en GeoJSON (~19 MB con gzip).
- **Actualización**: «Trois fois par jour» (metadatos DCAT); `data_processed` 2026-09-23T15:00:42Z.
- **Campos clave**: `route_id` (`IDFM:C01739`), `id_ilico` (`C01739`), `route_short_name`, `route_type` (`Rail`, `Subway`, `Bus`…), `route_color` (sin `#`), `operatorname`, `networkname`, `shape`.
- **Cruce con PRIM**: `id_ilico` = `line_code()` del servidor.
- **Ojo**: una línea es **un único MultiLineString con un recorrido por sentido y variante, solapados**. La J suma 982,6 km cuando su red ferroviaria mide 181,5 km; el 14, 302,5 km. Hay que elegir la parte correcta y recortarla (sección 8.3). Probado: para Saint-Lazare → Argenteuil, 8 de las 23 partes pasan por las dos paradas en el sentido bueno (distancias de 8 a 24 m a la línea) y el recorte mide 9,69–9,71 km. En el bus 272 salen dos variantes para el mismo par de paradas (2,16 km y 2,87 km).

### 3.2 Trazados del ferrocarril — `traces-du-reseau-ferre-idf`

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/traces-du-reseau-ferre-idf/information/
- **Export probado**: `traces-du-reseau-ferre-idf/exports/geojson?where=indice_lig='J'` → 200, 130 041 bytes, 56 tramos. Con `intersects(geo_shape, geom'POLYGON((2.25 48.87, 2.33 48.87, 2.33 48.951, 2.25 48.951, 2.25 48.87))')` → 8 tramos.
- **Clave**: no. **Licencia**: Licence Ouverte v2.0 (Etalab).
- **Formato**: GeoJSON `LineString`. **Tamaño**: 1 673 tramos, **estimado ~3,4 MB** (~1,1 MB con gzip).
- **Actualización**: «Annuelle»; `data_processed` 2026-07-16T14:43:15Z.
- **Modos**: METRO 394 tramos, RER 268, TRAIN 321, TER 406, TRAMWAY 273, NAVETTE 7, CABLE 4. **Sin bus.**
- **Campos clave**: `idrefligc` (línea comercial, `C01739`), `idrefliga` (administrativa), `res_com` (`TRAIN J`, `METRO 14`), `indice_lig` (`J`, `14`), `mode`, `colourweb_hexa`, `shape_leng`, `date_mes`, `geo_shape`.
- **Estructura**: según su descripción, un tramo por línea y por tramo entre estaciones (y en los cruces), duplicado si varias líneas comparten vía. Comprobado: en la J, 100 de los 112 extremos de tramo coinciden **exactamente** con los puntos de `emplacement-des-gares-idf`; el camino Saint-Lazare → Argenteuil son los tramos 279, 321, 280, 283, 282 y 281 (9,83 km).
- **Trampas medidas**:
  - El tramo `objectid_1=550` de la J trae `idrefligc='C0173'` (truncado) y `idrefliga='A0185'`; los TER traen `idrefligc='NR'`. Filtrar por `idrefligc='C01739' or res_com='TRAIN J'`.
  - `indice_lig='14'` mezcla el metro 14 (`C01384`, 20 tramos) y el tranvía T14 (`C02732`, 4 tramos): no filtrar por `indice_lig`.
  - Con coincidencia exacta de extremos, el grafo del metro 14 sale partido en 2–3 piezas y el del metro 1 en 2. Probando tolerancias de 0,5, 5, 25 y 60 m, el M14 queda conexo a partir de **25 m** y el M1 solo con **60 m**. J, L, RER A y T2 salen conexos sin tolerancia.

### 3.3 Estaciones por línea — `emplacement-des-gares-idf` (y `…-data-generalisee`)

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/emplacement-des-gares-idf/information/
- **Export probado**: `emplacement-des-gares-idf/exports/geojson?where=id_ref_zdc in (71370, 65063)` → 200, 7 puntos (J, L, metros 3, 12, 13, 14 en Saint-Lazare; J en Argenteuil). `where=indice_lig='J'` → 52 estaciones.
- **Clave**: no. **Licencia**: Licence Ouverte v2.0. **Formato**: GeoJSON `Point`.
- **Tamaño**: 1 240 puntos, **estimado ~1,1 MB**. **Actualización**: «Annuelle»; `data_processed` 2025-12-10T14:10:02Z.
- **Campos clave**: `id_gares`, `nom_gares`, `nom_iv` (nombre tal como se ve en la red), `id_ref_zdc`, `id_ref_zda`, `idrefligc`, `res_com`, `indice_lig`, `mode`, `principal`.
- **Uso**: un punto por estación **y por línea**, sobre la vía. Son los nodos del grafo de 3.2 y dan las paradas intermedias con nombre.
- `emplacement-des-gares-idf-data-generalisee` (999 puntos, Licence Ouverte 2.0, probado: `where=id_ref_zdc in (71370,65063)` → 2) da **un punto por estación** con todas sus líneas en `res_com` («TRAIN J / TRAIN L / RER E / METRO 3 / …»): útil para etiquetas con zoom lejano.

### 3.4 Referencial de líneas y colores — `referentiel-des-lignes`

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/referentiel-des-lignes/information/ · PRIM: https://prim.iledefrance-mobilites.fr/fr/jeux-de-donnees/referentiel-des-lignes
- **Export probado**: `referentiel-des-lignes/exports/json?where=id_line='C01739'` → 200, 1 registro.
- **Clave**: no. **Licencia**: ODbL. **Formato**: JSON/CSV (sin geometría).
- **Tamaño**: 2 128 líneas, **estimado ~1,9 MB** (~0,2 MB gzip). **Actualización**: «Quotidienne»; `data_processed` 2026-09-23T10:21:29Z.
- **Campos clave**: `id_line`, `name_line`, `shortname_line`, `transportmode` (`rail`, `metro`, `tram`, `bus`…), `transportsubmode`, `networkname`, `operatorname`, `colourweb_hexa`, `textcolourweb_hexa`, `status`, `valid_fromdate`/`valid_todate`, `id_groupoflines`, `picto`.
- **Valores reales**: J `cec73d` / texto `000000`; L `c4a4cc` / `000000`; RER A `eb2132` / `ffffff`; metro 14 `640082` / `ffffff`; T2 `a0006e` / `ffffff`; bus 272 `ff5a00` / `000000`.
- Hoy el color ya llega de Navitia al guardar la ruta (`app/planner.py:79`); este dataset añade el **color del texto** y permite refrescar los dos.

### 3.5 Paradas de cada línea — `arrets-lignes`

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/arrets-lignes/information/
- **Export probado**: `arrets-lignes/exports/json?where=id='IDFM:C01739'` → 200, 54 paradas. Por `stop_id in (<paradas de la ZdC 65063>)` → 29 filas (16 líneas en Argenteuil).
- **Clave**: no. **Licencia**: ODbL. **Formato**: JSON/CSV con `pointgeo`.
- **Tamaño**: 74 038 filas, **estimado ~29 MB** (~3,6 MB gzip). **Actualización**: «Quotidienne»; `data_processed` 2026-09-23T15:06:22Z.
- **Campos clave**: `id` (`IDFM:C01739`), `stop_id` (igual que el GTFS: `IDFM:monomodalStopPlace:<zdaid>` en RER/Transilien, `IDFM:<arrid>` en el resto), `stop_name`, `stop_lon`, `stop_lat`, `mode`, `operatorname`.
- **Uso**: coordenadas de la parada de subida/bajada y de las intermedias de cualquier línea, bus incluido.

### 3.6 Référentiel des arrêts (paradas, zonas y jerarquía)

Todos con **Licence Ouverte v2.0**, sin clave, actualización «Quotidienne»
(`data_processed` del 22 o 23/09/2026). Coordenadas en WGS84 (`*geopoint`) y
en Lambert 93 (`*epsg2154`).

| dataset (id) | qué es | campos clave | probado | tamaño |
|---|---|---|---|---|
| `zones-de-correspondance` | ZdC | `zdcid`, `zdcname`, `zdctype` (`railStation`…), centroide Lambert 93 (sin geopoint) | `where=zdcid in ('71370','65063')` → 2 | 15 552 filas, est. ~4,4 MB |
| `zones-d-arrets` | ZdA | `zdaid`, `zdaname`, `zdatype` (`railStation`, `metroStation`, `onstreetBus`…), `zdcid` | `where=zdcid in ('71370','65063')` → 11 | 18 013 filas, est. ~5,5 MB |
| `arrets` | ArR (andén, poste, vía) | `arrid`, `arrname`, `arrtype` (`rail`, `metro`, `bus`…), `zdaid`, `arrgeopoint`, `arraccessibility` | `where=zdaid in (<8 ZdA>)` → 55 en Saint-Lazare; 24 en Argenteuil | 37 963 filas, est. ~18,6 MB GeoJSON |
| `relations` | la jerarquía entera en una tabla | `pdeid`, `zdcid`, `zdaid`, `arrid`, `artid`, `arrgeopoint`, `artgeopoint` | `where=zdcid in ('71370','65063')` → 139 | 55 952 filas, est. ~20 MB |
| `arrets-transporteur` | ArT (objeto del operador) | `artid`, `arrid`, `artname`, `fournisseurname`, `privatecode`, **`publiccode` (número de vía, SNCF)**, `artgeopoint` | `where=arrid in (<27 ArR rail de la ZdA 58566>)` → 28 (vías 1 a 27) | 55 929 filas, est. ~33 MB |
| `poles-d-echange` | polos (aeropuertos, grandes estaciones) | `pdeid`, `pdename` | `limit=3` → 200 (10 filas; p. ej. «Paris Saint-Lazare - Opéra») | mínimo |
| `referentiel-arret-tc-idf` | los mismos objetos en shapefile | enlaces a `REF_ZdA.zip` (36,4 MB), `REF_ArR.zip` (2,5 MB), `REF_ZdC.zip` (160 bytes, parece vacío) | `records` → 200; zips solo con `HEAD` | — |

Páginas: `https://data.iledefrance-mobilites.fr/explore/dataset/<id>/information/`.

Nota útil para la función «vía»: en Saint-Lazare las vías 1 a 27 tienen
coordenadas propias en `arrets-transporteur` (`publiccode`); las vías 6 y 7
comparten `arrid 471658`, y el `arrid 41194` («GARE ST LAZARE») trae
`publiccode='-'`. Con eso el mapa puede marcar la vía prevista por
`app/platform.py`. Son puntos, no el andén entero.

### 3.7 Accesos — `acces` y `relations-acces`

- **Páginas**: https://data.iledefrance-mobilites.fr/explore/dataset/acces/information/ · https://data.iledefrance-mobilites.fr/explore/dataset/relations-acces/information/ · PRIM: https://prim.iledefrance-mobilites.fr/fr/jeux-de-donnees/acces
- **Exports probados**:
  - `relations-acces/exports/json?where=zdaid in (<11 ZdA de Saint-Lazare y Argenteuil>)` → 22 filas.
  - `acces/exports/geojson?where=accid in (<14 accid>)&select=accid,accname,accshortname,accdescription,accisentry,accisexit,fournisseurname,accgeopoint` → 14 accesos en Saint-Lazare, 4 en Argenteuil.
  - `acces/exports/geojson?where=within_distance(accgeopoint, geom'POINT(2.32535 48.87594)', 350m)` → 27 accesos (incluye los de Havre-Caumartin y Haussmann-Saint-Lazare, que son otras ZdC).
- **Clave**: no. **Licencia**: Licence Ouverte v2.0. **Formato**: GeoJSON `Point`.
- **Tamaño**: `acces` 2 523 filas, **estimado ~1,2 MB** (~0,15 MB gzip); `relations-acces` 2 553 filas, ~0,2 MB. **Actualización**: «Quotidienne».
- **Campos clave**: `accid`, `accname` («r. Saint-Lazare»), `accshortname` (el número del acceso), `accisentry`/`accisexit` (`"true"`/`"false"` como texto), `fournisseurname` (RATP/SNCF), `accgeopoint`. En `relations-acces`: `zdaid` ↔ `accid`.
- **Cruce**: `accid` = número de `IDFM:StopPlaceEntrance:<accid>` en el GTFS (la propia descripción del dataset lo dice, y se ha comprobado con `50148706`). Un acceso puede servir a varias ZdA (en Saint-Lazare, «cour de Rome» nº 1 sirve al metro `462374` y a los trenes `58566`).
- **Ejemplo real**: «cour du Havre» nº 9 es **solo salida** (`accisentry="false"`); a los trenes de Saint-Lazare (`58566`) se entra por «r. Budapest», «r. de Rome» y «r. de Londres» (SNCF) y por varios accesos RATP compartidos.

### 3.8 GTFS — `offre-horaires-tc-gtfs-idfm`

- **Página**: https://data.iledefrance-mobilites.fr/explore/dataset/offre-horaires-tc-gtfs-idfm/information/ · PRIM: https://prim.iledefrance-mobilites.fr/fr/jeux-de-donnees/offre-horaires-tc-gtfs-idfm · transport.data.gouv.fr: https://transport.data.gouv.fr/datasets/reseau-urbain-et-interurbain-dile-de-france-mobilites
- **Probado**: la API del portal → **403 `ForbiddenAccess`** sin sesión. El fichero directo `https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip` → 200 sin credenciales, con `ETag`/`Last-Modified`, 304 condicional y `Range` (ver 1.3).
- **Licencia**: **Licence Mobilités** (y `shapes.txt` ODbL por venir de OSM).
- **Tamaño**: 132 MB comprimido. **Actualización**: 3 veces al día (08 h, 13 h, 17 h).
- **Lo que sirve al mapa**:
  - `stops.txt` (53 421 filas): 35 044 paradas `IDFM:<arrid>`, 471 paradas `IDFM:monomodalStopPlace:<zdaid>` (RER/Transilien), 15 390 zonas `location_type=1` (`IDFM:<zdcid>`) y **2 516 accesos** `location_type=2` (`IDFM:StopPlaceEntrance:<accid>`, con `stop_code` = número de acceso y `parent_station` = ZdC). La documentación en PDF describe otro formato de id de acceso (`StationEntrance:[ZdA]-IO…`); el fichero real usa `IDFM:StopPlaceEntrance:<accid>`.
  - `pathways.txt` (4 975 filas): **acceso ↔ parada** con `length` (1,2 a 636 m, mediana 78,7 m) y `traversal_time` (mediana 83 s). `pathway_mode` es siempre `1` (voie piétonne), aunque la documentación prevé también escaleras, ascensores, etc.; `stair_count`, `max_slope`, `min_width` y `signposted_as` vienen vacíos. Hay 376 caminos de un solo sentido (`is_bidirectional=0`). Ejemplo: de «r. de Londres» a la zona de los trenes de Saint-Lazare, 149,46 m y 158 s; de «r. Budapest», 212,91 m y 226 s.
  - `transfers.txt` (191 622 filas, todas `transfer_type=2`): tiempo mínimo entre dos paradas cercanas. Ejemplo: trenes de Saint-Lazare (`monomodalStopPlace:58566`) → andén del metro 14 (`462972`): 360 s.
- **Uso recomendado**: no descargar el zip; leer por `Range` solo `pathways.txt` y `transfers.txt` (sección 8.2).

### 3.9 Complementarios

| dataset | qué aporta | licencia | probado |
|---|---|---|---|
| `positionnement-dans-la-rame` | en qué coche subir en el metro para la salida o el transbordo (`from_id`/`to_id` = ArR, `line_id`, `position`, `position_max`, `position_average`, `equipment_type`); 5 239 filas, RATP, faltan RER A y B en Châtelet | Licence Ouverte 2.0 | `where=from_name like 'Saint-Lazare%' or to_name like 'Saint-Lazare%'` → 247 (p. ej. metro 14 desde `21962` hacia `462969`: coche 5 de 8, «Milieu», escalera mecánica) |
| `accessibilite-en-gare` | nivel de accesibilidad por estación; su `stop_point_id` usa el formato Navitia (`stop_point:IDFM:monomodalStopPlace:58566`) | Licence Ouverte 2.0 | `where=stop_name like '%Lazare%'` → 2 |
| `traces-des-lignes-regulieres-de-bus-en-ile-de-france` | un trazado por línea de bus comercial (1 939), con `linecolor` y `linetextco`; atribución «© Les contributeurs OpenStreetMap»; `updated` 07/09/2026 | ODbL | `exports/geojson?where=lineid like '%C01254%'` → 200, 85 925 bytes. Redundante con 3.1, sin sentidos separados |
| `etat-des-ascenseurs` | estado de ascensores por ZdC, 3 veces al día | Licence Mobilités | **403** sin sesión |
| `perimetre-des-donnees-tr-disponibles-plateforme-idfm` | qué paradas y líneas tienen tiempo real | Licence Mobilités | **403** sin sesión |
| `schema_*`, `traces-du-reseau-de-transport-ferre-dile-de-france-schematique` | planos esquemáticos, no geográficos | Licence Ouverte 2.0 | no sirven para un mapa real |
| `plans-region`, `plans-de-secteur` | planos en imagen | CC BY-NC-ND | no reutilizables en la app |

---

## 4. Pruebas realizadas (todas sin clave)

Fecha: 23/09/2026 22:23–22:40 UTC. Base `B = https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets`.

| # | petición | resultado |
|---|---|---|
| 1 | `B?limit=100` | 200 · 94 datasets en el catálogo |
| 2 | `B/referentiel-des-lignes/records?where=shortname_line in ('J','14','L','A','T2') and transportmode in ('rail','metro','tram')` | 200 · 5 líneas; J = `C01739` |
| 3 | `B/traces-des-lignes-de-transport-en-commun-idfm/exports/geojson?where=id_ilico='C01739'` | 200 · 229 706 B · 23 partes · 11 019 puntos |
| 4 | ídem `C01384` (metro 14) y `C01254` (bus 272) | 200 · 72 215 B y 53 567 B |
| 5 | `B/traces-du-reseau-ferre-idf/exports/geojson?where=indice_lig='J'` | 200 · 130 041 B · 56 tramos |
| 6 | ídem con `intersects(geo_shape, geom'POLYGON(…)')` / con `in_bbox(geo_point_2d, 48.87, 2.25, 48.951, 2.33)` | 200 · 8 / 7 tramos |
| 7 | `B/emplacement-des-gares-idf/records?where=id_ref_zdc in (71370, 65063)` | 200 · 7 |
| 8 | `B/zones-de-correspondance/records?where=zdcid in ('71370','65063')` · `B/zones-d-arrets/…` · `B/relations/…` | 200 · 2 · 11 · 139 |
| 9 | `B/arrets/records?where=zdaid in (…)` (Saint-Lazare / Argenteuil) | 200 · 55 / 24 |
| 10 | `B/arrets-transporteur/records?where=arrid in (…)` | 200 · 28 (vías) |
| 11 | `B/relations-acces/records?where=zdaid in (…)` · `B/acces/exports/geojson?where=accid in (…)` | 200 · 22 · 14 + 4 |
| 12 | `B/acces/exports/geojson?where=within_distance(accgeopoint, geom'POINT(2.32535 48.87594)', 350m)` | 200 · 27 · 12 884 B |
| 13 | `B/arrets-lignes/records?where=id='IDFM:C01739'` | 200 · 54 |
| 14 | `B/positionnement-dans-la-rame/records?where=…Saint-Lazare…` · `B/accessibilite-en-gare/…` · `B/poles-d-echange/…` · `B/emplacement-des-gares-idf-data-generalisee/…` | 200 en los cuatro |
| 15 | `B/traces-des-lignes-regulieres-de-bus-en-ile-de-france/exports/geojson?where=lineid like '%C01254%'` | 200 · 85 925 B |
| 16 | `B/offre-horaires-tc-gtfs-idfm/records?limit=5` · `B/perimetre-des-donnees-tr-disponibles-plateforme-idfm/records?…` · `B/etat-des-ascenseurs/records?limit=1` | **403 ForbiddenAccess** (Licence Mobilités, requiere sesión) |
| 17 | `HEAD https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip` + `If-None-Match` + `If-Modified-Since` + `Range` | 200 · 304 · 304 · 206 |
| 18 | `B?where=dataset_id in (…)&select=dataset_id,modified,data_processed,records_count,license` | 200 · frescura de 12 datasets en una llamada |
| 19 | `B/arrets/records?limit=101` · `…?limit=10&offset=9995` | error `InvalidRESTParameterError` (topes de `records`) |

---

## 5. Licencias y atribución

### 5.1 Licence Ouverte v2.0 (Etalab)

Texto: https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf
(redirige a `static.data.gouv.fr`). Obligación única: **mencionar la
paternidad**, es decir, «sa source (au moins le nom du Concédant) et la date
de dernière mise à jour de l'Information réutilisée», por ejemplo con un
enlace a la fuente. Afecta a: trazados ferroviarios, gares, todo el
Référentiel des arrêts, accesos, `positionnement-dans-la-rame`,
`accessibilite-en-gare`.

### 5.2 ODbL (versión francesa)

Enlace que da el portal: https://doc.transport.data.gouv.fr/le-point-d-acces-national/cadre-juridique/conditions-dutilisation-des-donnees/licence-odbl ·
texto original: https://opendatacommons.org/licenses/odbl/1-0/. Afecta a:
trazados GTFS (más la base OpenStreetMap), `referentiel-des-lignes`,
`arrets-lignes`, trazados de bus.

- §4.3: al usar públicamente un resultado (un mapa, una pantalla), poner un
  aviso de que el contenido sale de la base y está bajo ODbL.
- §4.4 y §4.6 (compartir igual): **solo** si una base derivada se «usa
  públicamente», y la licencia define «Publicly» como hacia personas que no
  sean uno mismo o alguien bajo su control. Trajet es un servidor casero para
  su dueño: basta con el aviso. Si algún día se publicara para terceros, la
  base derivada (trazados recortados y simplificados) tendría que ofrecerse
  bajo ODbL.
- Los trazados GTFS vienen de OpenStreetMap: añadir «© contributeurs OpenStreetMap».

### 5.3 Licence Mobilités

Texto: https://cloud.fabmob.io/s/eYWWJBdM3fQiFNm (enlace de los metadatos del
portal). Según la página de licencias de PRIM (https://prim.iledefrance-mobilites.fr/fr/licences):
se basa en la ODbL y añade la **posibilidad de exigir la identificación del
usuario**, una condición particular que **limita el compartir igual** de las
bases derivadas y un **compromiso de compatibilidad** con el SDRIF y el PDUIF.
Esa página dice que hoy solo cubre los pasos teóricos (GTFS) y en tiempo real,
aunque en el portal también la llevan `etat-des-ascenseurs` y
`perimetre-des-donnees-tr-disponibles-plateforme-idfm`. Es la licencia de lo
que el servidor ya consume de PRIM. El portal pide iniciar sesión para exportar
el GTFS; el titular de Trajet ya tiene cuenta en PRIM (su clave de API).

### 5.4 Texto de atribución propuesto para la app

En la esquina del mapa (enlace a una hoja) y en Ajustes → Acerca de:

> Datos: Île-de-France Mobilités — Référentiel des arrêts, accès et tracés du
> réseau ferré (Licence Ouverte v2.0, mise à jour du JJ/MM/AAAA) ; tracés des
> lignes, référentiel des lignes, arrêts et lignes associées (ODbL) ; horaires
> GTFS (Licence Mobilités). Tracés calculés sur OpenStreetMap © contributeurs
> OpenStreetMap.

La fecha sale del `data_processed` que el servidor guarda (sección 8.7) y el
servidor la manda en la respuesta del mapa.

---

## 6. Transbordos: qué hay y qué no

- **No hay** en los datos abiertos de IDFM ningún trazado de los pasillos
  dentro de las estaciones ni caminos andén → andén: `pathways.txt` solo une
  **accesos** con **paradas**, siempre en modo «voie piétonne» y sin
  geometría (sección 3.8).
- **Sí hay**:
  - tiempo mínimo de transbordo entre dos paradas (`transfers.txt`, p. ej. 360 s
    de los trenes de Saint-Lazare al metro 14);
  - metros y segundos de cada acceso a cada parada (`pathways.txt`);
  - coordenadas de los dos andenes (`arrets`);
  - en el metro, en qué coche ir para salir cerca del transbordo
    (`positionnement-dans-la-rame`).
- **Propuesta**: dibujar el transbordo como línea discontinua recta entre las
  dos paradas, con la etiqueta del tiempo de `transfers.txt` (y el coche
  recomendado si lo hay). Si las dos ZdC son distintas (p. ej. Gare
  Saint-Lazare `71370` y Haussmann Saint-Lazare `73688`), la app puede pedir
  a MapKit una ruta a pie por la calle entre sus accesos.
- **Camino hasta el acceso más cercano**: la app tiene la posición del
  usuario y las coordenadas de los accesos (sección 3.7). Elegir el acceso de
  **entrada** (`accisentry`) de la ZdA de la primera línea que minimice
  «andar hasta el acceso + `length` de `pathways.txt` hasta la parada», y
  pedir la ruta a pie por la calle a MapKit en el propio iPhone (sin datos de
  IDFM ni llamadas al servidor).

---

## 7. Lo que no se ha podido verificar

- **Geometrías de Navitia**: las secciones de `/journeys` y los objetos de
  `/lines` de Navitia suelen traer `geojson`. Sería otra fuente exacta del
  trayecto guardado, pero no se ha comprobado porque no se podía llamar a
  PRIM y en el repo no hay ninguna respuesta de `/journeys` guardada
  (`tools/fixtures*/` solo tiene `board.json` y `routes.json`). Además, gasta
  cuota de Navitia. Queda como mejora a verificar con una respuesta real.
- **NeTEx** de IDFM (enlazado en transport.data.gouv.fr): no explorado; es XML
  pesado y el GTFS y el referencial ya cubren lo necesario.
- El tamaño de un «paquete semilla» con toda la red ferroviaria simplificada
  (sección 8.9) no se ha medido.

---

## 8. Propuesta: módulo de mapa del servidor

Encaja con lo que fija `docs/servidor-v2.md:148-154` (módulo `app/mapdata.py`,
función `route_map(route)`, tabla `map_cache`, «si el portal cae, sirve lo
guardado; si no hay nada, devuelve paradas sin trazado»). Aquí va el detalle.

### 8.1 Principios

1. **Solo lo que usan las rutas guardadas.** Una ruta típica toca 1–3 líneas y
   2–4 estaciones: unas pocas decenas de KB de descarga.
2. **Nada de volcados completos.** Todas las peticiones llevan `where` por
   línea o por zona y `select` con los campos justos.
3. **Nunca en el camino crítico del tablero.** El mapa se calcula en segundo
   plano y se guarda; `/api/board` no depende de él.
4. **El último dato bueno se conserva siempre**, como hace ya `app/prim.py:84-123`
   con PRIM.
5. **Un cliente HTTP propio, sin la cabecera `apikey`.** El cliente de PRIM la
   pone en todas sus peticiones (`app/prim.py:69-73`); reutilizarlo mandaría la
   clave a Opendatasoft.

### 8.2 Qué descargar (y qué no)

| dato | petición | cuándo |
|---|---|---|
| Colores y modo de la línea | `referentiel-des-lignes/exports/json?where=id_line in ('C01739',…)&select=id_line,shortname_line,transportmode,transportsubmode,networkname,colourweb_hexa,textcolourweb_hexa,status` | al guardar la ruta y en el refresco |
| Paradas de la línea | `arrets-lignes/exports/json?where=id='IDFM:C01739'&select=stop_id,stop_name,stop_lon,stop_lat,mode` | ídem |
| Jerarquía de las zonas de la ruta | `relations/exports/json?where=zdcid in ('71370','65063')&select=zdcid,zdaid,arrid,arrgeopoint` y `zones-d-arrets/exports/json?where=zdcid in (…)&select=zdaid,zdaname,zdatype,zdcid` | ídem |
| Trazado (todas las líneas) | `traces-des-lignes-de-transport-en-commun-idfm/exports/geojson?where=id_ilico='C01739'&select=id_ilico,route_type,route_color,shape` | ídem |
| Trazado ferroviario (plan B para tren/RER/metro/tranvía) | `traces-du-reseau-ferre-idf/exports/geojson?where=idrefligc='C01739' or res_com='TRAIN J'&select=objectid_1,idrefligc,res_com,shape_leng` + `emplacement-des-gares-idf/exports/geojson?where=idrefligc='C01739'&select=nom_gares,nom_iv,id_ref_zdc,id_ref_zda` | solo si falla el trazado GTFS |
| Andenes y postes | `arrets/exports/geojson?where=zdaid in (…)&select=arrid,arrname,arrtype,zdaid,arrgeopoint` | ídem |
| Vías (solo estaciones SNCF) | `arrets-transporteur/exports/json?where=arrid in (…)&select=arrid,publiccode,artgeopoint` | ídem |
| Accesos | `relations-acces/exports/json?where=zdaid in (…)` → `acces/exports/geojson?where=accid in (…)&select=accid,accname,accshortname,accisentry,accisexit,accgeopoint` | ídem |
| Acceso → andén y transbordos | `pathways.txt` y `transfers.txt` del GTFS, por `Range` (≈1,7 MB en total), filtrados en streaming por los `stop_id` de las zonas de la ruta | semanal |
| Frescura | `catalog/datasets?where=dataset_id in (…)&select=dataset_id,data_processed` | a diario |

**No se descarga**: el zip GTFS entero, `shapes.txt`, `stop_times.txt`,
`trips.txt`, ninguna exportación sin `where`.

### 8.3 Algoritmo por tramo de la ruta

Entrada: `line_id`, `from_id`, `to_id` del tramo (`app/db.py:40-47`).

1. `code = line_code(line_id)`; `zdc_from = sa_code(from_id)`; `zdc_to = sa_code(to_id)` (`app/idfm.py:15-31`).
2. **Paradas candidatas**: las paradas de la línea (`arrets-lignes`) cuyo `stop_id`
   (quitando `IDFM:` o `IDFM:monomodalStopPlace:`) esté entre los `arrid` o
   `zdaid` de `zdc_from` / `zdc_to` según `relations`. En la J da
   `IDFM:monomodalStopPlace:58566` y `…:47875`. En un bus suele dar dos postes
   por zona (uno por sentido); se prueban todas las combinaciones.
3. **Recorte del trazado GTFS**: para cada parte del MultiLineString,
   proyectar las dos paradas (proyección plana local: `x = lon·cos(48,85°)·R`,
   `y = lat·R`, error despreciable en Île-de-France). Es candidata si las dos
   quedan a **≤ 50 m** y la de subida va antes que la de bajada. Se elige el
   **recorte más corto** y se corta en los puntos proyectados (interpolando).
   Medido: J Saint-Lazare → Argenteuil, 8 candidatas, distancias de 8 a 24 m,
   recorte de 9 769 m y 130 puntos; bus 272 Gare d'Argenteuil → Jean Moulin -
   Henri Barbusse, variantes de 2,16 y 2,87 km (se queda la de 2,16 km).
4. **Plan B ferroviario** (si no hay candidata y el modo no es bus): grafo con
   los tramos de `traces-du-reseau-ferre-idf` y las estaciones de
   `emplacement-des-gares-idf` como nodos, **uniendo extremos a menos de 60 m**,
   y Dijkstra por longitud entre la estación de `zdc_from` y la de `zdc_to`.
   Medido: la J da los tramos 279 → 321 → 280 → 283 → 282 → 281, 9,83 km.
5. **Plan C**: segmento recto entre las dos paradas (`"source": "recta"`).
6. **Paradas intermedias**: las de la línea que se proyectan a ≤ 30 m del
   recorte, en orden. En la J, entre Saint-Lazare y Argenteuil: Asnières-sur-Seine,
   Bois-Colombes, Colombes y Le Stade (comprobado contra las estaciones de
   `emplacement-des-gares-idf`: de 2 a 12 m del recorte).
7. **Simplificar** (8.4) y **codificar** (8.5).

Por estación (origen, cada transbordo y destino): ZdA, andenes (`arrets`),
vías si es SNCF, accesos con `accisentry`/`accisexit` y, por acceso, el
`length`/`traversal_time` de `pathways.txt` hasta cada parada de la ruta. Por
transbordo: `min_transfer_time` de `transfers.txt` entre la parada de bajada y
la de subida.

Todo en Python puro (Douglas-Peucker, proyección, Dijkstra con `heapq`,
polilínea): unas 150 líneas y **ninguna dependencia nueva** (hoy
`requirements.txt` solo tiene fastapi, uvicorn, httpx y tzdata). El cálculo se
hace fuera del bucle de eventos (`run_in_threadpool`, como ya hace
`app/main.py` con las estadísticas).

### 8.4 Simplificación (Douglas-Peucker en metros)

DP sobre la proyección plana del paso 3, con tolerancia en metros. Medidas
reales:

| trazado | original | 1 m | 2 m | 5 m | 10 m | 25 m | 50 m |
|---|---|---|---|---|---|---|---|
| J entera (GTFS, 23 partes) | 11 019 pts | 7 042 | 4 957 | 3 087 | 2 071 | 1 259 | 894 |
| Metro 14 entero (GTFS) | 3 456 | 2 827 | 2 472 | 1 604 | 1 081 | 684 | 474 |
| Bus 272 entero (GTFS) | 2 544 | 1 384 | 990 | 604 | 392 | 299 | 232 |
| **J Saint-Lazare → Argenteuil**, recorte del trazado GTFS (130 pts) | 130 | 72 pts · 281 B | **52 pts · 208 B** | 29 · 122 B | 16 · 75 B | 11 · 56 B | 8 · 45 B |
| **J Saint-Lazare → Argenteuil**, cadena de tramos ferroviarios (137 pts) | 137 | 73 pts · 289 B | **46 pts · 189 B** | 29 · 126 B | 17 · 78 B | 11 · 57 B | 8 · 46 B |

(Bytes = polilínea codificada con precisión 5.) A 20 m, los dos recortes se
quedan en 12 puntos (60 y 61 B). Parsear el GeoJSON de la J entera y pasar el
DP a sus 11 019 puntos tarda 0,28 s en este PC.

Metros por punto de pantalla en MapKit a la latitud de París
(156 543 · cos 48,9° / 2^zoom):

| zoom | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|
| m/pt | 100 | 50 | 25 | 12,6 | 6,3 | 3,1 | 1,6 | 0,8 | 0,4 |

Tolerancia recomendada = **error ≤ 1 punto de pantalla**:

- **Baja, 20 m**: vista de la ruta entera (zoom ≤ 13). J Saint-Lazare →
  Argenteuil: 12 puntos, 60 bytes.
- **Alta, 2 m**: de zoom 14 a 16 (estación, camino al acceso). 52 puntos,
  208 bytes (recorte GTFS).
- Por encima de zoom 16 no merece la pena bajar de 2 m: los propios datos no
  son más precisos (las paradas quedan a 8–24 m del trazado GTFS).

Con estos tamaños se pueden mandar siempre las dos versiones; la app cambia
de una a otra según `MKMapCamera.centerCoordinateDistance`.

### 8.5 Formato de respuesta

`GET /api/v1/routes/{id}/map` (token de dispositivo, como el resto de `/api/v1`).
JSON, polilínea codificada (algoritmo de Google, precisión 5, ~1,1 m), puntos
con 6 decimales, `gzip` y `ETag` fuerte (hash del cuerpo) con 304. Mantiene
las claves de `docs/servidor-v2.md:150` (`lines`, `stops`, `accesses`,
`generated_at`, `source`, `license`) y añade `transfers` y `stale`.

Ejemplo con datos reales (la polilínea `coarse` es la real del recorte de la J
a 20 m; la `fine` se abrevia):

```json
{
  "route_id": 3,
  "generated_at": "2026-09-24T00:40:00+02:00",
  "stale": false,
  "lines": [
    {
      "seq": 0,
      "line_id": "line:IDFM:C01739",
      "code": "J",
      "mode": "rail",
      "color": "#CEC73D",
      "text_color": "#000000",
      "from": {"zdc": "71370", "stop_id": "IDFM:monomodalStopPlace:58566", "name": "Gare Saint-Lazare", "lat": 48.877476, "lon": 2.324439},
      "to":   {"zdc": "65063", "stop_id": "IDFM:monomodalStopPlace:47875", "name": "Argenteuil", "lat": 48.946895, "lon": 2.257914},
      "path": {
        "encoding": "polyline5",
        "coarse": "ujiiHa~dMuSxLsg@~h@o_CzzE_rAlqBcJfKoKbEuMCkv@cVaNiA{MtBae@xZ",
        "fine": "ujiiHa~dMwDzBkDvAuD~B{BdB…",
        "tolerance_m": {"coarse": 20, "fine": 2}
      },
      "length_m": 9769,
      "via": [
        {"name": "Asnières-sur-Seine", "lat": 48.90598, "lon": 2.2832},
        {"name": "Bois-Colombes", "lat": 48.91425, "lon": 2.2716},
        {"name": "Colombes", "lat": 48.92392, "lon": 2.25935},
        {"name": "Le Stade", "lat": 48.9319, "lon": 2.26097}
      ],
      "source": "gtfs"
    }
  ],
  "stops": [
    {
      "zdc": "71370",
      "name": "Gare Saint-Lazare",
      "platforms": [
        {"id": "STIF:StopPoint:Q:462972:", "arrid": "462972", "line": "C01384", "lat": 48.875797, "lon": 2.324242}
      ],
      "tracks": [{"voie": "5", "lat": 48.877259, "lon": 2.323623}]
    }
  ],
  "accesses": [
    {
      "id": "50243328", "zdc": "71370", "zda": ["58566"],
      "name": "r. de Londres", "number": null,
      "entry": true, "exit": true,
      "lat": 48.87809, "lon": 2.325862,
      "to_stop": [{"stop_id": "IDFM:monomodalStopPlace:58566", "m": 149.46, "s": 158}]
    }
  ],
  "transfers": [],
  "source": {
    "traces-des-lignes-de-transport-en-commun-idfm": "2026-09-23T15:00:42Z",
    "acces": "2026-09-23T00:30:34Z"
  },
  "license": "Données : Île-de-France Mobilités (Licence Ouverte v2.0, ODbL, Licence Mobilités) · © contributeurs OpenStreetMap"
}
```

- El `id` de los andenes va en formato SIRI para que la app lo case con el
  `MonitoringRef` del tablero sin conversión.
- Una ruta como esta pesará del orden de 2–3 KB sin comprimir (estimado, con
  la `fine` completa de 208 B y todos los accesos). La app la guarda en disco
  y la vuelve a pedir con `If-None-Match`; casi siempre recibirá 304.
- Alternativa descartada: un array GeoJSON de coordenadas con 5 decimales
  ocupa unas 4,7 veces más para el mismo recorte (983 B frente a 208 B a 2 m)
  y MapKit no lo necesita.

### 8.6 Almacenamiento (tabla `map_cache`)

Una fila por clave, con el cuerpo ya procesado (no el dato crudo):

| clave | contenido |
|---|---|
| `line:C01739` | referencial de la línea (colores, modo) |
| `leg:C01739:71370:65063` | recorte simplificado (las dos polilíneas, `via`, `source`, `length_m`) |
| `zdc:71370` | andenes, vías, accesos y `pathways` de la estación |
| `transfer:71370` | `transfers.txt` filtrado de esa zona |
| `src:<dataset>` | último `data_processed` visto |
| `src:gtfs` | `ETag`/`Last-Modified` del zip |

Columnas sugeridas: `key TEXT PRIMARY KEY, body BLOB (json+gzip), raw_hash TEXT, fetched_at TEXT, source_version TEXT`.
Se guarda el hash del dato crudo para no recalcular si no ha cambiado. Una
ruta ocupa unos pocos KB. Va en la migración `m0002_v2.py`
(`docs/servidor-v2.md:28`).

### 8.7 Caché y refresco

- **Comprobación diaria** (p. ej. a las 03:30 de París, lejos de la franja de
  la sonda de andenes): **una** llamada al catálogo con
  `select=dataset_id,data_processed`. Solo se vuelven a pedir las claves de
  `map_cache` cuyo dataset tenga `data_processed` nuevo, y solo se recalculan
  si cambia el hash del dato crudo.
  - Los trazados GTFS cambian `data_processed` tres veces al día aunque la
    geometría casi nunca cambie: el hash evita recalcular. Basta con volver a
    pedirlos **una vez por semana** (lo que ya prevé `docs/servidor-v2.md:153`).
  - Référentiel des arrêts y accesos: diario (pocos KB por estación).
  - Ferrocarril y gares: «Annuelle» en origen; mensual es de sobra.
  - GTFS (`pathways`/`transfers`): semanal, con `If-None-Match` y, si cambió,
    lectura por `Range` de los dos miembros.
- **Opendatasoft no da `ETag` ni `Last-Modified`** (comprobado): el único
  indicador de cambios es `data_processed` del catálogo. El zip GTFS sí los da
  y responde 304.
- **Ruta nueva o editada**: calcular su mapa enseguida en una tarea en segundo
  plano. Si la app pide el mapa antes, se responde con lo que haya (paradas
  sin trazado) y `"pending": true`.
- Respetar `X-RateLimit-*` (límite observado de 1 000 000 al día: de sobra) y
  mandar un `User-Agent` que identifique a Trajet.

### 8.8 Presupuesto de memoria (`mem_limit 384m`)

El límite es el del servicio `web` en el compose del Umbrel
(`PROMPT-trajet-v2.md:65`); el `docker-compose.yml` de `trajet-server` no fija
ninguno. Medido con `tracemalloc` en este PC:

- Parsear el GeoJSON de la J (230 KB) → pico de **2,1 MB**; con el DP de sus
  23 partes, el pico sigue en 2,1 MB.
- 40 líneas de muestra (2,15 MB de GeoJSON) → **16,8 MB** en memoria (unas 8
  veces el tamaño del fichero). El dataset entero (~100 MB) serían del orden de
  800 MB: **no cabe**; de ahí la regla de pedir línea a línea.
- La línea más larga de la muestra tenía 27 966 puntos: unos 5–8 MB mientras
  se procesa.
- `transfers.txt` (5,5 MB, 191 622 filas) se lee en streaming con
  `csv.reader` y se queda solo con las filas de las zonas de la ruta: memoria
  constante. No cargarlo entero en diccionarios.

Presupuesto propuesto para el módulo: **≤ 20 MB de pico y < 5 MB en reposo**.
Un solo refresco a la vez (`asyncio.Semaphore(1)`), una línea detrás de otra,
y en RAM solo un LRU de las últimas ~20 respuestas del mapa (cada una < 10 KB).
El resto, en SQLite.

### 8.9 Si el portal está caído

- Tiempo de espera de 10 s (5 s de conexión), dos reintentos con espera
  creciente y, tras tres fallos seguidos, no volver a intentarlo en 30 min.
- **Nunca se borra** lo guardado antes de tener el dato nuevo validado (JSON
  válido, al menos un punto, coordenadas dentro de Île-de-France).
- Se sirve lo último guardado con `"stale": true` y la fecha; el panel
  enseña «datos del mapa de hace N días» y el fallo va al registro de errores.
- Ruta nueva sin nada guardado y portal caído: paradas sin trazado, o
  segmento recto si se conocen las coordenadas. Mejora posible en la FASE 1:
  guardar las coordenadas de subida y bajada que ya trae la sección de
  Navitia al guardar la ruta (hoy `app/planner.py:34-41` solo guarda id y
  nombre), para tener siempre al menos la recta.
- Opcional: un «paquete semilla» dentro de la imagen Docker con la red
  ferroviaria entera ya simplificada (`traces-du-reseau-ferre-idf` +
  `emplacement-des-gares-idf`, Licence Ouverte 2.0, sin compartir igual), para
  poder pintar cualquier tramo de tren, RER, metro o tranvía sin red. Tamaño
  no medido (ver sección 7).

### 8.10 Tests con las muestras

`trajet-server/tests/fixtures/idfm/` permite probar sin red:

- recorte de la J Saint-Lazare → Argenteuil con el trazado GTFS
  (`traces-gtfs-ligne-J.geojson.gz` + `arrets-lignes-J.json`): 9,7 km ± 0,1;
- el mismo tramo por el grafo ferroviario
  (`traces-ferre-J-saint-lazare-argenteuil.geojson` +
  `gares-saint-lazare-argenteuil.geojson`): tramos 279, 321, 280, 283, 282 y 281;
  el tramo 550 con `idrefligc='C0173'` debe entrar por `res_com`;
- elección de variante en el bus 272 (`traces-gtfs-bus-272.geojson.gz`);
- DP del recorte: 2 m → 52 puntos (GTFS) o 46 (cadena ferroviaria); 20 m →
  12 puntos en los dos;
- acceso más cercano y distancias de `pathways`
  (`acces-*.geojson`, `relations-acces-*.json`, `gtfs-pathways-*.txt`);
- «cour du Havre» (`accid 50148490`) no debe salir como entrada;
- vías de Saint-Lazare (`arrets-transporteur-vias-saint-lazare.json`);
- detección de cambios con `catalogo-frescura.json`.

---

## 9. Enlaces

- Portal: https://data.iledefrance-mobilites.fr/ · API Explore v2.1 de Opendatasoft: https://help.opendatasoft.com/apis/ods-explore-v2/
- PRIM, catálogo: https://prim.iledefrance-mobilites.fr/fr/catalogue-data · licencias: https://prim.iledefrance-mobilites.fr/fr/licences
- PRIM, identificación de objetos (SIRI): https://prim.iledefrance-mobilites.fr/fr/aide-et-contact/documentation/prise-en-main-des-api/prise-en-main-des-api-prochains-passages/identification-des-objets
- GTFS: https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip · documentación: https://eu.ftp.opendatasoft.com/stif/GTFS/opendata_gtfs.pdf · transport.data.gouv.fr: https://transport.data.gouv.fr/datasets/reseau-urbain-et-interurbain-dile-de-france-mobilites
- Documentación de los referenciales (adjunto de `referentiel-des-lignes`): https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets/referentiel-des-lignes/attachments/2023_idfm_referentiels_pdf
- Fichas de dataset: `https://data.iledefrance-mobilites.fr/explore/dataset/<id>/information/` con `<id>` = `traces-des-lignes-de-transport-en-commun-idfm`, `traces-du-reseau-ferre-idf`, `emplacement-des-gares-idf`, `emplacement-des-gares-idf-data-generalisee`, `referentiel-des-lignes`, `arrets-lignes`, `zones-de-correspondance`, `zones-d-arrets`, `arrets`, `arrets-transporteur`, `relations`, `acces`, `relations-acces`, `poles-d-echange`, `referentiel-arret-tc-idf`, `offre-horaires-tc-gtfs-idfm`, `positionnement-dans-la-rame`, `accessibilite-en-gare`, `traces-des-lignes-regulieres-de-bus-en-ile-de-france`, `etat-des-ascenseurs`, `perimetre-des-donnees-tr-disponibles-plateforme-idfm`.
- Licencias: Licence Ouverte 2.0 https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf · ODbL https://opendatacommons.org/licenses/odbl/1-0/ (versión francesa enlazada por el portal: https://doc.transport.data.gouv.fr/le-point-d-acces-national/cadre-juridique/conditions-dutilisation-des-donnees/licence-odbl) · Licence Mobilités https://cloud.fabmob.io/s/eYWWJBdM3fQiFNm · explicación: https://wiki.lafabriquedesmobilites.fr/wiki/Licence_Mobilit%C3%A9s
