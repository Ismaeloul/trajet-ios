# Qué se reutiliza de la app iOS actual

Análisis de `Trajet/` (rama `rewrite-v2`, commit `942ffbe`) para la FASE 3:
qué pasa a la v2 tal cual, qué hay que rehacer y por qué, y qué problemas
tiene el código, empezando por los de compilación. Rutas relativas a
`Trajet/` salvo que se diga otra cosa. Reglas (R…) en `docs/reglas.md`;
funcionalidades (F…) en `docs/inventario-funcional.md`.

---

## 0. Resumen

| Pieza | Veredicto | Motivo corto |
|---|---|---|
| `Model/Decoding.swift` | **tal cual** | la decodificación tolerante (R21) es justo lo que pide la v2 |
| `Model/Board.swift`, `Routes.swift`, `Plan.swift`, `Stats.swift` | **reutilizar con ajustes** | calcados de la API y ya `Sendable`; corregir `TransportMode`, `directionLabel`, añadir `position` |
| `Resources/PreviewData.swift` | **conservar y ampliar** | R13; los 7 JSON validan; pasarlos a ficheros de fixtures compartidos |
| `Design/Format.swift` | **lógica tal cual**, separar el color | `Fmt`, `DepartureMoment`, `Pace` son puros; `Pace.color` depende de la paleta vieja |
| `Design/LineColor.swift` | **`parse` y luminancia sí; `ink` y `LineBadge` no** | el umbral 0,45 no garantiza contraste (R12); el distintivo cambia con «Cristal» |
| `Net/TrajetAPI.swift` | **algoritmo sí, aislamiento no** | el orden de direcciones y el «4xx no salta» valen; decodifica en el `MainActor` y no tiene token |
| `Net/ServerConfig.swift` | **algoritmo sí, almacenamiento no** | la v2 empareja por QR, sin IPs en el código y con token en el Keychain |
| `Store/BoardStore.swift` | **reutilizar con arreglos** | bucle y caché correctos en lo esencial; 5 fallos de lógica (§4) |
| `Store/RoutesStore.swift` | **reutilizar con arreglos** | no enseña el error de carga |
| `Design/Theme.swift`, todas las `Views/`, `TrajetApp.swift` | **rehacer** | estética «Cristal», claro/oscuro, Dynamic Type, nuevas pantallas |
| `Info.plist`, `project.yml`, `.github/workflows/ios.yml` | **rehacer** | ATS, permisos, iOS 17, Swift 6, objetivos de extensiones y tests, dos IPA |

---

## 1. Estado de compilación

### 1.1 Configuración actual

- `project.yml:13` `SWIFT_VERSION: "5.0"` y `:17`
  `SWIFT_STRICT_CONCURRENCY: minimal`: hoy se compila en modo Swift 5 sin
  comprobación estricta. **La v2 pide Swift 6 con concurrencia estricta**
  (encargo 3.1).
- `project.yml:7` y `:14`: objetivo de despliegue **iOS 26.0**. La v2 pide
  **iOS 17+** con extras de iOS 26 tras `if #available`.
- Un solo objetivo (`project.yml:19-40`): sin tests, sin extensiones y sin
  esquema declarado.
- CI (`.github/workflows/ios.yml:43-57`): solo `build` Release para
  `generic/platform=iOS`; ni simulador ni tests.
- Según el encargo, la app **nunca ha llegado a compilar en CI**. La revisión
  de abajo confirma al menos un error que lo impide.

### 1.2 Errores de compilación seguros

**E1 · `Views/Board/DepartureChip.swift:64`**

```swift
if let platform = platformBadge {
```

`platformBadge` (`DepartureChip.swift:152-162`) está declarada como
`@ViewBuilder private var platformBadge: some View`. Su tipo es opaco
(`some View`), no `Optional`, así que el `if let` no compila: *initializer for
conditional binding must have Optional type, not 'some View'*. Es la pieza
central del tablero (el chip de cada salida), así que ni R2 ni R3 se han
ejecutado nunca.

Arreglo mínimo: decidir antes si hay vía que pintar
(`leg.showsPlatform && (departure.hasRealPlatform || departure.guess != nil)`)
y pintar el filete y `platformBadge` dentro de ese `if`; o que la propiedad
devuelva `PlatformBadge?`.

