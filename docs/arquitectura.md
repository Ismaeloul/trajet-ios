# Arquitectura de Trajet v2

Dos piezas: la **app del iPhone** (la de verdad) y el **servidor en el
Umbrel** (API + panel). Aquí va cómo encajan. El detalle de cada parte está
en `docs/servidor.md` (cómo es hoy), `docs/servidor-v2.md` (cómo es por
dentro la v2), `docs/openapi.yaml` (el contrato) y `docs/diseno/` (el
aspecto).

## 1. Vista general

```mermaid
flowchart LR
  subgraph iPhone
    APP[App Trajet<br/>SwiftUI]
    WID[Widgets]
    LA[Live Activity]
    KC[(Llavero<br/>token)]
    AG[(App Group<br/>último tablero)]
    APP --- KC
    APP --> AG
    WID --> AG
    APP --> LA
  end

  subgraph Umbrel["Umbrel (umbreld 2.0)"]
    GW[app-gateway<br/>login de Umbrel]
    subgraph web["contenedor web (384 MB)"]
      API["/api/v1<br/>token"]
      ADM["/api/admin + panel<br/>/api (0.3.0)"]
      CORE[tablero · rutas · planificador<br/>recolector · previsión de vía<br/>cuota · caché · mapa]
      DB[(SQLite<br/>/data/trajet.db)]
      SEC[(/data/secrets<br/>clave PRIM cifrada)]
    end
    OLL[Ollama<br/>gemma3:4b]
  end

  PRIM[(PRIM · IDFM<br/>tiempo real)]
  ODS[(data.iledefrance-mobilites.fr<br/>datos abiertos)]

  APP -- "LAN 192.168.1.188:7796<br/>o Tailscale 100.99.38.76:7796" --> GW
  GW -- "/api/v1/* (lista blanca,<br/>sin login)" --> API
  GW -- "resto: con login de Umbrel" --> ADM
  API --> CORE
  ADM --> CORE
  CORE --> DB
  CORE --> SEC
  CORE -- "apikey (solo aquí)" --> PRIM
  CORE -- "sin clave" --> ODS
  CORE -- traducción --> OLL
```

- Las direcciones del servidor **no están en el código**: llegan en el QR y
  se guardan en la app; se pueden cambiar en Ajustes.
- La clave PRIM vive solo en el servidor. La app nunca la ve.

## 2. Servidor por dentro

```mermaid
flowchart TB
  subgraph HTTP
    MW[middlewares<br/>gzip · ETag · cabeceras de seguridad<br/>filtro de secretos en logs]
    V1[api/v1.py]
    LEG[api/legacy.py]
    ADMIN[api/admin.py]
    PANEL[panel/ HTML+CSS+JS]
  end
  AUTH[auth.py<br/>emparejamiento · tokens · rate limit<br/>comprobación del proxy]
  COMMON[api/common.py]
  BOARD[board.py]
  PLAN[planner.py]
  ALT[alternativas]
  COL[collector.py<br/>tarea de fondo]
  PLAT[platform.py<br/>previsión de vía]
  TR[translate.py<br/>Ollama en segundo plano]
  MAP[mapdata.py<br/>IDFM open data]
  PRIMC[prim.py<br/>caché con TTL · lock por clave<br/>clave en caliente]
  QUOTA[quota.py<br/>por endpoint y día UTC]
  KS[keystore.py<br/>AES-GCM · HKDF(APP_SEED)]
  LOGS[logs.py<br/>error_log]
  MIG[migrations/]
  DB[(SQLite)]

  MW --> V1 & LEG & ADMIN & PANEL
  V1 --> AUTH
  ADMIN --> AUTH
  V1 & LEG --> COMMON
  COMMON --> BOARD & PLAN & ALT & PLAT & TR & MAP
  BOARD --> PRIMC
  PLAN --> PRIMC
  ALT --> PRIMC
  COL --> PRIMC
  COL --> PLAT
  PRIMC --> QUOTA
  PRIMC --> KS
  ADMIN --> KS & QUOTA & LOGS
  PLAT & TR & MAP & AUTH & QUOTA & LOGS --> DB
  MIG --> DB
```

