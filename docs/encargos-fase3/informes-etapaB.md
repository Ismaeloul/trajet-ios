# Informes de la etapa B (FASE 3)
Informes finales de los agentes B1 (tablero), B2 (mapa y trayecto) y B4 (widgets y Live Activity), tal cual. Sirven a la integración.

---

## Informe B1: navegación y tablero (reanudación)

Nada compilado. Tampoco hay commit ni push, como pedía el encargo.

### Lo que ya estaba (commits 003cd88 y 1c6e172) y se conserva
Lo leí entero contra el código real del núcleo: los nombres de campos, los inits y los casos de los modelos cuadran, y no encontré nada que no case con la interfaz.
- `Views/Board/`: `BoardViewLogic`, `DepartureTicket` (con `PaceTag`), `DepartureChip` (con `ChipDestinationText` y `DepartureChipStrip`), `PlatformBadge`, `LegCard` (con `LegEmptyBox` y `BoardTitleText`), `LegDetailSheet` (con `BoardTagFlow`), `LineStatusNotice` (con `NoticeMessageText`, `TranslatingLabel` y `DisruptionsUnreadNotice`), `StatusPill` (con `RefreshBar` y `LiveDot`), `AlternativesSheet` (con `BoardAlternativesModel`), `BoardHeader`, `BoardIssueView`, `BoardTripControls` y `EmptyBoardView` (con `BoardSkeleton`).
- `Views/Common/`: `AppNavigator`, `HapticTrigger`, `MessageStateView`, `NavigationZoom` y `Toast`.
- Faltaba: `BoardScreen` y `MainTabView` seguían siendo stubs, y no había tests.

### Lo que he añadido o cambiado
- **`Trajet/App/Views/Board/BoardScreen.swift`**, completo:
  - Mapa de cabecera `RouteMapView(routeID:style: .header)`. Tocarlo empuja el mapa entero con el zoom de iOS 18 (en iOS 17, push normal). Sin ruta, no hay mapa.
  - Cabecera de cristal con el selector de ruta, la píldora y la barra de refresco.
  - Tarjetas que se apagan con el dato viejo (R19), el tramo conservado atenuado, «Empezar/Parar trayecto», «Buscar alternativa» (roja con la línea cortada) y el pie con errores y cuota.
  - Tirar para refrescar con 3 s mínimos entre tirones, y `setVisible` al aparecer y al irse.
  - Hápticas: vía (respeta el ajuste), tren a 2 min y subida de nivel, nunca con el dato viejo. Aviso a VoiceOver cuando sale la vía.
  - Aviso efímero «Esa ruta ya no existe» (R44).
  - Enlaces: baja hasta el tramo pedido y abre la hoja de alternativas.
  - Estados de carga, vacío, sin tramos y error diseñado.
- **`Trajet/App/Views/MainTabView.swift`**, completo: `TabView` del sistema con Tablero, Trayecto, Rutas e Historial y háptica al cambiar. Ajustes como hoja. Consume `pendingLink`. Decide el bucle por pestaña (solo con Tablero o Trayecto delante) y avisa con un toast cuando el trayecto termina solo.
- **Nuevo `Trajet/App/Views/Common/DemoServicesPreview.swift`** (solo DEBUG): da a las vistas previas los servicios de la demo y pide el tablero.
- **`BoardViewLogic.swift`**: añadidos `BoardDimming` (la decisión de apagado, R19), `BoardText.moreErrors`, `alternativesTitle` y `alternativesIsUrgent`.
- **`AppNavigator.swift`**: añadido `AppTab.refreshesBoard`.
- **Vistas previas** de `LegDetailSheet`, `BoardTripControls` y `AlternativesSheet`: antes salían vacías y ahora cargan datos con `DemoServicesPreview`.
- **`.controlSize(.large)`** en los botones de cristal anchos, para llegar a 44 pt en iOS 26 (R52).
- **Nuevo `TrajetTests/BoardViewLogicTests.swift`**: 65 tests.

