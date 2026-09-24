# Reglas de Trajet

Fuente única de las reglas que la v2 no puede romper. Cada regla tiene un id
estable (**R1…**) que no se reutiliza ni se renumera aunque una regla se
retire. Los verificadores revisan el código contra esta lista punto por punto
y en la FASE 5 se rellena la columna «Test que la cubre».

- **R1–R13**: las 13 reglas no negociables del encargo
  (`PROMPT-trajet-v2.md`, sección 2), copiadas literalmente.
- **R14 en adelante**: reglas adicionales sacadas del `README.md`, del código
  y de los comentarios de la app iOS actual (rama `rewrite-v2`, commit
  `942ffbe`). Cada una cita `fichero:línea`.
- Al final: reglas de la v1 que el encargo cambia, decisiones de aspecto que
  **no** son reglas y un hueco para las reglas del servidor.

Convenciones de la tabla:

- **Capa**: `iOS`, `servidor` o `ambas`.
- **Test propuesto**: `Clase.testNombre` es XCTest/XCUITest de la app;
  `test_nombre` es pytest del servidor; «manual» remite a
  `docs/pruebas-iphone.md` (se escribe en la FASE 3).
- Las rutas de fichero sin prefijo son relativas a `Trajet/`. Las del
  servidor llevan `trajet-server/app/`.
- Aviso importante para quien verifique: la app v1 **nunca ha llegado a
  compilar** (ver `docs/ios-reutilizable.md`). Lo que aquí se describe como
  «estado en la v1» es lo que dice el código fuente, no algo observado en un
  iPhone.

---

## Tabla maestra