Reglas de la casa: un solo proceso (la caché, la cuota y el recolector viven
en memoria), SQLite fuera del bucle de eventos, nada de trabajo pesado en la
petición del tablero, y el último dato bueno siempre se conserva.

## 3. Panel y seguridad

```mermaid
flowchart LR
  YO[Tú, en el navegador] -->|"http://umbrel.local:7796/"| GW[app-gateway]
  GW -->|sin sesión| LOGIN[login de Umbrel]
  LOGIN --> GW
  GW -->|"con sesión (cookie de Umbrel,<br/>que el gateway quita antes de pasar)"| P[panel /]
  P -->|"fetch /api/admin/*<br/>X-Trajet-Panel: 1"| A[api/admin.py]
  A -->|"¿viene del gateway?<br/>(TRAJET_ADMIN_PEERS=auto)"| OK{sí}
  OK --> ACC[QR · dispositivos · clave PRIM<br/>cuota · Ollama · recolector · errores]
  OTRA[otra app en la red Docker de Umbrel] -.->|"directo a web:8000"| A
  A -.->|"403"| OTRA
```

| superficie | protección |
|---|---|
| `/api/v1/*` | fuera del login (lista blanca) + token de dispositivo |
| `/api/v1/pair` | código de 5 min de un solo uso + rate limit |
| panel y `/api/admin/*` | login de Umbrel + cabecera anti-CSRF + origen de la conexión |
| `/api/*` (0.3.0) | detrás del login, como el panel |

## 4. Emparejamiento

```mermaid
sequenceDiagram
  autonumber
  actor Yo
  participant Panel as Panel (navegador)
  participant S as Servidor
  participant App as App (iPhone)
  participant KC as Llavero

  Yo->>Panel: «Emparejar un iPhone»
  Panel->>S: POST /api/admin/pairing
  S->>S: código ABCD-EFGH (se guarda su hash, caduca en 5 min)
  S-->>Panel: QR = trajet://pair?v=1&code=…&lan=…&ts=…
  Yo->>App: escanear (o teclear código y direcciones)
  App->>S: GET /api/v1/ping en cada dirección (la que responda)
  App->>S: POST /api/v1/pair {code, device_name}
  alt código bueno
    S->>S: marca el código como usado · token 256 bits (se guarda su hash)
    S-->>App: {token, device, server.urls}
    App->>KC: guarda el token
    Panel->>S: GET /api/admin/pairing/{id} (sondeo)
    S-->>Panel: used + dispositivo → «Emparejado»
  else malo, caducado o usado
    S-->>App: 401 pairing_invalid (misma respuesta en los tres casos)
  else demasiados intentos
    S-->>App: 429 + Retry-After
  end
```

## 5. App del iPhone

```mermaid
flowchart TB
  subgraph Vistas["Vistas (SwiftUI · «Cristal»)"]
    PAIR[Emparejar]
    BOARDV[Tablero]
    MAPV[Mapa]
    ROUTESV[Rutas + editor]
    PLANV[Planificador]
    STATSV[Estadísticas]
    SETV[Ajustes]
  end
  subgraph Estado["Estado (@Observable, MainActor)"]
    BS[BoardStore<br/>bucle 30 s solo mirando o en trayecto]
    RS[RoutesStore]
    TS[TripController<br/>modo trayecto]
    MS[MapStore]
  end
  subgraph Datos["Datos (fuera del MainActor)"]
    API[TrajetAPI actor<br/>dos direcciones · reintento · ETag]
    CACHE[BoardCache<br/>disco / App Group]
    DEC[decodificación tolerante]
    CAP[Capabilities<br/>¿hay App Group y extensiones?]
  end
  LOC[CoreLocation<br/>precisión ~100 m · geocercas]
  ACT[ActivityKit]
  WK[WidgetKit]

  Vistas --> Estado
  BS --> API
  BS --> CACHE
  RS --> API
  MS --> API
  TS --> BS
  TS --> LOC
  TS --> ACT
  API --> DEC
  CACHE --> WK
  CAP -.-> ACT
  CAP -.-> WK
```

