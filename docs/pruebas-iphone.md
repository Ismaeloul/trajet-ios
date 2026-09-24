# Pruebas en el iPhone (lo que el simulador no prueba bien)

Checklist manual, paso a paso y con el resultado esperado. Es lo que **no**
cubren los tests de interfaz ni las capturas del CI (`TrajetUITests/`, modo
`capturas`): instalar las dos IPA, emparejar con el panel de verdad, GPS,
geocercas, Live Activity con el iPhone bloqueado, widgets, batería, red y
accesibilidad con datos reales.

Cómo usarla: una sección por sesión; marca `[x]` lo que sale bien y apunta
al lado lo que no (iPhone, iOS, fecha). Lo que falle va a
`docs/pendiente.md`. Los números de batería van a la tabla de
`docs/rendimiento.md` §5.

Antes de empezar:

- [ ] El servidor responde en casa (`http://192.168.1.188:7796/api/v1/ping`
      desde Safari devuelve `"service": "trajet"`) y por Tailscale
      (`http://100.99.38.76:7796/api/v1/ping` con el wifi apagado).
- [ ] El panel del Umbrel tiene la clave de PRIM puesta (si no, el tablero
      dirá «servidor sin clave de PRIM»: es correcto, pero no sirve para
      probar lo demás).
- [ ] Hay al menos dos rutas guardadas en el panel, una con un tren (RER o
      Transilien, que publican vía) y otra con metro o bus.

---

## 1. Instalar las dos IPA

Las dos salen del mismo `push` (artefacto `Trajet-ipa-<n>` de Actions) y
tienen el **mismo bundle id** (`com.ismaeloul.trajet`): instalar una encima
de la otra conserva el emparejamiento, las direcciones y la caché.

### 1.1 IPA full (certificado tipo Signulous)

- [ ] Sube `Trajet-full.ipa` a Signulous (o al firmador que use certificado
      de empresa/desarrollador con **App Groups**). Al firmar, comprueba que
      los entitlements incluyen `group.com.ismaeloul.trajet` (la IPA ya lleva
      una firma ad hoc solo para que viajen dentro).
- [ ] Instala. Icono «Trajet» en la pantalla de inicio; abre y sale la
      pantalla de emparejar (negra, marco del escáner, «Escanear el QR» y
      «Escribir a mano»).
- [ ] En **Ajustes › Widgets y Live Activity** (dentro de la app, tras
      emparejar) dice «Widgets: disponibles» y «Live Activity: disponible».
      Si dice «no disponibles» con la full, la firma no ha metido el App
      Group: es cosa del firmador, no de la app (R60).
- [ ] Mantén pulsada la pantalla de inicio › «+» › busca «Trajet»: aparecen
      los tres tamaños (pequeño, mediano, grande). En la pantalla de bloqueo
      (Personalizar) aparecen el circular, el rectangular y el de una línea.
- [ ] En *Ajustes de iOS › Trajet* están: Ubicación, Red local, Cámara y
      **Live Activities** (activadas).

### 1.2 IPA lite (Apple ID gratuito)

- [ ] Sube `Trajet-lite.ipa` a IPA Station / Sideloadly con el Apple ID
      gratuito. Instala. **La firma caduca a los 7 días**: pasado ese tiempo
      la app no abre y hay que reinstalar (no se pierde nada).
- [ ] Abre: misma app, mismas pantallas, mismo emparejamiento.
- [ ] **Ajustes › Widgets y Live Activity** dice «no disponibles» / «no
      disponible» y explica que es la versión lite y por qué (R60). Nada se
      rompe: tablero, mapa, rutas, historial y ajustes funcionan igual.
- [ ] Mantén pulsada la pantalla de inicio › «+»: Trajet **no** ofrece
      widgets. Al empezar un trayecto no sale Live Activity (la app lo dice
      en el pie de la tarjeta del trayecto).
- [ ] *Ajustes de iOS › Trajet* **no** tiene «Live Activities».
- [ ] Instala la full encima de la lite (o al revés): sigue emparejada y con
      la misma ruta elegida.

---

## 2. Emparejar con el QR del panel real