| ID | Regla (enunciado corto) | Capa | Test propuesto | Test que la cubre |
|---|---|---|---|---|
| R1 | Uso real: mirar de reojo si llego, de pie, una mano, 2–3 s, a contraluz | iOS | `SnapshotTests.testJerarquiaMinutosPrimero` · `AccesibilidadUITests.testContrasteMinutosYVia` · manual «contraluz» | pendiente (fase 5) |
| R2 | La vía solo en el 17 %; nunca columna fija; cuando aparece, caja llamativa y latido | ambas | `PlatformBadgeTests.testViaNuevaDestacadaYLatido` · `DepartureChipTests.testSinViaNoHayHueco` · `test_board_platform_new_al_aparecer` | pendiente (fase 5) |
| R3 | Metro, bus y tranvía no publican vía: sin hueco reservado | ambas | `TransportModeTests.testModosSinVia` · `DepartureChipTests.testMetroBusTranviaSinHuecoDeVia` · `test_board_sin_via_metro` | pendiente (fase 5) |
| R4 | 26 de 36 líneas sin hora teórica: en metro y bus no hay retraso y no se inventa | ambas | `DepartureTests.testSinHoraTeoricaNoHayRetraso` · `test_extract_departures_sin_aimed_delay_null` | pendiente (fase 5) |
| R5 | No hay ocupación; sí longitud del tren (corto/largo), y se enseña | ambas | `DepartureChipTests.testLongitudDelTren` · `ModelTests.testNoHayCampoDeOcupacion` · `test_train_length_short_long` | pendiente (fase 5) |
| R6 | Minutos largos formateados: 106 → «1h46» | iOS | `FormatTests.testMinutosLargos1h46` | pendiente (fase 5) |
| R7 | Cuota 1000/día: refresco de 30 s solo mirando o en modo trayecto; si no, en segundo plano el bucle se para | iOS | `BoardStoreTests.testBucleSoloEnPrimerPlanoYTablero` · `ModoTrayectoTests.testRefrescoEnSegundoPlanoSoloEnTrayecto` | pendiente (fase 5) |
| R8 | Avisos en francés con «traduciendo»; se sustituyen al llegar la traducción; nunca se espera | ambas | `LegStatusTests.testFrancesMientrasTraduce` · `DisruptionNoticeTests.testEtiquetaTraduciendo` · `test_board_no_espera_traduccion` | pendiente (fase 5) |
| R9 | Nunca se borra la pantalla: último tablero bueno con su antigüedad, guardado en disco | iOS | `BoardStoreTests.testErrorConservaTablero` · `BoardCacheTests.testPrimeraAperturaEnseñaCache` · `BoardStoreTests.testCambioDeRutaNoVaciaPantalla` | pendiente (fase 5) |
| R10 | Vía probable ≠ real: caja sólida «Vía» frente a recuadro punteado «probable» | iOS | `PlatformBadgeTests.testRealSolidaProbablePunteada` · `SnapshotTests.testViaRealYProbableEnGris` | pendiente (fase 5) |
| R11 | El acierto de la previsión sale solo de `/api/platform-model`; nunca se pregunta al usuario | ambas | `StatsTests.testAciertoSoloDePlatformModel` · `UITests.testNingunaPreguntaDeAcierto` · `test_platform_model_accuracy` | pendiente (fase 5) |
| R12 | Colores de línea de `line_color`; únicos saturados con los estados; contraste garantizado en distintivos | ambas | `LineColorTests.testContrasteAAEnDistintivos` · `LineColorTests.testTodasLasLineasIDFM` · `test_line_color_hex_6` | pendiente (fase 5) |
| R13 | `PreviewData` son bancos de prueba: conservar y ampliar los 8 casos | ambas | `DecodingTests.testTodosLosPreviewData` · `PreviewDataTests.testCubreLosOchoCasos` · `test_mock_prim_casos_previewdata` | pendiente (fase 5) |
| R14 | Retraso solo si existe y ≠ 0, con signo | iOS | `DepartureTests.testRetrasoCeroNoSePinta` · `FormatTests.testRetrasoConSigno` | pendiente (fase 5) |
| R15 | «En andén» (confirmado) ≠ «ya» (contador a cero) | iOS | `FormatTests.testEnAndenDistintoDeYa` | pendiente (fase 5) |
| R16 | Ritmo «¿corro o no corro?»: ≤ 3 min, ≤ 8 min, > 8 min | iOS | `FormatTests.testRitmoPorMinutos` | pendiente (fase 5) |
| R17 | La antigüedad cuenta desde la llegada al teléfono, más `data_age` | iOS | `BoardTests.testAntiguedadDesdeLlegadaAlTelefono` | pendiente (fase 5) |
| R18 | Antigüedad dicha «hace N s / min / h» | iOS | `FormatTests.testAntiguedadSegundosMinutosHoras` | pendiente (fase 5) |
| R19 | Dato viejo (stale del servidor o > 90 s sin recibir tablero): se apaga el tablero entero | ambas | `BoardTests.testViejoA90Segundos` · `SnapshotTests.testTableroViejoApagado` · `test_board_stale_tres_refrescos` | pendiente (fase 5) |
| R20 | La caché en disco guarda la hora real de llegada | iOS | `BoardCacheTests.testRestauraHoraDeLlegada` | pendiente (fase 5) |
| R21 | Decodificación tolerante: un JSON raro degrada, no revienta | iOS | `DecodingTests.testCamposAusentesNulosOTipoErroneo` | pendiente (fase 5) |
| R22 | Tren como cadena o número; `age` antiguo = `data_age` | iOS | `DecodingTests.testTrenNumeroOCadena` · `DecodingTests.testAgeLegadoComoDataAge` | pendiente (fase 5) |
| R23 | Identidad estable de cada salida entre refrescos | iOS | `DepartureTests.testIdEstableSinJid` | pendiente (fase 5) |
| R24 | Tramo sin sentido con varios destinos: cada salida dice a dónde va | iOS | `LegTests.testMezclaDestinos` · `DepartureChipTests.testDestinoSoloSiMezcla` | pendiente (fase 5) |
| R25 | Tramo vacío: «Sin circulación» si está cortada, «Servicio finalizado» si no | iOS | `LegCardTests.testTramoVacioCortadoVsFinalizado` | pendiente (fase 5) |
| R26 | Una estación que falla no tumba el tablero; el fallo va al pie | ambas | `BoardViewTests.testErroresDeEstacionEnPie` · `test_board_error_estacion_parcial` | pendiente (fase 5) |
| R27 | El aviso va dentro de la tarjeta de su tramo; en el detalle, español y francés | iOS | `DisruptionNoticeTests.testAvisoEnSuTramo` · `LegDetailTests.testAvisoBilingue` | pendiente (fase 5) |
| R28 | Obras con fecha futura no encienden el semáforo; se cuentan aparte | ambas | `test_line_status_planificados_no_cuentan` · `LegDetailTests.testCuentaAvisosPlanificados` | pendiente (fase 5) |
| R29 | Alternativas solo al pedirlas, nunca en el refresco | iOS | `BoardStoreTests.testRefrescoNoPideAlternativas` | pendiente (fase 5) |
| R30 | Alternativa que pasa por otra línea caída: «No sirve»; búsqueda forzable | ambas | `AlternativesTests.testNoUsableSeMarca` · `AlternativesTests.testBuscarDeTodasFormasForce` · `test_alternatives_usable_false` | pendiente (fase 5) |
| R31 | Buscadores: mínimo 2 caracteres y 350 ms de espera | iOS | `SearchTests.testDebounce350msYMinimo2` | pendiente (fase 5) |
| R32 | El sentido se elige de los que circulan ahora; sin elegir = todos, avisado | ambas | `LegBuilderUITests.testSentidoSeEligeDeLista` · `test_directions_observadas` | pendiente (fase 5) |
| R33 | Guardar desde el planificador: los tramos sin sentido se dicen | ambas | `SavePlanTests.testAvisaTramosSinSentido` · `test_from_plan_without_direction` | pendiente (fase 5) |
| R34 | «Llegar a» ≠ «salir a»; la API solo entiende `arrival`/`departure` | ambas | `TrajetAPITests.testPlanModoArrivalDeparture` · `test_plan_arrival_prefiere_salir_tarde` | pendiente (fase 5) |
| R35 | El horario se guarda y se enseña como se definió | iOS | `RoutesTests.testEtiquetaHorario` | pendiente (fase 5) |
| R36 | Días: 0 = lunes; etiquetas en español | iOS | `RoutesTests.testEtiquetaDias` | pendiente (fase 5) |
| R37 | La ruta que toca la decide el servidor por día y franja | servidor | `test_pick_active_route_mas_concreta` · `test_pick_active_route_sin_franja` · `BoardStoreTests.testSinFijarNoMandaRouteId` | pendiente (fase 5) |
| R38 | «Llego a» / «salgo a» se traducen a una franja | servidor | `test_derive_window_llegada` · `test_derive_window_salida` | pendiente (fase 5) |
| R39 | Cambiar de ruta o tocar rutas refresca al momento | iOS | `BoardStoreTests.testSeleccionRefrescaYa` · `BoardStoreTests.testInvalidarTrasGuardar` | pendiente (fase 5) |
| R40 | Los refrescos automáticos no engordan el historial | ambas | `BoardStoreTests.testRefrescoAutomaticoSinHistorial` · `test_board_log_history_false` | pendiente (fase 5) |
| R41 | Rutas: una sola copia compartida y una sola carga | iOS | `RoutesStoreTests.testLoadIfNeededUnaVez` | pendiente (fase 5) |
| R42 | Dos direcciones en orden, se recuerda la buena; un error HTTP no salta | iOS | `TrajetAPITests.testOrdenDeCandidatos` · `TrajetAPITests.testErrorHTTPNoSaltaDeDireccion` · `TrajetAPITests.testFalloDeRedSalta` | pendiente (fase 5) |
| R43 | Timeouts cortos (6 s / 12 s) y sin caché HTTP | iOS | `TrajetAPITests.testConfiguracionDeSesion` | pendiente (fase 5) |
| R44 | Un 404 de ruta borrada no es «sin red» | ambas | `BoardStoreTests.test404RutaBorradaVuelveAAutomatica` · `test_board_route_id_inexistente_404` | pendiente (fase 5) |
| R45 | Permiso de red local; sin él solo funciona Tailscale | iOS | `InfoPlistTests.testTextoRedLocal` · manual «red local» | pendiente (fase 5) |
| R46 | Cuota visible en el pie y en Ajustes; se reinicia a medianoche UTC | ambas | `BoardViewTests.testCuotaEnPie` · `SettingsTests.testCuotaPorEndpoint` · `test_quota_reinicio_utc` | pendiente (fase 5) |
| R47 | Densidad de las salidas según el número de tramos (1–6) | iOS | `ChipDensityTests.testDensidadPorTramos` | pendiente (fase 5) |
| R48 | Minutos primero, en cifras de ancho fijo; la primera salida manda | iOS | `SnapshotTests.testPrimeraSalidaDestacada` · `DepartureChipTests.testTransicionNumerica` | pendiente (fase 5) |
| R49 | La vía probable se explica (porcentaje, muestras y motivo) | iOS | `LegDetailTests.testExplicaViaProbable` | pendiente (fase 5) |
| R50 | VoiceOver: cada salida se lee como una frase completa | iOS | `DepartureChipTests.testEtiquetaAccesible` | pendiente (fase 5) |
| R51 | «Reducir movimiento» para latidos y barras | iOS | `AccesibilidadTests.testReducirMovimiento` | pendiente (fase 5) |
| R52 | Área táctil mínima de 44 pt | iOS | `AccesibilidadUITests.testAreasTactiles44` | pendiente (fase 5) |
| R53 | Estados no felices: esqueleto, vacío que dice qué hacer, «no se llega» solo sin nada guardado | iOS | `BoardViewTests.testEstadosVacioCargaError` | pendiente (fase 5) |
| R54 | Se ve cuándo llega el siguiente dato (barra de 30 s) | iOS | `BoardViewTests.testBarraDeRefresco` | pendiente (fase 5) |
| R55 | Avisos efímeros (2,4 s), sin diálogos que corten el paso | iOS | `RoutesViewTests.testToastEfimero` | pendiente (fase 5) |
| R56 | Formatos en español (coma decimal, meses, horas de Navitia, transbordos) | iOS | `FormatTests.testFormatosEnEspanol` | pendiente (fase 5) |
| R57 | Hex de color tolerante y gris de reserva que no miente | iOS | `LineColorTests.testParseHexVariantes` | pendiente (fase 5) |
| R58 | El bundle id `com.ismaeloul.trajet` no cambia nunca | iOS | `AppTests.testBundleIdNoCambia` | pendiente (fase 5) |
| R59 | El `.xcodeproj` no se versiona: lo genera XcodeGen | iOS | CI: paso `xcodegen generate` de `ios.yml` | pendiente (fase 5) |
| R60 | La IPA «lite» no depende de nada que el Apple ID gratuito no dé | iOS | `AppTests.testLiteSinAppGroupNoRompe` | pendiente (fase 5) |
| R61 | Ajustes: las direcciones se guardan al escribir; «Restablecer» olvida la preferida | iOS | `ServerConfigTests.testPersisteAlEscribir` · `ServerConfigTests.testRestablecer` | pendiente (fase 5) |
| R62 | Las líneas de una parada llegan ordenadas por modo; la app no reordena | servidor | `test_lines_orden_por_modo` | pendiente (fase 5) |