### Tipos que exporto
- `MainTabView()` y `BoardScreen()`.
- `enum AppTab { board, trip, routes, history }`, con `title`, `symbol` y `refreshesBoard`.
- `@MainActor @Observable final class AppNavigator`:
  - propiedades `tab`, `showingSettings`, `alternativesRouteID: Int?`, `focusLegSeq: Int?` y `let toasts: ToastCenter`;
  - `show(_:)` y `open(_ link: AppLink)`;
  - se lee con `@Environment(AppNavigator.self) private var navigator: AppNavigator?`.
- `@MainActor @Observable final class ToastCenter`:
  - `show(_ text: String, symbol: String? = nil) -> ToastMessage` (resultado descartable), `dismiss(_ id: UUID? = nil)` y `static let duration` (2,4 s);
  - se lee con `@Environment(ToastCenter.self) private var toasts: ToastCenter?`;
  - `View.toastHost(_:)` lo pinta.
- `HapticTrigger` (`mutating func fire()`), que se usa con `.haptic(_:trigger:)`.
- `MessageStateView(symbol:tint:title:message:actions:)`.
- `View.trajetZoomSource(id:in:)` y `View.trajetZoomTransition(sourceID:in:)`.
- `DemoServicesPreview(_ escenario:loadsBoard:content:)`.
- `BoardPreferences.platformHapticKey = "board.platformHaptic"`: B3 debe usar esta clave para el interruptor «Vibrar cuando aparece la vía» (por defecto, sí).
- Componentes:
  - `DepartureTicket(departure:leg:density:isNewPlatform:)`
  - `DepartureChip(departure:leg:density:)` y `DepartureChipStrip(departures:leg:density:)`
  - `PlatformBadge(state:context:isNew:showsPercent:)`
  - `LegCard(leg:density:officialTextColor:retainedAge:stationError:isNewPlatform:onOpen:)`
  - `LineStatusNotice(status:limit:)`
  - `StatusPill(pill:refreshFrom:refreshTo:now:)` y `RefreshBar(from:to:)`
  - `LegDetailSheet(legSeq:)` y `AlternativesSheet(routeID:)`
  - `BoardIssueView(issue:isRetrying:onRetry:onOpenSettings:onRepair:)`
  - `EmptyBoardView(kind:onCreateRoute:)`
  - `BoardTripControls(routeID:)`, con `static func endedText(_:) -> String?`
  - `BoardFooter(board:)`
- Lógica pura: `BoardSpeech`, `BoardText`, `BoardPill`, `BoardNotice`, `BoardLegEmpty`, `BoardChipContent`, `BoardPlatformState`, `BoardContentState`, `BoardIssueCopy`, `BoardDimming`, `BoardRefreshThrottle`, `BoardHapticRules` y `BoardAlternativesText`.

### Reglas cubiertas por tests (`BoardViewLogicTests`, la regla va en el nombre)

