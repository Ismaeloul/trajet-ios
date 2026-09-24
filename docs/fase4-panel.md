# FASE 4 · El panel probado en el navegador

El panel de administración «Cristal» (`trajet-server/app/panel`) probado **de
verdad** como lo haría el dueño: un servidor levantado con `docker compose`
en este PC (BD vacía, sin clave de PRIM, `TRAJET_ADMIN_PEERS=auto`), el
navegador integrado de la sesión para recorrerlo con clics, `curl` haciendo de
iPhone, y `design-lab/tools/capturar.mjs` (Chrome headless) para las capturas y
los GIF a tamaños exactos. Hecho el 24-09-2026 en dos sesiones (la primera se
cortó por límite de uso tras dejar las capturas 01-19 y los GIF).

Las capturas están en [`capturas/panel-fase4/`](capturas/panel-fase4/README.md)
(84 PNG: 21 estados × móvil/PC × claro/oscuro, y 4 GIF).

## 1. Cómo se probó

| qué | cómo |
|---|---|
| Servidor | `env -u PRIM_API_KEY docker compose up --build -d` en `trajet-server` → imagen `trajet:dev`, contenedor `trajet-dev`, panel en `http://127.0.0.1:7796`. `/api/health` → 200 con `key_configured: false`; el panel avisa «No hay clave de PRIM» y «No hay APP_SEED». Sin 403 de `TRAJET_ADMIN_PEERS` (el `auto` del compose vale para 127.0.0.1). |
| Navegador integrado | Pestaña recién abierta (consola y red a cero) a **390 × 844 claro**: recorrido entero con clics, teclado y `read_page`/`find`; consola y red leídas en cada paso. A **1440 × 900 oscuro**: carga, maquetación, refresco, clave falsa y Ajustes por teclado (ver §5 sobre los clics con la vista escalada). |
| iPhone | Simulado con `curl`: `POST /api/v1/pair` con el código que enseña la pantalla, y luego llamadas con el token para comprobar que vale y que deja de valer al revocar. |
| Chrome headless | `capturas/panel-fase4/plan_capturas.py` genera un plan que recorre el panel **cuatro veces** (móvil/PC × claro/oscuro) pulsando los botones de verdad (`click()` desde la página, el iPhone simulado con `fetch` a `/api/v1/pair`) y captura 19 estados y los 4 GIF; `plan-caducado.json` genera un QR y espera 5 min de reloj para la 20 (último minuto) y la 21 (caducado). El script apunta cualquier excepción, `console.error` o recurso fallido. |
| Corte de red | Real: `docker compose stop` con el panel abierto, y `start` después. (En la captura 19 se cortó `fetch` desde la página, que da el mismo estado.) |

## 2. Qué se probó y cómo salió

Leyenda: **N** = a mano en el navegador integrado · **H** = por Chrome headless con `capturar.mjs` (mismo recorrido, mismas comprobaciones de consola) · **C** = hay captura (número). Todo lo de la tabla salió bien salvo lo marcado con ✗ (una cosa, ya corregida, §4).