---

## R1–R13: reglas del encargo (texto literal)

Enunciados copiados de `PROMPT-trajet-v2.md:94-106`.

### R1 · Uso real
> Uso real: no es una app de planificar viajes, es de mirar de reojo si llego. De pie, andando por una estación, con una mano, en 2 o 3 segundos y a contraluz. Todo el diseño se supedita a esto.

- **Dato / origen**: `README.md:75-79`; jerarquía en `Views/Board/BoardView.swift:3-7` y `Views/Board/DepartureChip.swift:46-50`; la pregunta «¿corro o no corro?» en `Design/Format.swift:46-49`.
- **Cómo se comprueba**: capturas automáticas (iPhone SE, 16, 16 Pro Max; claro y oscuro; Dynamic Type grande): los minutos son lo primero y lo más grande de cada tramo; contraste AAA en minutos y vía; nada crítico debajo de cristal (encargo 3.1). Prueba manual a contraluz.
- **Estado en la v1**: tema oscuro forzado (`TrajetApp.swift:11-12`, `Info.plist:32-34`); todos los cuerpos de letra son fijos (`.system(size:)`, p. ej. `Design/Theme.swift:27-39`), así que **no hay Dynamic Type**.

### R2 · La vía solo en el 17 %
> La vía solo aparece en el 17 % de los trenes (mediana: 7,7 min antes). Nunca es una columna fija. Cuando aparece, se destaca (caja llamativa y latido).

- **Dato / origen**: `README.md:86`; `Views/Board/PlatformBadge.swift:12-14`; `Model/Board.swift:43-44` (`platform` nil el 83 %, `platform_new`). El servidor marca `platform_new` cuando un viaje pasa de «sin andén» a «con andén» (`trajet-server/app/board.py:265-284`).
- **Cómo se comprueba**: salida sin `platform` ni `guess` → el chip no tiene hueco de vía; con `platform` y `platform_new: true` → caja amarilla y latido (y, en la v2, háptica, encargo 3.2); con «Reducir movimiento», sin latido.
- **Estado en la v1**: caja amarilla `rgb(1.0, 0.84, 0.16)` y latido de 0,65 s repetido 5 veces al aparecer (`PlatformBadge.swift:53-65`); no hay háptica. La vía se inserta en el chip solo si existe (`DepartureChip.swift:64-70`, `152-162`), **pero esa línea 64 no compila** (ver `docs/ios-reutilizable.md`).

### R3 · Metro, bus y tranvía sin vía
> Metro, bus y tranvía no publican vía nunca: en esos modos no se reserva hueco para ella.

- **Dato / origen**: `README.md:87` (0 de ~600); `Model/Board.swift:183-188` y `204-226` (`TransportMode.publishesPlatform`: solo RER, Transilien y TER).
- **Cómo se comprueba**: con `line_mode` «Métro», «Bus», «Tramway» no se pinta vía aunque venga `platform` o `guess`; con «RER», «Train Transilien», «TER» sí.
- **Discrepancia a resolver en la v2**: la app usa una **lista blanca** por subcadenas (`Board.swift:208-218`: `metro`, `rer`, `transilien`, `ter`, `tram`, `bus`; cualquier otro modo es `.other` y no enseña vía); el servidor usa una **lista negra** (`trajet-server/app/collector.py:53`: `metro, bus, tram, tramway, funicular, funiculaire`) y el laboratorio otra expresión (`design-lab/shared/core.js`, `publishesPlatform`: `/rer|transilien|ter|train/`, que sí incluye «train»). Un modo como «Train» a secas recibe trato distinto en cada sitio. Además `contains("ter")` casa con cualquier modo que contenga esas letras.

### R4 · Sin hora teórica no hay retraso
> 26 de 36 líneas no mandan hora teórica: en metro y bus no hay retraso que enseñar, y no se inventa.

- **Dato / origen**: `README.md:88`; el servidor solo calcula `delay` si viene la hora teórica (`trajet-server/app/board.py:255-257`); en la app `delay` es opcional (`Model/Board.swift:46`) y se pinta vía `realDelay` (`Board.swift:80-84`, `DepartureChip.swift:135-137`).
- **Cómo se comprueba**: `delay: null` → ningún texto de retraso en chip, detalle ni VoiceOver. La regla es por **dato**, no por modo: un bus que sí manda hora teórica enseña su retraso (caso `b1`, `Resources/PreviewData.swift:56-58`, +11 min).

### R5 · Longitud sí, ocupación no
> No existe dato de ocupación. Sí existe la longitud del tren (corto/largo, en el 61 % de las salidas): esa sí se enseña.

- **Dato / origen**: `README.md:89`; `Model/Board.swift:29-35` (`TrainLength`: «Tren corto» / «Tren largo»); servidor `trajet-server/app/board.py:285-294`.
- **Cómo se comprueba**: `length: "short"|"long"` aparece en la segunda línea del chip cuando no hay destino ni retraso que decir (`DepartureChip.swift:125-145`), en el detalle (`LegDetailSheet.swift:162`) y en VoiceOver (`DepartureChip.swift:183`). Ningún modelo tiene campo de ocupación.

### R6 · Minutos largos
> Los minutos largos se formatean: 106 min se pinta "1h46".

- **Dato / origen**: `README.md:90` (buses a 106 y 165 min); `Design/Format.swift:7-23`.
- **Cómo se comprueba**: 59 → «59» + «min»; 60 → «1h» sin unidad; 106 → «1h46»; 165 → «2h45»; negativos → «0».
- **Estado en la v1**: VoiceOver dice «en 1 horas y 46 minutos» (`Format.swift:137-138`): concordancia a corregir.

### R7 · Cuota y bucle de 30 s
> Cuota de 1000 llamadas al día por endpoint en PRIM: el refresco de 30 s solo corre mientras se está mirando o en el modo trayecto. En cualquier otro caso, en segundo plano el bucle se para.

- **Dato / origen**: `README.md:91`; `Views/RootView.swift:55-71`; `Store/BoardStore.swift:12-13`, `18-19`, `43-65`; cuota por endpoint y reinicio en `trajet-server/app/prim.py:6-7`.
- **Cómo se comprueba**: el bucle arranca solo con `scenePhase == .active` y la pestaña Tablero; se para al pasar a inactiva/segundo plano o a otra pestaña; nunca hay dos bucles. En la v2, además, sigue vivo durante el modo trayecto y solo entonces.
- **Estado en la v1**: no existe modo trayecto. Cada vuelta a la pestaña Tablero o a primer plano lanza un refresco inmediato sin límite mínimo (ver `docs/inventario-funcional.md`, F58).

