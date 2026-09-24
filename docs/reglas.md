# Reglas de Trajet

Fuente única de las reglas que la v2 no puede romper. Cada regla tiene un id
estable (**R1…**) que no se reutiliza ni se renumera aunque una regla se
retire. Los verificadores revisan el código contra esta lista punto por punto.
La columna «Test que la cubre», rellenada en la FASE 5, dice qué tests reales
comprueban cada regla (resumen de cobertura al final del documento).

- **R1–R13**: las 13 reglas no negociables del encargo
  (`PROMPT-trajet-v2.md`, sección 2), copiadas literalmente.
- **R14 en adelante**: reglas adicionales sacadas del `README.md`, del código
  y de los comentarios de la app iOS actual (rama `rewrite-v2`, commit
  `942ffbe`). Cada una cita `fichero:línea`.
- Al final: reglas de la v1 que el encargo cambia, decisiones de aspecto que
  **no** son reglas y un hueco para las reglas del servidor.

Convenciones de la tabla:

- **Capa**: `iOS`, `servidor` o `ambas`.
- **Test propuesto**: lo que se pensó en la FASE 1 (`Clase.testNombre` es
  XCTest/XCUITest de la app; `test_nombre` es pytest del servidor; «manual»
  remite a `docs/pruebas-iphone.md`). Muchos nombres cambiaron al escribir
  los tests: manda la columna siguiente.