| Sección / caso | Móvil claro | Móvil oscuro | PC claro | PC oscuro | Detalle |
|---|---|---|---|---|---|
| Cabecera: nombre, versión, píldora («Cargando…» → «Revisar» por el error de clave), botón actualizar | N H C01 | H C01 | H C01 | N H C01 | En móvil la versión se esconde y queda solo el nombre del servidor. |
| Resumen (Clave «Sin clave», Cuota 0 % «Normal», iPhones, En marcha) y avisos (error sin clave, info sin APP_SEED) | N H C01 | H C01 | H C01 | N H C01 | Los avisos salen tal cual los manda `/api/admin/overview`. |
| Emparejar: generar QR (imagen SVG en `data:`, código `XXXX-XXXX`, cuenta atrás desde 4:59 con barra, «Esperando al iPhone…», direcciones que lleva el QR) | N H C02 C03 GIF1 | H C02 C03 | H C02 C03 | H C02 C03 | La cuenta atrás va con el reloj del navegador desde que llega la respuesta. |
| Emparejar: anular → «Código anulado» + «Generar otro» | H C04 | H C04 | H C04 | H C04 | `DELETE /api/admin/pairing/{id}` → 200. |
| Emparejar: el iPhone canjea el código → «Emparejado: iPhone de Isma» en el siguiente sondeo (2 s), el dispositivo aparece abajo y el contador sube a 1 | N H C05 GIF2 | H C05 | H C05 | H C05 | Con `curl` desde fuera (N) y con `fetch` desde la página (H). El mismo código otra vez → 401 `pairing_invalid`. |
| Emparejar: último minuto (cuenta atrás en ámbar, barra casi vacía) | N H C20 | H C20 | H C20 | H C20 | Esperado de reloj, sin acelerar nada. |
| Emparejar: **caducado** a los 5 min → «Caducado» + «Generar otro» | N H C21 | H C21 | H C21 | H C21 | El último sondeo devuelve 200 con `status: expired` (no 404). |
| Emparejar: código anulado desde otro sitio (otro navegador genera un QR) → «Código anulado» | N | — | — | — | Visto sin querer (§6): el servidor anula el QR anterior y el panel lo refleja en el siguiente sondeo. |
| Dispositivos: lista (modelo, app, último uso, IP) y vacía («Ningún iPhone…» + «Emparejar uno») | N H C06 | H C06 | H C06 | H C06 | |
| Dispositivos: renombrar en línea (Enter guarda, aviso «Ahora se llama…», el foco vuelve al botón) | N | — | — | — | `PATCH /api/admin/devices/11` → 200. Sin captura: el estado dura lo que dura el aviso. |
| Dispositivos: revocar con diálogo modal (foco inicial en «Cancelar», fondo desenfocado) → lista vacía, contador 0, aviso «… ya no tiene acceso» | N H C07 C08 GIF3 | H C07 C08 | H C07 C08 | H C07 C08 | `DELETE` → 200. Con el token revocado, `curl /api/v1/routes` → **401** «el token no vale o el dispositivo está revocado»; antes de revocar daba 200. |
| Clave de PRIM: sin clave (recuadro rojo con el enlace al portal y el formulario abierto) | N H C09 | H C09 | H C09 | H C09 | |
| Clave de PRIM: clave corta → el panel la para sin llamar al servidor, campo vacío y marcado | N H C10 | H C10 | H C10 | H C10 | «La clave tiene que tener de 8 a 256 caracteres.» |
| Clave de PRIM: clave falsa `CLAVEFALSA1234567890` → «Probando con PRIM…» → 422 «No se ha guardado: PRIM no reconoce la clave (401)» con las tres APIs | N H C11 GIF4 | H C11 | H C11 | N (teclado) H C11 | El servidor la prueba contra PRIM de verdad (401 en las tres). |
| Clave de PRIM: el ojo enseña/oculta lo escrito; al enviar el campo vuelve a `password` y se vacía | N | — | — | N | |
| Clave de PRIM: **nunca en el DOM ni en la red** | N | — | — | N | `outerHTML` sin la clave tras enviar; el cuerpo del 422 solo lleva `checks` y `error`; el overview solo `last4: null`. |
| Cuota: tres medidores 0 / 1000, hora del reinicio en hora local, historial de 7 días | N H C12 | H C12 | H C12 | H C12 | |
| Salud: versión, en marcha, hora en París, memoria (RSS de 384 MB), BD, contenido, mapa | N H C13 | H C13 | H C13 | H C13 | ✗ en móvil el valor «2 h 53 min» salía como «2 h 5…» → corregido (§4). |
| Traducción (Ollama): «Sin configurar» y la explicación | N H C14 | H C14 | H C14 | H C14 | |
| Andenes y previsión: colector «En marcha», acierto sin previsiones, última pasada, ritmo «sin clave de PRIM» | N H C15 | H C15 | H C15 | H C15 | ✗ en móvil «sin previsiones aún» salía «sin previsión…» → corregido (§4). |
| Errores recientes: desplegar, contador, el aviso `trajet.prim` sin clave | N H C16 | H C16 | H C16 | H C16 | |
| Ajustes del QR: nombre y las dos direcciones guardadas | N H C17 | H C17 | H C17 | H C17 | |
| Ajustes: dirección con ruta (`…/api`) → error del panel sin petición, campo marcado | N H C18 | H C18 | H C18 | H C18 | «Solo host y puerto, sin ruta…» |
| Ajustes: dirección con usuario:contraseña → error del panel, campo marcado (`aria-invalid`) | N | — | — | N (teclado) | «Sin usuario ni contraseña.» |
| Ajustes: guardar válida → `PUT /api/admin/settings` 200, «Guardado. Los QR nuevos ya lo llevan.», y el QR siguiente las lleva («El QR lleva: Casa … · Tailscale …») | N H C03 | H C03 | H C03 | N (teclado) H C03 | |
| Sin conexión: franja «No hay conexión con el servidor. Se enseña lo último que se supo.», píldora «Sin conexión» (ámbar porque hay datos), datos intactos | N H C19 | H C19 | H C19 | H C19 | N con el contenedor parado de verdad. |
| Sin conexión: «Reintentar» con el servidor caído (la franja sigue) y recuperación al volver | N | — | — | — | Ver §5: la recuperación la hizo el refresco automático de 15 s antes de que me diera tiempo a pulsar el botón. |
| Refresco automático cada 15 s y «actualizado a las hh:mm:ss» en el pie | N | — | — | N | |
| Maquetación: 1 columna (móvil), 3 columnas de 434 px (1440), sin desbordamiento horizontal, oscuro real (`prefers-color-scheme`) | N H | H | H | N H | |

