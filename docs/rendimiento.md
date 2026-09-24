# Rendimiento: batería del modo trayecto y arranque

Qué gasta Trajet, cuánto debería gastar **por diseño** y cómo se mide de
verdad. Los números de este documento son **objetivos y cuentas de diseño,
no medidas**: los reales los mide el usuario en su iPhone (apartado 4) y se
apuntan en la tabla del final.

## 1. Qué gasta el modo trayecto y por qué está acotado

El modo trayecto (`Trajet/App/Trip/`) es lo único que puede tener la app
despierta con la pantalla apagada. Se enciende **a mano** («Empezar
trayecto») y **nunca** se queda encendido: se apaga al llegar (a menos de
~150 m de la estación de destino), al pasar el tiempo máximo (90 min por
defecto, `TripSettings.maxMinutes`) o a mano (app o Live Activity).

| Pieza | Cómo está hecha | Por qué gasta poco |
|---|---|---|
| Ubicación | `CLLocationManager` con `desiredAccuracy = kCLLocationAccuracyHundredMeters`, `distanceFilter = 50`, `activityType = .otherNavigation` | Con 100 m iOS tira casi siempre de wifi y antenas, no del GPS. Llegar se decide con un radio de 150 m: no hace falta más precisión |
| Segundo plano | `allowsBackgroundLocationUpdates = true` **solo** durante el trayecto (y `false` al terminar) + `CLBackgroundActivitySession` (iOS 17) | Fuera del trayecto la app no se despierta nunca por la ubicación |
| Pausa automática | `pausesLocationUpdatesAutomatically = false` | Si iOS pausara (tren parado en un túnel), no la reanuda solo en segundo plano y se perdería la llegada. El gasto lo acota el tiempo máximo, no la pausa |
| Tablero | `board.setTripMode(true)`: el bucle sigue cada `max(30, server.refresh_hint_s)` s, sin historial (R7, R40) | Una petición HTTP pequeña al servidor de casa (LAN o Tailscale). Si el servidor va justo de cuota, el `refresh_hint_s` alarga el intervalo solo |
| Live Activity | Se reescribe con cada tablero y en cada cambio de la cifra (1 por minuto); una foto igual a la anterior no se reescribe antes de 45 s | Escrituras locales, sin push ni red |
| Geocercas | `CLMonitor` (iOS 17) en las estaciones habituales, radio 200 m, como mucho 20; solo con permiso «Siempre» y activadas en Ajustes | Las vigila el sistema con antenas y wifi, sin GPS y sin la app despierta. Al entrar: un refresco del tablero y, como mucho, uno cada 5 min |

Lo que **no** hay: ni ubicación continua fuera del trayecto, ni posición de
trenes en vivo, ni push, ni sondeo en segundo plano sin trayecto.

## 2. Cuentas por hora de trayecto (diseño)

Con los valores por defecto (`refresh_hint_s` = 30):

| Qué | Por hora | De dónde sale |
|---|---|---|
| Peticiones al servidor | ≈ 120 (≈ 30 si el servidor pide 120 s) | 3600 / 30 |
| Escrituras de la Live Activity | ≤ 180 (120 por tablero + 60 por minuto; menos con la regla de los 45 s) | ver §1 |
| Posiciones entregadas a la app | depende de lo que se mueva: ≈ 1 cada 50 m (en metro a 30 km/h, unas 10 por minuto; parado, casi ninguna) | `distanceFilter = 50` |
| Refrescos por geocerca | 1 por estación en la que se entra (máx. 1 cada 5 min) | `TripController.geofenceCooldown` |
| Tiempo encendido como mucho | 90 min por trayecto | `TripSettings.maxMinutes` |

**Objetivo de diseño** (a comprobar, no medido): que una hora de trayecto
con la pantalla apagada gaste **del orden de un 3–6 % de batería** en un
iPhone reciente con buena salud de batería, y que un día sin trayectos las
geocercas no se noten en *Ajustes › Batería* (menos de un 1 % atribuido a
Trajet). Si la medida real se sale mucho de eso, lo primero que se mira es si
iOS ha encendido el GPS (interiores, sin wifi) y si el `refresh_hint_s` es el
esperado.

## 3. Arranque: en frío < 1 s y primer dato < 1,5 s

