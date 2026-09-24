# Paradas

Informe de cada «Parada» del encargo. En modo autónomo no me detengo: dejo
aquí lo hecho, los resultados de los tests y los problemas, y sigo.

---

## Parada 1 — FASE 0: código recuperado y análisis (24-09-2026, 01:15)

### Qué se hizo

- **Código del servidor recuperado** del NAS (`~/trajet`, SSH con clave, solo
  lectura, sin `.env` ni `data/`). Es el de producción: la `openapi.json` que
  sirve `192.168.1.188:7796` es idéntica a la que genera este código. Solo
  difiere la PWA de `app/static` (la del NAS es más nueva que la desplegada;
  da igual, la v2 la quita). Ver `docs/decisiones.md` D0.1.
- **Repo privado `Ismaeloul/trajet-server`** creado. Primer commit (`main`) =
  producción 0.3.0 tal cual; el trabajo sigue en `rewrite-v2`.
- **Análisis** (tres agentes en paralelo, revisado e integrado por mí):

  | documento | qué tiene |
  |---|---|
  | `docs/reglas.md` | **90 reglas**: R1–R13 del encargo, R14–R62 sacadas de la app, R63–R82 del servidor y R83–R90 nuevas de seguridad/cuota/migración de la v2. Cada una con su test propuesto |
  | `docs/inventario-funcional.md` | **82 funcionalidades** (F1–F82) de la app actual, para comprobar que la v2 no pierde ninguna |
  | `docs/ios-reutilizable.md` | qué se reutiliza, qué se rehace, 23 fallos de lógica (L1–L23) y problemas de compilación |
  | `docs/api.md` | los 16 endpoints de la 0.3.0 con todos sus campos, errores, llamadas a PRIM y efectos en la BD |
  | `docs/openapi-0.3.0.yaml` | la API de producción tal cual |
  | `docs/openapi.yaml` | **contrato congelado de la v2 (0.4.0)**: la 0.3.0 + `/api/v1` (iPhone) + `/api/admin` (panel). 41 rutas, 52 operaciones |
  | `docs/servidor.md` | cómo funciona hoy: PRIM, cuota, caché, tablero, recolector, previsión de vía, alternativas, Ollama, planificador, esquema SQLite, Docker; 70 decisiones con `fichero:línea`; 22 fallos de lógica y riesgos de seguridad |
  | `docs/servidor-v2.md` | estructura de la v2 e interfaces entre módulos |
  | `docs/datos-idfm.md` | datos abiertos de IDFM para el mapa (trazados, paradas, accesos, transbordos), licencias, pruebas reales sin clave y diseño del módulo de mapa |
  | `docs/arquitectura.md` | diagramas Mermaid: vista general, servidor, panel y seguridad, emparejamiento, app, modo trayecto, Live Activity y widgets, despliegue |

### Tests y validaciones

- `docs/openapi-0.3.0.yaml`: pasa `openapi-spec-validator` (3.1) y el
  conjunto (ruta, método, parámetros) coincide **exactamente** con la
  `openapi.json` de producción (16 operaciones, 17 parámetros). La app real,
  arrancada contra un PRIM simulado, dio **49 respuestas y las 49 cumplen**
  los esquemas estrictos.
- `docs/openapi.yaml` (0.4.0): pasa `openapi-spec-validator`; ningún esquema
  sin usar; todas las operaciones de `/api/v1` llevan token salvo `ping` y
  `pair`.
- Tests sin red que ya traía el repo del servidor (`tools/test_platform.py`,
  `test_routes.py`, `test_resilience.py`): **todo OK**.
- Datos de IDFM: 20 muestras reales descargadas sin clave (184 KB) en
  `trajet-server/tests/fixtures/idfm/`. Recorte de la J Saint-Lazare →
  Argenteuil medido: 9,77 km, 46 puntos a 2 m.
- CI de iOS probado en `rewrite-v2`: el runner tiene Xcode 26.6 (SDK iOS
  26.5) y simuladores iPhone SE (3.ª), 16 y 16 Pro Max. La app actual **no
  compila** (2 errores en vistas que se rehacen enteras).

### Hallazgos que cambian cosas

1. **La app de iOS nunca ha llegado a compilar** (Actions estaba bloqueado
   por facturación; ahora ya funciona). La v2 será su primera compilación.
2. **Seguridad 0.3.0**: la API no tiene ninguna autenticación y el proxy de
   Umbrel está con `PROXY_AUTH_ADD: "false"`. Cualquiera en la LAN o la
   tailnet puede leer y borrar rutas o agotar la cuota.
3. **La métrica de acierto de la vía está sesgada**: cuenta combinaciones y
   no trenes, y el recolector impide puntuar los trenes que ve primero. Se
   corrige en la FASE 1 (sin tocar los datos viejos).
4. **Si falla `general-message`, las líneas cortadas salen «normal»** sin
   decir nada. La v2 lo marca (`disruptions_ok: false`).
5. **El «dato viejo» salta en falso**: con el TTL adaptativo, una estación
   cuyo próximo tren está a 40 min hace que todo el tablero parezca viejo.