- [ ] Panel del Umbrel › «Emparejar un iPhone»: sale un QR y el código
      `ABCD-EFGH` con una cuenta atrás de 5 minutos.
- [ ] App › «Escanear el QR»: iOS pide permiso de cámara **después** de la
      explicación (nunca al abrir la app). Da el permiso.
- [ ] Enfoca el QR: el marco se pone verde y encoge, «Conectando con
      «Trajet de casa»…», y en 1–2 s «Listo. iPhone de Isma emparejado.»
      con vibración. Tras 1,2 s funde a las pestañas con el tablero.
- [ ] El panel pasa solo a «Emparejado» con el nombre del iPhone (sin
      recargar).
- [ ] La primera vez que la app habla con la red de casa, iOS pide **Red
      local**: dale permiso. Si lo niegas, la dirección de casa no responde y
      solo funciona Tailscale (R45); Ajustes › Permisos lo explica.
- [ ] Vuelve a escanear el **mismo** QR (Ajustes › «Emparejar de nuevo»):
      «Ese código ya no vale» (un código sirve una vez). Genera otro en el
      panel y funciona.
- [ ] Escanea un QR que no sea de Trajet (una URL cualquiera): «Ese QR no es
      de Trajet. Enfoca el del panel del servidor.» y sigue buscando.
- [ ] Con la cámara del sistema (app Cámara de iOS) enfoca el QR: sale el
      enlace `trajet://pair…` y al tocarlo se abre Trajet y empareja igual.
- [ ] «Escribir a mano»: escribe el código en minúsculas y sin guion
      («abcdefgh») y solo la dirección de casa: empareja igual. La dirección
      de Tailscale la rellena el servidor (Ajustes › Servidor las enseña las
      dos).
- [ ] Panel › Dispositivos › revoca el iPhone: al siguiente refresco el
      tablero dice «iPhone sin emparejar» en la píldora (con el último
      tablero debajo) y, sin caché, la pantalla «Este iPhone no está
      emparejado» con «Emparejar de nuevo».

---

## 3. GPS real y llegada automática

Con una ruta cuyo destino esté a más de 400 m de donde empiezas (la app
«arma» la llegada cuando ya has estado lejos: empezar al lado del destino no
cuenta como llegar).

- [ ] Tablero › «Empezar trayecto» (o pestaña Trayecto): la **primera vez**
      sale la explicación de la app («Ubicación durante el trayecto», con
      Continuar / Sin ubicación / Cancelar) y, tras «Continuar», el aviso de
      iOS. Elige «Permitir mientras se usa la app».
- [ ] El botón pasa a «Parar trayecto», el tablero dice «Trayecto en marcha ·
      sigue en segundo plano · se apaga al llegar», y en la barra de estado
      sale el indicador azul de ubicación mientras dura.
- [ ] Pestaña Trayecto: «N min a pie hasta <estación>» (minutos de Apple, no
      de la API), el punto azul de tu posición y, si la estación es SNCF y
      hay vía, la vía señalada en su andén.
- [ ] Haz el trayecto de verdad con el iPhone bloqueado. Al llegar a menos
      de ~150 m de la estación de destino: el trayecto termina solo, la Live
      Activity dice «Trayecto terminado · has llegado · se quita sola a las
      HH:MM» y el indicador de ubicación desaparece.
- [ ] Al abrir la app: aviso efímero «Has llegado: trayecto terminado» (si
      la app estaba delante) y en la tarjeta del trayecto la nota «Trayecto
      terminado: has llegado. · HH:MM» durante 30 min, con su «x».
- [ ] *Ajustes de iOS › Privacidad › Localización › Trajet* enseña «Mientras
      se usa» y, tras el trayecto, la app **no** vuelve a usar la ubicación
      (no aparece en el resumen de uso reciente).

## 4. Tiempo máximo

- [ ] Ajustes › Modo trayecto › «Tiempo máximo»: baja a **15 min** (el
      mínimo; el paso es de 15 y se enseña «15 min» / «1h30» según R6).
- [ ] Empieza un trayecto sin moverte. El pie de la tarjeta dice «se apaga
      solo a las HH:MM» (hora de inicio + 15 min, solo si no hay GPS) o
      «sigue en segundo plano · se apaga al llegar».
