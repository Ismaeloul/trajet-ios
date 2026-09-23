# Servidor v2 — diseño y contratos internos

Documento de trabajo de la FASE 1. Fija la estructura del código y las
interfaces entre módulos **antes** de repartir el trabajo, para que nadie
invente nada. El contrato HTTP está en `docs/openapi.yaml` (la parte `v1` y
`admin`); aquí va lo de dentro.

Se mantiene el stack: **Python 3.12 + FastAPI + httpx + SQLite**. No hay
razón para cambiarlo: el código actual es bueno, pequeño y está medido contra
la API real. Dependencias nuevas, cada una justificada:

| paquete | para qué | por qué no la biblioteca estándar |
|---|---|---|
| `cryptography` | AES-256-GCM + HKDF para cifrar la clave PRIM en reposo | la estándar no trae ningún cifrado autenticado |
| `segno` | QR en SVG para el panel (sin dependencias, puro Python) | no hay generador de QR en la estándar; hacerlo en el navegador obligaría a un CDN y el panel tiene que ir sin internet |
| `pytest`, `pytest-asyncio`, `jsonschema`, `pyyaml`, `ruff` | tests, contrato y lint (solo desarrollo) | — |

## Estructura

```
app/
  main.py          fábrica de la app: middlewares, routers, ciclo de vida
  config.py        ajustes por entorno (sin cambios de nombre en los existentes)
  db.py            conexión + acceso a datos de siempre (rutas, historial, stats)
  migrations/      migraciones versionadas (PRAGMA user_version)
    __init__.py    runner: migrate(con) aplica las pendientes en orden, en transacción
    m0001_base.py  esquema 0.3.0 tal cual (idempotente sobre una BD de producción)
    m0002_v2.py    tablas nuevas (dispositivos, emparejamiento, cuota, errores, mapa, ajustes)
  prim.py          cliente PRIM: caché con TTL, cuota, clave en caliente, errores tipados
  quota.py         contador de cuota por endpoint y día UTC, persistido; niveles y degradación
  keystore.py      clave PRIM cifrada en /data/secrets, prioridad panel > entorno
  auth.py          emparejamiento, dispositivos, tokens, rate limit, dependencias FastAPI
  logs.py          filtro que tacha secretos + registro de errores recientes
  mapdata.py       datos abiertos de IDFM para el mapa (trazados, paradas, accesos)
  board.py collector.py platform.py planner.py translate.py idfm.py frdate.py   (lógica de siempre)
  api/
    errors.py      sobre de error {"error": {"code", "message"}} y excepciones
    etag.py        ETag débil + 304 en GET JSON
    legacy.py      las rutas /api/* de la 0.3.0, mismo comportamiento
    v1.py          /api/v1/* para el iPhone (token obligatorio salvo /pair y /ping)
    admin.py       /api/admin/* para el panel (detrás del login de Umbrel)
    common.py      lógica compartida entre legacy y v1 (construir tablero, alternativas…)
  panel/           HTML/CSS/JS del panel, sin paso de compilación
tests/
  conftest.py      app con BD temporal y PRIM falso
  fakeprim.py      PRIM falso (httpx.MockTransport) con los escenarios de PreviewData
  fixtures/        respuestas reales de PRIM (sin clave) e IDFM
  real/            pruebas contra la API real (test:real), fuera de la tanda normal
scripts/
  publish.sh       construye y publica la imagen en el registro local del Umbrel
  test-real.sh     lanza tests/real con el tope de 800 llamadas/endpoint/día
```

## Interfaces entre módulos

### migrations
```python
def migrate(con: sqlite3.Connection) -> list[int]   # versiones aplicadas
LATEST: int
```
- `PRAGMA user_version` guarda la versión. Una BD de producción 0.3.0 tiene
  `user_version = 0` y tablas ya creadas: `m0001` es idempotente (CREATE IF
  NOT EXISTS + columnas que falten) y la deja en 1 **sin tocar datos**.
- Antes de migrar una BD con datos se hace copia `trajet.db.bak-v<N>` al lado
  (una por versión, no se pisa).
- Cada migración en su transacción; si falla, rollback y el servidor no
  arranca con un esquema a medias (arranca en modo degradado y lo dice en
  `/api/health`).

### quota
```python
ENDPOINTS = ("stop-monitoring", "general-message", "navitia")
class Quota:
    def __init__(self, cap_per_endpoint: int = 1000): ...
    def can_spend(self, endpoint) -> bool          # False si se llegó al tope local
    def spend(self, endpoint, remaining_reported: int | None) -> None
    def snapshot(self) -> dict                      # por endpoint: used, limit, remaining, level
    def level(self) -> str                          # ok | warn | critical | exhausted
    def refresh_hint(self) -> int                   # 30 / 60 / 120 / 300 s
    def reset_for_new_key(self) -> None             # al cambiar la clave
```
- Día = día UTC (PRIM reinicia a medianoche UTC). Persistido en la tabla
  `quota_usage(day, endpoint, used, remaining_reported, key_id)`.
- Niveles por el peor endpoint: `< 70 %` ok · `< 85 %` warn · `< 95 %`
  critical · resto exhausted. En `exhausted` no se llama a PRIM: se sirve la
  caché con su antigüedad (nunca pantalla vacía).
