# Decisiones tomadas en modo autónomo

Cada entrada: qué decidí, qué alternativas había y por qué. Las más recientes
al final de cada sección.

---

## FASE 0

### D0.1 · De dónde sale el código del servidor
- **Decisión**: el código de producción es el de `~/trajet` en el NAS (leído
  por SSH con la clave que ya tenía este PC, sin sudo ni Docker y sin tocar
  nada). Se copió sin `.env` ni `data/`.
- **Por qué es el bueno**: el servidor que responde en `192.168.1.188:7796` es
  el stack de `docker compose` de `~/trajet`, no la app `ismaeloul-trajet` del
  store (no está instalada: no existe `~/umbrel/app-data/ismaeloul-trajet`).
  Para comprobarlo sin Docker comparé el `openapi.json` que sirve producción
  con el que genera este código: **idénticos** (rutas, métodos y parámetros).
- **Diferencia encontrada**: la PWA de `app/static` del NAS es **más nueva**
  que la de la imagen desplegada (la desplegada es la oscura de cristal; la
  del NAS, la «hoja clara» del 5 de septiembre, que se subió pero no se llegó
  a reconstruir). No importa: la v2 elimina la PWA.
- **No existe `scripts/publish.sh`** en ningún sitio (ni en este PC ni en el
  NAS). Lo que había es `pasar-al-store.sh`. El `publish.sh` se escribe nuevo
  en la FASE 1.
- **Alternativas descartadas**: `docker cp` desde el contenedor (el usuario
  `umbrel` no está en el grupo `docker` y `sudo` pide contraseña).

### D0.2 · Dónde vive cada repo en local
- `Trajet v2/` es `trajet-ios` (rama `rewrite-v2`, creada desde `design-lab`).
- `Trajet v2/trajet-server/` es el repo `trajet-server`, con su propio `.git`,
  ignorado por `trajet-ios`. Así el encargo funciona tal cual está escrito
  (`./trajet-server`, `trajet-server/.env`) y cada repo va por su lado.
- `Trajet v2/umbrel-app-store/` será un **clon nuevo** del store (ignorado),
  para preparar la 0.4.0 en una rama local sin tocar los otros clones que
  tienes en el PC (alguno tiene cambios sin commitear).
- La documentación de todo el proyecto vive en `trajet-ios/docs/`.

### D0.3 · Primer commit de `trajet-server` en `main`
- El encargo pide que el primer commit sea el estado de producción. Un repo
  nuevo necesita una rama por defecto, así que ese único commit va a `main`
  (junto con un `.gitignore` que protege `.env` y `data/`). **Todo lo demás va
  a `rewrite-v2`**; a `main` no se vuelve a escribir.

### D0.4 · Copia de `trajet.db`
- La copia por SSH (solo lectura) la **denegó** el control de permisos de la
  sesión. No la he forzado. Los tests de migración usan una BD sintética con
  el esquema exacto de la 0.3.0; el test contra la copia real se salta si no
  está. Detalle y comando para hacerla tú en `docs/pendiente.md`.

### D0.5 · CI de iOS: qué hay en el runner
- Probado con un push a `rewrite-v2` (GitHub Actions ya funciona otra vez):
  `macos-latest` = macOS 26.6 con **Xcode 26.6** (SDK iOS **26.5**) y
  simuladores iOS 26.2, 26.4 y 26.5; modelos iPhone SE (3.ª gen.), iPhone 16,
  16 Pro Max, 17… Compila en ~30 s.
- La app actual **no compila** (2 errores en `AlternativesSheet.swift:152` y
  `DepartureChip.swift:64`). No se arreglan: esas vistas se rehacen enteras.

### D0.6 · Login de Umbrel y API del iPhone
- Umbrel (umbreld, módulo `app-gateway`) deja fuera del login las rutas de
  `PROXY_AUTH_WHITELIST`. Reglas de coincidencia (leídas del código fuente de
  `app-gateway.ts`): `"/api/v1/*"` casa con todo lo que empieza por
  `/api/v1/`; la lista negra gana a la blanca; sin sesión, lo no permitido se
  **redirige** (302) al login de Umbrel. El proxy **quita sus cookies** antes
  de pasar la petición y pone `X-Forwarded-For` con la IP real.
- Solución: `PROXY_AUTH_ADD: "true"` + `PROXY_AUTH_WHITELIST: "/api/v1/*"`.
  Panel y API antigua quedan detrás del login; la API del iPhone queda fuera
  pero **exige token** en el propio servidor. Detalle en la FASE 1.
- En tu NAS corre **umbreld 2.0**, con el `app-gateway` dentro del propio
  umbreld (no un contenedor `app_proxy` aparte): las peticiones llegan al
  contenedor desde la puerta de enlace de la red Docker de Umbrel
  (`10.21.0.1`). Eso permite que el panel compruebe, además, que la conexión
  viene del proxy y no de otra app de la red compartida
  (`TRAJET_ADMIN_PEERS=auto`).
- Umbrel da a cada app un secreto estable `APP_SEED` (derivado de la semilla
  del Umbrel); es el que se usará para cifrar la clave de PRIM en reposo.