No he encontrado otro error seguro. He revisado a mano cada fichero:
inicializadores por miembros (orden de argumentos de `RouteDraft`,
`RouteDraft.LegDraft`, `PlanSaveRequest.Meta`, `DraftLeg`, y que los
`@State private` con valor inicial no los vuelvan privados), cada `if let`
de las vistas (todos los demás desenvuelven opcionales de verdad), las
expresiones `switch` de una sola expresión, los genéricos de
`TrajetAPI.get/send`, los `ForEach` sobre tuplas, el `@Bindable` local de
`SettingsView.swift:13`, los `#Preview` con `return` explícito y que todo lo
que usa `PreviewData` (solo en DEBUG, y el CI compila Release) esté también
dentro de `#if DEBUG`. Los 7 JSON de `PreviewData` son JSON válidos
(comprobado con un analizador), así que los `try!` de
`PreviewData.swift:14-17` no deberían fallar.

### 1.3 Riesgos probables (comprobar en la primera compilación)

| Id | Dónde | Riesgo | Probabilidad |
|---|---|---|---|
| P1 | `ios.yml:48`, `project.yml:19-40` | `-scheme Trajet` sin esquema declarado en `project.yml`: depende de que `xcodebuild` cree el esquema solo. La v2 necesita de todas formas un esquema explícito con acción de test | media-baja |
| P2 | `ios.yml:18`, `:27` | `macos-latest` más «el Xcode más nuevo» (`sort -V | tail -1`): con despliegue 26 hace falta el SDK de Xcode 26; puede tocar un Xcode beta. Para la v2, fijar la imagen y la versión de Xcode | media |
| P3 | `Views/Board/BoardView.swift:39-42`, `Views/Plan/PlanView.swift:150-164`, `Views/Routes/RouteEditorView.swift:320-334` | En modo Swift 6, los cierres de `Binding(get:set:)` pueden exigirse `@Sendable`; capturan estado de la vista. Se espera que compile (las vistas están aisladas al `MainActor`), pero es lo primero que miraría si falla | baja |
| P4 | `Model/Decoding.swift:29`, `:37` | `static let trajet: JSONDecoder/JSONEncoder` exige que sean `Sendable` en Swift 6. En los SDK actuales lo son (`@unchecked Sendable`); si no, cambiar a una función que cree el decodificador | baja |
| P5 | `Store/BoardStore.swift:31` | `nextRefreshAt` usa `refreshInterval` sin `Self.` en el valor inicial de una propiedad de instancia. Debería resolver como miembro estático; si el compilador protesta, escribir `Self.refreshInterval` o `BoardStore.refreshInterval` | baja |
| P6 | `Views/Board/BoardView.swift:202-205` | Concatenar `Text` con `+` y `foregroundColor` están desaconsejados en los SDK recientes: avisos, no errores. Con despliegue 17 puede que ni avisen. Mejor interpolación y `foregroundStyle` | aviso |

### 1.4 Paso a Swift 6 con concurrencia estricta

El código ya está escrito pensando en el `MainActor`, así que el salto es
barato en compilación y caro en diseño:

1. **Modelos**: todos son `struct`/`enum` `Sendable` (p. ej.
   `Model/Board.swift:8`, `30`, `37`, `94`, `146`, `205`, `239`, `256`).
   Valen tal cual. **Ojo** si la v2 activa `SWIFT_DEFAULT_ACTOR_ISOLATION =
   MainActor` (lo que Xcode 26 pone por defecto en proyectos nuevos; XcodeGen
   no lo pone solo): las conformidades `Decodable` quedarían aisladas al
   `MainActor` y no se podrían usar desde un decodificador en segundo plano.
   Decidirlo en `docs/decisiones.md` y, si se activa, marcar los modelos como
   `nonisolated`.
2. **`TrajetAPI` es `@MainActor`** (`Net/TrajetAPI.swift:28`): la red no
   bloquea (es `async`), pero **decodifica en el hilo principal**
   (`TrajetAPI.swift:210`), en contra del encargo 3.3 («Decodificación y
   cálculo fuera del `MainActor`»). Hay que convertirlo en `actor` o en clase
   `nonisolated` `Sendable` que reciba las direcciones candidatas como valor y
   devuelva cuál respondió, en vez de leer y escribir `ServerConfig` (que es
   `@MainActor`) desde dentro.
3. **Caché en disco** (`Store/BoardStore.swift:113-145`): lectura y escritura
   síncronas en el hilo principal (`:38`, `:81`). Leer al arrancar es lo que da
   el «último tablero en < 1 s» (encargo 3.3), pero la escritura y la
   decodificación deben ir fuera.