| Reglas | Tests |
|---|---|
| R2, R3, R10 (la vía) | `testR3MetroBusTranviaSinHuecoDeVia`, `testR10RealManda_ProbableSoloSinReal`, `testR2SinViaNiPrevisionNoHayHueco`, `testR2ViaNuevaDuranteVeinticincoSegundos`, `testR2PlatformNewDelServidorYNadaConElDatoViejo` |
| R4, R14 (retraso) | `testR4SinHoraTeoricaNoHayRetraso`, `testR14RetrasoCeroNoSePintaYConSigno`, `testR14FichaSinRetrasoCero` |
| R5, R6, R15, R16 (formato y ritmo) | `testR5LongitudDelTren`, `testR6MinutosLargos`, `testR15EnAndenDistintoDeYa`, `testR16RitmoCorroAndoConCalma` |
| R50 (VoiceOver) | los 10 `testR50…` |
| R8, R27, R28 (avisos) | `testR8FrancesMientrasTraduce`, `testR8TraducidoSustituyeAlFrances`, `testR8MedioTraducidoSigueTraduciendo`, `testR27DosMensajesEnLaTarjetaYLosDosIdiomasEnElDetalle`, `testR28ObrasFuturasNoEnciendenElAvisoYSeCuentan` |
| R9, R17, R18, R19 (antigüedad y apagado) | `testR17R18EnDirectoConSuAntiguedad`, `testR19ViejoA90Segundos`, `testR19StaleDelServidorApagaYDataAgeNo`, `testR9SinConexionConservaElTableroYDiceSuEdad`, `testR9ServidorSinClaveDisenado`, `testR9TramoConservadoDiceSuAntiguedad` |
| R24, R25, R26, R47 (tramos y fichas) | `testR24DestinoSoloSiMezcla_TambienEnCompacto`, `testR24UnSoloDestinoNoEsMezcla`, `testR25TramoVacioCortadoVsFinalizado`, `testR26EstacionCaidaNoTumbaElTablero`, `testR26ErroresDeEstacionEnPie`, `testR47DensidadPorTramos`, `testR47R5R10FichaHolgadaYCompacta` |
| R7, R46, R54 (cuota y refresco) | `testR7AhorrandoCuotaDiceSuRitmo`, `testR7NuncaMenosDeTreintaSegundos`, `testR7TironesConTresSegundosDeSeparacion`, `testR7BucleSoloEnTableroYTrayecto`, `testR46CuotaEnPie`, `testR46CuotaAgotadaVuelveAMedianocheUTC`, `testR54BarraDeRefrescoEnTexto` |
| R29, R30, R56 (alternativas) | `testR29BotonDeAlternativasNoPideNada`, `testR29AlternativasSoloAlPedirlas`, `testR30BuscarDeTodasFormasForce`, `testR30FalloDeRedYCancelacion`, `testR30NoUsableSeMarca`, `testR56R6AlternativasEnEspanol` |
| R37, R49, R53, R55 | `testR37RotuloRutaQueTocaFrenteAElegida`, `testR49ExplicaViaProbable`, `testR53EstadosVacioCargaError`, `testR53ErrorDisenadoDiceQueHacer`, `testR55ToastEfimero` |
| Sin regla propia | hápticas (3 tests), enlaces (`testEnlacesAbrenLoQuePiden`), título del tramo y fin de trayecto |

R51 y R52 no tienen test unitario: dependen de la vista. Van por `Motion` y `.hitTarget`, y la comprobación queda para los tests de interfaz.

### Dudas de compilación
- **`TODO-COMPILAR` (el único que queda):** `AttributedString.languageIdentifier = "fr"` en `LineStatusNotice.swift`. Si no compila, se quita esa línea y solo se pierde la voz francesa de VoiceOver.
- **Botones redondos de cristal en iOS 26:** los de Ajustes y Mapa dependen de `.cristalButton(circle:)` de la capa Design. Hay que confirmar que miden 44 pt.
- **Mapa de cabecera:** `.frame(height:)` más `.ignoresSafeArea(edges: .top)` compila seguro, pero el encaje final hay que revisarlo en las capturas.
- **Hojas:** vuelvo a poner `.environment(services)` en su contenido por si no lo heredan.

### Para los demás agentes
- **B3:** `SettingsScreen` se presenta tal cual como hoja, así que debe traer su propio `NavigationStack` y su botón «Cerrar».
- **Bucle del tablero (R7):** lo llevan `MainTabView` (por pestaña) y `BoardScreen` al aparecer e irse. `MapScreen` no debe llamar a `setVisible(false)`; hoy no lo hace.
- **B2 ya añadió** `trip` y `tripSettings` a `AppServices` con los nombres acordados, y lo uso tal cual.

---

Terminé la parte B2: mapa, modo trayecto, geocercas, Live Activity, tests y `docs/rendimiento.md`. Como pedía la etapa, no he compilado ni hecho commit ni push, así que todo está sin probar hasta que el agente de integración compile en CI.

