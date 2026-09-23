# Referencias (septiembre 2026)

Lo que he mirado antes de dibujar y qué me llevo de cada cosa. Todo lo que no
sea esto lo he descartado por genérico (plantillas de dashboard, gradientes
«IA», tarjetas todas iguales).

## iOS 26 · Liquid Glass

- **Apple · Adopting Liquid Glass** —
  <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>
  El cristal es la **capa de controles**, nunca la de contenido. Tab bar,
  barras, hojas y botones flotantes lo adoptan solos; en vistas propias
  `glassEffect()` y `GlassEffectContainer` para que dos piezas se fundan.
  Hay que respetar *Reduce Transparency* con un sólido.
  → Me llevo: en la dirección **B (Cristal)** el mapa es el contenido y el
  cristal solo lleva controles; **los minutos y la vía van siempre en una
  cápsula opaca**, nunca sobre cristal (regla 11).
- **Donny Wals · Designing custom UI with Liquid Glass** —
  <https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/>
  Cristal encima de algo, no en filas de lista. `.tint()` con opacidad alta
  para colorear sin perder la refracción; `.interactive()` para el rebote
  al tocar; el morph entre piezas del mismo contenedor.
  → Me llevo: el «morph» del botón «Iniciar trayecto» que se convierte en
  la hoja inferior del mapa, y no poner cristal en las tarjetas de tramo.
- **learnui.design · iOS 26 design guidelines** —
  <https://www.learnui.design/blog/ios-design-guidelines-templates.html>
  Tab bar flotante en cápsula centrada; Large Title 34 pt / título compacto
  17 pt; cuerpo 17 pt, secundario 15 pt, tab bar 11 pt; anchos 390 / 402 /
  430-440 pt, diseñar primero para el estrecho.
  → Me llevo: la escala tipográfica base y la tab bar flotante en las
  direcciones que la usan (B y D). Los prototipos se prueban a 375, 390 y 430.
- **Wikipedia · Liquid Glass** — <https://en.wikipedia.org/wiki/Liquid_Glass>
  Contexto: primer rediseño grande desde iOS 7; el material responde al
  fondo, la luz y el movimiento.

## Live Activities y Dynamic Island

- **Swift Crafted · Live Activities iOS 26** —
  <https://swiftcrafted.dev/article/live-activities-dynamic-island-ios-26-swiftui-activitykit-guide>
  Compact leading/trailing ≈ 44 pt cada hueco, con `monospacedDigit()`;
  expandido ≈ 160 pt de alto en cuatro regiones (leading, trailing, center,
  bottom); `Text(timerInterval:)` para que la cuenta atrás corra sin push;
  botones con App Intents en iOS 26; payload 4 KB.
  → Me llevo: en la isla compacta solo caben **minutos** a un lado y
  **vía** al otro; el expandido lleva línea, destino, vía y cuenta atrás; el
  botón «Parar trayecto» puede ir en la Live Activity.
  Nota del README: con Apple ID gratuito no hay Live Activity; se diseña
  igual para que el sistema esté listo si algún día hay cuenta de pago.
- **CityTransit (App Store)** —
  <https://apps.apple.com/us/app/citytransit-bus-train-times/id1250234465>
  Alarmas de llegada con Live Activity en isla y pantalla de bloqueo.
  → Me llevo: la cuenta atrás como estado que cambia es lo que justifica
  la isla; no hay que meter más.

## Apps de transporte (referencia de patrones, no de estética)

- **Transit** — <https://transitapp.com/> ·
  Al abrir, sin tocar nada, ya ves lo que pasa cerca; GO sigue el trayecto.
  → Me llevo: **cero toques** para el caso de uso principal (la ruta que
  toca ya está en pantalla) y el modo trayecto como estado explícito que se
  apaga solo.
- **Bonjour RATP** — <https://apps.apple.com/us/app/bonjour-ratp/id507107090>
  e **Île-de-France Mobilités** (comparativa 2026:
  <https://worldwalk.app/en/blog/paris/paris-best-transport-app/>).
  Colores de línea oficiales por todas partes, «itinéraire recommandé»
  cuando hay obras. → Me llevo: el ojo del usuario ya conoce el amarillo de
  la J y el azul de la 13: **los distintivos son el único color saturado**.
  Lo que NO me llevo: la densidad de opciones y anuncios; Trajet es una
  app de una sola pregunta.
- **Ligne J (Wikipedia FR)** — <https://fr.wikipedia.org/wiki/Ligne_J_du_Transilien>
  Rama Paris-Saint-Lazare → Asnières-sur-Seine → Bois-Colombes → Colombes →
  Le Stade → Argenteuil → Sannois → Ermont-Eaubonne (grupo IV). Es el
  trazado que pinta el mapa; Pont-Cardinet y Clichy-Levallois son de la L,
  se dibujan como paradas «de paso» sin servicio J.

## Mapas

- **MapLibre GL JS** — <https://maplibre.org/maplibre-gl-js/docs/> ·
  versión fijada **6.11.1** en jsDelivr (comprobado el CSS en
  `https://cdn.jsdelivr.net/npm/maplibre-gl@6.11.1/dist/maplibre-gl.css`).
- **OpenFreeMap** — <https://openfreemap.org/quick_start/> y
  <https://github.com/hyperknot/openfreemap-styles> ·
  Sin clave ni registro. Estilos: `liberty`, `bright`, `positron` (claro
  sin POIs), `dark` y `fiord` (oscuros). Atribución OpenStreetMap +
  OpenMapTiles. → Me llevo: **positron** como base clara y **dark** como
  base oscura, y cada dirección los retiñe (agua, suelo, carreteras,
  etiquetas) para que el mapa hable el idioma de su diseño. En SwiftUI el
  equivalente es MapKit con `MapStyle` o MapLibre Native con el mismo JSON.

## Tendencias 2026 (con filtro)

- **Rajesh R Nair · UI trends 2026: bento, glass, what's shipping** —
  <https://rajeshrnair.com/blog/design/ui-ux/ui-design-trends-2026-bento-grids-glassmorphism.html>
  El bento sirve cuando cada celda responde a una pregunta distinta; el
  cristal cansa si está en todo. → Dirección **E (Bento)**: cada celda es
  una pregunta («¿corro?», «¿qué vía?», «¿qué falla?»), no decoración.
- **Midrocket · UI trends 2026** — <https://midrocket.com/en/guides/ui-design-trends-2026/>
  Tipografía expresiva a 80-120 px como elemento gráfico, no como texto.
  → Dirección **C (Cifra)**: el número de minutos es la pantalla.
- **Elinext · mobile UI/UX trends 2026** —
  <https://www.elinext.com/services/ui-ux-design/trends/key-mobile-app-ui-ux-design-trends/>
  Tipografía adaptativa y accesibilidad como norma. → Dynamic Type en todas
  las direcciones (escenario «letra grande»).

## Lo que sale del propio repo (manda sobre todo lo anterior)

- README «Lo que decide el diseño»: vía en el 17 % (7,7 min), metro/bus sin
  vía ni retraso, sin ocupación pero con longitud, «1h46», nunca borrar la
  pantalla, vía probable ≠ vía real por forma y palabra.
- `Design/Theme.swift`: los colores de línea son los únicos saturados; los
  minutos en cifras de ancho fijo; 44 pt de área táctil.
- `Design/Format.swift`: «En andén» ≠ «ya»; ritmo corro/ando/con calma
  (≤3 / ≤8 / >8 min).
- El icono actual (dos cuadrados unidos por un hilo, amarillo J y azul 13):
  es la semilla de la dirección **D (Hilo)**.