### R8 · Avisos en francés
> Los avisos llegan en francés: se muestra el francés con la etiqueta «traduciendo» y se sustituye al llegar la traducción. Nunca se espera al modelo.

- **Dato / origen**: `README.md:92`; `Model/Board.swift:126-140` (`visibleMessages`, `awaitingTranslation`); `Views/Board/DisruptionNotice.swift:63-67` y `82-106` (`TranslatingChip`); servidor `trajet-server/app/main.py:199-204`.
- **Cómo se comprueba**: `messages_es` con `null` o vacío en la posición *i* → se ve el francés de esa posición y la etiqueta «Traduciendo»; `translating: true` también la enciende; con la traducción, se ve el español sin etiqueta.

### R9 · Nunca se borra la pantalla
> Nunca se borra la pantalla. Si la API falla, se queda el último tablero bueno y se indica su antigüedad. Se guarda en disco, para que la primera apertura del día no enseñe un hueco.

- **Dato / origen**: `README.md:96-98`; `Store/BoardStore.swift:7-11`, `69-86` (un fallo solo apunta `lastError`), `108-145` (`BoardCache`); `Views/Board/BoardView.swift:221-255` (`FreshnessPill`).
- **Cómo se comprueba**: tras un tablero bueno, un fallo de red deja el tablero y cambia la píldora a «sin conexión» con su antigüedad; al arrancar sin red se ve el último tablero de disco con su edad real.
- **Excepción en la v1 que la v2 debe corregir**: al cambiar de ruta desde el título se hace `board = nil` (`BoardStore.swift:92`); si esa petición falla, se ve «No se llega al servidor» aunque haya un tablero guardado.
- Nota: el encargo 2B cita esta regla como «regla 6» (`PROMPT-trajet-v2.md:244`); es esta R9.

### R10 · Vía probable ≠ real
> La vía probable nunca se confunde con la real. Se distinguen por forma y palabra, no por un matiz de color: caja sólida con «Vía» frente a recuadro punteado con «probable».

- **Dato / origen**: `README.md:99-101`; `Views/Board/PlatformBadge.swift:3-11`, `39-68` (real: caja sólida blanca o amarilla, rótulo «VÍA»), `72-102` (probable: recuadro punteado `dash [3, 2.5]`, rótulo «PROBABLE», texto atenuado).
- **Cómo se comprueba**: en escala de grises y en widgets monocromos se siguen distinguiendo por forma y palabra; la probable nunca lleva «Vía» ni caja rellena.
- Nota: el encargo 2B la cita como «regla 7» (`PROMPT-trajet-v2.md:260`); es esta R10.

### R11 · Acierto solo del servidor
> El porcentaje de acierto de la previsión sale solo de /api/platform-model. La app nunca pregunta al usuario si acertó.

- **Dato / origen**: `README.md:147-150`; `Views/Stats/StatsView.swift:127-131`, `137-139`, `183-195`; `Model/Stats.swift:93-119`.
- **Cómo se comprueba**: el único origen del porcentaje es `accuracy.rate`; con `rate: null` se enseña «—» (`Stats.swift:115-118`); no existe ninguna vista, alerta ni botón que pregunte por el acierto.

### R12 · Colores de línea
> Los colores de línea vienen de la API (line_color): son los oficiales de las estaciones y los únicos colores saturados junto a los estados. Hay que garantizar su contraste en los distintivos.

- **Dato / origen**: `README.md:117-120`; `Design/Theme.swift:3-23` (paleta neutra y tres tonos de estado); `Design/LineColor.swift:3-26`, `47-53`, `60-88`.
- **Cómo se comprueba**: ningún color saturado fuera de `line_color` y los estados; para cada color de línea de IDFM, el texto del distintivo cumple AA (≥ 4,5:1, o ≥ 3:1 si el cuerpo es grande).
- **Hallazgo en la v1: el contraste NO está garantizado.** `LineColor.ink(on:)` elige negro si la luminancia relativa supera **0,45** (`LineColor.swift:23-26`). El punto en que negro y blanco dan el mismo contraste es ≈ 0,179, así que todo color con luminancia entre 0,18 y 0,45 recibe texto blanco con menos de 4,5:1. Cálculo reproducible (script en el scratchpad de la sesión): `#FF7E2E` (naranja de prueba) → blanco a **2,54:1** (negro daría 8,28:1). Los colores que hay hoy en `PreviewData` salen bien, pero `B94E9A` (RER E) queda justo en 4,55:1. La v2 debe elegir la tinta por el **mayor contraste** y testearlo con la lista completa de colores de IDFM.

### R13 · PreviewData como banco de pruebas
> PreviewData son bancos de prueba, no maquetas: tramo vacío, línea cortada, aviso sin traducir, vía que aparece, vía solo probable, bus a 106 min, tren parado en el andén y destinos mezclados. Consérvalos y amplíalos.