6. **No hay caminos a pie entre andenes en los datos abiertos**: solo tiempos
   mínimos de transbordo. El mapa enseñará el tiempo, no un trazado inventado.
7. El «17 %» y los «7,7 min» salen de dos horas de un domingo en dos
   estaciones. Se respetan como regla (lo pide el encargo), pero conviene
   saberlo.

### Problemas y pendientes

- **Copia de `trajet.db`**: la copia por SSH la denegó el control de
  permisos de la sesión. Los tests de migración usarán una BD sintética con
  el esquema exacto de la 0.3.0; el test contra la copia real se salta si no
  está. Comando para hacerla tú en `docs/pendiente.md`.
- No existe `scripts/publish.sh` en ningún sitio: se escribe nuevo en la
  FASE 1.

---

## Parada 2 — FASE 1: servidor (24-09-2026, 04:10)

Todo en `Ismaeloul/trajet-server`, rama `rewrite-v2`. Nada desplegado en el
Umbrel, nada publicado en `localhost:5000`, la app `ismaeloul-trajet` sin
tocar.

### Qué se hizo

| pieza | resumen |
|---|---|
| Compatibilidad | `/api/*` de la 0.3.0 con el mismo `openapi.json` que producción (test que lo compara) y los mismos errores 502. Ahora solo acepta conexiones del proxy de Umbrel |
| Migraciones | `PRAGMA user_version`; la 0.3.0 migra **sin perder rutas, historial ni andenes** (test con BD sintética del esquema exacto; el de la copia real espera a que la copies: `docs/pendiente.md`). Copia `.bak-v0` antes de migrar; si falla, modo degradado con el motivo en el panel |
| API v1 | las 21 operaciones del contrato; token obligatorio; nunca un tablero hueco (errores con código: sin clave, clave rechazada, sin cuota, PRIM caído); ETag/304 y gzip |
| Emparejamiento | QR de 5 min y un solo uso con las dos direcciones; token de 256 bits guardado como hash; comparación en tiempo constante; rate limit por IP y global; ver, renombrar y revocar dispositivos |
| Seguridad | panel y `/api` detrás del login de Umbrel **y** solo desde el proxy (otra app de la red Docker recibe 403); anti-CSRF; CSP estricta; logs sin clave, tokens, códigos ni query strings |
| Clave PRIM | se pega en el panel, se prueba contra PRIM antes de guardar, AES-256-GCM con clave derivada de `APP_SEED`, 0600; solo se ven los 4 últimos caracteres; reemplazo en caliente; prioridad panel > entorno y el panel dice de cuál sale |
| Cuota | por endpoint y día UTC, persistida, en el panel y en `/api/v1/health`; degradación suave (TTL ×2/×4, mínimo 10 min, refresco sugerido a la app) sin pantalla vacía |
| Mapa | `GET /api/v1/routes/{id}/map`: trazado recortado y simplificado (J Saint-Lazare → Argenteuil: 9 769 m, 52 puntos a 2 m, 12 a 20 m), paradas, andenes, vías, accesos, tiempo de transbordo; ~7 KB; pico de 3,4 MB |
| Panel | «Cristal», móvil y escritorio, claro/oscuro; QR, dispositivos, clave, cuota, Ollama, colector, salud, errores, ajustes del QR. Capturas en `docs/capturas/panel/` |
| Núcleo | acierto de la vía **por tren**; ruta que toca con franjas que cruzan medianoche; avisos con la fecha de París; SIRI con nulls no tumba el tablero; recolector sin SQLite en el bucle y quieto sin clave |
| Empaquetado | Dockerfile multi-stage, usuario 1000, healthcheck sin curl, un worker; imagen 260 MB, ~65 MB de RSS en reposo; `scripts/publish.sh` (se lanza en el NAS; probado contra un registro efímero en este PC); CI en GitHub; README |
| Store | `umbrel-app-store/ismaeloul-trajet` 0.4.0 en una rama **local** con el push bloqueado (whitelist `/api/v1/*`, `APP_SEED`, sin IPs; notas en español con el aviso de emparejar antes de actualizar) |

### Tests

- **618 tests en verde** (2 saltados: permisos POSIX en Windows —en CI sí
  corren— y la migración contra la copia real, que no existe).
- **Pruebas contra la API real** (aparte, `scripts/test-real.sh`, tope de
  800 llamadas por endpoint y día): 9 en verde con unas 37 llamadas en total,
  incluida la zona de la clave del panel de principio a fin (pegar una falsa
  → rechazada; la real → validada y guardada; reemplazar; comprobar; borrar).
  Las respuestas reales, recortadas y sin la clave, son nuevos casos del mock.
- CI del servidor en GitHub: ruff, contrato, pytest, construcción y arranque
  de la imagen.

### Verificación independiente