- El dato de la cabecera `x-ratelimit-remaining-day` manda si es más
  pesimista que el contador local.

### keystore
```python
class KeyStore:
    def __init__(self, data_dir: str, seed: str | None, env_key: str): ...
    def current(self) -> tuple[str, str]      # (clave, origen: "panel" | "env" | "none")
    def info(self) -> dict                    # {configured, source, last4, saved_at, state, state_detail, checked_at}
    def save(self, key: str, state: str) -> None   # cifra y guarda; 0600
    def delete(self) -> None
    def set_state(self, state: str, detail: str = "") -> None
```
- Fichero `/data/secrets/prim-key.json` (carpeta 0700, fichero 0600):
  `{v, kdf: "HKDF-SHA256", salt, nonce, ct, last4, saved_at, state, ...}`.
  AES-256-GCM, clave derivada con HKDF de `TRAJET_SECRET_SEED` (en Umbrel =
  `${APP_SEED}`). Sin semilla: se genera `/data/secrets/master.key` aleatoria
  (0600) y se avisa en el panel de que es la opción menos buena.
- `state`: `valid | invalid | forbidden | quota_exhausted | unreachable | unknown`.
- La clave en claro solo vive en memoria del proceso. Nunca en logs,
  respuestas ni HTML (hay tests que lo comprueban).

### prim
```python
class PrimClient:
    async def set_key(self, key: str) -> None     # en caliente: vacía la caché y reinicia cuota
    async def validate_key(self, key: str) -> dict # prueba mínima SIN tocar la clave en uso
    # los métodos de siempre: stop_monitoring, general_message, places, line_info, lines_at_stop, journeys
class PrimError(Exception):  kind: "no_key"|"invalid"|"forbidden"|"quota"|"unreachable"|"http"
```
- `validate_key` hace **una** llamada barata por API (stop-monitoring de una
  estación fija, general-message y navitia `coverage`), cuenta en la cuota
  y traduce: 401 → clave no válida; 403 → sin permiso para esa API; 429 →
  cuota agotada; 5xx/timeout → PRIM caído.

### auth
```python
PAIR_TTL = 300                        # 5 minutos
def new_pairing(urls: list[str]) -> dict       # {id, code, expires_at, payload}; guarda el hash del código
def redeem(code: str, device_name: str, ip: str) -> dict   # {token, device}; un solo uso
def verify_token(token: str) -> dict | None    # dispositivo; actualiza last_used (como mucho 1 vez/min)
def list_devices() -> list[dict]; def revoke(device_id: int) -> bool; def rename(...)
require_device = Depends(...)                  # 401 {"error": {"code": "unauthorized"}}
```
- Código de un solo uso: 8 caracteres de un alfabeto sin ambigüedades
  (sin 0/O/1/I), mostrado como `ABCD-EFGH`. Se guarda su SHA-256.
- Token: `trj_` + 32 bytes aleatorios (`secrets.token_urlsafe(32)`), 256
  bits. En la BD solo su SHA-256. Comparación con `hmac.compare_digest`.
- Rate limit del canje: 5 intentos/minuto por IP y 20 cada 5 minutos en
  total; al pasarse, 429 con `Retry-After`. Tras 10 fallos seguidos se
  invalidan todos los códigos vivos (hay que generar otro en el panel).
- La IP sale de `X-Forwarded-For` solo si la conexión viene del proxy de
  Umbrel; si no, de la conexión.

### logs
- `RedactingFilter` en el logger raíz: sustituye por `***` la clave PRIM en
  uso (y la de entorno), cualquier `Bearer …`, `trj_…` y códigos de
  emparejamiento.
- `recent_errors(limit=50)` para el panel: WARNING o peor, ya tachados,
  guardados en la tabla `error_log` (se conservan los 500 últimos).

### mapdata
```python
async def route_map(route: dict) -> dict   # {lines: [...], stops: [...], accesses: [...], generated_at, source, license}
```
- Ver `docs/datos-idfm.md`. Descarga bajo demanda por línea y estación,
  simplifica y guarda en SQLite (`map_cache`), refresco semanal. Si el portal
  cae, sirve lo guardado; si no hay nada, devuelve paradas sin trazado.

## Seguridad de un vistazo

| superficie | quién llega | protección |
|---|---|---|
| `/api/v1/*` | el iPhone, por LAN o Tailscale | fuera del login de Umbrel (lista blanca) · token de dispositivo obligatorio (menos `/pair` y `/ping`) |
| `/api/v1/pair` | cualquiera en la red | código de un solo uso de 5 min · rate limit · respuesta idéntica para código malo, caducado o usado |
| `/`, `/panel/*`, `/api/admin/*` | solo yo | login de Umbrel · cabecera `X-Trajet-Panel` y mismo origen en lo que modifica · sin caché |
| `/api/*` (0.3.0) | compatibilidad | detrás del login de Umbrel, igual que el panel |
| red Docker compartida de Umbrel | otras apps | la API del iPhone pide token; el panel además comprueba que la conexión venga del proxy de Umbrel (`TRAJET_ADMIN_PEERS=auto`) |