- **Test que la cubre**: los tests que existen de verdad (FASE 5), abiertos
  uno a uno para confirmar que comprueban lo que dice la regla.
  `Clase.testNombre` está en `TrajetTests/` o `TrajetUITests/` (ojo:
  `SettingsLogicTests` vive en `StatsLogicTests.swift`);
  `fichero.py::test_nombre` en `trajet-server/tests/`. «parcial: …» dice qué
  parte de la regla se queda sin test; «sin test: …» que no hay ninguno y
  por qué. Lo que solo se puede probar en el aparato remite a
  `docs/pruebas-iphone.md` §N.
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
| R1 | Uso real: mirar de reojo si llego, de pie, una mano, 2–3 s, a contraluz | iOS | `SnapshotTests.testJerarquiaMinutosPrimero` · `AccesibilidadUITests.testContrasteMinutosYVia` · manual «contraluz» | parcial: `CapturasUITests.testCapturas1Tablero` (capturas de todos los tableros en iPhone SE, 16 y 16 Pro Max, claro y oscuro y letra grande, para revisar a ojo que la cifra manda) · `BoardViewLogicTests.testR47DensidadPorTramos` (la cifra de minutos no baja de lo legible en ninguna densidad); el contraluz, la lectura en 2–3 s y AX3 solo a mano: docs/pruebas-iphone.md §10 y §13. No hay test automático de contraste. |
| R2 | La vía solo en el 17 %; nunca columna fija; cuando aparece, caja llamativa y latido | ambas | `PlatformBadgeTests.testViaNuevaDestacadaYLatido` · `DepartureChipTests.testSinViaNoHayHueco` · `test_board_platform_new_al_aparecer` | `BoardViewLogicTests.testR2SinViaNiPrevisionNoHayHueco` · `BoardViewLogicTests.testR2ViaNuevaDuranteVeinticincoSegundos` · `BoardViewLogicTests.testR2PlatformNewDelServidorYNadaConElDatoViejo` · `BoardStoreTests.testViaQueApareceAvisa` · `ActivityContentBuilderTests.testViaPublicada` · `DecodingTests.testPreviewDataCubreLosCasos` · `test_escenarios.py::test_R2_sin_via_no_hay_hueco` · `test_escenarios.py::test_R2_R74_via_que_aparece` · `test_board.py::test_board_platform_new_al_aparecer` · parcial: la caja amarilla y el latido son vista y no tienen test (se ven en la captura 11 de `CapturasUITests.testCapturas1Tablero`); la lógica de cuándo la vía es «nueva» (25 s, no con el dato viejo, nunca la probable) sí. |
| R3 | Metro, bus y tranvía no publican vía: sin hueco reservado | ambas | `TransportModeTests.testModosSinVia` · `DepartureChipTests.testMetroBusTranviaSinHuecoDeVia` · `test_board_sin_via_metro` | `BoardViewLogicTests.testR3MetroBusTranviaSinHuecoDeVia` · `BoardViewLogicTests.testR50R3MetroSinVia` · `DecodingTests.testModosConYSinVia` · `StatsLogicTests.testR3CoberturaPorTramo` · `ActivityContentBuilderTests.testSinViaEnMetroBusYTranvia` · `ActivityContentBuilderTests.testMomentosDeLaCifra` · `WidgetTimelineTests.testMetroSinViaYDestinosMezclados` · `TableroUITests.testTableroCincoTramos` · `test_escenarios.py::test_R3_modos_sin_via_no_reservan_hueco` · `test_idfm.py::test_publishes_platform` · `test_collector.py::test_collector_objetivos` · `test_v1.py::test_flujo_completo_emparejar_y_tablero` |
| R4 | 26 de 36 líneas sin hora teórica: en metro y bus no hay retraso y no se inventa | ambas | `DepartureTests.testSinHoraTeoricaNoHayRetraso` · `test_extract_departures_sin_aimed_delay_null` | `BoardViewLogicTests.testR4SinHoraTeoricaNoHayRetraso` · `ActivityContentBuilderTests.testRetrasoSoloConHoraTeorica` · `WidgetTimelineTests.testRetrasoSoloConHoraTeorica` · `test_board.py::test_extract_departures_sin_aimed_delay_null` · `test_escenarios.py::test_R4_sin_hora_teorica_no_hay_retraso` · `test_legacy.py::test_tablero_legacy_forma_exacta` |
| R5 | No hay ocupación; sí longitud del tren (corto/largo), y se enseña | ambas | `DepartureChipTests.testLongitudDelTren` · `ModelTests.testNoHayCampoDeOcupacion` · `test_train_length_short_long` | `BoardViewLogicTests.testR5LongitudDelTren` · `BoardViewLogicTests.testR50R5FraseCompletaConViaYLongitud` · `BoardViewLogicTests.testR47R5R10FichaHolgadaYCompacta` · `DecodingTests.testCamposV1DelTablero` · `WidgetTimelineTests.testTextoDelBillete` · `ActivityContentBuilderTests.testMinutosLargos` · `test_board.py::test_train_length_short_long` · `test_escenarios.py::test_R5_longitud_del_tren_y_sin_ocupacion` (que no exista campo de ocupación solo lo afirma el servidor; en iOS no hay `ModelTests`) |
| R6 | Minutos largos formateados: 106 → «1h46» | iOS | `FormatTests.testMinutosLargos1h46` | `BoardViewLogicTests.testR6MinutosLargos` · `BoardViewLogicTests.testR50R6R14ConcordanciaEnHorasYRetraso` · `BoardViewLogicTests.testR50R6DuracionesYAntiguedadDichas` · `BoardViewLogicTests.testR56R6AlternativasEnEspanol` · `RoutesLogicTests.testR6R56TextosDelPlanificador` · `SettingsLogicTests.testR6TiempoMaximoDelTrayecto` · `ActivityContentBuilderTests.testMinutosLargos` · `ActivityContentBuilderTests.testMomentosDeLaCifra` · `WidgetTimelineTests.testUnaHoraOMasEsHoraFija` · `DecodingTests.testPreviewDataCubreLosCasos` · `TableroUITests.testBusAUnaHoraCuarentaYSeis` · `test_escenarios.py::test_R6_minutos_largos_llegan_enteros` |
| R7 | Cuota 1000/día: refresco de 30 s solo mirando o en modo trayecto; si no, en segundo plano el bucle se para | iOS | `BoardStoreTests.testBucleSoloEnPrimerPlanoYTablero` · `ModoTrayectoTests.testRefrescoEnSegundoPlanoSoloEnTrayecto` | `BoardStoreTests.testBucleSoloVisibleOEnTrayecto` · `TripControllerTests.testRefrescoEnSegundoPlanoSoloEnTrayecto` · `BoardViewLogicTests.testR7BucleSoloEnTableroYTrayecto` · `BoardViewLogicTests.testR7NuncaMenosDeTreintaSegundos` · `BoardViewLogicTests.testR7TironesConTresSegundosDeSeparacion` · `BoardViewLogicTests.testR7AhorrandoCuotaDiceSuRitmo` · `BoardStoreTests.testRitmoDelServidor` · `SettingsLogicTests.testR46R7CuotaJustaConSusNiveles` (el enganche con `scenePhase` de SwiftUI no se prueba; sí `setSceneActive`, `setVisible` y `setTripMode` del store) |
| R8 | Avisos en francés con «traduciendo»; se sustituyen al llegar la traducción; nunca se espera | ambas | `LegStatusTests.testFrancesMientrasTraduce` · `DisruptionNoticeTests.testEtiquetaTraduciendo` · `test_board_no_espera_traduccion` | `BoardViewLogicTests.testR8FrancesMientrasTraduce` · `BoardViewLogicTests.testR8TraducidoSustituyeAlFrances` · `BoardViewLogicTests.testR8MedioTraducidoSigueTraduciendo` · `DecodingTests.testPreviewDataCubreLosCasos` · `TableroUITests.testTableroCincoTramos` · `TableroUITests.testDetalleDelTramoCortado` · `TableroUITests.testLineaCortada` · `test_translate.py::test_board_no_espera_traduccion` · `test_translate.py::test_board_no_espera_traduccion_por_la_api` · `test_escenarios.py::test_R8_aviso_en_frances_sin_esperar_a_la_traduccion` · `test_v1.py::test_flujo_completo_emparejar_y_tablero` |
| R9 | Nunca se borra la pantalla: último tablero bueno con su antigüedad, guardado en disco | iOS | `BoardStoreTests.testErrorConservaTablero` · `BoardCacheTests.testPrimeraAperturaEnseñaCache` · `BoardStoreTests.testCambioDeRutaNoVaciaPantalla` | `BoardStoreTests.testErrorConservaTablero` · `BoardStoreTests.testPrimeraAperturaEnsenaCache` · `BoardStoreTests.testCambioDeRutaNoVaciaPantalla` · `BoardStoreTests.testTramoCaidoConservaSusSalidas` · `BoardViewLogicTests.testR9SinConexionConservaElTableroYDiceSuEdad` · `BoardViewLogicTests.testR9ServidorSinClaveDisenado` · `BoardViewLogicTests.testR9TramoConservadoDiceSuAntiguedad` · `BoardCacheTests.testRestauraHoraDeLlegada` · `StatsLogicTests.testR11UnFalloDeLaPrevisionSeCallaYNoBorraNada` · `TableroUITests.testSinConexionConservaElUltimoTablero` · `TableroUITests.testDatoViejoSeDiceYElTableroSigue` · `CapturasUITests.testCapturas3EstadosSinDatos` · `test_board.py::test_estaciones_caidas_con_avisos_no_es_todo_fallido` · `test_v1.py::test_v1_board_nunca_hueco` |
| R10 | Vía probable ≠ real: caja sólida «Vía» frente a recuadro punteado «probable» | iOS | `PlatformBadgeTests.testRealSolidaProbablePunteada` · `SnapshotTests.testViaRealYProbableEnGris` | `BoardViewLogicTests.testR10RealManda_ProbableSoloSinReal` · `BoardViewLogicTests.testR10R50EtiquetasDeLaVia` · `BoardViewLogicTests.testR47R5R10FichaHolgadaYCompacta` · `TableroUITests.testViaProbableYSuExplicacion` · `TableroUITests.testViaRealEnElBillete` · `WidgetTimelineTests.testLaProbableSigueProbable` · `ActivityContentBuilderTests.testViaRealYProbableDelTablero` · `ActivityContentBuilderTests.testMomentosDeLaCifra` · `DecodingTests.testPreviewDataCubreLosCasos` · `test_escenarios.py::test_R10_via_probable_frente_a_real` · `test_platform.py::test_annotate_solo_sin_via_real` · parcial: la palabra («Vía» frente a «probable») y que la real mande están cubiertas; la forma (caja sólida frente a recuadro punteado) no tiene test: capturas 15, 16 y 41 de `CapturasUITests` y, en gris y tintado, docs/pruebas-iphone.md §8 y §10. |
| R11 | El acierto de la previsión sale solo de `/api/platform-model`; nunca se pregunta al usuario | ambas | `StatsTests.testAciertoSoloDePlatformModel` · `UITests.testNingunaPreguntaDeAcierto` · `test_platform_model_accuracy` | `StatsLogicTests.testR11AciertoSoloDePlatformModel` · `StatsLogicTests.testR11UnFalloDeLaPrevisionSeCallaYNoBorraNada` · `DecodingTests.testSalud` · `DecodingTests.testEstadisticas` · `RutasYAjustesUITests.testHistorial` · `test_platform.py::test_platform_model_accuracy` · `test_v1.py::test_stats_por_defecto_y_platform_model` · parcial: no existe `UITests.testNingunaPreguntaDeAcierto`; que ninguna pantalla pregunte al usuario no lo afirma ningún test (se apoya en que `StatsText.accuracy` solo lee la respuesta de `/platform-model` y en que los tests de interfaz del Historial no ven ninguna pregunta). |
| R12 | Colores de línea de `line_color`; únicos saturados con los estados; contraste garantizado en distintivos | ambas | `LineColorTests.testContrasteAAEnDistintivos` · `LineColorTests.testTodasLasLineasIDFM` · `test_line_color_hex_6` | parcial: `test_v1.py::test_line_color_hex_6` (el servidor guarda `line_color` como hex de 6 en mayúsculas o «»); en iOS no existe ningún test de `LineColor` (ni `LineColorTests.testContrasteAAEnDistintivos` ni `testTodasLasLineasIDFM`): el contraste de la tinta en los distintivos con la lista de colores de IDFM y que no haya otros saturados siguen sin test. |
| R13 | `PreviewData` son bancos de prueba: conservar y ampliar los 8 casos | ambas | `DecodingTests.testTodosLosPreviewData` · `PreviewDataTests.testCubreLosOchoCasos` · `test_mock_prim_casos_previewdata` | `DecodingTests.testTodosLosPreviewData` · `DecodingTests.testPreviewDataCubreLosCasos` · `DecodingTests.testCamposV1DelTablero` · `test_contrato_v1.py::test_board_v1_forma_con_todos_los_casos` (cada escenario de `tests/scenarios.py` por `/api/v1/board`) · `test_escenarios.py::test_casa_trabajo_cinco_tramos` y el resto de `test_escenarios.py` (los mocks de PRIM reproducen los casos: tramo vacío, línea cortada, aviso sin traducir, vía que aparece, vía probable, bus a 106, tren en el andén, destinos mezclados) |
| R14 | Retraso solo si existe y ≠ 0, con signo | iOS | `DepartureTests.testRetrasoCeroNoSePinta` · `FormatTests.testRetrasoConSigno` | `BoardViewLogicTests.testR14RetrasoCeroNoSePintaYConSigno` · `BoardViewLogicTests.testR14FichaSinRetrasoCero` · `BoardViewLogicTests.testR50R14AdelantoEnSingular` · `BoardViewLogicTests.testR50R6R14ConcordanciaEnHorasYRetraso` · `DecodingTests.testPreviewDataCubreLosCasos` · `ActivityContentBuilderTests.testRetrasoSoloConHoraTeorica` · `WidgetTimelineTests.testRetrasoSoloConHoraTeorica` · `TableroUITests.testTableroCincoTramos` |
| R15 | «En andén» (confirmado) ≠ «ya» (contador a cero) | iOS | `FormatTests.testEnAndenDistintoDeYa` | `BoardViewLogicTests.testR15EnAndenDistintoDeYa` · `BoardViewLogicTests.testR50R15ParadoEnElAndenSinHora` · `DecodingTests.testPreviewDataCubreLosCasos` · `ActivityContentBuilderTests.testEnAndenNoEsYa` · `ActivityContentBuilderTests.testMomentosDeLaCifra` · `WidgetTimelineTests.testEnAndenSoloConDatoReciente` · `TableroUITests.testTableroCincoTramos` · `test_escenarios.py::test_tren_parado_en_el_anden` |
| R16 | Ritmo «¿corro o no corro?»: ≤ 3 min, ≤ 8 min, > 8 min | iOS | `FormatTests.testRitmoPorMinutos` | `BoardViewLogicTests.testR16RitmoCorroAndoConCalma` · `BoardViewLogicTests.testR15EnAndenDistintoDeYa` («ya» corre; «En andén» sin ritmo) (que en compacto el icono vaya solo en la primera salida es vista y no tiene test) |
| R17 | La antigüedad cuenta desde la llegada al teléfono, más `data_age` | iOS | `BoardTests.testAntiguedadDesdeLlegadaAlTelefono` | `BoardStoreTests.testAntiguedadDesdeLlegadaAlTelefono` · `BoardViewLogicTests.testR17R18EnDirectoConSuAntiguedad` · `DecodingTests.testAntiguedadYDatoViejo` · `BoardCacheTests.testRestauraHoraDeLlegada` · `BoardStoreTests.testPrimeraAperturaEnsenaCache` · `WidgetTimelineTests.testAntiguedadSiempreALaVista` · `TableroUITests.testTableroCincoTramos` |
| R18 | Antigüedad dicha «hace N s / min / h» | iOS | `FormatTests.testAntiguedadSegundosMinutosHoras` | `BoardViewLogicTests.testR17R18EnDirectoConSuAntiguedad` («hace 10 s») · `BoardViewLogicTests.testR19ViejoA90Segundos` («hace 1 min») · `BoardViewLogicTests.testR19StaleDelServidorApagaYDataAgeNo` («hace 5 min») · `BoardViewLogicTests.testR9SinConexionConservaElTableroYDiceSuEdad` · `BoardViewLogicTests.testR50R6DuracionesYAntiguedadDichas` (voz: segundos, minutos y horas) · `WidgetTimelineTests.testAntiguedadSiempreALaVista` · parcial: «hace N h» solo se comprueba en la versión hablada (`BoardSpeech.age(7200)`), no en el texto de la píldora; tampoco los bordes 59,4 s, 3599 s y 3600 s. |
| R19 | Dato viejo (stale del servidor o > 90 s sin recibir tablero): se apaga el tablero entero | ambas | `BoardTests.testViejoA90Segundos` · `SnapshotTests.testTableroViejoApagado` · `test_board_stale_tres_refrescos` | `BoardViewLogicTests.testR19ViejoA90Segundos` · `BoardViewLogicTests.testR19StaleDelServidorApagaYDataAgeNo` · `BoardStoreTests.testViejoA90Segundos` · `DecodingTests.testAntiguedadYDatoViejo` · `BoardViewLogicTests.testR2PlatformNewDelServidorYNadaConElDatoViejo` (apagado: no late) · `TableroUITests.testDatoViejoSeDiceYElTableroSigue` · `test_escenarios.py::test_R19_umbral_de_stale` · `test_escenarios.py::test_R65_si_prim_cae_se_sirve_la_copia_con_su_edad` · `test_prim.py::test_degraded_solo_mira_el_tablero` (el propuesto `test_board_stale_tres_refrescos` no existe: lo sustituye `test_R19_umbral_de_stale`) |
| R20 | La caché en disco guarda la hora real de llegada | iOS | `BoardCacheTests.testRestauraHoraDeLlegada` | `BoardCacheTests.testRestauraHoraDeLlegada` · `BoardCacheTests.testFormatoEnDisco` (`received_at` aparte) · `BoardStoreTests.testPrimeraAperturaEnsenaCache` |
| R21 | Decodificación tolerante: un JSON raro degrada, no revienta | iOS | `DecodingTests.testCamposAusentesNulosOTipoErroneo` | `DecodingTests.testCamposAusentesNulosOTipoErroneo` · `DecodingTests.testEnumeradosDesconocidos` · `DecodingTests.testRutaRara` · `DecodingTests.testTableroSinServidorNiRuta` · `DecodingTests.testPlanVacioYMapaMinimo` · `DecodingTests.testErrorV1YLegado` · `BoardCacheTests.testSinFicheroOFicheroRoto` |
| R22 | Tren como cadena o número; `age` antiguo = `data_age` | iOS | `DecodingTests.testTrenNumeroOCadena` · `DecodingTests.testAgeLegadoComoDataAge` | `DecodingTests.testTrenNumeroOCadena` · `DecodingTests.testAgeLegadoComoDataAge` · `test_board.py::test_train_numbers_null_no_revienta` (el servidor también acepta el número de tren como entero) |
| R23 | Identidad estable de cada salida entre refrescos | iOS | `DepartureTests.testIdEstableSinJid` | `DecodingTests.testIdEstable` · `BoardStoreTests.testTramoCaidoConservaSusSalidas` (los ids conservados son los mismos entre refrescos) |
| R24 | Tramo sin sentido con varios destinos: cada salida dice a dónde va | iOS | `LegTests.testMezclaDestinos` · `DepartureChipTests.testDestinoSoloSiMezcla` | `BoardViewLogicTests.testR24DestinoSoloSiMezcla_TambienEnCompacto` · `BoardViewLogicTests.testR24UnSoloDestinoNoEsMezcla` · `BoardViewLogicTests.testR47R5R10FichaHolgadaYCompacta` (con sentido: «dirección …» y sin destino en la ficha) · `DecodingTests.testPreviewDataCubreLosCasos` · `ActivityContentBuilderTests.testDestinosMezclados` · `WidgetTimelineTests.testMetroSinViaYDestinosMezclados` · `test_escenarios.py::test_R24_destinos_mezclados` · `test_board.py::test_direccion_sin_tildes_ni_espacios_raros` |
| R25 | Tramo vacío: «Sin circulación» si está cortada, «Servicio finalizado» si no | iOS | `LegCardTests.testTramoVacioCortadoVsFinalizado` | `BoardViewLogicTests.testR25TramoVacioCortadoVsFinalizado` · `ActivityContentBuilderTests.testLineaCortada` · `ActivityContentBuilderTests.testServicioFinalizado` · `WidgetTimelineTests.testLineaCortadaYServicioFinalizado` · `TableroUITests.testTableroCincoTramos` («Servicio finalizado») · `TableroUITests.testLineaCortada` («Sin circulación») · `TableroUITests.testDetalleDelTramoCortado` · `test_escenarios.py::test_R25_tramo_vacio_cortado_frente_a_finalizado` · `test_escenarios.py::test_R25_tramo_vacio_sin_avisos_es_servicio_finalizado` |
| R26 | Una estación que falla no tumba el tablero; el fallo va al pie | ambas | `BoardViewTests.testErroresDeEstacionEnPie` · `test_board_error_estacion_parcial` | `BoardViewLogicTests.testR26EstacionCaidaNoTumbaElTablero` · `BoardViewLogicTests.testR26ErroresDeEstacionEnPie` · `BoardStoreTests.testTramoCaidoConservaSusSalidas` · `CapturasUITests.testCapturas1Tablero` (capturas 26 y 27) · `test_escenarios.py::test_R26_una_estacion_caida_no_tumba_el_tablero` · `test_board.py::test_resiliencia_tramo_roto_no_tumba_el_tablero` · `test_board.py::test_estaciones_caidas_con_avisos_no_es_todo_fallido` · `test_v1.py::test_tablero_parcial_da_200_con_errors` · `test_collector.py::test_recolector_estacion_caida_no_para_el_resto` |
| R27 | El aviso va dentro de la tarjeta de su tramo; en el detalle, español y francés | iOS | `DisruptionNoticeTests.testAvisoEnSuTramo` · `LegDetailTests.testAvisoBilingue` | `BoardViewLogicTests.testR27DosMensajesEnLaTarjetaYLosDosIdiomasEnElDetalle` · `BoardViewLogicTests.testR8FrancesMientrasTraduce` · `TableroUITests.testTableroCincoTramos` (el aviso dentro de `tablero.tramo.3`) · `TableroUITests.testDetalleDelTramoCortado` («Original en francés») · `CapturasUITests.testCapturas4DetalleYAlternativas` (captura 42, detalle bilingüe) |
| R28 | Obras con fecha futura no encienden el semáforo; se cuentan aparte | ambas | `test_line_status_planificados_no_cuentan` · `LegDetailTests.testCuentaAvisosPlanificados` | `BoardViewLogicTests.testR28ObrasFuturasNoEnciendenElAvisoYSeCuentan` · `DecodingTests.testPreviewDataCubreLosCasos` · `test_board.py::test_line_status_planificados_no_cuentan` · `test_board.py::test_aviso_caducado_y_futuro` · `test_frdate.py::test_fecha_futura_es_planificado` · `test_contrato_v1.py::test_aviso_traducido_y_planned_segun_el_contrato` |
| R29 | Alternativas solo al pedirlas, nunca en el refresco | iOS | `BoardStoreTests.testRefrescoNoPideAlternativas` | `BoardViewLogicTests.testR29AlternativasSoloAlPedirlas` · `BoardViewLogicTests.testR29BotonDeAlternativasNoPideNada` · `AlternativasUITests.testHojaConOpcionesYNoSirve` (se pide al abrir la hoja) · `test_planner.py::test_alternatives_usable_false` (sin línea tocada ni se pregunta a Navitia) · parcial: el propuesto `BoardStoreTests.testRefrescoNoPideAlternativas` no existe; que N refrescos hagan 0 llamadas a `/alternatives` no lo afirma ningún test (se apoya en que `BoardStore` no conoce esa llamada: vive en `BoardAlternativesModel`). |
| R30 | Alternativa que pasa por otra línea caída: «No sirve»; búsqueda forzable | ambas | `AlternativesTests.testNoUsableSeMarca` · `AlternativesTests.testBuscarDeTodasFormasForce` · `test_alternatives_usable_false` | `BoardViewLogicTests.testR30NoUsableSeMarca` · `BoardViewLogicTests.testR30BuscarDeTodasFormasForce` · `BoardViewLogicTests.testR30FalloDeRedYCancelacion` · `DecodingTests.testAlternativasYPlan` · `AlternativasUITests.testHojaConOpcionesYNoSirve` · `AlternativasUITests.testSinOpcionesYBuscarDeTodasFormas` · `test_planner.py::test_alternatives_usable_false` · `test_v1.py::test_alternativas` |
| R31 | Buscadores: mínimo 2 caracteres y 350 ms de espera | iOS | `SearchTests.testDebounce350msYMinimo2` | `RoutesLogicTests.testR31MinimoDosCaracteres` · `RoutesLogicTests.testR31Debounce350msYMinimo2` · `RoutesLogicTests.testR31BuscadorDeParadasNoGastaCuotaConUnaLetra` · `RoutesLogicTests.testR31FalloDelBuscadorSeDice` · `RutasYAjustesUITests.testPlanificadorSeAbreYSeCierra` · `test_v1.py::test_buscadores_400` (el servidor también rechaza menos de 2 caracteres) |
| R32 | El sentido se elige de los que circulan ahora; sin elegir = todos, avisado | ambas | `LegBuilderUITests.testSentidoSeEligeDeLista` · `test_directions_observadas` | `RoutesLogicTests.testR32SentidoSeEligeDeLista` · `CapturasUITests.testCapturas6RutasYPlanificador` (paso del sentido, capturas 70 y 71) · `test_v1.py::test_buscadores` (`/stops/{id}/directions` devuelve los destinos que circulan) · `test_board.py::test_direccion_sin_tildes_ni_espacios_raros` (`observed_destinations`; sin sentido se ven todos) · `test_planner.py::test_resolve_direction` (el propuesto `test_directions_observadas` no existe con ese nombre) |
| R33 | Guardar desde el planificador: los tramos sin sentido se dicen | ambas | `SavePlanTests.testAvisaTramosSinSentido` · `test_from_plan_without_direction` | `RoutesLogicTests.testR33AvisaTramosSinSentido` · `RoutesLogicTests.testR33R34R35MetaAlGuardarDesdeElPlanificador` · `DecodingTests.testAlternativasYPlan` · `TrajetAPITests.testOperacionesDeRutas` (`without_direction` de `/routes/from-plan`) · `CapturasUITests.testCapturas6RutasYPlanificador` («Guardada, pero con un aviso», captura 81) · `test_planner.py::test_from_plan_without_direction` |
| R34 | «Llegar a» ≠ «salir a»; la API solo entiende `arrival`/`departure` | ambas | `TrajetAPITests.testPlanModoArrivalDeparture` · `test_plan_arrival_prefiere_salir_tarde` | `TrajetAPITests.testPlanModoArrivalDeparture` · `RoutesLogicTests.testR34PlanModoArrivalDeparture` · `RoutesLogicTests.testR34PlanSinOpcionesY404` · `RoutesLogicTests.testF42RotuloDeLaBusquedaHecha` · `RoutesLogicTests.testR33R34R35MetaAlGuardarDesdeElPlanificador` · `test_planner.py::test_plan_arrival_prefiere_salir_tarde` (un modo que no es ninguno de los dos: 400) |
| R35 | El horario se guarda y se enseña como se definió | iOS | `RoutesTests.testEtiquetaHorario` | `RoutesLogicTests.testR35EtiquetaHorario` · `RoutesLogicTests.testR33R34R35MetaAlGuardarDesdeElPlanificador` · `RoutesLogicTests.testRouteInputSinCambiosEsLaMismaRuta` · `DecodingTests.testRutasYEtiquetas` · `RutasYAjustesUITests.testListaYEditorDeRutas` · `test_board.py::test_ruta_guarda_modo_hora_duracion_y_franja` · `test_planner.py::test_guardar_como_llego_a_las_9` |
| R36 | Días: 0 = lunes; etiquetas en español | iOS | `RoutesTests.testEtiquetaDias` | `RoutesLogicTests.testR36EtiquetaDias` · `RoutesLogicTests.testR36RutaNuevaLunesAViernesLlegoALasNueve` · `RoutesLogicTests.testR36R50TarjetaDeRutaParaVoiceOver` · `RoutesLogicTests.testRouteInputFranjaSinHoraYDiasOrdenados` · `DecodingTests.testRutasYEtiquetas` · `RutasYAjustesUITests.testListaYEditorDeRutas` · `RutasYAjustesUITests.testNuevaRutaAManoYCancelar` |
| R37 | La ruta que toca la decide el servidor por día y franja | servidor | `test_pick_active_route_mas_concreta` · `test_pick_active_route_sin_franja` · `BoardStoreTests.testSinFijarNoMandaRouteId` | `test_board.py::test_pick_active_route_mas_concreta` · `test_board.py::test_pick_active_route_sin_franja` · `test_board.py::test_pick_active_route_cruza_medianoche` · `TrajetAPITests.testParametrosDelTablero` (`route_id` solo con ruta fijada; hace lo del propuesto `BoardStoreTests.testSinFijarNoMandaRouteId`) · `BoardStoreTests.test404RutaBorradaVuelveAAutomatica` · `BoardViewLogicTests.testR37RotuloRutaQueTocaFrenteAElegida` · `TableroUITests.testTableroCincoTramos` («La que toca ahora») |
| R38 | «Llego a» / «salgo a» se traducen a una franja | servidor | `test_derive_window_llegada` · `test_derive_window_salida` | `test_board.py::test_derive_window_salida` · `test_board.py::test_derive_window_llegada` · `test_board.py::test_derive_window_franja_tal_cual` · `test_board.py::test_ruta_guarda_modo_hora_duracion_y_franja` · `test_planner.py::test_guardar_como_llego_a_las_9` · `RoutesLogicTests.testR38FranjaDerivada` · `RoutesLogicTests.testR38TextoDeSalgoACuentaLaMediaHoraTrasLlegar` (la discrepancia del texto del editor queda resuelta y probada) |
| R39 | Cambiar de ruta o tocar rutas refresca al momento | iOS | `BoardStoreTests.testSeleccionRefrescaYa` · `BoardStoreTests.testInvalidarTrasGuardar` | `BoardStoreTests.testSeleccionRefrescaYa` · `BoardStoreTests.testBorrarLaRutaFijada` · `RoutesStoreTests.testBorrarAvisaAlTablero` · `BoardStoreTests.testCambioDeRutaNoVaciaPantalla` · parcial: solo borrar una ruta tiene test de que avise al tablero; crear y editar (desde el editor y desde el planificador) no lo tienen (el propuesto `BoardStoreTests.testInvalidarTrasGuardar` no existe). |
| R40 | Los refrescos automáticos no engordan el historial | ambas | `BoardStoreTests.testRefrescoAutomaticoSinHistorial` · `test_board_log_history_false` | `BoardStoreTests.testRefrescoAutomaticoSinHistorial` · `BoardStoreTests.testBucleSoloVisibleOEnTrayecto` (el primer refresco del bucle va sin historial) · `TrajetAPITests.testParametrosDelTablero` · `TripControllerTests.testRefrescoEnSegundoPlanoSoloEnTrayecto` · `test_board.py::test_board_log_history_false` · `test_board.py::test_record_history_10min` |
| R41 | Rutas: una sola copia compartida y una sola carga | iOS | `RoutesStoreTests.testLoadIfNeededUnaVez` | `RoutesStoreTests.testLoadIfNeededUnaVez` · `RoutesStoreTests.testFalloNoCuentaComoCargado` · `RutasYAjustesUITests.testListaYEditorDeRutas` (la lista es la misma que el selector del tablero) |
| R42 | Dos direcciones en orden, se recuerda la buena; un error HTTP no salta | iOS | `TrajetAPITests.testOrdenDeCandidatos` · `TrajetAPITests.testErrorHTTPNoSaltaDeDireccion` · `TrajetAPITests.testFalloDeRedSalta` | `TrajetAPITests.testOrdenDeCandidatos` · `TrajetAPITests.testErrorHTTPNoSaltaDeDireccion` · `TrajetAPITests.testFalloDeRedSalta` · `TrajetAPITests.testRespuestaIlegible` · `ServerConfigTests.testOrdenDeCandidatos` · `ServerConfigTests.testEditarOlvidaLaPreferida` · `PairingStoreTests.testEmparejaPorLaDireccionQueResponde` · `PairingStoreTests.testNadieResponde` · con red de verdad: docs/pruebas-iphone.md §11 |
| R43 | Timeouts cortos (6 s / 12 s) y sin caché HTTP | iOS | `TrajetAPITests.testConfiguracionDeSesion` | `TrajetAPITests.testConfiguracionDeSesion` · con cambios de red durante un trayecto: docs/pruebas-iphone.md §12 |
| R44 | Un 404 de ruta borrada no es «sin red» | ambas | `BoardStoreTests.test404RutaBorradaVuelveAAutomatica` · `test_board_route_id_inexistente_404` | `BoardStoreTests.test404RutaBorradaVuelveAAutomatica` · `BoardStoreTests.testBorrarLaRutaFijada` · `TrajetAPITests.testErroresConCodigo` (`.notFound`) · `DecodingTests.testErrorV1YLegado` · `test_v1.py::test_tablero_ruta_inexistente_404` · `test_v1.py::test_id_enorme_no_da_500` |
| R45 | Permiso de red local; sin él solo funciona Tailscale | iOS | `InfoPlistTests.testTextoRedLocal` · manual «red local» | `SettingsLogicTests.testR45Permisos` (la nota de Ajustes habla de Red local y Tailscale) · `PairingViewLogicTests.testR45ServidorQueNoAparecePistaDeRed` · `SettingsLogicTests.testR61DireccionesYExcepcionDeTailscale` · parcial: el texto de `NSLocalNetworkUsageDescription` del Info.plist no tiene test (no existe `InfoPlistTests.testTextoRedLocal`) y el permiso real solo se prueba en el iPhone: docs/pruebas-iphone.md §2 y §11. |
| R46 | Cuota visible en el pie y en Ajustes; se reinicia a medianoche UTC | ambas | `BoardViewTests.testCuotaEnPie` · `SettingsTests.testCuotaPorEndpoint` · `test_quota_reinicio_utc` | `BoardViewLogicTests.testR46CuotaEnPie` · `BoardViewLogicTests.testR46CuotaAgotadaVuelveAMedianocheUTC` · `SettingsLogicTests.testR46CuotaPorEndpoint` · `SettingsLogicTests.testR46CuotaSeReiniciaAMedianocheUTC` · `SettingsLogicTests.testR46R7CuotaJustaConSusNiveles` · `DecodingTests.testSalud` · `TableroUITests.testTableroCincoTramos` («llamadas hoy») · `test_quota.py::test_dia_utc_nuevo_empieza_de_cero` · `test_quota.py::test_hora_de_paris_no_manda` · `test_quota.py::test_persistida_sobrevive_a_un_reinicio` · `test_admin.py::test_cuota_hoy_e_historial_de_7_dias` |
| R47 | Densidad de las salidas según el número de tramos (1–6) | iOS | `ChipDensityTests.testDensidadPorTramos` | `BoardViewLogicTests.testR47DensidadPorTramos` · `BoardViewLogicTests.testR47R5R10FichaHolgadaYCompacta` · `BoardViewLogicTests.testR24DestinoSoloSiMezcla_TambienEnCompacto` · `DecodingTests.testPreviewDataCubreLosCasos` (bancos de 1, 5 y 6 tramos) · `TableroUITests.testTableroCincoTramos` · `CapturasUITests.testCapturas1Tablero` (capturas 22 y 23, seis tramos compacto) |
| R48 | Minutos primero, en cifras de ancho fijo; la primera salida manda | iOS | `SnapshotTests.testPrimeraSalidaDestacada` · `DepartureChipTests.testTransicionNumerica` | sin test: las cifras de ancho fijo, `contentTransition(.numericText())` y que la primera salida sea la grande son detalles de vista sin test unitario ni de interfaz (no existen `SnapshotTests` ni `DepartureChipTests.testTransicionNumerica`); solo se ven en las capturas (`CapturasUITests.testCapturas1Tablero`) y a mano en docs/pruebas-iphone.md §10. |
| R49 | La vía probable se explica (porcentaje, muestras y motivo) | iOS | `LegDetailTests.testExplicaViaProbable` | `BoardViewLogicTests.testR49ExplicaViaProbable` · `BoardViewLogicTests.testR50R49FraseDeViaProbable` · `BoardViewLogicTests.testR10R50EtiquetasDeLaVia` · `BoardViewLogicTests.testR10RealManda_ProbableSoloSinReal` (solo sin vía real) · `TableroUITests.testViaProbableYSuExplicacion` · `CapturasUITests.testCapturas4DetalleYAlternativas` (captura 41) |
| R50 | VoiceOver: cada salida se lee como una frase completa | iOS | `DepartureChipTests.testEtiquetaAccesible` | `BoardViewLogicTests.testR50R5FraseCompletaConViaYLongitud` · `BoardViewLogicTests.testR50R2FraseDeViaRecienPublicada` · `BoardViewLogicTests.testR50R49FraseDeViaProbable` · `BoardViewLogicTests.testR50R6R14ConcordanciaEnHorasYRetraso` · `BoardViewLogicTests.testR50R15ParadoEnElAndenSinHora` · `BoardViewLogicTests.testR50R14AdelantoEnSingular` · `BoardViewLogicTests.testR50R3MetroSinVia` · `BoardViewLogicTests.testR50SuprimidoYSaleYa` · `BoardViewLogicTests.testR50ModoDesconocidoYSinDestino` · `BoardViewLogicTests.testR50R6DuracionesYAntiguedadDichas` · `BoardViewLogicTests.testR10R50EtiquetasDeLaVia` · `RoutesLogicTests.testR36R50TarjetaDeRutaParaVoiceOver` · `ActivityContentBuilderTests.testVozUnaFrasePorSalida` · `TableroUITests.testTableroCincoTramos` · `TableroUITests.testViaProbableYSuExplicacion` · `TableroUITests.testViaRealEnElBillete` · `TableroUITests.testBusAUnaHoraCuarentaYSeis` (los tests de interfaz encuentran cada frase como un solo elemento) · con VoiceOver de verdad: docs/pruebas-iphone.md §13 |
| R51 | «Reducir movimiento» para latidos y barras | iOS | `AccesibilidadTests.testReducirMovimiento` | sin test: «Reducir movimiento» no aparece en ningún test unitario ni de interfaz (no existe `AccesibilidadTests.testReducirMovimiento`); solo a mano en docs/pruebas-iphone.md §13 (punto «en directo» quieto, anillo fijo en la vía nueva, «próximo en N s» en vez de la barra). |
| R52 | Área táctil mínima de 44 pt | iOS | `AccesibilidadUITests.testAreasTactiles44` | sin test: no hay test de áreas táctiles (no existe `AccesibilidadUITests.testAreasTactiles44`); a mano en docs/pruebas-iphone.md §13 (botones de días de 44 pt con AX3) y a ojo en las capturas. |
| R53 | Estados no felices: esqueleto, vacío que dice qué hacer, «no se llega» solo sin nada guardado | iOS | `BoardViewTests.testEstadosVacioCargaError` | `BoardViewLogicTests.testR53EstadosVacioCargaError` · `BoardViewLogicTests.testR53ErrorDisenadoDiceQueHacer` · `BoardStoreTests.testSinRutasNoEsError` · `TableroUITests.testSinRutasDiceQueHacer` · `CapturasUITests.testCapturas3EstadosSinDatos` («No se llega al servidor» solo con `-demoSinCache`; capturas 30 a 40) (el parpadeo del esqueleto es vista y no tiene test) |
| R54 | Se ve cuándo llega el siguiente dato (barra de 30 s) | iOS | `BoardViewTests.testBarraDeRefresco` | `BoardViewLogicTests.testR54BarraDeRefrescoEnTexto` · `BoardStoreTests.testRitmoDelServidor` (`nextRefreshAt`) · parcial: la barra en sí (la vista que baja durante 30 s) no tiene test; sí el texto «próximo en N s» que la sustituye y el instante del siguiente refresco. |
| R55 | Avisos efímeros (2,4 s), sin diálogos que corten el paso | iOS | `RoutesViewTests.testToastEfimero` | `BoardViewLogicTests.testR55ToastEfimero` (2,4 s; un temporizador viejo no se lleva un aviso nuevo) · `BoardViewLogicTests.testFinDeTrayectoSeDiceSoloSiNoFueAMano` |
| R56 | Formatos en español (coma decimal, meses, horas de Navitia, transbordos) | iOS | `FormatTests.testFormatosEnEspanol` | `StatsLogicTests.testR56DecimalesConComa` · `StatsLogicTests.testR56ResumenConLoQueDicenLosDatos` · `StatsLogicTests.testR56DiasConIncidenciasPorMes` · `BoardViewLogicTests.testR56R6AlternativasEnEspanol` · `RoutesLogicTests.testR6R56TextosDelPlanificador` · `DecodingTests.testAlternativasYPlan` · `DecodingTests.testEstadisticas` · `BoardViewLogicTests.testR49ExplicaViaProbable` («84 %» con espacio) · `RutasYAjustesUITests.testHistorial` («3,4») |
| R57 | Hex de color tolerante y gris de reserva que no miente | iOS | `LineColorTests.testParseHexVariantes` | sin test: `LineColor` (con o sin «#», 3 o 6 dígitos, gris de reserva, tinta blanca sin color) no tiene ningún test en iOS (no existe `LineColorTests.testParseHexVariantes`); el banco `coloresRaros` existe pero `DecodingTests.testPreviewDataCubreLosCasos` solo comprueba que los valores llegan tal cual, y `StatsLogicTests.testLaLineaQueMasFallaSonVecesNoDias` solo el «» de reserva de `StatsText`. El servidor normaliza a 6 cifras (`test_v1.py::test_line_color_hex_6`). |
| R58 | El bundle id `com.ismaeloul.trajet` no cambia nunca | iOS | `AppTests.testBundleIdNoCambia` | sin test: el bundle id vive en `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER: com.ismaeloul.trajet` en los dos esquemas) y no hay `AppTests.testBundleIdNoCambia` ni comprobación en el CI; que reinstalar conserve los datos se prueba a mano: docs/pruebas-iphone.md §1. |
| R59 | El `.xcodeproj` no se versiona: lo genera XcodeGen | iOS | CI: paso `xcodegen generate` de `ios.yml` | sin test propio: lo garantiza el CI (paso `xcodegen generate --spec project.yml` en `.github/workflows/ios.yml`) y `Trajet.xcodeproj/` en `.gitignore`; no es un test de XCTest ni de pytest. |
| R60 | La IPA «lite» no depende de nada que el Apple ID gratuito no dé | iOS | `AppTests.testLiteSinAppGroupNoRompe` | `SettingsLogicTests.testR60ExtrasSegunLaInstalacion` · `WidgetTimelineTests.testSinAppGroupLoDice` · `BoardCacheTests.testHayDondeGuardar` (App Group o Application Support) · CI: `scripts/ci-ipa.sh` (la lite no lleva extensiones ni anuncia Live Activities; la full lleva el App Group) y `.github/workflows/ios.yml` compila el esquema `TrajetLite` · parcial: los tests unitarios corren contra el esquema `Trajet` (full), no contra la lite; que la lite funcione entera se prueba a mano: docs/pruebas-iphone.md §1.2. |
| R61 | Ajustes: las direcciones se guardan al escribir; «Restablecer» olvida la preferida | iOS | `ServerConfigTests.testPersisteAlEscribir` · `ServerConfigTests.testRestablecer` | `ServerConfigTests.testPersisteAlEscribir` · `ServerConfigTests.testRestablecer` · `ServerConfigTests.testEditarOlvidaLaPreferida` · `ServerConfigTests.testNormalizar` · `SettingsLogicTests.testR61PersisteAlEscribirYRestablecer` · `SettingsLogicTests.testR61DireccionesYExcepcionDeTailscale` · `RutasYAjustesUITests.testAjustesSeAbrenYSeCierran` · a mano: docs/pruebas-iphone.md §11 |
| R62 | Las líneas de una parada llegan ordenadas por modo; la app no reordena | servidor | `test_lines_orden_por_modo` | `test_idfm.py::test_lines_orden_por_modo` · `test_idfm.py::test_lines_orden_por_modo_en_la_api` · `test_v1.py::test_buscadores` · `RoutesLogicTests.testR62LasLineasNoSeReordenan` |

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
| R63 | PRIM se autentica con la cabecera `apikey`; Navitia vive en `/marketplace/v2/navitia` | `app/prim.py:4-5, 23-25, 71` | `test_prim_cabecera_apikey_y_base` | `test_prim.py::test_prim_cabecera_apikey_y_base` · `test_prim.py::test_validate_key_con_el_prim_falso` (las tres rutas, con la clave nueva) |
| R64 | Una sola llamada a stop-monitoring por **estación** (StopArea padre), aunque varios tramos salgan de ella | `app/prim.py:9-10`; `app/board.py:371-372` | `test_board_una_llamada_por_estacion` | `test_legacy.py::test_tablero_legacy_una_llamada_por_estacion` · `test_escenarios.py::test_casa_trabajo_cinco_tramos` (5 estaciones, 5 llamadas) · `test_v1.py::test_flujo_completo_emparejar_y_tablero` (la J y el metro comparten Saint-Lazare: 3 llamadas para 4 tramos) · `test_collector.py::test_collector_objetivos` (dos tramos de la misma estación, una entrada) (el propuesto `test_board_una_llamada_por_estacion` no existe con ese nombre) |
| R65 | Si PRIM falla y hay copia, se sirve la copia con su **edad real**; nunca pantalla vacía | `app/prim.py:84-123` | `test_prim_fallo_sirve_copia_con_edad` | `test_prim.py::test_prim_fallo_sirve_copia_con_edad` · `test_escenarios.py::test_R65_si_prim_cae_se_sirve_la_copia_con_su_edad` · `test_board.py::test_resiliencia_api_caida_copia_con_edad_y_se_recupera` · `test_quota.py::test_sin_cuota_no_se_llama` |
| R66 | Peticiones simultáneas a la misma clave de caché = **una** llamada (lock por clave) | `app/prim.py:96-100` | `test_prim_lock_una_llamada` | `test_prim.py::test_prim_lock_una_llamada` · `test_escenarios.py::test_R66_peticiones_simultaneas_una_sola_llamada` · `test_board.py::test_resiliencia_simultaneas_una_sola_llamada` |
| R67 | TTL de cada estación según lo cerca que esté su próximo paso (20/30/90/300/600 s) | `app/board.py:337-354` | `test_station_ttl_por_cercania` | `test_board.py::test_station_ttl_cada_tramo_de_la_tabla` · `test_escenarios.py::test_R67_cada_estacion_a_su_ritmo` · `test_escenarios.py::test_R19_umbral_de_stale` (el propuesto `test_station_ttl_por_cercania` no existe con ese nombre) |
| R68 | Aviso con «trafic (est) interrompu» y variantes = línea **interrumpida**, no solo perturbada | `app/board.py:21-33` | `test_interrumpido_con_copula` | `test_board.py::test_interrumpido_con_copula` · `test_board.py::test_perturbado_no_es_interrumpido` · `test_v1.py::test_flujo_completo_emparejar_y_tablero` · `test_prim.py::test_respuesta_real_de_prim_pasa_por_el_tablero` (se salta si falta la captura real) |
| R69 | Aviso caducado (`ValidUntilTime` pasado) no cuenta; aviso con inicio futuro va a `planned` | `app/board.py:167-169, 180-182` | `test_aviso_caducado_y_futuro` | `test_board.py::test_aviso_caducado_y_futuro` · `test_board.py::test_avisos_hoy_es_la_fecha_de_paris` · `test_frdate.py::test_fecha_futura_es_planificado` · `test_frdate.py::test_fecha_de_hoy_o_pasada_es_activo` · `test_frdate.py::test_jusqua_antes_de_la_fecha_es_activo` · `test_frdate.py::test_hoy_es_el_de_paris` · `test_contrato_v1.py::test_aviso_traducido_y_planned_segun_el_contrato` |
| R70 | La línea de un aviso sale de `LineRef` **o** de `IDFM.Cnnnnn` en `ItemIdentifier` | `app/idfm.py:44-57` | `test_lineas_en_mensaje` | `test_idfm.py::test_lineas_en_mensaje` · `test_idfm.py::test_lineas_en_mensaje_lineref_suelto_o_texto` · `test_idfm.py::test_lineas_en_mensaje_con_campos_raros_no_revienta` |
| R71 | Una salida que se fue hace más de 1 min no se enseña; los minutos nunca son negativos | `app/board.py:249-251, 276` | `test_salida_pasada_y_minutos` | `test_board.py::test_salida_pasada_y_minutos` · `test_escenarios.py::test_R71_salida_pasada_fuera_y_minutos_nunca_negativos` · `test_prim.py::test_respuesta_real_de_prim_pasa_por_el_tablero` |
| R72 | Destinos comparados sin tildes, guiones raros ni espacios finos/duros | `app/idfm.py:89-106` | `test_norm_text_destinos` | `test_idfm.py::test_norm_text_destinos` · `test_board.py::test_direccion_sin_tildes_ni_espacios_raros` · `test_planner.py::test_resolve_direction` · `test_platform.py::test_sin_numero_de_tren_cae_a_la_hora_y_normaliza_el_destino` |
| R73 | Vía real solo si es una vía: fuera `unknown`, vacío y nombres de estación de París | `app/idfm.py:69-86` | `test_real_platform` | `test_idfm.py::test_real_platform` · `test_escenarios.py::test_R2_sin_via_no_hay_hueco` («unknown» → null) · `test_prim.py::test_respuesta_real_de_prim_pasa_por_el_tablero` |
| R74 | `platform_new` se enciende cuando aparece la vía de un viaje que no la tenía | `app/board.py:264-272` | `test_board_platform_new_al_aparecer` | `test_board.py::test_board_platform_new_al_aparecer` · `test_escenarios.py::test_R2_R74_via_que_aparece` · `test_board.py::test_extract_departures_remember_false_no_toca_la_memoria` · `test_collector.py::test_recolector_no_toca_la_via_nueva` |
| R75 | Previsión de vía: ≥ 3 observaciones y mayoría **estricta** (> 50 %); misión > hora teórica > línea; laborable y fin de semana aparte | `app/platform.py:29-33, 123-182` | `test_prevision_umbral_niveles_tipo_dia` | `test_platform.py::test_prevision_umbral_niveles_tipo_dia` · `test_platform.py::test_prevision_linea_sin_mayoria_no_se_pinta` · `test_platform.py::test_el_mismo_tren_varios_dias` · `test_platform.py::test_sin_datos_no_se_inventa_nada` · `test_platform.py::test_sin_numero_de_tren_cae_a_la_hora_y_normaliza_el_destino` |
| R76 | El acierto se puntúa **sin** los datos de hoy (no se hace trampa) | `app/platform.py:96-120` | `test_puntuacion_sin_trampa` | `test_platform.py::test_puntuacion_sin_trampa` · `test_platform.py::test_acierto_por_tren` · `test_platform.py::test_tablero_puntua_aunque_la_observacion_ya_exista` · `test_platform.py::test_recolector_primero_tambien_puntua` |
| R77 | Solo se aprenden las estaciones de las rutas guardadas; los modos sin vía no se sondean | `app/collector.py:50-53, 91-115` | `test_collector_objetivos` | `test_collector.py::test_collector_objetivos` · `test_collector.py::test_collector_solo_pide_las_estaciones_de_mis_rutas` · `test_collector.py::test_franja_solo_decide_el_ritmo` |
| R78 | El recolector nunca toca las 320 llamadas reservadas a la pantalla, no muestrea de 01:00 a 05:00 y va entre 120 y 1800 s | `app/collector.py:31-48, 126-156` | `test_plan_interval` | `test_collector.py::test_plan_interval` · `test_collector.py::test_recolector_respeta_la_reserva_y_la_noche` · `test_collector.py::test_ritmo_se_adapta_a_la_cuota` · `test_collector.py::test_formula_hasta_la_medianoche_utc` · `test_quota.py::test_recolector_vuelve_a_aprender_tras_medianoche` |
| R79 | Alternativas: solo con línea tocada o `force`; excluyen las líneas tocadas; una alternativa con línea interrumpida no es usable | `app/main.py:230-336` | `test_alternatives_usable_false` | `test_planner.py::test_alternatives_usable_false` · `test_v1.py::test_alternativas` |
| R80 | Traducción: el francés nunca se pierde; se traduce entero; una vez por texto (caché); el tablero nunca espera al modelo | `app/translate.py:9-17, 141-172` | `test_board_no_espera_traduccion` | `test_translate.py::test_traduccion_entera_una_vez_por_texto` · `test_translate.py::test_fallo_de_ollama_deja_el_frances_y_no_se_recuerda` · `test_translate.py::test_board_no_espera_traduccion` · `test_translate.py::test_board_no_espera_traduccion_por_la_api` · `test_translate.py::test_sin_ollama_configurado_no_se_llama` · `test_escenarios.py::test_R8_aviso_en_frances_sin_esperar_a_la_traduccion` |
| R81 | Planificador: los itinerarios solo a pie se descartan; «llegar a» prefiere la salida más tardía; una hora ya pasada es mañana | `app/planner.py:22-24, 102-107, 202-219` | `test_plan_arrival_prefiere_salir_tarde` | `test_planner.py::test_parse_journeys_orden_a_pie_y_repetidos` · `test_planner.py::test_plan_arrival_prefiere_salir_tarde` · `test_planner.py::test_when_param_hora_pasada_es_manana` · `test_planner.py::test_coordenadas_de_la_respuesta_real_de_navitia` (se salta si falta la respuesta real) |
| R82 | Historial: como mucho una fila cada 10 min por ruta | `app/board.py:453-460` | `test_record_history_10min` | `test_board.py::test_record_history_10min` · `test_board.py::test_board_log_history_false` |