- [ ] Bloquea el iPhone y espera 15 min: la Live Activity pasa a «Trayecto
      terminado · se pasó el tiempo máximo» y se quita sola 15 min después
      (lo dice: «se quita sola a las HH:MM»).
- [ ] Al abrir la app: aviso «Trayecto parado: se ha pasado el tiempo
      máximo» y «Empezar trayecto» otra vez. Vuelve a poner 90 min.

## 5. Parar desde la Live Activity y desde la app

- [ ] Con un trayecto en marcha, bloquea el iPhone: en la Live Activity de
      la pantalla de bloqueo hay un botón «Parar». Tócalo: pide Face ID (si
      el iPhone está bloqueado) y la actividad **desaparece al momento**
      (parar a mano no deja resumen).
- [ ] Al abrir la app: «Empezar trayecto» otra vez, sin aviso efímero (parar
      a mano ya se vio) y sin indicador de ubicación.
- [ ] Empieza otro. Mantén pulsada la Dynamic Island: en la vista expandida
      también está «Parar». Igual que arriba.
- [ ] Empieza otro y para desde la app (tablero o pestaña Trayecto): la Live
      Activity se quita al momento y la isla se cierra.
- [ ] Empieza otro, cierra la app del todo (deslizar en el selector) y vuelve
      a abrirla: **el trayecto sigue** (se guardó en disco) y la Live
      Activity es la misma (no sale otra). Para desde la app: se quita.
- [ ] Con un trayecto en marcha, Ajustes › «Desemparejar este iPhone»: se
      para el trayecto y se quita la Live Activity antes de volver a la
      pantalla de emparejar.

## 6. Geocercas (entrar en una estación con la app cerrada)

- [ ] Ajustes › Modo trayecto › «Geocercas en tus estaciones»: al activarlo
      sale la explicación (ya a la vista en el pie) y iOS pide el permiso
      **«Siempre»** (o «Cambiar a permitir siempre»). Concede.
- [ ] Aparece la sección «Estaciones vigiladas» con las paradas de subida de
      tus rutas marcadas por defecto («Ahora: las paradas donde empiezan tus
      rutas»). Desmarca una: el pie pasa a «Elegidas a mano» y sale «Volver a
      las de siempre».
- [ ] Niega el permiso «Siempre» (o déjalo en «Mientras se usa» desde
      Ajustes de iOS): el interruptor se queda apagado y dice «Las geocercas
      necesitan el permiso de ubicación «Siempre»» con «Abrir Ajustes».
- [ ] Con las geocercas activas, **cierra la app del todo** y entra andando
      en una estación vigilada (radio 200 m). En *Ajustes de iOS › Batería* o
      en la Consola de un Mac no se puede ver desde el iPhone; lo que se ve:
      al abrir Trajet después, la píldora del tablero dice «hace N s/min»
      con una antigüedad **menor** que el tiempo que llevaba cerrada (se
      refrescó al entrar, sin historial).
- [ ] Con un trayecto en marcha y el iPhone bloqueado, entra en una estación
      vigilada: la Live Activity se pone al día (antigüedad «hace 0 s»)
      aunque no hubiera tocado refresco. Como mucho una vez cada 5 min por
      geocerca.
- [ ] Un día entero con geocercas y sin trayectos: *Ajustes de iOS ›
      Batería › últimas 24 h* no atribuye a Trajet más de ~1 % (apúntalo en
      `docs/rendimiento.md`).

## 7. Live Activity en bloqueo y Dynamic Island con el iPhone bloqueado

Lo que se comprueba: que la cifra la sigue escribiendo la app cada minuto
con el iPhone bloqueado (Apple no lo garantiza sin push) y que, si deja de
escribir, el `staleDate` la congela con horas fijas en vez de mentir.

- [ ] Empieza un trayecto en una ruta con tren y bloquea el iPhone. En la
      pantalla de bloqueo: distintivo, destino, «hace N s», el billete con la
      cifra grande (dos tallas: «6» + «min»), la vía (caja amarilla «Vía 21»
      o punteada «probable 21»), y abajo «luego HH:MM» o el transbordo, y
      «Parar».
