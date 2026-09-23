# Decisiones tomadas en modo autónomo

Cada entrada: qué decidí, qué alternativas había y por qué. Las más recientes
al final de cada sección.

---

## FASE 0

### D0.1 · De dónde sale el código del servidor
- **Decisión**: el código de producción es el de `~/trajet` en el NAS (leído
  por SSH con la clave que ya tenía este PC, sin sudo ni Docker y sin tocar
  nada). Se copió sin `.env` ni `data/`.
- **Por qué es el bueno**: el servidor que responde en `192.168.1.188:7796` es
  el stack de `docker compose` de `~/trajet`, no la app `ismaeloul-trajet` del
  store (no está instalada: no existe `~/umbrel/app-data/ismaeloul-trajet`).
  Para comprobarlo sin Docker comparé el `openapi.json` que sirve producción
  con el que genera este código: **idénticos** (rutas, métodos y parámetros).
- **Diferencia encontrada**: la PWA de `app/static` del NAS es **más nueva**
  que la de la imagen desplegada (la desplegada es la oscura de cristal; la
  del NAS, la «hoja clara» del 5 de septiembre, que se subió pero no se llegó
  a reconstruir). No importa: la v2 elimina la PWA.
- **No existe `scripts/publish.sh`** en ningún sitio (ni en este PC ni en el
  NAS). Lo que había es `pasar-al-store.sh`. El `publish.sh` se escribe nuevo
  en la FASE 1.
- **Alternativas descartadas**: `docker cp` desde el contenedor (el usuario
  `umbrel` no está en el grupo `docker` y `sudo` pide contraseña).

### D0.2 · Dónde vive cada repo en local
- `Trajet v2/` es `trajet-ios` (rama `rewrite-v2`, creada desde `design-lab`).
- `Trajet v2/trajet-server/` es el repo `trajet-server`, con su propio `.git`,
  ignorado por `trajet-ios`. Así el encargo funciona tal cual está escrito
  (`./trajet-server`, `trajet-server/.env`) y cada repo va por su lado.
- `Trajet v2/umbrel-app-store/` será un **clon nuevo** del store (ignorado),
  para preparar la 0.4.0 en una rama local sin tocar los otros clones que
  tienes en el PC (alguno tiene cambios sin commitear).
- La documentación de todo el proyecto vive en `trajet-ios/docs/`.

### D0.3 · Primer commit de `trajet-server` en `main`
- El encargo pide que el primer commit sea el estado de producción. Un repo
  nuevo necesita una rama por defecto, así que ese único commit va a `main`
  (junto con un `.gitignore` que protege `.env` y `data/`). **Todo lo demás va
  a `rewrite-v2`**; a `main` no se vuelve a escribir.

### D0.4 · Copia de `trajet.db`
- La copia por SSH (solo lectura) la **denegó** el control de permisos de la
  sesión. No la he forzado. Los tests de migración usan una BD sintética con
  el esquema exacto de la 0.3.0; el test contra la copia real se salta si no
  está. Detalle y comando para hacerla tú en `docs/pendiente.md`.

### D0.5 · CI de iOS: qué hay en el runner
- Probado con un push a `rewrite-v2` (GitHub Actions ya funciona otra vez):
  `macos-latest` = macOS 26.6 con **Xcode 26.6** (SDK iOS **26.5**) y
  simuladores iOS 26.2, 26.4 y 26.5; modelos iPhone SE (3.ª gen.), iPhone 16,
  16 Pro Max, 17… Compila en ~30 s.
- La app actual **no compila** (2 errores en `AlternativesSheet.swift:152` y
  `DepartureChip.swift:64`). No se arreglan: esas vistas se rehacen enteras.

### D0.6 · Login de Umbrel y API del iPhone
- Umbrel (umbreld, módulo `app-gateway`) deja fuera del login las rutas de
  `PROXY_AUTH_WHITELIST`. Reglas de coincidencia (leídas del código fuente de
  `app-gateway.ts`): `"/api/v1/*"` casa con todo lo que empieza por
  `/api/v1/`; la lista negra gana a la blanca; sin sesión, lo no permitido se
  **redirige** (302) al login de Umbrel. El proxy **quita sus cookies** antes
  de pasar la petición y pone `X-Forwarded-For` con la IP real.
- Solución: `PROXY_AUTH_ADD: "true"` + `PROXY_AUTH_WHITELIST: "/api/v1/*"`.
  Panel y API antigua quedan detrás del login; la API del iPhone queda fuera
  pero **exige token** en el propio servidor. Detalle en la FASE 1.