4. **`@Observable` + `@MainActor`** (`ServerConfig`, `BoardStore`,
   `RoutesStore`, `AppModel`): correcto en Xcode 16+. Marcar
   `@ObservationIgnored` lo que no se pinta (`BoardStore.loop`, `api`).
   `AppModel` solo tiene `let` y es `@Observable` únicamente para poder ir en
   `@Environment(AppModel.self)`.
5. **Tareas**: `Task { [weak self] in … }` del bucle (`BoardStore.swift:47-53`)
   y los `Task {}` de las vistas heredan el `MainActor`; no dan problemas.
6. **Tests**: los stores son `@MainActor`, así que los XCTest que los usen
   tendrán que ser `@MainActor`.

### 1.5 De iOS 26 a iOS 17

**Nada de lo que usa hoy el código exige más de iOS 17.** Lo más reciente
que aparece y su mínimo:

| API | Mínimo | Dónde |
|---|---|---|
| `@Observable`, `@Bindable`, `@Environment(Tipo.self)`, `.environment(objeto)` | 17 | stores, `SettingsView.swift:13`, `TrajetApp.swift:10` |
| `onChange(of:initial:_:)` con dos parámetros | 17 | `RootView.swift:57-62`, `BoardView.swift:275`, `SettingsView.swift:94-95` |
| `scrollTargetLayout`, `scrollTargetBehavior(.viewAligned)`, `scrollClipDisabled` | 17 | `LegCardView.swift:137-141` |
| animación `.snappy` | 17 | `RootView.swift:87` |
| `ToolbarItemPlacement.topBarLeading/.topBarTrailing` | 17 | hojas y editores |
| `#Preview` | 17 | vistas previas |
| `contentTransition(.numericText())`, `Task.sleep(for:)`, `NavigationStack`, `presentationDetents`, `LabeledContent`, `scrollContentBackground`, `scrollIndicators`, `Font.width`, `View.kerning` | 16 | varios |

Bajar `project.yml:7` y `:14` a 17.0 no debería romper nada del código actual.
Los símbolos SF usados (`train.side.front.car`, `figure.run`,
`dot.radiowaves.up.forward`, `tram.fill.tunnel`…) son de SF Symbols 4 o
anteriores; comprobarlo en el simulador de iOS 17, porque un símbolo que no
existe no rompe la compilación: sale vacío.

Lo que la v2 **sí** va a necesitar detrás de `if #available`:

- **iOS 26**: `glassEffect(_:in:)`, `GlassEffectContainer`,
  `.buttonStyle(.glass)` / `.glassProminent`, `tabBarMinimizeBehavior`,
  `tabViewBottomAccessory`, `ToolbarSpacer`, `backgroundExtensionEffect`,
  `scrollEdgeEffectStyle`. Alternativa con materiales (`.ultraThinMaterial`)
  en 17 y 18 (encargo 3.1).
- **iOS 18**: la API nueva de `TabView` con `Tab`, `MeshGradient`,
  `symbolEffect(.breathe/.wiggle/.rotate)`,
  `navigationTransition(.zoom)` + `matchedTransitionSource` (para «de la
  tarjeta de ruta al detalle», encargo 3.2), `onScrollGeometryChange`,
  `presentationSizing`.
- **Disponible ya en iOS 17** (no necesita `#available`): MapKit para SwiftUI
  (`Map` con `MapPolyline`, `Annotation`, `UserAnnotation`,
  `MapCameraPosition`), `MKDirections`, `CLMonitor`,
  `CLLocationUpdate.liveUpdates()`, `CLBackgroundActivitySession`,
  ActivityKit (16.1) con botones de App Intent (17), `Text(timerInterval:)`
  (16), `sensoryFeedback` (17), `ContentUnavailableView` (17),
  `symbolEffect(.bounce/.pulse)` (17), widgets interactivos y
  `containerBackground(for: .widget)` (17).

Compilar con el SDK de Xcode 26 da el cristal del sistema en barras, hojas y
barras de herramientas estándar en iOS 26. La barra de pestañas actual es
propia (`RootView.swift:74-127`) y no lo recibiría: es un motivo más para
pasar a la `TabView` del sistema.

---

## 2. Reutilizable tal cual o casi