- **Dato / origen**: `README.md:122-128`; `Resources/PreviewData.swift:4-10`. Dónde está cada caso: tramo vacío `:67-71` (T2 sin salidas); línea cortada `:96-102` (13, nivel 2); aviso sin traducir `:100-101` (`messages_es: [null]`, `translating: true`); vía que aparece `:79-81` (E, vía 11, `platform_new: true`); vía solo probable `:82-93` y `:153-158`; bus a 106 min `:62-64`; tren parado en el andén `:104-106` (`at_stop: true`); destinos mezclados `:98` y `:104-112` (13 sin sentido, Place d'Italie / Bobigny).
- **Cómo se comprueba**: todos los JSON decodifican sin `try!` fallido; cada caso tiene al menos un test que lo usa; los mocks de PRIM del servidor reproducen los mismos casos (encargo 1.7).
- Qué falta añadir: ver `docs/inventario-funcional.md`, sección «PreviewData».

---

## R14+: reglas adicionales encontradas en la app

### R14 · Retraso solo si existe y ≠ 0
«Un retraso de cero no es un retraso: no se pinta» (`Model/Board.swift:80-84`); «Retraso con signo. Un +0 no se enseña nunca» (`Design/Format.swift:25-28`). Positivo «+2 min», negativo «-1 min»; VoiceOver dice «minutos de retraso» / «minutos de adelanto» (`DepartureChip.swift:171-174`).
- **Comprobación**: `delay` 0 o null → sin texto; 2 → «+2 min»; −1 → «-1 min».

### R15 · «En andén» ≠ «ya»
«"En andén" y "ya" son cosas distintas y no se pueden mezclar: la primera está confirmada por el tren (`at_stop`), la segunda solo quiere decir que el contador ha llegado a cero» (`Design/Format.swift:86-100`; `Model/Board.swift:48`). `at_stop` manda sobre `minutes`.
- **Comprobación**: `at_stop: true, minutes: 0` → «En andén» sin icono de ritmo; `at_stop: false, minutes: 0` → «ya» con ritmo «correr».

### R16 · Ritmo «¿corro o no corro?»
`Design/Format.swift:46-59`: ≤ 3 min → correr (`figure.run`, color de aviso rojo); ≤ 8 min → andar; > 8 min → con calma. «ya» cuenta como correr; «En andén» no lleva ritmo (`Format.swift:124-130`). En modo compacto el icono solo va en la primera salida (`DepartureChip.swift:107`).
- **Comprobación**: 3 → correr; 4 → andar; 8 → andar; 9 → con calma.

### R17 · La antigüedad se cuenta desde el teléfono
«La antigüedad que se enseña se cuenta desde aquí y no desde `updated_at`: si el móvil pierde la red, lo que envejece es lo que tenemos en la mano» (`Model/Board.swift:274-277`). Edad = (ahora − `receivedAt`) + `data_age` (`Board.swift:326-329`).
- **Comprobación**: tablero con `data_age` 8 recibido hace 60 s → 68 s.

### R18 · Formato de la antigüedad
`Design/Format.swift:30-38`: < 60 s → «hace N s»; < 60 min → «hace N min»; si no, «hace N h» (redondeo al segundo, truncado a minutos y horas).
- **Comprobación**: 59,4 → «hace 59 s»; 60 → «hace 1 min»; 3599 → «hace 59 min»; 3600 → «hace 1 h».

### R19 · Dato viejo: se apaga el tablero entero
«Con el dato viejo se apaga el tablero entero, no solo una etiqueta» (`Model/Board.swift:331-334`; `Views/Board/BoardView.swift:83-86`: opacidad 0,5 y gris 0,45). Viejo = `stale` del servidor **o** el teléfono lleva más de 90 s sin recibir un tablero nuevo. **Cambio de la v2**: con el TTL adaptativo, una estación con el próximo tren a 40 min se pide cada 5 min y su `data_age` llega a 300 s sin ser un dato viejo; por eso el servidor marca `stale` solo cuando una estación o los avisos superan su propio ritmo de refresco + 60 s o fallan, y la app ya no apaga el tablero por `data_age` > 90 s. La antigüedad que se enseña sigue siendo la real (R17). El reloj interno avanza cada 5 s (`BoardView.swift:27-34`).
- **Comprobación**: recibido hace 90 s → vivo; 91 s → apagado; `stale: true` recién recibido → apagado; `data_age` 300 con `stale: false` y recibido ahora → vivo.

### R20 · Caché con hora real de llegada
«Se guarda el JSON y la hora de llegada por separado: si se recuperase sin la hora, el tablero de anoche parecería recién hecho» (`Store/BoardStore.swift:108-145`).
- **Comprobación**: guardar, esperar, recargar → `receivedAt` igual al guardado y la antigüedad incluye el tiempo en disco.

### R21 · Decodificación tolerante
«Un JSON raro degrada, no revienta» (`Model/Decoding.swift:3-16`). Todo modelo usa `get(clave, reserva)` u `opt(clave)`: un campo ausente, `null` o de otro tipo toma el valor de reserva (p. ej. `label` «normal», `time_from` «07:00», `time_to` «10:00», `time_mode` «window», `usable` true: `Board.swift:109`, `Routes.swift:90-92`, `Plan.swift:178`).
- **Comprobación**: `{}` decodifica a un `Board` vacío; `"minutes": "6"` no lanza (queda 0); `time_mode` desconocido → `.window`.

### R22 · Formatos cambiantes de la API
El número de tren llega como cadena o número (`Model/Decoding.swift:18-24`, usado en `Board.swift:70`). Los ficheros antiguos traen `age` en lugar de `data_age` (`Board.swift:293-294`).
- **Comprobación**: `"train": 135711` y `"train": "135711"` → «135711»; `{"age": 12}` → `dataAge` 12.

### R23 · Identidad estable de las salidas
«Identidad estable entre refrescos: es lo que permite que una salida se desplace por la tira en vez de que parpadee la lista entera» (`Model/Board.swift:74-78`): `jid`, o `at|destination|minutes` si falta.
- **Comprobación**: mismo `jid` con otros minutos → mismo `id`.

### R24 · Destinos mezclados
«Cuando el tramo no filtra sentido, en la misma parada se mezclan destinos distintos y hay que decir a dónde va cada paso» (`Model/Board.swift:197-201`). La cabecera dice «todos los sentidos» (`LegCardView.swift:84-90`) y cada chip lleva su destino (`DepartureChip.swift:125-134`).
- **Comprobación**: `directions: []` y dos destinos → mezcla; `directions: []` y un solo destino → no; con `directions` → nunca.

### R25 · Tramo vacío
«Pasa de noche, y pasa cuando la línea está cortada de verdad. Los demás tramos siguen funcionando» (`Views/Board/LegCardView.swift:104-127`): «Sin circulación» si el nivel es 2, si no «Servicio finalizado», más «no hay más salidas». El detalle dice «La línea no está circulando.» / «No quedan más salidas hoy.» (`LegDetailSheet.swift:22-27`).

### R26 · Fallo parcial
«Un fallo en una estación no puede tumbar a las otras: se dice aquí abajo y el resto del tablero sigue vivo» (`Views/Board/BoardView.swift:171-182`, máximo 3 errores). El servidor apunta cada estación caída en `errors` y sigue (`trajet-server/app/board.py:398-400`).

### R27 · El aviso va en su tramo
«No va en una franja global arriba porque una franja global no dice *qué* tramo está tocado» (`Views/Board/DisruptionNotice.swift:3-6`). En la tarjeta caben 2 mensajes (`DisruptionNotice.swift:34-35`; el servidor manda hasta 3, `board.py:212`). En el detalle se enseñan español y francés «para comprobar la traducción» (`LegDetailSheet.swift:71-93`).

### R28 · Obras futuras no encienden el semáforo
Servidor: «Un aviso de obras para dentro de un mes NO es una perturbación de hoy» (`trajet-server/app/board.py:180-182`, `195-213`); se cuentan en `planned`. La app lo dice en el detalle: «Además hay N aviso(s) de obras con fecha futura, que no afectan a hoy.» (`LegDetailSheet.swift:95-100`).

### R29 · Alternativas solo bajo demanda
«Esta llamada NO va en el refresco de 30 s: comparte la bolsa de mil llamadas diarias con el buscador» (`Views/Board/AlternativesSheet.swift:3-7`; `README.md:143`). Se pide al abrir la hoja (`AlternativesSheet.swift:43`).
- **Comprobación**: N refrescos del tablero → 0 llamadas a `/api/alternatives`.

### R30 · Alternativas que no sirven
«Pasar por otra línea que también está caída no es una alternativa» (`AlternativesSheet.swift:128-129`, `175-190`, opacidad 0,62 en `:195`; `Model/Plan.swift:161-162`). Si no hay opciones, «Buscar de todas formas» repite con `force=true` (`AlternativesSheet.swift:54-74`; `Net/TrajetAPI.swift:136-140`).

### R31 · Buscadores sin gastar cuota por tecla
Mínimo 2 caracteres (tras recortar espacios) y 350 ms de espera; cada tecla cancela la búsqueda anterior (`Views/Plan/PlaceSearchView.swift:71-81`; `Views/Routes/LegBuilderView.swift:99-109`).

### R32 · El sentido se elige, no se escribe
«El texto del tiempo real no coincide con el del planificador y un sentido mal escrito deja el tablero vacío sin decir nada» (`Views/Routes/RouteEditorView.swift:33-37`; `LegBuilderView.swift:3-8`; `Net/TrajetAPI.swift:107-108`). Se elige entre los destinos que circulan ahora; sin elegir ninguno «se enseñan todos los pasos de la línea, en los dos sentidos» (`LegBuilderView.swift:203`) y el editor lo marca en color de aviso (`RouteEditorView.swift:168-173`).

### R33 · Tramos guardados sin sentido: se dice
«Tramos que se han guardado sin sentido porque el texto de Navitia no casaba con el del tiempo real. Hay que decirlo, no callarlo» (`Model/Plan.swift:114-118`; `Views/Plan/PlaceSearchView.swift:116-118`, `184-200`, `231-237`; servidor `trajet-server/app/main.py:408-411`).

### R34 · Llegar a ≠ salir a
«"Llegar a las 09:00" y "salir a las 09:00" no son el mismo resultado reordenado: la API resuelve hacia atrás, y por llegada gana el itinerario que te deja salir más tarde» (`Views/Plan/PlanView.swift:5-8`). El servidor solo entiende `departure` y `arrival` (`Net/TrajetAPI.swift:123-124`).

### R35 · El horario se enseña como se pensó
«"llego a las 09:00" no es "de 07:30 a 09:15"» (`Model/Routes.swift:5-7`); etiquetas «llego 09:00», «salgo 08:00» o «07:00–10:00» (`Routes.swift:99-107`).

### R36 · Días de la semana
`days` con 0 = lunes (`Model/Routes.swift:67`; servidor `trajet-server/app/board.py:134-137`). Etiquetas: 7 días → «todos los días», 0–4 → «entre semana», 5–6 → «fin de semana», si no las letras «L M X J V S D» (`Routes.swift:109-117`). Nuevas rutas: lunes a viernes por defecto (`RouteEditorView.swift:46`, `PlaceSearchView.swift:113`).

### R37 · La ruta que toca la decide el servidor
La app no calcula qué ruta toca: sin ruta fijada no manda `route_id` y «manda el servidor, que sabe cuál toca según el día y la hora» (`Store/BoardStore.swift:25-27`, `Net/TrajetAPI.swift:52`; `RoutesStore.swift:11`). Algoritmo exacto en `trajet-server/app/board.py:125-151` (explicado paso a paso en `docs/inventario-funcional.md`, F62–F64). El tablero dice «Ruta activa» si la eligió el servidor y «Ruta elegida» si la fijó el usuario (`BoardView.swift:93`, `auto_selected` en `main.py:213`).

### R38 · Franja derivada
Las tres formas de horario «acaban siendo una franja en el servidor» (`Model/Routes.swift:5-7`). Servidor: salida → `[hora − 45, hora + duración + 30]`; llegada → `[hora − duración − 45, hora + 15]`; duración por defecto 60 min (`trajet-server/app/board.py:83-122`; se guarda al salvar, `db.py:202-208`).
- **Discrepancia**: el texto del editor para «Salgo a» dice «La franja va desde 45 min antes hasta que llegas» (`RouteEditorView.swift:150`), pero el servidor la alarga 30 min más allá de la llegada.

### R39 · Refresco inmediato al cambiar
«Cambiar de ruta desde el título. Se refresca ya, sin esperar al ciclo» (`Store/BoardStore.swift:88-94`); «Tras crear, editar o borrar una ruta el tablero puede haber cambiado» (`BoardStore.swift:99-105`), llamado desde `RoutesView.swift:64`, `:115` y `PlanView.swift:98`.

### R40 · Refrescos automáticos sin historial
«`logHistory: false` para los refrescos que no queremos que engorden el historial (una consulta cada 30 s no es una consulta real)» (`Net/TrajetAPI.swift:48-54`; servidor `main.py:170`, `207-211`).
- **Estado en la v1: no se cumple.** `BoardStore.refresh()` llama `api.board(routeId:)` con el valor por defecto `true` (`Store/BoardStore.swift:78`). Lo mitiga el servidor, que no guarda dos observaciones de la misma ruta en menos de 600 s (`board.py:453-459`).

### R41 · Rutas: una copia, una carga
«Las comparten el selector del título del tablero y la pantalla de rutas, así que hay una sola copia y una sola recarga» (`Store/RoutesStore.swift:4-5`); «Solo recarga si no hay nada: evita una llamada por cada vez que se abre la pestaña» (`RoutesStore.swift:37-42`).

### R42 · Dos direcciones
«La app no pregunta cuál usar: prueba, se queda con la que responde y la recuerda» (`Net/ServerConfig.swift:4-9`; `README.md:60-67`). Orden: la preferida (última que respondió), luego casa, luego Tailscale, sin repetir ni vacías (`ServerConfig.swift:50-59`). «Un error del servidor (4xx/5xx) NO hace saltar a la siguiente» (`Net/TrajetAPI.swift:174-178`, `199-219`); un fallo de transporte sí.
- **Comprobación** (con `URLProtocol` simulado): casa caída → Tailscale y queda preferida; casa responde 500 → error sin probar Tailscale; JSON ilegible → `badPayload` sin saltar.

### R43 · Timeouts cortos
«Corto a propósito: si la red de casa no está, hay que descartarla rápido y saltar a Tailscale antes de que el refresco de 30 s pase» (`Net/TrajetAPI.swift:36-43`): petición 6 s, recurso 12 s, `waitsForConnectivity = false`, sesión efímera y `reloadIgnoringLocalCacheData`.

### R44 · 404 de ruta borrada
«Un 404 de ruta borrada no es lo mismo que quedarse sin red» (`Net/TrajetAPI.swift:19-23`); el servidor responde 404 «ruta no encontrada» (`trajet-server/app/main.py:176-179`).
- **Estado en la v1: declarado pero sin usar.** `isNotFound` no se llama en ningún sitio; si se borra la ruta fijada que se está viendo, `invalidate()` no suelta la fijación (`BoardStore.swift:100-103` solo la suelta si no coincide con la del tablero) y el tablero pide cada 30 s una ruta inexistente, enseñando «sin conexión».

### R45 · Permiso de red local
«La primera vez iOS pedirá permiso para hablar con la red local: hay que dárselo o la dirección de casa no funcionará (Tailscale sí)» (`README.md:69-71`; texto en `Info.plist:54-56`).

### R46 · Cuota visible
Pie del tablero: «N llamadas hoy» del endpoint `stop-monitoring` (`Model/Board.swift:338-339`; `BoardView.swift:184-187`; `Format.swift:40-43`). Ajustes: «N / 1000» por endpoint con nombres «Tablero», «Avisos», «Buscador» (`SettingsView.swift:51-53`, `100-107`) y el aviso «se reinicia a medianoche UTC» (`SettingsView.swift:78`; `trajet-server/app/prim.py:6-7`).

### R47 · Densidad según número de tramos
«Es lo que permite que quepan de uno a seis tramos sin que se pisen» (`Views/Board/DepartureChip.swift:3-44`): 1–2 tramos holgado (cifra 34 pt), 3–4 normal (30 pt), 5–6 compacto (26 pt, sin segunda línea). «Lo que nunca se encoge por debajo de lo legible es la cifra de minutos.»

### R48 · Minutos primero y sin bailar
«Los minutos son lo primero, el estado de la línea lo segundo y el resto se lee solo si sobra tiempo» (`BoardView.swift:5-7`). «Los minutos van en cifras de ancho fijo para que no bailen cuando pasan de 9 a 10» (`Design/Theme.swift:25-31`) y cambian con `contentTransition(.numericText())` (`DepartureChip.swift:99`). «La primera salida es la que se mira; las demás son contexto» (`DepartureChip.swift:55-56`, `74-82`). Tira horizontal: «Apiladas, cinco tramos no caben en una pantalla» (`LegCardView.swift:129`).

### R49 · La vía probable se explica
«Por qué la previsión dice esa vía. Sin esto es un número mágico» (`Views/Board/LegDetailSheet.swift:142-148`): «Sale por la X el N % de las veces (M observaciones, motivo).» Solo en modos con vía y sin vía real. VoiceOver lo dice también (`PlatformBadge.swift:97-101`).

### R50 · VoiceOver: una frase por salida
`Views/Board/DepartureChip.swift:164-185`: momento («en 6 minutos», «sale ya», «parado en el andén»), destino si hay mezcla, retraso o adelanto, vía («acaba de salir la vía 11» si es nueva) o «vía 11 probable, 82 por ciento», y longitud. El chip es un solo elemento (`:83-84`).

### R51 · Reducir movimiento
Se respeta en el latido de la vía (`PlatformBadge.swift:60-65`), en «Traduciendo» (`DisruptionNotice.swift:98-103`) y en la barra de refresco (`BoardView.swift:278`).
- **Estado en la v1**: el esqueleto de carga parpadea siempre (`BoardView.swift:311-313`) y las transiciones de la barra de pestañas no miran la preferencia (`RootView.swift:87`).

### R52 · Área táctil mínima
«El manual no la negocia: 44 pt» (`Design/Theme.swift:62-67`). Ejemplos: pestañas 48 pt (`RootView.swift:102`), botón de ajustes (`BoardView.swift:104`), selector de ruta (`BoardView.swift:145`), «Buscar alternativa» (`DisruptionNotice.swift:54`).

### R53 · Estados no felices
- Esqueleto al cargar sin nada que enseñar: «así se ve dónde va a estar cada cosa antes de que llegue» (`BoardView.swift:287-316`).
- Vacío que dice qué hacer: «Tiene que decir qué hacer, no solo que está vacío» (`BoardView.swift:318-337`).
- «No se llega al servidor y encima no hay nada guardado que enseñar. Es el único caso en que la pantalla está vacía, y entonces dice por qué», con «Reintentar» (`BoardView.swift:339-373`).

### R54 · Barra del próximo refresco
«La barra de 30 s: dice cuándo llega el dato siguiente sin que haya que preguntárselo a nadie» (`BoardView.swift:257-283`), calculada desde `nextRefreshAt` «sin que el store tenga que latir a 60 fps» (`BoardStore.swift:29-31`).

### R55 · Avisos efímeros
«Aviso efímero. Nada de diálogos que corten el paso» (`Views/Routes/RoutesView.swift:198`): 2,4 s (`RoutesView.swift:121-127`; `PlanView.swift:99-103`).

### R56 · Formatos en español
Decimales con coma (`Views/Stats/StatsView.swift:197-199`); meses completos «agosto 2026» (`Model/Stats.swift:29-39`); «directo», «1 transbordo», «N transbordos» (`Model/Plan.swift:73-79`); «+12 min», «igual de rápido» (`Plan.swift:186-191`); horas de Navitia `AAAAMMDDTHHMMSS` → «HH:MM» (`AlternativesSheet.swift:198-206`); porcentaje «84 %» con espacio (`Stats.swift:115-118`).

### R57 · Hex de color tolerante
«Acepta con o sin almohadilla, y 3 o 6 dígitos» (`Design/LineColor.swift:10-14`, `35-45`). «Si la API no manda color (pasa en algún bus), un gris que no miente» (`LineColor.swift:7-8`); sin color válido, tinta blanca (`:24`).

### R58 · Bundle id fijo
«El identificador `com.ismaeloul.trajet` no cambia entre versiones», así reinstalar no borra nada (`README.md:43-45`; `project.yml:29`; encargo 1.1).

### R59 · Proyecto generado
«El `.xcodeproj` no se versiona: se genera. Lo que se edita es `project.yml`» (`README.md:55-56`; `project.yml:1-2`; `.gitignore:1-2`; `.github/workflows/ios.yml:37-41`).

### R60 · Firma gratuita
Con Apple ID gratuito «no lleva nada que necesite permisos que Apple no da a las cuentas gratuitas»: sin push, sin App Groups (sin widget ni Live Activity), sin iCloud (`README.md:33-41`). En la v2 esto se convierte en la IPA `lite`, que tiene que funcionar entera sin ellos (encargo 3.5).

### R61 · Ajustes sin botón de guardar
«Las direcciones se guardan según se escriben, para que no haya que acordarse de darle a nada» (`Views/Settings/SettingsView.swift:92-95`; `Net/ServerConfig.swift:43-48`). «Restablecer direcciones» vuelve a los valores de fábrica y olvida la preferida (`ServerConfig.swift:74-80`). En la v2 las direcciones llegan por el QR (encargo 1.2, 3.2), pero la edición a mano se mantiene.

### R62 · Líneas de una parada ordenadas por modo
«Líneas de una parada, ya ordenadas por el servidor: metro, RER, Transilien, TER, tranvía y los buses al final» (`Net/TrajetAPI.swift:99-100`; `LegBuilderView.swift:129-131`: «Saint-Lazare tiene 38 líneas y 30 son buses»). La app no reordena.

---

## Reglas de la v1 que el encargo v2 cambia

No son reglas vigentes: se listan para que nadie las «restaure» por error.

| v1 (origen) | v2 (encargo) |
|---|---|
| Tema oscuro forzado (`TrajetApp.swift:11-12`, `Info.plist:32-34`) | Modo claro y oscuro (encargo 2B y 3.6) |
| `NSAllowsArbitraryLoads` (`Info.plist:41-52`) | Excepciones solo para LAN y Tailscale; nada de `NSAllowsArbitraryLoads` (3.2) |
| IPs por defecto en el código (`Net/ServerConfig.swift:18-21`) | Las IPs van en la configuración y el QR, nunca fijas en el código (1.2) |
| Sin widget ni Live Activity (`README.md:37-41`) | IPA `full` con extensiones y App Group, IPA `lite` sin ellas (3.5) |
| Tamaños de letra fijos (`Design/Theme.swift:27-39`) | Dynamic Type (3.1) |
| Refresco solo mirando el tablero (`RootView.swift:55-71`) | Además durante el modo trayecto (R7) |
| API sin autenticación | Token de dispositivo en el Keychain (1.2, 3.2) |

## Decisiones de aspecto de la v1 (no son reglas)

La dirección «Cristal» puede cambiarlas sin romper nada: el hilo vertical que
degrada del color de un tramo al del siguiente (`LegCardView.swift:3-6`,
`LineColor.swift:56-59`); el distintivo fuera de la tarjeta; la barra de
pestañas en píldora flotante con etiqueta solo en la activa
(`RootView.swift:74-127`); la caja de vía real en blanco (salvo la nueva, que
sí es regla R2); los radios, sombras y grises concretos de `Design/Theme.swift`.

---

## Reglas del servidor

Sacadas de `docs/servidor.md` §17 (análisis del código 0.3.0). Solo se suben
a regla con id las que la v2 **no puede romper**; el resto de constantes
(TTL, umbrales del recolector…) siguen documentadas allí como decisiones
ajustables. Los tests son pytest de `trajet-server/tests/`.

| id | regla | origen | test propuesto | Test que la cubre |
|---|---|---|---|---|
| R63 | PRIM se autentica con la cabecera `apikey`; Navitia vive en `/marketplace/v2/navitia` | `app/prim.py:4-5, 23-25, 71` | `test_prim_cabecera_apikey_y_base` | pendiente (fase 5) |
| R64 | Una sola llamada a stop-monitoring por **estación** (StopArea padre), aunque varios tramos salgan de ella | `app/prim.py:9-10`; `app/board.py:371-372` | `test_board_una_llamada_por_estacion` | pendiente (fase 5) |
| R65 | Si PRIM falla y hay copia, se sirve la copia con su **edad real**; nunca pantalla vacía | `app/prim.py:84-123` | `test_prim_fallo_sirve_copia_con_edad` | pendiente (fase 5) |
| R66 | Peticiones simultáneas a la misma clave de caché = **una** llamada (lock por clave) | `app/prim.py:96-100` | `test_prim_lock_una_llamada` | pendiente (fase 5) |
| R67 | TTL de cada estación según lo cerca que esté su próximo paso (20/30/90/300/600 s) | `app/board.py:337-354` | `test_station_ttl_por_cercania` | pendiente (fase 5) |
| R68 | Aviso con «trafic (est) interrompu» y variantes = línea **interrumpida**, no solo perturbada | `app/board.py:21-33` | `test_interrumpido_con_copula` | pendiente (fase 5) |
| R69 | Aviso caducado (`ValidUntilTime` pasado) no cuenta; aviso con inicio futuro va a `planned` | `app/board.py:167-169, 180-182` | `test_aviso_caducado_y_futuro` | pendiente (fase 5) |
| R70 | La línea de un aviso sale de `LineRef` **o** de `IDFM.Cnnnnn` en `ItemIdentifier` | `app/idfm.py:44-57` | `test_lineas_en_mensaje` | pendiente (fase 5) |
| R71 | Una salida que se fue hace más de 1 min no se enseña; los minutos nunca son negativos | `app/board.py:249-251, 276` | `test_salida_pasada_y_minutos` | pendiente (fase 5) |
| R72 | Destinos comparados sin tildes, guiones raros ni espacios finos/duros | `app/idfm.py:89-106` | `test_norm_text_destinos` | pendiente (fase 5) |
| R73 | Vía real solo si es una vía: fuera `unknown`, vacío y nombres de estación de París | `app/idfm.py:69-86` | `test_real_platform` | pendiente (fase 5) |
| R74 | `platform_new` se enciende cuando aparece la vía de un viaje que no la tenía | `app/board.py:264-272` | `test_board_platform_new_al_aparecer` | pendiente (fase 5) |
| R75 | Previsión de vía: ≥ 3 observaciones y mayoría **estricta** (> 50 %); misión > hora teórica > línea; laborable y fin de semana aparte | `app/platform.py:29-33, 123-182` | `test_prevision_umbral_niveles_tipo_dia` | pendiente (fase 5) |
| R76 | El acierto se puntúa **sin** los datos de hoy (no se hace trampa) | `app/platform.py:96-120` | `test_puntuacion_sin_trampa` | pendiente (fase 5) |
| R77 | Solo se aprenden las estaciones de las rutas guardadas; los modos sin vía no se sondean | `app/collector.py:50-53, 91-115` | `test_collector_objetivos` | pendiente (fase 5) |
| R78 | El recolector nunca toca las 320 llamadas reservadas a la pantalla, no muestrea de 01:00 a 05:00 y va entre 120 y 1800 s | `app/collector.py:31-48, 126-156` | `test_plan_interval` | pendiente (fase 5) |
| R79 | Alternativas: solo con línea tocada o `force`; excluyen las líneas tocadas; una alternativa con línea interrumpida no es usable | `app/main.py:230-336` | `test_alternatives_usable_false` | pendiente (fase 5) |
| R80 | Traducción: el francés nunca se pierde; se traduce entero; una vez por texto (caché); el tablero nunca espera al modelo | `app/translate.py:9-17, 141-172` | `test_board_no_espera_traduccion` | pendiente (fase 5) |
| R81 | Planificador: los itinerarios solo a pie se descartan; «llegar a» prefiere la salida más tardía; una hora ya pasada es mañana | `app/planner.py:22-24, 102-107, 202-219` | `test_plan_arrival_prefiere_salir_tarde` | pendiente (fase 5) |
| R82 | Historial: como mucho una fila cada 10 min por ruta | `app/board.py:453-460` | `test_record_history_10min` | pendiente (fase 5) |

### Reglas nuevas de la v2 (servidor)

| id | regla | test propuesto | Test que la cubre |
|---|---|---|---|
| R83 | La clave PRIM **nunca** sale del servidor: ni en respuestas, ni en logs, ni en el HTML del panel, ni en errores (solo sus 4 últimos caracteres en el panel) | `test_clave_nunca_expuesta` | pendiente (fase 5) |
| R84 | La clave guardada en el panel manda sobre `PRIM_API_KEY` del entorno; va cifrada en reposo (AES-GCM, clave derivada de `APP_SEED`) con permisos 0600 | `test_keystore_prioridad_y_cifrado` | pendiente (fase 5) |
| R85 | Toda `/api/v1` exige token de dispositivo (salvo `ping` y `pair`); token de 256 bits guardado solo como hash y comparado en tiempo constante | `test_v1_sin_token_401` · `test_token_hash_y_compare_digest` | pendiente (fase 5) |
| R86 | Código de emparejamiento: un solo uso, 5 min, misma respuesta para malo/caducado/usado, rate limit por IP y global | `test_pair_caducado_reutilizado_fuerza_bruta` | pendiente (fase 5) |
| R87 | Un dispositivo revocado deja de funcionar al momento | `test_token_revocado_401` | pendiente (fase 5) |
| R88 | Cuota contada por endpoint y día UTC, persistida; al acercarse al límite se degrada (refresco más lento, caché) y nunca se sirve un tablero hueco | `test_quota_niveles_y_degradacion` · `test_v1_board_nunca_hueco` | pendiente (fase 5) |
| R89 | Las migraciones de SQLite conservan rutas, historial y andenes aprendidos | `test_migracion_conserva_datos` (+ copia real si está) | pendiente (fase 5) |
| R90 | El cliente del portal de IDFM no manda nunca la cabecera `apikey` de PRIM | `test_mapdata_sin_apikey` | pendiente (fase 5) |