### Reglas nuevas de la v2 (servidor)

| id | regla | test propuesto | Test que la cubre |
|---|---|---|---|
| R83 | La clave PRIM **nunca** sale del servidor: ni en respuestas, ni en logs, ni en el HTML del panel, ni en errores (solo sus 4 últimos caracteres en el panel) | `test_clave_nunca_expuesta` | `test_prim.py::test_clave_nunca_expuesta` · `test_admin.py::test_la_clave_nunca_sale_del_servidor` · `test_logs.py::test_secretos_tachados_en_todos_los_registros` · `test_logs.py::test_clave_nunca_en_respuestas_ni_logs` · `test_panel.py::test_html_y_estaticos_sin_la_clave` · `test_admin.py::test_errores_recientes_sin_secretos` · `test_prim.py::test_last_error_sin_parametros` · `test_keystore.py::test_semilla_cambiada_se_avisa_y_se_usa_el_entorno` · `test_empaquetado.py::test_env_example_sin_clave_ni_direcciones_reales` |
| R84 | La clave guardada en el panel manda sobre `PRIM_API_KEY` del entorno; va cifrada en reposo (AES-GCM, clave derivada de `APP_SEED`) con permisos 0600 | `test_keystore_prioridad_y_cifrado` | `test_keystore.py::test_keystore_prioridad_y_cifrado` · `test_keystore.py::test_permisos_0700_y_0600` (solo en POSIX; en Windows se salta) · `test_keystore.py::test_mismo_texto_cifrado_distinto_cada_vez` · `test_keystore.py::test_reemplazo` · `test_keystore.py::test_borrado_vuelve_al_entorno_o_a_nada` · `test_keystore.py::test_semilla_cambiada_se_avisa_y_se_usa_el_entorno` · `test_keystore.py::test_sin_semilla_clave_maestra_local` · `test_admin.py::test_reemplazo_y_borrado_con_prioridad_panel_sobre_entorno` · `test_prim.py::test_guardar_borrar_y_recomprobar` |
| R85 | Toda `/api/v1` exige token de dispositivo (salvo `ping` y `pair`); token de 256 bits guardado solo como hash y comparado en tiempo constante | `test_v1_sin_token_401` · `test_token_hash_y_compare_digest` | `test_auth.py::test_v1_sin_token_401` · `test_auth.py::test_token_hash_y_compare_digest` · `test_auth.py::test_ping_nunca_401_ni_escribe` · `test_auth.py::test_pair_ok_y_estado_used` (token `trj_` + 43 caracteres) · `test_auth.py::test_tabla_pairing_y_devices_sin_secretos_en_claro` · `test_v1.py::test_flujo_completo_emparejar_y_tablero` · en la app: `TrajetAPITests.testTokenBearerYSinToken` |
| R86 | Código de emparejamiento: un solo uso, 5 min, misma respuesta para malo/caducado/usado, rate limit por IP y global | `test_pair_caducado_reutilizado_fuerza_bruta` | `test_auth.py::test_pair_reutilizado` · `test_auth.py::test_pair_caducado` · `test_auth.py::test_pair_justo_antes_de_caducar_vale` · `test_auth.py::test_pair_misma_respuesta_para_malo_caducado_usado_anulado` · `test_auth.py::test_fuerza_bruta_por_ip_429_con_retry_after` · `test_auth.py::test_fuerza_bruta_global_20_cada_5_min` · `test_auth.py::test_rate_limit_se_libera_con_el_tiempo` · `test_auth.py::test_diez_fallos_seguidos_anulan_los_codigos_vivos` · `test_auth.py::test_nuevo_codigo_anula_el_anterior` · `test_auth.py::test_xff_inventado_no_salta_el_limite_por_ip` · `test_admin.py::test_flujo_de_emparejamiento_panel_app` · `test_admin.py::test_qr_anulado_caducado_y_el_nuevo_anula_el_anterior` · en la app: `PairingViewLogicTests.testR86CodigoQueNoValeNoDistingueCaducadoNiUsado` · `PairingStoreTests.testCodigoRechazado` · `EmparejamientoUITests.testCodigoQueNoValeSeDiceEnLaHoja` (el propuesto `test_pair_caducado_reutilizado_fuerza_bruta` está repartido en esos tests) |
| R87 | Un dispositivo revocado deja de funcionar al momento | `test_token_revocado_401` | `test_auth.py::test_token_revocado_401_al_momento` · `test_auth.py::test_desemparejar_desde_el_iphone` · `test_auth.py::test_v1_sin_token_401` (con un token revocado) · `test_admin.py::test_revocar_desde_el_panel` · en el iPhone: docs/pruebas-iphone.md §2 |
| R88 | Cuota contada por endpoint y día UTC, persistida; al acercarse al límite se degrada (refresco más lento, caché) y nunca se sirve un tablero hueco | `test_quota_niveles_y_degradacion` · `test_v1_board_nunca_hueco` | `test_quota.py::test_quota_niveles_y_degradacion` · `test_quota.py::test_dia_utc_nuevo_empieza_de_cero` · `test_quota.py::test_persistida_sobrevive_a_un_reinicio` · `test_quota.py::test_ttl_degradado_sirve_la_copia_sin_llamar` · `test_quota.py::test_sin_cuota_no_se_llama` · `test_quota.py::test_refresco_por_los_endpoints_del_tablero` · `test_quota.py::test_la_cabecera_manda_si_es_mas_pesimista` · `test_v1.py::test_v1_board_nunca_hueco` · `test_v1.py::test_v1_board_sin_estaciones_pero_con_avisos_da_200` · `test_prim.py::test_429_de_rafaga_no_agota_el_dia` |
| R89 | Las migraciones de SQLite conservan rutas, historial y andenes aprendidos | `test_migracion_conserva_datos` (+ copia real si está) | `test_migraciones.py::test_migracion_conserva_datos_de_la_030` · `test_migraciones.py::test_migracion_recoge_bd_de_la_010` · `test_migraciones.py::test_migracion_fallida_no_deja_esquema_a_medias` · `test_migraciones.py::test_migracion_fallida_arranca_en_modo_degradado` · `test_migraciones.py::test_migracion_real_conserva_todo` (solo si hay copia real en `.local/trajet-prod.db`) · `test_board.py::test_migracion_desde_la_primera_version` · `test_platform.py::test_accuracy_cae_a_la_tabla_vieja` (la tabla vieja de aciertos se conserva) |
| R90 | El cliente del portal de IDFM no manda nunca la cabecera `apikey` de PRIM | `test_mapdata_sin_apikey` | `test_mapdata.py::test_mapdata_sin_apikey` |