## 3. Errores de consola y peticiones fallidas

Lo que dice el propio navegador (`read_console_messages` solo errores y
`read_network_requests`), pestaña abierta limpia para la ocasión:

| dónde | errores de consola | peticiones ≥ 400 o fallidas | esperado |
|---|---|---|---|
| Móvil claro, recorrido entero | 1 × «Failed to load resource: 422» | `POST /api/admin/prim-key` → 422 (una vez) | Sí: es la clave falsa. |
| Ídem, corte de red | 23 × `net::ERR_CONNECTION_REFUSED` | `GET /api/admin/*` fallidas mientras el contenedor estuvo parado (dos paradas) | Sí: es la prueba «sin conexión». |
| PC oscuro | 1 × 422 | `POST /api/admin/prim-key` → 422 | Sí. |
| Chrome headless, 4 pasadas + GIF | 5 × 422 | `POST /api/admin/prim-key` → 422 (una por pasada y una del GIF 4) | Sí. |
| Chrome headless, 20-21 | ninguno | ninguna | — |

Cero excepciones de JavaScript, cero `console.error` propios del panel y
ningún 4xx/5xx que no fuera de una prueba negativa. Todo lo demás: 200, 201
(`POST /api/admin/pairing`) y 304 (el sprite de iconos, con caché).

Fuera del navegador, con `curl`, los 4xx esperados de las pruebas negativas:
401 al canjear un código ya usado (`pairing_invalid`), 401 en `/api/v1/routes`
sin token y 401 con el token revocado (`unauthorized`). `/api/v1/ping` es
público y responde 200 con `paired: false` al token revocado, como dice el
contrato.

## 4. Lo corregido en el panel

Una sola cosa, de CSS, con test:

- **Las casillas («tiles») de «Salud del servidor» y «Andenes» recortaban el
  valor en un iPhone.** A 390 px las tres casillas de una fila tienen 78 px
  útiles y `.tile .num` llevaba `white-space: nowrap` + `text-overflow:
  ellipsis`: «2 h 53 min» (108 px) salía como «2 h 5…» y la nota «sin
  previsiones aún» (99 px) como «sin previsión…». Se perdía el dato. Las
  capturas de la primera sesión no lo enseñaron porque el servidor llevaba 3-4
  minutos («4 min» cabe); se vio en la segunda, con 2 h 53 min en marcha.
  Arreglo en `app/panel/static/panel.css`: el valor y la nota saltan de línea
  en vez de recortarse (la fila se estira a la misma altura) y a ≤ 430 px el
  valor baja de 1,45 a 1,25 rem. Test nuevo
  `tests/test_panel.py::test_css_las_casillas_no_recortan_el_valor`.
  Comprobado en el navegador tras reconstruir la imagen: anchura 78 px =
  anchura de desplazamiento 78 px (nada oculto), dos líneas.

Nada que apuntar de la API (`app/api/*` y el contrato sin tocar).

## 5. Lo que no se pudo probar (o no del todo)

- **Login de Umbrel.** Aquí no hay Umbrel; el aviso «La sesión de Umbrel ha
  caducado: recarga la página» solo se dispara cuando `/api/admin/*` devuelve
  HTML o una redirección. Queda para el Umbrel de verdad (con la app
  instalada desde el store).