### 2.1 `Model/Decoding.swift` (tal cual)
`get(_:_:)`, `opt(_:)` y `text(_:)` (`Decoding.swift:6-25`) son la base de R21 y
R22; `JSONDecoder.trajet`/`JSONEncoder.trajet` con snake_case (`:27-42`).
Ojo conocido y hoy inofensivo: `convertFromSnakeCase` también convierte las
claves de los diccionarios; las de `quota` («stop-monitoring»…) no llevan
guion bajo y no cambian.

### 2.2 Modelos (con ajustes)
- **`Board.swift`**: reutilizar `Departure` (`id` estable, `realDelay`,
  `hasRealPlatform`), `LegStatus` (`visibleMessages`, `awaitingTranslation`),
  `Leg.mixesDestinations`, `Board.ageSeconds/isStale`, y la codificación a mano
  que deja `receivedAt` fuera (`:305-324`). Ajustes:
  - `TransportMode` (`:204-237`): un solo criterio de «modo con vía» acordado
    con el servidor (hoy lista blanca aquí, lista negra en
    `trajet-server/app/collector.py:53`, otra regla en el laboratorio) y sin
    `contains("ter")` a secas (R3).
  - `directionLabel` (`:190-195`): no usar `to_name` como si fuera un sentido
    (F14).
- **`Routes.swift`**: tal cual; añadir `position` a `RouteDraft`
  (`:136-162`) para que editar no la ponga a 0 (`db.py:216`).
- **`Plan.swift`, `Stats.swift`**: tal cual. `PlanOption`/`PlanLeg` son
  `Codable` en los dos sentidos porque la opción vuelve al servidor intacta
  (`Plan.swift:5-6`): mantenerlo.
- Nuevos modelos que harán falta: emparejamiento (QR, token), geometría para
  el mapa, estado «servidor sin clave PRIM», modo trayecto.

### 2.3 `Resources/PreviewData.swift` (conservar y ampliar)
Todos los casos de R13 están (inventario F77). Propuesta: sacar los JSON a
ficheros (`Fixtures/*.json`) que lean a la vez las vistas previas (DEBUG), los
XCTest, los XCUITest (tablero con datos de prueba por argumento de arranque) y
los mocks de PRIM del servidor (encargo 1.7), para que haya **una sola** fuente
de casos. Ampliar con F78 y F79.

### 2.4 `Design/Format.swift` (lógica tal cual)
`Fmt` (`:5-44`), `Pace` (`:50-84`) y `DepartureMoment` (`:91-141`) son
funciones puras y testeables (R6, R14–R18). Separar `Pace.color` (`:69-75`),
que depende de la paleta vieja, y corregir el VoiceOver «1 horas»
(`:137-138`).

### 2.5 `Design/LineColor.swift` (en parte)
`parse` y `components` (`:11-14`, `35-45`) y la luminancia W3C (`:47-53`) valen.
`ink(on:)` (`:23-26`) hay que cambiarlo: elegir la tinta con **más contraste**
(negro si la luminancia > ≈ 0,179) y testearlo con todos los colores de IDFM
(R12). `LineBadge` (`:60-88`) se rediseña con «Cristal», pero conviene
conservar el ajuste de cuerpo según la longitud del código (`:65-71`).

### 2.6 Red (`Net/`): el algoritmo sí
De `TrajetAPI.perform` (`TrajetAPI.swift:179-224`) se conserva: probar las
candidatas en orden, recordar la que responde, no saltar con 4xx/5xx, leer
el `detail` de FastAPI (`:226-230`), timeouts de 6 y 12 s (`:36-43`). De
`ServerConfig` (`ServerConfig.swift:50-72`): `candidates`, `remember`,
`label(for:)`. Hay que rehacer: aislamiento (§1.4), cabecera con el token de
dispositivo, rutas `/api/v1/`, ETag/304 (encargo 3.3), tratar la cancelación
como cancelación, usar `isNotFound` (R44), estado «sin clave PRIM», y el
almacenamiento: direcciones desde el QR, sin valores por defecto en el código
(`ServerConfig.swift:18-21`), token en el Keychain.

### 2.7 Stores (con arreglos)
`BoardStore`: el bucle idempotente (`:45-65`), `nextRefreshAt` para la barra
(`:29-31`), «un fallo no borra» (`:71-86`) y `BoardCache` (`:108-145`) son la
base de R7, R9 y R20. Arreglos en §4. En la IPA `full`, la caché tiene que ir
al contenedor del App Group para que la lean los widgets. `RoutesStore`: vale;
enseñar `lastError` y no marcar `hasLoadedOnce` si la carga falla.

