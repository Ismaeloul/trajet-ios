# Laboratorio de diseño de Trajet

Cinco prototipos interactivos para elegir el diseño de la app antes de
reescribirla. Todo es HTML, CSS y JS sin compilar; los datos son los de
`Trajet/Resources/PreviewData.swift` pasados a JavaScript.

```
design-lab/
  index.html        la galería: las 5 a la vez, escenarios comunes, «comparar la misma pantalla»
  a-anden/          A · Andén    señalética de estación
  b-cristal/        B · Cristal  Liquid Glass sobre el mapa
  c-cifra/          C · Cifra    tipografía gigante, casi monocromo
  d-hilo/           D · Hilo     la línea del trayecto como hilo gráfico
  e-bento/          E · Bento    rejilla densa de celdas
  shared/           datos (data.js), núcleo (core.js), mapa (map.js), base.css, servidor.js
  capturas/         capturas y GIFs de la revisión
  referencias.md    lo que he mirado antes de diseñar
  revision.md       la autocrítica contra las reglas del brief
  servir.ps1        levanta el servidor en la red local
```

## Verlo en el PC

```powershell
cd design-lab
.\servir.ps1
```

Abre <http://localhost:7797/> (la galería) o `http://localhost:7797/a-anden/`
para una dirección sola con su panel de escenarios al lado. Hace falta
**Node.js**; no hay ninguna otra dependencia. Las librerías (MapLibre GL JS
5.24.0) y las fuentes vienen de CDN, así que con conexión el mapa es de
verdad (teselas de OpenFreeMap, sin clave) y sin conexión sale el mismo
trazado en SVG.

## Verlo en el iPhone

1. PC e iPhone en la **misma Wi-Fi** (o los dos en la tailnet).
2. `.\servir.ps1` enseña las URLs con la IP de este PC; en esta casa la Wi-Fi
   del PC es `192.168.1.28` (la Ethernet, `192.168.1.156`) y la tailnet
   `100.109.137.119`.
3. En Safari del iPhone abre, por ejemplo:
   `http://192.168.1.28:7797/a-anden/?full=1`
   (el `?full=1` quita el marco y el panel: la app ocupa la pantalla real,
   con sus zonas seguras). El botón redondo discreto abajo a la derecha abre
   los escenarios.
4. Para que no salga la barra de Safari: **Compartir → Añadir a pantalla de
   inicio**. Se abre a pantalla completa como una app.

Las cinco, en modo móvil:

| | URL |
|---|---|
| A · Andén | `http://192.168.1.28:7797/a-anden/?full=1` |
| B · Cristal | `http://192.168.1.28:7797/b-cristal/?full=1` |
| C · Cifra | `http://192.168.1.28:7797/c-cifra/?full=1` |
| D · Hilo | `http://192.168.1.28:7797/d-hilo/?full=1` |
| E · Bento | `http://192.168.1.28:7797/e-bento/?full=1` |

Los escenarios y el reloj se guardan en el navegador (localStorage) y se
comparten entre pestañas del mismo navegador. El iPhone tiene los suyos.

### Si el firewall de Windows lo bloquea

La primera vez que `node` escucha en la red, Windows suele preguntar:
marca **solo «Redes privadas»**. Si no preguntó y desde el iPhone no carga,
abre una PowerShell **como administrador** y permite solo el puerto y solo
en el perfil privado:

```powershell
New-NetFirewallRule -DisplayName "Trajet design-lab" -Direction Inbound -Protocol TCP -LocalPort 7797 -Profile Private -Action Allow
```

Para quitarla después:

```powershell
Remove-NetFirewallRule -DisplayName "Trajet design-lab"
```

Comprueba también que la Wi-Fi de casa está como red **privada** en
Configuración → Red e Internet → Wi-Fi → propiedades de la red.

## Qué se puede tocar

- **Escenarios** (panel a la derecha, o el botón redondo en el móvil): vía
  real / probable / sin vía y el botón «que aparezca la vía ahora»; bus a
  1h46; línea 14 cortada; aviso en francés «traduciendo» → traducido; sin
  conexión (tablero antiguo con su antigüedad); tren parado en el andén;
  tramo vacío; modo trayecto; claro / oscuro; reducir movimiento; letra
  grande (Dynamic Type).
- **Reloj**: arranca a las 12:50 (la hora de los datos) y corre de verdad.
  ×10 o ×60 para ver cambiar los minutos sin esperar; «Reiniciar» lo vuelve
  a las 12:50.
- **Pantalla**: emparejamiento, tablero, mapa / modo trayecto, alternativas,
  rutas, editor de ruta, planificador, estadísticas, ajustes, Live Activity,
  widgets y panel del servidor (en el móvil y, con el botón del panel, en una
  ventana de escritorio 1440×900).
- **Tamaño** del iPhone: 390×844, 430×932 y 375×667.

## Cómo está hecho

- `shared/core.js` es el banco de pruebas: formato («1h46», «hace 4 min»),
  escenarios, reloj simulado, construcción del tablero desde los datos,
  enrutado, marco del iPhone y panel. **Cada dirección solo pinta**:
  `render(ctx)` devuelve el HTML de la pantalla y el núcleo actualiza
  minutos, cuentas atrás y antigüedad cada segundo sobre los atributos
  `data-dep-min`, `data-countdown`, `data-age`…
- Las animaciones son solo `transform` y `opacity` (más `filter: blur` en
  las cifras de la C, que en SwiftUI es `.blur`), y todas tienen su
  equivalente nativo: springs, `matchedGeometryEffect`, `contentTransition
  (.numericText())`, `glassEffect`, `trim` de un `Path` para el hilo.
- Nada de secretos: el QR y las direcciones son de mentira.