- [ ] Sin desbloquear, mira cada minuto durante 10 min: la cifra baja de
      minuto en minuto y «hace N s» se queda por debajo de ~40 s (la app
      refresca cada 30 s y escribe). Apunta cuántos minutos se saltó (si se
      saltó alguno).
- [ ] Deja el iPhone bloqueado 15 min sin tocarlo. Si iOS suspende la app,
      la actividad pasa a **congelada**: apagada (gris), «sin actualizar ·
      hace N min», y en lugar de la cifra la **hora fija** «sale a las
      12:56» del tren que enseñaba (o del siguiente si ese ya salió). Nunca
      una cuenta atrás que no baja.
- [ ] Desbloquea y abre la app: la actividad vuelve a estar viva en el
      primer refresco (cifra y «hace N s»).
- [ ] Dynamic Island (iPhone 14 Pro o posterior): compacta = distintivo a la
      izquierda y cifra + caja de vía a la derecha; mínima (con otra
      actividad) = aro del color de la línea con la cifra; pulsación larga =
      expandida con destino, cifra grande, matriz de vía, estado y «Parar».
- [ ] Cuando aparece la vía (o cambia): la actividad **alerta** (la isla se
      expande sola un momento con la franja «Vía 21 · anunciada ahora» /
      «cambio de vía · antes 21») y vibra. Un cambio de minuto **nunca**
      alerta.
- [ ] Un tren cancelado: el billete pasa al siguiente y el pie dice «✕ el de
      las 12:56, cancelado», con alerta.
- [ ] Línea cortada durante el trayecto: billete rojo «Sin circulación · toca
      para ver alternativas»; al tocar se abre la app en la hoja de
      alternativas.
- [ ] Sin conexión (modo avión un minuto): la actividad se apaga y dice «sin
      conexión · hace N min», la cifra sigue bajando (la escribe la app con
      su último tablero). Quita el modo avión: vuelve a vivo.
- [ ] Toca la actividad (fuera de «Parar»): abre Trajet en el tablero, en la
      ruta del trayecto.
- [ ] Con Dynamic Type al tope (Ajustes › Pantalla y brillo › Tamaño del
      texto, o Accesibilidad): la actividad no pasa de 160 pt de alto y nada
      se corta (los textos caen por prioridad, no se truncan a mitad).

## 8. Widgets de inicio y de bloqueo

- [ ] Pequeño: cabecera con el distintivo y el destino, billete con la cifra
      del sistema («6» + «min», o «6 min» de una talla si iOS no da el número
      suelto), vía o «luego HH:MM», y «hace N min» abajo. Con ≥ 60 min, hora
      fija «sale a las 14:36».
- [ ] Mediano: la columna del pequeño + «desde …» con dos filas (destino,
      hora, vía). Grande: un bloque por tramo. Un nivel de abreviatura del
      destino por widget (no una fila abreviada y otra no).
- [ ] Una vía **probable** sigue probable en el widget aunque la Live
      Activity, viva, ya diga «Vía 21» (el widget es una foto).
- [ ] Deja pasar los trenes de la foto sin abrir la app: el widget va
      cambiando de tren por su cuenta y, al acabarse, «Sin datos recientes ·
      abre Trajet». Con metro (paso < 5 min) la cifra puede quedarse en
      «0 min» unos minutos entre entradas: límite aceptado.
- [ ] Toca el widget: abre el tablero en esa ruta; una fila del mediano abre
      ese tramo; sin clave de PRIM abre Ajustes del servidor.
- [ ] **Tintado (iOS 26)**: mantén pulsada la pantalla de inicio › Editar ›
      Personalizar › Tintado (y también «Transparente»). El widget pasa a
      blanco: el billete es una forma blanca con la cifra calada o en
      contorno, la vía real caja llena, la probable punteada. Se sigue
      distinguiendo real de probable **sin color** (R10). Si algo sale como
      un bloque blanco sin cifra, apúntalo (es el calado; hay alternativa
      «contorno» en `GlanceInk.accentedKnockout`).
- [ ] **Reducir transparencia** (Ajustes › Accesibilidad › Pantalla y
      tamaño): el widget y la app siguen legibles; en la app el cristal pasa
      a opaco con canto.