Tres verificadores (tests y reglas; seguridad con peticiones reales; funcionalidad
y contrato frente al encargo). Encontraron **2 fallos altos** —el mismo, visto por
dos: la API 0.3.0 no comprobaba de dónde venía la conexión— y **~14 medios o
bajos** (ReDoS en el tachado de logs, un test que fallaba los sábados, 500 con
nulls en rutas, tablero v1 que se daba por hueco con avisos, escritura de
errores en el bucle de eventos, sin modo degradado si falla la migración…).
**Todos corregidos**, cada uno con un test que falla antes y pasa después.
Aceptado sin arreglar: un tercero en la red podría gastar el cupo de intentos
del emparejamiento (molestia de 5 min, no roba nada).

### Problemas y pendientes

- **Incidente**: la clave de pruebas salió en la salida de un
  `docker compose config` (solo en la transcripción; en ningún fichero).
  **Rótala en PRIM.** Detalle en `docs/pendiente.md`.
- La copia real de `trajet.db` sigue pendiente (permiso denegado en la sesión).
- Publicar la 0.4.0 **después** de tener la app del iPhone emparejada: con
  la 0.4.0 la web desaparece.

### Re-verificación

Un cuarto verificador reprodujo los 24 hallazgos contra el código corregido:
**18 arreglados, 2 parciales y 4 que siguen** —los 4 aceptados o fuera de mi
alcance: SEC-3 (depende de que umbreld sobrescriba `X-Forwarded-Host`, como
dice su código fuente), SEC-4 (compromiso aceptado) y la migración contra la
copia real (x2, espera a tu copia). Los 2 parciales (avisos del README y una
frase de `servidor-v2.md`) y un fallo viejo que encontró de paso (un id mayor
que 2^63−1 daba 500) quedaron arreglados después. **Sin regresiones.** Suite:
**619 en verde**; ruff limpio; CI del servidor en verde.


---

## Parada 3 — FASE 2: sistema «Cristal» y rediseño de la Live Activity y los widgets (24-09-2026)

### Qué se hizo

- **2A · Sistema de diseño** (`docs/diseno/sistema.md`): tokens en OKLCH y
  sRGB (claro, oscuro y «Aumentar contraste»), tipografía y escalas, espaciado
  y radios concéntricos, cristal y materiales (iOS 26 con alternativa y
  opaco con «Reducir transparencia»), componentes con todos sus estados,
  catálogo de animaciones traducido a SwiftUI. Fuente única de tokens:
  `design-lab/tools/tokens.mjs` → `design-lab/tokens.json` y la capa
  `Trajet/Design/` (Tokens, Typography, Metrics, Motion, Glass, LineColor).
  Muestrario en `design-lab/sistema/`.
- **Contraste medido**: 147/147 parejas texto/fondo AA y los 59 colores de
  línea oficiales de IDFM con el distintivo a ≥ 4,55:1. Consecuencia visible:
  RER A/B/D, Transilien K/N/V, T6, T9, T14 llevan el código en negro.
- **Ajustes de B al pasarlo a nativo** (`docs/diseno/ajustes-b.md`, 35): las
  tarjetas de tramo pasan a opacas (en B los minutos quedaban sobre cristal),
  colores de texto nuevos para AA, amarillo **solo** para la vía confirmada.
- **2B · Referencias y límites** (`docs/diseno/referencias-la-widgets.md`):
  ~30 referencias con enlace y los tamaños reales de iOS (Live Activity,
  Dynamic Island, widgets de inicio y de bloqueo por dispositivo).
- **2B · Tres variantes** en `design-lab/b-cristal-v2/` (A «Billete», B
  «Tablero», C «Fases»), a tamaño real, conectadas a los escenarios. Un
  **revisor independiente** las puntuó sin piedad: **A 7,6 · B 6,1 · C 5,9**.
- **Elegida A «Billete»** y corregidos los 23 puntos del revisor (4 graves).
  Por qué y cómo resuelve uno por uno los problemas del encargo:
  `docs/diseno/decisiones-la-widgets.md`. Especificación para la FASE 3
  (tamaños, estados, `ActivityAttributes`, `TimelineProvider`, App Intent de
  «Parar», deep links): `docs/diseno/sistema.md` §12.

### Capturas y GIF

`design-lab/capturas/la-widgets/`: la elegida en `A/` (≈600), las otras dos
en `B/` y `C/`, `comparar/` (las tres lado a lado por escenario) y GIF de la
cuenta atrás, la vía que aparece y el morph de la isla. **Cero errores de
consola** en todas las pasadas. Muestrario del sistema en
`design-lab/capturas/sistema/`.

### Problemas y pendientes

- Swift de `Trajet/Design/` escrito sin poder compilar (no hay Mac): se
  compila en la FASE 3; cinco firmas de iOS 26 marcadas `TODO-COMPILAR` con
  su alternativa segura.
- Tamaños de iPhone 16 Pro Max y de la Live Activity del SE: estimados (Apple
  no los publica); se miden en el simulador en la FASE 3.
- A comprobar en el simulador: las cadenas exactas de los textos de fecha del
  sistema en español, si el «calado» se pinta en la extensión y cuántas
  actualizaciones se pierden con el iPhone bloqueado.
- La sesión se cortó una vez por el límite de uso a mitad de la FASE 2; se
  retomó sin perder nada (lo hecho estaba en disco).
