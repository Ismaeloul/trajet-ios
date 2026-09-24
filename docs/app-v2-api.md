# App v2 — API interna del núcleo (contrato para las vistas)

Lo que exporta el núcleo de la app (FASE 3, etapa A, commit `44d354c`). Las
vistas, el modo trayecto y la extensión **usan esto**; no lo dupliquen. Si
algo falta, se añade aquí y en el código a la vez.

## Modelos (Trajet/Shared)

- `Board` (Codable, Hashable, Sendable): `route: BoardRoute?`, `legs: [Leg]`,
  `worstLevel`, `worstLine`, `maxDelay`, `updatedAt`, `dataAge`, `stale`,
  `errors`, `quota: [String: Int]`, `lastError`, `autoSelected`,
  `server: ServerState?`, `disruptionsOK: Bool`, `receivedAt: Date`.
  Métodos: `ageSeconds(now:)`, `isStale(now:)`, `refreshInterval`,
  `remainingCalls`, `hasContent`. Constantes: `staleAfter = 90`,
  `minimumRefresh = 30`.
- `Leg`: lo de siempre + `fromId`, `toId`, `platformExpected: Bool?`;
  `showsPlatform` (= `platformExpected ?? mode.publishesPlatform`),
  `stationFailed`, `mixesDestinations`, `directionLabel`, `mode`.
- `Departure`: `realDelay`, `hasRealPlatform`, `isCancelled`, `date(near:)`,
  `static parisDate(_:near:)`. Siguen `PlatformGuess`, `LegStatus`,
  `TrainLength`, `TransportMode`, `BoardRoute`.
- `enum BoardPayload { case board(Board); case empty(message: String, server: ServerState?) }`.
- `ServerState { primKey: PrimKeyState, quotaLevel: QuotaLevel, refreshHintS: Int, degraded: Bool; refreshInterval; static normal }`.
- Salud: `ServerHealth` (`prim: PrimState`, `quota: QuotaSnapshot`,
  `collector: CollectorStatus`, `platformModel: PlatformAccuracy`,
  `translator: TranslatorStatus`), `QuotaEndpoint` (`label`: Tablero/Avisos/
  Buscador, `remaining`, `usedShare`), `PrimKeySource`.
- Errores: `APIErrorBody { code, message, retryAfter; knownCode; static parse(Data) }`,
  `enum ServerErrorCode` (todos los del contrato + `.unknown`).
- Emparejamiento: `PingResponse` (`isTrajet`),
  `PairRequest(code:deviceName:deviceModel:appVersion:)`,
  `PairResult { token, device, server: Server { name, version, urls; url(_ kind) } }`,
  `DeviceInfo`, `ServerURL { kind: .lan/.tailscale/.other, url }`, `UnpairResult`.
- Mapa: `RouteMap`, `MapLine`, `MapPath`, `MapLegStop`, `MapPoint`,
  `MapStation`, `MapPlatform`, `MapTrack`, `MapAccess`, `MapAccessPath`,
  `MapTransfer` (`lat`/`lon` + `coordinate`); `MapLine.coordinates(fine:)`,
  `RouteMap.line(seq:)`, `station(zdc:)`, `accesses(zdc:)`.
  `Polyline.decode(_:) -> [CLLocationCoordinate2D]`, `encode(_:)`.
- `enum AppLink { pair(URL), route(id:legSeq:departureJID:), alternatives(routeID:), board, settings, serverSettings }`
  con `init?(url:)` y `url` (acepta `ruta` y `route`).
- Rutas: `SavedRoute` (+`createdAt`), `SavedLeg` (+`routeId`),
  `RoutesResponse`, `RouteSaved`, `RouteDeleted`, `RouteDraft(_ route:)` con
  `timeMode: TimeMode`, `StopLine`, `StopResult`, `PlaceResult`.
- Planificador: `PlanSaveRequest.Meta` (`timeMode: TimeMode`),
  `PlanSaveResponse` (+`route`), `AlternativesResponse` (+`age`, `quota`),
  `AlternativeOption` (+`departureTime`/`arrivalTime` «HH:MM»).
- Estadísticas: `PlatformModelResponse` (+`collector`, `routeId`); en
  `StatsV1` `avgDelay`/`maxDelay` pueden ser `nil`.
- Caché: `CachedBoard { board, receivedAt, routeID }`, `BoardCache.load()`,
  `save(_:)`, `clear()`, `load(from:)`, `save(_:to:)`, `fileURL`.
- `Capabilities.appGroupID`, `hasAppGroup`, `appGroupContainer`, `isLite`,
  `isWidgetExtension`, `liveActivitiesAvailable`.