- **Clave de PRIM real** y todo lo que viene después de tener clave: estado
  «Válida», «Comprobar otra vez», «Reemplazar», «Borrar» (con «borrar»
  tecleado en el diálogo), cuota con consumo, colector muestreando, avisos
  traducidos. La clave real ya se probó en la FASE 1 (test real) y estos
  caminos los cubren `tests/test_admin.py` y `tests/test_panel.py`; en el
  navegador solo se vieron los estados «sin clave» y «clave rechazada».
- **Ollama** en marcha (aquí no hay `OLLAMA_URL`): solo el estado «Sin
  configurar».
- **«Reintentar» en su camino de éxito.** Con el servidor caído el botón deja
  la franja (probado); al arrancarlo, el refresco automático de 15 s se
  adelantó dos veces a mi clic y el panel se recuperó solo. El botón llama al
  mismo `refresh()` que el de la cabecera, que sí se pulsó.
- **Clics a 1440 × 900 en el navegador integrado.** El panel de vista previa
  reduce la página para que quepa y los clics por referencia no llegan al
  elemento (lo comprobé: ninguna petición, foco en `body`); no es cosa del
  panel. A ese tamaño se probó por teclado (`form_input` + Enter) y el resto
  lo cubrió Chrome headless, que sí pulsa los botones de verdad.
- **Un iPhone escaneando el QR.** Simulado con `curl` y `fetch` con el mismo
  cuerpo que manda la app; el escaneo real está en `pruebas-iphone.md`.
- Renombrar con un nombre vacío o de más de 60 caracteres (el panel lo para
  antes de mandarlo, según el código; no se probó a mano).

## 6. Observaciones

- **Un QR nuevo anula el anterior, también desde otra pestaña.** El servidor
  lo hace en `new_pairing` y el panel lo enseña como «Código anulado» en el
  siguiente sondeo. Me pasó al generar un QR en el navegador mientras Chrome
  headless esperaba con otro en pantalla: la primera tanda de las capturas
  20-21 salió como «Código anulado» y hubo que repetirla sin tocar nada.
  Correcto y hasta útil (no puede haber dos QR vivos), pero conviene saberlo
  si el dueño abre el panel en dos sitios.
- El panel se recupera solo de un corte: el refresco cada 15 s vuelve a
  intentarlo y la franja desaparece sin tocar nada.
- En móvil la cabecera dice «Trajet» y debajo el nombre del servidor, que
  aquí también es «Trajet»; con un nombre propio («Casa», «Umbrel») no se
  repite. No se ha cambiado.
- Las respuestas de `/api/admin/*` no llevan la clave ni siquiera cuando se
  ha enviado una: el panel la lee del campo, lo vacía al momento y solo viaja
  en el cuerpo del `POST`.

## 7. Capturas y GIF

En [`capturas/panel-fase4/`](capturas/panel-fase4/README.md), con su README
(qué es cada una y cómo repetirlas): 84 PNG (`01`-`21` × móvil/PC ×
claro/oscuro, las de sección recortadas a la tarjeta) y 4 GIF en móvil (generar
el QR y la cuenta atrás; el paso a «Emparejado»; revocar un dispositivo;
pegar y rechazar la clave). Nuevas en esta sesión: `20-emparejar-ultimo-minuto-*`
y `21-emparejar-caducado-*`, más `plan_capturas.py` y `plan-caducado.json` para
regenerarlas.

## 8. Suite y commits

- `env -u PRIM_API_KEY .venv/Scripts/python -m pytest -p no:warnings` en
  `trajet-server`: **620 passed, 2 skipped** en 39 s (619 que había + el test
  nuevo; los 2 saltados son los de siempre, que necesitan `node` o red).
- `trajet-server` (rama `rewrite-v2`): commit `645eacc` — `panel.css`
  (casillas) y `tests/test_panel.py` (test nuevo). Las capturas 01-19 y los
  GIF de la primera sesión no necesitaron cambios en el panel.
- `trajet-ios` (rama `rewrite-v2`): el commit que trae este informe, con el
  README de las capturas, las capturas 20-21 y los planes (`plan_capturas.py`,
  `plan-caducado.json`). Las 01-19 y los GIF ya estaban en `9cac637`.
- Al terminar: `docker compose down -v` y borrada la imagen `trajet:dev`.
