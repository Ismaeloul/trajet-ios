# Progreso de Trajet v2

Estado vivo del trabajo en modo autónomo. Si la sesión se corta, se retoma
desde aquí.

## Dónde está cada cosa

| pieza | carpeta local | repo / rama |
|---|---|---|
| App iOS + docs + laboratorio de diseño | `Trajet v2/` | `Ismaeloul/trajet-ios` · `rewrite-v2` |
| Servidor (API + panel) | `Trajet v2/trajet-server/` | `Ismaeloul/trajet-server` (privado) · `rewrite-v2` |
| Store de Umbrel (solo local, sin push) | `Trajet v2/umbrel-app-store/` | `Ismaeloul/umbrel-app-store` · rama local `rewrite-v2` |

## Fases

- [x] FASE 0 — Recuperar el código y analizar (Parada 1 en `docs/PARADAS.md`)
  - [x] 0.1 Código del servidor recuperado del NAS (`~/trajet`, solo lectura) → `trajet-server` (privado), commit inicial = producción 0.3.0
  - [ ] 0.1 Copia de `trajet.db` → **bloqueada** (ver `docs/pendiente.md`)
  - [x] 0.2 Análisis (`reglas.md`, `api.md`, `openapi.yaml`, `servidor.md`, `datos-idfm.md`, `arquitectura.md`)
  - [x] Contrato v2 congelado: `docs/openapi.yaml` 0.4.0
- [x] FASE 1 — Servidor (Parada 2 en `docs/PARADAS.md`)
  - [x] Base: migraciones, API separada (0.3.0/v1/admin), errores, ETag, tests
  - [x] Seguridad + API v1 · PRIM/cuota/clave cifrada · mapa IDFM (272 tests en verde, 8 reales)
  - [x] Panel · empaquetado (Docker, publish.sh, CI, store 0.4.0) · correcciones del núcleo
  - [x] Verificación independiente (3 + re-verificación) y Parada 2
- [x] FASE 2 — Sistema de diseño «Cristal» + Live Activity y widgets (Parada 3; elegida la variante A «Billete»)
- [ ] FASE 3 — App iOS (a medias: ver `docs/RESUMEN-MAÑANA.md` «Cómo retomar»)
  - [x] Estructura full/lite/widgets/tests + CI con las dos IPA
  - [x] Núcleo (modelos v1, red, stores, caché, demo, 77 tests)
  - [ ] Etapa B: tablero (B1), mapa y trayecto (B2), widgets y Live Activity (B4) — escritas sin compilar
  - [ ] B3 rutas/planificador/estadísticas/ajustes/emparejamiento · integración en CI · tests de interfaz y capturas · verificación
- [x] FASE 4 — Pruebas en navegador (panel; `docs/fase4-panel.md`)
- [ ] FASE 5 — CI, documentación y entrega

## Bitácora

- 2026-09-24 00:20 — Arranque. Código del servidor encontrado en el NAS; la API
  coincide con la desplegada. Repo `trajet-server` creado.
- 2026-09-24 01:15 — FASE 0 cerrada. Contrato 0.4.0 congelado. Empieza la FASE 1.
- 2026-09-24 02:10 — FASE 1 etapa B integrada (commit 95c05d4 en trajet-server). Etapa C en marcha.
- 2026-09-24 04:30 — FASE 1 cerrada (619 tests, CI verde). Empieza la FASE 2 (diseño).
- 2026-09-24 — FASE 2 cerrada (corte por límite de uso a mitad, retomada). Empieza la FASE 3 (app iOS).
- 2026-09-24 ~08:00 — Cuota de uso al 31 %: se deja todo listo para retomar (encargos en `docs/encargos-fase3/`).