- `TrajetActivityAttributes` = `docs/diseno/sistema.md` §12.4 (`ContentState`,
  `Leg`, `Dep`, `Link`, `Connection`, `EndReason`); `typealias BoardLeg = Leg`
  (dentro del tipo, `Leg`, `Dep` y `Link` son los de la actividad).
- `StopTripIntent` («Parar trayecto») y
  `@MainActor enum TripStopHandler { static var stop; static func run() }`.
- `PreviewData` (solo DEBUG): `board(_:)`, `payload(_:)`,
  `cached(_:receivedSecondsAgo:)` para los 16 `BoardCase`; `emptyPayload`,
  `error(_:)` (9 `ErrorCase`), `health(_:)` (4 `HealthCase`), `routeMap`,
  `routes`, `plan`, `alternatives`, `stats`, `platformModel`, `ping`,
  `pairResult`, `demoCode` (`DEMO-2026`), `pairingLink`, `OddCase`, `catalog`.

## Red (Trajet/App/Net)

- `actor TrajetAPI(config:tokens:session:)`: `ping()`, `ping(baseURL:)`,
  `pair(_:baseURL:)`, `me()`, `unpair()`, `health()`,
  `board(routeID:logHistory:)`, `alternatives(routeID:force:)`, `routes()`,
  `route(id:)`, `createRoute(_:)`, `updateRoute(id:_:)`, `deleteRoute(id:)`,
  `routeFromPlan(_:)`, `routeMap(routeID:)`,
  `routeMap(routeID:etag:) -> ConditionalFetch<RouteMap>`, `searchStops(_:)`,
  `searchPlaces(_:)`, `stopLines(stopID:)`, `stopDirections(stopID:lineID:)`,
  `plan(from:to:when:mode:)`, `stats(days:)`, `platformModel(routeID:)`,
  `clearETags()`. Cumple `protocol BoardFetching`.
- `enum APIError` (`notPaired`, `unauthorized`, `notFound`,
  `server(code:message:status:retryAfter:)`, `network`, `decoding`) +
  `serverCode`, `isNetwork`, `needsPairing`, `retryAfter`, textos en español.
  Una cancelación lanza `CancellationError`.
- `ServerConfig(defaults:)`: `lanURL`, `tailscaleURL`, `serverName`,
  `preferredURL`, `candidates`, `connectedVia`, `remember(_:)`,
  `label(for:)`, `applyPairing(lan:tailscale:name:reachable:)`, `reset()`,
  `clearAll()`, `static normalize(_:)`.
- `enum Keychain` y `TokenStore` (`.keychain`, `.memory(_:)`).

## Stores (Trajet/App/Store)

- `BoardStore`: `board`, `emptyMessage`, `server`, `issue: BoardIssue?`,
  `isLoading`, `hasLoadedOnce`, `pinnedRouteID`, `nextRefreshAt`,
  `lastPlatformEvent: PlatformEvent?`, `retainedLegSeqs`, `isLoopRunning`,
  `receivedAt`, `currentRouteID`, `refreshInterval`, `isShowingOtherRoute`,
  `ageSeconds(now:)`, `isStale(now:)`, `legAge(seq:now:)`, `isRetained(seq:)`,
  `setVisible(_:)`, `setTripMode(_:)`, `setSceneActive(_:)`, `refresh()`,
  `autoRefresh()`, `selectRoute(_:)`, `routesChanged(_:)`, `reset()`.
  `BoardIssue`: `offline`, `noKey`, `keyRejected`, `quotaExhausted`,
  `upstream`, `notPaired`, `other` (con `title`, `message`, `symbol`).
- `RoutesStore`: `routes`, `activeID`, `activeRoute`, `hasLoaded`,
  `lastError`, `load()`, `loadIfNeeded()`, `create`, `update`, `delete`,
  `saveFromPlan`, `route(id:)`, `onChange`.
- `HealthStore`: `health`, `device`, `boardQuota`, `load()`.
- `MapStore`: `map(for:)`, `load(routeID:force:)`, `isLoading`,
  `error(for:)`, `forget`, `clear`.
- `PairingStore`: `phase` (`idle`, `checking`, `pairing`,
  `failed(PairingFailure)`), `isPaired`, `device`, `lastLink`, `failure`,
  `serverName`, `handle(url:)`, `pair(link:)`,
  `pair(code:lanURL:tailscaleURL:)`, `unpair()`, `forgetLocally()`,
  `refreshDevice()`, `dismissFailure()`; `PairingLink.parse(_:)`,
  `normalizeCode(_:)`.