- En tu NAS corre **umbreld 2.0**, con el `app-gateway` dentro del propio
  umbreld (no un contenedor `app_proxy` aparte): las peticiones llegan al
  contenedor desde la puerta de enlace de la red Docker de Umbrel
  (`10.21.0.1`). Eso permite que el panel compruebe, además, que la conexión
  viene del proxy y no de otra app de la red compartida
  (`TRAJET_ADMIN_PEERS=auto`).
- Umbrel da a cada app un secreto estable `APP_SEED` (derivado de la semilla
  del Umbrel); es el que se usará para cifrar la clave de PRIM en reposo.

---

## FASE 1 — Servidor

### D1.1 · Se mantiene Python + FastAPI + SQLite
- El código de la 0.3.0 es bueno, pequeño y está medido contra la API real.
  Cambiar de stack solo añadía riesgo. Dependencias nuevas, justificadas en
  `docs/servidor-v2.md`: `cryptography` (AES-GCM; la estándar no trae
  cifrado autenticado) y `segno` (QR en SVG sin dependencias, para que el
  panel funcione sin internet).

### D1.2 · Contrato primero
- `docs/openapi.yaml` 0.4.0 se congeló antes de repartir el trabajo. Los tests
  del servidor validan cada respuesta de `/api/v1` y `/api/admin` contra él
  (copia en `trajet-server/tests/contract/`). La 0.3.0 se conserva con el
  mismo `openapi.json` que producción (hay un test que lo compara).

### D1.3 · Migraciones
- `PRAGMA user_version`. La migración 1 es el esquema 0.3.0 idempotente, así
  que una BD de producción queda en v1 sin tocar un dato; la 2 solo añade.
  Copia `trajet.db.bak-v<N>` antes de migrar. Si una migración falla, rollback
  y el servidor no arranca con un esquema a medias.
- El acierto de la previsión de vía pasa a contarse **por tren** en una tabla
  nueva (`platform_score_v2`); la vieja se conserva intacta como histórico.

### D1.4 · Seguridad
- `/api/v1/*` fuera del login de Umbrel (lista blanca) pero con token
  obligatorio; panel, `/api/admin` y la API 0.3.0 detrás del login.
- Token `trj_` + 256 bits; en la BD solo su SHA-256; `hmac.compare_digest`.
- `X-Forwarded-For`: se usa el **último** valor, y solo si la conexión viene
  del proxy. El primero lo escribe el cliente y podría falsearlo para
  saltarse el límite de intentos del emparejamiento.
- El panel, además del login de Umbrel, comprueba que la conexión venga del
  proxy (`TRAJET_ADMIN_PEERS=auto`): en la red Docker de Umbrel cualquier otra
  app podría llegar a `web:8000` saltándose el login.
- En el `docker compose` de desarrollo, con `auto`, un navegador de la LAN
  que entre directo por el puerto recibe 403: se relaja con
  `TRAJET_ADMIN_PEERS=any` (solo en local).
- Los códigos de un solo uso anulan el anterior; tras 10 fallos seguidos se
  anulan todos; la respuesta es la misma para código malo, caducado o usado.
- Campos extra en `POST /api/v1/pair` se ignoran (no 400) para que una app
  más nueva pueda emparejar con un servidor más viejo.

### D1.5 · Cuota
- Se cuenta cada respuesta HTTP real por endpoint y día UTC, con la clave en
  uso (cambiar de clave = contador nuevo). Manda lo más pesimista entre el
  contador propio y la cabecera de PRIM.
- Degradación: warn ×2 el TTL, critical ×4, exhausted mínimo 600 s; sin
  cuota, no se llama y se sirve la caché. El refresco sugerido a la app sale
  solo de los endpoints del tablero (que el planificador gaste navitia no
  frena el tablero).
- Un 429 solo marca el día como agotado si la cabecera dice 0; si no, es un
  límite por segundo y se pausa.
- Validar la clave usa `navitia/places?count=1`: `/coverage` no existe en
  PRIM (404, medido con la clave de pruebas).

### D1.6 · Clave PRIM
- Se guarda solo si al menos una API responde 200 y ninguna 401/403.
- `/data/secrets/prim-key.json` (0600, carpeta 0700), AES-256-GCM con clave
  derivada por HKDF de `APP_SEED`. Sin `APP_SEED`, clave maestra local en
  `/data/secrets/master.key` y el panel lo avisa.

### D1.7 · Mapa
- Nunca se descarga un dataset entero: todo con `where`/`select` por línea y
  estación (el de trazados entero no cabría en 384 MB). Pico medido: 3,4 MB.
- Los ficheros del GTFS (`pathways`, `transfers`) se leen por HTTP Range del
  zip, sin bajarlo.
- No hay caminos a pie entre andenes en los datos abiertos: se da el tiempo
  mínimo de transbordo, no un trazado inventado.