- [ ] **Bloqueo**: circular (aro solo si faltan ≤ 30 min; si no, la hora),
      rectangular (línea + destino, cifra + vía, antigüedad) y en línea («J ·
      6 min · Vía 21 · hace 5 min», cae por el final). En el bloqueo todo va
      en gris (vibrante): real caja llena, probable punteada.
- [ ] **StandBy** (iPhone cargando en horizontal): el widget se ve en grande;
      de noche (rojo) la jerarquía se entiende solo por tamaño y forma.
      Siempre activa (iPhone 14 Pro+): sin animación y legible atenuado.
- [ ] Sin conexión: el pequeño enseña el símbolo junto al distintivo y
      «hace N min» en rojo; mediano y grande «sin conexión · hace N min».
      Servidor sin clave: símbolo de servidor y toca → Ajustes.
- [ ] Al volver a abrir la app, cambiar de ruta o aparecer una vía en
      trayecto, el widget se recarga (como mucho una vez cada 2 min; si
      cambia algo antes, queda pendiente, no se pierde).

## 9. Batería del modo trayecto

Sigue `docs/rendimiento.md` §4.1 al pie de la letra (referencia sin
trayecto y trayecto de 60 min, mismas condiciones) y apunta en §5.

- [ ] Referencia: % al empezar y a los 60 min bloqueado, sin trayecto.
- [ ] Trayecto: ruta cuyo destino esté lejos (para que no se apague al
      llegar), tiempo máximo a 90 min, «Empezar trayecto», bloquear, 60 min.
      % al empezar y al acabar.
- [ ] Resta: objetivo de diseño **3–6 % por hora** en un iPhone reciente. Si
      se sale mucho: mira si iOS encendió el GPS (interior sin wifi) y si el
      `refresh_hint_s` del servidor es el esperado (Ajustes › Cuota).
- [ ] *Ajustes de iOS › Batería › últimas 24 h*: % de Trajet y «Actividad en
      segundo plano». Durante el trayecto se ve el indicador azul; al
      terminar, desaparece.
- [ ] Arranque en frío: graba la pantalla, cierra la app del todo, tócala.
      Objetivo: el tablero guardado en < 1 s y el primer dato del servidor en
      < 1,5 s (por wifi de casa; aparte por Tailscale). Mediana de 5.

## 10. Legibilidad a contraluz en un andén

La regla 1: mirar de reojo si llego, de pie, con una mano, 2–3 s, con el sol
detrás del iPhone.

- [ ] En un andén al aire libre, brillo automático, sol de cara: en 2–3 s se
      leen **la cifra** y **la vía** de la primera salida sin acercar el
      iPhone (billete opaco negro con cifra blanca en claro; en oscuro,
      blanco con negro).
- [ ] Vía real (amarilla, «Vía 21») frente a probable (recuadro punteado,
      «probable 21»): se distinguen sin fijarse en el color.
- [ ] «En andén» (billete verde) frente a «ya»: se distinguen.
- [ ] Con gafas de sol polarizadas: lo mismo (el OLED puede oscurecerse en
      vertical; gira el iPhone si hace falta y apúntalo).
- [ ] Modo oscuro y modo claro: en los dos se leen cifra y vía a contraluz;
      el mapa de cabecera no compite con el billete.
- [ ] Letra grande (AX3): el billete pasa a dos filas y la cifra sigue
      siendo lo primero que se ve.

## 11. Red local y Tailscale (ATS)

- [ ] En casa, wifi: Ajustes › Servidor › «Probar conexión»: «Red de casa:
      responde · Trajet 0.4.0» y «Tailscale: responde · Trajet 0.4.0» (si
      Tailscale está encendido) o «no responde».
- [ ] «Conectado por» dice «red de casa».
- [ ] Wifi apagado, datos móviles, Tailscale encendido: el tablero sigue
      refrescando; «Conectado por» pasa a «Tailscale» tras el primer fallo
      de la de casa (un fallo de red salta de dirección; un error HTTP no,
      R42).
- [ ] Tailscale **apagado** y sin wifi: la píldora dice «sin conexión ·
      último tablero hace N min» y el tablero se queda (R9). Sin caché: «No
      se llega al servidor · Ni por la red de casa ni por Tailscale».
