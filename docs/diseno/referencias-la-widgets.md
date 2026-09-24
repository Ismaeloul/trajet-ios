# Live Activity y widgets: referencias y límites reales

FASE 2B.1 · consultado el 24 de septiembre de 2026 · alimenta
`design-lab/b-cristal-v2/` (2B.2) y `docs/diseno/decisiones-la-widgets.md` (2B.4).

Este documento reúne dos cosas: **qué hacen bien otras apps** (y qué nos
llevamos o evitamos) y **qué deja hacer iOS de verdad** en la Live Activity y
en los widgets. Al final, «Qué implica para Trajet» convierte todo en
principios concretos para el rediseño.

Cómo leer las cifras:

- Sin marca: dato **oficial** de Apple (HIG, documentación o sesión WWDC), con
  enlace.
- **[estimación]**: deducido por mí a partir de datos oficiales. Hay que
  medirlo en el simulador (FASE 3, con `GeometryReader`, como hace
  [simonbs/ios-widget-sizes](https://github.com/simonbs/ios-widget-sizes)).
- **[a verificar]**: comportamiento descrito por terceros o poco documentado.
  Hay que probarlo en el simulador o en el iPhone antes de fiarse.

Las reglas se citan por su id de `docs/reglas.md`. Ojo: el encargo 2B llama
«regla 6» a la antigüedad (es **R9/R17**) y «regla 7» a la vía real/probable
(es **R10**).

---

## 0. Resumen en diez líneas

1. **Pantalla de bloqueo**: 371 pt de ancho en iPhone 16 y 408 pt en los
   «Max»; alto entre **84 y 160 pt** (por encima, el sistema puede cortar);
   margen estándar de **14 pt**.
2. **Dynamic Island**: compacta de **52,33 × 36,67 pt** por lado (62,33 en
   los «Max»); mínima de **36,67–45 × 36,67**; expandida de **371/408 × 84–160**
   con cuatro regiones (leading, trailing, center y bottom). El fondo es
   **negro opaco** siempre.
3. **La Live Activity no tiene red ni ubicación**: solo cambia cuando la app la
   actualiza. **Actualizar en segundo plano sin push «no está soportado
   explícitamente»** (respuesta de un ingeniero de Apple): hay que diseñarla
   para que diga la verdad **aunque se congele**.
4. **Lo que corre solo** son los textos de fecha del sistema
   (`Text(timerInterval:)`, `Text(fecha, style:)` y, desde iOS 18, los
   formatos `.timer`, `.reference` y `.offset`). **No hay segundos en
   nuestro dato** (`at` es «HH:MM»): una cuenta atrás «05:58» aparenta una
   precisión que no tenemos.
5. **Widgets**: de **40 a 70 recargas al día** (cada 15–60 min) y entradas de
   timeline separadas **al menos unos 5 minutos**. Un widget casi siempre
   enseña un dato de hace un buen rato: la antigüedad forma parte del
   contenido.
6. **Colores**: en la pantalla de bloqueo los widgets son **vibrantes**
   (monocromo), y en el inicio «tintado» o «transparente» de iOS 26 se pintan
   **en blanco sobre cristal**. El color de línea y el amarillo de la vía
   **desaparecen**, así que todo tiene que funcionar por forma, peso y palabra.
7. **Animaciones de 2 s como máximo**, solo al actualizarse y **ninguna** en
   Always-On. No hay latidos continuos en la Live Activity ni en los widgets.
8. **Botón «Parar»**: `LiveActivityIntent` (iOS 17), solo en la expandida y en
   la de bloqueo. **Con el iPhone bloqueado pide desbloquear**, y en CarPlay
   está desactivado.
9. **Duración**: 8 h activa, más hasta 4 h en la pantalla de bloqueo ya
   terminada. `staleDate` hace que el sistema marque el dato como caducado
   **sin que la app haga nada**.
10. **Apple ID gratuito**: la tabla oficial de Apple **sí** marca App Groups
    como disponibles para cuentas gratuitas, y la Live Activity **no necesita
    App Group** ni push. La premisa «gratuito = sin widget ni Live Activity»
    hay que **comprobarla con IPA Station** antes de darla por buena (§3.15).

---

## 1. Lo que nuestro dato permite (y lo que no)

La Live Activity y los widgets solo pueden enseñar lo que da
`/api/v1/board` (`docs/openapi.yaml`, `BoardV1`). **No se inventa nada.**

| Hay | Campo | Para qué sirve aquí |
|---|---|---|
| Minutos al paso | `departures[].minutes` (entero ≥ 0, **redondeado**) | la cifra, en el momento en que llegó |
| Hora prevista | `departures[].at` (**«HH:MM»**, hora de París, **sin segundos**) | la fecha de la cuenta atrás que corre sola |
| Hora teórica y retraso | `aimed_at` (puede ser «»), `delay` (null sin hora teórica, R4) | «+2 min» solo si existe y ≠ 0 (R14) |
| Vía real / nueva | `platform` (null el 83 %), `platform_new` | caja sólida; animación y alerta al aparecer (R2) |
| Vía probable | `guess {platform, share, samples, basis, why}` | recuadro punteado «probable» (R10, R49) |
| ¿Este modo publica vía? | `legs[].platform_expected` | no reservar hueco (R3) |
| En el andén | `at_stop` | «En andén» ≠ «ya» (R15) |
| Longitud | `length` short/long/null | «tren largo» (R5) |
| Destino | `destination`, `legs[].directions`, `to_name` | destino por fila si hay mezcla (R24) |
| Línea | `line_code`, `line_color`, `line_mode` | distintivo con el color oficial (R12) |
| Estado de la línea | `status.level` 0/1/2, `label`, `messages` (FR, ≤ 3), `messages_es`, `translating` | etiqueta «perturbada»/«cortada» |
| Tramos | `legs[]` con `seq`, `from_name`, `to_name` | tramo actual y transbordo |
| Antigüedad | `data_age`, `updated_at`, `stale`, y la hora de llegada al teléfono | R17, R19 |
| Ritmo de refresco | `server.refresh_hint_s` (30/60/120/300), `server.degraded` | cuánto tarda el siguiente dato |
| Estado del servidor | `server.prim_key`, `disruptions_ok`, `errors` | «sin clave», «avisos sin leer», fallo parcial |

**No hay** (y por tanto no se copia de ninguna referencia):

- **Segundos** en la hora de salida → nada de «05:58».
- **Posición del tren**, paradas restantes o progreso por la línea → nada de
  «quedan 3 paradas» (Transit) ni de barra por las estaciones (concepto de
  Trainline, §2).
- **Hora de llegada** al destino o al transbordo en el tablero → nada de
  «llegas 13:25».
- **Ocupación** (R5) ni composición más allá de corto/largo.

---

## 2. Referencias

### 2.1 Apple

**A1 · HIG, Live Activities** (actualizada el 16-12-2025) —
<https://developer.apple.com/design/human-interface-guidelines/live-activities>

- *Qué hace bien:* es la fuente de los tamaños (§3.1 y §3.2) y de las reglas
  de contenido: «texto grande y de peso medio o mayor»; la compacta «se lee
  como una sola pieza de información», pegada a la cámara y **sin relleno**;
  la mínima **no debe ser solo un logo** (el Temporizador enseña el tiempo
  que queda); la expandida mantiene **la posición relativa** de lo que había
  en la compacta; la de bloqueo **no debe imitar una notificación**; el alto
  cambia según la información que haya.
- *Nos llevamos:* una sola acción como mucho («prefer limiting it to a single
  element»); retirar la Live Activity a los **15–30 min** de terminar; alertas
  solo para lo esencial; tocar abre la app **en el sitio exacto**.
- *Evitamos:* botones que roben espacio a la información; cualquier elemento
  de la app que «apunte» a la isla.

**A2 · HIG, Widgets** (actualizada el 16-12-2025) —
<https://developer.apple.com/design/human-interface-guidelines/widgets>

- *Qué hace bien:* los tamaños por pantalla (§3.3 y §3.4), los modos de
  renderizado y una advertencia que nos toca de lleno: «si la gente mira el
  widget más a menudo de lo que puede actualizarse, **enseña cuándo se
  actualizó el dato**». Además: «usa la funcionalidad del sistema para
  refrescar fechas y horas» y «no escondas el dato viejo tras un marcador
  vacío».
- *Nos llevamos:* no depender del color («convey meaning without relying on
  specific colors»), texto de **11 pt como mínimo** y márgenes de **16 pt**
  (11 pt para agrupar).
- *Evitamos:* un widget grande que sea «el pequeño estirado» («avoid expanding
  a smaller widget's content to simply fill a larger area»).

**A3 · WWDC23, «Design dynamic Live Activities»** —
<https://developer.apple.com/videos/play/wwdc2023/10194/>

- *Qué hace bien:* da el criterio para la isla: la compacta tiene que ser
  **«tan estrecha como sea posible, sin espacio desperdiciado»**, y para eso
  propone **acortar las unidades o dar un dato menos preciso**. En la
  expandida, nada de «frente» vacía alrededor de la cámara. Contenido
  concéntrico con la forma de la isla, texto grande y grueso, y
  «numeric content transition» para las cifras que suben o bajan.
- *Nos llevamos:* en la compacta, «12′» o «12» con una «min» diminuta, no
  «12 minutos»; los márgenes de 14 pt de la pantalla de bloqueo; en StandBy,
  la de bloqueo se ve al **200 %**.

**A4 · WWDC25, «What's new in widgets»** —
<https://developer.apple.com/videos/play/wwdc2025/278/> (notas:
<https://wwdcnotes.com/documentation/wwdc25-278-whats-new-in-widgets/>)

- *Qué trae iOS 26:* el modo **acentuado** con Liquid Glass (todo el
  contenido en blanco y el fondo cambiado por cristal o por un tinte), el
  modificador `widgetAccentedRenderingMode` para las imágenes, **widgets en
  todos los coches con CarPlay**, Live Activities en **CarPlay** y en la barra
  de menús del **Mac** (macOS Tahoe) y widgets por push (`WidgetPushHandler`,
  que requiere push y no nos sirve, §3.15).
- *Nos llevamos:* el diseño tiene que aguantar **sin color** en el inicio.

**A5 · WWDC26, «Live Activities essentials»** —
<https://developer.apple.com/videos/play/wwdc2026/223/>

- *Qué trae iOS 27* (publicado el 14-09-2026): la isla se ve **también en
  apaisado**, con un valor de entorno nuevo, `isDynamicIslandLimitedInWidth`,
  para cuando no puede ensancharse. Repasa `supplementalActivityFamilies`,
  `activityFamily`, `showsWidgetContainerBackground`,
  `activityBackgroundTint` y `LiveActivityIntent`.
- *Nos toca poco hoy:* el CI compila con Xcode 26.6 (SDK de iOS 26.5,
  `docs/decisiones.md` D0.5), así que no podemos usar esa API. Pero la
  compacta tiene que **sobrevivir con menos ancho**: si solo caben los
  minutos, que queden los minutos.

**A6 · ActivityKit, «Displaying live data with Live Activities»** —
<https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities>

- La referencia de los límites técnicos (§3.8–§3.11): 8 h + 4 h; 4 KB; sin red
  ni ubicación; imágenes no más grandes que la presentación; `staleDate` y
  `relevanceScore`; alertas con `AlertConfiguration`; cómo se reparte el
  ancho de la expandida.

**A7 · Wallet en iOS 26 (tarjeta de embarque con Live Activity) y el
Temporizador** —
<https://9to5mac.com/2025/11/04/ios-26-wallet-app-boarding-pass-features-ios-26/>
· búsqueda de prensa (Gadget Hacks, NeatPass) sobre la Live Activity de
embarque.

- *Qué hace bien:* es el «billete» de Apple: puerta, hora, retraso y
  **cambio de puerta** en la pantalla de bloqueo y en la isla, sin abrir nada.
  La puerta es nuestra vía y el cambio de puerta es nuestro «cambio de vía».
- *Nos llevamos:* el cambio de vía (y la vía que aparece) es de lo poco que
  merece una **alerta**.
- *Nota:* Apple no publica el diseño exacto de esta Live Activity; solo
  tomamos la idea.

**A8 · Apple Maps** — «Transporte cercano» y navegación en transporte
público: <https://support.apple.com/guide/iphone/get-transit-directions-ipha44f57caa/ios>

- *Qué hace bien:* un toque para ver horarios y retrasos de las paradas
  cercanas.
- *Aviso:* Apple **no documenta** cómo es la Live Activity de Mapas durante
  una ruta en transporte público (la guía de usuario de iOS 27 no lo cuenta).
  No copiamos nada de memoria: para la isla nos guiamos por la HIG (A1) y por
  el Temporizador y Wallet (A7).

### 2.2 Apps de transporte

**T1 · Transit** — reseña 2024 de MacStories:
<https://www.macstories.net/reviews/transit-is-still-the-best-designed-transit-app-on-the-iphone-in-2024/>
· App Store: <https://apps.apple.com/us/app/transit-subway-bus-times/id498151501>
· ayuda: <https://help.transitapp.com/article/151-check-a-schedule>

- *Qué hace bien:* «la mejor Live Activity de la isla que he visto»
  (MacStories). GO da **alarmas de salida** y avisa de cuándo bajarse o hacer
  transbordo; la isla **se abre sola** dos paradas antes. En la app, el tiempo
  real va **en negrita con dos ondas** y el horario teórico **en gris**.
- *Nos llevamos:* distinguir **dato vivo frente a dato no vivo** con forma y
  peso, no solo con color. Para nosotros: «en directo» frente a «dato de hace
  X». Y un modo trayecto explícito que se apaga solo.
- *Evitamos:* la cuenta de paradas restantes: **no tenemos posición del
  tren** (§1).

**T2 · Citymapper** — Apple Developer, «Spotlight on: The Dynamic Island»:
<https://developer.apple.com/news/?id=mis6swzt> · anuncio:
<https://citymapper.com/news/2553/citymapper-introduces-ios-lock-screen-navigation>
· diseñador: <https://jasonhibbs.co.uk/work/citymapper-live-activity/>

- *Qué hace bien:* divide el viaje en **cuatro fases** (ir a la parada,
  esperar, ir a bordo y caminar al destino). En la compacta hay **un icono de
  la fase y una cuenta atrás**, nada más. «No queríamos que estorbase.»
  Reducir el modo GO a «lo esencial de cada momento».
- *Nos llevamos:* la Live Activity enseña **el tramo que toca ahora** y cambia
  cuando toca el transbordo, y la compacta lleva solo **icono o línea +
  minutos**.
- *Evitamos:* fases que no podemos detectar con fiabilidad («a bordo»:
  sin posición del tren y con GPS de baja precisión).

**T3 · Google Maps** — Live Activities en iPhone:
<https://9to5google.com/2024/07/17/google-maps-live-activities-iphone/>
· widgets: <https://www.bgr.com/tech/google-maps-has-new-widgets-on-iphone-that-you-need-to-try/>

- *Qué hace bien:* «indicaciones de un vistazo»: hora de llegada y siguiente
  indicación, nada más.
- *Lección de widgets:* en 2021 Google cambió sus widgets concretos (entre
  ellos «Transit Departures») por dos genéricos, y la prensa recogió que los
  usuarios **echaban de menos el de salidas**. Un widget de próximas salidas
  sí tiene público.

**T4 · Moovit** — App Store:
<https://apps.apple.com/us/app/moovit-bus-transit-tracker/id498477945>

- No documenta Live Activity en su ficha. Su baza son los avisos de «bájate»
  (Live Ride / Live Directions:
  <https://www.masstransitmag.com/technology/press-release/12145871/moovit-moovit-adds-live-directions-and-get-off-notifications>).
- *Nos llevamos:* las alertas son la herramienta para los momentos clave,
  no la Live Activity entera.

**T5 · Bonjour RATP** — ayuda «Comment ajouter un widget»:
<https://www.bonjour-ratp.fr/aide-contact/?question=comment-ajouter-un-widget-a-mon-ecran-d-accueil>
(la página devuelve 403 a descargas automáticas; cito su resumen en el buscador)
· App Store: <https://apps.apple.com/fr/app/bonjour-ratp/id507107090>

- *Qué hace:* un widget con los **próximos pasos de los favoritos** y el
  estado de la red. No anuncia Live Activity en su ficha.
- *Nos llevamos:* el usuario de Île-de-France ya lee los colores oficiales
  de un vistazo.
- *Evitamos:* elegir favoritos a mano. En Trajet **la ruta que toca la elige
  el servidor** (R37): el widget no necesita configuración.

**T6 · Île-de-France Mobilités** — App Store:
<https://apps.apple.com/FR/app/id484527651>

- *Qué hace:* la versión 9.7.0 (abril; en la ficha no pone el año) añade
  «suivre les prochains départs via des widgets». No anuncia Live Activity.
- *Nos llevamos:* es la app oficial de la red y hoy **no tiene Live
  Activity**. El hueco existe.

**T7 · SNCF Connect** — artículo propio «L'application SNCF Connect : les
meilleures fonctionnalités»:
<https://www.sncf-connect.com/article/l-application-sncf-connect-mode-d-emploi-et-astuces>
(403 a descargas automáticas; cito su resumen en el buscador)

- *Qué hace:* cuando se acerca la salida, la pantalla de inicio de la app
  enseña **coche, plaza, vestíbulo y vía**. Su ficha no anuncia Live
  Activity.
- *Nos llevamos:* la vía gana protagonismo **cuanto más cerca está la
  salida** (en Trajet aparece de media 7,7 min antes, R2).

**T8 · DB Navigator y ÖPNV Navigator** — App Store DB:
<https://apps.apple.com/de/app/db-navigator/id343555245> · ÖPNV Navigator:
<https://www.iphone-ticker.de/oepnv-navigator-aufgewertet-live-aktivitaeten-wagenreihung-und-mehr-230238/>

- *Qué hacen:* DB tiene «Reisebegleitung» con avisos de **cambio de vía** y
  de retraso; su ficha no anuncia Live Activity. ÖPNV Navigator (febrero de
  2024) ofrece activar la Live Activity **una hora antes** del viaje, con el
  tramo actual según la ubicación.
- *Nos llevamos:* **proponer** el modo trayecto al acercarse la hora de la
  ruta o al entrar en la geocerca (encargo 3.4), sin encenderlo por su cuenta.

**T9 · Trainline** — widget oficial:
<https://www.thetrainline.com/information/apps/widgets> · concepto de Live
Activity (caso de estudio UX, **no es el producto**):
<https://medium.com/@hlk73071/trainline-live-activities-ux-addition-for-real-time-train-updates-21614a1ef091>

- *Qué hace bien:* el widget es solo «tu próximo tren, con hora en directo y
  vía». El concepto de Live Activity añade una barra de progreso por las
  paradas.
- *Nos llevamos:* el widget pequeño responde **una** pregunta.
- *Evitamos:* la barra por paradas (no hay posición del tren) y **cualquier
  barra sin etiqueta** (es justo el fallo del prototipo B: «¿progreso de
  qué?»).

**T10 · Flighty** (aviones, pero es un tablero de salidas) —
<https://9to5mac.com/2022/10/24/flighty-dynamic-island-iphone-live-activities/>
· <https://x.com/Flighty/status/1584607890676977664> ·
<https://flighty.com/help/live-activities-widgets>

- *Qué hace bien:* es el referente del género. La compacta lleva **cuenta
  atrás hasta la salida y la puerta**; los cambios de puerta y los retrasos
  van en la isla; tiene colores pensados para **Always-On**; y sin conexión
  (modo avión) sigue enseñando un progreso y una hora estimados **calculados
  en el propio teléfono**.
- *Nos llevamos:* compacta = **minutos + vía**. Y sobre todo que, sin red, lo
  que se enseña se calcula a partir de **fechas** y no se congela.

### 2.3 Apps de cuenta atrás de salidas

**C1 · Nearly Departed** (trenes del Reino Unido) — novedades:
<https://nearlydeparted.app/whatsnew>

- *Qué hace bien:* abre la Live Activity al **fijar un tren** (2.36, enero de
  2024). En la 2.38 **estrechó la isla «para no tapar la hora del sistema»**.
  Tiene widgets de bloqueo desde iOS 16 y StandBy desde iOS 17, y la Live
  Activity en el Smart Stack de watchOS 11. Distinguía «vías provisionales»
  (las retiró en 2025 por un acuerdo de datos con National Rail).
- *Nos llevamos:* compacta estrecha y una sola Live Activity por trayecto.

**C2 · UK Live Trains** — <https://traintimesapp.uk/>

- *Qué hace:* Live Activity e isla con salidas de la estación cercana o del
  trayecto habitual, **vía prevista y vía real** y progreso del tren.
- *Nos llevamos:* es el mismo problema que nuestra vía probable/real (R10),
  resuelto a la vista.

**C3 · CT Trains, EL Tracker y Commuter Widgets** —
<https://apps.apple.com/us/app/ct-trains/id6761348766> ·
<https://apps.apple.com/mr/app/el-tracker/id6499103522> ·
<https://apps.apple.com/us/app/commuter-widgets/id6738397174>

- *Qué hacen:* cuenta atrás en la isla y en la pantalla de bloqueo; CT
  Trains presume de una cuenta atrás «al segundo».
- *Evitamos:* **los segundos**. Con nuestro dato (HH:MM) serían precisión
  falsa, y hacen que el número parpadee cuando se mira de reojo.

**C4 · Pantograph** — <https://pantographapp.com/> ·
<https://apps.apple.com/us/app/pantograph/id1467024983>

- *Qué hace:* widgets con el **estado de varias líneas**. No documenta Live
  Activity.
- *Nos llevamos:* el widget grande puede enseñar el estado de **todas las
  líneas de la ruta** (cortada o perturbada), no solo la primera.

**C5 · CityTransit** (ya estaba en `design-lab/referencias.md`) —
<https://apps.apple.com/us/app/citytransit-bus-train-times/id1250234465>

- Alarmas de llegada con Live Activity. La cuenta atrás es lo que justifica
  la isla.

### 2.4 Práctica: lo que cuentan quienes ya lo han hecho

**P1 · Swift and Sour, «Live Activity – the problems (almost) no one speaks
about»** —
<https://swiftandsour.com/live-activity-not-so-live-%F0%9F%98%B5-part-2/>

- El texto de temporizador **ensancha la isla** porque reserva el ancho
  máximo. Solución: `monospacedDigit()` y un **marco fijo** calculado para el
  peor caso.
- `.timer` **vuelve a contar hacia arriba** al pasar la hora. Con
  `Text(timerInterval:countsDown: true)` se para en 0.
- **Zonas horarias**: hay que construir bien las fechas. En Trajet, `at` va
  en hora de París y hay que tener en cuenta el cambio de día a medianoche.

**P2 · Foros de desarrolladores de Apple**

- [757140](https://developer.apple.com/forums/thread/757140): cómo conseguir
  una cuenta atrás compacta tipo «3m». Un ingeniero de Apple remite a los
  formatos nuevos (`TimeDataSource` + `.units`, iOS 18). Problemas que siguen
  abiertos: el marco enorme (se arregla con un texto oculto de plantilla y
  `overlay`), el **signo negativo** en las cuentas atrás, y que un
  `DiscreteFormatStyle` propio **no se pinta** en la Live Activity.
- [748569](https://developer.apple.com/forums/thread/748569): con el iPhone
  bloqueado, una app en segundo plano **con modo audio tiene prohibido**
  actualizar su Live Activity. El ingeniero de Apple: «otros modos de segundo
  plano pueden permitir actualizaciones más frecuentes, **pero no está
  soportado explícitamente**»; lo soportado es APNs.
- [776031](https://developer.apple.com/forums/thread/776031): «la única forma
  soportada [en segundo plano] es por push, salvo que la app esté en primer
  plano».
- [722073](https://developer.apple.com/forums/thread/722073):
  `ProgressView(timerInterval:)` **se queda al 100 %** en la isla y en
  Always-On desde iOS 16.2 (sin respuesta de Apple).
- [760027](https://developer.apple.com/forums/thread/760027): los formatos de
  iOS 18 no se pueden personalizar: las palabras y el prefijo («in …») los
  pone el sistema.

**P3 · «Why your iOS Live Activity silently stops updating»** —
<https://dev.to/hellomisterdev/why-your-ios-live-activity-silently-stops-updating-lmd>

- Cuando se agota el presupuesto, la Live Activity **deja de moverse sin dar
  ningún error**. Las actualizaciones locales demasiado seguidas se fusionan.

---

## 3. Límites reales que afectan al diseño

### 3.1 Live Activity en la pantalla de bloqueo

| Dispositivo | Pantalla (pt) | Live Activity (pt) | Fuente |
|---|---|---|---|
| iPhone 16, 16 Pro¹, 15, 15 Pro, 14 Pro, 17, 17 Pro | 393 × 852 | **371 × 84–160** | HIG (A1) |
| iPhone 16 Plus, 15 Plus, 15 Pro Max, 14 Pro Max | 430 × 932 | **408 × 84–160** | HIG (A1) |
| iPhone 16 Pro (402 × 874) | 402 × 874 | [estimación] ≈ 380 × 84–160 | pantalla − 22 pt, como en las dos filas oficiales |
| iPhone 16 Pro Max, 17 Pro Max, Air (440 × 956) | 440 × 956 | [estimación] 408–418 × 84–160 | la HIG no da fila; la isla expandida de estos modelos mide 408 |
| iPhone SE (3.ª gen.), **sin isla** | 375 × 667 | [estimación] ≈ 353 × 84–160 | pantalla − 22 pt |

¹ La HIG solo publica las filas de 393 y 430 pt de ancho.

- **Alto**: entre 84 y 160 pt. «El sistema puede truncar una Live Activity
  que pase de 160 pt» (A6). El alto se adapta: si hay menos información, se
  encoge (A1).
- **Margen estándar: 14 pt** («alinea con las notificaciones»). Ancho útil:
  **343 pt** en iPhone 16 y **380 pt** en los de 430.
- **Fondo**: por defecto, claro en modo claro y oscuro en modo oscuro. Se
  puede poner un tinte propio (`activityBackgroundTint`) **solo aquí**, con
  mesura y comprobado en Always-On. El color del botón de cerrar lo genera el
  sistema y se ajusta con `activitySystemActionForegroundColor`.
- **Dónde sale**: en la pantalla de bloqueo, con las notificaciones. En un
  iPhone **sin isla** (SE), una actualización **con alerta** aparece como
  banner arriba, encima de la app que esté abierta (A6).
- **StandBy**: se escala al **200 %** y rellena la pantalla; se detecta con
  `isActivityFullscreen`. En modo noche lleva **tinte rojo** (A1, A3).

### 3.2 Dynamic Island

| | Modelos de 393 pt (16, 16 Pro, 15, 15 Pro, 14 Pro, 17, 17 Pro) | Modelos de 430/440 pt (16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max, 17 Pro Max, Air) |
|---|---|---|
| Compacta: leading | **52,33 × 36,67** | **62,33 × 36,67** |
| Compacta: trailing | **52,33 × 36,67** | **62,33 × 36,67** |
| Ancho total de la isla (compacta o mínima) | **230** | **250** |
| Mínima | **36,67–45 × 36,67** (circular u ovalada) | igual |
| Expandida | **371 × 84–160** | **408 × 84–160** |
| Radio de las esquinas | 44 | 44 |

Fuente: HIG (A1), tablas «iOS dimensions» y «Dynamic Island width». Ojo:
para el 16 Pro y el 16 Pro Max, la HIG da **230/371** y **250/408**: la isla
no crece con el borde más fino.

- **Compacta**: solo cuando hay **una** Live Activity. Dos piezas a los lados
  de la cámara que tienen que leerse como una sola; sin relleno contra la
  cámara; las dos llevan al mismo sitio al tocarlas. La isla **se ensancha si
  el contenido lo pide** (por eso un temporizador sin marco la estira, P1 y
  P2), pero Apple pide lo más estrecho posible y **equilibrado**. Si se pasa
  de ancho, tapa la hora y las barras de estado (Nearly Departed tuvo que
  estrecharla, C1).
- **Mínima**: cuando hay **varias** Live Activities de apps distintas. Una va
  pegada a la isla y otra suelta (circular u ovalada). También es la que sale
  arriba en StandBy. Imágenes de **45 × 36,67 pt como máximo**, o la Live
  Activity puede no arrancar (A6).
- **Expandida**: al mantener pulsado y, brevemente, con cada actualización
  que lleve alerta. Regiones (A6):
  - `leading`: junto a la cámara, a la izquierda; lo que no cabe baja por
    debajo.
  - `trailing`: lo mismo a la derecha.
  - `center`: debajo de la cámara.
  - `bottom`: debajo de todo lo anterior.
  - Por defecto leading y trailing reciben el mismo ancho. Con `priority` una
    región ocupa todo el ancho, y con
    `dynamicIsland(verticalPlacement: .belowIfTooWide)` la leading baja si no
    cabe junto a la cámara.
  - [estimación] En la fila de la cámara, cada lado mide unos
    (371 − 125) / 2 ≈ **120 pt** en un iPhone 16, con un alto de unos 37 pt.
    Los 125 pt de la cámara salen de restar las dos piezas compactas al ancho
    de 230.
- **Fondo negro opaco** siempre, sin opción de cambiarlo. En modo oscuro hay
  un **filete** alrededor de la isla que se tiñe con `keylineTint` (A1).
- **iOS 27**: se ve también en apaisado, con menos ancho
  (`isDynamicIslandLimitedInWidth`, A5).
- **Sin isla** (iPhone SE): no hay compacta, mínima ni expandida. Solo la de
  bloqueo y el banner.

### 3.3 Widgets de la pantalla de inicio

| Dispositivo | Pantalla (pt) | Pequeño | Mediano | Grande | Fuente |
|---|---|---|---|---|---|
| iPhone SE (2.ª/3.ª) | 375 × 667 | **148 × 148** | **321 × 148** | **321 × 324** | HIG (A2) |
| iPhone 14, 13 | 390 × 844 | **158 × 158** | **338 × 158** | **338 × 354** | HIG (A2) |
| iPhone 16, 15, 14 Pro | 393 × 852 | **158 × 158** | **338 × 158** | **338 × 354** | HIG (A2) |
| iPhone 16 Pro | 402 × 874 | [estimación] 158 × 158 | [estimación] 338 × 158 | [estimación] 338 × 354 | sin fila oficial; la más cercana es 393 |
| iPhone 16 Plus, 15 Pro Max | 430 × 932 | **170 × 170** | **364 × 170** | **364 × 382** | HIG (A2) |
| iPhone 16 Pro Max | 440 × 956 | [estimación] 170 × 170 | [estimación] 364 × 170 | [estimación] 364 × 382 | sin fila oficial; la más cercana es 430 |

- **Márgenes**: 16 pt en general; 11 pt para agrupar formas o botones (A2).
- **Texto**: 11 pt como mínimo. Dynamic Type de **Large a AX5** (A2).
- **El pequeño también sale en StandBy y en CarPlay** (iOS 26: en todos los
  coches con CarPlay): **sin fondo**, escalado y a todo color. Hay que marcar
  el fondo como removible con `containerBackground(for: .widget)`.
- No hay extragrande en iPhone con el SDK que usamos. La prensa habla de un
  tamaño de página entera en iOS 27 [a verificar]; no lo contemplamos.

### 3.4 Widgets de la pantalla de bloqueo

| Dispositivo | Circular | Rectangular | En línea | Fuente |
|---|---|---|---|---|
| iPhone SE (375 × 667) | **68 × 68** | **153 × 68** | **225 × 26** | HIG (A2) |
| iPhone 14/16 (390/393) | **72 × 72** | **160 × 72** | **234 × 26** | HIG (A2) |
| iPhone 16 Plus, 15 Pro Max (430) | **76 × 76** | **172 × 76** | **257 × 26** | HIG (A2) |
| iPhone 16 Pro / 16 Pro Max | [estimación] como 393 / como 430 | | | sin fila oficial |

- **Siempre vibrantes** en el iPhone: el sistema desatura texto, imágenes y
  medidores y los colorea según el fondo de pantalla o el tinte que haya
  elegido el usuario. **No hay color de línea ni amarillo.**
- **En línea**: una sola línea encima de la hora, con **un solo destino al
  tocar** (A2). [a verificar] El sistema impone su tipografía: no hay
  jerarquía posible.
- **iOS 26**: los widgets de bloqueo se pueden colocar **abajo**, justo
  encima de los botones de linterna y cámara, y bajan solos si el reloj
  adaptativo crece
  (<https://www.macrumors.com/how-to/ios-move-lock-screen-widgets-bottom-display/>).
- Always-On: se ven con luminancia reducida (`isLuminanceReduced`).

### 3.5 Tipografía

- «Texto grande, de peso **medio o mayor**» en la Live Activity (A1). En la
  isla funcionan bien las formas «extra redondeadas y gruesas» (A3).
- SF Pro Rounded es la fuente del sistema: `.fontDesign(.rounded)`,
  `.fontWeight(.heavy)` y `.monospacedDigit()` funcionan en extensiones sin
  tener que empaquetar nada.
- La isla tiene un alto fijo de 36,67 pt, así que el Dynamic Type grande no
  cabe. Hay que limitarlo con `.dynamicTypeSize(...)` en las regiones
  compactas y comprobar la de bloqueo con tamaños grandes.

### 3.6 Texto que se actualiza solo (sin la app)

Es **lo único** que cambia en una Live Activity sin que la app la actualice,
y lo único que cambia en un widget entre una entrada de timeline y la
siguiente.

| API | Desde | Qué enseña | Para Trajet |
|---|---|---|---|
| `Text(fecha, style: .timer)` | iOS 14 | «15:00» bajando; **al pasar la hora, cuenta hacia arriba** | nunca sola: un tren que ya salió seguiría «contando» |
| `Text(timerInterval: a...b, countsDown: true)` | iOS 16 | «12:00» → «0:00» y **se para en 0**; en un widget **se estira a todo el ancho** (hay que darle un marco) | alternativa para iOS 17; enseña segundos |
| `Text(fecha, style: .relative)` | iOS 14 | «11 min, 14 sec»: diferencia **absoluta**, igual en pasado que en futuro | antigüedad en iOS 17 («hace …») |
| `Text(fecha, style: .offset)` | iOS 14 | «-11 minutes» | no |
| `Text(.currentDate, format: .timer(countingDownIn: a..<b, maxPrecision: .seconds(60)))` | iOS 18 | con precisión de minuto: «5 minutes», «4 minutes» | **candidata** para la cuenta atrás sin segundos [a verificar: texto en español, redondeo] |
| `Text(.currentDate, format: .reference(to: fecha, allowedFields: …))` | iOS 18 | «now», «in 5 minutes», «3 days ago» | **candidata** para la antigüedad («hace 4 min») [a verificar] |
| `Text(.currentDate, format: .offset(to: fecha, allowedFields: …, maxFieldCount: …))` | iOS 18 | «5:32» o «1 hour, 5 minutes» | poco útil |
| `Text(TimeDataSource<Date>.durationOffset(to: fecha), format: .units(allowed: [.hours, .minutes], width: .narrow, …))` | iOS 18 | formato estrecho tipo «3m» (P2) | **candidata** para la compacta [a verificar: signo negativo] |
| `ProgressView(timerInterval: a...b, countsDown: true)` | iOS 16 | barra o anillo que avanza solo | **fallo**: se queda al 100 % en la isla y en Always-On (P2, 722073) |

Fuentes: <https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates>,
[Text(timerInterval:)](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)),
[SystemFormatStyle.Timer](https://developer.apple.com/documentation/swiftui/systemformatstyle/timer),
[DateReference](https://developer.apple.com/documentation/swiftui/systemformatstyle/datereference),
[DateOffset](https://developer.apple.com/documentation/swiftui/systemformatstyle/dateoffset),
[TimeDataSource](https://developer.apple.com/documentation/swiftui/timedatasource).

Consecuencias:

- **Las palabras las pone el sistema** y en el idioma del iPhone. No hay forma
  de separar la cifra de la unidad para dar a cada una su tamaño («12» grande
  y «min» pequeño). Un número con esa jerarquía **solo puede ser estático**
  (lo escribe la app al actualizar).
- **Redondeo**: el servidor **redondea** `minutes`, y los formatos del
  sistema probablemente **truncan** [a verificar]. Pueden diferir en un
  minuto; hay que elegir un criterio y testearlo (R16: correr con ≤ 3 min).
- **Fecha de salida**: se construye con `at` («HH:MM») en
  `Europe/Paris`, pasando al día siguiente si hace falta, y se comprueba
  contra `minutes`. Nunca hay segundos.
- **Patrón posible para la Live Activity** (a decidir en 2B): mientras llegan
  datos, se enseña el `minutes` estático con toda la jerarquía tipográfica. Se
  pone un `staleDate` cercano; si la app deja de actualizar, el sistema pone
  `context.isStale` a `true` y la vista cambia **sola** a la cuenta atrás por
  fecha, con el aviso de dato antiguo (§3.10).

### 3.7 Qué se puede animar

- Máximo **2 segundos** por animación, en widgets y en la Live Activity
  (<https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities>).
- Desde iOS 17 se admiten **todas** las transiciones y animaciones de SwiftUI
  (hasta iOS 16 la Live Activity ignoraba `withAnimation` y `animation`).
  Por defecto el texto cambia con un fundido con desenfoque, los símbolos e
  imágenes con su transición de contenido, y las vistas que entran o salen,
  con un fundido.
- `.contentTransition(.numericText(countsDown: true))` para los minutos, y
  `numericText(countsDown:)` también para el texto de temporizador.
- `.id(valor)` + `.transition(.push(from:))` para animar una pieza cuando
  cambia otro dato (por ejemplo, que aparezca la vía).
- **Sin animación en Always-On** (`isLuminanceReduced`). `Transaction` no
  existe en extensiones: se desactiva con `.transition(.identity)` o
  `animation(nil)`.
- **Nada continuo**: no hay latidos en bucle ni pulsos de «en directo».
  La animación solo ocurre al actualizarse (y, en widgets, al pasar de una
  entrada a otra). El latido de la vía nueva (R2) se traduce en **una
  transición de ≤ 2 s más una alerta**.
- **Alertas** (`update(_:alertConfiguration:)`): encienden la pantalla,
  suenan por defecto, abren la expandida en la isla o sacan un banner en los
  iPhone sin isla; en el Watch usan `title` y `body`. Solo para lo esencial
  (A1).
- La háptica solo existe dentro de la app. En la Live Activity, el aviso es
  la alerta del sistema.

### 3.8 Actualizar sin push (nuestro caso)

- **Empezar**: solo con la app **en primer plano**, salvo desde un
  `LiveActivityIntent` (Centro de control, atajo, botón de acción), que
  arranca el proceso de la app sin abrirla
  (<https://developer.apple.com/documentation/appintents/liveactivityintent>).
- **Actualizar o terminar en segundo plano**: la documentación dice que se
  puede «mientras la app corre en segundo plano, por ejemplo con
  BackgroundTasks» (A6). Pero los ingenieros de Apple lo matizan en los foros:
  lo soportado es **push**; las apps de **audio** tienen prohibido
  actualizar con el iPhone bloqueado; otros modos «pueden permitirlo, pero no
  está soportado explícitamente» (P2, 748569 y 776031). **El modo trayecto
  (ubicación en segundo plano) probablemente funcione, pero no está
  garantizado.** Con la geocerca la app tiene solo unos segundos.
- **La Live Activity no tiene red ni ubicación propias** (A6): todo lo que
  enseña lo trae la app.
- **Sin cifras de presupuesto** para las actualizaciones locales; el sistema
  puede fusionarlas si llegan muy seguidas (P3).
  `NSSupportsLiveActivitiesFrequentUpdates` solo sube el presupuesto de
  **push**
  (<https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates>).
- **Consecuencia de diseño**: la Live Activity tiene que ser **veraz aunque
  se congele**. Cuenta atrás y antigüedad por fecha, `staleDate` y un estado
  «dato antiguo» diseñado.

### 3.9 Widgets: presupuesto y timeline

Fuente: <https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date>.

- **40–70 recargas al día** para un widget que se mira a menudo, más o menos
  **cada 15–60 min**. Cada widget colocado tiene su propio presupuesto de 24 h,
  que se ajusta al uso del usuario.
- **Entradas separadas unos 5 minutos como mínimo** («should create timeline
  entries that are at least about 5 minutes apart»).
- **No gastan presupuesto**: la app **en primer plano**, una sesión de audio
  o navegación activa, un App Intent del propio widget, una animación, y los
  cambios de idioma, Dynamic Type o accesibilidad. En StandBy se refresca al
  ritmo del sistema.
- Políticas del timeline: `.atEnd`, `.after(fecha)` y `.never`. La app pide
  recargar con `WidgetCenter.reloadTimelines(ofKind:)`.
- El widget **puede pedir datos por red** en su proveedor de timeline
  (URLSession). Cada recarga sería una llamada a nuestro servidor, que tiene
  caché por estación (R64–R67). Necesita la dirección y el token, así que
  también depende de compartir datos con la app (§3.15).
- `WidgetPushHandler` (iOS 26) requiere push: no lo tenemos.

### 3.10 Duración, fin y dato caducado

- **8 h activa**. A las 8 h el sistema la termina y la quita de la isla; en
  la pantalla de bloqueo puede seguir **hasta 4 h más** (12 h en total) (A6).
- **Terminar** con `end(_:dismissalPolicy:)` y **un estado final**: con
  `.default` se queda hasta 4 h, con `.immediate` se va, y con
  `.after(fecha)` se va en esa fecha (dentro de las 4 h). La HIG recomienda
  **15–30 min** para un resumen final.
- Si el usuario **quita la Live Activity a mano**, esta pasa a `.dismissed`,
  pero eso **no cancela la acción** que la creó (A6). La app lo ve con
  `activityStateUpdates` y decide qué hacer con el modo trayecto.
- **`staleDate`**: al llegar esa fecha, el estado pasa a `.stale` y
  `context.isStale` a `true`. La vista se vuelve a pintar sin la app (A6,
  <https://developer.apple.com/documentation/activitykit/activitycontent/staledate>).
  Es la pieza que hace posible R19 en la Live Activity.
- Si hay varias Live Activities de la app, `relevanceScore` decide cuál va a
  la isla.
- El usuario puede **desactivar** las Live Activities de la app en Ajustes:
  se consulta con `areActivitiesEnabled` y `activityEnablementUpdates`.
  Arrancar puede fallar si el dispositivo llegó a su límite de actividades.

### 3.11 Tamaño del estado y aislamiento

- Estático + dinámico: **4 KB en total**, contando cada actualización y el
  estado final (A6). Nada de meter los avisos enteros (hasta 3 en francés más
  su traducción): solo el nivel y una etiqueta.
- Las imágenes deben venir en el paquete de la extensión (o en un App Group) y
  no pueden superar el tamaño de la presentación. Los colores de línea son un
  hex en el estado, así que no necesitamos imágenes.
- Los datos de la Live Activity viajan por ActivityKit: **no hace falta App
  Group** para ella.

### 3.12 Renderizado, tintado, cristal y accesibilidad

| Plataforma | Color completo | Acentuado | Vibrante |
|---|---|---|---|
| iPhone | inicio, Hoy, StandBy, CarPlay (sin fondo) | inicio y Hoy (aspecto **tintado** o **transparente**) | **pantalla de bloqueo**, StandBy con poca luz |
| iPad | inicio, Hoy | inicio, Hoy | pantalla de bloqueo |
| Watch | Smart Stack, complicaciones | Smart Stack, complicaciones | no |
| Mac | escritorio, Centro de notificaciones | no | escritorio |

Fuente: A2 y
<https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances>.

- **Acentuado** (iOS 26): quita el fondo y pone **cristal** (transparente) o
  un **tinte**; pinta **en blanco** tanto el grupo principal como el de acento
  (`widgetAccentable`). Las imágenes opacas pasan a blanco liso, y lo
  transparente conserva su opacidad
  (<https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass>).
  Para imágenes: `widgetAccentedRenderingMode(.accented | .desaturated |
  .accentedDesaturated | .fullColor)`; Apple recomienda **desaturated**.
  - **Una forma rellena con texto dentro** (el distintivo de línea o la caja
    de vía) **se convierte en un bloque blanco** y el texto desaparece.
    Solución: texto **calado** (knockout, con `compositingGroup` y
    `blendMode(.destinationOut)`) o pasar a contorno cuando
    `widgetRenderingMode != .fullColor` [a verificar en el simulador].
- **Vibrante**: se usan **grises opacos**, no blanco con opacidad. El brillo
  decide la viveza: lo claro destaca y lo oscuro retrocede (A2).
- **StandBy con poca luz**: todo rojo. **Always-On**: luminancia reducida.
- **Fondo removible**: `containerBackground(for: .widget) { … }`
  (<https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background>).
  En los de bloqueo, `AccessoryWidgetBackground()` para el disco o el
  recuadro del sistema.
- **Cristal propio**: en widgets el cristal **lo pone el sistema**. No hay
  documentación de que `glassEffect` se pinte dentro de una extensión, así que
  no dependemos de él. La isla es negra opaca, y la de bloqueo tiene el fondo
  del sistema o un tinte.
- **iOS 26.1** añade Ajustes > Pantalla y brillo > **Liquid Glass:
  Transparente / Tintado** (el tintado es más opaco), que convive con
  «Reducir transparencia» y «Aumentar contraste»
  (<https://techcrunch.com/2025/11/04/ios-26-1-lets-you-turn-down-liquid-glass-transparency>).
  Si los minutos y la vía van en cápsulas **opacas**, estos ajustes no les
  afectan. En la de bloqueo, con `accessibilityReduceTransparency`, el tinte
  translúcido pasa a sólido [a verificar que el entorno llegue a la
  extensión].
- **VoiceOver**: cada presentación necesita su etiqueta
  (<https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities>,
  «Provide accessibility labels»). Una frase completa por salida (R50).

### 3.13 Interactividad y enlaces

- **Botones**: `Button(intent:)` o `Toggle(intent:)` con un
  **`LiveActivityIntent`** (iOS 17), que **se ejecuta en el proceso de la
  app**. En la Live Activity solo se permiten en la **expandida** y en la
  **de bloqueo**
  (<https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities>).
- **Con el iPhone bloqueado**, «los botones están inactivos y el sistema no
  ejecuta nada **hasta que la persona se autentica y desbloquea**». Parar
  desde la pantalla de bloqueo = tocar y Face ID.
- **CarPlay**: botones desactivados (A1, A6). En el Watch sí funcionan.
- **Widgets**: botones en pequeño, mediano, grande y en los de bloqueo
  circular y rectangular. Cada interacción garantiza una recarga del
  timeline.
- **Enlaces**: `widgetURL(_:)` (**uno solo** por jerarquía) para todo el
  widget o la Live Activity, y `Link` para destinos por zona en el
  rectangular, el pequeño y mayores. El de **en línea** tiene **un único**
  destino
  (<https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity>).
  La app lo recibe en `onOpenURL`. Las dos piezas de la compacta deben llevar
  al mismo sitio (A1).
- Un **App Shortcut** que arranque la Live Activity (botón de acción, Siri)
  es una idea que Apple sugiere (A1).

### 3.14 Otros sitios donde aparece

- **Apple Watch (Smart Stack)**: por defecto **combina la compacta leading +
  trailing** del iPhone. Para dar un diseño propio,
  `.supplementalActivityFamilies([.small])` y `@Environment(\.activityFamily)`.
  Tamaños: 152 × 69,5 (40 mm) … 191 × 81,5 (49 mm). Sin app de Watch, tocar
  abre una vista a pantalla completa con un botón para abrir la app en el
  iPhone (A1).
- **CarPlay (iOS 26)**: la Live Activity sale en el Dashboard, con la
  compacta combinada o con la familia `.small`. Tamaños: **240 × 78**,
  **240 × 100** y **170 × 78**. Sin botones. Los widgets pequeños salen a todo
  color y sin fondo (A1, A4).
- **Mac (macOS 26)**: en la **barra de menús**, con la compacta, la mínima y
  la expandida sin cambios; al hacer clic se abre la app por Duplicación del
  iPhone (A1, A4).
- **StandBy**: la mínima arriba; al tocarla, la de bloqueo al 200 %. Apple
  recomienda el fondo por defecto (A1).
- **La compacta es la pieza que más se reutiliza** (Watch, CarPlay, Mac):
  tiene que entenderse sola.

### 3.15 Firma con Apple ID gratuito

- **Tabla oficial de Apple**
  (<https://developer.apple.com/help/account/reference/supported-capabilities-ios>),
  columna «Apple Developer», que es la cuenta **gratuita** («no cost … can't
  distribute apps»): **App groups: sí**, **Background modes: sí**,
  **Keychain sharing: sí**; **Push notifications: no**, **Siri: no** y **Time
  Sensitive Notifications: no**. Lo he comprobado leyendo el HTML de la
  página.
- **La Live Activity no necesita App Group ni push**: necesita
  `NSSupportsLiveActivities` y la extensión de widgets, y se actualiza en
  local. En teoría **funciona con una cuenta gratuita** si la extensión
  sobrevive a la firma.
- **Los widgets sí necesitan compartir datos** con la app (App Group o llavero
  compartido) para leer la caché o, si piden por red, la dirección y el
  token.
- **En la práctica**, con Apple ID gratuito: la firma **caduca a los 7 días**;
  hay como mucho **3 apps** a la vez y **10 App IDs por semana**
  (<https://docs.sidestore.io/docs/faq>). Cada extensión necesita su propio
  identificador [a verificar si cuenta para ese límite]. Además, el
  identificador del App Group tiene que registrarse en el equipo de quien
  firma y hay que reescribir los entitlements de la app y de la extensión:
  **depende de lo que haga IPA Station**.
- **Recomendación**: antes de dar por hecho que con la cuenta gratuita solo
  vale la IPA `lite`, **probar una `full` firmada con IPA Station** y apuntar
  el resultado en `docs/decisiones.md`. La detección en tiempo de ejecución
  (R60) se mantiene en cualquier caso.

---

## 4. Choques con otros documentos del proyecto

| Documento | Qué dice | Qué dicen Apple y la práctica | Propuesta |
|---|---|---|---|
| `docs/arquitectura.md` §7 | widgets con un «timeline con entradas por minuto» | entradas separadas **unos 5 min como mínimo** (§3.9) | entradas en las **horas de salida**, fusionadas si distan menos de 5 min, y la cuenta atrás por fecha |
| `docs/arquitectura.md` §7, encargo 3.5 | la cuenta atrás con `Text(timerInterval:)` | enseña segundos y el dato es HH:MM; en un widget se estira | precisión de minuto (iOS 18+) y `timerInterval` solo como alternativa en iOS 17, con marco fijo |
| `docs/arquitectura.md` §5, `README.md` | «sin App Groups → sin widget ni Live Activity»; la capa `Capabilities` deduce las extensiones a partir del App Group | la cuenta gratuita **sí** tiene App Groups según Apple; la Live Activity **no** necesita App Group | comprobar con IPA Station; en tiempo de ejecución, la Live Activity se decide con `areActivitiesEnabled` y los widgets con el App Group |
| `docs/arquitectura.md` §6 y §7 | «cada 30 s … actualiza la Live Activity» en segundo plano | «no soportado explícitamente» sin push (§3.8) | se mantiene, pero el diseño aguanta congelado (`staleDate` y fechas) |
| encargo 3.4 | «Parar desde la Live Activity» | con el iPhone bloqueado **pide Face ID**; en CarPlay no hay botones | se asume; el texto del botón no promete «sin desbloquear» |
| `design-lab/referencias.md` | compacta «≈ 44 pt cada hueco» | **52,33 pt** (393) y **62,33 pt** (430) | el laboratorio usa las cifras de la HIG (§5) |
| `design-lab` (marco 390 × 844) | se usa como «iPhone» genérico | 390 × 844 es un iPhone 14 **sin isla** | para la Live Activity y la isla, usar los valores de 393 × 852 (iPhone 16) |

No he tocado esos documentos: se corrigen en la fase que les toca (2B.4 y
FASE 3).

---

## 5. Tamaños que debe usar el laboratorio (`b-cristal-v2`)

Para los tres marcos del laboratorio (`design-lab/LEEME.md`: 390 × 844,
430 × 932 y 375 × 667):

| Pieza | Marco 390 (tratar como iPhone 16, 393) | Marco 430 | Marco 375 (SE, sin isla) |
|---|---|---|---|
| Live Activity de bloqueo | 371 × 84–160, margen 14, útil 343 | 408 × 84–160, útil 380 | [estimación] 353 × 84–160, útil 325 |
| Isla compacta | 52,33 × 36,67 por lado; isla de 230 | 62,33 × 36,67; isla de 250 | no hay |
| Isla mínima | 36,67–45 × 36,67 | igual | no hay |
| Isla expandida | 371 × 84–160; ≈ 120 pt por lado junto a la cámara | 408 × 84–160 | no hay |
| Widget pequeño | 158 × 158 | 170 × 170 | 148 × 148 |
| Widget mediano | 338 × 158 | 364 × 170 | 321 × 148 |
| Widget grande | 338 × 354 | 364 × 382 | 321 × 324 |
| Bloqueo circular | 72 × 72 | 76 × 76 | 68 × 68 |
| Bloqueo rectangular | 160 × 72 | 172 × 76 | 153 × 68 |
| Bloqueo en línea | 234 × 26 | 257 × 26 | 225 × 26 |
| Márgenes de widget | 16 (11 para agrupar) | 16 | 16 |

Y además, para simular los modos: **color completo claro y oscuro**,
**acentuado** (todo blanco sobre cristal o tinte), **vibrante** (grises
opacos sobre el fondo de pantalla), **rojo nocturno** de StandBy y
**Always-On** (luminancia reducida y sin animación).

---

## 6. Qué implica para Trajet

Quince principios para el rediseño. Cada variante del laboratorio se revisa
contra ellos (2B.3).

1. **Una pregunta, una cifra.** En cada superficie, lo más grande son **los
   minutos del próximo paso del tramo que toca** (R1, R48). La compacta,
   15–17 pt heavy; la de bloqueo, 40–48 pt; el widget pequeño, ≥ 52 pt. «1h46»
   (R6) tiene que caber: `ViewThatFits`, o `minimumScaleFactor` **solo en la
   cifra** y nunca por debajo de 0,7. En la isla el Dynamic Type se limita;
   en los widgets se prueba hasta AX5.

2. **Una sola cuenta atrás, de minuto en minuto y ligada a la fecha.** Nunca
   «6 min» junto a «05:58». La cifra no puede congelarse si la app deja de
   actualizar: se calcula desde la hora de salida (`at` en `Europe/Paris`). En
   iOS 18+, con los formatos de minuto (§3.6); en iOS 17,
   `Text(timerInterval:countsDown: true)` con marco fijo. **Sin segundos**: el
   dato no los tiene. Nunca `.timer` ni `.relative` solos, porque vuelven a
   contar al pasar la hora.

3. **La antigüedad siempre se ve y envejece sola.** La referencia es la hora
   de llegada menos `data_age` (R17), escrita con texto de fecha del sistema.
   En la Live Activity, **`staleDate` = el primero de: llegada + 90 s (R19) o
   salida del tren mostrado + 60 s**. Al pasar, `context.isStale` activa el
   estado «dato antiguo» (todo apagado, R19) **sin la app**. Si
   `refresh_hint_s` es mayor de 60 s, esos 90 s crecen (a decidir en 2B). En
   los widgets, la edad **es contenido y no pie de página**: casi siempre
   tendrá de 15 a 60 min.

4. **Vía real ≠ probable por forma y palabra, en todos los modos** (R10).
   Real: **caja rellena** + «Vía». Probable: **contorno punteado** +
   «probable» (o «prob.»). En la compacta y la mínima basta la forma, y la
   palabra va en VoiceOver y en la expandida. En los modos acentuado,
   vibrante, rojo nocturno y Always-On, el número de la caja rellena va
   **calado**, y el amarillo solo existe a todo color. La vía que aparece (R2)
   = transición de ≤ 2 s + alerta del sistema, no un latido en bucle
   (imposible, §3.7).

5. **Sin hueco de vía donde no hay vía** (R3). Con `platform_expected ==
   false` (metro, bus, tranvía) la fila se cierra. En los trenes, la vía
   aparece solo cuando existe y nunca es una columna fija (R2).

6. **Destino entero o abreviado con reglas, nunca cortado a mitad de
   palabra.** La app prepara 2–3 variantes: completo; con abreviaturas fijas
   («Saint»→«St», «Sainte»→«Ste», fuera «Paris » y «Gare de»); y corto. La
   vista elige con `ViewThatFits` y `lineLimit(1)`, sin «…» dentro de una
   palabra. Si no cabe ninguna, se quita el destino antes que cortarlo; en un
   tramo con un solo sentido ya se sabe (R24). Las variantes caben de sobra en
   los 4 KB.

7. **Una línea secundaria por bloque, con prioridad fija.** Nunca
   «Saint-Lazare · 12:56 · 05:58». El orden es: destino > vía > retraso (solo
   si existe y ≠ 0, R4/R14) > longitud (R5) > hora. Lo que no cabe **se cae
   entero**, no se aprieta.

8. **El siguiente tren y el tramo, siempre legibles.** En la de bloqueo y en
   la expandida: «luego 14 min» (por fecha) y, en rutas de varios tramos,
   «tramo 1 de 2 · transbordo en Saint-Lazare → 13». El tramo actual lo decide
   la app (por la hora y las geocercas). La Live Activity **no puede cambiar
   de tramo sola**; si se congela, `staleDate` lo dice.

9. **La isla habla sola en sus tres tamaños.**
   - **Compacta**: leading = distintivo de línea con su color oficial (R12);
     trailing = minutos + vía como forma. Estrecha, equilibrada y con marco
     fijo (el temporizador ensancha la isla).
   - **Mínima**: los minutos, no un logo.
   - **Expandida**: leading = línea y destino, trailing = minutos grandes,
     center o bottom = vía, siguiente tren, antigüedad y «Parar». Cada cosa en
     el mismo sitio que en la compacta.

   La compacta es la que se reutiliza en el Watch, en CarPlay, en el Mac y en
   iOS 27 en apaisado: si solo cabe una cosa, son los minutos.

10. **Una sola acción: Parar.** `Button(intent:)` con `LiveActivityIntent` en
    la expandida y en la de bloqueo. Con el iPhone bloqueado pide Face ID, y
    en CarPlay no existe. Al parar: `end` con el estado final «Trayecto
    terminado», retirada a los 15 min (o inmediata si se paró a mano). Si el
    usuario quita la Live Activity, la app lo ve (`.dismissed`).

11. **Tocar lleva a la ruta.** `widgetURL` hacia la ruta y el tramo en la
    Live Activity y en los widgets, un `Link` por fila en el mediano y el
    grande, y un único destino en el de línea. Las dos piezas de la compacta,
    al mismo sitio.

12. **Estados diseñados, no errores.** Vía real, vía probable, sin vía, bus a
    1h46, línea cortada o aviso, en andén (R15, distinto de «ya»), transbordo,
    dato antiguo, sin conexión / servidor sin clave (`server.prim_key`), y
    trayecto terminado. Cada uno con **palabra + símbolo**, nunca solo color.
    Del aviso solo se enseña la etiqueta y el nivel; nunca el texto (4 KB,
    francés, R8), que se lee en la app.

13. **El color es un lujo que el sistema quita.** El color de línea solo va
    en el distintivo (con contraste garantizado, R12), y el amarillo solo en
    la vía real a todo color. En los modos acentuado, vibrante, StandBy
    nocturno y Always-On la jerarquía tiene que funcionar **en gris**, con
    tamaño, peso y forma. El fondo es removible (`containerBackground`) y no
    se dibuja cristal propio: el cristal lo pone el sistema. Los «billetes»
    (minutos y vía) son opacos, así que «Reducir transparencia», «Tintado» y
    «Aumentar contraste» no cambian nada importante.

14. **Movimiento con mesura.** `numericText(countsDown: true)` en los
    minutos, transiciones de ≤ 2 s cuando cambia algo (vía que aparece, cambio
    de tramo), nada en Always-On y nada con «Reducir movimiento» (R51).
    **Alertas** solo para la vía publicada, el cambio de vía y la línea
    cortada; nunca por un cambio de minuto.

15. **Widgets: una foto con fecha que sabe cuándo caduca.**
    - **Timeline**: entradas en las horas de salida conocidas (fusionadas si
      distan menos de 5 min) y una **entrada final** que, al agotarse los
      pasos, cambia a «sin datos recientes · abre Trajet».
    - **Recargas**: desde la app en primer plano (gratis) y, en modo trayecto,
      con cuentagotas (40–70 al día).
    - **Tamaños**: pequeño = una cifra enorme con la línea, la vía y la edad;
      mediano = 2–3 filas con destino por fila; grande = el tablero de la ruta
      que toca, con todos sus tramos y el estado de cada línea (no el pequeño
      estirado).
    - **Bloqueo**: circular = anillo o cifra por fecha (el `ProgressView`
      tiene el fallo del 100 %, a verificar); rectangular = línea, minutos y
      vía en dos líneas sin desbordar; en línea = «J 6 min · Vía 11».

### Del prototipo B a los principios

| Problema del prototipo B (encargo 2B) | Límite o causa | Principio |
|---|---|---|
| Destino cortado («Ermont - Eaub…») | truncado de cola por defecto | 6 |
| Texto secundario apelotonado en varias líneas | todo en una línea con «·» | 7 |
| Cuenta atrás duplicada («6 min» y «05:58») | dos formatos a la vez y segundos inventados | 2 |
| Falta la antigüedad del dato | la Live Activity no refresca sola | 3 |
| Barra de progreso incomprensible | barra sin etiqueta; `ProgressView` con fallos | 15 (y T9: nada de barras sin etiqueta) |
| Sin siguiente tren, tramo ni transbordo | — | 8 |
| Sin acción para parar | — | 10 |
| Expandida = bloqueo apretada | no usa las regiones de la isla | 9 |
| Compacta con minutos en un hueco raro | sin marco fijo; reparto leading/trailing | 9 |
| Mínima que no se entiende sola | logo en vez de dato | 9 |
| Widget pequeño con hueco central y minutos pequeños | — | 1 |
| Mediano: vía descolocada, sin destino por fila, sin edad | — | 4, 6, 3 |
| Widgets de bloqueo dependientes del color; rectangular desbordado | modo vibrante; 160 × 72 pt | 4, 13, 15 |
| Circular sin medidor | `Gauge` estático; `ProgressView` con fallo | 15 |

---

## 7. Fuentes

Apple (diseño y documentación):

- HIG Live Activities: <https://developer.apple.com/design/human-interface-guidelines/live-activities>
- HIG Widgets: <https://developer.apple.com/design/human-interface-guidelines/widgets>
- Displaying live data with Live Activities: <https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities>
- Creating custom views for Live Activities: <https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities>
- Keeping a widget up to date: <https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date>
- Animating data updates: <https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities>
- Accented rendering mode y Liquid Glass: <https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass>
- Contextos y apariencias: <https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances>
- Fondo del widget: <https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background>
- StandBy y CarPlay: <https://developer.apple.com/documentation/widgetkit/adding-standby-and-carplay-support-to-your-widget>
- Fechas dinámicas: <https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates>
- Interactividad: <https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities>
- Enlaces: <https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity>
- LiveActivityIntent: <https://developer.apple.com/documentation/appintents/liveactivityintent>
- staleDate: <https://developer.apple.com/documentation/activitykit/activitycontent/staledate>
- end(_:dismissalPolicy:): <https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)>
- NSSupportsLiveActivitiesFrequentUpdates: <https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates>
- Text(timerInterval:): <https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)>
- SystemFormatStyle.Timer / DateReference / DateOffset: <https://developer.apple.com/documentation/swiftui/systemformatstyle/timer>, <https://developer.apple.com/documentation/swiftui/systemformatstyle/datereference>, <https://developer.apple.com/documentation/swiftui/systemformatstyle/dateoffset>
- TimeDataSource: <https://developer.apple.com/documentation/swiftui/timedatasource>
- numericText(countsDown:): <https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(countsdown:)>
- isLuminanceReduced: <https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced>
- WidgetRenderingMode: <https://developer.apple.com/documentation/widgetkit/widgetrenderingmode>
- Capacidades por tipo de cuenta: <https://developer.apple.com/help/account/reference/supported-capabilities-ios>
- WWDC23 10194: <https://developer.apple.com/videos/play/wwdc2023/10194/>
- WWDC25 278: <https://developer.apple.com/videos/play/wwdc2025/278/>
- WWDC26 223: <https://developer.apple.com/videos/play/wwdc2026/223/>
- Spotlight on: The Dynamic Island: <https://developer.apple.com/news/?id=mis6swzt>
- Foros: [757140](https://developer.apple.com/forums/thread/757140), [748569](https://developer.apple.com/forums/thread/748569), [776031](https://developer.apple.com/forums/thread/776031), [722073](https://developer.apple.com/forums/thread/722073), [760027](https://developer.apple.com/forums/thread/760027)

Terceros:

- WWDCNotes 2025-278: <https://wwdcnotes.com/documentation/wwdc25-278-whats-new-in-widgets/>
- Use Your Loaf, guía WWDC26: <https://useyourloaf.com/blog/wwdc-2026-viewing-guide/>
- MacRumors, widgets de bloqueo abajo en iOS 26: <https://www.macrumors.com/how-to/ios-move-lock-screen-widgets-bottom-display/>
- TechCrunch, Liquid Glass tintado en iOS 26.1: <https://techcrunch.com/2025/11/04/ios-26-1-lets-you-turn-down-liquid-glass-transparency>
- Swift and Sour: <https://swiftandsour.com/live-activity-not-so-live-%F0%9F%98%B5-part-2/>
- dev.to (presupuesto): <https://dev.to/hellomisterdev/why-your-ios-live-activity-silently-stops-updating-lmd>
- simonbs/ios-widget-sizes: <https://github.com/simonbs/ios-widget-sizes>
- SideStore FAQ: <https://docs.sidestore.io/docs/faq>
- Apps: las de §2.2 y §2.3, con su enlace en cada entrada.
