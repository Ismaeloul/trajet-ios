# Capturas del panel · FASE 4

Capturas y GIF del panel de administración de Trajet (`trajet-server/app/panel`,
dirección «Cristal») **probado de verdad** en un servidor levantado con
`docker compose` en este PC (BD vacía, sin clave PRIM, `TRAJET_ADMIN_PEERS=auto`),
el 24-09-2026. El informe completo está en [`../../fase4-panel.md`](../../fase4-panel.md).

Se hicieron con `design-lab/tools/capturar.mjs` (Chrome headless por CDP) a partir
de un plan que recorre el panel como un usuario: generar el QR, anularlo, generar
otro y **canjearlo como lo haría el iPhone** (`POST /api/v1/pair` desde la propia
página), renombrar, revocar, pegar una clave corta y una clave falsa, etc. Nada
está simulado en el HTML: cada estado sale del servidor real.

## Nombres

`NN-que-es-<tamaño>-<modo>.png`

| trozo | valores |
|---|---|
| `<tamaño>` | `movil` = 390 × 844 (iPhone, a 2x: 780 × 1688 px) · `pc` = 1440 × 900 (a 2x: 2880 × 1800 px) |
| `<modo>` | `claro` · `oscuro` (`prefers-color-scheme`) |

Las de una sección van **recortadas a la tarjeta**; las de pantalla entera
(`01`, `07`, `08`, `19`) enseñan el panel completo a ese tamaño. Cada número
existe en las cuatro combinaciones (76 PNG en total).

## Qué es cada una

| n.º | fichero | qué se ve |
|---|---|---|
| 01 | `01-panel-*` | El panel recién cargado sin clave de PRIM: cabecera con la píldora «Revisar», los cuatro resúmenes (Clave PRIM «Sin clave», Cuota 0 %, iPhones, En marcha) y los avisos (error por falta de clave, info por falta de `APP_SEED`). En PC, las tres columnas. |
| 02 | `02-emparejar-reposo-*` | Tarjeta «Emparejar un iPhone» en reposo, con el botón grande. |
| 03 | `03-emparejar-qr-*` | QR generado: el código (`ABCD-EFGH`), la cuenta atrás de 5 min con su barra, «Esperando al iPhone…» y las direcciones que lleva el QR (casa y Tailscale, las guardadas en Ajustes). |
| 04 | `04-emparejar-anulado-*` | Tras pulsar «Anular»: «Código anulado» y «Generar otro». |
| 05 | `05-emparejar-emparejado-*` | El iPhone (simulado con `POST /api/v1/pair` con el código de la pantalla) ha canjeado el código: «Emparejado: iPhone de Isma» y «Emparejar otro». |
| 06 | `06-dispositivos-*` | Tarjeta «Dispositivos» con el iPhone recién emparejado: modelo, versión de la app, último uso, IP, y los botones Renombrar y Revocar. |
| 07 | `07-dispositivos-revocar-dialogo-*` | Pantalla entera con el diálogo modal «¿Revocar «iPhone de Isma»?» y el fondo desenfocado. |
| 08 | `08-dispositivos-revocado-*` | Pantalla entera tras confirmar: la lista vuelve a «Ningún iPhone emparejado todavía» y sale el aviso flotante «… ya no tiene acceso». |
| 09 | `09-clave-sin-clave-*` | Tarjeta «Clave de PRIM» sin clave: recuadro rojo con el enlace al portal y el formulario para pegarla. |
| 10 | `10-clave-corta-*` | Se ha enviado `corta`: el propio panel lo para («La clave tiene que tener de 8 a 256 caracteres.») sin llamar al servidor, y el campo queda vacío. |
| 11 | `11-clave-rechazada-*` | Se ha enviado la clave inventada `CLAVEFALSA1234567890`: el servidor la prueba contra PRIM y responde 422; el panel dice «No se ha guardado: PRIM no reconoce la clave (401)» con el detalle de las tres APIs. El campo está vacío (la clave nunca se queda en la página). |
| 12 | `12-cuota-*` | Tarjeta «Cuota de PRIM»: los tres medidores (0 / 1000), la hora del reinicio (medianoche UTC en hora local) y el historial de 7 días. |
| 13 | `13-salud-*` | «Salud del servidor»: versión, tiempo en marcha, hora en París, memoria del contenedor (RSS de 384 MB), base de datos (tamaño y esquema), contenido y datos del mapa. |
| 14 | `14-traduccion-ollama-*` | «Traducción de avisos» sin `OLLAMA_URL`: «Sin configurar» y la explicación de que es opcional. |
| 15 | `15-andenes-*` | «Andenes y previsión de vía»: colector en marcha, acierto sin previsiones aún, última pasada y ritmo («sin clave de PRIM»). |
| 16 | `16-errores-*` | «Errores recientes» desplegado: el aviso `trajet.prim` de que no hay clave. |
| 17 | `17-ajustes-*` | «Ajustes del QR» con el nombre y las dos direcciones guardadas. |
| 18 | `18-ajustes-error-*` | Se intenta guardar `http://192.168.1.10:7796/api`: el panel lo rechaza antes de mandarlo («Solo host y puerto, sin ruta…») y marca el campo. |
| 19 | `19-sin-conexion-*` | El servidor no responde (se ha cortado `fetch`): franja «No hay conexión con el servidor. Se enseña lo último que se supo.» con «Reintentar», píldora «Sin conexión» y los datos anteriores intactos. |

## GIF

Grabados en móvil (390 × 844, a 1x, modo claro, con las animaciones activas).
Chrome headless hace los fotogramas y Pillow los monta (los fotogramas idénticos
se funden y su tiempo se suma, por eso tienen menos «frames» de los capturados).

| fichero | qué se ve |
|---|---|
| `gif-1-generar-qr-cuenta-atras.gif` | Se pulsa «Emparejar un iPhone»: aparece el QR con su animación, el código y la cuenta atrás corriendo desde 5:00 (unos 12 s). Recortado a la tarjeta. |
| `gif-2-paso-a-emparejado.gif` | Con el QR en pantalla, el iPhone (simulado) canjea el código; en el siguiente sondeo (2 s) la tarjeta pasa a «Emparejado: iPhone de Isma» y el dispositivo aparece en la lista de abajo. Recortado a la tarjeta y la lista. |
| `gif-3-revocar-dispositivo.gif` | Se pulsa «Revocar»: diálogo de confirmación, «Revocar», la lista se vacía y sale el aviso flotante. Pantalla entera. |
| `gif-4-clave-rechazada.gif` | Se pega la clave falsa poco a poco (puntos en el campo de contraseña), se pulsa «Probar y guardar» y PRIM la rechaza: el campo se vacía y sale el motivo con las tres APIs. Pantalla entera. |

## Cómo se repiten

```powershell
cd trajet-server
env -u PRIM_API_KEY docker compose up --build -d      # panel en http://127.0.0.1:7796
# guarda antes dos direcciones en «Ajustes del QR» (el plan da por hecho que están)
node ..\design-lab\tools\capturar.mjs plan.json     # el plan se genera con el script de la FASE 4 (ver fase4-panel.md)
env -u PRIM_API_KEY docker compose down -v
```

Las capturas de la FASE 1 (maquetas del panel antes de probarlo) siguen en
[`../panel/`](../panel/).