---

## Cobertura de las reglas (FASE 5)

Recuento de la columna «Test que la cubre» (90 reglas). «Cubierta» quiere
decir que todo lo que dice el enunciado corto tiene al menos un test real que
lo comprueba; «parcial», que una parte se queda sin test (la celda dice
cuál); «sin test», que no hay ninguno y solo quedan el CI, las capturas o la
prueba a mano en `docs/pruebas-iphone.md`.

- **Cubiertas: 73** — R3–R9, R13–R17, R19–R28, R30–R38, R40–R44, R46, R47,
  R49, R50, R53, R55, R56, R61–R90.
- **Parciales: 11**
  - R1 · uso real: solo capturas y a mano (§10 y §13); no hay test de
    contraste.
  - R2 · vía nueva: la lógica de cuándo es «nueva» sí; la caja y el latido
    son vista.
  - R10 · vía probable: la palabra («Vía» frente a «probable») sí; la forma
    (sólida frente a punteada) no.
  - R11 · acierto: el origen único sí; que ninguna pantalla pregunte al
    usuario no lo afirma ningún test.
  - R12 · colores de línea: el servidor normaliza el hex; en iOS `LineColor`
    no tiene tests (ni el contraste de la tinta ni la lista de IDFM).
  - R18 · antigüedad: «hace N h» solo en la versión hablada; los bordes
    59,4 s, 3599 s y 3600 s sin test.
  - R29 · alternativas: se piden al abrir la hoja sí; «N refrescos, 0
    llamadas» no.
  - R39 · refresco al tocar rutas: borrar sí; crear y editar no.
  - R45 · red local: los textos sí; el `Info.plist` y el permiso real no
    (§2 y §11).
  - R54 · barra de refresco: el texto y `nextRefreshAt` sí; la barra no.
  - R60 · IPA lite: la lógica de «no disponible» y el CI sí; los tests
    unitarios no corren contra la lite (§1.2).