- **Lite / full**: la misma app. `Capabilities` mira en tiempo de ejecución
  si hay App Group (y por tanto extensiones útiles). Sin él, no se ofrecen la
  Live Activity ni los widgets y la caché va al contenedor de la app.
- **Nunca se borra la pantalla**: la caché en disco se pinta al arrancar
  (< 1 s) antes de pedir nada.

## 6. Modo trayecto

```mermaid
stateDiagram-v2
  [*] --> Apagado
  Apagado --> PidiendoPermiso: «Empezar trayecto»<br/>(o propuesta aceptada)
  PidiendoPermiso --> Activo: ubicación concedida
  PidiendoPermiso --> ActivoSinGPS: ubicación denegada<br/>(sin llegada automática)
  Activo --> Activo: cada 30 s refresca el tablero<br/>y actualiza la Live Activity
  ActivoSinGPS --> ActivoSinGPS: cada 30 s refresca
  Activo --> Terminado: llegada al destino (GPS)
  Activo --> Terminado: duración máxima (90 min por defecto)
  ActivoSinGPS --> Terminado: duración máxima
  Activo --> Terminado: «Parar» (app o Live Activity)
  ActivoSinGPS --> Terminado: «Parar»
  Terminado --> Apagado: se apaga la ubicación en segundo plano<br/>y la Live Activity enseña «terminado»
```

- Ubicación en segundo plano **solo** mientras dura el trayecto, con
  precisión reducida (~100 m).
- **Geocercas** (monitorización de regiones) en las estaciones habituales:
  al entrar, iOS despierta la app unos segundos, pide el tablero y actualiza
  la Live Activity si hay una. Fuera de eso, el bucle está parado (R7).

## 7. Live Activity y widgets

```mermaid
sequenceDiagram
  participant App
  participant TC as TripController
  participant S as Servidor
  participant AK as ActivityKit
  participant AG as App Group
  participant W as WidgetKit

  App->>TC: empezar trayecto (app en primer plano)
  TC->>AK: Activity.request(estado inicial)
  loop cada 30 s mientras dura
    TC->>S: GET /api/v1/board (log_history=false)
    S-->>TC: tablero
    TC->>AG: guarda el tablero
    TC->>AK: update(ContentState) · la cuenta atrás corre sola (Text(timerInterval:))
    TC->>W: reloadTimelines (con presupuesto)
  end
  Note over AK: «Parar» = App Intent → TC.stop()
  TC->>AK: end(estado final, dismissal)
  W->>AG: lee el último tablero · timeline con entradas por minuto<br/>que siguen bien aunque no se refresque
```

Sin notificaciones push (no hay cuenta de desarrollador de pago): la Live
Activity se empieza en primer plano y se actualiza desde el modo trayecto y
las geocercas. Los widgets leen la caché del App Group; su cuenta atrás y la
antigüedad del dato corren solas con `Text(date, style:)`.

## 8. Despliegue

```mermaid
flowchart LR
  DEV[trajet-server en el Umbrel<br/>(git pull por SSH)] -->|scripts/publish.sh| REG[(registro local del Umbrel<br/>localhost:5000)]
  STORE[umbrel-app-store<br/>ismaeloul-trajet 0.4.0] --> UMB[umbreld]
  REG --> UMB
  UMB --> WEB[contenedor web · usuario 1000 · healthcheck]
  CI[GitHub Actions · trajet-ios] --> IPA1[Trajet-full.ipa<br/>widgets + Live Activity + App Group]
  CI --> IPA2[Trajet-lite.ipa<br/>sin extensiones]
```

El despliegue en el Umbrel lo haces tú (ver `trajet-server/README.md`): en
esta sesión no se publica nada en el registro ni se toca la app instalada.