## Qué estaba hecho y qué he añadido

**Ya estaba (commits 003cd88 y 1c6e172), conservado y corregido:** en `Trip/` estaban `TripModels`, `TripController`, `LocationService`, `GeofenceService`, `ActivityController`, `TripSettings` y `TripGeometry`. En `Views/Map/` estaban `RouteMapView` y `WalkingGuide`. Correcciones:
- **`RouteMapView`**: tenía dos cosas que no compilaban. Quité `.mapControls {}` y moví `.annotationTitles` a cada `Annotation`. Además, cambié el nombre a las vistas privadas (`RouteMapStationDot`, `RouteMapTransferTag`, `RouteMapPlatformPin`) para evitar choques de nombres.
- **Permisos**: si iOS no enseña el aviso de «Siempre» (solo lo enseña una vez en la vida de la app), ahora se contesta en 1,5 s en vez de esperar 90 s.
- **Geocercas**: el `CLMonitor` se abre al arrancar si ya había geocercas registradas, y sus eventos se leen fuera del MainActor.
- **Concurrencia**: los cuatro protocolos de servicios del trayecto pasan a ser `Sendable`.
- **Live Activity**: el `staleDate` y el reloj de la cifra cuentan desde la llegada del tablero, igual que `ActivityContentBuilder` de B4. Se conserva el cambio de vía (`platformBefore`) entre escrituras.
- **Ruta del trayecto**: durante el trayecto su ruta queda **siempre fijada** en el tablero, para que el servidor no cambie de ruta a mitad del viaje. Al terminar se vuelve a lo de antes.
- Añadí `deadline` y `usesLocation` al `TripController`. Las estaciones por defecto salen del tramo con menor `seq`.

**Nuevo:**
- `MapScreen.swift` (antes era un stub): barra de cristal con la píldora de ruta (menú, bloqueado durante un trayecto), botón de encuadrar y `MapUserLocationButton`. Aviso discreto si el trazado está en `pending`, si el portal falla (`stale`) o si alguna línea va en recta. Camino a pie y vía en su andén. Enlace a la licencia del mapa.
- `TripCard.swift`: panel de cristal con los minutos a pie, el billete del próximo tren y Empezar/Parar con morph y háptica. Antes de que iOS pida el permiso se enseña una explicación con «Continuar / Sin ubicación / Cancelar».
- `AppServices.swift`: solo `tripSettings` y `trip`.
- `TrajetTests/TripControllerTests.swift` (17 tests) y `TrajetTests/MapLogicTests.swift` (17 tests).
- `docs/rendimiento.md`: cuentas por diseño y cómo medir. Dejo claro que los números reales los mide el usuario.

## Tipos que exporto
- **`TripController`** (`@MainActor @Observable`): `state`, `isActive`, `activeRouteID`, `session`, `currentLegSeq`, `deadline`, `usesLocation`, `isAskingPermission`, `endReason`, `endedAt`, `monitoredStationIDs`, `canUseGeofences`, `location`.
  - Métodos: `start(routeID:) async`, `start(routeID:askLocation:) async`, `stop(reason:) async`, `acknowledgeEnd()`, `requestAlwaysForGeofences() async`, `watchableStations() -> [StationOption]`.
  - Estáticos: `make(board:maps:routes:settings:isDemo:)` y `link(routeID:) -> URL`.
- **Máquina de estados**: `enum TripState { off, askingPermission, active(TripSession), ended(TripEndReason) }` y `enum TripEndReason { arrived, timeLimit, manual, permissionDenied, failed(String) }`, con `summary` para el texto.
- **`TripSettings`**: `maxMinutes` (entre 15 y 240, 90 por defecto), `geofencesEnabled`, `watchedStationIDs`, `usesDefaultStations`, `resetWatchedStations()`, `geofenceExplanation`, `maxMinutesRange`.
- **Vistas**: `RouteMapView(routeID:style:)` con `RouteMapStyle { header, full }`, `MapScreen()` y `TripCard(routeID:walking:hasLicense:onShowLicense:)`.