- **Sin test: 6**
  - R48 · minutos primero y cifras de ancho fijo (vista; capturas y §10).
  - R51 · «Reducir movimiento» (§13).
  - R52 · área táctil de 44 pt (§13).
  - R57 · `LineColor` tolerante y gris de reserva (ningún test en iOS).
  - R58 · bundle id fijo (solo `project.yml`; §1).
  - R59 · `.xcodeproj` generado (lo garantiza el CI, no un test).

Lo que más merece un test nuevo, por lo poco que cuesta y lo que cierra:
una clase de tests de `LineColor` (R12 y R57: lógica pura, sin vista) y un
test de `RoutesStore` que compruebe que crear y editar avisan al tablero
(R39). R48, R51 y R52 son de interfaz y se quedan, de momento, en las
capturas y en el iPhone.

### Nombres de la columna «Test propuesto» que no existen

En la app casi ninguno existe con ese nombre: los tests se agruparon por
lógica (`BoardViewLogicTests`, `BoardStoreTests`, `RoutesLogicTests`,
`StatsLogicTests` y `SettingsLogicTests`, `DecodingTests`, `TrajetAPITests`,
`ServerConfigTests`, `BoardCacheTests`, `RoutesStoreTests`,
`TripControllerTests`, los de widgets y Live Activity y los de interfaz en
`TrajetUITests/`); la columna «Test que la cubre» dice cuál hace cada cosa.
En el servidor los nombres propuestos que cambiaron son:
`test_board_sin_via_metro` → `test_escenarios.py::test_R3_modos_sin_via_no_reservan_hueco`;
`test_mock_prim_casos_previewdata` → `test_contrato_v1.py::test_board_v1_forma_con_todos_los_casos` y `test_escenarios.py`;
`test_board_stale_tres_refrescos` → `test_escenarios.py::test_R19_umbral_de_stale`;
`test_board_error_estacion_parcial` → `test_escenarios.py::test_R26_una_estacion_caida_no_tumba_el_tablero` y `test_v1.py::test_tablero_parcial_da_200_con_errors`;
`test_directions_observadas` → `test_v1.py::test_buscadores` y `test_board.py::test_direccion_sin_tildes_ni_espacios_raros`;
`test_board_route_id_inexistente_404` → `test_v1.py::test_tablero_ruta_inexistente_404`;
`test_quota_reinicio_utc` → `test_quota.py::test_dia_utc_nuevo_empieza_de_cero`;
`test_board_una_llamada_por_estacion` → `test_legacy.py::test_tablero_legacy_una_llamada_por_estacion`;
`test_station_ttl_por_cercania` → `test_board.py::test_station_ttl_cada_tramo_de_la_tabla`;
`test_pair_caducado_reutilizado_fuerza_bruta` → repartido en `test_auth.py` (`test_pair_caducado`, `test_pair_reutilizado`, `test_pair_misma_respuesta_para_malo_caducado_usado_anulado`, `test_fuerza_bruta_por_ip_429_con_retry_after`, `test_fuerza_bruta_global_20_cada_5_min`);
`test_token_revocado_401` → `test_auth.py::test_token_revocado_401_al_momento`;
`test_migracion_conserva_datos` → `test_migraciones.py::test_migracion_conserva_datos_de_la_030`.
El resto de nombres del servidor existen tal cual.
