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
- [ ] FASE 1 — Servidor
  - [x] Base: migraciones, API separada (0.3.0/v1/admin), errores, ETag, tests
  - [x] Seguridad + API v1 · PRIM/cuota/clave cifrada · mapa IDFM (272 tests en verde, 8 reales)
  - [ ] Panel · empaquetado (Docker, publish.sh, CI, store 0.4.0) · correcciones del núcleo
  - [ ] Verificación independiente y Parada 2
- [ ] FASE 2 — Sistema de diseño «Cristal» + Live Activity y widgets
- [ ] FASE 3 — App iOS
- [ ] FASE 4 — Pruebas en navegador
- [ ] FASE 5 — CI, documentación y entrega

## Bitácora

- 2026-09-24 00:20 — Arranque. Código del servidor encontrado en el NAS; la API
  coincide con la desplegada. Repo `trajet-server` creado.
- 2026-09-24 01:15 — FASE 0 cerrada. Contrato 0.4.0 congelado. Empieza la FASE 1.
- 2026-09-24 02:10 — FASE 1 etapa B integrada (commit 95c05d4 en trajet-server). Etapa C en marcha.