## Reglas cubiertas
| Regla | Test |
|---|---|
| R7 | `TripControllerTests.testRefrescoEnSegundoPlanoSoloEnTrayecto`. La tabla de reglas proponía la clase `ModoTrayectoTests`; el método se llama igual. |
| R40 | El mismo test y `testEntrarEnGeocercaRefrescaUnaVez` comprueban que se refresca con `logHistory=false`. |
| R3 y R10 | `MapLogicTests.testViaEnElMapa` |
| R19 | `testTarjetaDescuentaMinutosYQuitaElQueSalio` |
| R50 y R56 | `testTextosDeLaTarjeta` |
| Alertas de la Live Activity (decisiones §5.4) | `testAlertasSoloLoQueImporta` |

La máquina de estados tiene sus propios tests: inicio, llegada, tiempo máximo, parada desde la app y desde la Live Activity, permiso denegado, permiso quitado a mitad, avance de tramo y geocercas. Aparte hay tests de llegada por distancia, polilínea según zoom y estaciones vigiladas por defecto.

## Dudas de compilación (`TODO-COMPILAR`)
1. La firma de `CLMonitor.add(_:identifier:assuming:)`, y si `await monitor.events` se puede iterar así.
2. `LocalizedStringResource(stringLiteral:)` con un String que no es literal, en `AlertConfiguration`.
3. `MKPlacemark` / `MKMapItem(placemark:)` están obsoletos en iOS 26 (solo avisos). Si `MKDirections` fuera `@MainActor`, habría que marcar `WalkingGuide.calculate` también.
4. En `AppServices.init` leo `self.board`, `self.maps` y `self.routes` antes de asignar `trip`. Es una clase raíz `final` y debería valer; si el compilador protesta, se crean en variables locales.
5. `.annotationTitles` sobre `Annotation` y el `ForEach` / `if let` de `MapContentBuilder`: API de iOS 17 que no he podido probar.

## Lo que falta o hay que saber
- **`Info.plist`** (no es mío): el texto de «Siempre» dice «fuera de un trayecto no la usa», y las geocercas sí la usan. Hay que corregirlo.
- **`docs/app-v2-api.md`**: no documenta todavía `trip` ni `tripSettings`.
- **Ajustes** (otro agente) tiene que usar `trip.requestAlwaysForGeofences()`, `TripSettings.geofenceExplanation`, `trip.watchableStations()` y `tripSettings.maxMinutes`.
- **Mapa y bucle del tablero**: el `MainTabView` de B1 ya pone `board.setVisible(tab.refreshesBoard)`. Aun así, `MapScreen` refresca por su cuenta solo cuando el bucle del tablero está parado, así que nunca hay dos refrescos a la vez.
- **Fin del trayecto**: B1 enseña un aviso efímero al terminar. La tarjeta añade una nota solo si terminó sola (llegada o tiempo), durante 30 min.
- **Desemparejar** con un trayecto en marcha no lo para (no he tocado `wire()` de `AppServices`).
- **Enlace de la Live Activity**: el `widgetURL` lo pone B4. `TripController.link` genera `trajet://ruta/<id>`; `AppLink` acepta también `route`.

