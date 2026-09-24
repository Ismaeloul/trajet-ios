# Resumen para mañana (provisional)

> Escrito el 24-09-2026 por la mañana porque tu cuota de uso estaba al 31 %:
> la sesión se para **a mitad de la FASE 3**. Todo lo hecho está en git (o en
> disco, si una etapa se cortó a medias). Abajo, cómo retomar.

## Qué está hecho

| fase | estado | dónde |
|---|---|---|
| 0 · Código y análisis | ✅ | `docs/` (reglas, API, servidor, datos IDFM, arquitectura, contrato `openapi.yaml`) · Parada 1 |
| 1 · Servidor 0.4.0 | ✅ 619 tests, CI verde, 4 verificaciones | repo **privado** `Ismaeloul/trajet-server`, rama `rewrite-v2` · Parada 2 |
| 2 · Diseño «Cristal» + Live Activity y widgets | ✅ variante A «Billete» | `docs/diseno/`, `design-lab/b-cristal-v2/`, capturas en `design-lab/capturas/` · Parada 3 |
| 3 · App iOS | 🟡 a medias | ver abajo |
| 4 · Pruebas en navegador | ⬜ | (el panel ya tiene capturas en `docs/capturas/panel/`) |
| 5 · CI, docs y entrega | ⬜ | el CI de iOS ya hace las dos IPA y los tests |

### FASE 3, detalle

- ✅ Estructura (XcodeGen): apps **full** y **lite** con el mismo bundle id,
  extensión de widgets, tests; ATS sin `NSAllowsArbitraryLoads`; CI por modos
  (`compilar` / `completo` / `capturas`) que genera `Trajet-full.ipa` y
  `Trajet-lite.ipa` (verde).
- ✅ Núcleo (commit `44d354c`): modelos de la API v1, red con las dos
  direcciones y token en el Llavero, stores, caché, modo demo, 77 tests en
  verde. API interna en `docs/app-v2-api.md`.
- 🟡 Etapa B (vistas), escrita **sin compilar** por tres agentes a la vez:
  tablero y navegación (B1), mapa y modo trayecto (B2), widgets y Live
  Activity (B4). Si la sesión se cortó mientras trabajaban, lo que llegaron a
  escribir está en disco (sin commit o en un commit «[skip ci]»).
- ⬜ B3 (rutas, planificador, estadísticas, ajustes, emparejamiento), la
  integración con CI hasta verde, los tests de interfaz y capturas, y la
  verificación.

## Cómo retomar (en una sesión nueva de Claude Code en `Trajet v2`)

1. `git status` para ver lo que quedó sin commit de la etapa B; si hay
   ficheros nuevos en `Trajet/App/Views`, `Trajet/App/Trip`, `TrajetWidgets` o
   `Trajet/Shared/Activity|Components`, **consérvalos**: son el trabajo de B1,
   B2 y B4.
2. Si alguna de esas partes quedó a medias, relanzar solo esa con su encargo
   de `docs/encargos-fase3/02-vistas-B1-B2-B4.workflow.js`, diciéndole que
   primero haga inventario de lo que hay en disco y lo complete (no empezar
   de cero).
3. Lanzar B3 con `docs/encargos-fase3/03-rutas-ajustes-emparejamiento-B3.txt`
   y, a la vez o después, la integración con
   `docs/encargos-fase3/04-integracion-y-ci.txt` (compila en CI hasta verde).
4. Después: tests de interfaz y capturas automáticas (`scripts/ci-capturas.sh`
   está vacío), `docs/pruebas-iphone.md`, verificación independiente (tests,
   reglas, seguridad, funcionalidad) y Parada 4; FASE 4 (panel en el
   navegador con `docker compose`) y FASE 5.

Todas las decisiones están en `docs/decisiones.md`; el diario en
`docs/PROGRESO.md`; los informes de cada parada en `docs/PARADAS.md`.

## Lo que tienes que hacer tú

- **Rotar la clave de pruebas de PRIM** (salió en la salida de un comando de
  la sesión; no está en ningún fichero). Ver `docs/pendiente.md`.
- `trajet-ios` es **público** desde hoy (lo autorizaste); `trajet-server`
  sigue privado.
- La copia de `trajet.db` ya no hace falta: empiezas de cero.
- No publiques la 0.4.0 del servidor hasta tener la app del iPhone
  emparejada (la web desaparece). El store está preparado en un commit local
  de `umbrel-app-store` (rama `rewrite-v2`, sin push).

## Dónde están las IPA y las capturas

- IPA: GitHub → `Ismaeloul/trajet-ios` → Actions → la última ejecución «iOS»
  en verde → artefacto `Trajet-ipa-N` (`Trajet-full.ipa` y `Trajet-lite.ipa`).
  **Ojo:** la última IPA verde es aún el núcleo sin pantallas de verdad.
- Capturas: `design-lab/capturas/` (Live Activity y widgets, sistema) y
  `docs/capturas/panel/` (panel del servidor).
