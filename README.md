# Trajet · app iOS

Cliente nativo (SwiftUI) del servidor Trajet. Enseña los próximos pasos de los
trayectos habituales por Île-de-France, con datos en vivo del portal PRIM.

El servidor no se toca: esta app solo consume su API.

---

## Cómo se saca el .ipa

No hace falta un Mac. Cada `push` a `main` dispara
[`.github/workflows/ios.yml`](.github/workflows/ios.yml), que compila en un
runner macOS de GitHub y deja el **`.ipa` sin firmar** como artifact.

```
push a main
   ↓
runner macOS · xcodegen + xcodebuild (CODE_SIGNING_ALLOWED=NO)
   ↓
Payload/Trajet.app → Trajet.ipa          ← artifact «Trajet-ipa-<nº>»
   ↓
IPA Station lo firma con el Apple ID gratuito
   ↓
iPhone
```

Para bajarlo: pestaña **Actions** → última ejecución → *Artifacts* →
`Trajet-ipa-N`. Es un zip; dentro va el `.ipa`, que es lo que come IPA Station.

También se puede lanzar a mano desde Actions con **Run workflow**.

### Firmar y caducidad

Con un Apple ID gratuito la firma **caduca a los siete días** y hay que
reinstalar desde IPA Station. Eso condiciona la app y por eso no lleva nada
que necesite permisos que Apple no da a las cuentas gratuitas:

- sin notificaciones push
- sin App Groups → **sin widget ni Live Activity**
- sin iCloud ni llavero compartido

Todo lo que guarda la app (direcciones del servidor, último tablero) vive en
su propio contenedor, así que **reinstalar encima no borra nada**: el
identificador `com.ismaeloul.trajet` no cambia entre versiones.

### Compilar en un Mac, si algún día hay uno

```bash
brew install xcodegen
xcodegen generate        # crea Trajet.xcodeproj a partir de project.yml
open Trajet.xcodeproj
```

El `.xcodeproj` **no se versiona**: se genera. Lo que se edita es
[`project.yml`](project.yml).

---

## Cómo llega al servidor

Dos direcciones, que se prueban en orden y se recuerda la que responde:

| | dirección | cuándo sirve |
|---|---|---|
| Red de casa | `http://192.168.1.188:7796` | en casa, sin pasar por el relé |
| Tailscale | `http://100.99.38.76:7796` | desde la calle y con datos |

Se cambian en **Ajustes**, dentro de la app. La primera vez iOS pedirá permiso
para hablar con la red local: hay que dárselo o la dirección de casa no
funcionará (Tailscale sí).

---

## Lo que decide el diseño

No es una app de planificar viajes: es de **mirar de reojo si llego**. De pie,
andando por una estación, con una mano, dos o tres segundos, a contraluz. De
ahí salen casi todas las decisiones.

Estos números están **medidos** contra la API real (sondeo del 30 de agosto,
32 122 observaciones) y son los que mandan sobre la pantalla:

| dato | consecuencia en la app |
|---|---|
| La vía aparece solo en el **17 %** de los trenes, con 7,7 min de mediana | la vía nunca es una columna fija; cuando aparece, **se canta** (caja amarilla y latido) |
| Metro, bus y tranvía **no publican vía jamás** (0 de ~600) | en esos modos no se reserva el hueco: sería un vacío permanente |
| **26 de 36** líneas no mandan hora teórica | en metro y bus no hay retraso que enseñar, y no se finge |
| **No existe** dato de ocupación | donde el prototipo dibujaba «crowding» va `length`, que sí es real (tren corto/largo, en el 61 % de las salidas) |
| Hay buses a **106 y 165 min** | los minutos se pintan `1h46`, no `106` |
| Cuota de **1000 llamadas/día** por endpoint | el tablero se refresca cada 30 s y **solo mientras se está mirando**; en segundo plano el bucle se para en seco |
| Los avisos llegan **en francés** y se traducen aparte | se enseña el francés y se dice «traduciendo»; nunca se espera al modelo |

Dos reglas que no se negocian:

1. **Nunca se borra la pantalla.** Si la API falla, se queda el último tablero
   bueno y lo que cambia es su antigüedad. Se guarda en disco, así que la
   primera apertura del día tampoco enseña un hueco.
2. **La vía probable no puede leerse como la real.** No se distinguen por un
   matiz de color, que a contraluz se pierde, sino por la forma y la palabra:
   caja sólida con «Vía» contra recuadro punteado con «probable».

---

## Cómo está montado

```
Trajet/
  Model/      Board, Routes, Plan, Stats   ← calcados de la API, decodificación tolerante
  Net/        ServerConfig, TrajetAPI      ← las dos direcciones y el reintento
  Store/      BoardStore, RoutesStore      ← el bucle de 30 s y la caché en disco
  Design/     Theme, LineColor, Format     ← paleta, contraste de los distintivos, «1h46»
  Views/      Board · Routes · Plan · Stats · Settings
  Resources/  PreviewData                  ← bancos de prueba con la forma real de la API
```

`Design/` es donde vive lo discutible: la paleta neutra, los cuerpos de letra
y las reglas de redacción. Los colores de línea **no** se eligen aquí: vienen
en `line_color` y son los que están pintados en las paredes de la estación.
Son los únicos colores saturados de la pantalla.

### Las vistas previas hacen de banco de pruebas

`PreviewData` no son maquetas: son respuestas con la forma exacta de la API,
elegidas para cubrir lo que un JSON feliz esconde —tramo vacío, línea cortada,
aviso sin traducir, vía que aparece, vía solo probable, bus a 106 minutos,
tren parado en el andén y destinos mezclados—. En Xcode, el lienzo de
`BoardView`, `DepartureChip` y `LegCardView` enseña esos casos sin servidor.

---

## Endpoints que consume

| | |
|---|---|
| `GET /api/board?route_id=` | el tablero; cada 30 s mientras está visible |
| `GET /api/routes` · `POST` · `PUT` · `DELETE` | rutas guardadas |
| `GET /api/search/places?q=` | direcciones, paradas y sitios (planificador) |
| `GET /api/plan?from=&to=&when=&mode=` | itinerarios |
| `POST /api/routes/from-plan` | guardar el itinerario elegido |
| `GET /api/search/stops?q=` | solo paradas (editor manual) |
| `GET /api/stops/{id}/lines` · `/directions?line_id=` | líneas y sentidos que circulan ahora |
| `GET /api/alternatives/{id}` | solo al tocar «Buscar alternativa», nunca en el refresco |
| `GET /api/stats` · `GET /api/platform-model` | historial |
| `GET /api/health` | estado y cuota, en Ajustes |

El porcentaje de acierto de la previsión sale de `/api/platform-model` y solo
de ahí. El servidor se puntúa solo y sin sesgo, así que **la app no le
pregunta nunca al usuario si acertó**: preguntarlo da peor dato y encima
interrumpe justo cuando hay que echar a andar.