- `AppServices`: `config`, `api`, `board`, `routes`, `health`, `maps`,
  `pairing`, `isDemo`, `pendingLink`, `handle(url:)`, `consumePendingLink()`,
  `live()`, `demo(escenario:)`.
- Demo: `-demo [-demoEscenario X]` (X = un `BoardCase` o `emparejar`,
  `vacio`, `sinConexion`, `sinClave`, `cuotaAgotada`, `revocado`). En la demo,
  la vía de `viaAparece` aparece a los 20 s.

## Obligaciones de las vistas

- `BoardScreen` llama a `board.setVisible(true/false)` (`RootView` ya conecta
  `scenePhase`). `MainTabView` consume `pendingLink`.
- El modo trayecto registra su manejador en `TripStopHandler.stop` y llama a
  `board.setTripMode(_:)`.
- Tramos con la estación caída: salidas conservadas tal cual; la vista los
  atenúa con `isRetained(seq:)` / `legAge(seq:now:)`.
- `Board` ya no tiene `empty`/`message`: `BoardPayload` o
  `BoardStore.emptyMessage`.

## Etapa B (FASE 3): trayecto, widgets y navegación

Lo que añadieron los agentes de la etapa B (informes en
`docs/encargos-fase3/informes-etapaB.md`), integrado y compilado en CI.

- `AppServices` además: `tripSettings: TripSettings` y `trip: TripController`.
  Desemparejar para el trayecto (y su Live Activity).
- `TripController` (`@MainActor @Observable`, Trajet/App/Trip): `state`
  (`TripState { off, askingPermission, active(TripSession), ended(TripEndReason) }`),
  `isActive`, `activeRouteID`, `session`, `currentLegSeq`, `deadline`,
  `usesLocation`, `isAskingPermission`, `endReason`, `endedAt`,
  `monitoredStationIDs`, `canUseGeofences`, `location`; `start(routeID:)`,
  `start(routeID:askLocation:)`, `stop(reason:)`, `acknowledgeEnd()`,
  `requestAlwaysForGeofences()`, `watchableStations() -> [StationOption]`,
  `static link(routeID:) -> URL`. `TripEndReason { arrived, timeLimit, manual, permissionDenied, failed(String) }` con `summary`.
- `TripSettings`: `maxMinutes` (15…240, 90 por defecto), `geofencesEnabled`,
  `watchedStationIDs`, `usesDefaultStations`, `resetWatchedStations()`,
  `static geofenceExplanation`, `static maxMinutesRange`.
- Vistas: `MainTabView`, `BoardScreen`, `MapScreen`,
  `RouteMapView(routeID:style:)` (`RouteMapStyle { header, full }`),
  `TripCard(routeID:walking:hasLicense:onShowLicense:)`.
- Navegación (Views/Common): `AppTab { board, trip, routes, history }`,
  `AppNavigator` (`tab`, `showingSettings`, `alternativesRouteID`,
  `focusLegSeq`, `toasts`, `show(_:)`, `open(_:)`), `ToastCenter`
  (`show(_:symbol:)`, `View.toastHost(_:)`), `HapticTrigger` +
  `.haptic(_:trigger:)`, `MessageStateView`, `DemoServicesPreview` (DEBUG).
  Se leen con `@Environment(AppNavigator.self) private var navigator: AppNavigator?`.
  `BoardPreferences.platformHapticKey` = «Vibrar cuando aparece la vía».
  `SettingsScreen` se presenta como hoja: trae su `NavigationStack` y su «Cerrar».
- Widgets y Live Activity (Trajet/Shared): `ActivityContentBuilder.make(board:receivedAt:routeID:now:)`
  (y con `options:`), `staleDate(for:writtenAt:)`, `alert(previous:current:)`;
  `WidgetRefresher.boardDidChange()` (lo llama `BoardPersistence.disk` al
  guardar) y `refreshFailed(_: WidgetFailure)` (lo llama `BoardStore` con
  «sin conexión» y «servidor sin clave», vía `BoardPersistence.failed`);
  `TrajetWidgetKind.home/.lock`; `DestinationAbbreviator.variants(_:)`,
  `shortest(_:)`, `sharedLevel(_:)`; piezas `GlanceTicket`,
  `GlancePlatformMark`, `ActivityPresentation`,
  `WidgetTimelinePlanner.plan(cached:hasAppGroup:failure:now:)`.
- `TrajetActivityAttributes.ContentState.endedAt: Date?` (solo en el estado
  final): `ActivityContentBuilder.ended(_:reason:at:)`, `endedLinger` (15 min),
  `ActivityPresentation.dismissesAt` y `endedDetail` («se quita sola a las HH:MM»).
- `RootView`: al emparejarse deja ver el «Listo» 1,2 s y funde a las pestañas.
