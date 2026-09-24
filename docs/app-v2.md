# App iOS v2 — diseño técnico

Documento de trabajo de la FASE 3: fija la estructura, los targets y las
interfaces **antes** de repartir el trabajo entre agentes. El aspecto está en
`docs/diseno/` (sistema «Cristal» y decisiones de Live Activity y widgets);
el contrato con el servidor, en `docs/openapi.yaml` (`/api/v1`).

## Principios

- **SwiftUI, iOS 17 mínimo**, extras de iOS 26 tras `if #available(iOS 26.0, *)`
  (Liquid Glass). **Swift 6 con concurrencia estricta** (`SWIFT_VERSION 6.0`,
  `SWIFT_STRICT_CONCURRENCY complete`), aislamiento por defecto clásico (no
  `MainActor` por defecto): estado de UI en `@MainActor @Observable`, red y
  decodificación en un `actor`, modelos `Sendable`.
- **Sin dependencias externas.** XcodeGen (`project.yml`); el `.xcodeproj` no se
  versiona.
- **No hay Mac**: todo se compila y se prueba en GitHub Actions
  (`macos-latest`: Xcode 26.6, SDK iOS 26.5, simuladores iOS 26.x). Código
  conservador: si hay duda con una API, la alternativa segura.
- Bundle id `com.ismaeloul.trajet` **siempre** (full y lite).
- Reglas: `docs/reglas.md` (R1–R62 de la app) y las notas de
  `docs/decisiones.md` («Notas que la FASE 3 tiene que respetar»).

## Targets

| target | tipo | fuentes | notas |
|---|---|---|---|
| `Trajet` | app (IPA **full**) | `Trajet/Shared`, `Trajet/App` | embebe `TrajetWidgets`; entitlement App Group `group.com.ismaeloul.trajet`; `NSSupportsLiveActivities` |
| `TrajetLite` | app (IPA **lite**) | las mismas | sin extensión ni App Group; condición de compilación `TRAJET_LITE`; mismo bundle id |
| `TrajetWidgets` | extensión WidgetKit | `Trajet/Shared`, `TrajetWidgets` | widgets de inicio y bloqueo + Live Activity (`ActivityConfiguration`) |
| `TrajetTests` | XCTest | — | `@testable import Trajet` |
| `TrajetUITests` | XCUITest | — | flujos y capturas automáticas |

El código compartido se **compila dos veces** (app y extensión) en vez de ir
en un framework: menos piezas que firmar al instalar con un Apple ID gratuito
o con Signulous.

## Carpetas

```
Trajet/
  Shared/                 (app + extensión)
    Model/                Board, Routes, Plan, Stats, Health, RouteMap, Pairing… (Codable tolerante)
    Design/               tokens «Cristal», tipografía, cristal, colores de línea, Format
    Components/           billete de minutos, distintivo de línea, vía real/probable… (los usa también la extensión)
    Cache/                BoardCache (disco; App Group si existe)
    Activity/             TrajetActivityAttributes (+ ContentState), StopTripIntent
    Capabilities.swift    ¿hay App Group? ¿extensiones? (en tiempo de ejecución)
  App/
    TrajetApp.swift, RootView.swift, Info.plist, Trajet.entitlements
    Net/                  TrajetAPI (actor), ServerConfig, Keychain, errores con código
    Store/                BoardStore, RoutesStore, MapStore, HealthStore
    Trip/                 TripController (máquina de estados), LocationService, Geofences, ActivityController
    Pairing/              escáner QR (AVFoundation), entrada manual
    Views/                Board/, Map/, Routes/, Plan/, Stats/, Settings/, Common/
    Demo/                 servidor falso en proceso (URLProtocol) para capturas y UI tests
  Resources/              Assets.xcassets (icono nuevo: claro, oscuro, tintado), PreviewData
TrajetWidgets/            TrajetWidgetsBundle, widgets, LiveActivity, Info.plist, entitlements
TrajetTests/              …
TrajetUITests/            …
```

## Red y emparejamiento

- `TrajetAPI` es un `actor`: prueba las direcciones del emparejamiento en orden
  (LAN y Tailscale), recuerda la que responde, manda `Authorization: Bearer`
  (token en el **Llavero**), guarda los `ETag` y reenvía `If-None-Match`,
  decodifica fuera del `MainActor` y traduce los errores `ErrorV1` a un enum
  con los códigos del contrato (`prim_key_missing`, `unauthorized`…).
- Timeouts cortos (R43). Un error HTTP no salta a la otra dirección; un fallo
  de red sí (R42).
- QR: `trajet://pair?v=1&code=…&lan=…&ts=…&name=…` (esquema de URL propio: la
  cámara del sistema también abre la app).
- **ATS**: `NSAllowsLocalNetworking` + `NSExceptionDomains` con `100.64.0.0/10`
  y `ts.net` (HTTP permitido). Nada de `NSAllowsArbitraryLoads`. Textos de
  permisos en español: red local, cámara, ubicación («cuando se usa» y
  «siempre» para el modo trayecto).

## Tablero y bucle

- `BoardStore` pinta la caché de disco al arrancar (< 1 s) y refresca cada
  `max(30, server.refresh_hint_s)` s **solo** con la pantalla delante o en
  modo trayecto (R7). Refrescos automáticos con `log_history=false` (R40).
- Nunca se borra la pantalla (R9): un error deja el último tablero y su
  antigüedad; un tramo con error y sin salidas conserva sus últimas salidas
  buenas; errores con código → estado diseñado (servidor sin clave, cuota…).
- Apagado del tablero (R19): `stale` del servidor o > 90 s sin tablero nuevo.

## Modo trayecto

`TripController` (máquina de estados, probada con tests): `apagado →
pidiendoPermiso → activo(conGPS/sinGPS) → terminado`. Ubicación en segundo
plano con `desiredAccuracy = kCLLocationAccuracyHundredMeters`,
`allowsBackgroundLocationUpdates` solo mientras dura; llegada por GPS al
destino; tope configurable (90 min por defecto); parar desde la app o la
Live Activity (App Intent). Geocercas en las estaciones habituales
(coordenadas del mapa) con `CLMonitor` (iOS 17) para despertar la app y
refrescar la Live Activity.

## Live Activity y widgets

Según `docs/diseno/decisiones-la-widgets.md`. Sin push: la actividad se
empieza con la app delante y se actualiza desde el modo trayecto y las
geocercas. Los widgets leen la caché del App Group y usan
`Text(date, style: .timer/.relative)` para que la cuenta atrás y la
antigüedad corran solas. En la IPA lite no existen; en la full, si no hay App
Group en tiempo de ejecución, la app no los ofrece.

## Pruebas y capturas

- XCTest con `URLProtocol` falso: modelos (todos los `PreviewData`), formato,
  reglas de vía, ruta que toca, máquina de estados del trayecto, caché, cliente
  con dos direcciones y fallos de red.
- XCUITest con el servidor falso en proceso (`-demo`): emparejar con código,
  tablero, empezar y parar trayecto, mapa, alternativa.
- Capturas automáticas en iPhone SE (3.ª), iPhone 16 y 16 Pro Max, claro y
  oscuro y letra grande, como artefacto del CI.
