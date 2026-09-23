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

- [ ] FASE 0 — Recuperar el código y analizar
  - [x] 0.1 Código del servidor recuperado del NAS (`~/trajet`, solo lectura) → `trajet-server` (privado), commit inicial = producción 0.3.0
  - [ ] 0.1 Copia de `trajet.db` → **bloqueada** (ver `docs/pendiente.md`)
  - [ ] 0.2 Análisis (`reglas.md`, `api.md`, `openapi.yaml`, `servidor.md`, `datos-idfm.md`, `arquitectura.md`)
- [ ] FASE 1 — Servidor
- [ ] FASE 2 — Sistema de diseño «Cristal» + Live Activity y widgets
- [ ] FASE 3 — App iOS
- [ ] FASE 4 — Pruebas en navegador
- [ ] FASE 5 — CI, documentación y entrega

## Bitácora

- 2026-09-24 00:20 — Arranque. Código del servidor encontrado en el NAS; la API
  coincide con la desplegada. Repo `trajet-server` creado.