| Qué | Qué se mide exactamente | Cómo lo consigue la app |
|---|---|---|
| **Arranque en frío < 1 s** | Desde que se toca el icono (proceso nuevo) hasta que se ve el tablero **con lo último guardado** | `BoardStore` pinta la caché de disco (`BoardCache`) en el `init`, antes de pedir nada (R9, R20). Nada de red, Llavero ni mapas en el camino del primer fotograma; el modo trayecto solo crea su `CLLocationManager` (no pide permiso ni posiciones) |
| **Primer dato < 1,5 s** | Desde que se toca el icono hasta que el tablero enseña un tablero **recién llegado del servidor** (la píldora pasa a «hace 0 s») | Una sola petición `/api/v1/board`, con timeouts cortos y la dirección (LAN o Tailscale) que respondió la última vez primero (R42, R43) |

El primer dato depende de la red y del servidor: se mide en casa por wifi
(LAN) y fuera por Tailscale, por separado.

## 4. Cómo se mide (lo hace el usuario)

### 4.1 Prueba manual de batería en el iPhone (la que vale)

No hace falta Mac. Se hace dos veces en condiciones parecidas y se resta:

1. **Referencia** (sin trayecto): batería entre el 80 y el 95 %, sin cargar,
   las mismas apps abiertas de siempre. Apunta el % y la hora, bloquea el
   iPhone 60 min y vuelve a apuntar el %.
2. **Trayecto**: mismas condiciones. Abre Trajet, «Empezar trayecto» en una
   ruta de verdad (o en casa, con una ruta cuyo destino esté lejos, para que
   no se apague al llegar), bloquea el iPhone y déjalo 60 min. Apunta el %
   al empezar y al acabar.
3. **Resultado**: % por hora del trayecto − % por hora de la referencia =
   coste del modo trayecto. Apúntalo en la tabla de abajo.
4. Mira también *Ajustes › Batería › últimas 24 h*: el % atribuido a Trajet y
   su «Actividad en segundo plano». Y en *Ajustes › Privacidad › Localización
   › Trajet*, que el permiso es el esperado; durante el trayecto debe verse el
   indicador azul de ubicación, y al terminar debe desaparecer.
5. **Geocercas**: un día normal con las geocercas activadas y sin trayectos;
   al día siguiente, en *Ajustes › Batería*, Trajet no debería pasar de ~1 %.

Consejos: la misma ruta y la misma hora del día; sin «Modo de bajo
consumo»; si el iPhone se calienta o está cargando, la prueba no vale.

### 4.2 Con un Mac (si algún día lo hay)

- **Instruments › Power Profiler** (Xcode 26) o **Energy Log** con el iPhone
  conectado: grabar 10–15 min de trayecto con la pantalla apagada y mirar
  CPU, red, ubicación y pantalla. Se busca: CPU casi a cero entre refrescos,
  un pico de red cada 30 s y la ubicación en «baja precisión».
- **Xcode › Debug navigator › Energy Impact** durante un trayecto con el
  iPhone conectado: debería quedarse en «Low» casi todo el rato.
- **Arranque**: plantilla *App Launch* de Instruments (tiempo hasta el
  primer fotograma) o un test de UI con
  `measure(metrics: [XCTApplicationLaunchMetric()])` en el CI; el primer
  dato, con *Network* de Instruments (hora de la respuesta de
  `/api/v1/board` desde el arranque).

### 4.3 Arranque sin Mac

- **En frío**: quita Trajet del selector de apps, graba la pantalla y toca el
  icono. En la grabación, cuenta los fotogramas desde el toque hasta que se
  ve el tablero guardado (a 60 fps, 60 fotogramas = 1 s).
- **Primer dato**: en la misma grabación, hasta que la píldora pasa a
  «hace 0 s» / «en directo». Repite 5 veces y apunta la mediana, una tanda
  por wifi de casa y otra por datos móviles con Tailscale.

## 5. Resultados medidos

Los rellena el usuario. Sin medir, no hay número.

| Fecha | iPhone / iOS | Prueba | Resultado | Notas |
|---|---|---|---|---|
| — | — | Batería: referencia (% / h) | — | — |
| — | — | Batería: trayecto (% / h) | — | — |
| — | — | Geocercas, un día (% en Ajustes › Batería) | — | — |
| — | — | Arranque en frío (s, mediana de 5) | — | — |
| — | — | Primer dato por LAN (s) | — | — |
| — | — | Primer dato por Tailscale (s) | — | — |
