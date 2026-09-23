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