Ficheros (en `C:\Users\Isma\Desktop\Trajet v2\`):
- Trajet\App\Trip\ActivityController.swift
- Trajet\App\Trip\GeofenceService.swift
- Trajet\App\Trip\LocationService.swift
- Trajet\App\Trip\TripController.swift
- Trajet\App\Trip\TripGeometry.swift
- Trajet\App\Trip\TripSettings.swift
- Trajet\App\Trip\TripModels.swift (sin cambios)
- Trajet\App\Views\Map\MapScreen.swift
- Trajet\App\Views\Map\TripCard.swift
- Trajet\App\Views\Map\RouteMapView.swift
- Trajet\App\Views\Map\WalkingGuide.swift
- Trajet\App\Store\AppServices.swift
- TrajetTests\TripControllerTests.swift
- TrajetTests\MapLogicTests.swift
- docs\rendimiento.md

---

Informe B4: widgets y Live Activity. Sin compilar, sin commits y sin push, como se pidió; ha revisado las firmas a mano (sin compilador).

## Qué había hecho la ejecución anterior y qué he añadido

**Ya estaba (commits 003cd88 y 1c6e172), lo he conservado:**
- `ActivityContentBuilder`, `WidgetRefresher` y `DestinationAbbreviator`.
- Las piezas de `Trajet/Shared/Components/`: `ActivityPresentation`, `GlanceModel`, `GlanceNumber`, `GlancePlatformMark`, `GlanceStyle`, `GlanceTicket` y `WidgetTimeline`.
- `TrajetWidgets/GlanceParts.swift`.

**Faltaba, y lo he escrito ahora:**
- Toda la extensión: `TrajetWidgetsBundle.swift` (sustituye al esqueleto), `TrajetTimelineProvider.swift`, `HomeWidget.swift` (pequeño, mediano y grande), `LockWidget.swift` (circular con `Gauge`, rectangular y en línea), `LiveActivity.swift` (pantalla de bloqueo), `LiveActivityIsland.swift` (compacta, mínima, expandida y franja de vía) y `GlancePreviews.swift` (vistas previas, solo DEBUG).
- Los tests: `TrajetTests/ActivityContentBuilderTests.swift`, `DestinationAbbreviatorTests.swift` y `WidgetTimelineTests.swift`.
- La línea en `Trajet/App/Store/BoardStore.swift`: `save: { BoardCache.save($0); WidgetRefresher.boardDidChange() }`.

**Correcciones y añadidos en lo que ya estaba:**
- **Live Activity caducada, sin conexión o sin clave:** si la app se paraba en ese estado, la actividad podía enseñar un tren que ya había salido. Ahora pasa al siguiente de la foto.
- **Recargas de widgets:** si algo cambia antes de los 2 min de separación, la recarga queda pendiente en vez de perderse.
- **Un nivel de abreviatura por widget:** `sharedLevel` elige el mismo nivel para cabecera y filas, con una estimación del ancho del texto. Cada texto sigue teniendo su `ViewThatFits` por si no cabe.
- **Alternativa de cifra que corre sola:** `GlanceCountdown.usesSystemTimer` (apagado por defecto) usa `Text(timerInterval:countsDown:)`, que también vale en iOS 17.
- **La vía que aparece o cambia** entra en el billete con escala y fundido.
- **VoiceOver:** «1 minuto» en singular.
- **Maquetación:** prioridad a los textos que se abrevian dentro de pilas con `Spacer`; si no, recibían solo la mitad del hueco y se abreviaban antes de tiempo.
- He renombrado algunos identificadores que podían chocar al compilar.

## Tipos que exporto

- **`ActivityContentBuilder`**: `make(board:receivedAt:routeID:now:) -> TrajetActivityAttributes.ContentState`. También hay una versión con `options: Options(legSeq:previous:connection:ended:)`, más `ended(_:reason:)`, `staleDate(for:writtenAt:)` y `alert(previous:current:) -> AlertReason?`.
- **`WidgetRefresher`**: `boardDidChange()` (no hace nada en la extensión, en la lite ni sin App Group) y `refreshFailed(_: WidgetFailure)`. Además `WidgetFailure { offline, noKey }` y `TrajetWidgetKind.home` / `.lock`.
- **`DestinationAbbreviator`**: `variants(_:) -> [String]`, `shortest(_:)`, `variant(_:level:)`, `variants(_:from:)` y `sharedLevel(_: [Slot])`.
- **Piezas para la app o la extensión:**
  - `GlanceTicket(moment:meta:via:size:tone:showsShare:timer:)`
  - `GlancePlatformMark(via:size:word:showsShare:tone:onIsland:probableInk:)`: vía real o probable, segura en monocromo.
  - `GlanceNumber`, `GlanceBadge(code:color:size:tone:)`, `GlanceHeroTicket`, `GlanceEmptyTicket`, `GlanceMoment` y `GlanceVia`.
  - `ActivityPresentation(state:isStale:routeID:)`
  - `WidgetTimelinePlanner.plan(cached:hasAppGroup:failure:now:)` y `WidgetSnapshot`.

## Reglas cubiertas y sus tests

| Regla | Tests |
|---|---|
| R2 | `testViaPublicada`, `testViaRealYProbableDelTablero` |
| R3 | `testSinViaEnMetroBusYTranvia`, `testMetroSinViaYDestinosMezclados` |
| R4, R14 | `testRetrasoSoloConHoraTeorica` (en los dos ficheros) |
| R5 | `testTextoDelBillete` |
| R6 | `testMinutosLargos`, `testUnaHoraOMasEsHoraFija` |
| R10 | `testLaProbableSigueProbable`, `testMomentosDeLaCifra` |
| R15 | `testEnAndenNoEsYa`, `testEnAndenSoloConDatoReciente` |
| R17, R18 | `testAntiguedadSiempreALaVista` |
| R19 | `testCaducadaMuestraHoraFija`, `testFalloApuntadoPorLaApp`, `testServidorSinClave` |
| R24 | `testDestinosMezclados` |
| R25 | `testLineaCortada`, `testServicioFinalizado`, `testLineaCortadaYServicioFinalizado` |
| R50 | `testVozUnaFrasePorSalida` |
| R60 | `testSinAppGroupLoDice` |

Hay también tests del abreviado con los ejemplos del laboratorio: los he comparado ejecutando su `abreviar()` con Node y coinciden. Otros cubren el tamaño del estado (menos de 4 KB), las escaleras de caída del texto secundario y de la cabecera, y el ritmo de recargas.

## Dudas de compilación (TODO-COMPILAR)

- **Cierres de `ActivityConfiguration`:** construyo todo dentro del cierre, como la plantilla de Xcode, para no depender de cómo aísla WidgetKit esos cierres en Swift 6.
- **Macros `#Preview` de actividades y widgets:** tienen la forma de las plantillas, pero en Swift 6 podrían dar guerra. Solo son vistas previas de DEBUG: si fallan, se pueden quitar sin tocar nada más.
- **`TimelineProvider`:** los `completion` van sin `@Sendable`, igual que el esqueleto que ya compiló en el CI.
- **Pendientes de probar en el simulador** (decisiones §10): el calado en modo acentuado (`GlanceInk.accentedKnockout`, apagado de momento) y la cifra del sistema (`GlanceCountdown.usesSystemTimer`).

## Lo que falta o queda para la integración

- **Nadie llama todavía a `WidgetRefresher.refreshFailed(.offline / .noKey)`.** Debería hacerlo `BoardStore` en su camino de error, y no es mi fichero. Sin eso, los widgets solo saben «sin clave» si el propio tablero lo dice.
- **«Se quita sola a las 13:05»** necesita un `endedAt` en el `ContentState`, que es del núcleo. De momento dice «se quita sola en unos minutos».
- **La extensión no pide `/api/v1/board`**: no tiene ni el cliente ni el token. Solo lee la caché del App Group.
- **Integración con B2:** ya conserva él la vía anterior (`platformBefore`) y sigue llamando a `make(board:receivedAt:routeID:now:)`, así que las piezas encajan.
- **`docs/app-v2-api.md`** no lo he tocado porque no es de mi parte. La lista de tipos de arriba sirve para añadirla allí.

Todo está en `C:\Users\Isma\Desktop\Trajet v2\`: `TrajetWidgets\`, `Trajet\Shared\Components\`, `Trajet\Shared\Activity\`, `Trajet\Shared\Design\DestinationAbbreviator.swift`, `Trajet\App\Store\BoardStore.swift` y los tres ficheros de `TrajetTests\`.