- [ ] Ajustes › Tailscale: escribe el nombre MagicDNS
      (`http://<nombre>.<tailnet>.ts.net:7796`): la nota dice «Nombre
      MagicDNS de Tailscale (*.ts.net): también vale por HTTP» y «Probar
      conexión» responde. Con la IP `100.x.x.x` la nota dice que la app ya
      lleva la excepción.
- [ ] Escribe una dirección pública por HTTP (`http://ejemplo.com:7796`): la
      nota avisa «iOS no deja hablar por HTTP con esta dirección…» y, al
      probar, «no responde». Con `https://` no hay aviso. (ATS: sin
      `NSAllowsArbitraryLoads`; solo red local, 100.64.0.0/10 y ts.net.)
- [ ] Deniega «Red local» en Ajustes de iOS: la de casa deja de responder y
      solo va Tailscale; Ajustes › Permisos › Red local lo explica (R45).
      Vuelve a permitirla.
- [ ] «Restablecer direcciones»: vuelven las del emparejamiento y se olvida
      la preferida.

## 12. Cambio de red durante un trayecto

- [ ] Empieza un trayecto en casa por wifi. Sal de casa (o apaga el wifi)
      con Tailscale encendido: el trayecto **no se para**, la Live Activity
      sigue actualizándose y «Conectado por» pasa a Tailscale. Como mucho un
      refresco fallido (la píldora puede decir «sin conexión» un momento).
- [ ] En un túnel de metro (sin datos): la actividad se apaga con «sin
      conexión · hace N min» y la cifra sigue bajando; al salir, vuelve a
      vivo sola sin tocar nada.
- [ ] Modo avión 3 min con trayecto: igual que arriba; al quitarlo, el
      siguiente refresco (≤ 30 s) lo revive.
- [ ] Cambia de wifi a datos y vuelta varias veces: ningún refresco se queda
      colgado (los timeouts son de 6 s / 12 s, R43).

## 13. VoiceOver y letra grande en el tablero

- [ ] VoiceOver activado, tablero con datos: cada salida se lee como **una
      frase** («Tren a Ermont - Eaubonne, en 6 minutos, a las 12:56, vía 21,
      tren largo.»), sin trocearla (R50). La vía probable se lee «vía 21
      probable, 90 por ciento sobre 20 observaciones, por el número de tren».
- [ ] La píldora: «Dato de hace 6 segundos, en directo.» El distintivo:
      «Línea J». El botón redondo del mapa: «Abrir el mapa de la ruta»; el de
      ajustes: «Ajustes».
- [ ] Un aviso en francés sin traducir se lee con **voz francesa**.
- [ ] Cuando aparece la vía en directo, VoiceOver anuncia «Acaba de salir la
      vía 21» y el iPhone vibra (si «Vibrar cuando aparece la vía» está
      activado en Ajustes).
- [ ] La ruta de la cabecera es un menú: VoiceOver dice «Ruta: Casa →
      Trabajo, botón. Toca para cambiar de ruta»; se cambia con el rotor.
- [ ] En Rutas, con VoiceOver, las acciones personalizadas «Ver en el
      tablero», «Borrar», «Subir» y «Bajar» funcionan (arrastrar no hace
      falta).
- [ ] Letra grande **AX3** (Accesibilidad › Pantalla y tamaño de texto): el
      billete pasa a dos filas (cifra y destino arriba; vía, ritmo y
      metadatos debajo), el destino admite dos líneas y no se corta a mitad
      de palabra, las fichas pasan a dos por pantalla, las estadísticas a
      una ficha por fila, los días del editor a dos filas de botones de 44 pt,
      y las pestañas conservan su etiqueta.
- [ ] Con letra grande y «Reducir movimiento»: el punto «en directo» no
      ondea, la vía nueva enseña un anillo fijo en vez de latir y la barra de
      refresco se sustituye por «próximo en N s» en la píldora (R51).
- [ ] «Aumentar contraste»: cantos visibles en tarjetas y cristal, y los
      textos de estado (aviso, error, bien) siguen legibles.
- [ ] Texto en **negrita** (Accesibilidad): las cifras siguen heavy y el
      resto engorda sin romper la maqueta.