### 2.8 Lógica que hoy vive en las vistas y conviene sacar
Aunque las vistas se rehacen, esta lógica está bien y es testeable si se saca
a funciones o modelos de vista:
- `DepartureChip.secondaryText` (`:130-145`) y `spokenLabel` (`:166-185`).
- `ChipDensity` (`DepartureChip.swift:8-44`).
- Construcción del `RouteDraft` en `RouteEditorView.save` (`:235-253`).
- Flujo de tres pasos de `LegBuilderView` y su alternativa cuando falla
  `/lines` (`:161-170`).
- Flujo de «guardado con aviso» de `SavePlanView` (`PlaceSearchView.swift:228-241`).
- `AlternativeCard.hhmm` (`AlternativesSheet.swift:200-206`) y
  `StatsView.decimal` (`StatsView.swift:197-199`).

---

## 3. Qué hay que rehacer y por qué

| Pieza | Por qué |
|---|---|
| Todas las vistas (`Views/`) | estética «Cristal» obligatoria («sin restos de la estética anterior»); modo claro y oscuro; Dynamic Type (hoy todo es `.system(size:)`); pantallas nuevas: emparejamiento, mapa, modo trayecto, ajustes ampliados |
| `Design/Theme.swift` | tokens OKLCH con equivalente SwiftUI para claro y oscuro; escalas que respeten Dynamic Type; `minimumHitTarget` (`:64-67`) ni siquiera se usa |
| `TrajetApp.swift` | quitar el oscuro forzado (`:11-12`); primera pantalla de emparejamiento; deep links desde la Live Activity y los widgets |
| Barra de pestañas propia (`RootView.swift:74-127`) | no recibe el cristal del sistema ni sus comportamientos de iOS 26 |
| `Info.plist` | fuera `NSAllowsArbitraryLoads` (`:48-49`); excepciones solo LAN y Tailscale; textos de cámara y ubicación; `UIBackgroundModes: location`; `NSSupportsLiveActivities` (IPA `full`) |
| `project.yml` | iOS 17, Swift 6, objetivos de widgets/Live Activity y de tests, esquemas explícitos, configuraciones `full`/`lite`, App Group solo en `full` |
| `.github/workflows/ios.yml` | tests, capturas en simulador, dos IPA, adjuntarlas a las Releases de los tags `v*`; fijar la imagen de macOS y la versión de Xcode |

---

## 4. Problemas de lógica detectados

Además del error de compilación. Todos se ven en el código; ninguno se ha
podido observar en un iPhone.

| # | Problema | Dónde | Qué hacer en la v2 |
|---|---|---|---|
| L1 | Elegir ruta vacía el tablero: si la petición falla, «No se llega al servidor» aunque haya uno guardado | `Store/BoardStore.swift:92` | conservar el tablero anterior (atenuado) hasta que llegue el nuevo (R9) |
| L2 | El refresco de «elegir ruta» corre en paralelo con el del bucle; gana la respuesta más lenta, que puede ser de la ruta anterior | `BoardStore.swift:45-54`, `89-94` | un solo refresco en vuelo, o descartar respuestas de una ruta que ya no es la pedida |
| L3 | Parar el bucle con una petición en vuelo: la cancelación se trata como fallo de red, salta a la otra dirección y deja «sin conexión» | `Net/TrajetAPI.swift:214-219`; `BoardStore.swift:82-85` | detectar `CancellationError`/`URLError.cancelled` y no tocar `lastError` |
| L4 | Los refrescos automáticos no mandan `log_history=false` | `BoardStore.swift:78` frente a `TrajetAPI.swift:48-54` | mandarlo en el bucle; `true` solo en aperturas y refrescos manuales (R40) |
| L5 | Ruta fijada que se borra: 404 cada 30 s y «sin conexión» | `BoardStore.swift:100-103`; `TrajetAPI.swift:19-23` sin usar | ante `isNotFound`, soltar la fijación y volver a la automática (R44) |
| L6 | Cualquier error pone «sin conexión», también 4xx/5xx con el servidor respondiendo | `BoardView.swift:232-243` | distinguir «sin red», «servidor con error» y «sin clave PRIM» |
| L7 | Volver a primer plano o a la pestaña Tablero refresca siempre, sin mínimo | `RootView.swift:65-71`; `BoardStore.swift:45-54` | no refrescar si el último dato tiene < 30 s (cuota, R7) |
| L8 | Error al cargar rutas invisible: sale «Aún no hay ninguna ruta» y no se reintenta | `Store/RoutesStore.swift:23-35`; `Views/Routes/RoutesView.swift:17` | enseñar el error y no dar la carga por hecha |
| L9 | Ruta con 0 tramos se pinta como «No se llega al servidor» | `BoardView.swift:49-59` | estado propio «esta ruta no tiene tramos» |
| L10 | `directionLabel` usa la parada de bajada como sentido y tapa «todos los sentidos» | `Model/Board.swift:190-195`; `LegCardView.swift:79-90` | usar solo `directions` |
| L11 | La nota de obras futuras solo se ve si la línea ya está perturbada | `LegDetailSheet.swift:18-20`, `95-100` | enseñarla también con nivel 0 (R28) |
| L12 | Duraciones de planes y alternativas sin formato «1h46» | `AlternativesSheet.swift:136`; `PlanView.swift:227` | usar `Fmt.minutes` (R6) |
| L13 | «Guardar» con aviso de tramos sin sentido: no avisa al tablero y deja pulsar otra vez (ruta duplicada) | `Views/Plan/PlaceSearchView.swift:228-241` | tras guardar, cambiar el botón a «Hecho» e invalidar el tablero |
| L14 | Editar una dirección en Ajustes no olvida la preferida antigua | `Net/ServerConfig.swift:61-65`; `SettingsView.swift:94-95` | limpiar `preferred` si ya no es ninguna de las dos |
| L15 | No se valida el formato de las direcciones (sin `http://` la petición falla en silencio y salta) | `TrajetAPI.swift:187-189` | validar al escribir y al escanear |
| L16 | `position` se pierde al editar (el servidor la pone a 0) | `Model/Routes.swift:136-162`; `trajet-server/app/db.py:216` | mandar la `position` actual |
| L17 | El contraste del distintivo no está garantizado | `Design/LineColor.swift:23-26` | ver R12 |
| L18 | Tres criterios distintos de «modo con vía» | `Model/Board.swift:208-226`; `trajet-server/app/collector.py:53`; `design-lab/shared/core.js` | uno solo, en el contrato OpenAPI o en una tabla compartida (R3) |
| L19 | El esqueleto parpadea con «Reducir movimiento» activado | `BoardView.swift:311-313` | respetar la preferencia (R51) |
| L20 | «Con problemas» no sale nunca (el servidor siempre manda `ok: true`); `key_configured` no se enseña | `SettingsView.swift:45-46`; `trajet-server/app/main.py:51` | estado real de salud y «servidor sin clave PRIM» (encargo 1.5.1) |
| L21 | El texto de ayuda de «Salgo a» no coincide con la franja real (+30 min tras llegar) | `RouteEditorView.swift:150`; `trajet-server/app/board.py:120` | calcular el texto con la misma fórmula (R38) |
| L22 | El rótulo de resultados del planificador usa el criterio y la hora actuales, no los de la búsqueda | `Views/Plan/PlanView.swift:57-59` | guardar los parámetros de la búsqueda con los resultados |
| L23 | VoiceOver «en 1 horas y 46 minutos» | `Design/Format.swift:137-138` | concordancia y «1 hora» |

Código muerto o sobrante (limpiar al reutilizar): `TrajetError.isNotFound`
sin usar (`TrajetAPI.swift:19-23`); `lastTransportError` que se guarda y se
tira (`TrajetAPI.swift:184`, `217`, `222`); `LineColor.wash`
(`LineColor.swift:28-31`) y `View.minimumHitTarget` (`Theme.swift:62-67`) sin
usar; `import SwiftUI` innecesario en `BoardStore.swift:3`; el `#Preview` de
`LineColor.swift:90-101` es el único fuera de `#if DEBUG`.

---

## 5. Lo que hay que llevarse sí o sí a la v2

Checklist rápido para la FASE 3, en orden de riesgo:

1. Corregir E1 antes que nada y tener una compilación verde en CI con
   simulador y tests.
2. Bajar el despliegue a iOS 17, subir a Swift 6 y decidir el aislamiento por
   defecto (§1.4).
3. Sacar la red y la decodificación del `MainActor` sin perder el algoritmo de
   las dos direcciones (R42, R43).
4. Llevar `PreviewData` a fixtures compartidos y cubrir F77–F79.
5. Arreglar L1–L5 (tocan R9, R40 y R44) antes de construir el modo trayecto
   encima del bucle.
6. Contraste de distintivos con test sobre todos los colores de IDFM (R12).
